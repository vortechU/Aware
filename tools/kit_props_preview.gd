extends Node
## Throwaway visual harness: renders candidate cover/obstacle props in a row at ~1.5 m so
## the best "crate" / "tech block" can be picked for the obstacle skin. NON-headless.
##   Godot.exe --path <proj> res://tools/kit_props_preview.tscn
## Saves res://tools/kit_props_gallery.png.

const BASE := "res://Assets/kenney_space-station-kit/Models/GLB format/"
const NAMES := [
	"container", "container-flat", "container-tall", "container-wide",
	"structure", "structure-panel", "crate",
]


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -40.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)

	var x := -6.0
	for n in NAMES:
		var packed := load(BASE + String(n) + ".glb") as PackedScene
		if packed == null:
			x += 2.0
			continue
		var inst := packed.instantiate() as Node3D
		add_child(inst)
		# Scale each to ~1.5 m on its largest axis so they're comparable.
		var ab := _aabb(inst)
		var biggest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		var s := 1.5 / maxf(biggest, 0.01)
		inst.scale = Vector3(s, s, s)
		inst.position = Vector3(x, 0.0, 0.0)
		x += 2.2

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.2, 7.5)
	cam.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()
	for _i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://tools/kit_props_gallery.png"))
	print("KIT_PROPS_SAVED")
	get_tree().quit()


func _aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(root):
		var ab: AABB = (mi as MeshInstance3D).global_transform * (mi.mesh as Mesh).get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out


func _meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node)
	for c in node.get_children():
		found.append_array(_meshes(c))
	return found
