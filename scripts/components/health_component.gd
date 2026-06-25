class_name HealthComponent
extends Node
## Generic health container used by enemies (the player handles armor itself).

signal health_changed(health: float, max_health: float)
signal died

@export var max_health: float = 100.0

var health: float


func _ready() -> void:
	health = max_health


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health == 0.0:
		died.emit()


func heal(amount: float) -> void:
	if health <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func is_alive() -> bool:
	return health > 0.0
