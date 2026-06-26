extends Node
## Stronger shape contrast (procgen variety lever): the footprint range was widened
## from "medium rectangles" into a deliberate spread -- a tight close-quarters
## chamber, long corridors, a vast arena, and a bold deep L -- so consecutive rooms
## read as different spaces, not "another square box".
## Run: godot --headless --path . res://tools/shape_contrast_test.tscn
##
## Pure section: the new footprint classes exist, the combined-list index mapping
## still splits rectangles from L-shapes correctly, the endless picker's area/aspect
## spread genuinely widened, and the layer pools point at the right (shifted) indices.
## Scene section: each new footprint is forced through the REAL build_room pipeline
## (single-index footprint_pool) and must validate OK -- i.e. it's actually playable
## (navmesh bakes, a reachable enemy squad + cover fit), not just data.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("SHAPE_CONTRAST_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("SHAPE_CONTRAST_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	_part_pure()
	await _part_scene()


# ---------------------------------------------------------------- A. pure data

func _part_pure() -> void:
	var rb: GDScript = load("res://scripts/run/room_builder.gd")
	var rects: Array = rb.FOOTPRINTS
	var ls: Array = rb.L_FOOTPRINTS

	# The new shape classes are present in the rectangle pool.
	var has_tight := false       # a genuinely small chamber (both axes < the old compact 17)
	var has_wide_corridor := false   # long along X, aspect >= 2.3
	var has_deep_corridor := false   # long along Z, aspect >= 2.3
	var has_grand := false       # vast, both axes >= 28
	for fp in rects:
		var v: Vector2 = fp
		if v.x < 15.0 and v.y < 15.0:
			has_tight = true
		if v.x >= v.y * 2.3:
			has_wide_corridor = true
		if v.y >= v.x * 2.3:
			has_deep_corridor = true
		if v.x >= 28.0 and v.y >= 28.0:
			has_grand = true
	_check(has_tight, "no tight close-quarters footprint in FOOTPRINTS")
	_check(has_wide_corridor, "no wide corridor footprint (aspect >= 2.3 along X)")
	_check(has_deep_corridor, "no deep corridor footprint (aspect >= 2.3 along Z)")
	_check(has_grand, "no grand/vast footprint (both half-extents >= 28)")

	# Combined-index mapping still splits cleanly: the first L index is the rectangle
	# count, every rectangle index is a plain rect (zero notch), every L index notched.
	var rect_count: int = rects.size()
	# A transient instance only for the pure helper; .new() never runs _ready (not in
	# the tree), so it touches no scene state. Freed below.
	var inst: Node = rb.new()
	for i in rect_count:
		_check((inst._footprint_by_index(i).notch as Vector2) == Vector2.ZERO,
				"combined index %d should be a rectangle but is notched" % i)
	for i in range(rect_count, rect_count + ls.size()):
		_check((inst._footprint_by_index(i).notch as Vector2) != Vector2.ZERO,
				"combined index %d should be an L-shape but has no notch" % i)
	inst.free()

	# A bold deep L exists (notch area noticeably bigger than the original L set).
	var bold_l := false
	for d in ls:
		if (d.notch as Vector2).x * (d.notch as Vector2).y >= 18.0 * 15.0 - 0.5:
			bold_l = true
	_check(bold_l, "no bold deep L-shape added (notch >= ~18x15)")

	# The endless picker's spread genuinely widened: across many seeds it now yields a
	# small room AND a vast room AND many distinct classes.
	var picker: Node = rb.new()
	var rng := RandomNumberGenerator.new()
	var min_area := INF
	var max_area := 0.0
	var seen := {}
	for s in 300:
		rng.seed = s
		var fp: Dictionary = picker._pick_footprint(rng, {})  # {} = endless full range
		var half: Vector2 = fp.half
		var area := half.x * 2.0 * half.y * 2.0
		min_area = minf(min_area, area)
		max_area = maxf(max_area, area)
		seen["%s|%s" % [str(half), str(fp.notch)]] = true
	picker.free()
	_check(min_area <= 14.0 * 2.0 * 14.0 * 2.0 + 1.0,
			"endless picker never produced a tight room (min area %.0f)" % min_area)
	_check(max_area >= 56.0 * 54.0,
			"endless picker never produced a grand room (max area %.0f)" % max_area)
	_check(max_area / maxf(min_area, 1.0) >= 4.0,
			"footprint area spread too narrow (max/min = %.1f)" % (max_area / maxf(min_area, 1.0)))
	_check(seen.size() >= 10, "endless picker offered only %d footprint classes" % seen.size())

	# Layer pools point at the right (shifted) indices.
	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	var stack: Dictionary = LayerCatalog.profile_for_room(7)
	# Heap skips the compact/standard/tight squares (indices 0, 1, 6).
	for bad in [0, 1, 6]:
		_check(bad not in heap.footprint_pool,
				"Heap pool should skip small square index %d" % bad)
	# Heap still carries corridors + grand + at least one L (the irregular read).
	_check(7 in heap.footprint_pool and 8 in heap.footprint_pool and 9 in heap.footprint_pool,
			"Heap pool lost the corridor/grand footprints after the index shift")
	var heap_has_l := false
	for idx in heap.footprint_pool:
		if int(idx) >= rect_count:
			heap_has_l = true
	_check(heap_has_l, "Heap pool lost its L-shapes after the index shift")
	# Stack stayed rectangular-only AND gained the new rects.
	for idx in stack.footprint_pool:
		_check(int(idx) < rect_count, "Stack pool now references an L-shape index %d" % int(idx))
	_check(6 in stack.footprint_pool and 7 in stack.footprint_pool
			and 9 in stack.footprint_pool,
			"Stack pool did not pick up the new tight/corridor/grand rects")


# ---------------------------------------------------------------- B. scene build

func _part_scene() -> void:
	var rb: GDScript = load("res://scripts/run/room_builder.gd")
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)  # idle the starting squad during the inspection

	var builder: Node = main.get_node("RoomBuilder")
	# Each new footprint, forced via a single-index pool, must build + validate OK.
	# scattered_cover is corridor/tight friendly; room 2 is a plain COMBAT sector.
	var cases := {
		6: "tight square",
		7: "wide corridor",
		8: "deep corridor",
		9: "grand arena",
		13: "bold deep L",
	}
	for idx in cases:
		var expected: Vector2 = builder.call("_footprint_by_index", idx).half
		RunManager.run_seed = 7000 + idx
		var profile := {"footprint_pool": [idx], "archetype_pool": ["scattered_cover"]}
		var result: Dictionary = await builder.build_room(2, profile)
		var got: Vector2 = builder.get("_room_half")
		_check(got.is_equal_approx(expected),
				"%s: build used footprint %s, expected %s" % [cases[idx], str(got), str(expected)])
		_check(result.ok,
				"%s footprint failed validation -- not playable (no reachable squad/cover fit)"
						% cases[idx])
		_check(builder.get_enemy_spawn_points().size() >= 1,
				"%s footprint placed no enemy spawns" % cases[idx])
