extends Node
## Headless test for the environment-hacking system, Pass 1 (HACK_SMOKE_OK).
## Run: godot --headless --path . res://tools/hack_smoke_test.tscn
##
## Covers the HackManager (child of the real player.tscn), the Hackable component, the
## TraitInstance snapshot/restore, and the first adjective, Heavy.
##   - PURE: the catalog has "heavy"; a TraitInstance apply -> expire round-trips the
##     host body's mass / freeze / collision layer (no permanent mutation).
##   - TARGETING: a camera ray finds the aimed Hackable; aiming at nothing returns null
##     and a hack with no target is a no-op.
##   - CAST: aiming at a floating hackable cube and injecting Heavy releases it under
##     gravity; it falls and crushes the enemy beneath it (via BodyHitbox.take_hit) while
##     a control enemy off to the side is untouched.
##   - DECAY: the trait auto-decays and the cube reverts to its snapshot (re-frozen, mass
##     and layer restored, host's active_trait cleared).
## No navmesh needed; no persistence touched.

var fails: Array[String] = []
var _applied: Array = []
var _expired: Array = []


func _ready() -> void:
	GameEvents.trait_applied.connect(func(adj: String, _r: int): _applied.append(adj))
	GameEvents.trait_expired.connect(func(adj: String): _expired.append(adj))
	await _run()
	if fails.is_empty():
		print("HACK_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("HACK_SMOKE_FAIL: ", f)
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


## A hackable prop: a RigidBody3D on the world layer that starts frozen (so it reads as a
## floating/static prop) with a Hackable child. mask = world only, so when Heavy releases
## it the falling mass passes THROUGH enemies (layer "enemy") -- the crush is proximity,
## not physics contact, which keeps the test deterministic.
func _make_hackable(pos: Vector3, mass := 8.0) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.freeze = true
	rb.mass = mass
	rb.gravity_scale = 1.0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	col.shape = shape
	rb.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mesh.mesh = bm
	rb.add_child(mesh)
	var h := Hackable.new()
	h.name = "Hackable"
	rb.add_child(h)
	# Set the spawn transform BEFORE entering the tree: a frozen RigidBody3D ignores a
	# global_position written after add_child (it stays at the physics-server origin).
	rb.position = pos
	add_child(rb)
	return rb


## A real enemy, made inert (sight_range 0 + process off) so it stays where placed.
## take_hit still routes damage into its HealthComponent regardless of process state.
func _make_enemy(pos: Vector3) -> Node3D:
	var enemy := (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Node3D
	add_child(enemy)
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

	# ---- PURE: catalog + TraitInstance snapshot/restore round-trip ----
	_check(HackManager.CATALOG.has("heavy"), "catalog should contain 'heavy'")

	var probe := _make_hackable(Vector3(-30, 1, -30), 7.0)  # off in a corner, out of the way
	var probe_h: Hackable = probe.get_meta("hackable")
	await get_tree().physics_frame
	var ti := TraitInstance.new()
	ti.apply(probe_h, "heavy", 1, HackManager.CATALOG["heavy"])
	_check(probe.mass == float(HackManager.CATALOG["heavy"]["mass"]),
			"apply should set the heavy mass (got %.1f)" % probe.mass)
	_check(not probe.freeze, "apply should release (unfreeze) the prop")
	ti.expire()
	_check(probe.mass == 7.0, "expire should restore the original mass (got %.1f)" % probe.mass)
	_check(probe.freeze, "expire should re-freeze the prop")
	_check(probe.collision_layer == 1, "expire should restore the collision layer")
	probe.queue_free()

	# ---- aim: place a hackable cube in front of the camera, an enemy beneath it ----
	var cam: Camera3D = player.camera
	var forward: Vector3 = -cam.global_transform.basis.z
	var cube_pos: Vector3 = cam.global_position + forward * 5.0
	var cube := _make_hackable(cube_pos, 8.0)
	var cube_h: Hackable = cube.get_meta("hackable")
	var under := _make_enemy(Vector3(cube_pos.x, 0.1, cube_pos.z))
	var control := _make_enemy(Vector3(cube_pos.x + 20.0, 0.1, cube_pos.z))
	var under_hp := under.get_node("Health") as HealthComponent
	var control_hp := control.get_node("Health") as HealthComponent
	var under_full: float = under_hp.health
	var control_full: float = control_hp.health
	await get_tree().physics_frame

	# ---- unlock + targeting ----
	_check(hm.unlock("heavy"), "unlock('heavy') should succeed")
	_check(not hm.unlock("definitely_not_an_adjective"), "unlock should reject a non-catalog id")
	_check(hm.current_target() == cube_h, "aiming at the cube should target its Hackable")

	# ---- no target: aim away -> null, hack is a no-op ----
	player.rotation.y = PI  # face the opposite direction (nothing there)
	await get_tree().physics_frame
	_check(hm.current_target() == null, "aiming at nothing should return no target")
	_check(not hm.try_hack("heavy"), "a hack with no target should fail")
	_check(hm.active_count() == 0, "a failed hack must not create a trait")
	player.rotation.y = 0.0
	await get_tree().physics_frame

	# ---- cast: inject Heavy into the aimed cube ----
	_check(hm.try_hack("heavy"), "hacking the aimed cube should succeed")
	_check(_applied.has("Heavy"), "a successful hack should emit trait_applied('Heavy')")
	_check(not cube.freeze, "Heavy should release the cube under gravity")
	_check(hm.active_count() == 1, "the hack should register one live trait")
	_check(cube_h.active_trait != null, "the host should hold its active trait")

	# ---- the cube falls and crushes the enemy beneath it ----
	var crushed := false
	for _i in 90:
		await get_tree().physics_frame
		if under_hp.health < under_full:
			crushed = true
			break
	_check(crushed, "the falling Heavy cube should crush the enemy beneath it (%.1f / %.1f)"
			% [under_hp.health, under_full])
	_check(control_hp.health == control_full,
			"the off-to-the-side enemy must be untouched (%.1f / %.1f)"
			% [control_hp.health, control_full])

	# ---- decay: crank the timer down -> the trait expires and the cube reverts ----
	hm._active[0].time_left = 0.02
	var reverted := false
	for _i in 20:
		await get_tree().physics_frame
		if hm.active_count() == 0:
			reverted = true
			break
	_check(reverted, "the trait should decay to expiry")
	_check(_expired.has("Heavy"), "expiry should emit trait_expired('Heavy')")
	_check(cube.freeze, "on expiry the cube should be re-frozen")
	_check(cube.mass == 8.0, "on expiry the cube mass should be restored (got %.1f)" % cube.mass)
	_check(cube_h.active_trait == null, "on expiry the host's active_trait should be cleared")
