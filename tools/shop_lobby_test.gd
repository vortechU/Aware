extends Node
## Headless test for shop Pass 2: the cosmetic economy in MetaProgression, the
## ShopController bridge, and the lobby ShopTerminal station.
## Run: godot --headless --path . res://tools/shop_lobby_test.tscn
##
## Snapshots + restores the real user://meta_progress.cfg cores/cosmetics so test
## purchases never pollute progression (the lobby_smoke_test convention).
##   - MetaProgression.buy_cosmetic spends + persists, denies re-buy / unaffordable.
##   - ShopController.open syncs the terminal FROM the save (cores + owned), and a
##     purchase through the terminal commits back TO the save + reconciles display.
##   - the lobby builds a ShopTerminal station; standing on it + interacting opens
##     the shop and freezes the player; closing unfreezes.

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("SHOP_LOBBY_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("SHOP_LOBBY_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _find(id: String) -> Dictionary:
	for it: Dictionary in ShopCatalog.items():
		if String(it.get("id", "")) == id:
			return it
	return {}


func _run() -> void:
	var orig_cores: int = MetaProgression.cores
	var orig_cos: Dictionary = MetaProgression.owned_cosmetics.duplicate()
	var orig_equip: Dictionary = MetaProgression.equipped_cosmetics.duplicate()

	# 1. MetaProgression cosmetic economy + persistence.
	MetaProgression.cores = 5000
	MetaProgression.owned_cosmetics.clear()
	_check(not MetaProgression.owns_cosmetic("core_orb"), "core_orb should start unowned")
	_check(MetaProgression.buy_cosmetic("core_orb", 800), "affordable cosmetic buy should succeed")
	_check(MetaProgression.cores == 4200, "buy should spend 800, got %d" % MetaProgression.cores)
	_check(MetaProgression.owns_cosmetic("core_orb"), "core_orb should be owned after buying")
	_check(not MetaProgression.buy_cosmetic("core_orb", 800), "re-buying owned should be denied")
	_check(MetaProgression.cores == 4200, "denied re-buy must not spend")
	_check(not MetaProgression.buy_cosmetic("ram_ring", 99999), "unaffordable buy should be denied")
	_check(MetaProgression.cores == 4200, "denied poor buy must not spend")
	var cfg := ConfigFile.new()
	_check(cfg.load(MetaProgression.SAVE_PATH) == OK, "meta_progress.cfg not written")
	_check(bool(cfg.get_value("cosmetics", "core_orb", false)), "cosmetic purchase not persisted")

	# 2. ShopController bridge: open syncs from the save, a buy commits back.
	var ctrl: ShopController = ShopController.new()
	add_child(ctrl)
	await get_tree().process_frame
	ctrl.open()
	_check(ctrl.is_open, "controller should be open")
	var term := ctrl.terminal()
	_check(term.cores == MetaProgression.cores, "terminal cores should sync from the save (got %d/%d)"
			% [term.cores, MetaProgression.cores])
	_check(term.is_owned("core_orb"), "owned cosmetic should be pre-marked in the terminal")

	var cube := _find("data_cube")  # cost 4200, exactly affordable (cores == 4200)
	var before: int = MetaProgression.cores
	term.attempt_buy(cube)          # terminal gates + mirrors -> controller commits
	await get_tree().process_frame
	_check(MetaProgression.owns_cosmetic("data_cube"), "purchase should persist to MetaProgression")
	_check(MetaProgression.cores == before - 4200, "purchase should spend the real Cores (got %d)"
			% MetaProgression.cores)
	_check(term.cores == MetaProgression.cores, "terminal should reconcile to the save after buy")

	# 2b. Equip commits through the bridge + persists (no Cores cost).
	term.attempt_equip(cube)  # data_cube (Titles), just bought above
	await get_tree().process_frame
	_check(MetaProgression.is_equipped("data_cube"), "equip should persist to MetaProgression")
	_check(MetaProgression.equipped_in("Titles") == "data_cube",
			"equipped slot Titles should hold data_cube")
	var cfg2 := ConfigFile.new()
	cfg2.load(MetaProgression.SAVE_PATH)
	_check(String(cfg2.get_value("equipped", "Titles", "")) == "data_cube",
			"equip not persisted to the [equipped] cfg section")
	ctrl.close()
	_check(not ctrl.is_open, "controller should be closed")
	ctrl.queue_free()
	await get_tree().process_frame

	# 3. Lobby station: present, openable via interact, freezes/unfreezes the player.
	MetaProgression.cores = 2000
	var lobby: Node3D = (preload("res://scenes/ui/lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	await get_tree().process_frame
	var stations: Node = lobby.get_node("Stations")
	var shop_area := stations.get_node_or_null("ShopTerminal") as Area3D
	_check(shop_area != null, "lobby should build a ShopTerminal station")

	var lobby_player: Node = lobby.get_node("Player")
	if shop_area != null:
		lobby_player.global_position = shop_area.global_position + Vector3(0, 0.2, 0)
		for _i in 8:
			await get_tree().physics_frame
		_check(lobby.call("_current_station") == shop_area, "player should register on the shop station")

	lobby.call("_interact")  # nearest station == ShopTerminal -> open
	await get_tree().process_frame
	var lobby_shop: ShopController = lobby.get("_shop")
	_check(lobby_shop != null and lobby_shop.is_open, "interacting should open the lobby shop")
	_check(not lobby_player.is_physics_processing(), "player should be frozen while shopping")
	_check(lobby_shop.terminal().cores == MetaProgression.cores,
			"lobby shop should show the live Cores total")
	if lobby_shop != null:
		lobby_shop.close()
	await get_tree().process_frame
	_check(lobby_player.is_physics_processing(), "player should be unfrozen after closing the shop")

	lobby.queue_free()
	await get_tree().process_frame

	# 4. Restore real progression.
	MetaProgression.cores = orig_cores
	MetaProgression.owned_cosmetics = orig_cos
	MetaProgression.equipped_cosmetics = orig_equip
	MetaProgression.call("_save")
