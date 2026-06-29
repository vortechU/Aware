extends Node
## Throwaway visual harness (NOT shipped game code): renders the speed-line / wind
## overlay shader at a few intensities so the look can be eyeballed/tuned. Must run
## NON-headless (real D3D12 -- shaders don't compile headless):
##   Godot.exe --path <proj> res://tools/speed_lines_preview.tscn
## Saves res://tools/speed_lines_low.png / _mid.png / _full.png.

const SHADER := preload("res://shaders/speed_lines.gdshader")

var _mat: ShaderMaterial


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# A representative dark "game" backdrop so the additive streaks read in context.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.13, 0.16)
	layer.add_child(bg)
	# A bright centre patch stands in for a lit scene / crosshair area.
	var center := ColorRect.new()
	center.color = Color(0.32, 0.36, 0.4)
	center.size = Vector2(360, 240)
	center.position = get_viewport().get_visible_rect().size * 0.5 - center.size * 0.5
	layer.add_child(center)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var size := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", size.x / size.y)
	rect.material = _mat
	layer.add_child(rect)

	await _shoot(0.35, "res://tools/speed_lines_low.png")
	await _shoot(0.65, "res://tools/speed_lines_mid.png")
	await _shoot(1.0, "res://tools/speed_lines_full.png")

	print("SPEED_LINES_PREVIEW_SAVED")
	get_tree().quit()


func _shoot(intensity: float, path: String) -> void:
	_mat.set_shader_parameter("intensity", intensity)
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("SAVED ", path)
