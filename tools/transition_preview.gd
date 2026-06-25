extends Node3D
## Throwaway visual harness (NOT shipped game code): renders the matrix-spiral
## room transition so the look can be eyeballed without playing through a clear.
## Must run NON-headless (real D3D12) so the shaders actually compile:
##   Godot.exe --path <proj> res://tools/transition_preview.tscn
## Saves two PNGs, then quits:
##   res://tools/transition_preview_out.png  (full-screen matrix wipe at cover=1)
##   res://tools/gate_preview_out.png         (the exit gate portal in 3D)

const SPIRAL_SHADER := preload("res://shaders/matrix_spiral.gdshader")          # canvas overlay
const PORTAL_SHADER := preload("res://shaders/matrix_spiral_portal.gdshader")   # 3D gate pane

var _overlay: ColorRect
var _overlay_mat: ShaderMaterial


func _ready() -> void:
	# Dark environment so the green portal/spiral pops.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.2)
	env.ambient_light_energy = 1.0
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.1, 6.0)
	cam.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()

	# A back wall so the translucent portal pane has something behind it.
	var wall := CSGBox3D.new()
	wall.size = Vector3(16.0, 8.0, 0.4)
	wall.position = Vector3(0.0, 3.0, -1.5)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.11, 0.13)
	wall.material = wm
	add_child(wall)

	# The real exit gate, wired exactly as RunDirector does it.
	var gate := ExitGate.new()
	gate.set_portal_shader(PORTAL_SHADER)
	add_child(gate)
	gate.global_position = Vector3.ZERO
	gate.scale = Vector3.ONE  # skip the spawn pop for the still

	# Full-screen matrix wipe overlay (the canvas_item shader), hidden at first.
	var layer := CanvasLayer.new()
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = SPIRAL_SHADER
	_overlay_mat.set_shader_parameter("cover", 0.0)
	_overlay.material = _overlay_mat
	layer.add_child(_overlay)

	# Let the shaders compile and the gate settle, then grab the gate-only still.
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("res://tools/gate_preview_out.png")

	# Now drop the full-screen wipe to full cover and grab the transition still.
	_overlay_mat.set_shader_parameter("cover", 1.0)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("res://tools/transition_preview_out.png")

	get_tree().quit()


func _save(res_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(res_path)
	img.save_png(path)
	print("PREVIEW_SAVED ", path)
