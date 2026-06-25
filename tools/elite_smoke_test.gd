extends Node
## Headless test for elite/milestone rooms.
## Run: godot --headless --path . res://tools/elite_smoke_test.tscn
## Fast-forwards by setting current_room = 4 during the first upgrade pick, so
## the next room is milestone room 5. Verifies: proving-grounds arena, elite
## stats/markers, guard composition, guaranteed elite health drops, the double
## upgrade pick, and the return to a normal room afterwards.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # transitions pause the tree
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)
	await _run(main_scene)
	if fails.is_empty():
		print("ELITE_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("ELITE_SMOKE_FAIL: ", f)
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


## A cleared room raises an exit gate; the transition only runs once the player
## passes through it. Drive that here (signal, like the other emit-driven steps).
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
	for e in enemies:
		_kill(e)

	var run_hud: CanvasLayer = main_scene.get_node("RunHUD")
	var upgrade_panel: Control = run_hud.get_node("UpgradePanel")
	var upgrade_title: Label = run_hud.get_node("UpgradePanel/Center/Box/Title")
	var room_label: Label = run_hud.get_node("RoomLabel")
	await _pass_gate(main_scene)  # reach the exit gate to start the transition
	_check(await _await_panel(upgrade_panel), "upgrade screen never appeared after room 1")
	if not upgrade_panel.visible:
		return

	# Fast-forward: the pending advance_room() lands on milestone room 5.
	RunManager.current_room = 4
	run_hud.emit_signal("upgrade_chosen", "armor")

	# Milestone room 5: 1 elite + ceil(9/2)=5 guards.
	var expected: int = RunManager.enemy_count_for_room(5)
	_check(expected == 6, "room 5 milestone count should be 6, got %d" % expected)
	_check(await _await_room_ready(expected), "milestone room 5 never became ready")
	if _alive_enemies().size() != expected:
		return
	_check(room_label.text == "ROOM 5", "room label should read ROOM 5, got %s" % room_label.text)
	var builder: Node = main_scene.get_node("RoomBuilder")
	_check(str(builder.get("last_archetype")) == "proving_grounds",
			"milestone room should use proving_grounds, got %s" % builder.get("last_archetype"))

	# Elite composition and stats (room 5 multiplier = 1.4).
	var elite: Node = null
	var guards := []
	for e in _alive_enemies():
		e.set("sight_range", 0.0)
		if (e as Node).has_meta("elite"):
			_check(elite == null, "more than one elite spawned")
			elite = e
		else:
			guards.append(e)
	_check(elite != null, "no elite found in milestone room")
	if elite == null:
		return
	var elite_max: float = elite.get_node("Health").get("max_health")
	_check(absf(elite_max - 700.0) < 0.01, "elite max health should be 700, got %s" % elite_max)
	var elite_damage: float = elite.get("shot_damage")
	_check(absf(elite_damage - 22.4) < 0.01, "elite shot_damage should be 22.4, got %s" % elite_damage)
	_check(int(elite.get("burst_count")) == 5, "elite burst_count should be 5")
	var visual := elite.get_node("Visual") as Node3D
	_check(absf(visual.scale.x - 1.25) < 0.01, "elite visual not broadened")
	_check(guards.size() == 5, "expected 5 guards, got %d" % guards.size())
	if not guards.is_empty():
		var guard_max: float = (guards[0] as Node).get_node("Health").get("max_health")
		_check(absf(guard_max - 140.0) < 0.01,
				"guard max health should be 140 (normal scaling), got %s" % guard_max)

	# Elite death drops a guaranteed care package (2 health packs).
	var pickups_root: Node = main_scene.get_node("Pickups")
	var pickups_before := pickups_root.get_child_count()
	_kill(elite)
	await get_tree().process_frame
	_check(pickups_root.get_child_count() == pickups_before + 2,
			"elite death should drop 2 health packs (had %d, now %d)"
			% [pickups_before, pickups_root.get_child_count()])

	# Clearing the milestone room grants TWO upgrade picks.
	for guard in guards:
		_kill(guard)
	await _pass_gate(main_scene)  # reach the exit gate to start the transition
	_check(await _await_panel(upgrade_panel), "upgrade screen never appeared after milestone clear")
	if not upgrade_panel.visible:
		return
	_check("1 OF 2" in upgrade_title.text,
			"first milestone pick should be titled 1 OF 2, got: %s" % upgrade_title.text)
	run_hud.emit_signal("upgrade_chosen", "max_health")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(upgrade_panel.visible, "second milestone upgrade pick never appeared")
	_check("2 OF 2" in upgrade_title.text,
			"second milestone pick should be titled 2 OF 2, got: %s" % upgrade_title.text)
	run_hud.emit_signal("upgrade_chosen", "stamina")

	# Room 6 returns to the normal rotation: no elite, 10 enemies at 1.5x. It now
	# also contains archetypes (a sniper + rushers), so check a PLAIN enemy's
	# health rather than assuming index 0 is a regular.
	_check(await _await_room_ready(10), "room 6 never became ready (10 enemies)")
	if _alive_enemies().size() == 10:
		var room6 := _alive_enemies()
		var plain: Node = null
		for e in room6:
			e.set("sight_range", 0.0)
			_check(not (e as Node).has_meta("elite"), "room 6 should have no elite")
			if plain == null and not (e as Node).has_meta("rusher") \
					and not (e as Node).has_meta("sniper") \
					and not (e as Node).has_meta("grenadier"):
				plain = e
		_check(plain != null, "room 6 should still contain plain enemies")
		if plain != null:
			var max6: float = plain.get_node("Health").get("max_health")
			_check(absf(max6 - 150.0) < 0.01,
					"room 6 plain enemy max health should be 150, got %s" % max6)
	_check(str(builder.get("last_archetype")) != "proving_grounds",
			"room 6 should not reuse the milestone arena")
	_check(RunManager.current_run_modifiers.size() == 3,
			"3 upgrades should be recorded (1 + milestone 2), got %d"
			% RunManager.current_run_modifiers.size())
