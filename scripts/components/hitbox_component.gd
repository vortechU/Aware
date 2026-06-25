class_name HitboxComponent
extends Area3D
## Damage receiver area. Bullets raycast against the "hitbox" physics layer
## and call take_hit(). Routes damage into a HealthComponent with a per-part
## multiplier (head = 2.0 for the headshot bonus).

@export var damage_multiplier: float = 1.0
@export var health_path: NodePath

@onready var _health: HealthComponent = get_node(health_path)


## Returns {"headshot": bool, "killed": bool} so the shooter can show feedback.
## hit_point / hit_dir are optional: when supplied (real gunfire) they let the
## owner react to the precise shot -- e.g. fling the death ragdoll along the bullet
## and pop a head off on a headshot. Callers that don't care (test harnesses) can
## still pass just (damage, attacker_position).
func take_hit(base_damage: float, attacker_position: Vector3,
		hit_point: Vector3 = Vector3.INF, hit_dir: Vector3 = Vector3.ZERO) -> Dictionary:
	var was_alive := _health.is_alive()
	# Record the precise hit BEFORE applying damage: take_damage can trigger death
	# synchronously, so the ragdoll must already know this shot's point/direction.
	if hit_point != Vector3.INF and owner != null and owner.has_method("register_hit"):
		owner.register_hit(hit_point, hit_dir, damage_multiplier >= 1.5)
	_health.take_damage(base_damage * damage_multiplier)
	var killed := was_alive and not _health.is_alive()
	if owner != null and owner.has_method("on_hit"):
		owner.on_hit(attacker_position)
	return {"headshot": damage_multiplier >= 1.5, "killed": killed}
