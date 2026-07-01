extends Node3D
## Throwaway visual harness (NOT shipped): renders the first-person weapon
## viewmodels through the real player.tscn so the toon pass + orientation on each
## gun can be eyeballed. The player is process-disabled so it neither falls nor
## reads input; WeaponManager._ready still builds + positions the rig, ToonApplicator
## cel-shades it and WeaponClip flips it to render-on-top -- exactly the in-game
## pipeline. Per gun it saves TWO PNGs:
##   _weapon_preview_<name>.png -- the true FIRST-PERSON view (player's own camera),
##     against a bright magenta background so any backface-culling hole ("material
##     looks transparent") is obvious.
##   _weapon_side_<name>.png -- a clean SIDE view in the WEAPON MANAGER'S OWN local
##     frame (camera on +X looking -X, up = +Y). A first-person corner view can't
##     show roll/pitch; here a correctly-built gun points its muzzle toward -Z
##     (screen RIGHT) with its grip hanging toward -Y (screen DOWN). This is the view
##     that caught the shotgun being rolled 90deg about its barrel.
## Must run NON-headless (real D3D12). Quits when done.

const PLAYER := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.45, 0.9)  # bright: culling holes scream
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.58)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var player := PLAYER.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED  # no fall, no input, no rig anim
	add_child(player)
	var wm := player.get_node("Head/Bob/Recoil/Camera/WeaponManager") as Node3D
	var fp_cam := player.get_node("Head/Bob/Recoil/Camera") as Camera3D

	# A free camera for the framed side view (the player camera stays put for FP).
	var side_cam := Camera3D.new()
	add_child(side_cam)

	for i in 16:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var names := ["pistol", "rifle", "shotgun"]
	for i in 3:
		wm.call("_equip", i)
		for _f in 8:
			await get_tree().process_frame

		# 1) First-person: the real view the player sees.
		fp_cam.make_current()
		await _save(fp_cam, "_weapon_preview_%s.png" % names[i], false, wm, i)

		# 2) Clean side profile in the manager's own frame.
		side_cam.make_current()
		await _save(side_cam, "_weapon_side_%s.png" % names[i], true, wm, i)

		fp_cam.make_current()

	get_tree().quit()


## When `frame` is true, aim `cam` at the equipped gun from its +X side (manager
## frame) before shooting; otherwise the caller already positioned the camera.
func _save(cam: Camera3D, fname: String, frame: bool, wm: Node3D, i: int) -> void:
	if frame:
		var model_root: Node3D = wm.get_child(i)
		var aabb := _world_aabb(model_root)
		var c := aabb.get_center()
		var r: float = maxf(aabb.size.length() * 0.5, 0.05)
		var b := wm.global_transform.basis
		cam.global_position = c + b.x * r * 3.0
		cam.look_at(c, b.y)
	for _f in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/" + fname)
	img.save_png(path)
	print("WEAPON_PREVIEW_SAVED ", path)


func _world_aabb(root: Node) -> AABB:
	var acc := AABB()
	var first := true
	for mi in _all_meshes(root):
		var m := mi as MeshInstance3D
		var box: AABB = m.global_transform * (m.get_aabb())
		if first:
			acc = box
			first = false
		else:
			acc = acc.merge(box)
	return acc


func _all_meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_meshes(c))
	return out
