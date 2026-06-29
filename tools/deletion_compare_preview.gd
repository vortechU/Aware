extends Node3D
## Throwaway tuning harness (NOT shipped): kills three enemies side by side and
## overrides each death-dissolve material's `jitter` to a different level, so the
## spiky-vs-clean look can be compared in ONE frame. Must run NON-headless:
##   Godot.exe --path <proj> res://tools/deletion_compare_preview.tscn
## Saves res://tools/deletion_compare.png. Left->right = jitter 0.0 / 0.012 / 0.03
## (clean fade / new default / old spiky).

const ENEMY: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const JITTERS := [0.0, 0.012, 0.03]   # left -> right
const SPACING := 3.0                  # > DeletionVFX.CAPTURE_RADIUS so kills don't cross-capture

var _cam: Camera3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.2
	we.environment = env
	add_child(we)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 1, 40)
	fs.shape = fbox
	fs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fs)
	var fmesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fmesh.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.11, 0.12, 0.14)
	fmesh.material_override = gmat
	floor_body.add_child(fmesh)
	add_child(floor_body)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_cam.position = Vector3(0.0, 1.4, -7.6)
	_cam.look_at(Vector3(0, 0.85, 0), Vector3.UP)

	var enemies: Array = []
	for i in 3:
		var e: Node3D = ENEMY.instantiate()
		add_child(e)
		e.global_position = Vector3((i - 1) * SPACING, 0.1, 0)
		e.set_physics_process(false)
		enemies.append(e)
	for _i in 8:
		await get_tree().process_frame

	# Kill all three the same frame, diffing the corpse group per kill so each one's
	# fresh pieces get that column's jitter override (DeletionVFX has already swapped
	# the dissolve material synchronously by the time take_hit returns).
	for i in 3:
		var before := {}
		for c in get_tree().get_nodes_in_group("enemy_corpse"):
			before[c.get_instance_id()] = true
		(enemies[i] as Node).get_node("BodyHitbox").call("take_hit", 99999.0, Vector3(0, 1, 10))
		for c in get_tree().get_nodes_in_group("enemy_corpse"):
			if not before.has(c.get_instance_id()):
				_set_jitter(c, JITTERS[i])

	# Capture mid-dissolve so the spiky/clean difference is obvious.
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/deletion_compare.png"))
	print("DELETION_COMPARE_SAVED  (L->R jitter ", JITTERS, ")")
	get_tree().quit()


func _set_jitter(n: Node, value: float) -> void:
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader == DeletionVFX.DISSOLVE_SHADER:
			(m as ShaderMaterial).set_shader_parameter("jitter", value)
	for c in n.get_children():
		_set_jitter(c, value)
