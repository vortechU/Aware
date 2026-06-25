extends Node
## Headless test for Pass 1 of the layered world: the Layer backbone + the Heap
## re-skin. Run: godot --headless --path . res://tools/heap_smoke_test.tscn
##
## Covers, in three parts:
##  A. LayerCatalog (pure): the Heap owns global rooms 1..6, the room->layer/sector
##     mapping is correct, and rooms past the catalog clamp to the last layer.
##  B. RunManager: ENDLESS leaves the layer view at 0 and an empty profile (so the
##     legacy flow is untouched); CAMPAIGN populates current_layer/room_in_layer.
##  C. Heap re-skin: with the Heap profile, a built room draws its archetype from
##     the Heap pool, sizes to a Heap footprint, and the sun takes the Heap mood
##     (cold tint + dimmed). The HUD room label reads the layer tag, not "ROOM N".

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # transitions/builds pause-juggle the tree
	_part_a_catalog()
	_part_b_run_manager()
	await _part_c_heap_reskin()
	if fails.is_empty():
		print("HEAP_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HEAP_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


# ---------------------------------------------------------------- A. catalog

func _part_a_catalog() -> void:
	# The Heap owns global rooms 1..6, all map to layer 1, sector == the room.
	for room in range(1, 7):
		_check(LayerCatalog.profile_for_room(room).id == "heap",
				"room %d should be in the Heap" % room)
		_check(LayerCatalog.layer_index_for_room(room) == 1,
				"room %d should be layer 1, got %d" % [room, LayerCatalog.layer_index_for_room(room)])
		_check(LayerCatalog.room_in_layer_for_room(room) == room,
				"room %d sector should be %d, got %d"
				% [room, room, LayerCatalog.room_in_layer_for_room(room)])
	# Rooms past the catalog clamp to the last defined layer (whichever that is).
	var last_id: String = LayerCatalog.LAYERS[LayerCatalog.LAYERS.size() - 1].id
	_check(LayerCatalog.profile_for_room(99).id == last_id,
			"rooms past the catalog should clamp to the last layer")

	# The Heap profile carries the fields the re-skin needs.
	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	_check(heap.get("tag", "") == "HEAP", "Heap tag should be HEAP")
	var pool: Array = heap.get("archetype_pool", [])
	_check(not pool.is_empty(), "Heap should restrict the archetype pool")
	for id in pool:
		_check(id in ["open_field", "scattered_cover", "pillar_hall"],
				"Heap pool should be early archetypes only, saw %s" % id)
	_check(not (heap.get("footprint_pool", []) as Array).is_empty(),
			"Heap should bias the footprint pool")
	_check(heap.has("mood_tint"), "Heap should define a mood tint")


# ---------------------------------------------------------------- B. run manager

func _part_b_run_manager() -> void:
	# ENDLESS: the layer view stays inert and the profile is empty, so RoomBuilder
	# and every existing harness behave exactly as before.
	RunManager.selected_mode = RunManager.RunMode.ENDLESS
	RunManager.start_run()
	_check(RunManager.run_mode == RunManager.RunMode.ENDLESS, "endless mode not active")
	_check(RunManager.current_layer == 0, "endless should leave current_layer at 0")
	_check(RunManager.room_in_layer == 0, "endless should leave room_in_layer at 0")
	_check(RunManager.active_layer_profile().is_empty(),
			"endless should expose no layer profile")

	# CAMPAIGN: room 1 sits in the Heap as sector 1; advancing tracks the sector.
	RunManager.selected_mode = RunManager.RunMode.CAMPAIGN
	RunManager.start_run()
	_check(RunManager.run_mode == RunManager.RunMode.CAMPAIGN, "campaign mode not active")
	_check(RunManager.current_room == 1, "campaign should start at room 1")
	_check(RunManager.current_layer == 1, "campaign room 1 should be layer 1")
	_check(RunManager.room_in_layer == 1, "campaign room 1 should be sector 1")
	_check(RunManager.active_layer_profile().get("id", "") == "heap",
			"campaign room 1 profile should be the Heap")
	RunManager.advance_room()
	_check(RunManager.current_room == 2 and RunManager.room_in_layer == 2,
			"advancing to room 2 should read as sector 2")


# ---------------------------------------------------------------- C. re-skin

func _part_c_heap_reskin() -> void:
	# Launch a real campaign run, then build a room with the Heap profile and
	# inspect the result. selected_mode must be set BEFORE the scene loads so
	# RunDirector._ready -> start_run() picks up CAMPAIGN.
	RunManager.selected_mode = RunManager.RunMode.CAMPAIGN
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)

	# Wait for GameManager's room-1 spawn + RunDirector's adoption (like run_smoke).
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)  # blind the AI so a stray shot can't end the run mid-test

	# Campaign state is live and the HUD shows the layer, not a flat room number.
	_check(RunManager.run_mode == RunManager.RunMode.CAMPAIGN, "scene run is not campaign")
	_check(RunManager.current_layer == 1 and RunManager.room_in_layer == 1,
			"scene run should open on Heap sector 1")
	var room_label: Label = main_scene.get_node("RunHUD/RoomLabel")
	_check("HEAP" in room_label.text,
			"campaign room label should name the layer, got '%s'" % room_label.text)

	# Build a room with the Heap profile and read the re-skin off the builder.
	var builder: Node = main_scene.get_node("RoomBuilder")
	var profile: Dictionary = RunManager.active_layer_profile()
	_check(not profile.is_empty(), "no Heap profile to build with")
	var build: Dictionary = await builder.build_room(2, profile)

	# Archetype came from the Heap pool.
	_check(build.id in profile["archetype_pool"],
			"built archetype '%s' is not in the Heap pool" % build.id)

	# Footprint is one of the Heap-biased shapes (no compact/standard square).
	var room_half: Vector2 = builder.get("_room_half")
	var valid := false
	for idx in profile["footprint_pool"]:
		if room_half.is_equal_approx(builder.call("_footprint_by_index", int(idx)).half):
			valid = true
	_check(valid, "Heap room footprint %s is outside the Heap pool" % str(room_half))
	_check(not room_half.is_equal_approx(Vector2(17, 17))
			and not room_half.is_equal_approx(Vector2(21, 21)),
			"Heap should skip the compact/standard squares, got %s" % str(room_half))

	# Mood: the sun took the Heap tint and got dimmed.
	var sun: DirectionalLight3D = main_scene.get_node("Sun")
	var base_color: Color = builder.get("_base_sun_color")
	var base_energy: float = builder.get("_base_sun_energy")
	var expect_color: Color = base_color.lerp(profile["mood_tint"], profile["mood_strength"])
	_check(_color_close(sun.light_color, expect_color),
			"sun colour %s did not take the Heap mood %s" % [str(sun.light_color), str(expect_color)])
	_check(absf(sun.light_energy - base_energy * float(profile["sun_energy_factor"])) < 0.01,
			"sun was not dimmed to the Heap energy (got %.3f)" % sun.light_energy)
	_check(sun.light_energy < base_energy, "Heap mood should dim the sun below the authored energy")


func _color_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
