extends Node
## Combat FX: bullet tracers + impact decals. A sibling observer in the
## SettingsManager / AudioManager / ToonApplicator mould -- it only listens to the
## GameEvents bus and spawns cosmetic nodes, never touching gameplay scripts.
## weapon_manager emits `bullet_tracer` / `bullet_impact`; everything visual lives
## here.
##
## All visuals are built procedurally (a generated bullet-hole texture, code-built
## meshes/materials), matching the project's no-art-assets style. Spawned nodes are
## parented to the current scene so they die with it on a room rebuild / reload,
## grouped for cheap lookup, capped, and faded out. Stays valid under --headless
## (node creation only), so the smoke harness exercises it for free.

const MAX_DECALS := 96            # oldest recycled past this
const DECAL_SIZE_MIN := 0.12
const DECAL_SIZE_MAX := 0.2
const DECAL_HOLD := 8.0           # seconds at full opacity
const DECAL_FADE := 2.5           # then fade out over this
const DECAL_GROUP := "bullet_decal"

const TRACER_RADIUS := 0.015
const TRACER_LIFE := 0.06         # tracers are a brief streak
const TRACER_COLOR := Color(1.0, 0.85, 0.45)
const TRACER_GROUP := "bullet_tracer"
const TRACER_MIN_LENGTH := 0.5    # skip hits basically on the muzzle

var _decal_texture: Texture2D
var _decals: Array[Decal] = []


func _ready() -> void:
	_decal_texture = _make_hole_texture()
	GameEvents.bullet_tracer.connect(_on_bullet_tracer)
	GameEvents.bullet_impact.connect(_on_bullet_impact)


# ---------------------------------------------------------------- tracers

func _on_bullet_tracer(from: Vector3, to: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var length := from.distance_to(to)
	if length < TRACER_MIN_LENGTH:
		return

	var mesh := MeshInstance3D.new()
	mesh.add_to_group(TRACER_GROUP)
	var cyl := CylinderMesh.new()
	cyl.top_radius = TRACER_RADIUS
	cyl.bottom_radius = TRACER_RADIUS
	cyl.height = length
	cyl.radial_segments = 5
	cyl.rings = 0
	mesh.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TRACER_COLOR
	mat.emission_enabled = true
	mat.emission = TRACER_COLOR
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	scene.add_child(mesh)
	# CylinderMesh runs along local +Y, so align +Y with the shot direction.
	mesh.global_position = (from + to) * 0.5
	mesh.global_basis = _basis_with_y((to - from).normalized())

	var tween := mesh.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, TRACER_LIFE)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, TRACER_LIFE)
	tween.tween_callback(mesh.queue_free)


# ---------------------------------------------------------------- decals

func _on_bullet_impact(position: Vector3, normal: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var decal := Decal.new()
	decal.add_to_group(DECAL_GROUP)
	decal.texture_albedo = _decal_texture
	var s := randf_range(DECAL_SIZE_MIN, DECAL_SIZE_MAX)
	decal.size = Vector3(s, 0.25, s)  # projects along local -Y onto the surface
	decal.modulate = Color(1, 1, 1, 1)
	decal.cull_mask = 0xFFFFF

	scene.add_child(decal)
	decal.global_position = position
	# Decal projects down its local -Y, so point local +Y out along the surface
	# normal, with a random roll for variety.
	decal.global_basis = _basis_with_y(normal, randf() * TAU)

	_register_decal(decal)

	var tween := decal.create_tween()
	tween.tween_interval(DECAL_HOLD)
	tween.tween_property(decal, "modulate:a", 0.0, DECAL_FADE)
	tween.tween_callback(func() -> void:
		_decals.erase(decal)
		decal.queue_free())


func _register_decal(decal: Decal) -> void:
	# Drop any freed entries, then recycle the oldest if we're at the cap.
	_decals = _decals.filter(func(d: Decal) -> bool: return is_instance_valid(d))
	while _decals.size() >= MAX_DECALS:
		var oldest: Decal = _decals.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_decals.append(decal)


# ---------------------------------------------------------------- helpers

## Orthonormal basis whose +Y axis is `dir`, optionally rolled around it.
func _basis_with_y(dir: Vector3, roll := 0.0) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var basis := Basis(x, y, z)
	if roll != 0.0:
		basis = basis.rotated(y, roll)
	return basis


## A round scorch / bullet hole: dark centre, soft transparent edge. The alpha
## channel is the hole shape (Decals use albedo alpha as coverage).
func _make_hole_texture() -> Texture2D:
	var res := 32
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var center := Vector2(res - 1, res - 1) * 0.5
	var max_d := float(res) * 0.5
	for y in res:
		for x in res:
			var d := Vector2(x, y).distance_to(center) / max_d
			var alpha := 1.0 - smoothstep(0.35, 0.95, d)
			# Slightly lighter scorched ring just inside the edge.
			var shade := lerpf(0.04, 0.18, smoothstep(0.0, 0.6, d))
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(img)
