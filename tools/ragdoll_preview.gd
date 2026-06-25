extends Node3D
## Throwaway visual harness (NOT shipped): spawns an enemy, kills it, and captures
## two frames of the death ragdoll (launched + tumbling) so the corpse physics can
## be eyeballed. Must run NON-headless (real D3D12). Saves two PNGs.

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

	# Floor + a low wall to show the corpse tumbling against the world.
	add_child(_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0), Color(0.3, 0.31, 0.34)))

	if get_tree().current_scene == null:
		get_tree().current_scene = self

	# A dummy "player" so the enemy launches AWAY from it (toward +X here).
	var dummy := CharacterBody3D.new()
	dummy.add_to_group("player")
	add_child(dummy)
	dummy.global_position = Vector3(-8, 0, 0)

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.position = Vector3(0, 3.2, 9.0)
	add_child(cam)
	cam.look_at(Vector3(2.5, 1.0, 0))
	cam.make_current()

	var enemy: Node3D = ENEMY.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	for i in 8:
		await get_tree().process_frame

	# A headshot from the dummy's side (shot travels +X): the head pops off, the gun
	# drops, and the body flies along the bullet -- the full polish in one frame.
	enemy.get_node("HeadHitbox").call("take_hit", 99999.0, dummy.global_position,
			enemy.global_position + Vector3(0, 1.62, 0), Vector3(1, 0, 0))

	# Frame 1: just launched (airborne).
	for i in 9:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("ragdoll_preview_1.png")

	# Frame 2: tumbling toward the ground.
	for i in 22:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("ragdoll_preview_2.png")

	get_tree().quit()


func _save(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/" + file_name)
	img.save_png(path)
	print("RAGDOLL_PREVIEW_SAVED ", path)


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
