class_name ShockField
extends Node3D
## An attached effect node -- the "attach-effect-node" trait archetype (vs Heavy's
## mutate-body). A TraitInstance adds one of these to a hacked host and frees it on
## expire; it periodically zaps every enemy within radius via the existing enemy
## `BodyHitbox.take_hit` path, WITHOUT touching the host's own physics (a shocked wall
## stays a wall). Damage is by group-proximity, like Stack Smash / the Heavy crush --
## the established pattern, deterministic and no physics-overlap timing to wait on.

var damage := 18.0
var radius := 4.0
var period := 0.5

var _accum := 0.0


func setup(p_damage: float, p_radius: float, p_period: float) -> void:
	damage = p_damage
	radius = p_radius
	period = maxf(p_period, 0.05)


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < period:
		return
	_accum -= period
	_pulse()


## One zap: damage every enemy inside the radius and feed the world hearing sense.
func _pulse() -> void:
	var center := global_position
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.global_position.distance_to(center) > radius:
			continue
		var hitbox := enemy.get_node_or_null("BodyHitbox")
		if hitbox != null and hitbox.has_method("take_hit"):
			hitbox.take_hit(damage, center)
	GameEvents.sound_emitted.emit(center, radius)
