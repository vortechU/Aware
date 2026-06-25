extends Node
## NON-headless visual harness (kept, like toon_preview / transition_preview):
## renders the real run_hud upgrade screen so the card glitch shader can be
## eyeballed. The --headless renderer can't compile shaders, so this is the only
## way to see the look without a live run. Shows the three states at once --
## Card1 mid CLICK burst (intensity 1.0), Card2 HOVER (0.5), Card3 resting IDLE
## (0.12) -- freezes the driver, renders, saves a PNG, then quits.
## Run NON-headless: Godot_v4.6.3.exe --path . res://tools/glitch_preview.tscn

const RUN_HUD := preload("res://scenes/ui/run_hud.tscn")


func _ready() -> void:
	# Opaque backdrop behind the HUD CanvasLayer so the glitch reads against
	# something (and the PNG isn't transparent).
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var hud := RUN_HUD.instantiate()
	add_child(hud)

	var choices: Array[Dictionary] = [
		{"id": "damage", "title": "DAMAGE +20%", "desc": "Rounds hit harder."},
		{"id": "move_speed", "title": "MOVE SPEED +10%", "desc": "Run faster."},
		{"id": "max_health", "title": "MAX HEALTH +25", "desc": "Tougher hide."},
	]
	hud.call("show_upgrade_choices", choices, "CHOOSE AN UPGRADE")

	# Let the container lay the cards out, then freeze the glitch driver so our
	# hand-set uniforms survive to the rendered frame.
	for i in 6:
		await get_tree().process_frame
	hud.set_process(false)

	# Drive the single overlay directly: resting IDLE shimmer across the whole
	# card row, with the middle card pushed to a full CLICK burst (1.0). Hover
	# (0.5) is the same effect at an in-between level.
	var mat := (hud.get_node("UpgradePanel/Glitch") as ColorRect).material as ShaderMaterial
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var cards := hud.get_node("UpgradePanel/Center/Box/Cards")
	var first := (cards.get_child(0) as Control).get_global_rect()
	var last := (cards.get_child(2) as Control).get_global_rect()
	var mid := (cards.get_child(1) as Control).get_global_rect()
	mat.set_shader_parameter("cards_min", first.position / vp)
	mat.set_shader_parameter("cards_max", (last.position + last.size) / vp)
	mat.set_shader_parameter("base_intensity", 0.18)
	mat.set_shader_parameter("focus_rect", Vector4(
		mid.position.x / vp.x, mid.position.y / vp.y,
		(mid.position.x + mid.size.x) / vp.x, (mid.position.y + mid.size.y) / vp.y))
	mat.set_shader_parameter("focus_intensity", 1.0)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/glitch_preview_out.png")
	img.save_png(path)
	print("GLITCH_PREVIEW_SAVED ", path)
	get_tree().quit()
