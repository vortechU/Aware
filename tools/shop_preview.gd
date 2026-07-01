extends Node3D
## Interactive look-and-feel harness (NOT shipped game code) for the in-world
## holographic shop. Run NON-headless (real D3D12 -- the panel shader doesn't
## compile headless) and click around:
##   Godot.exe --path . res://tools/shop_preview.tscn
## A green-fogged computer-world room, a lit turntable on the right, and the
## ShopTerminal overlay on the left. Hover a card -> the turntable swaps + spins
## that item; PURCHASE spends Cores; CLOSE / ESC quits. Mirrors the reference
## Roblox "Tuck Shop" screenshot in the project's own palette.

const TERMINAL := preload("res://scripts/ui/shop_terminal.gd")
const TURNTABLE := preload("res://scripts/world/shop_turntable.gd")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()

	var turntable: ShopTurntable = TURNTABLE.new()
	turntable.position = Vector3(4.2, 0, -1.5)
	add_child(turntable)

	var cam := Camera3D.new()
	cam.position = Vector3(0.8, 1.7, 4.4)
	cam.fov = 66.0
	add_child(cam)
	cam.look_at(Vector3(3.4, 1.3, -1.0))
	cam.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	var term: ShopTerminal = TERMINAL.new()
	layer.add_child(term)
	var catalog := _catalog()
	term.set_catalog(catalog)
	# Demo a couple of lifecycle states for the look: one owned-but-unequipped
	# (shows EQUIP) and one equipped (shows EQUIPPED + the accent border).
	term.mark_owned("neon_chair")
	term.mark_owned("core_orb")
	term.mark_equipped("core_orb", "Effects")
	term.item_focused.connect(turntable.show_item)
	term.closed.connect(func() -> void: get_tree().quit())

	turntable.show_item(catalog[2])  # something on the pedestal before first hover

	# Optional one-shot capture for tuning/sharing: `... res://tools/shop_preview.tscn -- --shot`.
	# Hovers an item so the turntable shows the hero chair, then saves a PNG.
	if "--shot" in OS.get_cmdline_user_args():
		term.focus_item(catalog[0])
		await _shoot("res://tools/shop_preview.png")
		# A second, forced-tilt shot: a scripted capture has no real cursor to hover
		# the panel with, so freeze the terminal's own per-frame easing and set the
		# "3D tilt" shader uniforms directly to prove the reactive warp looks right.
		# `panel_size` has to be set too since `_process` (which normally feeds it
		# every frame) is now frozen -- the vertex shear scales by that size.
		term.set_process(false)
		var panel_size: Vector2 = term.get_node("Frame/TiltView").size
		term._tilt_material.set_shader_parameter("panel_size", panel_size)
		term._tilt_material.set_shader_parameter("tilt", Vector2(0.7, 0.35))
		await _shoot("res://tools/shop_preview_tilt.png")
		get_tree().quit()


func _shoot(path: String) -> void:
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("SHOP_PREVIEW_SAVED ", path)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.5, 0.4)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.35, 0.25)
	env.fog_density = 0.06
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mi.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.05, 0.10, 0.10)
	fmat.metallic = 0.6
	fmat.roughness = 0.4
	floor_mi.material_override = fmat
	add_child(floor_mi)

	var key := OmniLight3D.new()
	key.position = Vector3(2.5, 3.0, 1.5)
	key.light_color = Color(0.4, 1.0, 0.7)
	key.light_energy = 2.0
	key.omni_range = 14.0
	add_child(key)


func _catalog() -> Array:
	return ShopCatalog.items()
