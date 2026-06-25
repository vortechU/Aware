extends Node3D
## Throwaway visual harness (NOT shipped): renders the first-person viewmodel with
## a wall jammed right in front of the muzzle, so the render-on-top wall-clip fix
## can be eyeballed -- the gun should draw OVER the wall (no clipping), and its cel
## outline should still read as a thin silhouette, not flood the gun with ink.
## Must run NON-headless (real D3D12). Saves a PNG, then quits.

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

	# A wall ~0.45 m in front of the camera (player faces -Z), at head height.
	# Without the fix the gun would clip into / vanish behind this; with it the gun
	# draws on top. Bright surface so the gun-over-wall read is obvious.
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 4.0, 0.3)
	wall.mesh = box
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.70, 0.30, 0.30)
	wall.material_override = wmat
	wall.position = Vector3(0.0, 1.62, -0.45)
	add_child(wall)

	for i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/weapon_clip_preview_out.png")
	img.save_png(path)
	print("WEAPON_CLIP_PREVIEW_SAVED ", path)
	get_tree().quit()
