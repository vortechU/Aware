extends Node
## Headless test for the hacking RAM meter, Pass 2 (HACK_RAM_OK).
## Run: godot --headless --path . res://tools/hack_ram_test.tscn
##
## Covers the HackManager RAM pool and the RunHUD bar that reads it.
##   - SPEND: injecting a trait costs `ram_cost` up front and emits ram_changed.
##   - DRAIN + COLLAPSE: with regen throttled below upkeep, a live trait bleeds RAM down;
##     hitting empty force-expires the OLDEST trait (its host reverts).
##   - REGEN: with no traits live, RAM climbs back toward max.
##   - REFUSE: a hack with insufficient RAM fails and creates no trait.
##   - HUD: the RunHUD RAM bar tracks ram_changed and reveals on the first hack (the
##     ability_hud way -- the driver asserts the signal-fed state; the look is eyeballed).

const RUN_HUD := preload("res://scenes/ui/run_hud.tscn")

var fails: Array[String] = []
var _last_ram := -1.0
var _last_ram_max := -1.0


func _ready() -> void:
	GameEvents.ram_changed.connect(func(cur: float, mx: float):
		_last_ram = cur
		_last_ram_max = mx)
	await _run()
	if fails.is_empty():
		print("HACK_RAM_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HACK_RAM_FAIL: ", f)
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


func _run() -> void:
	add_child(_make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0)))
	var player: Player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.add_to_group("player")
	add_child(player)
	var hm: HackManager = player.get_node("HackManager")
	await get_tree().physics_frame

	var cam: Camera3D = player.camera
	var forward: Vector3 = -cam.global_transform.basis.z
	var cube_pos: Vector3 = cam.global_position + forward * 5.0
	var cube := _make_hackable(cube_pos, 8.0)
	var cube_h: Hackable = cube.get_meta("hackable")
	_dummy(Vector3(cube_pos.x, 0.1, cube_pos.z))
	await get_tree().physics_frame

	hm.unlock("heavy")
	var cost: float = float(HackManager.CATALOG["heavy"]["ram_cost"])
	var full: float = hm.ram_max

	# ---- SPEND: a hack costs ram_cost up front + emits ram_changed ----
	_check(is_equal_approx(hm.ram, full), "RAM should start full (%.1f / %.1f)" % [hm.ram, full])
	_check(hm.try_hack("heavy"), "hacking the aimed cube should succeed")
	_check(is_equal_approx(hm.ram, full - cost),
			"a hack should spend ram_cost (%.1f, expected %.1f)" % [hm.ram, full - cost])
	_check(is_equal_approx(_last_ram, hm.ram), "the spend should emit ram_changed")
	_check(is_equal_approx(_last_ram_max, full), "ram_changed should carry ram_max")
	_check(hm.active_count() == 1, "the hack should register one live trait")

	# ---- DRAIN + COLLAPSE: throttle regen below upkeep -> RAM bleeds to empty and the
	# oldest trait force-expires. Pin the trait's own timer high so this is RAM, not decay.
	hm._active[0].time_left = 999.0
	hm.ram_regen = 0.0
	hm.ram = 12.0
	var before := hm.ram
	for _i in 6:
		await get_tree().physics_frame
	_check(hm.ram < before, "a live trait should bleed RAM via upkeep (%.1f -> %.1f)" % [before, hm.ram])
	var collapsed := false
	for _i in 240:
		await get_tree().physics_frame
		if hm.active_count() == 0:
			collapsed = true
			break
	_check(collapsed, "running out of RAM should collapse the oldest trait")
	_check(cube.freeze, "the collapsed trait's host should revert (re-frozen)")
	_check(cube_h.active_trait == null, "the collapsed host's active_trait should clear")

	# ---- REGEN: with nothing live, RAM climbs back toward max ----
	hm.ram_regen = 18.0
	hm.ram = 10.0
	var low := hm.ram
	for _i in 12:
		await get_tree().physics_frame
	_check(hm.ram > low, "RAM should regenerate while idle (%.1f -> %.1f)" % [low, hm.ram])

	# ---- REFUSE: a hack with too little RAM fails and makes no trait ----
	hm.ram = 1.0
	await get_tree().physics_frame
	_check(hm.current_target() == cube_h, "the reverted cube should be aimable again")
	_check(not hm.try_hack("heavy"), "a hack with insufficient RAM should fail")
	_check(hm.active_count() == 0, "a refused hack must not create a trait")

	# ---- HUD: the RunHUD bar tracks ram_changed and reveals on the first hack ----
	# Freeze the live HackManager first, else its per-frame ram_changed emits overwrite
	# the manual ones below (ram_changed is a global GameEvents signal).
	hm.set_physics_process(false)
	var hud := RUN_HUD.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var meter := hud.get_node("RamMeter") as Control
	var bar := hud.get_node("RamMeter/Bar") as ProgressBar
	_check(not meter.visible, "the RAM meter should start hidden")
	GameEvents.ram_changed.emit(50.0, 100.0)
	await get_tree().process_frame
	_check(is_equal_approx(bar.value, 50.0) and is_equal_approx(bar.max_value, 100.0),
			"the bar should track ram_changed (%.1f / %.1f)" % [bar.value, bar.max_value])
	_check(not meter.visible, "ram_changed alone must not reveal the meter")
	GameEvents.trait_applied.emit("Heavy", 1)
	await get_tree().process_frame
	_check(meter.visible, "the first hack should reveal the RAM meter")


func _dummy(pos: Vector3) -> Node3D:
	var enemy := (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Node3D
	add_child(enemy)  # add BEFORE disabling, else _ready re-enables physics (nav errors)
	enemy.global_position = pos
	enemy.set("sight_range", 0.0)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy
