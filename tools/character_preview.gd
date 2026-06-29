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
	# Pulled back + widened to fit the whole row of 12 (4 plain + 4 archetypes + 4 corrupted).
	_cam.fov = 58.0
	_cam.position = Vector3(0.0, 1.3, -15.0)
	_cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)

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


## A row of 12: the 4 default plain skins (left, via the deterministic spawn-order
## rotation), the 4 archetypes (middle, each its fixed skin + archetype body colour),
## then the 4 CORRUPTED-layer plain grunts (right, spawned under a forced CAMPAIGN
## Heap context so the applicator pulls the "corrupted" pool -- a mix of normal +
## zombie skins). Prints the skin each one received so the mapping reads from the log.
const STEP := 1.35
func _spawn_enemies() -> void:
	var x := -STEP * 5.5   # centre a 12-wide row
	# Default plain grunts -- spawned first so the rotation runs 0..3 over all four.
	for i in 4:
		_one(Vector3(x, 0.0, 0.0), Color.WHITE, "", "plain")
		x += STEP
	# Archetypes -- meta + archetype body colour, like _outfit_* in RunDirector.
	_one(Vector3(x, 0.0, 0.0), Color(0.85, 0.34, 0.05), "rusher", "rusher");       x += STEP
	_one(Vector3(x, 0.0, 0.0), Color(0.32, 0.46, 0.16), "grenadier", "grenadier"); x += STEP
	_one(Vector3(x, 0.0, 0.0), Color(0.1, 0.5, 0.62), "sniper", "sniper");         x += STEP
	_one(Vector3(x, 0.0, 0.0), Color(0.32, 0.05, 0.09), "elite", "elite");         x += STEP

	# Corrupted layer (Pass 2): drive RunManager into a Heap room so active_layer_
	# profile() carries skin_set "corrupted", spawn 4 grunts, then restore.
	var prev_mode = RunManager.run_mode
	var prev_room = RunManager.current_room
	RunManager.run_mode = RunManager.RunMode.CAMPAIGN
	RunManager.current_room = 1
	for i in 4:
		_one(Vector3(x, 0.0, 0.0), Color.WHITE, "", "corrupt")
		x += STEP
	RunManager.run_mode = prev_mode
	RunManager.current_room = prev_room

	var pole := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, TARGET_HEIGHT, 0.05)
	pole.mesh = bm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(1.0, 0.9, 0.2)
	pole.material_override = pmat
	add_child(pole)
	pole.position = Vector3(-STEP * 5.5, TARGET_HEIGHT * 0.5, -0.6)


## Spawn one enemy. `archetype` "" = a plain grunt (rotation skin); otherwise it's
## stamped with that archetype meta + the given body colour, exactly as RunDirector
## outfits it before add_child, so CharacterApplicator skins + tints it accordingly.
## `label` is just for the CHAR_SKIN log line.
func _one(pos: Vector3, body_color: Color, archetype: String, label: String) -> void:
	var e := ENEMY.instantiate()
	if archetype != "":
		e.set_meta(archetype, true)
		var bodymesh := e.get_node("Visual/Body") as MeshInstance3D
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = body_color
		bodymesh.material_override = bmat
	add_child(e)
	e.global_position = pos
	# Freeze: no AI/gravity in the preview (the EnemyRig still processes its anim).
	e.set_physics_process(false)
	e.set_process(false)

	var rig := e.get_node_or_null("Visual/Rig")
	var skin := _skin_of(rig)
	print("CHAR_SKIN  %-10s -> %s" % [label, skin.resource_path if skin != null else "<none>"])


func _skin_of(rig: Node) -> Texture2D:
	if rig == null:
		return null
	var mi := _find_mesh(rig)
	if mi == null:
		return null
	var m := mi.material_override
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).albedo_texture
	return null


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
