extends Node
## Scene-side orchestrator for the roguelite run loop. Sits in main.tscn next
## to the untouched GameManager and takes over the game flow at runtime:
##  - disconnects GameManager's lives/respawn and win handlers (its navmesh
##    bake and the first room's enemy spawn keep working as before),
##  - adopts the room-1 enemies, then spawns scaled enemies for later rooms,
##  - drives the room-cleared freeze, upgrade selection and room reset,
##  - handles permadeath (freeze world, RunHUD shows the run summary).

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const PICKUP_SCENE := preload("res://scenes/pickups/pickup.tscn")
const PORTAL_SHADER := preload("res://shaders/matrix_spiral_portal.gdshader")

const TRANSITION_FREEZE_SECONDS := 1.0
const ROOM_BANNER_SECONDS := 1.6
const DESCENT_BEAT_SECONDS := 1.2  # extra beat when a run crosses into a new layer
const HEALTH_DROP_AMOUNT := 25.0
const SPAWN_JITTER := 1.5  # spread between enemies sharing a fallback marker

# High-ground reward (Tiers verticality V3): a bonus pickup the builder places on
# each raised platform cap. Enemies stay grounded, so it's a player-only payoff for
# climbing. Alternates the two premium pickups and does not respawn (one grab/room).
const HIGH_REWARD_AMOUNT := 40.0
const HIGH_REWARD_RESPAWN := 9999.0

# Elite (milestone room boss): factors stack on top of the room multiplier.
const ELITE_HEALTH_FACTOR := 5.0
const ELITE_DAMAGE_FACTOR := 2.0
const ELITE_SPEED_FACTOR := 1.15
const ELITE_DROP_COUNT := 2  # guaranteed health packs on elite death

# Rusher (aggressive archetype): a fragile glass cannon that charges in and
# sprays at point-blank. Factors stack on top of the room multiplier.
const RUSHER_HEALTH_FACTOR := 0.7
const RUSHER_DAMAGE_FACTOR := 0.75  # per pellet; it fires a fast spray
const RUSHER_SPEED_FACTOR := 1.6
const RUSHER_ATTACK_RANGE := 6.0    # fights right up in the player's face
const RUSHER_BURST := 4             # pellets per spray

# Sniper (long-range archetype): holds back and lands one big telegraphed shot.
const SNIPER_HEALTH_FACTOR := 0.85
const SNIPER_DAMAGE_FACTOR := 3.0   # one accurate shot hits hard
const SNIPER_SPEED_FACTOR := 0.9    # deliberate, not a runner
const SNIPER_SIGHT_RANGE := 60.0
const SNIPER_ATTACK_RANGE := 40.0

# Grenadier (area-denial archetype): keeps distance and lobs arcing grenades.
const GRENADIER_HEALTH_FACTOR := 1.15  # a bit tankier; a priority backline target
const GRENADIER_DAMAGE_FACTOR := 3.0   # AoE blast off the base shot damage
const GRENADIER_ATTACK_RANGE := 20.0   # mid range -- wants room to lob
const GRENADIER_BLAST_RADIUS := 4.5

var _pickup_configs: Array[Dictionary] = []

var _active_gate: ExitGate = null
var _fragment_reader: FragmentReader = null
var _dev_jump_active := false  # re-entrancy guard for the DevTools room-jump

@onready var _main: Node3D = get_parent()
@onready var _player: Player = _main.get_node("Player")
@onready var _player_spawn: Marker3D = _main.get_node("PlayerSpawn")
@onready var _pickups_root: Node3D = _main.get_node("Pickups")
@onready var _hud: CanvasLayer = _main.get_node("HUD")
@onready var _run_hud: CanvasLayer = _main.get_node("RunHUD")
@onready var _upgrades: PlayerUpgrades = _player.get_node("PlayerUpgrades")
@onready var _room_builder: Node = _main.get_node("RoomBuilder")
@onready var _nav_region: NavigationRegion3D = _main.get_node("NavRegion")


func _ready() -> void:
	# Keep working while the tree is paused during room transitions.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_pickups()
	# Non-modal Memory Fragment overlay, created once for the whole run. Deferred so
	# we add it after the scene finishes building (avoids a "parent busy" warning).
	_fragment_reader = FragmentReader.new()
	_fragment_reader.name = "FragmentReader"
	_main.add_child.call_deferred(_fragment_reader)
	RunManager.start_run()
	RunManager.room_cleared.connect(_on_room_cleared)
	GameEvents.player_died.connect(_on_player_died)
	_adopt_first_room()


## Record the scene-placed pickups so every room can respawn a fresh set.
func _snapshot_pickups() -> void:
	for child in _pickups_root.get_children():
		var pickup := child as Pickup
		if pickup == null:
			continue
		_pickup_configs.append({
			"transform": pickup.transform,
			"type": pickup.type,
			"amount": pickup.amount,
			"respawn_time": pickup.respawn_time,
		})


## GameManager (the Main root script) still bakes the navmesh and spawns the
## first squad. Wait for that, then take ownership of the run flow without
## modifying its script: detach its respawn/win handlers at runtime.
func _adopt_first_room() -> void:
	await get_tree().process_frame  # GameManager._ready has connected by now
	var gm_player_died := Callable(_main, "_on_player_died")
	if GameEvents.player_died.is_connected(gm_player_died):
		GameEvents.player_died.disconnect(gm_player_died)

	# Fires once GameManager finishes the initial spawn after the bake.
	await GameEvents.enemies_remaining_changed

	var gm_enemy_died := Callable(_main, "_on_enemy_died")
	var enemies := get_tree().get_nodes_in_group("enemies")
	for node in enemies:
		var enemy := node as EnemyAI
		if enemy.enemy_died.is_connected(gm_enemy_died):
			enemy.enemy_died.disconnect(gm_enemy_died)
		enemy.enemy_died.connect(_on_enemy_died)
	RunManager.register_room_enemies(enemies.size())


# ---------------------------------------------------------------- room loop

func _on_enemy_died(enemy: EnemyAI) -> void:
	if RunManager.run_active:
		if enemy.has_meta("elite"):
			# The elite always leaves a care package behind.
			for i in ELITE_DROP_COUNT:
				_spawn_health_drop(enemy.global_position
						+ Vector3(float(i) * 1.4 - 0.7, 0.0, 0.7))
		elif randf() < _upgrades.health_drop_chance:
			_spawn_health_drop(enemy.global_position)
	RunManager.notify_enemy_dead()


## Room cleared: instead of jumping straight into the next room, raise an exit
## gate at the far end so the player can sweep up any leftover pickups. Walking
## through the gate is what actually triggers the transition.
func _on_room_cleared() -> void:
	if not RunManager.run_active:
		return
	_spawn_exit_gate()


func _spawn_exit_gate() -> void:
	if is_instance_valid(_active_gate):
		_active_gate.queue_free()
	var gate := ExitGate.new()
	gate.name = "ExitGate"
	gate.set_portal_shader(PORTAL_SHADER)  # must be set before _ready (add_child)
	gate.player_entered.connect(_on_gate_entered, CONNECT_ONE_SHOT)
	_main.add_child(gate)
	gate.global_position = _gate_position()
	gate.face_toward(_player_spawn.global_position)
	_active_gate = gate
	_run_hud.show_hint("ROOM CLEARED  -  REACH THE EXIT GATE")


## The exit gate sits opposite the player spawn (mirrored across the room centre
## on Z), snapped onto the current room's navmesh so it always lands somewhere
## the player can actually walk into.
func _gate_position() -> Vector3:
	var spawn := _player_spawn.global_position
	var target := Vector3(0.0, 0.0, -spawn.z)
	var map: RID = _nav_region.get_world_3d().navigation_map
	var snapped := NavigationServer3D.map_get_closest_point(map, target)
	snapped.y = 0.0
	return snapped


func _on_gate_entered() -> void:
	_run_hud.hide_hint()
	if is_instance_valid(_active_gate):
		_active_gate.queue_free()
	_active_gate = null
	_run_transition()


func _run_transition() -> void:
	# Wipe the screen with the matrix-spiral overlay as the player crosses the
	# gate, then do the whole room change hidden behind it.
	await _run_hud.cover()
	# Freeze the whole game; this node and the RunHUD keep processing.
	get_tree().paused = true
	_run_hud.show_banner("ROOM CLEARED")
	await get_tree().create_timer(TRANSITION_FREEZE_SECONDS).timeout
	_run_hud.hide_banner()
	if not RunManager.run_active:  # died in the same instant the room cleared
		get_tree().paused = false
		await _run_hud.reveal()
		return

	# Milestone rooms reward extra picks; each pick rolls a fresh trio.
	var picks: int = RunManager.upgrade_picks_for_room(RunManager.current_room)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for pick in picks:
		var title := "CHOOSE AN UPGRADE"
		if picks > 1:
			title = "CHOOSE AN UPGRADE (%d OF %d)" % [pick + 1, picks]
		_run_hud.show_upgrade_choices(RunManager.roll_upgrade_choices(), title)
		var picked_id: String = await _run_hud.upgrade_chosen
		_run_hud.hide_upgrade_choices()
		_upgrades.apply_upgrade(picked_id)
		RunManager.record_upgrade(picked_id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _enter_next_room()


## Advance into RunManager.current_room + 1: roll the layer over, rebuild the room
## and populate it (pickups, high rewards, the squad or a narrative breather), then
## reveal. Assumes the caller has already covered the screen + paused the tree (the
## gate transition does the wipe + upgrade UI first; the dev room-jump does the wipe).
## Shared by both so the dev jump can't drift from the real transition.
func _enter_next_room() -> void:
	var prev_layer := RunManager.current_layer
	RunManager.advance_room()
	var descended: bool = RunManager.current_layer != prev_layer
	_clear_pickups()
	_clear_corpses()  # sweep last room's ragdolls/grenades while the wipe hides it
	_clear_narrative_markers()  # and any fragment/ghost marker from the last room

	# Crossing into a new layer gets its own beat before the build (CAMPAIGN only;
	# ENDLESS keeps current_layer at 0, so this never fires).
	if descended:
		_run_hud.show_banner("DESCENDING  //  %s" % RunManager.active_layer_profile().get("title", ""))
		await get_tree().create_timer(DESCENT_BEAT_SECONDS).timeout

	# Procedural rebuild needs live frames for the navmesh rebake, so the tree
	# unpauses behind a GENERATING beat while the player stays frozen.
	_run_hud.show_banner("GENERATING...")
	_set_player_frozen(true)
	get_tree().paused = false
	# In CAMPAIGN the active layer's profile re-skins the build; ENDLESS passes {}.
	var build: Dictionary = await _room_builder.build_room(RunManager.current_room,
			RunManager.active_layer_profile())
	# Teleport AFTER the build: the room footprint varies per room, so the builder
	# moves PlayerSpawn to the new south edge and we drop the player onto it here.
	_player.global_position = _player_spawn.global_position
	_player.velocity = Vector3.ZERO
	_spawn_pickups_at(_room_builder.get_pickup_points())
	_spawn_high_rewards(_room_builder.get_high_reward_points())
	# Combat rooms field a scaled squad; non-combat breathers (CAMPAIGN Fragment /
	# Ghost rooms) field none and raise the exit gate immediately so the player can
	# walk straight through. ENDLESS always reports COMBAT, so its loop is unchanged.
	var room_type: int = RunManager.current_room_type()
	if room_type == LayerCatalog.RoomType.COMBAT:
		_spawn_room_enemies(RunManager.current_room, _room_builder.get_enemy_spawn_points())
	else:
		_setup_narrative_room(room_type)
	_set_player_frozen(false)
	_run_hud.show_banner(_room_banner(_room_type_title(room_type, build.title)))
	# Reveal the freshly built room from behind the matrix wipe.
	await _run_hud.reveal()
	_decay_banner()


## DEV ONLY (driven by the DevTools autoload): jump straight to global room `target`,
## reusing the real transition pipeline. Sweeps the current room's leftover enemies +
## exit gate, wipes the screen, sets the counter so _enter_next_room lands on `target`,
## then rebuilds + populates it. Re-entrancy guarded so spamming the key is safe.
func dev_jump_to_room(target: int) -> void:
	if not RunManager.run_active or _dev_jump_active:
		return
	_dev_jump_active = true
	target = maxi(1, target)
	if is_instance_valid(_active_gate):
		_active_gate.queue_free()
		_active_gate = null
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()  # drop the old room's squad (no ragdoll; this is a dev warp)
	await _run_hud.cover()
	get_tree().paused = true
	# _enter_next_room's advance_room() ticks current_room from target-1 up to target;
	# leaving current_layer stale until then makes its descent check fire correctly.
	RunManager.current_room = target - 1
	await _enter_next_room()
	_dev_jump_active = false


## The freeze-reveal banner: in CAMPAIGN it reads "HEAP // SECTOR 2  -  PILLAR HALL"
## (layer tag + sector + archetype); in ENDLESS it stays the legacy "ROOM N - ...".
func _room_banner(archetype_title: String) -> String:
	if RunManager.run_mode == RunManager.RunMode.CAMPAIGN:
		var profile: Dictionary = RunManager.active_layer_profile()
		return "%s // SECTOR %d  -  %s" % [profile.get("tag", "?"),
				RunManager.room_in_layer, archetype_title]
	return "ROOM %d  -  %s" % [RunManager.current_room, archetype_title]


## The archetype subtitle for the banner, swapped for a room-type label in the
## non-combat breather rooms ("MEMORY FRAGMENT" / "CORRUPTED ECHO").
func _room_type_title(room_type: int, archetype_title: String) -> String:
	match room_type:
		LayerCatalog.RoomType.FRAGMENT:
			return "MEMORY FRAGMENT"
		LayerCatalog.RoomType.GHOST:
			return "CORRUPTED ECHO"
	return archetype_title


## Briefly keep the room title on screen, then clear it. Fire-and-forget.
func _decay_banner() -> void:
	await get_tree().create_timer(ROOM_BANNER_SECONDS).timeout
	if RunManager.run_active and not get_tree().paused:
		_run_hud.hide_banner()


## Externally freeze the player (no script changes): movement, camera input
## and weapon handling all stop while the next room generates.
func _set_player_frozen(frozen: bool) -> void:
	_player.set_physics_process(not frozen)
	_player.set_process(not frozen)
	_player.set_process_unhandled_input(not frozen)
	var weapon_manager: Node = _player.get_node("Head/Bob/Recoil/Camera/WeaponManager")
	weapon_manager.set_process(not frozen)
	weapon_manager.set_process_unhandled_input(not frozen)
	var ability_manager: Node = _player.get_node_or_null("AbilityManager")
	if ability_manager != null:
		ability_manager.set_physics_process(not frozen)
	var hack_manager: Node = _player.get_node_or_null("HackManager")
	if hack_manager != null:
		hack_manager.set_physics_process(not frozen)
		# Revert every live hack at transition start, before the old room's props free.
		if frozen:
			hack_manager.clear_all()


func _clear_pickups() -> void:
	for child in _pickups_root.get_children():
		child.queue_free()


## Free any death ragdolls / live grenades left over from the previous room, so
## they don't linger into the next one. Hidden behind the transition wipe.
func _clear_corpses() -> void:
	for node in get_tree().get_nodes_in_group("enemy_corpse"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("enemy_grenade"):
		node.queue_free()


## Free any fragment/ghost marker left over from the previous room (mirrors
## _clear_corpses; hidden behind the transition wipe).
func _clear_narrative_markers() -> void:
	for node in get_tree().get_nodes_in_group("narrative_marker"):
		node.queue_free()


## Restock the snapshot pickup set at builder-chosen spots: ammo behind cover,
## health/armor in the open. Falls back to the authored transforms if the
## builder came up short.
func _spawn_pickups_at(points: Array[Dictionary]) -> void:
	var covered: Array[Vector3] = []
	var exposed: Array[Vector3] = []
	for point in points:
		if point.exposed:
			exposed.append(point.position)
		else:
			covered.append(point.position)
	for config in _pickup_configs:
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		pickup.type = config.type
		pickup.amount = config.amount
		pickup.respawn_time = config.respawn_time
		var wants_cover: bool = config.type == Pickup.Type.AMMO
		var primary := covered if wants_cover else exposed
		var fallback := exposed if wants_cover else covered
		if not primary.is_empty():
			pickup.position = primary.pop_front()
		elif not fallback.is_empty():
			pickup.position = fallback.pop_front()
		else:
			pickup.transform = config.transform
		_pickups_root.add_child(pickup)


## Drop one bonus pickup on each elevated reward spot (a Tiers platform cap). The
## list is empty for every non-vertical room, so this is a no-op there. These are
## EXTRA pickups beyond the room's snapshot set, so the normal pickup balance is
## untouched -- pure reward for taking the high ground (enemies can't reach them).
## Position is set BEFORE add_child so each Pickup captures its cap-top _base_y.
func _spawn_high_rewards(points: Array[Vector3]) -> void:
	for i in points.size():
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		pickup.type = Pickup.Type.ARMOR if i % 2 == 0 else Pickup.Type.HEALTH
		pickup.amount = HIGH_REWARD_AMOUNT
		pickup.respawn_time = HIGH_REWARD_RESPAWN
		pickup.position = points[i]
		_pickups_root.add_child(pickup)


func _spawn_room_enemies(room: int, points: Array[Vector3]) -> void:
	var count := RunManager.enemy_count_for_room(room)
	var multiplier := RunManager.enemy_stat_multiplier(room)
	var milestone: bool = RunManager.is_milestone_room(room)
	# Archetype slots, front to back with no overlap (each clamp leaves room for
	# the rest): snipers take the front indices, grenadiers the next, rushers the
	# back, regulars whatever is left in the middle.
	var snipers: int = mini(RunManager.sniper_count_for_room(room), count)
	var grenadiers: int = mini(RunManager.grenadier_count_for_room(room), maxi(0, count - snipers))
	var rushers: int = mini(RunManager.rusher_count_for_room(room),
			maxi(0, count - snipers - grenadiers))
	var fallback_markers := get_tree().get_nodes_in_group("enemy_spawn")
	for i in count:
		var enemy := ENEMY_SCENE.instantiate() as EnemyAI
		if milestone and i == 0:
			_outfit_elite(enemy, room, multiplier)
		elif not milestone and i < snipers:
			# The first few of a normal squad hang back as snipers.
			_outfit_sniper(enemy, room, multiplier)
		elif not milestone and i < snipers + grenadiers:
			# Then a grenadier or two for area denial.
			_outfit_grenadier(enemy, room, multiplier)
		elif not milestone and i >= count - rushers:
			# The last few of a normal squad charge in as rushers.
			_outfit_rusher(enemy, room, multiplier)
		else:
			enemy.name = "Room%d Enemy %d" % [room, i + 1]
			enemy.shot_damage *= multiplier
			var enemy_health := enemy.get_node("Health") as HealthComponent
			enemy_health.max_health *= multiplier
		var spot: Vector3
		if i < points.size():
			spot = points[i]
		else:  # builder shortfall: authored markers, nudged when reused
			var marker := fallback_markers[i % fallback_markers.size()] as Node3D
			spot = marker.global_position + Vector3(
					randf_range(-SPAWN_JITTER, SPAWN_JITTER), 0.0,
					randf_range(-SPAWN_JITTER, SPAWN_JITTER))
		# Position before add_child so EnemyAI captures the right patrol home.
		enemy.position = spot  # Main sits at the origin, so local == global
		_main.add_child(enemy)
		enemy.enemy_died.connect(_on_enemy_died)
	RunManager.register_room_enemies(count)
	GameEvents.enemies_remaining_changed.emit(count)


## A non-combat breather room (CAMPAIGN Fragment / Ghost): no enemies, the HUD
## enemy counter cleared, a narrative object dropped at the room centre, and the
## exit gate raised immediately so traversal -- not killing -- advances the run.
## Fragment rooms get a real Memory Fragment (Pass 3); Ghost rooms keep a
## placeholder marker until Pass 4 gives them corrupted-echo visuals.
func _setup_narrative_room(room_type: int) -> void:
	GameEvents.enemies_remaining_changed.emit(0)
	if room_type == LayerCatalog.RoomType.GHOST:
		var marker := Marker3D.new()
		marker.name = "GhostMarker"
		marker.add_to_group("ghost_room")
		marker.add_to_group("narrative_marker")
		_main.add_child(marker)
		marker.global_position = Vector3(0.0, 1.0, 0.0)
		_run_hud.show_hint("CORRUPTED ECHO  -  REACH THE EXIT GATE")
	else:
		_spawn_memory_fragment()
		_run_hud.show_hint("MEMORY FRAGMENT DETECTED  -  REACH THE EXIT GATE")
	_spawn_exit_gate()


## Place the next unseen Awakening fragment at the room centre as a walk-into,
## optional Memory Fragment. Position is set before add_child so it captures its
## own bob origin; it joins the narrative_marker group so it is swept on transition.
func _spawn_memory_fragment() -> void:
	var fragment := MemoryFragment.new()
	fragment.name = "MemoryFragment"
	fragment.add_to_group("fragment_room")
	fragment.add_to_group("narrative_marker")
	# Each layer surfaces its own story arc (Heap = awakening, Stack = history, ...).
	var arc := String(RunManager.active_layer_profile().get("arc", "awakening"))
	fragment.set_fragment(FragmentDB.pick_for_arc(arc, RunManager.current_room))
	fragment.position = Vector3(0.0, 1.2, 0.0)  # Main sits at the origin: local == global
	_main.add_child(fragment)


## Turn a freshly instantiated (not yet added) enemy into the milestone elite:
## boosted stats on top of room scaling, a broader crimson/gold look, and a
## matching wider body hitbox. All per-instance — shared shape and material
## resources are duplicated or overridden, never mutated.
func _outfit_elite(enemy: EnemyAI, room: int, multiplier: float) -> void:
	enemy.name = "Room%d ELITE" % room
	enemy.set_meta("elite", true)
	enemy.shot_damage *= multiplier * ELITE_DAMAGE_FACTOR
	enemy.combat_speed *= ELITE_SPEED_FACTOR
	enemy.reaction_time *= 0.5
	enemy.lose_sight_time *= 1.5
	enemy.sight_range *= 1.25
	enemy.attack_range *= 1.25
	enemy.burst_count += 2
	enemy.mag_size *= 2
	var enemy_health := enemy.get_node("Health") as HealthComponent
	enemy_health.max_health *= multiplier * ELITE_HEALTH_FACTOR

	# Broader silhouette: XZ only, so the head stays where the head hitbox is.
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(1.25, 1.0, 1.25)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.32, 0.05, 0.09)
	body_material.emission_enabled = true
	body_material.emission = Color(0.8, 0.1, 0.1)
	body_material.emission_energy_multiplier = 0.35
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.95, 0.78, 0.3)
	head_material.emission_enabled = true
	head_material.emission = Color(1.0, 0.75, 0.2)
	head_material.emission_energy_multiplier = 0.6
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material

	# Wider body hitbox to match the silhouette (shape resource is shared
	# across enemy instances, so duplicate before resizing).
	var hit_shape := enemy.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D
	var capsule := (hit_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius *= 1.25
	hit_shape.shape = capsule


## Turn a freshly instantiated (not yet added) enemy into a Rusher: a fast,
## aggressive close-quarters attacker. Like the elite, this is pure external
## tuning of the stock enemy.tscn -- no enemy_ai.gd change, the behaviour is
## emergent from the existing state machine:
##  - charges in: high combat speed + short attack range + fast reactions, so it
##    CHASEs hard and only settles to fire at point-blank.
##  - never breaks contact: a huge magazine means it never stops to reload (so it
##    never takes the reload->cover path), and a 0 cover/flank threshold means a
##    hurt rusher never flees -- it just keeps coming.
##  - point-blank spray: a fast multi-shot burst with broad spread and lower
##    per-pellet damage reads like a shotgun up close, harmless at range.
## Fragile (less health) so the aggression is a kill-it-fast threat, not a wall.
## Leaner, hazard-orange silhouette so the player reads the threat at a glance.
func _outfit_rusher(enemy: EnemyAI, room: int, multiplier: float) -> void:
	enemy.name = "Room%d RUSHER" % room
	enemy.set_meta("rusher", true)
	enemy.combat_speed *= RUSHER_SPEED_FACTOR
	enemy.patrol_speed *= 1.2
	enemy.turn_speed *= 1.2
	enemy.reaction_time *= 0.5
	enemy.attack_range = RUSHER_ATTACK_RANGE
	enemy.aim_spread_deg = 9.0          # shotgun-like spread
	enemy.burst_count = RUSHER_BURST    # pellets per spray
	enemy.burst_shot_interval = 0.05    # near-simultaneous
	enemy.burst_pause = 0.7
	enemy.mag_size = 999                # never stops to reload -> never seeks cover
	enemy.cover_health_threshold = 0.0  # never flees / flanks, just keeps charging
	enemy.shot_damage *= multiplier * RUSHER_DAMAGE_FACTOR
	var enemy_health := enemy.get_node("Health") as HealthComponent
	enemy_health.max_health *= multiplier * RUSHER_HEALTH_FACTOR

	# Leaner, hazard-orange silhouette (XZ only, so the head stays aligned with
	# the head hitbox). Materials set before add_child, so ToonApplicator reads
	# and preserves the orange when it cel-shades the enemy.
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(0.85, 1.0, 0.85)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.85, 0.34, 0.05)
	body_material.emission_enabled = true
	body_material.emission = Color(1.0, 0.45, 0.05)
	body_material.emission_energy_multiplier = 0.45
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(1.0, 0.7, 0.2)
	head_material.emission_enabled = true
	head_material.emission = Color(1.0, 0.65, 0.15)
	head_material.emission_energy_multiplier = 0.5
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material

	# Narrow the body hitbox to match the leaner silhouette (shape resource is
	# shared across instances, so duplicate before resizing).
	var hit_shape := enemy.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D
	var capsule := (hit_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius *= 0.85
	hit_shape.shape = capsule


## Turn a freshly instantiated (not yet added) enemy into a Sniper: a long-range
## marksman that lands one big telegraphed shot. The charged-shot + relocate
## behaviour itself lives in enemy_ai.gd behind the `is_sniper` flag (a regular
## enemy never runs it); this hook just flips the flag and tunes the engagement:
## far sight + attack range, deliberate movement, a near-perfect aim, and a heavy
## single-shot damage. Less health than a regular, so flanking it pays off. Cold
## cyan silhouette (taller/leaner) so the long-range threat reads from afar.
func _outfit_sniper(enemy: EnemyAI, room: int, multiplier: float) -> void:
	enemy.name = "Room%d SNIPER" % room
	enemy.set_meta("sniper", true)
	enemy.is_sniper = true
	enemy.sight_range = SNIPER_SIGHT_RANGE
	enemy.attack_range = SNIPER_ATTACK_RANGE
	enemy.combat_speed *= SNIPER_SPEED_FACTOR
	enemy.aim_spread_deg = 0.4          # near-perfect aim down the locked line
	enemy.shot_damage *= multiplier * SNIPER_DAMAGE_FACTOR
	var enemy_health := enemy.get_node("Health") as HealthComponent
	enemy_health.max_health *= multiplier * SNIPER_HEALTH_FACTOR

	# Taller, leaner cold-cyan silhouette (XZ only, so the head stays aligned with
	# the head hitbox). Materials set before add_child so ToonApplicator keeps the
	# colour when it cel-shades the enemy.
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(0.85, 1.1, 0.85)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.1, 0.5, 0.62)
	body_material.emission_enabled = true
	body_material.emission = Color(0.15, 0.7, 0.9)
	body_material.emission_energy_multiplier = 0.4
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.75, 0.92, 1.0)
	head_material.emission_enabled = true
	head_material.emission = Color(0.5, 0.85, 1.0)
	head_material.emission_energy_multiplier = 0.6
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material

	# Narrow the body hitbox to match the leaner silhouette (shared shape -> dup).
	var hit_shape := enemy.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D
	var capsule := (hit_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius *= 0.85
	hit_shape.shape = capsule


## Turn a freshly instantiated (not yet added) enemy into a Grenadier: a mid-range
## area-denial unit that lobs arcing grenades to flush the player out of cover.
## Like the sniper, the lob behaviour lives in enemy_ai.gd behind the off-by-default
## `is_grenadier` flag; this hook flips it and tunes the engagement: mid attack
## range (it wants room to arc), a heavy AoE blast off the base damage, and a touch
## more health (it's a priority backline target, not a runner). Bulky olive-green
## silhouette so the launcher unit reads at a glance.
func _outfit_grenadier(enemy: EnemyAI, room: int, multiplier: float) -> void:
	enemy.name = "Room%d GRENADIER" % room
	enemy.set_meta("grenadier", true)
	enemy.is_grenadier = true
	enemy.attack_range = GRENADIER_ATTACK_RANGE
	enemy.grenade_damage = enemy.shot_damage * multiplier * GRENADIER_DAMAGE_FACTOR
	enemy.grenade_radius = GRENADIER_BLAST_RADIUS
	enemy.shot_damage *= multiplier  # unused (it never fires), kept consistent
	var enemy_health := enemy.get_node("Health") as HealthComponent
	enemy_health.max_health *= multiplier * GRENADIER_HEALTH_FACTOR

	# Bulky olive-green silhouette (XZ only, so the head stays aligned with the head
	# hitbox). Materials set before add_child so ToonApplicator keeps the colour.
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(1.15, 1.0, 1.15)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.32, 0.46, 0.16)
	body_material.emission_enabled = true
	body_material.emission = Color(0.4, 0.8, 0.2)
	body_material.emission_energy_multiplier = 0.4
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.7, 0.85, 0.4)
	head_material.emission_enabled = true
	head_material.emission = Color(0.6, 0.9, 0.3)
	head_material.emission_energy_multiplier = 0.5
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material

	# Wider body hitbox to match the bulkier silhouette (shared shape -> dup).
	var hit_shape := enemy.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D
	var capsule := (hit_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius *= 1.15
	hit_shape.shape = capsule


func _spawn_health_drop(at: Vector3) -> void:
	var pickup := PICKUP_SCENE.instantiate() as Pickup
	pickup.type = Pickup.Type.HEALTH
	pickup.amount = HEALTH_DROP_AMOUNT
	pickup.respawn_time = 9999.0  # consumed drops should not come back
	pickup.position = Vector3(at.x, 0.1, at.z)
	_pickups_root.add_child(pickup)


# ---------------------------------------------------------------- permadeath

func _on_player_died() -> void:
	# RunManager (connected first) has already flagged the run as over and the
	# RunHUD is showing the summary; freeze what is left of the world.
	if is_instance_valid(_active_gate):
		_active_gate.queue_free()
		_active_gate = null
	_run_hud.hide_hint()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The legacy HUD death screen ("Respawning in...") no longer applies:
	# hide it once its handler has run.
	await get_tree().process_frame
	var legacy_death_screen := _hud.get_node("DeathScreen") as Control
	legacy_death_screen.visible = false
