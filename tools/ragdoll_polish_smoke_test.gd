extends Node
## Headless test for the death-ragdoll polish (RAGDOLL_POLISH_OK).
## Run: godot --headless --path . res://tools/ragdoll_polish_smoke_test.tscn
##
## Pass 1 -- per-shot impulse direction: a fatal shot records its travel direction
## + contact point (HitboxComponent.register_hit, before damage) and the corpse is
## launched along that direction. The player sits to the -Z (so the old "away from
## shooter" launch would fly +Z), but we fire a shot traveling +X -- the corpse
## must follow the SHOT (+X).
## Pass 2 -- headshot pop-off: a HEAD hit detaches the head as its own rigid body
## that pops upward, leaving the body corpse headless.
## (Corpse clearing on transition is covered by run_smoke_test.)

var fails: Array[String] = []


func _ready() -> void:
	# Exercises the ragdoll PHYSICS substrate (per-shot launch dir, head-pop, gun-drop),
	# so turn off the deletion-VFX layer that would freeze + dissolve the corpse.
	DeletionVFX.enabled = false

	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	floor.add_child(cs)
	add_child(floor)
	floor.global_position = Vector3(0, -0.5, 0)  # top at y=0

	if get_tree().current_scene == null:
		get_tree().current_scene = self

	var dummy := (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	dummy.add_to_group("player")
	add_child(dummy)
	dummy.set_physics_process(false)
	dummy.set_process(false)
	dummy.set_process_unhandled_input(false)
	dummy.global_position = Vector3(0, 0.5, -5)

	var enemy_a: Node3D = _spawn_enemy(Vector3(0, 0.1, 0))
	var enemy_b: Node3D = _spawn_enemy(Vector3(6, 0.1, 0))
	for i in 15:  # settle on the floor
		await get_tree().physics_frame

	# --- Pass 1 (+ Pass 3): body shot traveling +X; the gun also drops. ---
	var before := _corpse_ids()
	enemy_a.get_node("BodyHitbox").call("take_hit", 99999.0, dummy.global_position,
			enemy_a.global_position + Vector3(0, 0.9, 0), Vector3(1, 0, 0))
	await get_tree().physics_frame
	var a_new := _new_corpses(before)
	_check(a_new.size() == 2, "a kill should spawn a body corpse + a dropped gun, got %d" % a_new.size())
	var corpse_a := _with_child(a_new, "Visual")
	var gun_a := _with_child(a_new, "Gun")
	_check(corpse_a != null, "kill should leave a body corpse")
	_check(gun_a != null, "kill should drop the gun as a separate piece")
	if corpse_a != null:
		_check(corpse_a.get_node_or_null("Visual/Gun") == null, "the gun should detach from the body")
		var start := corpse_a.global_position
		for i in 24:
			await get_tree().physics_frame
		var moved := corpse_a.global_position - start
		_check(moved.x > 0.8, "corpse should fly along the bullet (+X), moved x=%.2f" % moved.x)
		_check(moved.x > absf(moved.z),
				"corpse should follow the shot (+X), not 'away from shooter' (+Z): dx=%.2f dz=%.2f"
				% [moved.x, moved.z])

	# --- Pass 2: headshot pops the head off (plus the dropped gun). ---
	before = _corpse_ids()
	enemy_b.get_node("HeadHitbox").call("take_hit", 99999.0, dummy.global_position,
			enemy_b.global_position + Vector3(0, 1.62, 0), Vector3(-1, 0, 0))
	await get_tree().physics_frame
	var b_new := _new_corpses(before)
	_check(b_new.size() == 3, "a headshot should spawn body + gun + head, got %d" % b_new.size())
	var body := _with_child(b_new, "Visual")
	var head := _with_child(b_new, "Head")
	var gun := _with_child(b_new, "Gun")
	_check(body != null, "headshot should leave a body corpse")
	_check(head != null, "headshot should spawn a detached head rigid body")
	_check(gun != null, "headshot should also drop the gun")
	if body != null:
		_check(body.get_node_or_null("Visual/Head") == null,
				"the body corpse should be headless after a head pop")
		_check(body.get_node_or_null("Visual/Gun") == null, "the body corpse should be disarmed")
	if head != null:
		var hstart := head.global_position
		for i in 8:
			await get_tree().physics_frame
		_check(head.global_position.y > hstart.y + 0.2,
				"the popped head should pop upward, rose %.2f" % (head.global_position.y - hstart.y))

	_finish()


func _spawn_enemy(pos: Vector3) -> Node3D:
	var enemy: Node3D = (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	add_child(enemy)
	enemy.global_position = pos
	return enemy


func _corpse_ids() -> Dictionary:
	var ids := {}
	for c in get_tree().get_nodes_in_group("enemy_corpse"):
		ids[c.get_instance_id()] = true
	return ids


func _new_corpses(before: Dictionary) -> Array:
	var out := []
	for c in get_tree().get_nodes_in_group("enemy_corpse"):
		if not before.has(c.get_instance_id()):
			out.append(c)
	return out


## First corpse in the list with a direct child of the given name.
func _with_child(arr: Array, child_name: String) -> Node3D:
	for c in arr:
		if (c as Node).get_node_or_null(child_name) != null:
			return c as Node3D
	return null


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _finish() -> void:
	if fails.is_empty():
		print("RAGDOLL_POLISH_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("RAGDOLL_POLISH_FAIL: ", f)
		get_tree().quit(1)
