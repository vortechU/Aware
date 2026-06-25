extends Node
## Per-layer materials + lighting: each narrative layer should read as a distinct
## PLACE, not just a differently-tinted gray box.
## Run: godot --headless --path . res://tools/layer_look_test.tscn
##
##  A. Palette: a layer profile resolves to its own floor/wall/struct materials
##     (Heap != Stack != the legacy gray); an empty profile (ENDLESS) keeps the
##     authored gray materials byte-for-byte.
##  B. Environment: applying a layer turns on its depth fog (colour + density) and
##     ambient; applying an empty profile restores the authored environment.
##  C. Render: a real CAMPAIGN Heap room's shell floor actually carries the Heap
##     colour through the toon shader (reads the toon `albedo` uniform, since the
##     ToonApplicator has swapped material_override by then).

var fails: Array[String] = []
const LEGACY_FLOOR := Color(0.33, 0.34, 0.37)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("LAYER_LOOK_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("LAYER_LOOK_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 6:
		await get_tree().process_frame
	var builder: Node = main.get_node("RoomBuilder")

	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	var stack: Dictionary = LayerCatalog.profile_for_room(7)

	# --- A. Palette --------------------------------------------------------------
	var p_heap: Dictionary = builder._resolve_palette(heap)
	var p_stack: Dictionary = builder._resolve_palette(stack)
	var p_endless: Dictionary = builder._resolve_palette({})

	_check(p_heap.floor.albedo_color.is_equal_approx(heap.floor_color),
			"Heap floor material does not use the Heap floor colour")
	_check(not p_heap.floor.albedo_color.is_equal_approx(LEGACY_FLOOR),
			"Heap floor still reads as the legacy gray")
	_check(not p_heap.floor.albedo_color.is_equal_approx(p_stack.floor.albedo_color),
			"Heap and Stack floors look the same (layers not visually distinct)")
	_check(not p_heap.wall.albedo_color.is_equal_approx(p_stack.wall.albedo_color),
			"Heap and Stack walls look the same")
	_check(p_endless.floor.albedo_color.is_equal_approx(LEGACY_FLOOR),
			"ENDLESS floor is not the authored gray (legacy look changed)")

	# --- B. Environment (fog + ambient) ------------------------------------------
	builder._apply_environment(heap, false)
	var env: Environment = builder._environment
	_check(env != null, "no scene environment captured")
	if env != null:
		_check(env.fog_enabled, "Heap did not enable fog")
		_check(is_equal_approx(env.fog_density, heap.fog_density),
				"Heap fog density wrong (%.4f)" % env.fog_density)
		_check(env.fog_light_color.is_equal_approx(heap.fog_color),
				"Heap fog colour wrong")
		_check(is_equal_approx(env.ambient_light_energy, heap.ambient_energy),
				"Heap ambient energy wrong (%.3f)" % env.ambient_light_energy)
		# ENDLESS restores the authored environment (fog off).
		builder._apply_environment({}, false)
		_check(not env.fog_enabled, "ENDLESS should restore the fog-off environment")

	# --- C. Render: the built Heap shell actually carries the Heap colour ---------
	RunManager.run_seed = 4242
	await builder.build_room(2, heap)  # global room 2 = Heap sector 2 (combat)
	var floor_body: Node = main.get_node_or_null("NavRegion/GeneratedShell/Floor")
	_check(floor_body != null, "no procedural shell floor was built")
	if floor_body != null:
		var mesh: MeshInstance3D = null
		for child in floor_body.get_children():
			if child is MeshInstance3D:
				mesh = child
		_check(mesh != null, "shell floor has no mesh")
		if mesh != null:
			var mat: ShaderMaterial = mesh.material_override as ShaderMaterial
			_check(mat != null, "shell floor was not toon-shaded (expected a ShaderMaterial)")
			if mat != null:
				var albedo: Color = mat.get_shader_parameter("albedo")
				_check(albedo.is_equal_approx(heap.floor_color),
						"rendered Heap floor colour (%s) is not the Heap palette" % albedo)
