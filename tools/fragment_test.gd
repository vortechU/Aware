extends Node
## Headless test for Pass 3 of the layered world: the Fragment system.
## Run: godot --headless --path . res://tools/fragment_test.tscn
##
##  A. FragmentDB (pure): the Awakening arc reveals in order -- pick_for_arc returns
##     the first uncollected entry, advancing as they are collected; collected
##     state tracks. (Snapshots + restores user://fragments.cfg so real progress
##     is never touched.)
##  B. Scene: a CAMPAIGN run reaches the Fragment room; a real MemoryFragment sits
##     there. Walking the player into it records the fragment (FragmentDB), fires
##     GameEvents.fragment_read, and shows it in the FragmentReader overlay.

var fails: Array[String] = []
var read_ids: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.fragment_read.connect(func(f: Dictionary) -> void: read_ids.append(f.get("id", "")))
	var snapshot: Dictionary = FragmentDB.collected.duplicate()
	_part_a_db()
	await _part_b_scene()
	# Restore the player's real collected set + on-disk save.
	FragmentDB.collected = snapshot
	FragmentDB.call("_save")
	if fails.is_empty():
		print("FRAGMENT_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("FRAGMENT_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


# ---------------------------------------------------------------- A. db

func _part_a_db() -> void:
	FragmentDB.collected.clear()
	var arc := FragmentDB.arc_fragments("awakening")
	_check(arc.size() >= 2, "expected at least 2 awakening fragments, got %d" % arc.size())
	if arc.size() < 2:
		return
	# First pick is the first uncollected entry; collecting it advances the reveal.
	var first: Dictionary = FragmentDB.pick_for_arc("awakening", 1)
	_check(first.id == arc[0].id, "first awakening pick should be %s, got %s" % [arc[0].id, first.id])
	FragmentDB.mark_collected(first.id)
	_check(FragmentDB.is_collected(first.id), "fragment should read as collected after marking")
	_check(FragmentDB.collected_count() == 1, "collected_count should be 1, got %d"
			% FragmentDB.collected_count())
	var second: Dictionary = FragmentDB.pick_for_arc("awakening", 1)
	_check(second.id == arc[1].id, "after collecting the first, pick should advance to %s, got %s"
			% [arc[1].id, second.id])


# ---------------------------------------------------------------- B. scene

func _part_b_scene() -> void:
	FragmentDB.collected.clear()  # deterministic: the room surfaces the first arc entry
	read_ids.clear()
	RunManager.selected_mode = RunManager.RunMode.CAMPAIGN
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)

	# Room 1: wait for the squad, blind + clear it.
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

	# Cross the room-1 gate, then fast-forward so the pending advance lands on the
	# Heap's Fragment room (sector 3) -- skipping the room-2 build for speed.
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
	RunManager.current_room = 2  # advance_room() will tick this to 3 = FRAGMENT
	run_hud.emit_signal("upgrade_chosen", "armor")

	# Wait for the fragment room: unpaused, no enemies, gate up, a MemoryFragment present.
	tries = 0
	var frag: MemoryFragment = null
	while tries < 1800:
		if not get_tree().paused and main.get_node_or_null("ExitGate") != null:
			frag = _find_fragment()
			if frag != null:
				break
		tries += 1
		await get_tree().process_frame
	_check(RunManager.current_room == 3, "should be on room 3, got %d" % RunManager.current_room)
	_check(RunManager.current_room_type() == LayerCatalog.RoomType.FRAGMENT,
			"Heap sector 3 should be a fragment room")
	_check(frag != null, "no MemoryFragment spawned in the fragment room")
	if frag == null:
		return
	var frag_id := frag.fragment_id()
	_check(not frag_id.is_empty(), "the spawned fragment has no id")

	var reader: Node = main.get_node_or_null("FragmentReader")
	_check(reader != null, "FragmentReader overlay was never created")
	_check(not (reader as CanvasLayer).visible, "reader should be hidden before the fragment is read")

	# Walk the player into the fragment (it sits at room centre). Hold position over
	# physics frames so the Area3D overlap fires; fall back to the entry handler.
	var frag_pos: Vector3 = frag.global_position
	tries = 0
	while tries < 240 and not FragmentDB.is_collected(frag_id):
		(player as Node3D).global_position = Vector3(frag_pos.x,
				(player as Node3D).global_position.y, frag_pos.z)
		tries += 1
		await get_tree().physics_frame
	if not FragmentDB.is_collected(frag_id) and is_instance_valid(frag):
		frag.call("_on_body_entered", player)  # fallback if the overlap never fired
		await get_tree().process_frame

	_check(FragmentDB.is_collected(frag_id), "reaching the fragment did not record it")
	_check(frag_id in read_ids, "GameEvents.fragment_read did not fire for %s" % frag_id)
	if reader != null:
		_check((reader as CanvasLayer).visible, "the reader did not show after reading the fragment")
		_check((reader.get("last_fragment") as Dictionary).get("id", "") == frag_id,
				"the reader is showing the wrong fragment")


# ---------------------------------------------------------------- helpers

func _find_fragment() -> MemoryFragment:
	for node in get_tree().get_nodes_in_group("fragment_room"):
		if node is MemoryFragment:
			return node
	return null


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
