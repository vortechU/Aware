extends Node
## V2 of navigable verticality: the "Tiers" room-layout archetype.
## Run: godot --headless --path . res://tools/tiers_test.tscn
##
## V1 proved the platform/ramp BUILDERS. V2 proves they're wired into a real,
## opt-in room layout. A "tiers" room is forced via a profile archetype_pool and
## asserts:
##   - "tiers" is opt-in: it's NEVER chosen by the endless room-gated rotation,
##     only when a profile's archetype_pool lists it.
##   - the room builds OK -- which means validation passed, i.e. the platforms did
##     NOT wall off the ground (every enemy spawn stays reachable from the player
##     spawn across the GROUND navmesh -- the real risk of this approach).
##   - it actually generates raised platforms + ramps + high cover (the player's
##     reward), all solid grouped world geometry within the room bounds.
##   - the ground still spawns a real enemy squad on the navmesh.
##   - determinism: the same seed reproduces the same platform count.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("TIERS_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("TIERS_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _all_reachable(map: RID, start: Vector3, points: Array) -> bool:
	for p in points:
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, p)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, snapped, true)
		if path.is_empty() or path[path.size() - 1].distance_to(snapped) > 1.5:
			return false
	return true


func _run() -> void:
	# --- Pure layer: "tiers" is opt-in (skipped by the endless rotation) ----------
	var builder_script: GDScript = load("res://scripts/run/room_builder.gd")
	var has_tiers := false
	var tiers_is_vertical := false
	for a in builder_script.ARCHETYPES:
		if a.id == "tiers":
			has_tiers = true
			tiers_is_vertical = bool(a.get("vertical", false))
	_check(has_tiers, "no 'tiers' archetype registered")
	_check(tiers_is_vertical, "'tiers' is not flagged vertical (would leak into endless)")

	# Wired into a layer: the Stack opts tiers into its archetype pool (so a CAMPAIGN
	# run actually meets vertical rooms). It must NOT be in the Heap pool.
	var stack: Dictionary = LayerCatalog.profile_for_room(7)
	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	_check(stack.id == "stack" and "tiers" in stack.archetype_pool,
			"tiers is not opted into the Stack's archetype pool")
	_check("tiers" not in heap.get("archetype_pool", []),
			"tiers leaked into the Heap pool (should be Stack-only for now)")

	# --- Scene: force a tiers room and inspect it ---------------------------------
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)  # keep the squad idle during the inspection

	var builder: Node = main.get_node("RoomBuilder")
	var nav: NavigationRegion3D = main.get_node("NavRegion")
	RunManager.run_seed = 4242  # deterministic tiers room
	# Force tiers, AND use the Stack's rectangular-only footprint pool (where tiers is
	# now wired in) -- the narrow footprints there are the tightest case for fitting
	# perimeter platforms. (build_room is pure geometry; the room number only seeds it.)
	var profile := {"archetype_pool": ["tiers"], "footprint_pool": [1, 2, 3, 4, 5]}
	var result: Dictionary = await builder.build_room(3, profile)

	_check(result.id == "tiers", "profile pool did not force the tiers archetype (got %s)" % result.id)
	_check(result.ok, "tiers room failed validation -- platforms likely walled off the ground")

	# Raised platforms + ramps + high cover, all solid grouped world geometry.
	var plats := get_tree().get_nodes_in_group("room_platform")
	var ramps := get_tree().get_nodes_in_group("room_ramp")
	var highs := get_tree().get_nodes_in_group("room_high_cover")
	_check(plats.size() >= 1, "tiers room generated no platforms")
	_check(ramps.size() >= 1, "tiers room generated no ramps")
	_check(highs.size() >= 1, "tiers room generated no high cover on the platforms")
	for p in plats:
		_check(p is StaticBody3D and (p as StaticBody3D).collision_layer == 1,
				"platform is not solid world geometry")
		var pos: Vector3 = (p as Node3D).global_position
		_check(absf(pos.x) <= builder._inner_limit.x + 0.01
				and absf(pos.z) <= builder._inner_limit.y + 0.01,
				"a platform sits outside the room bounds")
	for r in ramps:
		_check(r is StaticBody3D and (r as StaticBody3D).collision_layer == 1,
				"ramp is not solid world geometry")

	# High cover rides ABOVE the floor (it's on a platform cap), not on the ground.
	var any_elevated := false
	for h in highs:
		if (h as Node3D).global_position.y > 1.6:
			any_elevated = true
	_check(any_elevated, "high cover is not elevated onto a platform")

	# THE REAL RISK: the ground stayed enemy-navigable -- a full squad spawned on
	# the navmesh and every spawn is reachable from the player spawn.
	var spawns: Array = builder.get_enemy_spawn_points()
	_check(spawns.size() >= 1, "tiers room placed no enemy spawns on the ground")
	var map: RID = nav.get_world_3d().navigation_map
	var spawn_pos: Vector3 = (main.get_node("PlayerSpawn") as Node3D).global_position
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn_pos)
	_check(_all_reachable(map, start, spawns),
			"a tiers enemy spawn is unreachable from the player spawn (ground walled off)")

	# Determinism: rebuilding with the same seed reproduces the same platform count.
	var first_count := plats.size()
	RunManager.run_seed = 4242
	await builder.build_room(3, profile)
	_check(get_tree().get_nodes_in_group("room_platform").size() == first_count,
			"tiers platform count is not deterministic for a fixed seed")
