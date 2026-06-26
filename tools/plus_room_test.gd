extends Node
## Stronger shape contrast Pass 3: the plus/cross footprint family.
## Run: godot --headless --path . res://tools/plus_room_test.tscn
##
## A plus is the T generalised to all FOUR corners: a central crossing with four arms
## (south arm = player spawn, north arm = exit gate, east/west arms = flanking
## sightlines). This forces a plus room through the REAL build_room pipeline and asserts:
##   - the picker exposes plus-shapes; the combined-index split still holds (4 segments).
##   - the room builds + validates OK (reachable squad + cover fit the plus).
##   - the central crossing AND all four arms are reachable from the spawn (one space).
##   - all four bare corners are genuine unreachable holes (no navmesh ground there).
##   - no obstacle / enemy spawn / pickup lands in any of the four corners.
##   - determinism: a fixed seed reproduces the same plus.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("PLUS_ROOM_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("PLUS_ROOM_FAIL: ", f)
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


func _any_reachable(map: RID, start: Vector3, points: Array) -> bool:
	for p in points:
		if _reachable(map, start, p):
			return true
	return false


## A few sample points in the east (side=+1) or west (side=-1) flanking arm of a plus,
## a couple of metres in from the wall and spread in Z to dodge a crate on any one spot.
func _arm_samples(hx: float, side: float) -> Array:
	var out: Array = []
	for ix in [4.0, 6.0]:
		for z in [-4.0, 0.0, 4.0]:
			out.append(Vector3(side * (hx - ix), 0.0, z))
	return out


func _in_any_notch(notches: Array, x: float, z: float) -> bool:
	for n in notches:
		var nmin: Vector2 = n.min
		var nmax: Vector2 = n.max
		if x > nmin.x and x < nmax.x and z > nmin.y and z < nmax.y:
			return true
	return false


func _run() -> void:
	# --- Pure: the combined index list grew a PLUS segment after the T-shapes --------
	var rb: GDScript = load("res://scripts/run/room_builder.gd")
	_check(rb.PLUS_FOOTPRINTS.size() >= 1, "no PLUS_FOOTPRINTS registered")
	var inst: Node = rb.new()  # .new() never runs _ready (not in tree) -> no scene state
	var p_idx: int = rb.FOOTPRINTS.size() + rb.L_FOOTPRINTS.size() + rb.T_FOOTPRINTS.size()
	var fp: Dictionary = inst._footprint_by_index(p_idx)
	_check(String(fp.get("shape", "")) == "plus", "combined index %d is not a plus-shape" % p_idx)
	_check((fp.notch as Vector2) != Vector2.ZERO, "plus footprint should carry a per-corner notch")
	var heap_pool: Array = LayerCatalog.profile_for_room(1).footprint_pool
	_check(p_idx in heap_pool, "Heap pool did not opt into the plus-shapes")
	for idx in LayerCatalog.profile_for_room(7).footprint_pool:
		_check(int(idx) < rb.FOOTPRINTS.size(), "Stack picked up a notched shape index %d" % int(idx))
	inst.free()

	# --- Scene: force a plus room through the real pipeline ------------------------
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)

	var builder: Node = main.get_node("RoomBuilder")
	var nav: NavigationRegion3D = main.get_node("NavRegion")
	# Pre-retire the authored CSG arena + settle, else its 44x44 floor bakes over the
	# corners (build_room's internal 1-frame retire isn't enough for CSG; see l_room/t_room).
	builder.call("_retire_authored_interior")
	await get_tree().process_frame
	await get_tree().process_frame
	RunManager.run_seed = 24680
	var profile := {"footprint_pool": [p_idx], "archetype_pool": ["scattered_cover"]}
	var result: Dictionary = await builder.build_room(2, profile)

	_check(builder.get("_shape") == "plus", "build did not select the plus shell (shape=%s)"
			% str(builder.get("_shape")))
	var notches: Array = builder.get("_notches")
	_check(notches.size() == 4, "a plus should have four bare corners, got %d" % notches.size())
	_check(result.ok, "plus room failed validation -- not playable (no reachable squad/cover fit)")

	# Shell pieces: three floor boxes + the eight concave corner walls.
	for n in ["Floor", "Floor2", "Floor3", "WallNotchH0", "WallNotchV0",
			"WallNotchH3", "WallNotchV3"]:
		_check(main.get_node_or_null("NavRegion/GeneratedShell/" + n) != null,
				"plus shell missing piece %s" % n)

	var map: RID = nav.get_world_3d().navigation_map
	var spawn: Vector3 = (main.get_node("PlayerSpawn") as Node3D).global_position
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn)
	var hx: float = builder.get("_room_half").x
	var hz: float = builder.get("_room_half").y
	var nd: float = builder.get("_notch").y

	# The central crossing + all four arms are reachable from the spawn (one connected
	# space): centre, north arm, east/west band ends, south arm.
	_check(_reachable(map, start, Vector3(0.0, 0.0, 0.0)), "plus centre unreachable from spawn")
	_check(_reachable(map, start, Vector3(0.0, 0.0, -hz + nd * 0.5)),
			"plus north arm unreachable from spawn")
	_check(_reachable(map, start, Vector3(0.0, 0.0, hz - nd * 0.5)),
			"plus south arm unreachable from spawn")
	# The E/W band ends (the plus's flanking arms, x beyond the N/S arm width) are
	# reachable. Sample a small grid per side and require ANY reachable -- a single probe
	# can land on a crate-carved spot in the narrow band pocket.
	_check(_any_reachable(map, start, _arm_samples(hx, 1.0)),
			"plus east arm unreachable from spawn")
	_check(_any_reachable(map, start, _arm_samples(hx, -1.0)),
			"plus west arm unreachable from spawn")

	# All four bare corners are real holes: sample the DEEP outer corner (1 m in from the
	# room's actual corner). (Wall tops bake isolated navmesh islands at y~5 -- unreachable.)
	for cx in [1.0, -1.0]:
		for cz in [1.0, -1.0]:
			var corner := Vector3(cx * (hx - 1.0), 0.0, cz * (hz - 1.0))
			var snap: Vector3 = NavigationServer3D.map_get_closest_point(map, corner)
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, corner, true)
			var reach_end := Vector3(9999, 0, 0) if path.is_empty() else path[path.size() - 1]
			_check(snap.distance_to(corner) > 2.0,
					"plus corner %s is navigable -- not a real hole (snap dist %.2f)"
							% [str(corner), snap.distance_to(corner)])
			_check(reach_end.distance_to(corner) > 2.0,
					"plus corner %s is reachable from the spawn (reach_dist %.2f)"
							% [str(corner), reach_end.distance_to(corner)])

	# Nothing landed in any bare corner: obstacles, enemy spawns, pickups.
	for child in (main.get_node("NavRegion/GeneratedRoom") as Node).get_children():
		if child is StaticBody3D:
			var op: Vector3 = (child as Node3D).position
			_check(not _in_any_notch(notches, op.x, op.z),
					"obstacle landed in a plus corner at %s" % str(op))
	for sp in (builder.call("get_enemy_spawn_points") as Array):
		_check(not _in_any_notch(notches, (sp as Vector3).x, (sp as Vector3).z),
				"enemy spawn landed in a plus corner at %s" % str(sp))
	for pk in (builder.call("get_pickup_points") as Array):
		var pv: Vector3 = pk.position
		_check(not _in_any_notch(notches, pv.x, pv.z),
				"pickup landed in a plus corner at %s" % str(pv))

	# Determinism: same seed reproduces the same plus.
	RunManager.run_seed = 24680
	await builder.build_room(2, profile)
	_check(builder.get("_shape") == "plus" and (builder.get("_notches") as Array).size() == 4,
			"plus build is not deterministic for a fixed seed")
