extends Node
## Headless test for the Sniper enemy archetype (SNIPER_SMOKE_OK).
## Run: godot --headless --path . res://tools/sniper_smoke_test.tscn
##
## Two layers, like the rusher test:
##  - pure composition curve on RunManager: snipers start at room 4, none in
##    milestone rooms, ramp slowly, hard-capped, deterministic, and never overlap
##    the rusher slots.
##  - real spawn: fast-forwards to room 4 (the first sniper room), inspects the
##    spawned sniper's long-range tuning + cold look vs a regular squadmate, and
##    drives its CHARGED-SHOT behaviour on a tiny test floor: it telegraphs a beam,
##    does NOT fire instantly, then lands its locked shot on a stationary player.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # transitions pause the tree
	_check_composition()
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)
	await _run(main_scene)
	if fails.is_empty():
		print("SNIPER_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("SNIPER_SMOKE_FAIL: ", f)
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


## Pure curve: none early / in milestones, ramps, capped, deterministic, and the
## sniper + rusher slots together never exceed (and never fill) the squad.
func _check_composition() -> void:
	_check(RunManager.sniper_count_for_room(1) == 0, "room 1 should have no snipers")
	_check(RunManager.sniper_count_for_room(3) == 0, "room 3 should have no snipers")
	_check(RunManager.sniper_count_for_room(4) >= 1, "room 4 should introduce a sniper")
	_check(RunManager.sniper_count_for_room(5) == 0, "milestone room 5 should have no snipers")
	_check(RunManager.sniper_count_for_room(10) == 0, "milestone room 10 should have no snipers")
	for room in range(4, 50):
		if RunManager.is_milestone_room(room):
			continue
		var sc: int = RunManager.sniper_count_for_room(room)
		var rc: int = RunManager.rusher_count_for_room(room)
		var squad: int = RunManager.enemy_count_for_room(room)
		_check(sc >= 1 and sc <= RunManager.SNIPER_MAX,
				"room %d sniper count %d out of range" % [room, sc])
		_check(sc + rc <= squad, "room %d archetype slots (%d+%d) exceed squad %d"
				% [room, sc, rc, squad])
		_check(sc + rc < squad, "room %d should keep some plain enemies" % room)
		_check(sc == RunManager.sniper_count_for_room(room),
				"sniper count for room %d is not deterministic" % room)


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

	# Fast-forward: the pending advance_room() lands on room 4 (first sniper room).
	RunManager.current_room = 3
	run_hud.emit_signal("upgrade_chosen", "armor")

	var expected: int = RunManager.enemy_count_for_room(4)  # 8
	_check(expected == 8, "room 4 squad should be 8, got %d" % expected)
	_check(await _await_room_ready(expected), "room 4 never became ready")
	if _alive_enemies().size() != expected:
		return
	_check(room_label.text == "ROOM 4", "room label should read ROOM 4, got %s" % room_label.text)

	# Pull out the sniper and a plain squadmate (not the rusher) for comparison.
	var sniper: Node = null
	var regular: Node = null
	for e in _alive_enemies():
		if (e as Node).has_meta("sniper"):
			_check(sniper == null, "room 4 should spawn exactly one sniper")
			sniper = e
		elif not (e as Node).has_meta("rusher") and regular == null:
			regular = e
	_check(sniper != null, "no sniper found in room 4")
	_check(regular != null, "no plain enemy found to compare against")
	if sniper == null or regular == null:
		return

	# --- Long-range tuning vs a regular squadmate. ---
	_check(bool(sniper.get("is_sniper")), "sniper is_sniper flag not set")
	_check(absf(float(sniper.get("sight_range")) - 60.0) < 0.01,
			"sniper sight_range should be 60, got %s" % sniper.get("sight_range"))
	_check(absf(float(sniper.get("attack_range")) - 40.0) < 0.01,
			"sniper attack_range should be 40, got %s" % sniper.get("attack_range"))
	_check(float(sniper.get("attack_range")) > float(regular.get("attack_range")),
			"sniper should fight from farther than a regular enemy")
	_check(float(sniper.get("aim_spread_deg")) < float(regular.get("aim_spread_deg")),
			"sniper should aim tighter than a regular enemy")
	_check(absf(float(sniper.get("combat_speed")) - float(regular.get("combat_speed")) * 0.9) < 0.01,
			"sniper should move at 0.9x a regular enemy")
	var s_dmg: float = sniper.get("shot_damage")
	var n_dmg: float = regular.get("shot_damage")
	_check(absf(s_dmg - n_dmg * 3.0) < 0.01,
			"sniper shot should hit 3x a regular's (%.2f vs %.2f)" % [s_dmg, n_dmg])
	var s_hp: float = sniper.get_node("Health").get("max_health")
	var n_hp: float = regular.get_node("Health").get("max_health")
	_check(absf(s_hp - n_hp * 0.85) < 0.01,
			"sniper max health should be 0.85x regular (%.1f vs %.1f)" % [s_hp, n_hp])

	# --- Cold cyan look (taller/leaner) + matching hitbox. ---
	var visual: Node3D = sniper.get_node("Visual")
	_check(absf(visual.scale.x - 0.85) < 0.01 and absf(visual.scale.z - 0.85) < 0.01,
			"sniper should be narrowed to 0.85 XZ, got %s" % str(visual.scale))
	_check(absf(visual.scale.y - 1.1) < 0.01, "sniper should be a touch taller (1.1 Y)")
	var body_override: Material = (sniper.get_node("Visual/Body") as MeshInstance3D).material_override
	_check(body_override != null, "sniper body has no material override for the cyan look")
	var c := Color.WHITE
	if body_override is ShaderMaterial:
		var param: Variant = (body_override as ShaderMaterial).get_shader_parameter("albedo")
		if param is Color:
			c = param
	elif body_override is StandardMaterial3D:
		c = (body_override as StandardMaterial3D).albedo_color
	_check(c.b > 0.4 and c.r < 0.4 and c.b > c.r, "sniper body should be cold cyan, got %s" % str(c))
	var s_shape := (sniper.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D).shape as CapsuleShape3D
	var n_shape := (regular.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D).shape as CapsuleShape3D
	_check(absf(s_shape.radius - n_shape.radius * 0.85) < 0.01,
			"sniper hitbox should be narrowed to match (%.3f vs %.3f)" % [s_shape.radius, n_shape.radius])
	_check(s_shape != n_shape, "sniper must duplicate the shared hitbox shape, not mutate it")

	# --- Behaviour: charged + telegraphed shot on a stationary player. ---
	# Stand both on a tiny floor high above the room so geometry can't block LoS
	# and neither falls; blind the rest so only the sniper reacts.
	for e in _alive_enemies():
		if e != sniper:
			e.set("sight_range", 0.0)
	# Widen the FOV so the patrol-wander re-facing can't drop the player out of the
	# vision cone before the sniper locks on (we're testing the charged shot here).
	sniper.set("sight_half_fov_deg", 360.0)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 1, 24)
	cs.shape = box
	floor.add_child(cs)
	main_scene.add_child(floor)
	floor.global_position = Vector3(0, 39.0, -2.5)  # top at y=39.5

	var player: Node3D = get_tree().get_first_node_in_group("player")
	var sz := sniper as Node3D
	sz.global_position = Vector3(0, 39.8, 0)
	player.global_position = Vector3(0, 39.8, -5)  # 5 m in front, on the line
	sz.look_at(player.global_position, Vector3.UP)
	var hp_before: float = player.get("health")

	var saw_charge := false
	var saw_beam := false
	var fired_frame := -1
	var f := 0
	while f < 220:
		if bool(sniper.get("_sniper_charging")):
			saw_charge = true
			var beam = sniper.get("_sniper_beam")
			if beam != null and (beam as Node3D).visible:
				saw_beam = true
		if fired_frame < 0 and float(sniper.get("_sniper_cooldown")) > 0.0:
			fired_frame = f
			break
		f += 1
		await get_tree().physics_frame

	_check(saw_charge, "sniper never charged a shot (no telegraph)")
	_check(saw_beam, "sniper telegraph beam never became visible")
	_check(fired_frame >= 0, "sniper never fired within the test window")
	_check(fired_frame < 0 or fired_frame >= 30,
			"sniper fired too fast (frame %d) -- the charge telegraph is missing" % fired_frame)
	# Settle a frame so the hitscan's take_damage applies, then confirm the locked
	# shot connected with the stationary player.
	await get_tree().physics_frame
	var hp_after: float = player.get("health")
	_check(hp_after < hp_before,
			"sniper's locked shot should hit a player standing in the lane (%.1f -> %.1f)"
			% [hp_before, hp_after])
