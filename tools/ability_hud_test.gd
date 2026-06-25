extends Node
## Headless functional test for the RunHUD ability widget, Pass 2 (ABILITY_HUD_OK).
## Run: godot --headless --path . res://tools/ability_hud_test.tscn
##
## The ring look can't be verified headless (custom _draw needs a real renderer --
## eyeballed in play), but the driver that feeds it can: this asserts each per-slot
## widget tracks the slot-indexed GameEvents ability_* signals.
##   - both slots hidden until granted.
##   - grant slot 0 -> its widget shows, key label = the `ability` bind ("F"), title
##     = the ability name, reads ready; slot 1 stays hidden.
##   - a full-remaining cooldown_changed -> the widget reads "on cooldown".
##   - ability_used -> a cast pulse.
##   - a 0-remaining cooldown_changed -> ready again.
##   - granting slot 1 reveals the SECOND widget independently (key "G" / `ability_2`)
##     while slot 0 is untouched -- i.e. multi-slot routing.

const RUN_HUD := preload("res://scenes/ui/run_hud.tscn")

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("ABILITY_HUD_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("ABILITY_HUD_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	var hud := RUN_HUD.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var slot0 := hud.get_node("AbilityBar/Slot0") as AbilityWidget
	var slot1 := hud.get_node("AbilityBar/Slot1") as AbilityWidget
	var key := slot0.get_node("KeyLabel") as Label
	var title := slot0.get_node("TitleLabel") as Label

	# ---- both slots hidden until granted ----
	_check(not slot0.visible and not slot1.visible, "ability widgets should start hidden")

	# ---- grant slot 0 -> shown, labelled, ready ----
	GameEvents.ability_granted.emit(0, "stack_smash", 1)
	await get_tree().process_frame
	_check(slot0.visible, "granting slot 0 should reveal its widget")
	_check(not slot1.visible, "granting slot 0 must not reveal slot 1")
	_check(key.text == "F", "slot 0 key label should read the `ability` bind 'F' (got '%s')" % key.text)
	_check(title.text == "Stack Smash", "slot 0 title should be the ability name (got '%s')" % title.text)
	_check(slot0.is_ability_ready(), "a freshly granted ability should read ready")

	# ---- cast (full cooldown) -> on cooldown ----
	GameEvents.ability_cooldown_changed.emit(0, "stack_smash", 6.0, 6.0)
	await get_tree().process_frame
	_check(not slot0.is_ability_ready(), "after a cast slot 0 should be on cooldown")

	# ---- used -> a cast pulse ----
	GameEvents.ability_used.emit(0, "stack_smash")
	_check(slot0._flash > 0.0, "ability_used should pulse slot 0")

	# ---- cooldown done -> ready again ----
	GameEvents.ability_cooldown_changed.emit(0, "stack_smash", 0.0, 6.0)
	await get_tree().process_frame
	_check(slot0.is_ability_ready(), "a 0-remaining cooldown should read ready again")

	# ---- multi-slot: granting slot 1 reveals the SECOND widget independently ----
	var key1 := slot1.get_node("KeyLabel") as Label
	var title1 := slot1.get_node("TitleLabel") as Label
	GameEvents.ability_granted.emit(1, "overclock", 1)
	await get_tree().process_frame
	_check(slot1.visible, "granting slot 1 should reveal the second widget")
	_check(key1.text == "G", "slot 1 key label should read the `ability_2` bind 'G' (got '%s')" % key1.text)
	_check(title1.text == "Overclock", "slot 1 title should be Overclock (got '%s')" % title1.text)
	# Slot 0 stays as it was -- the two slots are independent.
	_check(slot0.visible and title.text == "Stack Smash",
			"slot 0 should be untouched when slot 1 is granted")
