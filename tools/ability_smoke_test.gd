extends Node
## Headless test for the active-ability system, Pass 1 (ABILITY_SMOKE_OK).
## Run: godot --headless --path . res://tools/ability_smoke_test.tscn
##
## Covers the AbilityManager (child of the real player.tscn) and the first ability,
## Stack Smash. Grant: the first grant equips at rank 1 and leaves it ready; a repeat
## grant ranks up and shortens the cooldown; a non-ability id is rejected (so
## PlayerUpgrades still warns on a truly unknown id). Cast: in a code world (floor +
## two inert enemies + the live player), an airborne cast drives the player down and,
## on landing, deals AoE damage to the in-radius enemy while leaving the out-of-radius
## enemy untouched, and arms the cooldown. Cooldown: blocks a recast even when airborne,
## then ticks down to ready. No navmesh needed; no persistence touched.

var fails: Array[String] = []
var _used_signal_id := ""


func _ready() -> void:
	GameEvents.ability_used.connect(func(_slot: int, id: String): _used_signal_id = id)
	await _run()
	if Input.is_action_pressed("ability"):
		Input.action_release("ability")
	if fails.is_empty():
		print("ABILITY_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("ABILITY_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _make_static_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # "world" -- the player's collision_mask includes it
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	return body


## A real enemy, made inert: sight_range 0 keeps it from chasing and its process is
## off so it stays exactly where placed (a deterministic AoE target). take_hit still
## routes damage into its HealthComponent regardless.
func _make_enemy(pos: Vector3) -> Node3D:
	var enemy := (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Node3D
	add_child(enemy)
	enemy.global_position = pos
	enemy.set("sight_range", 0.0)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy


func _run() -> void:
	# ---- world: a floor with its top at y=0 ----
	add_child(_make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0)))

	var player: Player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.add_to_group("player")
	add_child(player)
	var am: AbilityManager = player.get_node("AbilityManager")
	await get_tree().physics_frame

	# ---- 1. grant: first grant equips Stack Smash at rank 1, ready to use ----
	_check(am.grant("stack_smash"), "grant(stack_smash) should succeed")
	_check(am.equipped_id() == "stack_smash", "first grant should equip stack_smash in slot 0")
	_check(am.rank_of() == 1, "first grant should be rank 1 (%d)" % am.rank_of())
	_check(am.is_ready(), "a freshly granted ability should be ready")
	var cd_rank1: float = am.cooldown_total()

	# A non-ability id is rejected and must not disturb the slot.
	_check(not am.grant("definitely_not_an_ability"), "grant should reject a non-ability id")
	_check(am.equipped_id() == "stack_smash", "a rejected grant must not change the equipped slot")

	# ---- enemies: one inside the blast radius, one well outside ----
	var near := _make_enemy(Vector3(1.5, 0.1, 0.0))
	var far := _make_enemy(Vector3(16.0, 0.1, 0.0))
	var near_hp := near.get_node("Health") as HealthComponent
	var far_hp := far.get_node("Health") as HealthComponent
	var near_full: float = near_hp.health
	var far_full: float = far_hp.health

	# ---- 2. cast: an airborne slam lands and damages only the in-radius enemy ----
	player.global_position = Vector3(0.0, 4.0, 0.0)
	player.velocity = Vector3.ZERO
	player.move_state = Player.MoveState.WALK
	await get_tree().physics_frame
	_check(not player.is_on_floor(), "slam setup: player should be airborne")
	_check(am.can_cast(), "should be able to cast airborne with the cooldown ready")

	# Hold the action across a few physics frames so the AbilityManager catches the
	# just_pressed edge regardless of input-flush timing (same approach as _do_dash
	# in movement_smoke_test).
	Input.action_press("ability")
	var cast := false
	for _i in 5:
		await get_tree().physics_frame
		if am.cooldown_left() > 0.0:
			cast = true
			break
	Input.action_release("ability")
	_check(cast, "casting should arm the cooldown")
	_check(_used_signal_id == "stack_smash", "casting should emit GameEvents.ability_used")

	# Let the slam fall and resolve on touchdown.
	var landed := false
	for _i in 80:
		await get_tree().physics_frame
		if player.is_on_floor():
			landed = true
			break
	_check(landed, "the slam did not bring the player back to the floor")
	await get_tree().physics_frame  # one more frame so the post-land resolve runs
	_check(near_hp.health < near_full,
			"in-radius enemy should take slam damage (%.1f / %.1f)" % [near_hp.health, near_full])
	_check(far_hp.health == far_full,
			"out-of-radius enemy must be untouched (%.1f / %.1f)" % [far_hp.health, far_full])

	# ---- 3. cooldown gate: airborne again, but the cooldown blocks a recast ----
	player.global_position = Vector3(0.0, 4.0, 0.0)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	_check(not player.is_on_floor(), "recast setup: player should be airborne")
	_check(not am.can_cast(), "the cooldown should block a recast even while airborne")

	# ---- 4. cooldown ticks down to ready ----
	am._slots[0]["cd_left"] = 0.1  # crank down for a fast, deterministic refill
	var ready_again := false
	for _i in 30:
		await get_tree().physics_frame
		if am.is_ready():
			ready_again = true
			break
	_check(ready_again, "the cooldown should tick down to ready")

	# ---- 5. rank up: a repeat grant raises the rank and shortens the cooldown ----
	_check(am.grant("stack_smash"), "a repeat grant should succeed")
	_check(am.rank_of() == 2, "a repeat grant should rank up to 2 (%d)" % am.rank_of())
	_check(am.cooldown_total() < cd_rank1,
			"rank 2 cooldown should be shorter than rank 1 (%.2f vs %.2f)"
			% [am.cooldown_total(), cd_rank1])
