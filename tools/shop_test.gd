extends Node
## Headless functional test for the in-world shop (ShopTerminal + ShopTurntable).
## Run: godot --headless --path . res://tools/shop_test.tscn
##
## The holo-panel shader can't be verified headless (no shader compile -- see
## tools/shop_preview.tscn for the look); this asserts the catalog/economy/wiring
## that feeds it, the glitch_smoke way (drive the public API + signals directly).
##   - catalog builds one card per item for ALL, fewer for a category filter.
##   - hovering a card emits item_focused with that item.
##   - an affordable buy spends Cores, marks owned, emits item_purchased once;
##     re-buying it / an unaffordable item is denied with Cores unchanged.
##   - the turntable mounts exactly one display model per show_item.

const TERMINAL := preload("res://scripts/ui/shop_terminal.gd")
const TURNTABLE := preload("res://scripts/world/shop_turntable.gd")

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("SHOP_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("SHOP_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _catalog() -> Array:
	return [
		{"id": "neon_chair", "name": "Neon Throne", "category": "Chairs", "cost": 1200,
			"shape": "chair", "color": Color(0.3, 1.0, 0.6)},
		{"id": "void_chair", "name": "Void Seat", "category": "Chairs", "cost": 9800,
			"shape": "chair", "color": Color(0.6, 0.4, 1.0)},
		{"id": "core_orb", "name": "Core Orb", "category": "Effects", "cost": 800,
			"shape": "sphere", "color": Color(0.3, 0.9, 1.0)},
		{"id": "ram_ring", "name": "Ring of RAM", "category": "Effects", "cost": 15000,
			"shape": "torus", "color": Color(1.0, 0.85, 0.3)},
	]


func _card_for(term: ShopTerminal, id: String) -> ShopItemCard:
	for c in term.visible_cards():
		if String(c.item.get("id", "")) == id:
			return c
	return null


func _run() -> void:
	var term: ShopTerminal = TERMINAL.new()
	add_child(term)  # triggers _ready -> chrome built
	await get_tree().process_frame

	var focused: Array[Dictionary] = []
	var bought: Array[Dictionary] = []
	var denied: Array[Dictionary] = []
	term.item_focused.connect(func(it: Dictionary) -> void: focused.append(it))
	term.item_purchased.connect(func(it: Dictionary) -> void: bought.append(it))
	term.purchase_denied.connect(func(it: Dictionary) -> void: denied.append(it))

	var catalog := _catalog()
	term.set_catalog(catalog)
	await get_tree().process_frame

	# 1. ALL shows every item; a category filter narrows it.
	_check(term.visible_cards().size() == 4, "ALL should show 4 cards, got %d"
			% term.visible_cards().size())
	term.select_category("CHAIRS")
	await get_tree().process_frame
	_check(term.visible_cards().size() == 2, "CHAIRS should show 2 cards, got %d"
			% term.visible_cards().size())
	term.select_category("ALL")
	await get_tree().process_frame

	# 2. Hovering a card emits item_focused with that item.
	var orb: Dictionary = catalog[2]
	term.visible_cards()[0].focused.emit(term.visible_cards()[0].item)
	_check(focused.size() == 1, "hover should emit item_focused once")
	_check(focused.size() == 1 and String(focused[0].get("id")) ==
			String(term.visible_cards()[0].item.get("id")), "focused item id mismatch")

	# 3. Economy: an affordable buy spends Cores + marks owned + emits once.
	var start_cores: int = term.cores
	var ok := term.attempt_buy(orb)
	_check(ok, "affordable buy should succeed")
	_check(term.cores == start_cores - 800, "Cores should drop by 800, got %d" % term.cores)
	_check(term.is_owned("core_orb"), "core_orb should be owned after buying")
	_check(bought.size() == 1, "item_purchased should fire once")

	# Re-buying an owned item is denied, Cores unchanged.
	var cores_after: int = term.cores
	_check(not term.attempt_buy(orb), "re-buying an owned item should be denied")
	_check(term.cores == cores_after, "denied re-buy must not change Cores")
	_check(denied.size() == 1, "purchase_denied should fire on owned re-buy")

	# An unaffordable item is denied, Cores unchanged.
	term.cores = 100
	_check(not term.attempt_buy(catalog[3]), "unaffordable buy should be denied (15000 > 100)")
	var equipped: Array[Dictionary] = []
	term.item_equipped.connect(func(it: Dictionary) -> void: equipped.append(it))

	_check(term.cores == 100, "denied poor buy must not change Cores")
	_check(bought.size() == 1, "no extra item_purchased on denied buys")

	# 3b. Equip: an owned item equips into its category slot; equipping another in
	#     the same category swaps it; equipping an unowned item is refused.
	term.cores = 30000
	term.attempt_buy(catalog[3])  # ram_ring (Effects), so two Effects items are owned
	_check(term.attempt_equip(orb), "owned item should equip")
	_check(term.is_equipped("core_orb"), "core_orb should read equipped")
	_check(equipped.size() == 1, "item_equipped should fire on equip")
	await get_tree().process_frame
	var orb_card := _card_for(term, "core_orb")
	_check(orb_card != null and orb_card._buy_btn.text == "EQUIPPED",
			"equipped card button should read EQUIPPED")
	_check(term.attempt_equip(catalog[3]), "a second Effects item should equip")
	_check(term.is_equipped("ram_ring"), "ram_ring should read equipped after the swap")
	_check(not term.is_equipped("core_orb"), "core_orb should unequip (same-category swap)")
	_check(not term.attempt_equip(catalog[0]), "equipping an unowned item should be refused")

	# 4. Turntable mounts exactly one display model per item.
	var tt: ShopTurntable = TURNTABLE.new()
	add_child(tt)
	await get_tree().process_frame
	tt.show_item(catalog[0])  # chair (composite model)
	_check(tt.display_count() == 1, "turntable should hold one display root, got %d"
			% tt.display_count())
	tt.show_item(catalog[2])  # sphere -> still exactly one (old one cleared)
	await get_tree().process_frame
	_check(tt.display_count() == 1, "swapping items must not stack models, got %d"
			% tt.display_count())
