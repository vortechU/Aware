class_name ExitGate
extends Area3D
## Self-building exit portal that appears when a room is cleared. Instead of the
## next room starting the instant the last enemy dies, this gate is spawned at
## the far end of the room; the player roams to grab any remaining pickups, then
## walks through it to trigger the transition.
##
## Build-alongside, mirroring Pickup: it constructs its own visuals and detects
## the player via body_entered on the player's collision layer (layer 2). It
## emits player_entered once; RunDirector awaits that to run the room change.
##
## The portal plane can carry a spatial Matrix-spiral shader (set externally via
## set_portal_shader so the headless harnesses never need to compile it); a plain
## emissive material is used as the fallback.

signal player_entered

const GREEN := Color(0.15, 1.0, 0.45)   # matrix green
const PORTAL_SIZE := Vector2(3.0, 4.2)  # doorway width x height (metres)
const FRAME_THICKNESS := 0.22
const TRIGGER_DEPTH := 1.8              # walk-through depth along the facing axis
const SPAWN_POP_SPEED := 6.0            # how fast the gate scales in

var _portal_shader: Shader = null

var _time := 0.0
var _triggered := false
var _portal_mesh: MeshInstance3D
var _portal_material: ShaderMaterial
var _frame_material: StandardMaterial3D


## Optional: supply the spatial spiral shader before add_child. When absent the
## portal uses a plain emissive material, so headless loads never touch a shader.
func set_portal_shader(shader: Shader) -> void:
	_portal_shader = shader


## Orient the gate so its visible face (local +Z) looks at a world point,
## typically the player spawn. Call after positioning, before/after add_child.
func face_toward(target: Vector3) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length_squared() < 0.001:
		return
	rotation.y = atan2(d.x, d.z)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the player CharacterBody3D sits on layer 2
	monitoring = true
	monitorable = false
	_build_collision()
	_build_visual()
	body_entered.connect(_on_body_entered)
	scale = Vector3.ONE * 0.02  # pops up to full size in _process


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PORTAL_SIZE.x, PORTAL_SIZE.y, TRIGGER_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, PORTAL_SIZE.y * 0.5, 0.0)
	add_child(shape)


func _build_visual() -> void:
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = GREEN
	_frame_material.emission_enabled = true
	_frame_material.emission = GREEN
	_frame_material.emission_energy_multiplier = 2.2

	# Rectangular frame: two uprights, a lintel and a sill.
	var half_w := PORTAL_SIZE.x * 0.5
	var t := FRAME_THICKNESS
	_add_frame_bar(Vector3(t, PORTAL_SIZE.y + t, t), Vector3(-half_w, PORTAL_SIZE.y * 0.5, 0.0))
	_add_frame_bar(Vector3(t, PORTAL_SIZE.y + t, t), Vector3(half_w, PORTAL_SIZE.y * 0.5, 0.0))
	_add_frame_bar(Vector3(PORTAL_SIZE.x + t, t, t), Vector3(0.0, PORTAL_SIZE.y + t * 0.5, 0.0))
	_add_frame_bar(Vector3(PORTAL_SIZE.x + t, t, t), Vector3(0.0, -t * 0.5, 0.0))

	# Portal surface: a flat plane carrying the spiral (or a fallback glow).
	_portal_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = PORTAL_SIZE
	_portal_mesh.mesh = quad
	_portal_mesh.position = Vector3(0.0, PORTAL_SIZE.y * 0.5, 0.0)
	_portal_mesh.material_override = _make_portal_material()
	add_child(_portal_mesh)


func _add_frame_bar(size: Vector3, pos: Vector3) -> void:
	var bar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	bar.mesh = mesh
	bar.material_override = _frame_material
	bar.position = pos
	add_child(bar)


func _make_portal_material() -> Material:
	if _portal_shader != null:
		_portal_material = ShaderMaterial.new()
		_portal_material.shader = _portal_shader
		_portal_material.set_shader_parameter("tint", GREEN)
		return _portal_material
	# Fallback: translucent emissive pane, no shader compilation required.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = GREEN
	mat.emission_energy_multiplier = 1.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _process(delta: float) -> void:
	_time += delta
	# Spawn pop-in toward full size.
	if scale.x < 0.999:
		var s: float = minf(1.0, lerpf(scale.x, 1.0, delta * SPAWN_POP_SPEED) + delta)
		scale = Vector3.ONE * s
	# Gentle emission pulse on the frame for a "live portal" feel.
	if _frame_material != null:
		_frame_material.emission_energy_multiplier = 2.0 + sin(_time * 3.0) * 0.6


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	set_deferred("monitoring", false)
	player_entered.emit()
