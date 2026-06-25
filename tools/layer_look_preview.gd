extends Node
## Throwaway visual harness (NOT shipped game code): builds a real CAMPAIGN Heap
## room and a real Stack room from the actual generator and screenshots each, so the
## per-layer look (surface palette + fog + lighting) can be eyeballed without playing
## through. Must run NON-headless (real D3D12) so the toon shader + fog actually draw:
##   Godot.exe --path <proj> res://tools/layer_look_preview.tscn
## Saves res://tools/layer_look_heap.png and res://tools/layer_look_stack.png.

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

	# Clean architectural shot: hide the player + freeze/hide the room-1 squad.
	var player := _main.get_node_or_null("Player") as Node3D
	if player != null:
		player.visible = false
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).set_process(false)
		(e as Node).set_physics_process(false)
		(e as Node3D).visible = false

	# Our own camera (made current so the player cam isn't used).
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	_cam.make_current()

	RunManager.run_seed = 4242
	await _shoot(LayerCatalog.profile_for_room(2), 2, "res://tools/layer_look_heap.png")
	await _shoot(LayerCatalog.profile_for_room(7), 8, "res://tools/layer_look_stack.png")
	get_tree().quit()


func _shoot(profile: Dictionary, room: int, out_path: String) -> void:
	await _builder.build_room(room, profile)
	# Frame the room from just inside the south wall, looking north down its length.
	var half: Vector2 = _builder.get("_room_half")
	_cam.position = Vector3(0.0, 6.0, half.y - 1.5)
	_cam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	for _i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_path))
	print("LAYER_LOOK_PREVIEW_SAVED ", out_path)
