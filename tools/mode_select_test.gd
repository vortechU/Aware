extends Node
## Headless test for Pass 5b of the layered world: the lobby run-mode selector.
## Run: godot --headless --path . res://tools/mode_select_test.tscn
##
## Verifies the code-built ModeToggle station: it exists with a label, the lobby
## defaults the selection to CAMPAIGN, _ready does NOT mutate RunManager.selected_mode
## (so the endless-default harnesses stay correct), and interacting with the station
## flips the selected mode live (CAMPAIGN <-> ENDLESS) with the label tracking it.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("MODE_SELECT_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("MODE_SELECT_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	var snap_mode: int = RunManager.selected_mode
	# Force a known mode, then prove the lobby's _ready leaves it untouched.
	RunManager.selected_mode = RunManager.RunMode.ENDLESS

	var lobby: Node3D = (preload("res://scenes/ui/lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	await get_tree().process_frame

	_check(RunManager.selected_mode == RunManager.RunMode.ENDLESS,
			"lobby _ready must not change RunManager.selected_mode (endless harnesses rely on it)")
	_check(lobby.get("_selected_mode") == RunManager.RunMode.CAMPAIGN,
			"the lobby should default the run selection to CAMPAIGN")

	var stations: Node = lobby.get_node("Stations")
	var toggle := stations.get_node_or_null("ModeToggle") as Area3D
	_check(toggle != null, "the ModeToggle station was not built")
	if toggle == null:
		RunManager.selected_mode = snap_mode
		return
	var label := toggle.get_node_or_null("Label3D") as Label3D
	_check(label != null, "the ModeToggle station has no Label3D")

	# Real proximity: walk the player onto the toggle so it becomes the active station.
	var player: Node3D = lobby.get_node("Player")
	player.global_position = toggle.global_position + Vector3(0, 0.2, 0)
	for _i in 8:
		await get_tree().physics_frame
	_check(lobby.call("_current_station") == toggle,
			"Area3D proximity did not register the player on the ModeToggle")
	var prompt: Label = lobby.get_node("LobbyHUD/Prompt")
	_check(prompt.visible, "prompt not shown while standing on the ModeToggle")

	# Interact -> flips to ENDLESS, live on RunManager, label tracks it.
	lobby.call("_interact")
	_check(lobby.get("_selected_mode") == RunManager.RunMode.ENDLESS,
			"interacting should switch the selection to ENDLESS")
	_check(RunManager.selected_mode == RunManager.RunMode.ENDLESS,
			"the toggle should push the mode live to RunManager")
	_check(label != null and "ENDLESS" in label.text,
			"the toggle label should read ENDLESS, got '%s'" % (label.text if label else "<none>"))

	# Interact again -> back to CAMPAIGN ("ESCAPE").
	lobby.call("_interact")
	_check(lobby.get("_selected_mode") == RunManager.RunMode.CAMPAIGN,
			"interacting again should switch back to CAMPAIGN")
	_check(RunManager.selected_mode == RunManager.RunMode.CAMPAIGN,
			"the toggle should push CAMPAIGN live to RunManager")
	_check(label != null and "ESCAPE" in label.text,
			"the toggle label should read ESCAPE for campaign, got '%s'" % (label.text if label else "<none>"))

	RunManager.selected_mode = snap_mode  # leave the autoload as we found it
