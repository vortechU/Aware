extends Node
## Cel-shades enemies without touching enemy.tscn, enemy_ai.gd or run_director.gd.
## A sibling observer in the SettingsManager / AudioManager mould: it listens to
## the tree's node_added and, when an EnemyAI enters, swaps each Visual/* mesh
## material for a toon ShaderMaterial. The replacement copies the source material's
## albedo + emission and chains a black inverted-hull outline as its next_pass.
##
## Elites work for free: RunDirector outfits them (crimson/gold emissive
## material_override + a 1.25x XZ Visual scale) BEFORE adding them to the tree,
## so by the time node_added fires that emissive material is already the active
## one. Reading it here carries the glow straight into the toon material, so
## elites stay crimson/gold while still picking up the banded shading.
##
## First pass scopes to enemies only; widening to weapons / pickups / world is
## just a matter of broadening the node filter below.

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/toon_outline.gdshader")
# Scale-compensated outline for the heavily-scaled character rig (see the shader).
const OUTLINE_SHADER_SCALED: Shader = preload("res://shaders/toon_outline_scaled.gdshader")

# Look tunables, kept in one place so the cel style is editable at a glance.
const BANDS := 3
const RIM_STRENGTH := 0.35
const RIM_WIDTH := 0.7
const OUTLINE_COLOR := Color(0.03, 0.02, 0.04)
# Outline width is a world-space hull offset, so its on-screen weight scales with
# viewing distance: enemies sit metres away, the first-person weapon ~0.45 m from
# the camera, so the weapon needs a far thinner line to read at the same weight.
const OUTLINE_WIDTH_ENEMY := 0.02
const OUTLINE_WIDTH_WEAPON := 0.003
const OUTLINE_WIDTH_PICKUP := 0.012
# The rigged character: a textured skin reads busier than a flat capsule, so a
# softer rim, and a world-space-constant ink line (the scaled outline shader
# compensates for the rig's ~62x cumulative scale).
const RIM_STRENGTH_CHARACTER := 0.2
const OUTLINE_WIDTH_CHARACTER := 0.03

# Shared outline passes (constant black hull), reused as next_pass per target.
var _outline_enemy: ShaderMaterial
var _outline_weapon: ShaderMaterial
var _outline_pickup: ShaderMaterial
var _outline_character: ShaderMaterial


func _ready() -> void:
	_outline_enemy = _make_outline(OUTLINE_WIDTH_ENEMY)
	_outline_weapon = _make_outline(OUTLINE_WIDTH_WEAPON)
	_outline_pickup = _make_outline(OUTLINE_WIDTH_PICKUP)
	_outline_character = _make_outline(OUTLINE_WIDTH_CHARACTER, OUTLINE_SHADER_SCALED)
	# Catch every enemy / weapon rig that spawns, in any scene, like the other
	# observers do.
	get_tree().node_added.connect(_on_node_added)


func _make_outline(width: float, shader: Shader = OUTLINE_SHADER) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("outline_width", width)
	m.set_shader_parameter("outline_color", OUTLINE_COLOR)
	return m


func _on_node_added(node: Node) -> void:
	if node is EnemyAI:
		_toonify_enemy(node)
	elif node is WeaponManager:
		# The viewmodels are built in WeaponManager._ready, which runs just AFTER
		# this fires, so defer the walk until they exist.
		_toonify_weapon.call_deferred(node)
	elif node is Pickup:
		# Same story -- Pickup self-builds its mesh in _ready -- so defer.
		_toonify_pickup.call_deferred(node)
	elif node is CSGShape3D:
		# Arena geometry (room 1 + the retained Floor/walls shell). Banding-only.
		_toonify_csg(node)
	elif node is StaticBody3D:
		# Procedural room obstacles (RoomBuilder boxes). Banding-only.
		_toonify_static_body(node)


func _toonify_enemy(enemy: Node) -> void:
	var visual := enemy.get_node_or_null("Visual")
	if visual == null:
		return
	for child in visual.get_children():
		if child is MeshInstance3D:
			_toonify_mesh(child, _outline_enemy)


func _toonify_weapon(wm: Node) -> void:
	if not is_instance_valid(wm):
		return
	# Each direct child of the manager is a weapon model root; its body + barrel
	# are direct MeshInstance3D children. The muzzle flash lives one level deeper
	# under a "MuzzleFlash" node, so only touching the root's direct mesh children
	# leaves the flash as the unshaded emissive billboard it needs to stay.
	for model in wm.get_children():
		for child in model.get_children():
			if child is MeshInstance3D:
				_toonify_mesh(child, _outline_weapon)


func _toonify_pickup(p: Node) -> void:
	if not is_instance_valid(p):
		return
	# Pickup self-builds a single floating BoxMesh child (plus a CollisionShape).
	# Its StandardMaterial3D carries the type colour + emission, so the toon copy
	# keeps the glow. Visibility toggles on consume/respawn leave the override be.
	for child in p.get_children():
		if child is MeshInstance3D:
			_toonify_mesh(child, _outline_pickup)


func _toonify_mesh(mesh: MeshInstance3D, outline: ShaderMaterial, rim := RIM_STRENGTH) -> void:
	# Read whatever material is currently active -- the scene's surface material
	# for a normal enemy, RunDirector's emissive override for an elite -- so the
	# toon copy keeps the original colour and any glow.
	mesh.material_override = _make_toon_material(mesh.get_active_material(0), outline, rim)


func _toonify_csg(csg: CSGShape3D) -> void:
	# Arena geometry is CSG, which inherits material_override from
	# GeometryInstance3D. Only render roots actually draw, and each arena box is an
	# independent root (its parent is a plain Node3D). The per-node `material`
	# (a StandardMaterial3D) supplies the colour. World is banding-only: outline = null.
	if not csg.is_root_shape():
		return
	# rim = 0: the view-dependent fresnel makes a bright ring on big flat surfaces
	# (it tracks the camera). World is banding-only, so kill it.
	csg.material_override = _make_toon_material(csg.get("material") as Material, null, 0.0)


func _toonify_static_body(body: Node) -> void:
	# Procedural room obstacles (RoomBuilder StaticBody3D + BoxMesh child). The
	# mesh is parented before the body enters the tree, so it's here already.
	# Banding-only to match the CSG world; rim = 0 to avoid the camera-tracking
	# fresnel ring on flat surfaces.
	for child in body.get_children():
		if child is MeshInstance3D:
			_toonify_mesh(child, null, 0.0)


## Build a toon ShaderMaterial from a source StandardMaterial3D (may be null),
## carrying its albedo + emission. `outline` chains as next_pass, or null for none.
func _make_toon_material(src: Material, outline: ShaderMaterial, rim := RIM_STRENGTH) -> ShaderMaterial:
	var albedo := Color.WHITE
	var emission := Color.BLACK
	var emission_energy := 0.0
	if src is StandardMaterial3D:
		var std := src as StandardMaterial3D
		albedo = std.albedo_color
		if std.emission_enabled:
			emission = std.emission
			emission_energy = std.emission_energy_multiplier

	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", albedo)
	mat.set_shader_parameter("bands", BANDS)
	mat.set_shader_parameter("rim_strength", rim)
	mat.set_shader_parameter("rim_width", RIM_WIDTH)
	mat.set_shader_parameter("emission_color", emission)
	mat.set_shader_parameter("emission_energy", emission_energy)
	mat.next_pass = outline
	return mat


## Cel material for a textured, skinned character rig: the toon banding + the rig's
## own skin texture (multiplied by `tint`, the archetype hue or white) + the
## scale-compensated ink outline. Called by CharacterApplicator, which owns the rig
## skin/tint -- this keeps the cel look (shader, bands, rim, outline) in one place.
func make_character_material(skin: Texture2D, tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", tint)
	mat.set_shader_parameter("albedo_texture", skin)
	mat.set_shader_parameter("bands", BANDS)
	mat.set_shader_parameter("rim_strength", RIM_STRENGTH_CHARACTER)
	mat.set_shader_parameter("rim_width", RIM_WIDTH)
	mat.set_shader_parameter("emission_color", Color.BLACK)
	mat.set_shader_parameter("emission_energy", 0.0)
	mat.next_pass = _outline_character
	return mat
