extends Node
## Headless test for Pass 5a of the layered world: the layer descent (Heap -> Stack).
## Run: godot --headless --path . res://tools/descent_test.tscn
##
##  A. Pure: a second layer (The Stack) exists; rooms 7..12 map to it (sector 1 at
##     room 7), the Heap/Stack boundary is right, the Stack is rectangular-only and
##     surfaces the History arc.
##  B. Scene: a CAMPAIGN run crossing the Heap's last sector descends into the
##     Stack -- current_layer ticks to 2, the active profile becomes the Stack, the
##     HUD reads STACK, and the built room uses a Stack archetype + rectangular shell.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_part_a_pure()
	await _part_b_scene()
	if fails.is_empty():
		print("DESCENT_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("DESCENT_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


# ---------------------------------------------------------------- A. pure

func _part_a_pure() -> void:
	_check(LayerCatalog.LAYERS.size() >= 2, "a second layer (the Stack) should be defined")
	_check(LayerCatalog.profile_for_room(7).id == "stack", "room 7 should be the Stack")
	_check(LayerCatalog.layer_index_for_room(7) == 2, "room 7 should be layer 2")
	_check(LayerCatalog.room_in_layer_for_room(7) == 1, "room 7 should be Stack sector 1")
	# Boundary: room 6 is the Heap's last sector.
	_check(LayerCatalog.profile_for_room(6).id == "heap", "room 6 should still be the Heap")
	_check(LayerCatalog.room_in_layer_for_room(6) == 6, "room 6 should be Heap sector 6")

	var stack: Dictionary = LayerCatalog.profile_for_room(7)
	_check(stack.get("arc", "") == "history", "the Stack should surface the History arc")
	_check(FragmentDB.arc_fragments("history").size() >= 1, "the History arc needs fragments")
	for idx in stack.get("footprint_pool", []):
		# Indices 6+ are L-shapes in RoomBuilder's combined list; the Stack has none.
		_check(int(idx) < 6, "the Stack should be rectangular-only, saw footprint index %d" % int(idx))


# ---------------------------------------------------------------- B. scene

func _part_b_scene() -> void:
	RunManager.selected_mode = RunManager.RunMode.CAMPAIGN
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)

	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)
	for e in _alive_enemies():
		_kill(e)

	var run_hud: CanvasLayer = main.get_node("RunHUD")
	var upgrade_panel: Control = run_hud.get_node("UpgradePanel")

	# Cross the room-1 gate, then fast-forward so the pending advance crosses the
	# Heap/Stack boundary (room 6 -> 7) -- the descent.
	if not await _pass_through_gate(main, player):
		_check(false, "transition never began after the room 1 gate")
		return
	tries = 0
	while not upgrade_panel.visible and tries < 600:
		tries += 1
		await get_tree().process_frame
	if not upgrade_panel.visible:
		_check(false, "upgrade screen never appeared")
		return
	RunManager.current_room = 6  # advance_room() will tick this to 7 = Stack sector 1
	run_hud.emit_signal("upgrade_chosen", "armor")

	# Wait for the Stack room: unpaused, on room 7, with a live squad.
	tries = 0
	while tries < 2400:
		if not get_tree().paused and RunManager.current_room == 7 and _alive_enemies().size() >= 1:
			break
		tries += 1
		await get_tree().process_frame

	_check(RunManager.current_room == 7, "should be on room 7, got %d" % RunManager.current_room)
	_check(RunManager.current_layer == 2, "descent should put the run in layer 2, got %d"
			% RunManager.current_layer)
	_check(RunManager.room_in_layer == 1, "room 7 should read as Stack sector 1, got %d"
			% RunManager.room_in_layer)
	_check(RunManager.active_layer_profile().get("id", "") == "stack",
			"the active profile after descent should be the Stack")
	var room_label: Label = main.get_node("RunHUD/RoomLabel")
	_check("STACK" in room_label.text, "the room label should name the Stack, got '%s'" % room_label.text)

	# The built room used a Stack archetype + a rectangular shell (no L-notch).
	var builder: Node = main.get_node("RoomBuilder")
	var stack_pool: Array = LayerCatalog.profile_for_room(7).archetype_pool
	_check(builder.get("last_archetype") in stack_pool,
			"the Stack room used archetype '%s', not in the Stack pool" % builder.get("last_archetype"))
	_check((builder.get("_notch") as Vector2) == Vector2.ZERO,
			"the Stack room should be rectangular (no L-notch)")


# ---------------------------------------------------------------- helpers

func _alive_enemies() -> Array:
	var alive := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if int(e.get("state")) != 7:  # EnemyAI.State.DEAD
			alive.append(e)
	return alive


func _kill(enemy: Node) -> void:
	enemy.get_node("BodyHitbox").call("take_hit", 100000.0, Vector3.ZERO)


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
