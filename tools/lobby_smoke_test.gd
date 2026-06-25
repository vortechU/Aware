extends Node
## Headless test for the 3D lobby hub + MetaProgression layer.
## Run: godot --headless --path . res://tools/lobby_smoke_test.tscn
## Verifies the lobby's 3D structure (player + Area3D pedestals + portal/door),
## real Area3D proximity detection moving the player onto a pedestal, a buy
## persisting to user://meta_progress.cfg, armed run-start bonuses landing on a
## fresh Player's exported vars (while unarmed players stay vanilla), and the
## permadeath Cores payout through RunManager.run_ended (10 per cleared room,
## +50 per cleared milestone room). Snapshots and restores the real
## user://meta_progress.cfg values so test runs never pollute progression.

var fails: Array[String] = []


func _ready() -> void:
	await _run()
	if fails.is_empty():
		print("LOBBY_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("LOBBY_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	# Snapshot meta progression so this test leaves no trace.
	var orig_cores: int = MetaProgression.cores
	var orig_levels: Dictionary = MetaProgression.upgrade_levels.duplicate()

	# 1. Lobby structure: 3D world with the player, one Area3D per meta upgrade,
	#    plus the start portal and menu door, and the HUD labels.
	MetaProgression.cores = 0
	for id in MetaProgression.upgrade_levels:
		MetaProgression.upgrade_levels[id] = 0
	var lobby: Node3D = (preload("res://scenes/ui/lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	await get_tree().process_frame
	var lobby_player: Node = lobby.get_node("Player")
	var stations: Node = lobby.get_node("Stations")
	_check(lobby_player != null and lobby_player.is_in_group("player"),
			"lobby has no first-person player")
	for def in MetaProgression.META_UPGRADES:
		var node := stations.get_node_or_null(String(def.id)) as Area3D
		_check(node != null, "missing pedestal for upgrade '%s'" % def.id)
	_check(stations.get_node_or_null("StartPortal") is Area3D, "missing StartPortal")
	_check(stations.get_node_or_null("MenuDoor") is Area3D, "missing MenuDoor")
	var cores_label: Label = lobby.get_node("LobbyHUD/CoresLabel")
	var prompt: Label = lobby.get_node("LobbyHUD/Prompt")
	_check(cores_label.text == "CORES: 0", "cores label wrong: '%s'" % cores_label.text)
	_check(not prompt.visible, "prompt should be hidden away from any station")

	# 2. Real proximity: walking the player onto the starting_hp pedestal makes
	#    it the active station and shows the prompt (Area3D detects the player's
	#    physics layer on the next physics ticks).
	var hp_station: Area3D = stations.get_node("starting_hp")
	lobby_player.global_position = hp_station.global_position + Vector3(0, 0.2, 0)
	for _i in 8:
		await get_tree().physics_frame
	_check(lobby.call("_current_station") == hp_station,
			"Area3D proximity did not register the player on the pedestal")
	_check(prompt.visible, "prompt not shown while standing on a pedestal")

	# 3. Purchase via the worldspace interact, while standing on the pedestal.
	MetaProgression.cores = MetaProgression.next_cost("starting_hp")
	lobby.call("_refresh_all")
	lobby.call("_interact")  # nearest station == starting_hp -> buy
	_check(MetaProgression.level_of("starting_hp") == 1, "interact did not buy the upgrade")
	_check(MetaProgression.cores == 0, "purchase did not spend the cores")
	var hp_label: Label3D = hp_station.get_node("Label3D")
	_check("Lv 1 / 5" in hp_label.text, "pedestal label did not update (got '%s')" % hp_label.text)

	# 4. Persistence: the purchase reached user://meta_progress.cfg.
	var config := ConfigFile.new()
	_check(config.load(MetaProgression.SAVE_PATH) == OK, "meta_progress.cfg not written")
	_check(int(config.get_value("upgrades", "starting_hp", 0)) == 1,
			"starting_hp level not persisted")
	_check(int(config.get_value("meta", "cores", -1)) == 0, "cores not persisted")

	# 5. Run-start bonuses: vanilla player while unarmed, boosted once armed.
	MetaProgression.upgrade_levels["starting_hp"] = 2
	MetaProgression.upgrade_levels["starting_armor"] = 1
	MetaProgression.upgrade_levels["move_speed"] = 1
	MetaProgression.upgrade_levels["reload_speed"] = 1
	MetaProgression.upgrade_levels["ammo_capacity"] = 1

	var base_player: Node = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(base_player)
	await get_tree().process_frame
	await get_tree().process_frame  # deferred applies settle
	var base_hp: float = base_player.get("max_health")
	var base_armor: float = base_player.get("armor")
	var base_walk: float = base_player.get("walk_speed")
	var base_wm: WeaponManager = base_player.get_node("Head/Bob/Recoil/Camera/WeaponManager")
	var base_reload: float = base_wm.weapon_datas[0].reload_time
	var base_mag: int = base_wm.weapon_datas[0].mag_size
	base_player.queue_free()
	await get_tree().process_frame

	MetaProgression.arm_run_bonuses()
	var run_player: Node = (preload("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(run_player)
	await get_tree().process_frame
	await get_tree().process_frame  # MetaProgression's deferred apply runs here
	_check(absf(float(run_player.get("max_health")) - (base_hp + 20.0)) < 0.001,
			"starting_hp bonus not applied (got %s)" % run_player.get("max_health"))
	_check(absf(float(run_player.get("health")) - (base_hp + 20.0)) < 0.001,
			"player did not spawn at full bonus health")
	_check(absf(float(run_player.get("armor")) - (base_armor + 10.0)) < 0.001,
			"starting_armor bonus not applied (got %s)" % run_player.get("armor"))
	_check(absf(float(run_player.get("walk_speed")) - base_walk * 1.03) < 0.001,
			"move_speed bonus not applied (got %s)" % run_player.get("walk_speed"))
	var run_wm: WeaponManager = run_player.get_node("Head/Bob/Recoil/Camera/WeaponManager")
	_check(absf(run_wm.weapon_datas[0].reload_time - base_reload / 1.06) < 0.001,
			"reload_speed bonus not applied (got %s)" % run_wm.weapon_datas[0].reload_time)
	var expected_mag := roundi(float(base_mag) * 1.1)
	_check(run_wm.weapon_datas[0].mag_size == expected_mag,
			"ammo_capacity bonus not applied (got %d)" % run_wm.weapon_datas[0].mag_size)
	var loaded: Array = run_wm.get("_mag")
	_check(int(loaded[0]) == expected_mag,
			"bigger magazine not loaded at spawn (got %s)" % str(loaded[0]))
	# The shared .tres in the resource cache must stay at base values.
	var cached := load("res://data/weapons/pistol.tres") as WeaponData
	_check(cached.mag_size == base_mag, "meta bonus leaked into the cached .tres")
	run_player.queue_free()
	await get_tree().process_frame

	# 6. Permadeath payout: died in room 7 -> 6 cleared with milestone room 5
	#    inside -> 10*6 + 50 = 110. Death in room 1 and a won run pay nothing.
	MetaProgression.cores = 0
	RunManager.start_run()
	RunManager.current_room = 7
	GameEvents.player_died.emit()  # RunManager flips run_active, emits run_ended(false)
	_check(MetaProgression.cores == 110,
			"expected 110 cores for 6 cleared rooms, got %d" % MetaProgression.cores)
	_check(cores_label.text == "CORES: 110", "lobby label did not refresh on payout")
	config = ConfigFile.new()
	_check(config.load(MetaProgression.SAVE_PATH) == OK
			and int(config.get_value("meta", "cores", -1)) == 110, "payout not persisted")
	RunManager.start_run()
	GameEvents.player_died.emit()  # died in room 1: nothing cleared
	_check(MetaProgression.cores == 110, "death in room 1 must award nothing")
	RunManager.run_ended.emit(true)  # a won run pays nothing either
	_check(MetaProgression.cores == 110, "won run must award nothing")

	# 7. Restore the real progression.
	MetaProgression.cores = orig_cores
	MetaProgression.upgrade_levels = orig_levels
	MetaProgression.run_bonuses_armed = false
	MetaProgression.call("_save")
