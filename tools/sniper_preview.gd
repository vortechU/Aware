extends Node3D
## Throwaway visual harness (NOT shipped): a regular enemy beside a Sniper so the
## cold-cyan, taller silhouette + the charge telegraph beam can be eyeballed
## (cel-shaded by ToonApplicator, like in a real run). Must run NON-headless.
## The sniper's LOOK here mirrors RunDirector._outfit_sniper's visual block; the
## beam is driven manually (AI frozen) so the telegraph renders for the capture.
const ENEMY := preload("res://scenes/enemies/enemy.tscn")


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.6)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	add_child(sun)

	add_child(_box(Vector3(24, 1, 24), Vector3(0, -0.5, 0), Color(0.3, 0.31, 0.34)))
	# A target stand-in the sniper's beam points at.
	add_child(_box(Vector3(0.6, 1.8, 0.6), Vector3(5.5, 0.9, 0), Color(0.25, 0.26, 0.3)))

	if get_tree().current_scene == null:
		get_tree().current_scene = self

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.position = Vector3(1.7, 2.1, 9.0)
	add_child(cam)
	cam.look_at(Vector3(1.7, 0.9, 0), Vector3.UP)
	cam.make_current()

	# Regular enemy on the left for colour comparison.
	var regular: Node3D = ENEMY.instantiate()
	regular.position = Vector3(-1.6, 0.1, 0)
	add_child(regular)

	# Sniper on the right, charging a beam toward the target.
	var sniper: Node3D = ENEMY.instantiate()
	_apply_sniper_look(sniper)
	sniper.set("is_sniper", true)
	sniper.position = Vector3(1.4, 0.1, 0)
	add_child(sniper)
	await get_tree().process_frame  # let _ready build the muzzle/light
	sniper.set_physics_process(false)  # freeze the AI; we drive the beam by hand
	sniper.call("_ensure_sniper_beam")
	sniper.set("_sniper_aim_point", Vector3(5.5, 1.1, 0))

	for i in 4:
		sniper.call("_update_sniper_beam", true, 0.85)
		await get_tree().process_frame
	sniper.call("_update_sniper_beam", true, 0.85)
	await RenderingServer.frame_post_draw
	_save("sniper_preview_out.png")
	get_tree().quit()


func _apply_sniper_look(enemy: Node) -> void:
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(0.85, 1.1, 0.85)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.1, 0.5, 0.62)
	body_material.emission_enabled = true
	body_material.emission = Color(0.15, 0.7, 0.9)
	body_material.emission_energy_multiplier = 0.4
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.75, 0.92, 1.0)
	head_material.emission_enabled = true
	head_material.emission = Color(0.5, 0.85, 1.0)
	head_material.emission_energy_multiplier = 0.6
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material


func _save(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/" + file_name)
	img.save_png(path)
	print("SNIPER_PREVIEW_SAVED ", path)


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
