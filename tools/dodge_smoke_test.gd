extends Node
## Headless test for reactive enemy dodging (DODGE_SMOKE_OK).
## Run: godot --headless --path . res://tools/dodge_smoke_test.tscn
##
## When a player shot (GameEvents.bullet_tracer) passes close to an aware, agile
## enemy it should juke sideways. Built in a code world (floor + frozen player +
## one enemy); the dodge is driven by emitting bullet_tracer and reading the
## enemy's state -- no navmesh needed. Covers the positive juke + the cooldown and
## the four cases that must NOT dodge (far shot, enemy-origin shot, sniper, patrol).

var fails: Array[String] = []
var _enemy: Node3D
var _player: Node3D


func _ready() -> void:
	# Floor so the lateral juke actually translates the body.
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor.add_child(cs)
	add_child(floor)
	floor.global_position = Vector3(0, -0.5, 0)  # top at y=0

	_player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.add_to_group("player")
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_unhandled_input(false)
	_player.global_position = Vector3(0, 1.0, -5.0)

	_enemy = (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	add_child(_enemy)
	_enemy.global_position = Vector3(0, 0.1, 0)
	_enemy.set("_player", _player)
	# Make the trigger deterministic and stop senses from changing state mid-test.
	_enemy.set("dodge_chance", 1.0)
	_enemy.set("sight_range", 0.0)

	for i in 18:  # let it settle onto the floor
		await get_tree().physics_frame

	await _run()
	if fails.is_empty():
		print("DODGE_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("DODGE_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _dodging() -> bool:
	return float(_enemy.get("_dodge_time_left")) > 0.0


## Put the enemy in an aware state with the dodge ready to fire.
func _arm(combat_state: int) -> void:
	_enemy.set("state", combat_state)
	_enemy.set("_last_known_player_pos", _player.global_position)
	_enemy.set("_dodge_time_left", 0.0)
	_enemy.set("_dodge_cooldown", 0.0)


## A player shot whose line ends right on the enemy.
func _shoot_at_enemy() -> void:
	GameEvents.bullet_tracer.emit(_player.global_position + Vector3.UP * 1.2,
			_enemy.global_position + Vector3.UP * 0.9)


func _run() -> void:
	# --- Positive: an aware enemy jukes a near shot and translates sideways. ---
	_arm(2)  # State.CHASE
	await get_tree().physics_frame
	var x0: float = _enemy.global_position.x
	_shoot_at_enemy()
	_check(_dodging(), "enemy should start dodging a shot that passes through it")
	_check(float(_enemy.get("_dodge_cooldown")) > 0.0, "starting a dodge should arm the cooldown")
	for i in 26:  # ride out the juke (dodge_duration ~0.32s)
		await get_tree().physics_frame
	var dx: float = absf(_enemy.global_position.x - x0)
	_check(dx > 1.0, "dodge should move the enemy sideways, moved only %.2f m" % dx)

	# Cooldown: a fresh near shot right after must NOT start another dodge.
	_check(not _dodging(), "dodge should have ended by now")
	_shoot_at_enemy()
	_check(not _dodging(), "cooldown should block a second dodge so soon")

	# --- Negative cases (each re-armed so only the case under test can block). ---
	_arm(2)
	GameEvents.bullet_tracer.emit(_player.global_position + Vector3.UP * 1.2,
			_player.global_position + Vector3(0, 1, -50))  # shot heads away from the enemy
	_check(not _dodging(), "a shot that misses by a lot should not trigger a dodge")

	_arm(2)
	GameEvents.bullet_tracer.emit(_enemy.global_position + Vector3(10, 1, 0),
			_enemy.global_position + Vector3.UP * 0.9)  # originates far from the player
	_check(not _dodging(), "a shot not fired by the player should be ignored")

	_arm(2)
	_enemy.set("is_sniper", true)
	_shoot_at_enemy()
	_check(not _dodging(), "snipers should hold their ground, not dodge")
	_enemy.set("is_sniper", false)

	_arm(0)  # State.PATROL (unaware)
	_shoot_at_enemy()
	_check(not _dodging(), "an unaware (patrolling) enemy should not psychically dodge")
