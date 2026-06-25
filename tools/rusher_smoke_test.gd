extends Node
## Headless test for the Rusher enemy archetype (RUSHER_SMOKE_OK).
## Run: godot --headless --path . res://tools/rusher_smoke_test.tscn
##
## Two layers, like the elite test:
##  - pure composition curve on RunManager (no scene): rushers start at room 3,
##    none in milestone rooms, ramp with depth, capped to a share of the squad,
##    and the count is deterministic.
##  - real spawn: fast-forwards to room 3 (the first rusher room) the same way
##    elite_smoke fast-forwards to room 5, then inspects the spawned rusher --
##    aggressive tuning vs a regular squadmate, leaner orange look + matching
##    hitbox -- and confirms it actually engages the player on sight.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # transitions pause the tree
	_check_composition()
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)
	await _run(main_scene)
	if fails.is_empty():
		print("RUSHER_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("RUSHER_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _alive_enemies() -> Array:
	var alive := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if int(e.get("state")) != 7:  # EnemyAI.State.DEAD
			alive.append(e)
	return alive


func _kill(enemy: Node) -> void:
	enemy.get_node("BodyHitbox").call("take_hit", 100000.0, Vector3.ZERO)


func _await_room_ready(count: int, max_frames: int = 1800) -> bool:
	var tries := 0
	while tries < max_frames:
		if _alive_enemies().size() == count and not get_tree().paused:
			return true
		tries += 1
		await get_tree().process_frame
	return false


func _await_panel(panel: Control, max_frames: int = 600) -> bool:
	var tries := 0
	while not panel.visible and tries < max_frames:
		tries += 1
		await get_tree().process_frame
	return panel.visible


func _pass_gate(main_scene: Node) -> void:
	var gate: Node = null
	var tries := 0
	while gate == null and tries < 300:
		gate = main_scene.get_node_or_null("ExitGate")
		tries += 1
		await get_tree().process_frame
	if gate != null:
		gate.emit_signal("player_entered")
		await get_tree().process_frame


## Pure curve: deterministic, none early/in milestones, ramps + capped.
func _check_composition() -> void:
	_check(RunManager.rusher_count_for_room(1) == 0, "room 1 should have no rushers")
	_check(RunManager.rusher_count_for_room(2) == 0, "room 2 should have no rushers")
	_check(RunManager.rusher_count_for_room(3) >= 1, "room 3 should introduce a rusher")
	_check(RunManager.rusher_count_for_room(5) == 0, "milestone room 5 should have no rushers")
	_check(RunManager.rusher_count_for_room(10) == 0, "milestone room 10 should have no rushers")
	_check(RunManager.rusher_count_for_room(9) >= RunManager.rusher_count_for_room(3),
			"rusher count should not shrink with depth")
	for room in range(3, 40):
		if RunManager.is_milestone_room(room):
			continue
		var rc: int = RunManager.rusher_count_for_room(room)
		var squad: int = RunManager.enemy_count_for_room(room)
		_check(rc >= 1, "non-milestone room %d should have >=1 rusher" % room)
		_check(rc <= maxi(1, squad / 3),
				"room %d rushers %d exceed the cap (squad %d)" % [room, rc, squad])
		_check(rc < squad, "room %d should never be all rushers" % room)
		_check(rc == RunManager.rusher_count_for_room(room),
				"rusher count for room %d is not deterministic" % room)


func _run(main_scene: Node) -> void:
	# Room 1: wait for the adopted squad, blind it, wipe it.
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check(enemies.size() == 5, "expected 5 enemies in room 1, got %d" % enemies.size())
	if enemies.size() < 5:
		return
	for e in enemies:
		e.set("sight_range", 0.0)
		_kill(e)

	var run_hud: CanvasLayer = main_scene.get_node("RunHUD")
	var upgrade_panel: Control = run_hud.get_node("UpgradePanel")
	var room_label: Label = run_hud.get_node("RoomLabel")
	await _pass_gate(main_scene)
	_check(await _await_panel(upgrade_panel), "upgrade screen never appeared after room 1")
	if not upgrade_panel.visible:
		return

	# Fast-forward: the pending advance_room() lands on room 3 (first rusher room).
	RunManager.current_room = 2
	run_hud.emit_signal("upgrade_chosen", "armor")

	var expected: int = RunManager.enemy_count_for_room(3)  # 7
	_check(expected == 7, "room 3 squad should be 7, got %d" % expected)
	_check(await _await_room_ready(expected), "room 3 never became ready")
	if _alive_enemies().size() != expected:
		return
	_check(room_label.text == "ROOM 3", "room label should read ROOM 3, got %s" % room_label.text)

	# Split the squad into the rusher and a plain squadmate for comparison.
	var rusher: Node = null
	var regular: Node = null
	for e in _alive_enemies():
		if (e as Node).has_meta("rusher"):
			_check(rusher == null, "room 3 should spawn exactly one rusher")
			rusher = e
		else:
			regular = e
	_check(rusher != null, "no rusher found in room 3")
	_check(regular != null, "no regular enemy found to compare against")
	if rusher == null or regular == null:
		return

	# --- Aggressive tuning (compared to a regular squadmate, so it survives any
	#     tscn stat overrides). ---
	var r_speed: float = rusher.get("combat_speed")
	var n_speed: float = regular.get("combat_speed")
	_check(absf(r_speed - n_speed * 1.6) < 0.01,
			"rusher combat_speed should be 1.6x regular (%.2f vs %.2f)" % [r_speed, n_speed])
	_check(absf(float(rusher.get("attack_range")) - 6.0) < 0.01,
			"rusher attack_range should be 6, got %s" % rusher.get("attack_range"))
	_check(float(rusher.get("attack_range")) < float(regular.get("attack_range")),
			"rusher should fight closer than a regular enemy")
	_check(int(rusher.get("mag_size")) >= 100,
			"rusher needs a huge mag so it never reload-covers, got %s" % rusher.get("mag_size"))
	_check(absf(float(rusher.get("cover_health_threshold"))) < 0.001,
			"rusher cover threshold should be 0 (never flees), got %s"
			% rusher.get("cover_health_threshold"))
	_check(int(rusher.get("burst_count")) == 4, "rusher burst_count should be 4")
	_check(float(rusher.get("aim_spread_deg")) > float(regular.get("aim_spread_deg")),
			"rusher should spray wider than a regular enemy")
	_check(float(rusher.get("reaction_time")) < float(regular.get("reaction_time")),
			"rusher should react faster than a regular enemy")

	# Glass cannon: less health, lower per-pellet damage than a regular squadmate.
	var r_hp: float = rusher.get_node("Health").get("max_health")
	var n_hp: float = regular.get_node("Health").get("max_health")
	_check(absf(r_hp - n_hp * 0.7) < 0.01,
			"rusher max health should be 0.7x regular (%.1f vs %.1f)" % [r_hp, n_hp])
	var r_dmg: float = rusher.get("shot_damage")
	var n_dmg: float = regular.get("shot_damage")
	_check(absf(r_dmg - n_dmg * 0.75) < 0.01,
			"rusher per-pellet damage should be 0.75x regular (%.2f vs %.2f)" % [r_dmg, n_dmg])

	# --- Leaner orange look + matching hitbox. ---
	var visual: Node3D = rusher.get_node("Visual")
	_check(absf(visual.scale.x - 0.85) < 0.01 and absf(visual.scale.z - 0.85) < 0.01,
			"rusher silhouette should be narrowed to 0.85 XZ, got %s" % str(visual.scale))
	_check(absf(visual.scale.y - 1.0) < 0.01, "rusher height should be unchanged (head stays aligned)")
	# The orange is set as a StandardMaterial3D before add_child, but ToonApplicator
	# then swaps material_override for a toon ShaderMaterial, copying the colour into
	# its "albedo" uniform (this is how elites keep their crimson). Read whichever.
	var body_override: Material = (rusher.get_node("Visual/Body") as MeshInstance3D).material_override
	_check(body_override != null, "rusher body has no material override for the orange look")
	var c := Color.WHITE
	if body_override is ShaderMaterial:
		var param: Variant = (body_override as ShaderMaterial).get_shader_parameter("albedo")
		if param is Color:
			c = param
	elif body_override is StandardMaterial3D:
		c = (body_override as StandardMaterial3D).albedo_color
	_check(c.r > 0.6 and c.g < 0.5 and c.b < 0.2, "rusher body should be hazard orange, got %s" % str(c))
	var r_shape := (rusher.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D).shape as CapsuleShape3D
	var n_shape := (regular.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D).shape as CapsuleShape3D
	_check(absf(r_shape.radius - n_shape.radius * 0.85) < 0.01,
			"rusher body hitbox should be narrowed to match (%.3f vs %.3f)"
			% [r_shape.radius, n_shape.radius])
	_check(r_shape != n_shape, "rusher must duplicate the shared hitbox shape, not mutate it")

	# --- Behaviour: it engages the player on sight (senses only, no navmesh). ---
	# Isolate a clean line of sight high above the room so geometry can't block;
	# blind the rest of the squad so only the rusher reacts.
	for e in _alive_enemies():
		if e != rusher:
			e.set("sight_range", 0.0)
	# Widen the FOV so the patrol-wander re-facing can't drop the player out of the
	# vision cone (we're testing sense->engage, not the cone itself).
	rusher.set("sight_half_fov_deg", 360.0)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var rz := rusher as Node3D
	rz.global_position = Vector3(0.0, 40.0, 0.0)
	player.global_position = Vector3(0.0, 40.0, -5.0)  # 5 m in front, well within sight
	rz.look_at(player.global_position, Vector3.UP)     # -Z faces the player (its forward)
	var engaged := false
	tries = 0
	while tries < 40:
		var st := int(rusher.get("state"))
		if st != 0 and st != 7:  # left PATROL, not DEAD -> ALERT/CHASE/ATTACK/...
			engaged = true
			break
		tries += 1
		await get_tree().physics_frame
	_check(engaged, "rusher did not engage the player on sight (state stayed %d)" % int(rusher.get("state")))
