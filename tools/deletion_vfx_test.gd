extends Node3D
## Headless test for the death "deletion" VFX (DELETION_VFX_OK).
## Run: godot --headless --path . res://tools/deletion_vfx_test.tscn
##
## DeletionVFX (autoload) replaces the death ragdoll's VISUAL with a glitch-dissolve
## "deletion" -- WITHOUT touching enemy_ai.gd. On enemy_died it freezes the corpse
## pieces (cancelling the launch impulse -> vanish in place), swaps their meshes to
## the dissolve ShaderMaterial, then tweens the dissolve up and frees them. Shaders
## don't compile headless, so the LOOK is eyeballed via tools/deletion_preview.tscn;
## this asserts the state machine (frozen, dissolving, freed), the glitch_smoke way.

const ENEMY := preload("res://scenes/enemies/enemy.tscn")

var fails: Array[String] = []


func _ready() -> void:
	_pure()
	await _scene()
	if fails.is_empty():
		print("DELETION_VFX_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("DELETION_VFX_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _pure() -> void:
	_check(DeletionVFX != null, "DeletionVFX autoload should exist")
	_check(DeletionVFX.DISSOLVE_SHADER != null, "the dissolve shader should load")
	_check(DeletionVFX.enabled, "DeletionVFX should be enabled by default (on in real play)")


func _scene() -> void:
	# Floor so the enemy settles, then a real kill through the damage path.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	fs.shape = box
	fs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fs)
	add_child(floor_body)

	var enemy: Node3D = ENEMY.instantiate()
	add_child(enemy)                      # node_added -> CharacterApplicator rigs it, DeletionVFX hooks enemy_died
	enemy.global_position = Vector3(0, 0.1, 0)
	for _i in 6:
		await get_tree().physics_frame

	# Kill it: _die spawns the corpse + emits enemy_died synchronously, so DeletionVFX
	# has already frozen + swapped materials by the time take_hit returns.
	enemy.get_node("BodyHitbox").call("take_hit", 99999.0, Vector3(0, 1, 10))

	var corpse := _body_corpse()
	_check(corpse != null, "a death should spawn a body corpse")
	if corpse == null:
		return

	# 1. Frozen -> the launch impulse is cancelled (vanish in place, no tumble).
	_check(corpse is RigidBody3D and (corpse as RigidBody3D).freeze,
			"the corpse should be frozen by DeletionVFX (no ragdoll launch)")

	# 2. Its visible meshes wear the deletion-dissolve ShaderMaterial, starting at 0.
	var mat := _dissolve_mat(corpse)
	_check(mat != null, "the corpse meshes should be swapped to the dissolve shader")
	if mat != null:
		_check(mat.shader == DeletionVFX.DISSOLVE_SHADER, "the swapped material should use the dissolve shader")
		_check(float(mat.get_shader_parameter("dissolve")) <= 0.01, "the dissolve should start at 0")

	# 3. Frozen => no horizontal flight (the original ragdoll would fly here).
	var start: Vector3 = (corpse as Node3D).global_position
	for _i in 18:
		await get_tree().physics_frame
	if is_instance_valid(corpse):
		var moved: float = (corpse as Node3D).global_position.distance_to(start)
		_check(moved < 0.1, "a frozen corpse should not be launched (moved %.2f m)" % moved)

	# 4. The dissolve advances over time.
	if mat != null and is_instance_valid(mat):
		_check(float(mat.get_shader_parameter("dissolve")) > 0.05,
				"the dissolve should advance after a moment, got %.2f" % float(mat.get_shader_parameter("dissolve")))

	# 5. ...and the pieces delete themselves once it completes.
	await get_tree().create_timer(DeletionVFX.DISSOLVE_TIME + 0.5).timeout
	_check(get_tree().get_nodes_in_group("enemy_corpse").is_empty(),
			"the deleted corpse pieces should free themselves")


func _body_corpse() -> Node:
	for c in get_tree().get_nodes_in_group("enemy_corpse"):
		if (c as Node).get_node_or_null("Visual") != null:
			return c
	return null


## The dissolve ShaderMaterial on the first visible mesh under the corpse that carries one.
func _dissolve_mat(root: Node) -> ShaderMaterial:
	if root is MeshInstance3D and (root as MeshInstance3D).material_override is ShaderMaterial:
		var sm := (root as MeshInstance3D).material_override as ShaderMaterial
		if sm.shader == DeletionVFX.DISSOLVE_SHADER:
			return sm
	for c in root.get_children():
		var r := _dissolve_mat(c)
		if r != null:
			return r
	return null
