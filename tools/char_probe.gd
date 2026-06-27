extends Node
## Non-asserting diagnostic: dumps the imported Kenney character FBXs — node tree,
## skeleton, mesh AABBs, and the animation clips in each anim file — so Pass E can
## be built against the REAL structure (FBX import names/scale are unknowable until
## the engine has imported them). Writes tools/_char_probe.txt. Run NON-headless is
## not required; the .scn is plain resource data.

const BASE_PROT := "res://Assets/kenney_animated-characters-protagonists/Model/characterMedium.fbx"
const BASE_SURV := "res://Assets/kenney_animated-characters-survivors/Model/characterMedium.fbx"
const ANIMS := [
	"res://Assets/kenney_animated-characters-protagonists/Animations/idle.fbx",
	"res://Assets/kenney_animated-characters-protagonists/Animations/run.fbx",
	"res://Assets/kenney_animated-characters-protagonists/Animations/jump.fbx",
]
const SKINS := "res://Assets/kenney_animated-characters-protagonists/Skins/"

var _lines: PackedStringArray = []


func _ready() -> void:
	_log("=== CHARACTER PROBE ===")
	_dump_scene("PROTAGONIST base", BASE_PROT)
	_measure_in_tree(BASE_PROT)
	for a in ANIMS:
		_dump_anim(String(a))
	_dump_anim_tree(ANIMS[0])
	_log("")
	_log("Skins dir listing:")
	var d := DirAccess.open(SKINS)
	if d != null:
		for f in d.get_files():
			_log("  " + f)
	var out := "res://tools/_char_probe.txt"
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string("\n".join(_lines))
	fa.close()
	print("\n".join(_lines))
	print("CHAR_PROBE_DONE")
	get_tree().quit(0)


func _dump_scene(label: String, path: String) -> void:
	_log("")
	_log("--- %s : %s ---" % [label, path])
	var ps := load(path) as PackedScene
	if ps == null:
		_log("  FAILED TO LOAD")
		return
	var inst := ps.instantiate()
	_walk(inst, 0)
	# Total AABB of all mesh instances (height estimate).
	var aabb := _subtree_aabb(inst)
	_log("  TOTAL AABB pos=%s size=%s  (height=%.3f)" % [aabb.position, aabb.size, aabb.size.y])
	inst.free()


func _walk(n: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var ab := mi.get_aabb()
		extra = " [MESH aabb_size=%s surfaces=%d skin=%s]" % [
			ab.size, mi.mesh.get_surface_count() if mi.mesh else 0,
			"yes" if mi.skin != null else "no"]
	elif n is Skeleton3D:
		var sk := n as Skeleton3D
		extra = " [SKELETON bones=%d]" % sk.get_bone_count()
	elif n is AnimationPlayer:
		var ap := n as AnimationPlayer
		extra = " [ANIMPLAYER libs=%s anims=%s]" % [ap.get_animation_library_list(), ap.get_animation_list()]
	_log("  %s%s (%s)%s" % [pad, n.name, n.get_class(), extra])
	for c in n.get_children():
		_walk(c, depth + 1)


func _dump_anim(path: String) -> void:
	_log("")
	_log("--- ANIM FILE : %s ---" % path)
	var ps := load(path) as PackedScene
	if ps == null:
		_log("  FAILED TO LOAD")
		return
	var inst := ps.instantiate()
	var ap := _find_anim_player(inst)
	if ap == null:
		_log("  no AnimationPlayer")
	else:
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for a in lib.get_animation_list():
				var anim := lib.get_animation(a)
				_log("  lib='%s' anim='%s' len=%.3f tracks=%d loop=%s" % [
					lib_name, a, anim.length, anim.get_track_count(), anim.loop_mode])
	inst.free()


func _measure_in_tree(path: String) -> void:
	_log("")
	_log("--- IN-TREE MEASURE : %s ---" % path)
	var ps := load(path) as PackedScene
	var inst := ps.instantiate()
	add_child(inst)
	var sk := _find_skeleton(inst)
	if sk == null:
		_log("  no skeleton")
		inst.free()
		return
	var ymin := INF
	var ymax := -INF
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		var low := bn.to_lower()
		# Skip IK/control/helper bones; measure the deform chain only.
		if "ctrl" in low or "roll" in low or "_end" in low or "ik" in low or "pole" in low:
			continue
		var o := sk.get_bone_global_rest(i).origin
		ymin = minf(ymin, o.y)
		ymax = maxf(ymax, o.y)
	_log("  DEFORM bone Y span: %.4f .. %.4f  (height=%.4f units)" % [ymin, ymax, ymax - ymin])
	# Named landmarks.
	for nm in ["Hips", "Head", "Head_end", "RightHand", "RightFoot"]:
		var bi := sk.find_bone(nm)
		if bi >= 0:
			_log("    %s.y = %.4f" % [nm, sk.get_bone_global_rest(bi).origin.y])
	# Sample some bone names that matter for weapon attach.
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if "hand" in bn.to_lower() or "head" in bn.to_lower() or "spine" in bn.to_lower():
			_log("    bone[%d]='%s'" % [i, bn])
	inst.free()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


func _dump_anim_tree(path) -> void:
	_log("")
	_log("--- ANIM FILE TREE : %s ---" % String(path))
	var ps := load(String(path)) as PackedScene
	var inst := ps.instantiate()
	_walk(inst, 0)
	var ap := _find_anim_player(inst)
	if ap != null:
		_log("  AnimationPlayer.root_node = %s" % str(ap.root_node))
		var anim := ap.get_animation("Root|Idle")
		if anim == null:
			# any non-pose anim
			for a in ap.get_animation_list():
				if not "Pose" in a:
					anim = ap.get_animation(a)
					break
		if anim != null:
			var n := mini(8, anim.get_track_count())
			for i in n:
				_log("    track[%d] path='%s' type=%d" % [i, anim.track_get_path(i), anim.track_get_type(i)])
	inst.free()


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _subtree_aabb(root: Node) -> AABB:
	var acc := AABB()
	var first := true
	for mi in _all_meshes(root):
		# Approx: ignore deep transforms for a quick height read.
		var local: AABB = mi.get_aabb()
		var box := AABB(local.position, local.size)
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


func _log(s: String) -> void:
	_lines.append(s)
