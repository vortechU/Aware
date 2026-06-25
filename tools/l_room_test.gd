extends Node
## Headless test for L-shaped (notched) procedural rooms.
## Run: godot --headless --path . res://tools/l_room_test.tscn
## Instances main.tscn, retires the authored room, forces a known NE-corner L
## footprint on RoomBuilder, builds + bakes the shell, and asserts: the L shell
## has its second floor box and both concave notch walls; the navmesh bakes; the
## playable centre is on the navmesh and reachable from the spawn; and the notch
## corner is NOT navigable (no floor there) -> the bite is a real hole, not just
## a cosmetic wall.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _run(main)
	if fails.is_empty():
		print("L_ROOM_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("L_ROOM_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run(main: Node) -> void:
	# Wait for GameManager's room-1 spawn so the scene (and navmesh) is settled.
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame

	var builder: Node = main.get_node("RoomBuilder")
	# Retire the authored room and let its CSG shell actually leave the tree before
	# we bake, otherwise the authored 44x44 floor bakes over our notch.
	builder.call("_retire_authored_interior")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main.get_node_or_null("NavRegion/Arena/Floor") == null,
			"authored floor still present before the L bake")

	# Force a known NE-corner L: 24x24 bounding, 16x16 notch in the +X/-Z corner.
	var hx := 24.0
	var hz := 24.0
	var nw := 16.0
	var nd := 16.0
	builder.set("_room_half", Vector2(hx, hz))
	builder.set("_notch", Vector2(nw, nd))
	builder.set("_notch_corner", 1)  # CORNER_NE
	builder.set("_inner_limit", Vector2(hx - 2.0, hz - 2.0))
	builder.set("_player_spawn_pos", Vector3(0.0, 0.0, hz - 3.0))
	builder.call("_compute_notch_rect")
	builder.call("_build_shell")

	# Shell structure: the L adds a second floor box + two concave notch walls.
	_check(main.get_node_or_null("NavRegion/GeneratedShell/Floor") != null,
			"L shell missing main floor box")
	_check(main.get_node_or_null("NavRegion/GeneratedShell/Floor2") != null,
			"L shell missing second floor box")
	_check(main.get_node_or_null("NavRegion/GeneratedShell/WallNotchA") != null,
			"L shell missing concave notch wall A")
	_check(main.get_node_or_null("NavRegion/GeneratedShell/WallNotchB") != null,
			"L shell missing concave notch wall B")

	# Populate obstacles + cover like a real build.
	builder.call("_clear_generated")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var boxes: Array = builder.call("_descriptors_for", "scattered_cover", rng)
	builder.call("_instantiate_boxes", boxes)
	builder.call("_place_cover_markers", boxes)

	# Bake the navmesh. The new mesh replaces the authored one in the map after a
	# few physics frames; poll (the authored floor reached ~22, the new L reaches
	# z=25) so the hole/reachability checks below read the new mesh, not stale data.
	var nav: NavigationRegion3D = main.get_node("NavRegion")
	var map: RID = nav.get_world_3d().navigation_map
	await get_tree().process_frame
	nav.bake_navigation_mesh()
	await nav.bake_finished
	var synced := false
	for i in 30:
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(map)
		if NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 0.0, 100.0)).z > 22.5:
			synced = true
			break
	_check(synced, "navigation map never reflected the new L navmesh")
	var poly_count := nav.navigation_mesh.get_polygon_count()
	_check(poly_count >= 40, "L navmesh looks degenerate (%d polygons)" % poly_count)

	var spawn := Vector3(0.0, 0.0, hz - 3.0)
	var start := NavigationServer3D.map_get_closest_point(map, spawn)

	# The playable centre (west block) is on the navmesh and reachable.
	var play := Vector3(0.0, 0.0, 0.0)
	var play_snap := NavigationServer3D.map_get_closest_point(map, play)
	_check(play_snap.distance_to(play) < 1.5,
			"playable centre not on the navmesh (snap dist %.2f)" % play_snap.distance_to(play))
	var path := NavigationServer3D.map_get_path(map, start, play_snap, true)
	_check(not path.is_empty() and path[path.size() - 1].distance_to(play_snap) < 1.5,
			"playable centre unreachable from the spawn")

	# The notch centre has NO floor, so the closest navmesh point is far away.
	var notch_c := Vector3(hx - nw * 0.5, 0.0, -hz + nd * 0.5)  # (16, 0, -16)
	var notch_snap := NavigationServer3D.map_get_closest_point(map, notch_c)
	print("L_ROOM_DIAG polygons=", poly_count, " notch_snap=", notch_snap,
			" notch_snap_dist=", notch_snap.distance_to(notch_c))
	_check(notch_snap.distance_to(notch_c) > 2.0,
			"notch corner should not be navigable (snap dist %.2f)"
			% notch_snap.distance_to(notch_c))

	# No obstacle landed in the bare notch corner.
	var nmin: Vector2 = builder.get("_notch_min")
	var nmax: Vector2 = builder.get("_notch_max")
	for child in (main.get_node("NavRegion/GeneratedRoom") as Node).get_children():
		if child is StaticBody3D:
			var op: Vector3 = (child as Node3D).position
			_check(not (op.x > nmin.x and op.x < nmax.x and op.z > nmin.y and op.z < nmax.y),
					"obstacle landed inside the notch at %s" % str(op))

	# Real validation path: with the L footprint live, generated enemy spawns and
	# pickups must never land in the bare notch (geometric guard, sync-independent).
	builder.set("_min_spawn_dist", 14.0)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	builder.call("_validate_and_collect", 6, rng2)
	for sp in (builder.call("get_enemy_spawn_points") as Array):
		var v: Vector3 = sp
		_check(not (v.x > nmin.x and v.x < nmax.x and v.z > nmin.y and v.z < nmax.y),
				"enemy spawn landed inside the notch at %s" % str(v))
	for pk in (builder.call("get_pickup_points") as Array):
		var pv: Vector3 = pk.position
		_check(not (pv.x > nmin.x and pv.x < nmax.x and pv.z > nmin.y and pv.z < nmax.y),
				"pickup landed inside the notch at %s" % str(pv))
