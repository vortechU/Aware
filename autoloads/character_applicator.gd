extends Node
## Replaces each enemy's primitive capsule/sphere `Visual` with a rigged, animated
## Kenney character -- WITHOUT touching enemy.tscn, enemy_ai.gd or run_director.gd.
## A sibling observer of ToonApplicator: it listens to the tree's node_added and,
## when an EnemyAI enters, instances a character rig under its `Visual` node, hides
## the primitive Body + Head, tints the rig by the archetype body colour, and lets
## EnemyRig drive idle/run from the enemy's velocity.
##
## BUILD-ALONGSIDE + VISUAL-ONLY: the rig is decorative (no collision). The enemy's
## capsule collider, hitboxes, navmesh and AI are untouched -- exactly the kit-skin
## invariant, now for characters. The primitive `Gun` box is KEPT visible so the
## enemy still reads as armed AND the existing gun-drop ragdoll still fires; the
## hidden primitive Head is left in place so the headshot head-pop still has its
## donor (an invisible no-op). On death the ragdoll reparents the whole Visual
## (rig included) onto a corpse and tumbles the frozen-pose rig.
##
## ORDER NOTE: the archetype/elite outfit (RunDirector) sets the Body material
## BEFORE add_child, so the colour cue is present when node_added fires. The tint
## read is robust to whether ToonApplicator has already swapped the Body material
## (StandardMaterial3D vs toon ShaderMaterial) -- see `_albedo_of`.

const BASE_MODEL: PackedScene = preload(
	"res://Assets/kenney_animated-characters-protagonists/Model/characterMedium.fbx")
const ANIM_IDLE := "res://Assets/kenney_animated-characters-protagonists/Animations/idle.fbx"
const ANIM_RUN := "res://Assets/kenney_animated-characters-protagonists/Animations/run.fbx"
const ANIM_JUMP := "res://Assets/kenney_animated-characters-protagonists/Animations/jump.fbx"
const SKIN: Texture2D = preload(
	"res://Assets/kenney_animated-characters-protagonists/Skins/criminalMaleA.png")

# Stand the imported (tiny) model at the capsule height. Derived once empirically
# (tools/character_preview.gd measures the world-space deform-bone span and prints
# the recommended value); baked here so spawning never re-measures.
const RIG_SCALE := 0.62      # model is ~2.69 m at scale 1 (world deform span); -> ~1.8 m
const RIG_YAW_DEG := 180.0   # Kenney faces +Z; the enemy faces -Z, so flip.
const RIG_Y := 0.0           # model origin sits at the feet (capsule feet = y 0)

# The enemy.tscn Body colour for a plain enemy; anything else is an archetype cue.
const REGULAR_BODY := Color(0.66, 0.18, 0.18)
const TINT_BLEND := 0.6      # how far to pull the skin toward the archetype colour

var _anim_lib: AnimationLibrary
var _ok := false


func _ready() -> void:
	_anim_lib = _build_anim_lib()
	_ok = _anim_lib != null and BASE_MODEL != null
	if _ok:
		get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is EnemyAI:
		_apply(node)


func _apply(enemy: Node) -> void:
	var visual := enemy.get_node_or_null("Visual") as Node3D
	if visual == null or visual.has_node("Rig"):
		return
	var body := visual.get_node_or_null("Body") as MeshInstance3D
	var head := visual.get_node_or_null("Head") as MeshInstance3D
	var tint := _archetype_tint(body)

	# Build the rig: an EnemyRig wrapper holding the model + its own AnimationPlayer.
	var rig := EnemyRig.new()
	rig.name = "Rig"
	rig.scale = Vector3.ONE * RIG_SCALE
	rig.rotation.y = deg_to_rad(RIG_YAW_DEG)
	rig.position = Vector3(0.0, RIG_Y, 0.0)

	var model := BASE_MODEL.instantiate()
	model.name = "Model"
	rig.add_child(model)

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	ap.root_node = ap.get_path_to(model)  # tracks are "Root/Skeleton3D:Bone"
	ap.add_animation_library("", _anim_lib)

	_skin_model(model, tint)

	visual.add_child(rig)
	rig.setup(ap, enemy as Node3D)

	# Swap the primitives for the rig: hide Body + Head (replaced by the character),
	# keep the Gun for the armed silhouette + its gun-drop ragdoll piece.
	if body != null:
		body.visible = false
	if head != null:
		head.visible = false


## A skinned StandardMaterial3D (the Kenney skin texture, multiplied toward the
## archetype colour). Plain enemies keep the untinted skin; archetypes/elites read
## as their hue without losing the texture detail.
func _skin_model(model: Node, tint: Color) -> void:
	var mi := _find_mesh(model)
	if mi == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = SKIN
	m.albedo_color = tint
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = m


## Read the archetype colour cue off the Body mesh and, if it isn't the plain
## enemy crimson, return a tint blended toward it. Order-independent: handles the
## raw scene material, the archetype StandardMaterial3D override, OR the toon
## ShaderMaterial that ToonApplicator may have already installed.
func _archetype_tint(body: MeshInstance3D) -> Color:
	if body == null:
		return Color.WHITE
	var c := _albedo_of(body)
	if c.is_equal_approx(REGULAR_BODY):
		return Color.WHITE
	return Color.WHITE.lerp(c, TINT_BLEND)


func _albedo_of(mi: MeshInstance3D) -> Color:
	var m: Material = mi.material_override
	if m == null:
		m = mi.get_active_material(0)
	if m is ShaderMaterial:
		var a: Variant = (m as ShaderMaterial).get_shader_parameter("albedo")
		return a if a is Color else Color.WHITE
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).albedo_color
	return Color.WHITE


# --- Animation library: graft the separate idle/run/jump FBX clips onto one lib ---

func _build_anim_lib() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	if not _grab(lib, ANIM_IDLE, "Root|Idle", "idle", true):
		return null  # no idle == pipeline broken; bail so enemies stay primitive
	_grab(lib, ANIM_RUN, "Root|Run", "run", true)
	_grab(lib, ANIM_JUMP, "Root|Jump", "jump", false)
	return lib


func _grab(lib: AnimationLibrary, path: String, src: String, dst: String, loop: bool) -> bool:
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var inst := ps.instantiate()
	var ap := _find_anim_player(inst)
	var ok := false
	if ap != null and ap.has_animation(src):
		var anim := (ap.get_animation(src) as Animation).duplicate(true) as Animation
		if loop:
			anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(dst, anim)
		ok = true
	inst.free()
	return ok


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
