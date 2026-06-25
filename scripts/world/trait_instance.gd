class_name TraitInstance
extends RefCounted
## A single adjective applied live to one Hackable host. It SNAPSHOTS the host body's
## physics state on apply and RESTORES it byte-for-byte on expire, so an injected
## property is always temporary -- nothing in a generated room is permanently mutated
## (navmesh, procgen and the room-transition flow stay clean). Every trait also auto-
## decays on a timer.
##
## Per-adjective behaviour is a match() here (mirrors AbilityManager's effect style):
## a new adjective adds an arm in apply/tick without touching the snapshot scaffolding.
## P1 ships one -- Heavy (mutate-body archetype).

var host: Hackable
var adjective_id: String           ## catalog id, e.g. "heavy"
var rank: int
var time_left: float
var def: Dictionary

var _snapshot: Dictionary = {}
var _crushed: Dictionary = {}      ## instance_id -> true, so each enemy is crushed once
var _effect_node: Node = null      ## attach-effect-node archetype (e.g. Shocking's ShockField)


## Snapshot the host, then run the adjective's apply arm.
func apply(p_host: Hackable, p_id: String, p_rank: int, p_def: Dictionary) -> void:
	host = p_host
	adjective_id = p_id
	rank = p_rank
	def = p_def
	time_left = float(def.get("duration", 5.0)) \
			+ float(def.get("duration_per_rank", 0.0)) * float(rank - 1)
	var b := _body()
	if b == null:
		return
	_snapshot = _capture(b)
	match adjective_id:
		"heavy":
			_apply_heavy(b)
		"shocking":
			_apply_shocking(b)


## Advance one frame. Returns false once the trait has expired (the manager then calls
## expire() and drops it).
func tick(delta: float) -> bool:
	time_left -= delta
	var b := _body()
	if b != null:
		match adjective_id:
			"heavy":
				_tick_heavy(b)
	return time_left > 0.0 and host != null and is_instance_valid(host)


## Revert the host to exactly how it was before the hack.
func expire() -> void:
	# Tear down any attached effect node (attach-effect-node archetype) first.
	if _effect_node != null and is_instance_valid(_effect_node):
		_effect_node.queue_free()
	_effect_node = null
	var b := _body()
	if b != null:
		_restore(b, _snapshot)


# ---------------------------------------------------------------- heavy

## Release the prop under heavy gravity -- it drops and crushes whatever is beneath it.
func _apply_heavy(body: PhysicsBody3D) -> void:
	var rb := body as RigidBody3D
	if rb == null:
		return
	rb.mass = float(def.get("mass", 60.0))
	rb.gravity_scale = float(def.get("gravity_scale", 4.0))
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.freeze = false  # gravity now takes over


## While falling fast, deal a one-shot crush to each enemy under the mass (proximity +
## "below", not physics contact, so it's deterministic and never bounces off the target).
func _tick_heavy(body: PhysicsBody3D) -> void:
	var rb := body as RigidBody3D
	if rb == null or rb.linear_velocity.y > -float(def.get("crush_min_speed", 2.0)):
		return
	var radius := float(def.get("crush_radius", 1.8))
	var damage := float(def.get("crush_damage", 80.0)) \
			+ float(def.get("crush_damage_per_rank", 0.0)) * float(rank - 1)
	var center := rb.global_position
	for node in rb.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var eid := enemy.get_instance_id()
		if _crushed.has(eid):
			continue
		var ep := enemy.global_position
		if ep.y > center.y + 0.5:
			continue  # enemy is above the falling mass, not under it
		if Vector2(ep.x - center.x, ep.z - center.z).length() > radius:
			continue
		var hitbox := enemy.get_node_or_null("BodyHitbox")
		if hitbox != null and hitbox.has_method("take_hit"):
			hitbox.take_hit(damage, center)
			_crushed[eid] = true


# ---------------------------------------------------------------- shocking

## Attach a ShockField to the host (NOT mutating the body): it pulses damage to nearby
## enemies on its own timer. The effect node is freed in expire().
func _apply_shocking(body: PhysicsBody3D) -> void:
	var field := ShockField.new()
	field.name = "ShockField"
	field.setup(
			float(def.get("shock_damage", 18.0)) \
					+ float(def.get("shock_damage_per_rank", 0.0)) * float(rank - 1),
			float(def.get("shock_radius", 4.0)),
			float(def.get("shock_period", 0.5)))
	body.add_child(field)
	_effect_node = field


# ---------------------------------------------------------------- snapshot / restore

func _body() -> PhysicsBody3D:
	if host == null or not is_instance_valid(host):
		return null
	var b := host.body
	if b == null or not is_instance_valid(b):
		return null
	return b


func _capture(body: PhysicsBody3D) -> Dictionary:
	var snap := {
		"global_transform": body.global_transform,
		"collision_layer": body.collision_layer,
		"collision_mask": body.collision_mask,
	}
	var rb := body as RigidBody3D
	if rb != null:
		snap["freeze"] = rb.freeze
		snap["freeze_mode"] = rb.freeze_mode
		snap["mass"] = rb.mass
		snap["gravity_scale"] = rb.gravity_scale
		snap["physics_material_override"] = rb.physics_material_override
	return snap


func _restore(body: PhysicsBody3D, snap: Dictionary) -> void:
	if snap.is_empty():
		return
	body.collision_layer = int(snap.get("collision_layer", body.collision_layer))
	body.collision_mask = int(snap.get("collision_mask", body.collision_mask))
	var rb := body as RigidBody3D
	if rb != null:
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.mass = float(snap.get("mass", rb.mass))
		rb.gravity_scale = float(snap.get("gravity_scale", rb.gravity_scale))
		rb.physics_material_override = snap.get("physics_material_override", rb.physics_material_override)
		rb.freeze_mode = snap.get("freeze_mode", rb.freeze_mode)
		rb.freeze = bool(snap.get("freeze", rb.freeze))
	# Re-seat the prop AFTER re-freezing so the static placement sticks.
	body.global_transform = snap.get("global_transform", body.global_transform)
