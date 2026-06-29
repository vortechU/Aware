extends Node3D
## Throwaway visual harness (NOT shipped game code): spawns a rigged enemy, kills it,
## and screenshots the death "deletion" glitch-dissolve at a few moments so the look
## can be eyeballed/tuned. Must run NON-headless (real D3D12 -- shaders don't compile
## headless):
##   Godot.exe --path <proj> res://tools/deletion_preview.tscn
## Saves res://tools/deletion_intact.png / deletion_early.png / deletion_mid.png.

const ENEMY: PackedScene = preload("res://scenes/enemies/enemy.tscn")

var _cam: Camera3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	# A touch of glow so the hot dissolve edges + data bits bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.2
	we.environment = env
	add_child(we)

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
	gmat.albedo_color = Color(0.11, 0.12, 0.14)
	fmesh.material_override = gmat
	floor_body.add_child(fmesh)
	add_child(floor_body)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()
	# Front 3/4 view of the standing enemy (it faces -Z, so the camera sits at -Z).
	_cam.position = Vector3(1.9, 1.2, -3.4)
	_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)

	var enemy: Node3D = ENEMY.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	enemy.set_physics_process(false)  # no nav; we only want the death VFX
	for _i in 8:
		await get_tree().process_frame

	await _shoot("res://tools/deletion_intact.png")   # before deletion

	# Kill through the real damage path -> DeletionVFX freezes + dissolves in place.
	enemy.get_node("BodyHitbox").call("take_hit", 99999.0, Vector3(0, 1, 10))

	# The dissolve tween runs ~DISSOLVE_TIME on process; capture early then mid-wipe.
	await get_tree().create_timer(0.14).timeout
	await _shoot("res://tools/deletion_early.png")
	await get_tree().create_timer(0.16).timeout
	await _shoot("res://tools/deletion_mid.png")

	print("DELETION_PREVIEW_SAVED")
	get_tree().quit()


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("SAVED ", path)
