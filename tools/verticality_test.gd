extends Node
## V1 of navigable verticality (player-traversable approach).
## Run: godot --headless --path . res://tools/verticality_test.tscn
##
## Platforms + ramps are solid collision geometry the PLAYER climbs via physics;
## enemies stay grounded (the navmesh routes around the platform bases). So V1
## proves: the builders make solid, grouped world geometry; the player physically
## rests on the platform top (collision works, no fall-through, no slide-off); the
## ramp slope is within the player's climbable range; and -- the real risk for this
## approach -- the room stays ENEMY-navigable on the ground (the platforms don't
## make any enemy spawn unreachable from the player spawn).
##
## (Enemy-navigable high ground -- baking navmesh ONTO platforms -- is a separate
## later investigation; the de-risk run showed it needs dedicated navmesh tuning.)

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("VERTICALITY_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("VERTICALITY_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


## True only if every point is reachable from `start` across the ground navmesh.
func _all_reachable(map: RID, start: Vector3, points: Array) -> bool:
	for p in points:
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, p)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, snapped, true)
		if path.is_empty() or path[path.size() - 1].distance_to(snapped) > 1.5:
			return false
	return true


func _run() -> void:
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
	RunManager.run_seed = 777  # deterministic room for the proof
	await builder.build_room(2)

	var map: RID = nav.get_world_3d().navigation_map
	var spawn: Vector3 = (main.get_node("PlayerSpawn") as Node3D).global_position
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn)
	var enemy_spawns: Array = builder.get_enemy_spawn_points()
	_check(enemy_spawns.size() >= 1, "no enemy spawns to verify ground navigation against")
	_check(_all_reachable(map, start, enemy_spawns),
			"baseline: enemy spawns not reachable from the player spawn before platforms")

	# Build a player-only platform + ramp a little in front of the spawn.
	var top_y := 2.5
	var run := 4.0  # slope atan(2.5/4) ~= 32 deg -> comfortably climbable
	var plat_half := Vector2(3.0, 3.0)
	var top: Vector3 = builder._build_platform(Vector2(4.0, spawn.z - 9.0), plat_half, top_y)
	builder._build_ramp(top, plat_half.y, top_y, run, 3.0, 1.0)
	await builder._rebake()

	# 1. Solid, grouped world geometry.
	var plats := get_tree().get_nodes_in_group("room_platform")
	var ramps := get_tree().get_nodes_in_group("room_ramp")
	_check(plats.size() >= 1 and plats[0] is StaticBody3D and (plats[0] as StaticBody3D).collision_layer == 1,
			"platform is not solid world geometry")
	_check(ramps.size() >= 1 and ramps[0] is StaticBody3D and (ramps[0] as StaticBody3D).collision_layer == 1,
			"ramp is not solid world geometry")

	# 2. THE REAL RISK: the platforms must not wall off the ground -- every enemy
	#    spawn stays reachable from the player spawn across the ground navmesh.
	_check(_all_reachable(map, NavigationServer3D.map_get_closest_point(map, spawn), enemy_spawns),
			"platforms broke ground navigation (an enemy spawn became unreachable)")

	# 3. The ramp slope is within the player's climbable range.
	var slope := atan2(top_y, run)
	_check(slope < deg_to_rad(40.0), "ramp is too steep to climb (%.1f deg)" % rad_to_deg(slope))

	# 4. The player physically rests ON the platform top (solid collision, no
	#    fall-through, no slide-off): drop it from just above the centre and settle.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.set("velocity", Vector3.ZERO)
	player.global_position = top + Vector3(0.0, 1.6, 0.0)
	for _i in 50:
		await get_tree().physics_frame
	_check(player.global_position.y > top_y - 0.3,
			"player fell through/off the platform (y=%.2f, platform top=%.1f)"
			% [player.global_position.y, top_y])
	_check(Vector2(player.global_position.x - top.x, player.global_position.z - top.z).length() < plat_half.x,
			"player slid off the platform top")
