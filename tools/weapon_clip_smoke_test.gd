extends Node
## Headless functional test for the WeaponClip autoload (the "gun pokes through
## walls" fix). Run: godot --headless --path . res://tools/weapon_clip_smoke_test.tscn
##
## WeaponClip now makes the viewmodel render ON TOP of the world (depth test
## disabled) instead of pushing it back, so there is no per-frame offset to
## measure. Instead we instance the real player.tscn and assert the material setup:
##   1. The current weapon's body + barrel meshes draw without a depth test --
##      either swapped to toon_viewmodel.gdshader (the cel path, set by
##      ToonApplicator first) or no_depth_test on a StandardMaterial3D fallback.
##   2. The cel outline (next_pass) is preserved on the cel path, so the gun keeps
##      its silhouette.
##   3. The muzzle flash material has no_depth_test set, so the flash clears walls too.
##
## Shaders don't compile under --headless, but the assignment of a Shader / flag is
## plain resource data, so this verifies the real behaviour headless.

const PLAYER := preload("res://scenes/player/player.tscn")
const VIEWMODEL_SHADER := preload("res://shaders/toon_viewmodel.gdshader")

var fails: Array[String] = []


func _ready() -> void:
	await _run()
	if fails.is_empty():
		print("WEAPON_CLIP_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("WEAPON_CLIP_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


## True when a mesh is set up to draw over the world (cel viewmodel shader or a
## no_depth_test material).
func _renders_on_top(mesh: MeshInstance3D) -> bool:
	var mat: Material = mesh.material_override
	if mat is ShaderMaterial:
		return (mat as ShaderMaterial).shader == VIEWMODEL_SHADER
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).no_depth_test
	return false


func _run() -> void:
	var player := PLAYER.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED  # no fall / input / rig anim
	add_child(player)
	player.global_position = Vector3.ZERO
	var wm := player.get_node("Head/Bob/Recoil/Camera/WeaponManager") as Node3D

	# Let ToonApplicator cel-shade the weapon and WeaponClip adopt it (both deferred).
	await _settle(8)

	var current := wm.get("current_index") as int
	var model := wm.get_child(current) as Node3D
	_check(model != null, "no current weapon model root")
	if model == null:
		return

	var body_meshes := 0
	var flash_meshes := 0
	for child in model.get_children():
		if child.name == "MuzzleFlash":
			for sub in child.get_children():
				if sub is MeshInstance3D:
					flash_meshes += 1
					var fm := (sub as MeshInstance3D).material_override
					_check(fm is StandardMaterial3D and (fm as StandardMaterial3D).no_depth_test,
							"muzzle flash does not render on top")
		else:
			body_meshes += _check_mesh_tree(child)

	# Real weapon meshes (Kenney/Sketchfab GLBs) nest an arbitrary number of
	# MeshInstance3D nodes under "Model", unlike the old flat box+barrel -- so
	# this only asserts "at least one", not a fixed count.
	_check(body_meshes >= 1, "expected at least one body mesh, found %d" % body_meshes)
	_check(flash_meshes >= 1, "expected a muzzle flash mesh, found %d" % flash_meshes)


## Recursively checks every MeshInstance3D under `node` (the real weapon meshes
## nest arbitrarily deep), returning how many were found.
func _check_mesh_tree(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
		var m := node as MeshInstance3D
		_check(_renders_on_top(m), "body mesh '%s' does not render on top" % m.name)
		# NOTE: the inverted-hull outline (next_pass) is deliberately DROPPED for
		# TEXTURED weapon meshes -- ToonApplicator skips it because the flat-primitive
		# hull floods a detailed ripped GLB with ink (see _make_toon_material). So the
		# outline is only asserted for UNtextured (flat, procedural-primitive) meshes.
		if m.material_override is ShaderMaterial:
			var sm := m.material_override as ShaderMaterial
			var tex: Variant = sm.get_shader_parameter("albedo_texture")
			if tex == null:
				_check(sm.next_pass != null, "flat cel viewmodel lost its outline next_pass")
	for child in node.get_children():
		count += _check_mesh_tree(child)
	return count
