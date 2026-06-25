class_name Grenade
extends Node3D
## Thrown by the Grenadier enemy archetype. A self-contained lob: it follows a
## ballistic arc (integrated by hand so it lands where it was aimed regardless of
## the physics gravity setting), shows a ground "danger" ring at the target so the
## player is warned to move, and on impact (world hit or fuse) explodes with a
## falloff AoE that damages the player only on a clear line. Built procedurally to
## match the project's no-art style. A sibling node, parented to the live scene --
## it survives and explodes even if its thrower dies. No existing script edited.

const FLIGHT_TIME := 1.15   # seconds to reach the aim point
const GRAVITY := 22.0       # arc gravity (independent of project physics gravity)
const FUSE_EXTRA := 0.5     # backstop fuse past the expected landing

@export var damage: float = 30.0
@export var blast_radius: float = 4.5

var _vel := Vector3.ZERO
var _t := 0.0
var _exploded := false
var _marker: Node3D
var _player: Node3D


func _ready() -> void:
	add_to_group("enemy_grenade")
	_player = get_tree().get_first_node_in_group("player")
	_build_mesh()


## Aim the lob at a world point (usually the ground under the target). Call AFTER
## the node is in the tree and positioned at the muzzle.
func launch_at(target: Vector3) -> void:
	var from := global_position
	_vel = Vector3((target.x - from.x) / FLIGHT_TIME, 0.0, (target.z - from.z) / FLIGHT_TIME)
	_vel.y = (target.y - from.y) / FLIGHT_TIME + 0.5 * GRAVITY * FLIGHT_TIME
	_spawn_marker(target)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_vel.y -= GRAVITY * delta
	var next := global_position + _vel * delta
	# Explode on the first world surface along the step (ground, wall, cover).
	var params := PhysicsRayQueryParameters3D.create(global_position, next, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		global_position = hit.position
		_explode()
		return
	global_position = next
	rotation += Vector3(8.0, 5.0, 3.0) * delta  # tumble in flight
	_t += delta
	if _t >= FLIGHT_TIME + FUSE_EXTRA:
		_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	if is_instance_valid(_marker):
		_marker.queue_free()

	# Falloff AoE, but only on a clear line (a wall fully shields the player).
	if _player != null and is_instance_valid(_player):
		var target := _player.global_position + Vector3.UP * 0.9
		var d := global_position.distance_to(target)
		if d <= blast_radius:
			var p := PhysicsRayQueryParameters3D.create(global_position, target, 1)
			if get_world_3d().direct_space_state.intersect_ray(p).is_empty():
				var dmg := damage * (1.0 - d / blast_radius)
				if dmg > 0.0:
					_player.call("take_damage", dmg, global_position)

	GameEvents.sound_emitted.emit(global_position, 24.0)  # a blast is loud
	if GameEvents.has_signal("bullet_impact"):
		GameEvents.bullet_impact.emit(global_position, Vector3.UP)
	_spawn_blast()

	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
	await get_tree().create_timer(0.6).timeout
	queue_free()


func _build_mesh() -> void:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	m.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.22, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 0.2)
	mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


## Flat ring on the ground at the aim point, so the player sees where it lands.
func _spawn_marker(target: Vector3) -> void:
	_marker = Node3D.new()
	_marker.top_level = true
	add_child(_marker)
	_marker.global_position = target + Vector3.UP * 0.05
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = blast_radius
	cyl.bottom_radius = blast_radius
	cyl.height = 0.04
	ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.35, 0.1, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(ring)


func _spawn_blast() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.25)
	mat.emission_energy_multiplier = 4.0
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(flash)
	flash.global_position = global_position
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * (blast_radius * 0.9), 0.32)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	tween.chain().tween_callback(flash.queue_free)
