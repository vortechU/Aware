extends Node
## Headless test for the Overclock ability, active abilities Pass 3 (OVERCLOCK_OK).
## Run: godot --headless --path . res://tools/overclock_test.tscn
##
## Overclock drops every enemy's `ai_time_scale` for a few seconds (enemies slow, the
## player does not). Hook: `EnemyAI` scales its whole delta-driven update by
## `ai_time_scale` (default 1.0 = inert) -- proven here by a slowed enemy's weapon
## timer bleeding down ~quarter-speed vs a normal one. Ability: AbilityManager.grant
## equips it; an `ability` press holds every live enemy at the slow factor for the
## duration, then releases them to 1.0 on expiry, and arms the cooldown. Code world
## (floor + live player + real enemies via sight_range 0); no navmesh needed.

var fails: Array[String] = []
var _used_signal_id := ""


func _ready() -> void:
	GameEvents.ability_used.connect(func(_slot: int, id: String): _used_signal_id = id)
	await _run()
	if Input.is_action_pressed("ability"):
		Input.action_release("ability")
	if fails.is_empty():
		print("OVERCLOCK_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("OVERCLOCK_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _make_static_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	return body


## A real enemy left in PATROL (sight_range 0 so it never chases) but with its physics
## live, so its delta-driven timers actually tick.
func _make_enemy(pos: Vector3) -> Node3D:
	var enemy := (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Node3D
	enemy.add_to_group("enemies")
	add_child(enemy)
	enemy.global_position = pos
	enemy.set("sight_range", 0.0)
	return enemy


func _run() -> void:
	add_child(_make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0)))

	var player: Player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.add_to_group("player")
	add_child(player)
	var am: AbilityManager = player.get_node("AbilityManager")
	await get_tree().physics_frame

	# ---- 1. enemy_ai hook proof: a low ai_time_scale slows delta-driven timers ----
	# Two enemies, both with a long dodge cooldown counting down by delta; one slowed.
	var slow_enemy := _make_enemy(Vector3(-4, 0.1, 0))
	var normal_enemy := _make_enemy(Vector3(4, 0.1, 0))
	_check(float(normal_enemy.get("ai_time_scale")) == 1.0, "enemy ai_time_scale should default to 1.0")
	slow_enemy.set("_dodge_cooldown", 10.0)
	normal_enemy.set("_dodge_cooldown", 10.0)
	slow_enemy.set("ai_time_scale", 0.25)
	for _i in 30:
		await get_tree().physics_frame
	var drop_slow: float = 10.0 - float(slow_enemy.get("_dodge_cooldown"))
	var drop_normal: float = 10.0 - float(normal_enemy.get("_dodge_cooldown"))
	_check(drop_normal > 0.05, "control enemy's timer should bleed down normally (%.3f)" % drop_normal)
	_check(drop_slow < drop_normal * 0.5,
			"ai_time_scale 0.25 should slow the timer to well under half speed (slow %.3f vs normal %.3f)"
			% [drop_slow, drop_normal])
	slow_enemy.set("ai_time_scale", 1.0)  # back to normal before the ability test

	# ---- 2. grant: Overclock equips at rank 1 and is castable on the ground ----
	_check(am.grant("overclock"), "grant(overclock) should succeed")
	_check(am.equipped_id() == "overclock", "Overclock should be equipped in slot 0")
	_check(am.rank_of() == 1, "first grant should be rank 1 (%d)" % am.rank_of())
	_check(am.can_cast(), "Overclock should be castable on the ground (no airborne requirement)")

	# ---- 3. cast: every live enemy is held at the slow factor ----
	Input.action_press("ability")
	var cast := false
	for _i in 5:
		await get_tree().physics_frame
		if am._overclock_time_left > 0.0:
			cast = true
			break
	Input.action_release("ability")
	_check(cast, "pressing the ability key should start Overclock")
	_check(_used_signal_id == "overclock", "casting should emit ability_used for overclock")
	_check(am.cooldown_left() > 0.0, "casting should arm the cooldown")
	var slow: float = am._overclock_slow
	_check(absf(float(slow_enemy.get("ai_time_scale")) - slow) < 0.001
			and absf(float(normal_enemy.get("ai_time_scale")) - slow) < 0.001,
			"every enemy should be slowed to the overclock factor (%.2f)" % slow)

	# ---- 4. expiry: enemies are released back to normal ----
	am._overclock_time_left = 0.05  # fast-forward to the end of the effect
	for _i in 6:
		await get_tree().physics_frame
	_check(absf(float(slow_enemy.get("ai_time_scale")) - 1.0) < 0.001
			and absf(float(normal_enemy.get("ai_time_scale")) - 1.0) < 0.001,
			"enemies should return to ai_time_scale 1.0 when Overclock ends")
