extends Node3D
## Headless test for the enemy death ragdoll.
## Run: godot --headless --path . res://tools/ragdoll_smoke_test.tscn
## Spawns an enemy over a floor, kills it through its hitbox, and asserts the
## death hands the visual meshes to a physics corpse (group "enemy_corpse",
## a RigidBody3D) that the enemy husk no longer owns, that the corpse is knocked
## into motion by the impulse, and that it eventually frees itself.

const ENEMY := preload("res://scenes/enemies/enemy.tscn")

var fails: Array[String] = []


func _ready() -> void:
	await _run()
	if fails.is_empty():
		print("RAGDOLL_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("RAGDOLL_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	# A static floor on the world layer so the corpse has something to land on.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	var enemy: Node3D = ENEMY.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	# Let _ready run (health.died wired) and the body settle on the floor.
	for i in 4:
		await get_tree().physics_frame

	_check(enemy.get_node_or_null("Visual") != null, "enemy should start with a Visual")

	# Kill it through the body hitbox (the real damage path).
	enemy.get_node("BodyHitbox").call("take_hit", 99999.0, Vector3(0, 1, 10))

	# The corpse(s) are created synchronously inside _die: a body corpse plus the
	# dropped gun (the gun always detaches into its own piece now).
	var corpses := get_tree().get_nodes_in_group("enemy_corpse")
	_check(corpses.size() == 2, "death should spawn a body corpse + a dropped gun, got %d" % corpses.size())
	var corpse: Node = null
	for c in corpses:
		if (c as Node).get_node_or_null("Visual") != null:
			corpse = c
	_check(corpse != null, "a body corpse owning the Visual should spawn")
	if corpse == null:
		return
	_check(corpse is RigidBody3D, "corpse should be a RigidBody3D")
	_check(corpse.get_node_or_null("Visual") != null, "corpse should own the Visual meshes")
	_check(enemy.get_node_or_null("Visual") == null,
			"the enemy husk should no longer own the Visual after death")
	_check(int(enemy.get("state")) == 7, "enemy should be in the DEAD state")

	# The impulse applies on the next physics step; the corpse should move.
	var start: Vector3 = (corpse as Node3D).global_position
	var start_basis: Basis = (corpse as Node3D).global_transform.basis
	for i in 18:
		await get_tree().physics_frame
	if not is_instance_valid(corpse):
		fails.append("corpse freed too early")
		return
	var moved: float = (corpse as Node3D).global_position.distance_to(start)
	var spun := not (corpse as Node3D).global_transform.basis.is_equal_approx(start_basis)
	_check(moved > 0.5, "corpse should be launched into motion (moved %.2f m)" % moved)
	_check(spun, "corpse should tumble (rotation unchanged)")

	# It cleans itself up after settling + shrinking out.
	await get_tree().create_timer(EnemyAI.CORPSE_SETTLE + EnemyAI.CORPSE_FADE + 1.0).timeout
	_check(get_tree().get_nodes_in_group("enemy_corpse").is_empty(),
			"corpse should free itself after settling")
