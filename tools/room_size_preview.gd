extends Node3D
## Throwaway visual harness (NOT shipped): renders a procedurally built room at a
## square, a wide, a deep and an L-shaped footprint so the variable shell can be
## eyeballed for alignment (walls fully enclose the floor, floor doesn't overhang
## into the void, the L's notch corner is walled off) and to confirm ToonApplicator
## cel-shades the new shell. Must run NON-headless (real D3D12). Saves four top-down PNGs.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node3D = MAIN.instantiate()
	add_child(main)
	if get_tree().current_scene == null:
		get_tree().current_scene = self

	# Let GameManager finish its room-1 bake / spawn, then clear the clutter so the
	# top-down shot shows only the procedural shell + obstacles.
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for child in main.get_node("Pickups").get_children():
		child.queue_free()
	(main.get_node("Player") as Node3D).visible = false

	var builder: Node = main.get_node("RoomBuilder")
	builder.call("_retire_authored_interior")

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0, 70, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.size = 60.0
	cam.far = 200.0
	add_child(cam)
	cam.make_current()

	await _build_and_capture(builder, Vector2(21.0, 21.0), 101, "room_footprint_square.png")
	await _build_and_capture(builder, Vector2(27.0, 16.0), 202, "room_footprint_wide.png")
	await _build_and_capture(builder, Vector2(16.0, 27.0), 303, "room_footprint_deep.png")
	await _build_and_capture(builder, Vector2(24.0, 24.0), 404, "room_footprint_L.png",
			Vector2(16.0, 16.0), 1)  # NE-corner L
	get_tree().quit()


func _build_and_capture(builder: Node, half: Vector2, seed_value: int, file_name: String,
		notch := Vector2.ZERO, corner := 1) -> void:
	builder.set("_room_half", half)
	builder.set("_notch", notch)
	builder.set("_notch_corner", corner)
	builder.set("_inner_limit", half - Vector2(2.0, 2.0))
	builder.set("_player_spawn_pos", Vector3(0.0, 0.0, half.y - 3.0))
	builder.call("_compute_notch_rect")
	builder.call("_build_shell")
	builder.call("_clear_generated")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var boxes: Array = builder.call("_descriptors_for", "scattered_cover", rng)
	builder.call("_instantiate_boxes", boxes)

	# A couple frames so the freed authored shell leaves and the new meshes draw.
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/" + file_name)
	img.save_png(path)
	print("ROOM_SIZE_PREVIEW_SAVED ", path, "  (half=", half, ", boxes=", boxes.size(), ")")
