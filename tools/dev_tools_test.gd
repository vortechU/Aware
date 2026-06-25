extends Node
## Developer-tools test: god mode + kill-all + refill.
## Run: godot --headless --path . res://tools/dev_tools_test.tscn
##
## Drives DevTools' actions directly (no key input) against a live main.tscn:
##   - god mode raises the player's maxima so a lethal-sized hit does NOT kill, and
##     toggling it off restores the authored maxima;
##   - kill-all routes lethal hits through the BodyHitbox so every enemy dies (the
##     normal death path, which the room-clear flow keys off);
##   - refill tops health/armor back to full after damage.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("DEV_TOOLS_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("DEV_TOOLS_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _alive_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if int(e.get("state")) != 7:  # EnemyAI.State.DEAD
			n += 1
	return n


func _run() -> void:
	var dev: Node = get_node_or_null("/root/DevTools")
	_check(dev != null, "DevTools autoload not registered")
	if dev == null:
		return
	dev.enabled = true  # OS.is_debug_build() is true headless, but be explicit

	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	_check(player != null, "no player in the scene")
	if player == null:
		return

	var orig_max: float = float(player.get("max_health"))

	# --- God mode: a lethal-sized hit must not kill ------------------------------
	dev._toggle_god()
	_check(dev.god_mode, "god mode did not turn on")
	_check(float(player.get("max_health")) > 1.0e6, "god mode did not raise max health")
	player.call("take_damage", 5.0e5, Vector3.ZERO)  # would obliterate a 100-hp player
	_check(not bool(player.get("is_dead")), "player died in god mode")
	_check(float(player.get("health")) > 1.0e6, "god-mode health was not absorbed")

	# Toggling off restores the authored maxima.
	dev._toggle_god()
	_check(not dev.god_mode, "god mode did not turn off")
	_check(is_equal_approx(float(player.get("max_health")), orig_max),
			"max health not restored after god mode off (%.1f vs %.1f)"
			% [float(player.get("max_health")), orig_max])
	_check(float(player.get("health")) <= orig_max + 0.01, "health not clamped after god off")

	# --- Refill: damage then top back up -----------------------------------------
	player.set("health", 10.0)
	player.set("armor", 0.0)
	dev._refill()
	_check(is_equal_approx(float(player.get("health")), orig_max),
			"refill did not restore full health")
	_check(float(player.get("armor")) > 0.0, "refill did not restore armor")

	# --- Kill all enemies --------------------------------------------------------
	_check(_alive_enemies() >= 1, "no live enemies to kill")
	var killed: int = dev._kill_all_enemies()
	_check(killed >= 1, "kill-all reported zero kills")
	for _i in 8:
		await get_tree().process_frame
	_check(_alive_enemies() == 0, "enemies still alive after kill-all (%d left)" % _alive_enemies())

	# --- Room / layer jump -------------------------------------------------------
	_check(dev._layer_start_rooms() == [1, 7], "layer start rooms should be [1, 7] (Heap, Stack)")
	var director: Node = main.get_node_or_null("RunDirector")
	_check(director != null and director.has_method("dev_jump_to_room"),
			"RunDirector has no dev_jump_to_room")
	if director != null and director.has_method("dev_jump_to_room"):
		await director.dev_jump_to_room(8)  # warp deep, rebuilding via the real pipeline
		_check(RunManager.current_room == 8,
				"jump did not land on room 8 (got %d)" % RunManager.current_room)
		_check(RunManager.run_active, "run should still be active after a jump")
		_check(not get_tree().paused, "tree should be unpaused after the jump completes")
		_check(_alive_enemies() >= 1, "the jumped-to combat room spawned no squad")
