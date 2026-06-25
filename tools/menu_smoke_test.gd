extends Node
## Headless test for the main menu + settings system.
## Run: godot --headless --path . res://tools/menu_smoke_test.tscn
## Verifies menu structure, settings application (render scale, sensitivity,
## FOV onto a live player), key rebinding + reset, and persistence wiring.
## Snapshots and restores the real user://settings.cfg values so test runs
## never pollute the player's actual settings.

var fails: Array[String] = []


func _ready() -> void:
	await _run()
	if fails.is_empty():
		print("MENU_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("MENU_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	# Snapshot user settings so this test leaves no trace.
	var orig_scale: float = SettingsManager.render_scale
	var orig_sens: float = SettingsManager.mouse_sensitivity
	var orig_fov: float = SettingsManager.fov
	var orig_binds := {}
	for action in SettingsManager.REBINDABLE_ACTIONS:
		orig_binds[action] = InputMap.action_get_events(action)

	# 1. Menu structure: buttons exist and are wired; settings starts hidden.
	var menu: Control = (preload("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var play: Button = menu.get_node("MenuRoot/Center/Buttons/PlayBtn")
	var settings: Button = menu.get_node("MenuRoot/Center/Buttons/SettingsBtn")
	var quit: Button = menu.get_node("MenuRoot/Center/Buttons/QuitBtn")
	var panel: Control = menu.get_node("SettingsPanel")
	_check(play.pressed.get_connections().size() > 0, "Play button not wired")
	_check(settings.pressed.get_connections().size() > 0, "Settings button not wired")
	_check(quit.pressed.get_connections().size() > 0, "Quit button not wired")
	_check(not panel.visible, "settings panel should start hidden")
	settings.pressed.emit()
	_check(panel.visible, "settings panel did not open")
	var bind_list: Node = menu.get_node("SettingsPanel/Margin/VBox/Tabs/Controls/BindScroll/BindList")
	_check(bind_list.get_child_count() == 16,
			"expected 16 rebind rows, got %d" % bind_list.get_child_count())

	# 2. Graphics: render scale applies to the root viewport.
	SettingsManager.set_render_scale(0.8)
	_check(absf(get_tree().root.scaling_3d_scale - 0.8) < 0.001,
			"render scale not applied to root viewport")

	# 3. Controls: rebind jump to T, then reset back to Space.
	var key_t := InputEventKey.new()
	key_t.physical_keycode = KEY_T
	SettingsManager.rebind_action("jump", key_t)
	var events := InputMap.action_get_events("jump")
	_check(events.size() == 1
			and (events[0] as InputEventKey).physical_keycode == KEY_T,
			"jump rebind to T failed")
	SettingsManager.reset_controls()
	events = InputMap.action_get_events("jump")
	_check(not events.is_empty()
			and (events[0] as InputEventKey).physical_keycode == KEY_SPACE,
			"reset did not restore jump to Space")

	# 4. Mouse + FOV: applied onto a player that spawns afterwards.
	SettingsManager.set_mouse_sensitivity(2.0)
	SettingsManager.set_fov(90.0)
	var player: Node = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame  # deferred apply runs after enter-tree
	var sens: float = player.get("mouse_sensitivity")
	_check(absf(sens - 0.0044) < 0.00001,
			"sensitivity multiplier not applied to player (got %s)" % sens)
	_check(absf(float(player.get("base_fov")) - 90.0) < 0.01,
			"FOV not applied to player")
	# Changing the setting mid-game reaches the live player too.
	SettingsManager.set_mouse_sensitivity(1.5)
	_check(absf(float(player.get("mouse_sensitivity")) - 0.0033) < 0.00001,
			"live sensitivity change did not reach the player")

	# 5. Restore the user's real settings.
	SettingsManager.set_render_scale(orig_scale)
	SettingsManager.set_mouse_sensitivity(orig_sens)
	SettingsManager.set_fov(orig_fov)
	for action in orig_binds:
		InputMap.action_erase_events(action)
		for event in orig_binds[action]:
			InputMap.action_add_event(action, event)
	SettingsManager.call("_save")
