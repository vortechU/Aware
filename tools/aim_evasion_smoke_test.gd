extends Node
## Headless unit test for movement-trick aim fairness (AIM_EVASION_OK).
## Run: godot --headless --path . res://tools/aim_evasion_smoke_test.tscn
##
## EnemyAI._player_evasion_spread() widens enemy aim spread when the player is
## wall-running / sliding / dashing / vaulting / carrying momentum, so skilful
## movement is rewarded with harder-to-hit fairness. No navmesh or room needed:
## it pokes the player's movement state directly and reads the helper.

var fails: Array[String] = []
var _enemy: Node
var _player: Node


func _ready() -> void:
	_player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.add_to_group("player")
	add_child(_player)
	# Freeze the player so the values we poke in don't get overwritten by its own
	# movement update before we read them.
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_unhandled_input(false)

	_enemy = (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	add_child(_enemy)
	_enemy.set_physics_process(false)
	_enemy.set("_player", _player)
	await get_tree().process_frame

	_run()
	if fails.is_empty():
		print("AIM_EVASION_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("AIM_EVASION_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


## Set the player's movement state and read the resulting aim-spread bonus.
## ms: MoveState int (WALK0 SPRINT1 CROUCH2 PRONE3 SLIDE4 WALLRUN5 VAULT6).
func _ev(ms: int, dash: float, momentum: float) -> float:
	_player.set("move_state", ms)
	_player.set("_dash_time_left", dash)
	_player.set("momentum", momentum)
	return float(_enemy.call("_player_evasion_spread"))


func _run() -> void:
	# Walking, grounded, no momentum: no trick bonus at all.
	_check(_approx(_ev(0, 0.0, 0.0), 0.0), "baseline (walk) should add no spread")
	_check(_approx(_ev(1, 0.0, 0.0), 0.0), "sprinting alone is not a 'trick' (handled by velocity)")

	# Each trick adds its own penalty.
	_check(_approx(_ev(5, 0.0, 0.0), EnemyAI.EVADE_WALLRUN), "wall-run spread bonus wrong")
	_check(_approx(_ev(4, 0.0, 0.0), EnemyAI.EVADE_SLIDE), "slide spread bonus wrong")
	_check(_approx(_ev(6, 0.0, 0.0), EnemyAI.EVADE_VAULT), "vault spread bonus wrong")
	_check(_approx(_ev(0, 0.5, 0.0), EnemyAI.EVADE_DASH), "dash spread bonus wrong")

	# Momentum scales linearly 0..1.
	_check(_approx(_ev(0, 0.0, 1.0), EnemyAI.EVADE_MOMENTUM), "full momentum spread wrong")
	_check(_approx(_ev(0, 0.0, 0.5), EnemyAI.EVADE_MOMENTUM * 0.5), "half momentum should be half")
	_check(_approx(_ev(0, 0.0, 0.0), 0.0), "zero momentum should add nothing")

	# Tricks stack (wall-run + dash + full momentum).
	_check(_approx(_ev(5, 0.5, 1.0),
			EnemyAI.EVADE_WALLRUN + EnemyAI.EVADE_DASH + EnemyAI.EVADE_MOMENTUM),
			"stacked trick spread wrong")

	# Sanity: a wall-running player is evaded more than a walking one.
	var wallrun := _ev(5, 0.0, 0.0)
	var walk := _ev(0, 0.0, 0.0)
	_check(wallrun > walk, "wall-running should be harder to hit than walking")

	# Null-player safety: the helper must not crash if the player is gone.
	_enemy.set("_player", null)
	_check(_approx(float(_enemy.call("_player_evasion_spread")), 0.0),
			"missing player should yield zero, not a crash")
	_enemy.set("_player", _player)
