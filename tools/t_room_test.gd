extends Node
## Stronger shape contrast Pass 2: the T-shaped footprint family.
## Run: godot --headless --path . res://tools/t_room_test.tscn
##
## A T is the natural extension of the L (an L is one north-corner notch; a T is
## both), giving a wide south crossbar (player spawn) + a narrow north stem (the
## exit gate). This forces a T room through the REAL build_room pipeline and asserts:
##   - the picker exposes T-shapes; the combined-index split still holds.
##   - the room builds + validates OK (reachable squad + cover fit the T).
##   - BOTH bare north corners are genuine holes (no navmesh there), while the body
##     centre AND the north stem are on the navmesh and reachable from the spawn
##     (i.e. the crossbar actually connects to the stem).
##   - no obstacle / enemy spawn / pickup lands in either bare corner.
##   - determinism: a fixed seed reproduces the same T.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("T_ROOM_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("T_ROOM_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _reachable(map: RID, start: Vector3, p: Vector3) -> bool:
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, p)
	if snapped.distance_to(p) > 1.5:
		return false
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, snapped, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(snapped) < 1.5


func _in_any_notch(notches: Array, x: float, z: float) -> bool:
	for n in notches:
		var nmin: Vector2 = n.min
		var nmax: Vector2 = n.max
		if x > nmin.x and x < nmax.x and z > nmin.y and z < nmax.y:
			return true
	return false


func _run() -> void:
	# --- Pure: the combined index list grew a T segment after the L-shapes ---------
	var rb: GDScript = load("res://scripts/run/room_builder.gd")
	_check(rb.T_FOOTPRINTS.size() >= 1, "no T_FOOTPRINTS registered")
	var inst: Node = rb.new()  # .new() never runs _ready (not in tree) -> no scene state
	var t_idx: int = rb.FOOTPRINTS.size() + rb.L_FOOTPRINTS.size()  # first T in the combined list
	var fp: Dictionary = inst._footprint_by_index(t_idx)
	_check(String(fp.get("shape", "")) == "T", "combined index %d is not a T-shape" % t_idx)
	_check((fp.notch as Vector2) != Vector2.ZERO, "T footprint should carry a per-corner notch")
	# The Heap pool opted into the T-shapes; the Stack (rectangular-only) did not.
	var heap_pool: Array = LayerCatalog.profile_for_room(1).footprint_pool
	_check(t_idx in heap_pool, "Heap pool did not opt into the T-shapes")
	for idx in LayerCatalog.profile_for_room(7).footprint_pool:
		_check(int(idx) < rb.FOOTPRINTS.size(), "Stack picked up a notched shape index %d" % int(idx))
	inst.free()

	# --- Scene: force a T room through the real pipeline ---------------------------
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)  # idle the starting squad

	var builder: Node = main.get_node("RoomBuilder")
	var nav: NavigationRegion3D = main.get_node("NavRegion")
	# Retire the authored CSG arena and let it actually leave the tree BEFORE we build,
	# else its 44x44 floor bakes over our notch (its single-frame internal retire isn't
	# enough for CSG to clear -- same gotcha l_room_test documents).
	builder.call("_retire_authored_interior")
	await get_tree().process_frame
	await get_tree().process_frame
	RunManager.run_seed = 31337
	var profile := {"footprint_pool": [t_idx], "archetype_pool": ["scattered_cover"]}
	var result: Dictionary = await builder.build_room(2, profile)

	_check(builder.get("_shape") == "T", "build did not select the T shell (shape=%s)"
			% str(builder.get("_shape")))
	var notches: Array = builder.get("_notches")
	_check(notches.size() == 2, "a T should have two bare corners, got %d" % notches.size())
	_check(result.ok, "T room failed validation -- not playable (no reachable squad/cover fit)")

	# Shell pieces exist (two floor boxes + the concave corner walls).
	for n in ["Floor", "Floor2", "WallNotchEH", "WallNotchEV", "WallNotchWH", "WallNotchWV"]:
		_check(main.get_node_or_null("NavRegion/GeneratedShell/" + n) != null,
				"T shell missing piece %s" % n)

	var map: RID = nav.get_world_3d().navigation_map
	var spawn: Vector3 = (main.get_node("PlayerSpawn") as Node3D).global_position
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn)
	var hx: float = builder.get("_room_half").x
	var hz: float = builder.get("_room_half").y
	var nd: float = builder.get("_notch").y

	# Body centre + the north stem are navigable AND reachable from the spawn (the
	# crossbar connects to the stem -- the whole T is one connected space).
	_check(_reachable(map, start, Vector3(0.0, 0.0, 0.0)), "T body centre unreachable from spawn")
	_check(_reachable(map, start, Vector3(0.0, 0.0, -hz + nd * 0.5)),
			"T north stem unreachable from spawn (crossbar not connected to stem)")

	# Each bare north corner is a real hole: sample the DEEP outer corner (1 m in from
	# the room's actual corner, well clear of the walkable stem edge) -- no reachable
	# ground there. (Wall tops bake isolated navmesh islands at y~5; harmless + unreachable.)
	for sign in [1.0, -1.0]:
		var corner := Vector3(sign * (hx - 1.0), 0.0, -hz + 1.0)
		var snap: Vector3 = NavigationServer3D.map_get_closest_point(map, corner)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, corner, true)
		var reach_end := Vector3(9999, 0, 0) if path.is_empty() else path[path.size() - 1]
		_check(snap.distance_to(corner) > 2.0,
				"T corner %s is navigable -- the bite isn't a real hole (snap dist %.2f)"
						% [str(corner), snap.distance_to(corner)])
		_check(reach_end.distance_to(corner) > 2.0,
				"T corner %s is reachable from the spawn -- not a clean hole (reach_dist %.2f)"
						% [str(corner), reach_end.distance_to(corner)])

	# Nothing landed in either bare corner: obstacles, enemy spawns, pickups.
	for child in (main.get_node("NavRegion/GeneratedRoom") as Node).get_children():
		if child is StaticBody3D:
			var op: Vector3 = (child as Node3D).position
			_check(not _in_any_notch(notches, op.x, op.z),
					"obstacle landed in a T corner at %s" % str(op))
	for sp in (builder.call("get_enemy_spawn_points") as Array):
		_check(not _in_any_notch(notches, (sp as Vector3).x, (sp as Vector3).z),
				"enemy spawn landed in a T corner at %s" % str(sp))
	for pk in (builder.call("get_pickup_points") as Array):
		var pv: Vector3 = pk.position
		_check(not _in_any_notch(notches, pv.x, pv.z),
				"pickup landed in a T corner at %s" % str(pv))

	# Determinism: same seed reproduces the same T (shape + corner count).
	RunManager.run_seed = 31337
	await builder.build_room(2, profile)
	_check(builder.get("_shape") == "T" and (builder.get("_notches") as Array).size() == 2,
			"T build is not deterministic for a fixed seed")
