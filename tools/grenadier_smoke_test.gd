extends Node
## Headless test for the Grenadier enemy archetype (GRENADIER_SMOKE_OK).
## Run: godot --headless --path . res://tools/grenadier_smoke_test.tscn
##
## Two layers, like the rusher/sniper tests:
##  - pure composition curve on RunManager: grenadiers start at room 6, none in
##    milestone rooms, ramp slowly, hard-capped, deterministic, and the three
##    archetype slots together never fill the squad.
##  - real spawn: fast-forwards to room 6 (the first grenadier room), inspects the
##    grenadier's mid-range tuning + bulky olive look vs a regular squadmate, then
##    drives a full throw on a tiny test floor: it winds up, lobs a grenade that
##    arcs and explodes, and the blast damages a player standing on the spot.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # transitions pause the tree
	_check_composition()
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)
	await _run(main_scene)
	if fails.is_empty():
		print("GRENADIER_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("GRENADIER_SMOKE_FAIL: ", f)
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


## Pure curve: none early / in milestones, ramps, capped, deterministic, and all
## three archetype slots together never fill (or exceed) the squad.
func _check_composition() -> void:
	_check(RunManager.grenadier_count_for_room(1) == 0, "room 1 should have no grenadiers")
	_check(RunManager.grenadier_count_for_room(4) == 0, "room 4 should have no grenadiers")
	_check(RunManager.grenadier_count_for_room(5) == 0, "milestone room 5 should have no grenadiers")
	_check(RunManager.grenadier_count_for_room(6) >= 1, "room 6 should introduce a grenadier")
	_check(RunManager.grenadier_count_for_room(10) == 0, "milestone room 10 should have no grenadiers")
	for room in range(6, 60):
		if RunManager.is_milestone_room(room):
			continue
		var gc: int = RunManager.grenadier_count_for_room(room)
		var sc: int = RunManager.sniper_count_for_room(room)
		var rc: int = RunManager.rusher_count_for_room(room)
		var squad: int = RunManager.enemy_count_for_room(room)
		_check(gc >= 1 and gc <= RunManager.GRENADIER_MAX,
				"room %d grenadier count %d out of range" % [room, gc])
		_check(sc + gc + rc < squad,
				"room %d archetype slots (%d+%d+%d) leave no plain enemies of %d"
				% [room, sc, gc, rc, squad])
		_check(gc == RunManager.grenadier_count_for_room(room),
				"grenadier count for room %d is not deterministic" % room)


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

	# Fast-forward: the pending advance_room() lands on room 6 (first grenadier room).
	RunManager.current_room = 5
	run_hud.emit_signal("upgrade_chosen", "armor")

	var expected: int = RunManager.enemy_count_for_room(6)  # 10
	_check(expected == 10, "room 6 squad should be 10, got %d" % expected)
	_check(await _await_room_ready(expected), "room 6 never became ready")
	if _alive_enemies().size() != expected:
		return
	_check(room_label.text == "ROOM 6", "room label should read ROOM 6, got %s" % room_label.text)

	# Pull out the grenadier and a plain squadmate (no archetype meta) to compare.
	var grenadier: Node = null
	var regular: Node = null
	for e in _alive_enemies():
		if (e as Node).has_meta("grenadier"):
			_check(grenadier == null, "room 6 should spawn exactly one grenadier")
			grenadier = e
		elif regular == null and not (e as Node).has_meta("rusher") \
				and not (e as Node).has_meta("sniper"):
			regular = e
	_check(grenadier != null, "no grenadier found in room 6")
	_check(regular != null, "no plain enemy found to compare against")
	if grenadier == null or regular == null:
		return

	# --- Area-denial tuning vs a regular squadmate. ---
	_check(bool(grenadier.get("is_grenadier")), "grenadier is_grenadier flag not set")
	_check(absf(float(grenadier.get("attack_range")) - 20.0) < 0.01,
			"grenadier attack_range should be 20, got %s" % grenadier.get("attack_range"))
	_check(absf(float(grenadier.get("grenade_radius")) - 4.5) < 0.01,
			"grenadier blast radius should be 4.5, got %s" % grenadier.get("grenade_radius"))
	var g_blast: float = grenadier.get("grenade_damage")
	var n_dmg: float = regular.get("shot_damage")
	_check(absf(g_blast - n_dmg * 3.0) < 0.01,
			"grenade blast should be 3x a regular's shot (%.2f vs %.2f)" % [g_blast, n_dmg])
	var g_hp: float = grenadier.get_node("Health").get("max_health")
	var n_hp: float = regular.get_node("Health").get("max_health")
	_check(absf(g_hp - n_hp * 1.15) < 0.01,
			"grenadier max health should be 1.15x regular (%.1f vs %.1f)" % [g_hp, n_hp])

	# --- Bulky olive look + matching widened hitbox. ---
	var visual: Node3D = grenadier.get_node("Visual")
	_check(absf(visual.scale.x - 1.15) < 0.01 and absf(visual.scale.z - 1.15) < 0.01,
			"grenadier should be broadened to 1.15 XZ, got %s" % str(visual.scale))
	_check(absf(visual.scale.y - 1.0) < 0.01, "grenadier height should be unchanged")
	var body_override: Material = (grenadier.get_node("Visual/Body") as MeshInstance3D).material_override
	_check(body_override != null, "grenadier body has no material override for the olive look")
	var c := Color.WHITE
	if body_override is ShaderMaterial:
		var param: Variant = (body_override as ShaderMaterial).get_shader_parameter("albedo")
		if param is Color:
			c = param
	elif body_override is StandardMaterial3D:
		c = (body_override as StandardMaterial3D).albedo_color
	_check(c.g > 0.4 and c.g > c.r and c.g > c.b, "grenadier body should be olive green, got %s" % str(c))
	var g_shape := (grenadier.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D).shape as CapsuleShape3D
	var n_shape := (regular.get_node("BodyHitbox/BodyHitShape") as CollisionShape3D).shape as CapsuleShape3D
	_check(absf(g_shape.radius - n_shape.radius * 1.15) < 0.01,
			"grenadier hitbox should be widened to match (%.3f vs %.3f)" % [g_shape.radius, n_shape.radius])
	_check(g_shape != n_shape, "grenadier must duplicate the shared hitbox shape, not mutate it")

	# --- Behaviour: winds up, lobs a grenade that explodes and blasts the player. ---
	for e in _alive_enemies():
		if e != grenadier:
			e.set("sight_range", 0.0)
	grenadier.set("sight_half_fov_deg", 360.0)  # avoid patrol-wander cone flakiness
	# Stand both on a tiny floor high above the room: clean LoS, neither falls, and
	# the grenade has ground to land on and explode against.
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
	var gz := grenadier as Node3D
	gz.global_position = Vector3(0, 39.8, 0)
	player.global_position = Vector3(0, 39.8, -6)  # within mid range, in the open
	gz.look_at(player.global_position, Vector3.UP)
	var hp_before: float = player.get("health")

	var saw_windup := false
	var saw_grenade := false
	var got_blasted := false
	var f := 0
	while f < 260:
		if bool(grenadier.get("_gren_winding")):
			saw_windup = true
		if not get_tree().get_nodes_in_group("enemy_grenade").is_empty():
			saw_grenade = true
		if float(player.get("health")) < hp_before:
			got_blasted = true
			break
		f += 1
		await get_tree().physics_frame

	_check(saw_windup, "grenadier never telegraphed a throw (no wind-up)")
	_check(saw_grenade, "grenadier never spawned a grenade")
	_check(got_blasted,
			"the grenade blast should damage a player standing on the spot (health stayed %.1f)"
			% hp_before)
