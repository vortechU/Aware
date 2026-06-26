extends Node
## Throwaway visual harness (NOT shipped game code): builds REAL generated kit'd rooms of
## notched shapes (a T and a plus) through the actual RoomBuilder and screenshots them, so
## the Pass-C notched-shell skinning can be eyeballed. Must run NON-headless (real D3D12).
##   Godot.exe --path <proj> res://tools/kit_shapes_preview.tscn
## Saves res://tools/kit_shapes_t.png and res://tools/kit_shapes_plus.png.

var _main: Node
var _builder: Node
var _cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	for _i in 8:
		await get_tree().process_frame
	_builder = _main.get_node("RoomBuilder")

	var player := _main.get_node_or_null("Player") as Node3D
	if player != null:
		player.visible = false
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).set_process(false)
		(e as Node).set_physics_process(false)
		(e as Node3D).visible = false

	_cam = Camera3D.new()
	_cam.fov = 74.0
	add_child(_cam)
	_cam.make_current()

	# Retire the authored CSG arena + settle, else its 44x44 floor bakes/draws over the notch.
	_builder.call("_retire_authored_interior")
	await get_tree().process_frame
	await get_tree().process_frame

	var rb: GDScript = load("res://scripts/run/room_builder.gd")
	var t_idx: int = rb.FOOTPRINTS.size() + rb.L_FOOTPRINTS.size()         # first T
	var plus_idx: int = t_idx + rb.T_FOOTPRINTS.size()                     # first plus
	var heap: Dictionary = LayerCatalog.profile_for_room(1)

	await _shoot(heap, t_idx, "res://tools/kit_shapes_t.png")
	await _shoot(heap, plus_idx, "res://tools/kit_shapes_plus.png")
	get_tree().quit()


func _shoot(layer: Dictionary, footprint_idx: int, out_path: String) -> void:
	RunManager.run_seed = 24680 + footprint_idx
	var profile := {
		"kit": "space_station",
		"footprint_pool": [footprint_idx],
		"archetype_pool": ["scattered_cover"],
		"floor_color": layer.get("floor_color", Color.WHITE),
		"wall_color": layer.get("wall_color", Color.WHITE),
		"struct_color": layer.get("struct_color", Color.WHITE),
	}
	await _builder.build_room(2, profile)
	var half: Vector2 = _builder.get("_room_half")
	# Elevated south-of-centre shot looking north, to reveal the notched footprint.
	_cam.position = Vector3(0.0, 11.0, half.y + 2.0)
	_cam.look_at(Vector3(0.0, 0.5, -half.y * 0.35), Vector3.UP)
	for _i in 16:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_path))
	print("KIT_SHAPES_SAVED ", out_path)
