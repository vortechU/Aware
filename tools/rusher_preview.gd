extends Node3D
## Throwaway visual harness (NOT shipped): spawns a regular enemy beside a Rusher
## so the archetype's leaner, hazard-orange silhouette can be eyeballed (cel-shaded
## by ToonApplicator, like in a real run). Must run NON-headless (real D3D12).
## The rusher's LOOK here mirrors RunDirector._outfit_rusher's visual block.
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

	add_child(_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0), Color(0.3, 0.31, 0.34)))

	if get_tree().current_scene == null:
		get_tree().current_scene = self

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.position = Vector3(0, 1.6, 5.2)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

	# Regular enemy on the left.
	var regular: Node3D = ENEMY.instantiate()
	regular.position = Vector3(-1.4, 0.1, 0)
	add_child(regular)

	# Rusher on the right -- apply the same look outfit before add_child so
	# ToonApplicator reads the orange (exactly as the real spawn does).
	var rusher: Node3D = ENEMY.instantiate()
	_apply_rusher_look(rusher)
	rusher.position = Vector3(1.4, 0.1, 0)
	add_child(rusher)

	# Let ToonApplicator's pass run + a frame settle, then capture.
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("rusher_preview_out.png")
	get_tree().quit()


func _apply_rusher_look(enemy: Node) -> void:
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(0.85, 1.0, 0.85)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.85, 0.34, 0.05)
	body_material.emission_enabled = true
	body_material.emission = Color(1.0, 0.45, 0.05)
	body_material.emission_energy_multiplier = 0.45
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(1.0, 0.7, 0.2)
	head_material.emission_enabled = true
	head_material.emission = Color(1.0, 0.65, 0.15)
	head_material.emission_energy_multiplier = 0.5
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material


func _save(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/" + file_name)
	img.save_png(path)
	print("RUSHER_PREVIEW_SAVED ", path)


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
