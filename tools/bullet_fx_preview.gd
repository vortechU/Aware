extends Node3D
## Throwaway visual harness (NOT shipped): drives BulletFX directly so the bullet
## tracers + impact decals can be eyeballed. Builds a lit floor + wall, fires a
## scatter of impacts onto the wall and a few tracers across the view, renders, and
## saves a PNG. Must run NON-headless (real D3D12), since --headless can't draw the
## decals/emissive meshes.

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	# Wall the decals land on (facing +Z toward the camera), plus a floor.
	var wall := _box(Vector3(8, 4, 0.4), Vector3(0, 2, -3), Color(0.5, 0.5, 0.55))
	add_child(wall)
	add_child(_box(Vector3(12, 0.4, 12), Vector3(0, 0, 0), Color(0.3, 0.31, 0.34)))

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.position = Vector3(0, 2, 5.0)
	add_child(cam)
	cam.make_current()

	# BulletFX parents its nodes to the current scene; ensure that's us.
	if get_tree().current_scene == null:
		get_tree().current_scene = self

	# Scatter impacts across the wall face (normal points +Z, out of the wall).
	for i in 24:
		var p := Vector3(randf_range(-3.2, 3.2), randf_range(0.6, 3.4), -2.8)
		GameEvents.bullet_impact.emit(p, Vector3(0, 0, 1))

	# Let the decals settle / render before adding the short-lived tracers.
	for i in 4:
		await get_tree().process_frame

	# Tracers fade in ~0.06 s and their tween first ticks NEXT process frame, so
	# emit now and capture THIS frame's draw (no process_frame in between) to catch
	# them at full alpha.
	var muzzle := Vector3(0.4, 1.7, 1.6)
	for i in 7:
		var to := Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 3.0), -2.8)
		GameEvents.bullet_tracer.emit(muzzle, to)

	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/bullet_fx_preview_out.png")
	img.save_png(path)
	print("BULLET_FX_PREVIEW_SAVED ", path)
	get_tree().quit()


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	m.material_override = mat
	m.position = pos
	return m
