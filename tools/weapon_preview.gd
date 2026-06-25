extends Node3D
## Throwaway visual harness (NOT shipped): renders the first-person weapon
## viewmodel through the real player.tscn so the toon pass on the gun can be
## eyeballed. The player is process-disabled so it neither falls nor reads input;
## WeaponManager._ready still builds + positions the rig, and ToonApplicator
## cel-shades it. Must run NON-headless (real D3D12). Saves a PNG, then quits.

const PLAYER := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.23)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.43, 0.52)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var player := PLAYER.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED  # no fall, no input, no rig anim
	add_child(player)
	var cam := player.get_node("Head/Bob/Recoil/Camera") as Camera3D
	cam.make_current()

	for i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/weapon_preview_out.png")
	img.save_png(path)
	print("WEAPON_PREVIEW_SAVED ", path)
	get_tree().quit()
