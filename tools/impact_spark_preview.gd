extends Node3D
## Throwaway visual harness (NOT shipped): verifies weapon_manager._spawn_impact
## bursts its spark particles at the CONTACT POINT, not the world origin (the bug
## was that CPUParticles3D's default emitting=true fired at the origin before
## global_position was set). A red marker sits at the origin and a green marker at
## the intended impact point, so a regression (sparks at the red marker) is obvious.
## Must run NON-headless. Saves a PNG.

const PLAYER := preload("res://scenes/player/player.tscn")
const IMPACT_POINT := Vector3(-2.0, 1.5, -3.0)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.6)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)

	add_child(_marker(Vector3.ZERO, Color(1, 0.2, 0.2)))      # origin (bug location)
	add_child(_marker(IMPACT_POINT, Color(0.2, 1, 0.3)))      # intended contact point

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.position = Vector3(2.5, 2.2, 4.0)
	add_child(cam)
	cam.look_at(Vector3(-1, 1, -1.5))  # after add_child: look_at needs to be in-tree
	cam.make_current()

	if get_tree().current_scene == null:
		get_tree().current_scene = self

	var player := PLAYER.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.global_position = Vector3(10, 0, 10)  # out of frame; only its wm is used
	var wm := player.get_node("Head/Bob/Recoil/Camera/WeaponManager")

	# Fire several impacts at the green point; with the fix the sparks burst there.
	for i in 4:
		wm._spawn_impact(IMPACT_POINT, Vector3(0, 0, 1))

	# Particles emit on their first process tick (now at the correct transform), so
	# give them a couple of frames to appear, then capture before they fall/fade.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/impact_spark_preview_out.png")
	img.save_png(path)
	print("IMPACT_SPARK_PREVIEW_SAVED ", path)
	get_tree().quit()


func _marker(pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.position = pos
	return m
