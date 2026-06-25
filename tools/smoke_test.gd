extends Node
## Headless integration smoke test for the whole game loop.
## Run: godot --headless --path . res://tools/smoke_test.tscn
## Instances the real main scene, blinds the AI for determinism, then checks
## spawning, patrol movement, armor math, pickups, headshot kills and the win.

var fails: Array[String] = []
var room_cleared := false


func _ready() -> void:
	# The roguelite run system replaced the one-shot win: clearing the squad
	# now fires RunManager.room_cleared instead of GameEvents.game_won.
	RunManager.room_cleared.connect(func() -> void: room_cleared = true)
	var main_scene: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_scene)
	await _run()
	if fails.is_empty():
		print("SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	# 1. Enemies spawn after the navmesh bake.
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check(enemies.size() == 5, "expected 5 enemies, got %d" % enemies.size())
	if enemies.size() < 5:
		return

	# Blind the AI so damage numbers below stay deterministic.
	for e in enemies:
		e.set("sight_range", 0.0)

	var player := get_tree().get_first_node_in_group("player")
	_check(player != null, "player missing from group")
	if player == null:
		return

	# 2. Patrol: someone should wander within a few seconds.
	var before: Array[Vector3] = []
	for e in enemies:
		before.append((e as Node3D).global_position)
	await get_tree().create_timer(4.0).timeout
	var moved := false
	for i in enemies.size():
		if is_instance_valid(enemies[i]) \
				and (enemies[i] as Node3D).global_position.distance_to(before[i]) > 0.5:
			moved = true
	_check(moved, "no enemy moved while patrolling")

	# 3. Armor math: 20 damage with armor -> 6 absorbed, health 100 -> 86.
	player.call("take_damage", 20.0, Vector3.ZERO)
	var hp := float(player.get("health"))
	var armor := float(player.get("armor"))
	_check(absf(hp - 86.0) < 0.01, "health after absorb should be 86, got %s" % hp)
	_check(absf(armor - 19.0) < 0.01, "armor after absorb should be 19, got %s" % armor)

	# 4. Health pickup heals on contact.
	(player as Node3D).global_position = Vector3(16, 0.1, 16)
	await get_tree().create_timer(1.0).timeout
	var hp2 := float(player.get("health"))
	_check(hp2 > hp, "health pickup did not heal (was %s, now %s)" % [hp, hp2])

	# 5. Enemy fire: give one enemy its eyes back and stand in front of it;
	# a gunshot sound pulls it toward the player if it happens to face away.
	var shooter := enemies[2] as Node3D
	shooter.set("sight_range", 28.0)
	# Fixed open-ground duel spot south of center: nothing between them.
	shooter.global_position = Vector3(0, 0.1, 15)
	(player as Node3D).global_position = Vector3(0, 0.1, 12)
	GameEvents.sound_emitted.emit((player as Node3D).global_position, 60.0)
	var hp_before_fire := float(player.get("health"))
	await get_tree().create_timer(8.0).timeout
	var hp_after_fire := float(player.get("health"))
	_check(hp_after_fire < hp_before_fire,
			"enemy never damaged the player (hp %s -> %s)" % [hp_before_fire, hp_after_fire])
	shooter.set("sight_range", 0.0)

	# 6. Headshot kill: 60 base * 2.0 multiplier kills a 100 hp enemy.
	var victim := enemies[0] as Node
	victim.get_node("HeadHitbox").call("take_hit", 60.0, Vector3.ZERO)
	await get_tree().process_frame
	_check(int(victim.get("state")) == 7, "headshot did not put enemy in DEAD state")

	# 7. Wipe the squad -> the run system reports the room as cleared.
	for i in range(1, enemies.size()):
		(enemies[i] as Node).get_node("BodyHitbox").call("take_hit", 1000.0, Vector3.ZERO)
	await get_tree().create_timer(1.0).timeout
	_check(room_cleared, "room_cleared was not emitted after killing all enemies")
	get_tree().paused = false  # the room transition pauses the tree; undo for quit
