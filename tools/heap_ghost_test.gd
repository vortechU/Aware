extends Node
## Headless test for Pass 4 of the layered world: the Heap's generation identity
## (atmosphere debris + spectral Ghost rooms + corruption-driven mood).
## Run: godot --headless --path . res://tools/heap_ghost_test.tscn
##
##  A. Pure: the Heap profile carries `corruption` + a `ghost_tint`, and sector 5
##     is a Ghost room.
##  B. Builder: a built COMBAT Heap room gets floating atmosphere debris but no
##     ghost geometry; a built GHOST room gets MORE debris, spectral geometry
##     (group ghost_geometry), and a sun mood pulled toward the ghost tint.
##     (The translucent/emissive look itself is eyeballed by playing to sector 5.)

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_part_a_pure()
	await _part_b_builder()
	if fails.is_empty():
		print("HEAP_GHOST_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HEAP_GHOST_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _cdist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


# ---------------------------------------------------------------- A. pure

func _part_a_pure() -> void:
	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	var corruption: float = heap.get("corruption", 0.0)
	_check(corruption > 0.0 and corruption <= 1.0,
			"Heap corruption should be in (0,1], got %s" % corruption)
	_check(heap.has("ghost_tint"), "Heap should define a ghost_tint")
	_check(LayerCatalog.room_type_for(5) == LayerCatalog.RoomType.GHOST,
			"Heap sector 5 should be a Ghost room")


# ---------------------------------------------------------------- B. builder

func _part_b_builder() -> void:
	RunManager.selected_mode = RunManager.RunMode.CAMPAIGN
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)  # don't let a stray shot end the run mid-test

	var builder: Node = main.get_node("RoomBuilder")
	var sun: DirectionalLight3D = main.get_node("Sun")
	var profile: Dictionary = RunManager.active_layer_profile()
	_check(not profile.is_empty(), "no Heap profile to build with")
	if profile.is_empty():
		return

	# A COMBAT Heap room: atmosphere debris present, but no ghost geometry.
	await builder.build_room(2, profile)
	var combat_debris := get_tree().get_nodes_in_group("room_debris").size()
	_check(combat_debris > 0, "a Heap combat room should spawn atmosphere debris, got %d" % combat_debris)
	_check(get_tree().get_nodes_in_group("ghost_geometry").is_empty(),
			"a combat room should have no ghost geometry")
	var combat_color: Color = sun.light_color

	# A GHOST room (sector 5): heavier atmosphere, spectral geometry, ghost mood.
	await builder.build_room(5, profile)
	var ghost_debris := get_tree().get_nodes_in_group("room_debris").size()
	_check(ghost_debris > combat_debris,
			"a Ghost room should swarm more debris than a combat room (%d vs %d)"
			% [ghost_debris, combat_debris])
	_check(get_tree().get_nodes_in_group("ghost_geometry").size() > 0,
			"a Ghost room should tag spectral ghost geometry")
	var ghost_tint: Color = profile["ghost_tint"]
	_check(_cdist(sun.light_color, ghost_tint) < _cdist(combat_color, ghost_tint),
			"the Ghost room mood should pull the sun toward the ghost tint")
