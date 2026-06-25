extends Node
## Headless test for Pass 2 of the layered world: the Heap room-type taxonomy.
## Run: godot --headless --path . res://tools/heap_rooms_test.tscn
##
##  A. Pure: the Heap's room_sequence maps sectors to types (3 = Fragment, 5 =
##     Ghost, rest Combat); ENDLESS is always Combat; CAMPAIGN suppresses the
##     every-5th milestone while ENDLESS keeps it.
##  B. Scene: a real CAMPAIGN run -- room 2 is a built COMBAT room (a scaled squad
##     spawns), and clearing through to room 3 lands on the FRAGMENT breather: no
##     enemies, the exit gate already up, and a placeholder narrative marker.

var fails: Array[String] = []
var cleared_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RunManager.room_cleared.connect(func() -> void: cleared_count += 1)
	_part_a_pure()
	await _part_b_scene()
	if fails.is_empty():
		print("HEAP_ROOMS_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HEAP_ROOMS_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


# ---------------------------------------------------------------- A. pure

func _part_a_pure() -> void:
	var T := LayerCatalog.RoomType
	var expect := [T.COMBAT, T.COMBAT, T.FRAGMENT, T.COMBAT, T.GHOST, T.COMBAT]
	for sector in range(1, 7):
		_check(LayerCatalog.room_type_for(sector) == expect[sector - 1],
				"Heap sector %d should be type %d, got %d"
				% [sector, expect[sector - 1], LayerCatalog.room_type_for(sector)])

	# ENDLESS: always combat, and the every-5th milestone still fires.
	RunManager.run_mode = RunManager.RunMode.ENDLESS
	_check(RunManager.current_room_type() == T.COMBAT, "endless rooms should all be combat")
	_check(RunManager.is_milestone_room(5), "endless room 5 should still be a milestone")
	# CAMPAIGN: no every-5th milestone (layers gate progress with their own rooms).
	RunManager.run_mode = RunManager.RunMode.CAMPAIGN
	_check(not RunManager.is_milestone_room(5),
			"campaign should suppress the every-5th milestone")
	RunManager.run_mode = RunManager.RunMode.ENDLESS  # leave clean for the scene phase


# ---------------------------------------------------------------- B. scene

func _part_b_scene() -> void:
	RunManager.selected_mode = RunManager.RunMode.CAMPAIGN
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)

	# Room 1: wait for GameManager's squad + RunDirector adoption, then blind + clear.
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	_check(RunManager.run_mode == RunManager.RunMode.CAMPAIGN, "scene run is not campaign")
	_blind(get_tree().get_nodes_in_group("enemies"))
	for e in _alive_enemies():
		_kill(e)

	var run_hud: CanvasLayer = main.get_node("RunHUD")
	var upgrade_panel: Control = run_hud.get_node("UpgradePanel")

	# Room 1 -> 2: cross the gate, take the upgrade. Room 2 is a built CAMPAIGN
	# COMBAT room, so a scaled squad must spawn (proves combat still works campaign).
	if not await _pass_through_gate(main, player):
		_check(false, "transition never began after the room 1 gate")
		return
	if not await _take_upgrade(run_hud, upgrade_panel):
		_check(false, "upgrade screen never appeared leaving room 1")
		return
	if not await _await_combat_ready(6):
		_check(false, "room 2 never became a live 6-enemy combat room")
		return
	_check(RunManager.current_room == 2, "should be on room 2, got %d" % RunManager.current_room)
	_check(RunManager.current_room_type() == LayerCatalog.RoomType.COMBAT,
			"Heap sector 2 should be a combat room")
	_check(get_tree().get_nodes_in_group("narrative_marker").is_empty(),
			"a combat room should not place a narrative marker")
	_blind(_alive_enemies())
	for e in _alive_enemies():
		_kill(e)

	# Room 2 -> 3: cross the gate, take the upgrade. Room 3 is the FRAGMENT breather.
	if not await _pass_through_gate(main, player):
		_check(false, "transition never began after the room 2 gate")
		return
	if not await _take_upgrade(run_hud, upgrade_panel):
		_check(false, "upgrade screen never appeared leaving room 2")
		return
	if not await _await_narrative_ready(main):
		_check(false, "room 3 never became a live non-combat room with an exit gate")
		return
	_check(RunManager.current_room == 3, "should be on room 3, got %d" % RunManager.current_room)
	_check(RunManager.current_room_type() == LayerCatalog.RoomType.FRAGMENT,
			"Heap sector 3 should be a fragment room")
	_check(_alive_enemies().is_empty(), "a fragment room should spawn no enemies")
	_check(main.get_node_or_null("ExitGate") != null,
			"the fragment room's exit gate should be up on arrival")
	_check(get_tree().get_nodes_in_group("fragment_room").size() >= 1,
			"the fragment room should drop a fragment marker")
	# The room is still a real, built arena (geometry present), just empty of foes.
	_check(main.get_node_or_null("NavRegion/GeneratedRoom") != null
			and main.get_node("NavRegion/GeneratedRoom").get_child_count() > 0,
			"the fragment room should still build real geometry")


# ---------------------------------------------------------------- helpers

func _alive_enemies() -> Array:
	var alive := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if int(e.get("state")) != 7:  # EnemyAI.State.DEAD
			alive.append(e)
	return alive


func _blind(enemies: Array) -> void:
	for e in enemies:
		e.set("sight_range", 0.0)


func _kill(enemy: Node) -> void:
	enemy.get_node("BodyHitbox").call("take_hit", 100000.0, Vector3.ZERO)


func _take_upgrade(run_hud: CanvasLayer, upgrade_panel: Control) -> bool:
	var tries := 0
	while not upgrade_panel.visible and tries < 600:
		tries += 1
		await get_tree().process_frame
	if not upgrade_panel.visible:
		return false
	run_hud.emit_signal("upgrade_chosen", "armor")  # the path RunDirector awaits
	return true


func _await_combat_ready(count: int, max_frames := 1800) -> bool:
	var tries := 0
	while tries < max_frames:
		if not get_tree().paused and _alive_enemies().size() == count:
			return true
		tries += 1
		await get_tree().process_frame
	return false


func _await_narrative_ready(main: Node, max_frames := 1800) -> bool:
	var tries := 0
	while tries < max_frames:
		if not get_tree().paused and _alive_enemies().is_empty() \
				and main.get_node_or_null("ExitGate") != null:
			return true
		tries += 1
		await get_tree().process_frame
	return false


## Drive the player into the current exit gate until the transition begins (copied
## from run_smoke: hold them on it, fall back to the signal if the overlap is slow).
func _pass_through_gate(main: Node, player: Node) -> bool:
	var gate: Node = null
	var tries := 0
	while gate == null and tries < 300:
		gate = main.get_node_or_null("ExitGate")
		tries += 1
		await get_tree().process_frame
	if gate == null:
		return false
	tries = 0
	while tries < 600 and not get_tree().paused:
		if is_instance_valid(gate):
			(player as Node3D).global_position = (gate as Node3D).global_position
		tries += 1
		await get_tree().physics_frame
	if not get_tree().paused and is_instance_valid(gate):
		gate.emit_signal("player_entered")
	tries = 0
	while not get_tree().paused and tries < 200:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().paused
