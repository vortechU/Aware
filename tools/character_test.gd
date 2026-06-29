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

	# Skin variety registry (Pass 1 of the skin-variety follow-up).
	var plain: Array = CharacterApplicator.PLAIN_SKINS
	_check(plain.size() >= 3, "plain rotation should offer >= 3 skins, got %d" % plain.size())
	_check(plain[0] != null and plain[1] != null and plain[0] != plain[1],
			"consecutive plain skins should differ (deterministic rotation)")
	# Distinct textures across the whole plain set (no accidental duplicate entries).
	var seen := {}
	for s in plain:
		seen[s] = true
	_check(seen.size() == plain.size(), "plain skins should all be distinct")
	# Each archetype maps to a real, fixed skin.
	for key in CharacterApplicator.ARCHETYPE_KEYS:
		_check(CharacterApplicator.ARCHETYPE_SKINS.get(key) != null,
				"archetype '%s' should map to a skin" % key)

	# Per-layer skin sets (Pass 2 -- corruption). No profile / ENDLESS -> protagonists;
	# a corrupted layer mixes in a survivors-pack zombie skin.
	var def_pool: Array = CharacterApplicator._plain_pool_for({})
	_check(def_pool == CharacterApplicator.PLAIN_SKINS, "empty profile should map to the default plain pool")
	var corrupt_pool: Array = CharacterApplicator._plain_pool_for({"skin_set": "corrupted"})
	_check(corrupt_pool != CharacterApplicator.PLAIN_SKINS, "a corrupted layer should swap the plain pool")
	_check(CharacterApplicator.SKIN_ZOMBIE_A in corrupt_pool or CharacterApplicator.SKIN_ZOMBIE_C in corrupt_pool,
			"the corrupted pool should include a zombie skin")
	_check(CharacterApplicator._plain_pool_for({"skin_set": "no_such_set"}) == CharacterApplicator.PLAIN_SKINS,
			"an unknown skin_set should fall back to the default pool")


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

		# Cel-shaded: the rig wears the toon ShaderMaterial (banding + skin texture)
		# with the scale-compensated ink outline chained as next_pass.
		var rmat := _rig_material(rig)
		_check(rmat is ShaderMaterial, "the rig should wear a toon ShaderMaterial")
		if rmat is ShaderMaterial:
			var sm := rmat as ShaderMaterial
			_check(sm.shader == ToonApplicator.TOON_SHADER, "the rig material should use the toon shader")
			_check(sm.get_shader_parameter("albedo_texture") != null, "the toon rig should carry its skin texture")
			var op := sm.next_pass as ShaderMaterial
			_check(op != null and op.shader == ToonApplicator.OUTLINE_SHADER_SCALED,
					"the rig should chain the scale-compensated outline")

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

	# --- Skin variety (Pass 1) ---
	# Two plain grunts spawned back-to-back rotate to different skins (crowd variety,
	# deterministic by spawn order -- the pick is baked once, not re-rolled per frame).
	var g1 := _spawn(Vector3(0, 0.1, 6), Color.WHITE, false)
	var g2 := _spawn(Vector3(3, 0.1, 6), Color.WHITE, false)
	var s1 := _rig_skin(g1.get_node_or_null("Visual/Rig"))
	var s2 := _rig_skin(g2.get_node_or_null("Visual/Rig"))
	_check(s1 != null and s2 != null, "plain grunts should carry a skin texture")
	_check(s1 != s2, "two plain grunts should get different skins (variety)")
	_check(s1 in CharacterApplicator.PLAIN_SKINS, "a grunt's skin should come from the plain set")

	# An enemy tagged with an archetype meta (as RunDirector stamps it BEFORE
	# add_child) gets that archetype's fixed skin, not a plain-rotation one.
	var sniper := _spawn_meta(Vector3(-3, 0.1, 6), "sniper")
	var ss := _rig_skin(sniper.get_node_or_null("Visual/Rig"))
	_check(ss == CharacterApplicator.ARCHETYPE_SKINS["sniper"],
			"a meta-tagged sniper should wear the sniper skin")

	# --- Corruption (Pass 2): a corrupted layer mixes zombies into plain grunts ---
	# Drive the live RunManager into a CAMPAIGN Heap room (skin_set "corrupted") so
	# the applicator reads the corrupted pool through active_layer_profile(). Restore
	# it after so no global state leaks to later harnesses sharing the process.
	var prev_mode = RunManager.run_mode
	var prev_room := RunManager.current_room
	RunManager.run_mode = RunManager.RunMode.CAMPAIGN
	RunManager.current_room = 1   # Heap, sector 1
	_check(RunManager.active_layer_profile().get("skin_set", "") == "corrupted",
			"the Heap profile should carry skin_set 'corrupted'")

	# Spawn a full pool's worth of plain grunts; their skins should include a zombie.
	var zombie_seen := false
	var all_in_pool := true
	for i in 4:
		var g := _spawn(Vector3(-6 + i * 2, 0.1, 9), Color.WHITE, false)
		var sk := _rig_skin(g.get_node_or_null("Visual/Rig"))
		if sk == CharacterApplicator.SKIN_ZOMBIE_A or sk == CharacterApplicator.SKIN_ZOMBIE_C:
			zombie_seen = true
		if not (sk in CharacterApplicator.SKIN_SETS["corrupted"]):
			all_in_pool = false
	_check(zombie_seen, "a corrupted layer's grunts should include a zombie skin")
	_check(all_in_pool, "every corrupted grunt's skin should come from the corrupted pool")

	# Special types are NOT corrupted: a rusher keeps its fixed protagonist skin.
	var crusher := _spawn_meta(Vector3(6, 0.1, 9), "rusher")
	var cs := _rig_skin(crusher.get_node_or_null("Visual/Rig"))
	_check(cs == CharacterApplicator.ARCHETYPE_SKINS["rusher"],
			"an archetype keeps its fixed skin even in a corrupted layer")

	RunManager.run_mode = prev_mode
	RunManager.current_room = prev_room


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


## Spawn an enemy tagged with an archetype meta (the way RunDirector's _outfit_*
## stamps it before add_child), so CharacterApplicator classifies it by archetype.
func _spawn_meta(pos: Vector3, archetype: String) -> Node3D:
	var e: Node3D = ENEMY.instantiate()
	e.set_meta(archetype, true)
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	return e


func _rig_skin(rig: Node) -> Texture2D:
	if rig == null:
		return null
	var mi := _find_mesh(rig)
	if mi == null:
		return null
	var m := mi.material_override
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).albedo_texture
	if m is ShaderMaterial:
		return (m as ShaderMaterial).get_shader_parameter("albedo_texture") as Texture2D
	return null


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
	if m is ShaderMaterial:
		var a: Variant = (m as ShaderMaterial).get_shader_parameter("albedo")
		return a if a is Color else Color.BLACK
	return Color.BLACK


## The rig mesh's material, for cel-shading assertions.
func _rig_material(rig: Node) -> Material:
	var mi := _find_mesh(rig)
	return mi.material_override if mi != null else null


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
