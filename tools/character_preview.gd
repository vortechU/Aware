extends Node
## Throwaway visual harness (NOT shipped game code): renders the Pass E rigged
## enemy so the character scale / orientation / archetype tint can be eyeballed,
## and PRINTS the recommended RIG_SCALE (measured from the model's real world-space
## deform-bone span, which headless bone-rest math can't give -- the rest pose is
## reoriented by node transforms). Must run NON-headless (real D3D12):
##   Godot.exe --path <proj> res://tools/character_preview.tscn
## Saves res://tools/character_preview.png and prints CHAR_SCALE=<n>.

const ENEMY: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const BASE_MODEL: PackedScene = preload(
	"res://Assets/kenney_animated-characters-protagonists/Model/characterMedium.fbx")
const TARGET_HEIGHT := 1.7  # desired feet->head world height in metres

var _cam: Camera3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)

	# Ground grid.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.12, 0.13, 0.15)
	ground.material_override = gmat
	add_child(ground)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()

	_measure_scale()
	_spawn_enemies()

	# Camera at -Z, looking toward +Z: the enemies face -Z, so this frames their FRONTS.
	_cam.position = Vector3(0.0, 1.1, -4.6)
	_cam.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)

	for _i in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/character_preview.png"))
	print("CHAR_PREVIEW_SAVED")
	get_tree().quit()


## Add the raw model at scale 1, read the world-space deform-bone Y span, print the
## scale that would stand it at TARGET_HEIGHT.
func _measure_scale() -> void:
	var probe := BASE_MODEL.instantiate()
	add_child(probe)
	var sk := _find_skeleton(probe)
	if sk == null:
		print("CHAR_SCALE=?? (no skeleton)")
		probe.free()
		return
	var ymin := INF
	var ymax := -INF
	var xt := sk.global_transform
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i).to_lower()
		if "ctrl" in bn or "roll" in bn or "_end" in bn or "ik" in bn or "pole" in bn:
			continue
		var w: Vector3 = xt * sk.get_bone_global_rest(i).origin
		ymin = minf(ymin, w.y)
		ymax = maxf(ymax, w.y)
	var span := ymax - ymin
	var rec := TARGET_HEIGHT / span if span > 0.0001 else 0.0
	print("CHAR_SPAN=%.5f world-units  CHAR_SCALE=%.2f (for %.2f m)" % [span, rec, TARGET_HEIGHT])
	probe.free()


## Three enemies: a plain one + two with archetype-style body overrides, so the
## tint mapping reads. Plus a TARGET_HEIGHT reference pole behind the plain one.
func _spawn_enemies() -> void:
	_one(Vector3(0.0, 0.0, 0.0), Color.WHITE, false)                 # plain (no override)
	_one(Vector3(-1.6, 0.0, 0.0), Color(0.85, 0.34, 0.05), true)     # rusher orange
	_one(Vector3(1.6, 0.0, 0.0), Color(0.1, 0.5, 0.62), true)        # sniper cyan

	var pole := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, TARGET_HEIGHT, 0.05)
	pole.mesh = bm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(1.0, 0.9, 0.2)
	pole.material_override = pmat
	add_child(pole)
	pole.position = Vector3(0.0, TARGET_HEIGHT * 0.5, -0.6)


func _one(pos: Vector3, body_color: Color, override_body: bool) -> void:
	var e := ENEMY.instantiate()
	# Apply an archetype-style override BEFORE add_child, like RunDirector does, so
	# the CharacterApplicator sees the colour cue when node_added fires.
	if override_body:
		var bodymesh := e.get_node("Visual/Body") as MeshInstance3D
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = body_color
		bodymesh.material_override = bmat
	add_child(e)
	e.global_position = pos
	# Freeze: no AI/gravity in the preview (the EnemyRig still processes its anim).
	e.set_physics_process(false)
	e.set_process(false)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
