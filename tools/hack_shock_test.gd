extends Node
## Headless test for the Shocking adjective, Pass 3 (HACK_SHOCK_OK).
## Run: godot --headless --path . res://tools/hack_shock_test.tscn
##
## Shocking is the "attach-effect-node" archetype: instead of mutating the host body (the
## way Heavy does), it attaches a ShockField child that pulses damage to nearby enemies,
## proving the catalog handles non-mutating traits.
##   - INJECT: hacking the aimed panel with Shocking attaches a ShockField to it and does
##     NOT mutate the host (it stays frozen + in place -- a shocked wall is still a wall).
##   - ZAP: the field damages only the enemy inside its radius over time; one well outside
##     is untouched.
##   - EXPIRE: the trait decays -> the ShockField is removed and the host is unchanged.

var fails: Array[String] = []
var _applied: Array = []
var _expired: Array = []


func _ready() -> void:
	GameEvents.trait_applied.connect(func(adj: String, _r: int): _applied.append(adj))
	GameEvents.trait_expired.connect(func(adj: String): _expired.append(adj))
	await _run()
	if fails.is_empty():
		print("HACK_SHOCK_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HACK_SHOCK_FAIL: ", f)
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


func _make_hackable(pos: Vector3, mass := 8.0) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.freeze = true
	rb.mass = mass
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	col.shape = shape
	rb.add_child(col)
	var h := Hackable.new()
	h.name = "Hackable"
	rb.add_child(h)
	rb.position = pos  # set BEFORE add_child (frozen-rigidbody gotcha)
	add_child(rb)
	return rb


func _dummy(pos: Vector3) -> Node3D:
	var enemy := (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Node3D
	add_child(enemy)  # add BEFORE disabling, else _ready re-enables physics (nav errors)
	enemy.global_position = pos
	enemy.set("sight_range", 0.0)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy


func _run() -> void:
	add_child(_make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0)))
	var player: Player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.add_to_group("player")
	add_child(player)
	var hm: HackManager = player.get_node("HackManager")
	await get_tree().physics_frame

	var cam: Camera3D = player.camera
	var forward: Vector3 = -cam.global_transform.basis.z
	var panel_pos: Vector3 = cam.global_position + forward * 5.0
	var panel := _make_hackable(panel_pos, 8.0)
	var panel_h: Hackable = panel.get_meta("hackable")
	var panel_origin := panel.global_position

	var near := _dummy(Vector3(panel_pos.x + 1.5, 0.1, panel_pos.z))   # within shock radius (4)
	var far := _dummy(Vector3(panel_pos.x + 12.0, 0.1, panel_pos.z))   # well outside
	var near_hp := near.get_node("Health") as HealthComponent
	var far_hp := far.get_node("Health") as HealthComponent
	var near_full: float = near_hp.health
	var far_full: float = far_hp.health
	await get_tree().physics_frame

	# ---- INJECT: Shocking attaches a ShockField, does not mutate the host ----
	hm.unlock("shocking")
	_check(hm.current_target() == panel_h, "aiming at the panel should target its Hackable")
	_check(hm.try_hack("shocking"), "hacking the aimed panel with Shocking should succeed")
	_check(_applied.has("Shocking"), "a successful hack should emit trait_applied('Shocking')")
	_check(hm.active_count() == 1, "the hack should register one live trait")
	_check(panel.get_node_or_null("ShockField") != null,
			"Shocking should attach a ShockField effect node to the host")
	_check(panel.freeze, "Shocking must NOT mutate the host body (it stays frozen)")

	# ---- ZAP: only the in-radius enemy takes damage, over time ----
	var zapped := false
	for _i in 90:
		await get_tree().physics_frame
		if near_hp.health < near_full:
			zapped = true
			break
	_check(zapped, "the ShockField should damage the in-radius enemy (%.1f / %.1f)"
			% [near_hp.health, near_full])
	# Let a couple more pulses land, then confirm the far enemy is still untouched.
	for _i in 40:
		await get_tree().physics_frame
	_check(far_hp.health == far_full,
			"the out-of-radius enemy must be untouched (%.1f / %.1f)" % [far_hp.health, far_full])
	_check(panel.global_position.distance_to(panel_origin) < 0.05,
			"the shocked panel must not have moved")

	# ---- EXPIRE: the trait decays -> ShockField removed, host unchanged ----
	hm._active[0].time_left = 0.02
	var reverted := false
	for _i in 30:
		await get_tree().physics_frame
		if hm.active_count() == 0:
			reverted = true
			break
	await get_tree().physics_frame  # let the queued ShockField free
	_check(reverted, "the trait should decay to expiry")
	_check(_expired.has("Shocking"), "expiry should emit trait_expired('Shocking')")
	_check(panel.get_node_or_null("ShockField") == null,
			"expiry should remove the ShockField effect node")
	_check(panel_h.active_trait == null, "on expiry the host's active_trait should be cleared")
	_check(panel.freeze, "the host should remain its original frozen self after expiry")
