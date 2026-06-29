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
# --- Skin variety (Pass E follow-up) ---------------------------------------
# One model, swappable skin textures (all share the same UV layout, so a skin is
# just a different albedo_texture on the same StandardMaterial3D). Plain grunts
# rotate through the set for crowd variety; each archetype gets a recognizable
# fixed skin (still tinted toward its hue by _archetype_tint, so the orange/cyan/
# olive colour cue survives). criminalMaleA is the historical default + fallback.
const SKIN_CRIMINAL: Texture2D = preload(
	"res://Assets/kenney_animated-characters-protagonists/Skins/criminalMaleA.png")
const SKIN_SKATER_M: Texture2D = preload(
	"res://Assets/kenney_animated-characters-protagonists/Skins/skaterMaleA.png")
const SKIN_SKATER_F: Texture2D = preload(
	"res://Assets/kenney_animated-characters-protagonists/Skins/skaterFemaleA.png")
const SKIN_CYBORG: Texture2D = preload(
	"res://Assets/kenney_animated-characters-protagonists/Skins/cyborgFemaleA.png")

# Survivors pack (Pass 2 -- "corrupted" memories). The survivors `characterMedium.fbx`
# is BYTE-IDENTICAL to the protagonists one (same mesh + skeleton + UVs), so these
# skins drop onto the existing rig with NO new model or anim graft -- a "skin" is
# still just a different albedo_texture. Used in decayed/corrupted layers.
const SKIN_ZOMBIE_A: Texture2D = preload(
	"res://Assets/kenney_animated-characters-survivors/Skins/zombieA.png")
const SKIN_ZOMBIE_C: Texture2D = preload(
	"res://Assets/kenney_animated-characters-survivors/Skins/zombieC.png")
const SKIN_SURVIVOR_M: Texture2D = preload(
	"res://Assets/kenney_animated-characters-survivors/Skins/survivorMaleB.png")
const SKIN_SURVIVOR_F: Texture2D = preload(
	"res://Assets/kenney_animated-characters-survivors/Skins/survivorFemaleA.png")

## Plain enemies rotate through a skin POOL in spawn order (deterministic + stable
## per enemy: the pick is baked into the material once at graft, never re-rolled per
## frame, and squad spawn order is itself deterministic -> runs reproduce). The pool
## is the layer's -- see SKIN_SETS. PLAIN_SKINS is the default (protagonists).
const PLAIN_SKINS := [SKIN_CRIMINAL, SKIN_SKATER_M, SKIN_SKATER_F, SKIN_CYBORG]

## Per-layer plain-grunt skin pools, chosen by the active layer profile's `skin_set`
## key (the same declarative pattern as `kit`/palette). "" / absent = the default
## protagonists (intact memories), so ENDLESS + every un-tagged layer is unchanged.
## A corrupted layer mixes zombies into the rotation so a decaying memory reads as
## half-rotted; deeper layers can opt into the fully-corrupted set. Archetypes are
## NOT affected by this -- they keep their fixed ARCHETYPE_SKINS skin + tint.
const SKIN_SETS := {
	"": PLAIN_SKINS,
	"protagonists": PLAIN_SKINS,
	# Heap-style decay: intact echoes intermixed with corrupted (zombie) ones.
	"corrupted": [SKIN_CRIMINAL, SKIN_ZOMBIE_A, SKIN_SKATER_F, SKIN_ZOMBIE_C],
	# Fully corrupted -- ready for deeper layers (defined + tested; not yet assigned).
	"zombies": [SKIN_ZOMBIE_A, SKIN_ZOMBIE_C, SKIN_SURVIVOR_M, SKIN_SURVIVOR_F],
}

## Archetype -> fixed skin. Keyed by the meta RunDirector stamps on the enemy
## BEFORE add_child (so it's already present when node_added fires), NOT by colour
## -- decoupled + robust. The archetype hue still comes through via _archetype_tint.
const ARCHETYPE_SKINS := {
	"rusher": SKIN_SKATER_M,    # athletic, aggressive
	"grenadier": SKIN_CRIMINAL, # bulky / thuggish
	"sniper": SKIN_SKATER_F,    # lean marksman
	"elite": SKIN_CYBORG,       # most distinctive -> reads as the boss
}
## Checked in priority order (an elite is never also a rusher, but be explicit).
const ARCHETYPE_KEYS := ["elite", "sniper", "grenadier", "rusher"]

# Stand the imported (tiny) model at the capsule height. Derived once empirically
# (tools/character_preview.gd measures the world-space deform-bone span and prints
# the recommended value); baked here so spawning never re-measures.
const RIG_SCALE := 0.62      # model is ~2.69 m at scale 1 (world deform span); -> ~1.8 m
const RIG_YAW_DEG := 180.0   # Kenney faces +Z; the enemy faces -Z, so flip.
const RIG_Y := 0.0           # model origin sits at the feet (capsule feet = y 0)
const HAND_BONE := "RightHand"  # the kept gun is glued here by EnemyRig

# The enemy.tscn Body colour for a plain enemy; anything else is an archetype cue.
const REGULAR_BODY := Color(0.66, 0.18, 0.18)
const TINT_BLEND := 0.6      # how far to pull the skin toward the archetype colour

var _anim_lib: AnimationLibrary
var _ok := false
var _plain_count := 0   # rotates PLAIN_SKINS deterministically per spawned grunt


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

	_skin_model(model, tint, _pick_skin(enemy))

	visual.add_child(rig)

	# Hand the rig the kept Gun + the hand bone so EnemyRig can seat the gun in the
	# hand each frame (without reparenting it -- the gun stays at Visual/Gun so the
	# death ragdoll's _drop_gun still detaches it).
	var gun := visual.get_node_or_null("Gun") as Node3D
	var skel := _find_skeleton(model)
	var hand_idx := -1
	if skel != null:
		hand_idx = skel.find_bone(HAND_BONE)
	rig.setup(ap, enemy as Node3D, gun, skel, hand_idx)

	# Swap the primitives for the rig: hide Body + Head (replaced by the character),
	# keep the Gun for the armed silhouette + its gun-drop ragdoll piece.
	if body != null:
		body.visible = false
	if head != null:
		head.visible = false


## A skinned StandardMaterial3D (the chosen Kenney skin texture, multiplied toward
## the archetype colour). Plain enemies keep the untinted skin; archetypes/elites
## read as their hue without losing the texture detail.
func _skin_model(model: Node, tint: Color, skin: Texture2D) -> void:
	var mi := _find_mesh(model)
	if mi == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = skin if skin != null else SKIN_CRIMINAL
	m.albedo_color = tint
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = m


## Pick this enemy's skin. Archetypes (tagged by RunDirector's meta) get a fixed,
## recognizable skin regardless of layer; plain grunts rotate the CURRENT LAYER'S
## pool by spawn order, so a squad reads as several different people AND a corrupted
## layer mixes in zombies -- all deterministically.
func _pick_skin(enemy: Node) -> Texture2D:
	var key := _archetype_key(enemy)
	if key != "plain":
		return ARCHETYPE_SKINS[key]
	var pool := _active_plain_pool()
	var skin: Texture2D = pool[_plain_count % pool.size()]
	_plain_count += 1
	return skin


## The plain-grunt pool for the room being built, from the active layer's `skin_set`.
## ENDLESS / no campaign -> {} profile -> the default protagonists, so bare harnesses
## are unaffected. Split from _plain_pool_for so the mapping is unit-testable.
func _active_plain_pool() -> Array:
	return _plain_pool_for(RunManager.active_layer_profile())


func _plain_pool_for(profile: Dictionary) -> Array:
	var set_name: String = profile.get("skin_set", "")
	return SKIN_SETS.get(set_name, PLAIN_SKINS)


## The archetype this enemy was outfitted as, read from the meta RunDirector stamps
## before add_child (so it's available at graft time). "plain" if none -- a pure,
## side-effect-free classification, decoupled from enemy_ai.gd / run_director.gd.
func _archetype_key(enemy: Node) -> String:
	for key in ARCHETYPE_KEYS:
		if enemy.has_meta(key):
			return key
	return "plain"


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


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
