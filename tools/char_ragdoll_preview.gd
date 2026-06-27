extends Node3D
## Throwaway visual harness (NOT shipped game code): spawns a rigged enemy, kills
## it, and lets the PhysicalBone3D death ragdoll simulate, screenshotting the flop
## mid-fall and once settled so the ragdoll can be eyeballed/tuned. Must run
## NON-headless (real D3D12 + physics):
##   Godot.exe --path <proj> res://tools/char_ragdoll_preview.tscn
## Saves res://tools/char_ragdoll_mid.png and res://tools/char_ragdoll_settled.png.

const ENEMY: PackedScene = preload("res://scenes/enemies/enemy.tscn")

var _cam: Camera3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)

	# Floor on the WORLD layer (1) so the ragdoll bones (mask = world) rest on it.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(30, 1, 30)
	fs.shape = fbox
	fs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fs)
	var fmesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fmesh.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.13, 0.14, 0.16)
	fmesh.material_override = gmat
	floor_body.add_child(fmesh)
	add_child(floor_body)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_cam.position = Vector3(2.6, 1.6, -4.2)
	_cam.look_at(Vector3(0, 0.6, 0.4), Vector3.UP)

	var enemy: Node3D = ENEMY.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	enemy.set_physics_process(false)  # no nav; we only want the death ragdoll
	# Settle the rig.
	for _i in 6:
		await get_tree().physics_frame

	# Kill through the real damage path; gentle push so it crumples near the spot.
	enemy.get_node("BodyHitbox").call("take_hit", 99999.0, Vector3(0.15, -0.2, 0.4))

	# Simulate; capture mid-flop then settled, framing the body corpse each time.
	await _wait_physics(40)
	await _shoot("res://tools/char_ragdoll_mid.png")
	await _wait_physics(110)
	await _shoot("res://tools/char_ragdoll_settled.png")
	print("CHAR_RAGDOLL_PREVIEW_SAVED")
	get_tree().quit()


func _frame_corpse() -> void:
	# Point the camera at the body corpse (the enemy_corpse member that owns a Visual).
	for c in get_tree().get_nodes_in_group("enemy_corpse"):
		var n := c as Node3D
		if n != null and n.get_node_or_null("Visual") != null:
			_cam.position = n.global_position + Vector3(1.8, 1.2, -2.6)
			_cam.look_at(n.global_position, Vector3.UP)
			return


func _wait_physics(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _shoot(path: String) -> void:
	_frame_corpse()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("SAVED ", path)
