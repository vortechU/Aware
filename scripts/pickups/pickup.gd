class_name Pickup
extends Area3D
## Floating pickup (ammo / health / armor). Builds its own visuals, spins,
## grants on player touch and respawns after a delay.

enum Type { AMMO, HEALTH, ARMOR }

const COLORS := {
	Type.AMMO: Color(0.85, 0.7, 0.2),
	Type.HEALTH: Color(0.9, 0.25, 0.25),
	Type.ARMOR: Color(0.3, 0.55, 0.95),
}

@export var type: Type = Type.HEALTH
@export var amount: float = 35.0
@export var respawn_time: float = 15.0

var _base_y := 0.0
var _time := 0.0
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	_base_y = position.y

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	add_child(shape)

	var mat := StandardMaterial3D.new()
	var color: Color = COLORS[type]
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.45, 0.45)
	box.material = mat
	_mesh_instance.mesh = box
	_mesh_instance.position.y = 0.5
	add_child(_mesh_instance)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_mesh_instance.rotation.y += delta * 2.0
	position.y = _base_y + 0.12 + sin(_time * 2.2) * 0.1


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var consumed := bool(body.call("try_pickup", int(type), amount))
	if not consumed:
		return
	visible = false
	set_deferred("monitoring", false)
	set_process(false)
	await get_tree().create_timer(respawn_time).timeout
	visible = true
	set_deferred("monitoring", true)
	set_process(true)
