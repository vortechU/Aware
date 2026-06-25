extends Node
## Headless test for the advanced movement features (wall-run + dash + vault +
## momentum + double jump).
## Run: godot --headless --path . res://tools/movement_smoke_test.tscn
## Builds a tiny world (floor + one wall) and drives the real player.tscn.
## Wall-run: sticks to a wall and runs along it under reduced gravity, a jump
## launches off (away + up) and exits, and the cooldown blocks re-running the
## same wall. Dash: a charged burst consumes a charge and overrides speed on the
## ground and in the air (preserving vertical momentum), charges exhaust and then
## recharge over time. Vault: jumping into a low crate mantles over it to the far
## side, while a tall wall is correctly rejected. Momentum: running smoothly
## builds the momentum scalar and lifts top speed above base walk, and it decays
## once the player stops. Uses Input.action_press to inject real input. No
## persistence touched, nothing to restore.

var fails: Array[String] = []


func _ready() -> void:
	await _run()
	# Leave no input pressed behind.
	for a in ["move_forward", "jump"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	for a in ["dash"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if fails.is_empty():
		print("MOVEMENT_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("MOVEMENT_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _make_static_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # "world" — player collision_mask (5) includes it
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	return body


func _hspeed(player: Node) -> float:
	var v: Vector3 = player.velocity
	return Vector2(v.x, v.z).length()


## Press dash for a few frames; returns true if a charge was actually spent.
func _do_dash(player: Player) -> bool:
	var before: int = player._dash_charges
	Input.action_press("dash")
	var fired := false
	for _i in 3:
		await get_tree().physics_frame
		if player._dash_charges < before:
			fired = true
			break
	Input.action_release("dash")
	return fired


func _run() -> void:
	# ---- world: floor (top at y=0) + a wall whose face sits at x=1.5 ----
	var world := Node3D.new()
	add_child(world)
	world.add_child(_make_static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0)))
	world.add_child(_make_static_box(Vector3(1, 6, 20), Vector3(2, 3, 0)))

	var player: Player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	world.add_child(player)
	await get_tree().physics_frame
	var dt := 1.0 / float(Engine.physics_ticks_per_second)

	# ---- 1. enter wall-run: flush against the wall, airborne, moving along -z ----
	# Player capsule radius 0.4, so centre x=1.1 -> right edge touches the wall face.
	player.global_position = Vector3(1.1, 1.5, 0.0)
	player.velocity = Vector3(2.0, 2.0, -7.0)  # into wall (+x), up, along the wall (-z)
	Input.action_press("move_forward")         # wish_dir = forward (-z), along the wall
	var entered := false
	for _i in 10:
		await get_tree().physics_frame
		if player.move_state == Player.MoveState.WALLRUN:
			entered = true
			break
	_check(entered, "player did not enter WALLRUN against the wall")
	if not entered:
		return
	_check(_hspeed(player) >= player.wallrun_min_speed,
			"wall-run did not maintain speed (%.2f)" % _hspeed(player))

	# ---- 2. reduced gravity: y-velocity should decay far slower than full gravity ----
	var vy0: float = player.velocity.y
	var still := true
	for _i in 6:
		await get_tree().physics_frame
		if player.move_state != Player.MoveState.WALLRUN:
			still = false
			break
	_check(still, "fell out of WALLRUN during the gravity check")
	var implied_accel := (vy0 - player.velocity.y) / (6.0 * dt)
	var full_g := absf(player.get_gravity().y)
	_check(implied_accel > 0.2 and implied_accel < full_g * 0.5,
			"wall-run gravity not reduced (implied %.2f vs full %.2f)" % [implied_accel, full_g])

	# ---- 3. wall-jump: launches away from the wall + upward, and exits WALLRUN ----
	var wall_normal: Vector3 = player._wall_normal  # points away from the wall (~ -x)
	Input.action_press("jump")
	var jumped := false
	var post_vel := Vector3.ZERO
	for _i in 4:
		await get_tree().physics_frame
		if player.move_state != Player.MoveState.WALLRUN:
			jumped = true
			post_vel = player.velocity
			break
	Input.action_release("jump")
	_check(jumped, "jump did not exit WALLRUN")
	_check(post_vel.dot(wall_normal) > 0.0,
			"wall-jump did not push away from the wall (dot %.2f)" % post_vel.dot(wall_normal))
	_check(post_vel.y > 0.0, "wall-jump had no upward launch (vy %.2f)" % post_vel.y)

	# ---- 4. cooldown blocks immediately re-running the same wall ----
	player.global_position = Vector3(1.1, 1.5, 0.0)
	player.velocity = Vector3(2.0, 2.0, -7.0)
	await get_tree().physics_frame
	_check(player.move_state != Player.MoveState.WALLRUN,
			"cooldown did not block immediate re-entry on the same wall")

	# ---- 5. dash: ground burst, charge consumption, and exhaustion ----
	# Away from the wall, fresh charges, settle on the floor.
	Input.action_release("move_forward")
	player.global_position = Vector3(-5.0, 0.2, 0.0)
	player.velocity = Vector3.ZERO
	player.move_state = Player.MoveState.WALK
	player._dash_charges = player.dash_max_charges
	player._dash_time_left = 0.0
	player._dash_recharge_timer = 0.0
	for _i in 24:
		await get_tree().physics_frame
	_check(player.is_on_floor(), "player did not settle on the floor before dashing")

	Input.action_press("move_forward")  # dash direction = forward (-z)
	var d1 := await _do_dash(player)
	_check(d1, "ground dash did not fire")
	_check(player._dash_charges == player.dash_max_charges - 1,
			"ground dash did not consume exactly one charge (%d)" % player._dash_charges)
	_check(absf(_hspeed(player) - player.dash_speed) < 2.5,
			"ground dash did not boost to ~dash_speed (%.2f)" % _hspeed(player))

	# wait out the dash window, then dash again to exhaust the last charge
	for _i in 14:
		await get_tree().physics_frame
		if player._dash_time_left <= 0.0:
			break
	player.global_position = Vector3(-5.0, 1.0, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 4:
		await get_tree().physics_frame
	var d2 := await _do_dash(player)
	_check(d2 and player._dash_charges == 0,
			"second dash did not exhaust charges (%d)" % player._dash_charges)

	# with no charges, dash is blocked
	for _i in 14:
		await get_tree().physics_frame
		if player._dash_time_left <= 0.0:
			break
	var d3 := await _do_dash(player)
	_check(not d3 and player._dash_charges == 0,
			"dash fired with no charges (%d)" % player._dash_charges)

	# ---- 6. dash recharges over time ----
	player.dash_recharge_time = 0.1  # crank down for a fast, deterministic refill
	player._dash_recharge_timer = 0.0
	var refilled := false
	for _i in 20:
		await get_tree().physics_frame
		if player._dash_charges >= 1:
			refilled = true
			break
	_check(refilled, "dash did not recharge over time")

	# ---- 7. air-dash: horizontal burst that preserves vertical momentum ----
	player._dash_charges = player.dash_max_charges
	player._dash_time_left = 0.0
	player._dash_recharge_timer = 0.0
	player.global_position = Vector3(-5.0, 4.0, 0.0)
	player.velocity = Vector3(0.0, -1.0, 0.0)
	await get_tree().physics_frame
	_check(not player.is_on_floor(), "air-dash setup: player should be airborne")
	var vy_before: float = player.velocity.y
	var da := await _do_dash(player)
	_check(da, "air dash did not fire")
	_check(not player.is_on_floor(), "player should still be airborne mid air-dash")
	_check(absf(_hspeed(player) - player.dash_speed) < 2.5,
			"air-dash did not boost horizontal speed (%.2f)" % _hspeed(player))
	_check(player.velocity.y < vy_before + 0.05,
			"air-dash should keep falling, not zero/launch vertical (%.2f -> %.2f)"
			% [vy_before, player.velocity.y])

	# ---- 8. vault: mantle over a low crate, but not over a tall wall ----
	# A 1.4 m crate (like the authored/procedural ones) at the origin; the player
	# stands just in front of it (+z) facing -z toward it.
	for a in ["dash", "jump", "move_forward"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	world.add_child(_make_static_box(Vector3(2.4, 1.4, 1.1), Vector3(0.0, 0.7, 0.0)))
	player.global_position = Vector3(0.0, 0.1, 1.5)
	player.velocity = Vector3.ZERO
	player.move_state = Player.MoveState.WALK
	player._dash_time_left = 0.0
	for _i in 20:
		await get_tree().physics_frame
	_check(player.is_on_floor(), "player did not settle in front of the crate")

	# Jump into the crate -> should vault, not hop.
	Input.action_press("jump")
	var vaulting := false
	for _i in 6:
		await get_tree().physics_frame
		if player.move_state == Player.MoveState.VAULT:
			vaulting = true
			break
	_check(vaulting, "jump into a low crate did not start a vault")
	# Let the mantle complete.
	var vault_done := false
	for _i in 40:
		await get_tree().physics_frame
		if player.move_state != Player.MoveState.VAULT:
			vault_done = true
			break
	Input.action_release("jump")
	_check(vault_done, "vault did not finish")
	_check(player.global_position.z < -0.55,
			"vault did not carry the player past the crate (z=%.2f)" % player.global_position.z)

	# A 3 m wall must NOT be vaultable (high ray blocks it).
	world.add_child(_make_static_box(Vector3(2.0, 3.0, 1.0), Vector3(8.0, 1.5, 0.0)))
	player.global_position = Vector3(8.0, 0.1, 1.5)
	player.velocity = Vector3.ZERO
	player.move_state = Player.MoveState.WALK
	for _i in 20:
		await get_tree().physics_frame
	Input.action_press("jump")
	var tall_vault := false
	for _i in 6:
		await get_tree().physics_frame
		if player.move_state == Player.MoveState.VAULT:
			tall_vault = true
			break
	Input.action_release("jump")
	_check(not tall_vault, "player incorrectly vaulted a 3 m wall")

	# ---- 9. momentum: smooth running builds speed (capped), decays when stopped --
	# A clear lane at x=-8 (away from the wall, crate and tall box).
	for a in ["dash", "jump", "move_forward"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	player.global_position = Vector3(-8.0, 0.2, 9.0)
	player.velocity = Vector3.ZERO
	player.move_state = Player.MoveState.WALK
	player.momentum = 0.0
	for _i in 24:
		await get_tree().physics_frame
	_check(player.is_on_floor(), "player did not settle for the momentum test")

	# Run forward smoothly for ~1.5 s -> momentum builds, top speed rises past walk.
	Input.action_press("move_forward")
	for _i in 90:
		await get_tree().physics_frame
	_check(player.momentum > 0.3,
			"smooth running did not build momentum (%.2f)" % player.momentum)
	_check(player.momentum <= 1.0, "momentum exceeded its cap (%.2f)" % player.momentum)
	_check(_hspeed(player) > player.walk_speed * 1.1,
			"momentum did not raise speed above base walk (%.2f vs %.2f)"
			% [_hspeed(player), player.walk_speed])
	var peak_momentum: float = player.momentum

	# Stop -> the flow breaks and momentum decays back down.
	Input.action_release("move_forward")
	for _i in 90:
		await get_tree().physics_frame
	_check(player.momentum < peak_momentum * 0.5,
			"momentum did not decay after stopping (%.2f from peak %.2f)"
			% [player.momentum, peak_momentum])

	# ---- 10. double jump: an air jump pops the player up, capped by charges -----
	for a in ["dash", "jump", "move_forward"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	# Drop into open air, falling, with exactly one air jump available.
	player.global_position = Vector3(-8.0, 6.0, 9.0)
	player.velocity = Vector3(0.0, -2.0, 0.0)
	player.move_state = Player.MoveState.WALK
	player.max_air_jumps = 1
	player._air_jumps_left = 1
	await get_tree().physics_frame
	_check(not player.is_on_floor(), "double-jump setup: player should be airborne")

	# Jump in the air -> consumes the charge and launches the player upward.
	Input.action_press("jump")
	var air_jumped := false
	for _i in 4:
		await get_tree().physics_frame
		if player._air_jumps_left == 0:
			air_jumped = true
			break
	Input.action_release("jump")
	_check(air_jumped, "air jump did not consume a charge")
	_check(player.velocity.y > 2.0,
			"air jump did not launch the player upward (vy %.2f)" % player.velocity.y)

	# A second in-air jump with no charges left must do nothing.
	for _i in 2:
		await get_tree().physics_frame
	var vy_pre: float = player.velocity.y
	Input.action_press("jump")
	for _i in 4:
		await get_tree().physics_frame
	Input.action_release("jump")
	_check(player._air_jumps_left == 0 and player.velocity.y <= vy_pre + 0.05,
			"exhausted air jump still launched the player (vy %.2f -> %.2f)"
			% [vy_pre, player.velocity.y])

	# Landing refills the air jumps.
	player.global_position = Vector3(-8.0, 0.2, 9.0)
	player.velocity = Vector3.ZERO
	for _i in 24:
		await get_tree().physics_frame
	_check(player.is_on_floor(), "player did not settle to refill air jumps")
	_check(player._air_jumps_left == player.max_air_jumps,
			"landing did not refill air jumps (%d/%d)"
			% [player._air_jumps_left, player.max_air_jumps])
