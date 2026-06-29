extends Node
## Death "deletion" VFX -- in this computer world, a dead enemy is DELETED (glitch-
## dissolved out of existence) rather than physically ragdolling. A sibling observer
## of ToonApplicator / CharacterApplicator: it listens to the tree's node_added and,
## when an EnemyAI enters, connects to its `enemy_died`.
##
## BUILD-ALONGSIDE, ZERO enemy_ai.gd EDITS: enemy_ai's `_die` still spawns the physics
## corpse + drops the gun / pops the head, and emits `enemy_died` RIGHT AFTER (same
## frame, BEFORE the next physics step). We hook that signal and:
##   1. FREEZE the just-spawned corpse pieces -> the queued launch impulse never
##      integrates, so the body stays put ("vanish in place", no tumble).
##   2. Swap their visible meshes to the deletion-dissolve ShaderMaterial (carrying
##      over each enemy's own albedo so it still reads as THAT enemy), spawn a glowing
##      data-bit particle burst, tween `dissolve` 0->1, then free the pieces.
## The ragdoll PHYSICS is left intact as the substrate -- `enabled = false` makes this
## a no-op, so the ragdoll-physics harnesses still test the original launch/gun-drop.
##
## ORDER NOTE: the EnemyRig (if present) also hooks `enemy_died` to pause its anim +
## run the bone "crumple". That's orthogonal to us (it touches poses, we touch
## materials + freeze), so the body slumps a little AS it's deleted -- still in place.

const DISSOLVE_SHADER: Shader = preload("res://shaders/deletion_dissolve.gdshader")
const CORPSE_GROUP := "enemy_corpse"

const DISSOLVE_TIME := 0.55       # how long the wipe takes
const CAPTURE_RADIUS := 2.4       # gather this death's corpse pieces near the body
const EDGE_COLOR := Color(0.35, 1.0, 0.65)   # hot spectral-green "delete" glow

## Off makes the whole system a no-op (the ragdoll behaves exactly as before) -- the
## ragdoll-physics harnesses set this false so they still test the launch/gun-drop.
var enabled := true


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is EnemyAI and node.has_signal("enemy_died"):
		(node as EnemyAI).enemy_died.connect(_on_enemy_died)


func _on_enemy_died(enemy: EnemyAI) -> void:
	if not enabled or enemy == null or not is_instance_valid(enemy):
		return
	# enemy_died fires the same frame _spawn_ragdoll ran, so the corpse pieces exist
	# at the enemy's transform and haven't moved yet -- gather them by proximity.
	var origin := enemy.global_position
	var pieces := _capture_pieces(origin)
	if pieces.is_empty():
		return

	var mats: Array[ShaderMaterial] = []
	for piece in pieces:
		if piece is RigidBody3D:
			(piece as RigidBody3D).freeze = true   # cancels the queued launch impulse
		_dissolve_meshes(piece, mats)
	if mats.is_empty():
		return

	_spawn_burst(pieces[0] as Node3D, origin + Vector3.UP * 0.9)

	# Tween the shared dissolve up, then delete the corpse pieces. Bound to this
	# always-alive autoload; if a room transition clears the corpse group first, the
	# pieces just free early (the set_dissolve guards freed materials).
	var tw := create_tween()
	tw.tween_method(_set_dissolve.bind(mats), 0.0, 1.0, DISSOLVE_TIME)
	tw.tween_callback(_free_pieces.bind(pieces))


## Every enemy_corpse-group body near the death point (the body + dropped gun +
## popped head all spawn at the enemy's transform on the same frame).
func _capture_pieces(origin: Vector3) -> Array:
	var out: Array = []
	for c in get_tree().get_nodes_in_group(CORPSE_GROUP):
		if c is Node3D and (c as Node3D).global_position.distance_to(origin) < CAPTURE_RADIUS:
			out.append(c)
	return out


## Swap each visible mesh under `piece` to a deletion-dissolve material that carries
## over the mesh's current albedo (texture + colour), so the enemy dissolves as
## itself. Collects the materials so one tween drives them all.
func _dissolve_meshes(piece: Node, mats: Array[ShaderMaterial]) -> void:
	for mi in _visible_meshes(piece):
		var sm := ShaderMaterial.new()
		sm.shader = DISSOLVE_SHADER
		var col := Color.WHITE
		var tex: Texture2D = null
		var src: Material = mi.material_override
		if src == null:
			src = mi.get_active_material(0)
		if src is StandardMaterial3D:
			col = (src as StandardMaterial3D).albedo_color
			tex = (src as StandardMaterial3D).albedo_texture
		elif src is ShaderMaterial:
			var a: Variant = (src as ShaderMaterial).get_shader_parameter("albedo")
			if a is Color:
				col = a
			var t: Variant = (src as ShaderMaterial).get_shader_parameter("albedo_texture")
			if t is Texture2D:
				tex = t
		sm.set_shader_parameter("albedo_color", col)
		if tex != null:
			sm.set_shader_parameter("albedo_tex", tex)
		sm.set_shader_parameter("dissolve", 0.0)
		sm.set_shader_parameter("edge_color", EDGE_COLOR)
		mi.material_override = sm
		mats.append(sm)


func _set_dissolve(value: float, mats: Array[ShaderMaterial]) -> void:
	for m in mats:
		if is_instance_valid(m):
			m.set_shader_parameter("dissolve", value)


func _free_pieces(pieces: Array) -> void:
	for p in pieces:
		if is_instance_valid(p):
			(p as Node).queue_free()


## A short, one-shot burst of glowing "data bits" flying off the deleted body.
func _spawn_burst(host: Node3D, world_pos: Vector3) -> void:
	if host == null or not is_instance_valid(host):
		return
	var bits := CPUParticles3D.new()
	bits.emitting = true
	bits.one_shot = true
	bits.amount = 24
	bits.lifetime = 0.5
	bits.explosiveness = 1.0
	bits.local_coords = false
	bits.direction = Vector3.UP
	bits.spread = 70.0
	bits.initial_velocity_min = 2.0
	bits.initial_velocity_max = 5.0
	bits.gravity = Vector3(0, 2.0, 0)   # bits drift UP as they dissipate
	bits.scale_amount_min = 0.04
	bits.scale_amount_max = 0.10
	var bit_mesh := BoxMesh.new()
	bit_mesh.size = Vector3.ONE
	var bit_mat := StandardMaterial3D.new()
	bit_mat.albedo_color = EDGE_COLOR
	bit_mat.emission_enabled = true
	bit_mat.emission = EDGE_COLOR
	bit_mat.emission_energy_multiplier = 4.0
	bit_mesh.material = bit_mat
	bits.mesh = bit_mesh
	# Parent into the world next to the corpse so it sits at the death point, then
	# free it after the burst (one_shot) finishes.
	var parent := host.get_parent()
	if parent == null:
		return
	parent.add_child(bits)
	bits.global_position = world_pos
	var t := bits.create_tween()
	t.tween_interval(bits.lifetime + 0.2)
	t.tween_callback(bits.queue_free)


func _visible_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_visible(n, out)
	return out


func _collect_visible(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).visible:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_visible(c, out)
