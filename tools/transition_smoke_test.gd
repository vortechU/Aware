extends Node
## Headless test for full scene transitions, which the other harnesses skip
## (they instance scenes as children instead of swapping current_scene).
## This node lives under root and survives scene changes, so it can drive:
##   menu -> PLAY -> lobby -> START RUN -> main -> death -> Try Again (reload)
##   -> Main Menu (change).
## Any runtime error in those swaps prints to stderr; a clean pass + the
## TRANSITION_OK marker means the transition paths are error-free.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("TRANSITION_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("TRANSITION_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _load_scene(path: String) -> Node:
	var packed := load(path) as PackedScene
	var inst := packed.instantiate()
	# Defer so we never add during a node's _ready ("parent busy" error), then
	# adopt it as current_scene so change_scene/reload target it (not this node).
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	get_tree().current_scene = inst
	return inst


func _await_enemies(count: int, max_frames := 1800) -> bool:
	var tries := 0
	while tries < max_frames:
		if get_tree().get_nodes_in_group("enemies").size() >= count:
			return true
		tries += 1
		await get_tree().process_frame
	return false


func _run() -> void:
	await get_tree().process_frame  # let the SceneTree finish adopting this node

	# 1. Main menu loads and PLAY swaps to the lobby.
	var menu: Node = await _load_scene("res://scenes/ui/main_menu.tscn")
	await get_tree().process_frame
	_check(menu.get_node("MenuRoot/Center/Buttons/PlayBtn") != null, "menu missing Play button")
	menu.call("_on_play_pressed")  # change_scene_to_file(lobby)
	# change_scene is deferred; wait for the new current_scene.
	var tries := 0
	while (get_tree().current_scene == menu or get_tree().current_scene == null) and tries < 120:
		tries += 1
		await get_tree().process_frame
	var lobby := get_tree().current_scene
	_check(lobby != null and lobby.name == "Lobby", "PLAY did not load the Lobby scene")
	if lobby == null or lobby.name != "Lobby":
		return

	# 2. START RUN swaps from the lobby to the game scene.
	lobby.call("start_run")  # arms meta bonuses + change_scene_to_file(main)
	tries = 0
	while (get_tree().current_scene == lobby or get_tree().current_scene == null) and tries < 120:
		tries += 1
		await get_tree().process_frame
	var main := get_tree().current_scene
	_check(main != null and main.name == "Main", "START RUN did not load the Main scene")
	if main == null or main.name != "Main":
		return

	# 3. Game runs cleanly: enemies spawn, run is active.
	_check(await _await_enemies(5), "enemies never spawned after PLAY")
	_check(RunManager.run_active, "run not active after PLAY")
	var player := get_tree().get_first_node_in_group("player")
	_check(player != null, "player missing after PLAY")
	if player == null:
		return

	# 4. Death -> end screen, then Try Again reloads the scene.
	player.call("take_damage", 1000000.0, Vector3.ZERO)
	await get_tree().create_timer(0.3).timeout
	var run_hud: Node = main.get_node("RunHUD")
	_check(run_hud.get_node("RunEndPanel").visible, "end screen not shown on death")
	run_hud.call("_on_try_again_pressed")  # reload_current_scene()
	tries = 0
	while tries < 120:  # wait for the reloaded instance (fresh, run active again)
		if get_tree().current_scene != null and get_tree().current_scene != main \
				and RunManager.run_active:
			break
		tries += 1
		await get_tree().process_frame
	var main2 := get_tree().current_scene
	_check(main2 != null and main2 != main, "Try Again did not reload the scene")
	_check(not get_tree().paused, "tree left paused after Try Again")
	_check(RunManager.run_active and RunManager.current_room == 1,
			"run did not restart fresh after Try Again (room %d, active %s)"
			% [RunManager.current_room, RunManager.run_active])
	_check(await _await_enemies(5), "enemies never spawned after Try Again")
	if main2 == null:
		return

	# 5. Die again, then Main Menu changes back to the menu scene.
	var player2 := get_tree().get_first_node_in_group("player")
	player2.call("take_damage", 1000000.0, Vector3.ZERO)
	await get_tree().create_timer(0.3).timeout
	var run_hud2: Node = main2.get_node("RunHUD")
	run_hud2.call("_on_quit_pressed")  # change_scene_to_file(main_menu)
	tries = 0
	while (get_tree().current_scene == main2 or get_tree().current_scene == null) and tries < 120:
		tries += 1
		await get_tree().process_frame
	var menu2 := get_tree().current_scene
	_check(menu2 != null and menu2.get_node_or_null("MenuRoot") != null,
			"Main Menu button did not return to the menu")
	_check(not get_tree().paused, "tree left paused after returning to menu")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"mouse not released on the menu")
