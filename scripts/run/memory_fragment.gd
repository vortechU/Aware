class_name MemoryFragment
extends Area3D
## A self-building Memory Fragment that sits in a Fragment Room. Mirrors ExitGate:
## it constructs its own glowing data-shard + a floating id tag, and detects the
## player via body_entered on the player's collision layer (2). On first contact it
## records itself (FragmentDB) and announces the read on the GameEvents bus so the
## FragmentReader can display it, then dissolves. Optional by design -- the player
## only reads it if they choose to walk into it; it never blocks the path.

const ACCENT := Color(0.0, 0.9, 1.0)        # cyan data-shard
const SHARD_SIZE := Vector3(0.5, 0.8, 0.5)
const PICKUP_RADIUS := 1.4
const SPIN_SPEED := 1.2
const BOB_HEIGHT := 0.15
const BOB_SPEED := 2.0

var _fragment: Dictionary = {}
var _collected := false
var _time := 0.0
var _base_y := 0.0
var _shard: MeshInstance3D
var _material: StandardMaterial3D


## Set before add_child (like ExitGate.set_portal_shader); the visual reads it in _ready.
func set_fragment(fragment: Dictionary) -> void:
	_fragment = fragment


func fragment_id() -> String:
	return String(_fragment.get("id", ""))


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the player CharacterBody3D sits on layer 2
	monitoring = true
	monitorable = false
	_base_y = position.y
	_build_collision()
	_build_visual()
	body_entered.connect(_on_body_entered)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	add_child(shape)


func _build_visual() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = ACCENT
	_material.emission_enabled = true
	_material.emission = ACCENT
	_material.emission_energy_multiplier = 2.0
	_shard = MeshInstance3D.new()
	var mesh := PrismMesh.new()  # angular data-shard silhouette
	mesh.size = SHARD_SIZE
	_shard.mesh = mesh
	_shard.material_override = _material
	add_child(_shard)
	# Floating id tag above the shard so the fragment reads at a glance.
	var tag := Label3D.new()
	tag.text = fragment_id()
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.modulate = ACCENT
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0.0, SHARD_SIZE.y * 0.5 + 0.4, 0.0)
	add_child(tag)


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	if _shard != null:
		_shard.rotation.y = _time * SPIN_SPEED
	position.y = _base_y + sin(_time * BOB_SPEED) * BOB_HEIGHT


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	set_deferred("monitoring", false)
	FragmentDB.mark_collected(fragment_id())
	GameEvents.fragment_read.emit(_fragment)
	_dissolve()


## Shrink out, then free (the fragment has been recorded).
func _dissolve() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
	tween.tween_callback(queue_free)
