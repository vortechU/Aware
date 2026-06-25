extends Node
## Headless integration test for the roguelite run loop + procedural rooms.
## Run: godot --headless --path . res://tools/run_smoke_test.tscn
## Covers: room 1 adoption, clear -> freeze -> upgrade -> procedurally built
## room 2 (scaled enemies, fresh pickups, retired authored interior, rebaked
## navmesh), upgrade math without resource leaks, health drops, a second
## transition into room 3 with a different layout, seeded reproducibility,
## and the permadeath stats screen.

var fails: Array[String] = []
var cleared_count := 0
var run_end_result := []  # appended [won] when run_ended fires


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # transitions pause the tree
	RunManager.room_cleared.connect(func() -> void: cleared_count += 1)
	RunManager.run_ended.connect(func(won: bool) -> void: run_end_result.append(won))
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)
	await _run(main_scene)
	if fails.is_empty():
		print("RUN_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("RUN_SMOKE_FAIL: ", f)
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


## A cleared room now raises an exit gate; the next room only starts once the
## player walks through it. Find the gate, drive the player into it (exercising
## the real Area3D body_entered path), and return once the transition has begun
## (tree paused). Falls back to emitting the gate signal if the overlap is slow.
func _pass_through_gate(main_scene: Node, player: Node) -> bool:
	var gate: Node = null
	var tries := 0
	while gate == null and tries < 300:
		gate = main_scene.get_node_or_null("ExitGate")
		tries += 1
		await get_tree().process_frame
	if gate == null:
		return false
	# Hold the player on the gate until the transition takes over (the screen
	# cover fades in first, so the tree only pauses a beat after body_entered
	# fires and frees the gate -- stop teleporting once it is consumed).
	tries = 0
	while tries < 600 and not get_tree().paused:
		if is_instance_valid(gate):
			(player as Node3D).global_position = (gate as Node3D).global_position
		tries += 1
		await get_tree().physics_frame
	if not get_tree().paused and is_instance_valid(gate):
		gate.emit_signal("player_entered")  # fallback if the overlap never fired
	tries = 0
	while not get_tree().paused and tries < 200:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame  # let the gate's queue_free settle
	return get_tree().paused


## Wait until the given number of enemies is alive (room ready) or time out.
func _await_room_ready(count: int, max_frames: int = 1800) -> bool:
	var tries := 0
	while tries < max_frames:
		if _alive_enemies().size() == count and not get_tree().paused:
			return true
		tries += 1
		await get_tree().process_frame
	return false


func _generated_layout(main_scene: Node) -> String:
	var container: Node = main_scene.get_node_or_null("NavRegion/GeneratedRoom")
	if container == null:
		return ""
	var parts := PackedStringArray()
	for child in container.get_children():
		if child is StaticBody3D:
			parts.append(str((child as Node3D).position.snappedf(0.01)))
	return ";".join(parts)


## Footprint assertions: the room is a valid footprint (square / rectangular /
## L-shaped), the seeded picker varies (incl. a rectangle AND an L) + is
## deterministic, the spawn marker sat on the new south edge, and every generated
## obstacle sits inside the walls and out of the notch.
func _check_footprint(main_scene: Node, label: String, spawn_node: Node3D) -> void:
	var builder: Node = main_scene.get_node("RoomBuilder")
	var half: Vector2 = builder.get("_room_half")
	var notch: Vector2 = builder.get("_notch")

	# Reconstruct the possible footprints from the pure picker; this proves they
	# vary, include a rectangle and an L, and are reproducible for a given seed.
	var seen := {}
	var saw_rect := false
	var saw_l := false
	for s in 200:
		var r := RandomNumberGenerator.new()
		r.seed = s
		var fp: Dictionary = builder.call("_pick_footprint", r)
		seen[_fp_key(fp)] = true
		var h: Vector2 = fp.half
		if not is_equal_approx(h.x, h.y):
			saw_rect = true
		if (fp.notch as Vector2) != Vector2.ZERO:
			saw_l = true
	_check(seen.size() >= 3, "footprint should vary across seeds, saw %d kinds" % seen.size())
	_check(saw_rect, "picker should offer a rectangular footprint")
	_check(saw_l, "pass 3 picker should offer an L-shaped footprint")
	var cur_key := _fp_key({"half": half, "notch": notch,
			"corner": int(builder.get("_notch_corner"))})
	_check(seen.has(cur_key), "%s footprint %s is not a valid class" % [label, cur_key])
	var ra := RandomNumberGenerator.new()
	ra.seed = 7
	var rb := RandomNumberGenerator.new()
	rb.seed = 7
	_check(_fp_key(builder.call("_pick_footprint", ra)) == _fp_key(builder.call("_pick_footprint", rb)),
			"footprint pick is not deterministic")

	# Spawn marker sits 3 m off the south wall of the chosen footprint.
	_check(absf(spawn_node.position.z - (half.y - 3.0)) < 0.01,
			"%s spawn not on the south edge (z=%.2f, expected %.2f)"
			% [label, spawn_node.position.z, half.y - 3.0])

	# Every generated obstacle is inside the walls and out of the notch (if any).
	var nmin: Vector2 = builder.get("_notch_min")
	var nmax: Vector2 = builder.get("_notch_max")
	var container: Node = main_scene.get_node_or_null("NavRegion/GeneratedRoom")
	if container != null:
		for child in container.get_children():
			if child is StaticBody3D:
				var p: Vector3 = (child as Node3D).position
				_check(absf(p.x) <= half.x and absf(p.z) <= half.y,
						"%s obstacle outside the walls at %s (half %s)"
						% [label, str(p), str(half)])
				if notch != Vector2.ZERO:
					var in_notch := p.x > nmin.x and p.x < nmax.x \
							and p.z > nmin.y and p.z < nmax.y
					_check(not in_notch,
							"%s obstacle inside the notch at %s" % [label, str(p)])


func _fp_key(fp: Dictionary) -> String:
	return "%s|%s|%d" % [str(fp.half), str(fp.notch), int(fp.corner)]


func _run(main_scene: Node) -> void:
	# 1. Room 1: GameManager spawns 5 enemies; RunDirector adopts them.
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame  # let RunDirector finish the adoption
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check(enemies.size() == 5, "expected 5 enemies in room 1, got %d" % enemies.size())
	if enemies.size() < 5:
		return
	_check(RunManager.run_active, "run not active after scene load")
	_check(RunManager.current_room == 1, "current_room should start at 1")
	for e in enemies:
		e.set("sight_range", 0.0)  # blind the AI for determinism

	var run_hud: CanvasLayer = main_scene.get_node("RunHUD")
	var room_label: Label = run_hud.get_node("RoomLabel")
	var upgrade_panel: Control = run_hud.get_node("UpgradePanel")
	var banner: Label = run_hud.get_node("Banner")
	_check(room_label.text == "ROOM 1", "room label should read ROOM 1, got %s" % room_label.text)

	var player: Node = get_tree().get_first_node_in_group("player")
	var upgrades: Node = player.get_node("PlayerUpgrades")
	var weapon_manager: Node = player.get_node("Head/Bob/Recoil/Camera/WeaponManager")

	# 2. Killing 4 of 5 must NOT clear the room.
	for i in 4:
		_kill(enemies[i])
	await get_tree().process_frame
	_check(cleared_count == 0, "room cleared too early (after 4 of 5 kills)")
	_check(RunManager.enemies_killed == 4,
			"enemies_killed should be 4, got %d" % RunManager.enemies_killed)
	_check(not get_tree().paused, "tree paused before the room was cleared")

	# 3. Last kill -> room_cleared, but the next room must NOT start yet: an exit
	#    gate appears and the world stays live so the player can grab pickups.
	_kill(enemies[4])
	await get_tree().process_frame
	_check(cleared_count == 1, "room_cleared did not fire after the last kill")
	_check(not get_tree().paused, "tree should stay live until the player reaches the gate")
	var gate_hint: Label = run_hud.get_node("GateHint")
	_check(gate_hint.visible, "gate hint not shown after the room cleared")
	_check(main_scene.get_node_or_null("ExitGate") != null,
			"exit gate did not spawn on room clear")
	_check(not upgrade_panel.visible, "upgrade screen shown before reaching the gate")

	# 3b. Walk the player through the gate -> the transition begins (freeze).
	var reached := await _pass_through_gate(main_scene, player)
	_check(reached, "transition never began after passing through the gate")
	_check(get_tree().paused, "tree should be paused once the transition begins")
	_check(banner.visible, "ROOM CLEARED banner not visible during the freeze")
	_check(not gate_hint.visible, "gate hint still visible after passing the gate")
	_check(main_scene.get_node_or_null("ExitGate") == null,
			"exit gate not removed once the transition began")

	# 4. Upgrade screen appears after the freeze; pick the first card.
	tries = 0
	while not upgrade_panel.visible and tries < 600:
		tries += 1
		await get_tree().process_frame
	_check(upgrade_panel.visible, "upgrade screen never appeared")
	if not upgrade_panel.visible:
		return
	_check(not banner.visible, "banner still visible once choices are shown")
	var card: Button = run_hud.get_node("UpgradePanel/Center/Box/Cards/Card1")
	_check(card.text.length() > 0, "upgrade card has no text")
	card.pressed.emit()

	# 5. Room 2 is procedurally built (navmesh rebake takes a few frames).
	var room2_ready := await _await_room_ready(6)
	_check(room2_ready, "room 2 never became ready (6 alive enemies, unpaused)")
	if not room2_ready:
		return
	_check(RunManager.current_room == 2, "current_room should be 2, got %d" % RunManager.current_room)
	_check(room_label.text == "ROOM 2", "room label should read ROOM 2, got %s" % room_label.text)
	_check(RunManager.current_run_modifiers.size() == 1,
			"one upgrade should be recorded, got %d" % RunManager.current_run_modifiers.size())
	var spawn: Node3D = main_scene.get_node("PlayerSpawn")
	var dist: float = (player as Node3D).global_position.distance_to(spawn.global_position)
	_check(dist < 2.0, "player not teleported to spawn (distance %.2f)" % dist)
	# Room 1's death ragdolls should have been swept on the transition.
	_check(get_tree().get_nodes_in_group("enemy_corpse").is_empty(),
			"room 1 corpses should be cleared on the transition into room 2")

	var alive := _alive_enemies()
	for e in alive:
		e.set("sight_range", 0.0)
	var health_component: Node = (alive[0] as Node).get_node("Health")
	var enemy_max: float = health_component.get("max_health")
	_check(absf(enemy_max - 110.0) < 0.01,
			"room 2 enemy max health should be 110, got %s" % enemy_max)
	var scaled_damage: float = alive[0].get("shot_damage")
	_check(absf(scaled_damage - 8.8) < 0.01,
			"room 2 enemy shot_damage should be 8.8, got %s" % scaled_damage)

	# 6. Procedural-room assertions: generated geometry in place, authored
	# interior AND shell retired (a sized procedural shell takes over), cover
	# group repopulated, navmesh rebaked.
	var room2_layout := _generated_layout(main_scene)
	_check(room2_layout.length() > 0, "no generated geometry under NavRegion/GeneratedRoom")
	_check(main_scene.get_node_or_null("NavRegion/Arena/Crate1") == null,
			"authored interior crate still present in room 2")
	_check(main_scene.get_node_or_null("NavRegion/Arena/Pillar1") == null,
			"authored interior pillar still present in room 2")
	_check(main_scene.get_node_or_null("NavRegion/Arena/Floor") == null,
			"authored floor should be retired once the procedural shell takes over")
	_check(main_scene.get_node_or_null("NavRegion/GeneratedShell/Floor") != null,
			"procedural shell floor was not built")
	_check(main_scene.get_node_or_null("NavRegion/GeneratedShell/WallN") != null,
			"procedural shell wall was not built")
	_check(not main_scene.get_node("CoverPoints/CP1").is_in_group("cover_point"),
			"authored cover marker still in the cover_point group")
	var cover_count := get_tree().get_nodes_in_group("cover_point").size()
	_check(cover_count >= 6, "expected >= 6 generated cover points, got %d" % cover_count)
	var nav_region: NavigationRegion3D = main_scene.get_node("NavRegion")
	var polygons := nav_region.navigation_mesh.get_polygon_count()
	_check(polygons >= 40, "rebaked navmesh looks degenerate (%d polygons)" % polygons)

	# 6b. Variable footprint: room 2 is a valid footprint (square / rectangular /
	# L-shaped), the spawn marker sat on the new south edge, the player landed on
	# it, and every generated obstacle is inside the walls and out of any notch.
	_check_footprint(main_scene, "room 2", spawn)

	var pickups_root: Node = main_scene.get_node("Pickups")
	var pickup_count := pickups_root.get_child_count()
	_check(pickup_count == 6, "room 2 should restock 6 pickups, got %d" % pickup_count)

	# 7. Damage upgrade math + no resource-cache leak.
	var cached: Resource = load("res://data/weapons/pistol.tres")
	var cached_damage: float = cached.get("damage")
	var datas: Array = weapon_manager.get("weapon_datas")
	var live_damage: float = (datas[0] as Resource).get("damage")
	upgrades.call("apply_upgrade", "damage")
	var boosted: float = (datas[0] as Resource).get("damage")
	_check(absf(boosted - live_damage * 1.2) < 0.001,
			"damage upgrade should multiply by 1.2 (was %s, now %s)" % [live_damage, boosted])
	_check(absf(float(cached.get("damage")) - cached_damage) < 0.001,
			"damage upgrade leaked into the cached pistol.tres resource")

	# 8. Health-drop upgrade: 3 stacks -> guaranteed drop on the next kill.
	for i in 3:
		upgrades.call("apply_upgrade", "health_drop")
	_kill(alive[0])
	await get_tree().process_frame
	_check(pickups_root.get_child_count() == pickup_count + 1,
			"kill with Scavenger stacks did not drop a health pack")

	# 9. Seeded generation is reproducible: same seed, same layout.
	var builder: Node = main_scene.get_node("RoomBuilder")
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var layout_a: Array = builder.call("_descriptors_for", "pillar_hall", rng_a)
	var layout_b: Array = builder.call("_descriptors_for", "pillar_hall", rng_b)
	_check(str(layout_a) == str(layout_b), "same seed should produce identical layouts")
	_check(not layout_a.is_empty(), "pillar_hall generator produced no obstacles")

	# 10. Clear room 2 -> reach the gate -> room 3 must be a different layout.
	for e in _alive_enemies():
		_kill(e)
	var reached2 := await _pass_through_gate(main_scene, player)
	_check(reached2, "transition never began after the room 2 gate")
	tries = 0
	while not upgrade_panel.visible and tries < 600:
		tries += 1
		await get_tree().process_frame
	_check(upgrade_panel.visible, "upgrade screen never appeared for room 3")
	if not upgrade_panel.visible:
		return
	run_hud.emit_signal("upgrade_chosen", "armor")  # the path RunDirector awaits
	var room3_ready := await _await_room_ready(7)
	_check(room3_ready, "room 3 never became ready (7 alive enemies, unpaused)")
	if not room3_ready:
		return
	_check(room_label.text == "ROOM 3", "room label should read ROOM 3, got %s" % room_label.text)
	var room3_layout := _generated_layout(main_scene)
	_check(room3_layout.length() > 0, "no generated geometry in room 3")
	_check(room3_layout != room2_layout, "room 3 layout is identical to room 2")
	var alive3 := _alive_enemies()
	for e in alive3:
		e.set("sight_range", 0.0)
	var max3: float = (alive3[0] as Node).get_node("Health").get("max_health")
	_check(absf(max3 - 120.0) < 0.01, "room 3 enemy max health should be 120, got %s" % max3)

	# 11. Permadeath: stats screen up, world frozen, run over.
	player.call("take_damage", 1000000.0, Vector3.ZERO)
	await get_tree().create_timer(0.3).timeout
	_check(run_end_result == [false],
			"run_ended(false) should fire exactly once, got %s" % str(run_end_result))
	_check(not RunManager.run_active, "run still active after player death")
	var end_panel: Control = run_hud.get_node("RunEndPanel")
	_check(end_panel.visible, "run end screen not visible after death")
	var stats: Label = run_hud.get_node("RunEndPanel/Center/Box/StatsLabel")
	_check("Rooms cleared: 2" in stats.text,
			"stats should report 2 rooms cleared, got: %s" % stats.text.replace("\n", " | "))
	_check("Enemies killed: 11" in stats.text,
			"stats should report 11 enemies killed, got: %s" % stats.text.replace("\n", " | "))
	var legacy_death: Control = main_scene.get_node("HUD/DeathScreen")
	_check(not legacy_death.visible, "legacy respawn death screen should be hidden")
	var survivors := _alive_enemies()
	_check(survivors.size() > 0 and not (survivors[0] as Node).is_physics_processing(),
			"enemies were not frozen on player death")
	var try_again: Button = run_hud.get_node("RunEndPanel/Center/Box/Buttons/TryAgain")
	_check(try_again.pressed.get_connections().size() > 0,
			"Try Again button is not wired")

	# 12. No accidental respawn: the old 3-lives flow must stay disconnected.
	await get_tree().create_timer(3.5).timeout
	_check(bool(player.get("is_dead")), "player respawned despite permadeath")
