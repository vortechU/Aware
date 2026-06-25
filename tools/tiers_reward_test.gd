extends Node
## V3 of navigable verticality: player-only rewards on the Tiers platform caps.
## Run: godot --headless --path . res://tools/tiers_reward_test.tscn
##
## V2 made the climbable platforms. V3 gives the player a REASON to climb: the
## builder records one elevated reward spot per platform cap, and RunDirector drops
## a bonus pickup on each. Since enemies stay grounded, those pickups are a
## player-only payoff. Asserts:
##   - a tiers room reports >= 1 high-reward point, each genuinely elevated and in
##     bounds, sitting ABOVE the navmesh (a grounded agent can't stand there -- the
##     "player-only" property).
##   - RunDirector._spawn_high_rewards drops exactly one bonus pickup per cap, each a
##     premium type (HEALTH/ARMOR) floating up at cap height.
##   - non-vertical rooms report no high-reward points (so it's a no-op elsewhere).

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("TIERS_REWARD_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("TIERS_REWARD_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


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
	var director: Node = main.get_node("RunDirector")
	var nav: NavigationRegion3D = main.get_node("NavRegion")
	var pickups_root: Node3D = main.get_node("Pickups")

	# Control case: a plain (non-vertical) room records NO high-reward points.
	RunManager.run_seed = 4242
	await builder.build_room(2)  # no profile -> endless legacy, never tiers
	_check(builder.get_high_reward_points().is_empty(),
			"a non-vertical room should report no high-reward points")

	# Force a tiers room (Stack's rectangular footprint pool, where tiers is wired in).
	RunManager.run_seed = 4242
	var profile := {"archetype_pool": ["tiers"], "footprint_pool": [1, 2, 3, 4, 5]}
	await builder.build_room(8, profile)

	var caps: Array = builder.get_high_reward_points()
	_check(caps.size() >= 1, "tiers room recorded no high-reward points")
	var map: RID = nav.get_world_3d().navigation_map
	for c in caps:
		var cap: Vector3 = c
		_check(cap.y > 1.6, "a high-reward point is not elevated (y=%.2f)" % cap.y)
		_check(absf(cap.x) <= builder._inner_limit.x + 0.01
				and absf(cap.z) <= builder._inner_limit.y + 0.01,
				"a high-reward point is out of room bounds")
		# Player-only: the nearest NAVMESH point sits well below the cap, so a
		# grounded enemy can never stand where the reward floats.
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, cap)
		_check(snapped.y < cap.y - 1.0,
				"the navmesh reaches a high-reward cap (y=%.2f vs cap %.2f) -- not player-only"
				% [snapped.y, cap.y])

	# RunDirector drops exactly one bonus pickup per cap, each premium + elevated.
	var before := {}
	for child in pickups_root.get_children():
		before[child.get_instance_id()] = true
	director._spawn_high_rewards(caps)
	var fresh: Array = []
	for child in pickups_root.get_children():
		if not before.has(child.get_instance_id()):
			fresh.append(child)
	_check(fresh.size() == caps.size(),
			"expected %d bonus pickups, got %d" % [caps.size(), fresh.size()])
	for p in fresh:
		var pickup := p as Pickup
		_check(pickup != null, "a spawned high reward is not a Pickup")
		if pickup == null:
			continue
		_check(pickup.type == Pickup.Type.HEALTH or pickup.type == Pickup.Type.ARMOR,
				"high reward should be a premium pickup (health/armor), got type %d" % pickup.type)
		_check((pickup as Node3D).global_position.y > 1.6,
				"a bonus pickup did not spawn up on the cap (y=%.2f)"
				% (pickup as Node3D).global_position.y)
