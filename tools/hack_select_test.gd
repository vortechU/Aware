extends Node
## Headless test for the hack selector + targeting highlight + RoomBuilder seeding,
## Pass 4 (HACK_SELECT_OK). Run: godot --headless --path . res://tools/hack_select_test.tscn
##
## The wheel's LOOK needs a real renderer (eyeballed in play); this asserts the selection
## STATE MACHINE the wheel draws from, the glitch_smoke way.
##   - SEEDING: a built room contains at least one grouped `hackable` prop.
##   - FLICK MATH: a mouse-flick maps to the right wedge (and a tiny flick to none).
##   - HIGHLIGHT: aiming at a hackable glows it; aiming away clears it.
##   - SELECTOR: holding `hack` opens the wheel with the unlocked set + locks the aimed
##     target; cycling moves the selection; releasing injects the PICKED adjective into the
##     LOCKED target (even after aiming away).

var fails: Array[String] = []
var _applied: Array = []


func _ready() -> void:
	GameEvents.trait_applied.connect(func(adj: String, _r: int): _applied.append(adj))
	await _run()
	if Input.is_action_pressed("hack"):
		Input.action_release("hack")
	if fails.is_empty():
		print("HACK_SELECT_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HACK_SELECT_FAIL: ", f)
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


func _make_hackable(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.freeze = true
	rb.mass = 8.0
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
	await _part_seeding()
	await _part_selector()


# ---------------------------------------------------------------- seeding

func _part_seeding() -> void:
	RunManager.selected_mode = RunManager.RunMode.ENDLESS  # legacy build, no profile
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 1 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	var builder: Node = main.get_node("RoomBuilder")
	await builder.build_room(2)
	var hackables := get_tree().get_nodes_in_group("hackable").size()
	_check(hackables >= 1, "a built room should seed at least one hackable prop (got %d)" % hackables)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# ---------------------------------------------------------------- flick + selector

func _part_selector() -> void:
	add_child(_make_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0)))
	var player: Player = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.add_to_group("player")
	add_child(player)
	var hm: HackManager = player.get_node("HackManager")
	hm.select_time_scale = 1.0  # don't slow the harness with the bullet-time dip
	await get_tree().physics_frame

	# ---- FLICK MATH (pure): up -> wedge 0, down -> wedge 1, tiny -> none ----
	hm._ordered_ids = ["heavy", "shocking"]
	_check(hm._index_for_flick(Vector2(0, -100)) == 0, "flick up should pick wedge 0")
	_check(hm._index_for_flick(Vector2(0, 100)) == 1, "flick down should pick wedge 1")
	_check(hm._index_for_flick(Vector2(3, -3)) == -1, "a sub-deadzone flick should pick nothing")

	# ---- world: a hackable cube dead-centre in the camera ray ----
	var cam: Camera3D = player.camera
	var forward: Vector3 = -cam.global_transform.basis.z
	var cube_pos: Vector3 = cam.global_position + forward * 5.0
	var cube := _make_hackable(cube_pos)
	var cube_h: Hackable = cube.get_meta("hackable")
	hm.unlock("heavy")
	hm.unlock("shocking")
	await get_tree().physics_frame

	# ---- HIGHLIGHT follows the crosshair ----
	await get_tree().physics_frame
	_check(cube_h.highlighted, "aiming at a hackable should highlight it")
	player.rotation.y = PI
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not cube_h.highlighted, "aiming away should clear the highlight")
	player.rotation.y = 0.0
	await get_tree().physics_frame

	# ---- OPEN on hold: wheel up, unlocked set present, target locked ----
	Input.action_press("hack")
	var opened := false
	for _i in 6:
		await get_tree().physics_frame
		if hm.is_selecting():
			opened = true
			break
	_check(opened, "holding hack should open the selector")
	_check(hm.ordered_ids().size() == 2, "both unlocked adjectives should be on the wheel")
	_check(hm.locked_target() == cube_h, "opening should lock the aimed target")

	# ---- PICK shocking, then aim away to prove the pick targets the LOCKED cube ----
	hm.cycle_selection(1)
	_check(hm.selection_index() == 1, "cycling should move the selection")
	player.rotation.y = PI  # the locked target must still receive the injection
	await get_tree().physics_frame

	# ---- RELEASE injects the PICKED adjective into the LOCKED target ----
	Input.action_release("hack")
	var closed := false
	for _i in 6:
		await get_tree().physics_frame
		if not hm.is_selecting():
			closed = true
			break
	_check(closed, "releasing hack should close the selector")
	_check(_applied.has("Shocking"), "release should inject the PICKED adjective (Shocking)")
	_check(cube.get_node_or_null("ShockField") != null,
			"the picked Shocking should apply to the LOCKED cube (not the now-aimed nothing)")
	_check(cube.freeze, "Shocking must not have mutated the locked cube")
