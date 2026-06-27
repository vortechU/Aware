extends Node3D
## Pass E — rigged characters on enemies. Asserts the CharacterApplicator autoload
## grafts an animated Kenney rig onto each enemy WITHOUT touching enemy.tscn /
## enemy_ai.gd, that the primitive Body+Head are hidden while the Gun is kept, that
## the archetype body colour tints the rig, and that the existing death ragdoll
## carries the rig onto the corpse (frozen-pose). Run:
##   godot --headless --path . res://tools/character_test.tscn  -> CHARACTER_OK
##
## The look itself (scale / orientation / tint) is eyeballed via
## tools/character_preview.tscn (NON-headless).

const ENEMY := preload("res://scenes/enemies/enemy.tscn")

var fails: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_pure()
	await _scene()
	if fails.is_empty():
		print("CHARACTER_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("CHARACTER_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


# --- Pure: the anim-graft pipeline ---

func _pure() -> void:
	_check(CharacterApplicator._ok, "applicator pipeline should be ready")
	var lib: AnimationLibrary = CharacterApplicator._anim_lib
	_check(lib != null, "anim library should exist")
	if lib == null:
		return
	_check(lib.has_animation("idle"), "anim lib should carry 'idle'")
	_check(lib.has_animation("run"), "anim lib should carry 'run'")
	if lib.has_animation("idle"):
		_check(lib.get_animation("idle").loop_mode == Animation.LOOP_LINEAR,
				"idle should be set to loop")


# --- Scene: real enemies rigged by the live autoload ---

func _scene() -> void:
	_floor()

	# Plain enemy (no body override) -> untinted rig.
	var plain := _spawn(Vector3(0, 0.1, 0), Color.WHITE, false)
	var rig := plain.get_node_or_null("Visual/Rig")
	_check(rig != null, "a plain enemy should get a Visual/Rig")
	_check(rig is EnemyRig, "the rig should be an EnemyRig")
	if rig != null:
		_check(_find_mesh(rig) != null, "the rig should carry a character mesh")
		var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		_check(ap != null and ap.is_playing(), "the rig should be playing an animation")
		if ap != null:
			_check(ap.current_animation == "idle", "a still enemy should idle, got '%s'" % ap.current_animation)
		_check(is_equal_approx((rig as Node3D).scale.x, CharacterApplicator.RIG_SCALE),
				"the rig should use RIG_SCALE")
		var alb := _rig_albedo(rig)
		_check(alb.is_equal_approx(Color.WHITE), "a plain enemy's rig should be untinted, got %s" % alb)

	# Primitive swap: Body+Head hidden, Gun kept (armed look + gun-drop donor).
	_check(not (plain.get_node("Visual/Body") as MeshInstance3D).visible, "Body should be hidden")
	_check(not (plain.get_node("Visual/Head") as MeshInstance3D).visible, "Head should be hidden")
	_check((plain.get_node("Visual/Gun") as MeshInstance3D).visible, "Gun should stay visible")

	# Weapon-to-hand: the kept gun is driven to the RightHand bone each frame (NOT
	# reparented), so it sits in the hand instead of floating at its scene offset.
	for _i in 3:
		await get_tree().process_frame
	var gun := plain.get_node("Visual/Gun") as Node3D
	var skel := _find_skeleton(rig)
	_check(skel != null, "the rig should expose a Skeleton3D")
	if skel != null:
		var hi := skel.find_bone("RightHand")
		_check(hi >= 0, "the rig should have a RightHand bone")
		if hi >= 0:
			var hand_world: Vector3 = (skel.global_transform * skel.get_bone_global_pose(hi)).origin
			_check(gun.global_position.distance_to(hand_world) < 0.5,
					"the gun should track the hand bone (%.2f m away)" % gun.global_position.distance_to(hand_world))

	# Archetype enemy (orange body override, like _outfit_rusher) -> blended tint.
	var orange := Color(0.85, 0.34, 0.05)
	var rusher := _spawn(Vector3(3, 0.1, 0), orange, true)
	var rrig := rusher.get_node_or_null("Visual/Rig")
	_check(rrig != null, "an archetype enemy should get a rig too")
	if rrig != null:
		var expected := Color.WHITE.lerp(orange, CharacterApplicator.TINT_BLEND)
		var got := _rig_albedo(rrig)
		_check(got.is_equal_approx(expected),
				"archetype rig should tint toward the body colour (want %s got %s)" % [expected, got])

	# Death: the real ragdoll carries the rig onto the corpse and freezes its pose.
	var victim := _spawn(Vector3(-3, 0.1, 0), Color.WHITE, false)
	var vrig := victim.get_node_or_null("Visual/Rig")
	var vap: AnimationPlayer = null
	if vrig != null:
		vap = vrig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	victim.get_node("BodyHitbox").call("take_hit", 99999.0, Vector3(0, 1, 10))
	await get_tree().physics_frame
	var corpse: Node = null
	for c in get_tree().get_nodes_in_group("enemy_corpse"):
		if (c as Node).get_node_or_null("Visual/Rig") != null:
			corpse = c
	_check(corpse != null, "the rig should ride the Visual onto the death corpse")
	if vap != null:
		_check(not vap.is_playing(), "the rig animation should freeze (pause) on death")


# --- helpers ---

func _spawn(pos: Vector3, body_color: Color, override_body: bool) -> Node3D:
	var e: Node3D = ENEMY.instantiate()
	if override_body:
		var bm := StandardMaterial3D.new()
		bm.albedo_color = body_color
		(e.get_node("Visual/Body") as MeshInstance3D).material_override = bm
	add_child(e)              # node_added -> CharacterApplicator rigs it here
	e.global_position = pos
	e.set_physics_process(false)  # no nav region in the harness
	return e


func _floor() -> void:
	var fb := StaticBody3D.new()
	fb.collision_layer = 1
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	fs.shape = box
	fs.position = Vector3(0, -0.5, 0)
	fb.add_child(fs)
	add_child(fb)


func _rig_albedo(rig: Node) -> Color:
	var mi := _find_mesh(rig)
	if mi == null:
		return Color.BLACK
	var m := mi.material_override
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).albedo_color
	return Color.BLACK


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
