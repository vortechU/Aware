extends Node3D
## Throwaway visual harness (NOT shipped): a regular enemy beside a Grenadier so
## the bulky olive silhouette reads, plus a live grenade frozen mid-arc with its
## ground "danger ring" telegraph at the target. Must run NON-headless (D3D12).
## The grenadier's LOOK mirrors RunDirector._outfit_grenadier's visual block.
const ENEMY := preload("res://scenes/enemies/enemy.tscn")
const GRENADE := preload("res://scripts/enemies/grenade.gd")


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
	# A low cover slab between the grenadier and the target it lobs over.
	add_child(_box(Vector3(0.6, 1.2, 2.0), Vector3(3.2, 0.6, 0), Color(0.26, 0.27, 0.31)))

	if get_tree().current_scene == null:
		get_tree().current_scene = self

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.position = Vector3(2.0, 2.3, 9.2)
	add_child(cam)
	cam.look_at(Vector3(2.0, 0.9, 0), Vector3.UP)
	cam.make_current()

	var regular: Node3D = ENEMY.instantiate()
	regular.position = Vector3(-1.7, 0.1, 0)
	add_child(regular)

	var grenadier: Node3D = ENEMY.instantiate()
	_apply_grenadier_look(grenadier)
	grenadier.position = Vector3(1.0, 0.1, 0)
	add_child(grenadier)

	# A grenade frozen mid-lob, with its danger ring on the ground past the cover.
	var grenade: Node3D = GRENADE.new()
	add_child(grenade)
	grenade.global_position = Vector3(1.2, 1.6, 0)
	grenade.call("launch_at", Vector3(5.6, 0.1, 0))
	for i in 11:
		await get_tree().process_frame
	grenade.set_physics_process(false)  # freeze mid-arc for the capture

	await RenderingServer.frame_post_draw
	_save("grenadier_preview_out.png")
	get_tree().quit()


func _apply_grenadier_look(enemy: Node) -> void:
	var visual := enemy.get_node("Visual") as Node3D
	visual.scale = Vector3(1.15, 1.0, 1.15)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.32, 0.46, 0.16)
	body_material.emission_enabled = true
	body_material.emission = Color(0.4, 0.8, 0.2)
	body_material.emission_energy_multiplier = 0.4
	(enemy.get_node("Visual/Body") as MeshInstance3D).material_override = body_material
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.7, 0.85, 0.4)
	head_material.emission_enabled = true
	head_material.emission = Color(0.6, 0.9, 0.3)
	head_material.emission_energy_multiplier = 0.5
	(enemy.get_node("Visual/Head") as MeshInstance3D).material_override = head_material


func _save(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/" + file_name)
	img.save_png(path)
	print("GRENADIER_PREVIEW_SAVED ", path)


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
