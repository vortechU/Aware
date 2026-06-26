extends Node
## Throwaway visual harness (NOT shipped game code): skins a plain box room with the
## RoomKit space-station kit, recoloured by the REAL per-layer palette (Heap vs Stack),
## and screenshots each so the kit look + per-layer recolouring can be eyeballed before
## wiring it into the generator. Must run NON-headless (real D3D12) so the kit's meshes
## + materials actually draw:
##   Godot.exe --path <proj> res://tools/kit_preview.tscn
## Saves res://tools/kit_preview_heap.png and res://tools/kit_preview_stack.png.

const HALF := Vector2(11.0, 11.0)  # 22 x 22 m room
const HEIGHT := 5.0
const PROPS := "res://Assets/kenney_space-station-kit/Models/GLB format/"

var _cam: Camera3D
var _sun: DirectionalLight3D


func _ready() -> void:
	# Lighting + environment (the preview builds from scratch, no main.tscn).
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	_sun.light_energy = 1.6
	add_child(_sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.68, 0.75)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.fov = 78.0
	add_child(_cam)
	_cam.make_current()

	# Real per-layer palettes straight from the catalog (Heap = room 1, Stack = room 7).
	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	var stack: Dictionary = LayerCatalog.profile_for_room(7)
	await _shoot_room(heap, "res://tools/kit_preview_heap.png")
	await _shoot_room(stack, "res://tools/kit_preview_stack.png")
	get_tree().quit()


func _shoot_room(profile: Dictionary, out_path: String) -> void:
	# Fresh room each time so the two palettes don't overlap.
	var old := get_node_or_null("Room")
	if old != null:
		old.free()
	var room := Node3D.new()
	room.name = "Room"
	add_child(room)

	var floor_tint: Color = profile.get("floor_color", Color.WHITE)
	var wall_tint: Color = profile.get("wall_color", Color.WHITE)
	var struct_tint: Color = profile.get("struct_color", Color.WHITE)

	var kit := RoomKit.space_station()
	kit.skin_box(room, HALF, HEIGHT, floor_tint, wall_tint)

	# A scatter of cover props, tinted to the same layer palette.
	for spot in [Vector2(-5.0, -4.0), Vector2(4.0, 2.0), Vector2(-2.0, 6.0), Vector2(6.0, -6.0)]:
		var crate := (load(PROPS + "container-tall.glb") as PackedScene).instantiate() as Node3D
		room.add_child(crate)
		crate.position = Vector3(spot.x, 0.0, spot.y)
		crate.scale = Vector3(2.2, 2.2, 2.2)
		kit.tint_node(crate, struct_tint)

	_cam.position = Vector3(0.0, 2.2, HALF.y - 1.0)
	_cam.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	for _i in 16:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_path))
	print("KIT_PREVIEW_SAVED ", out_path)
