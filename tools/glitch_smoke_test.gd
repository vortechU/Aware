extends Node
## Headless functional test for the upgrade-card glitch driver in run_hud.gd.
## Run: godot --headless --path . res://tools/glitch_smoke_test.tscn
##
## The shader look can't be verified headless (the dummy renderer doesn't compile
## shaders -- see tools/glitch_preview.tscn for that), but the driver that feeds
## it can: this asserts the three states drive the overlay's uniforms.
##   - show -> resting IDLE base over the card row, no focus.
##   - hover a card -> focus_intensity rises to HOVER.
##   - click (button_down) -> focus_intensity spikes toward CLICK.
##   - hide -> base + focus cleared to 0.

const RUN_HUD := preload("res://scenes/ui/run_hud.tscn")

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("GLITCH_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("GLITCH_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	var hud := RUN_HUD.instantiate()
	add_child(hud)
	var mat: ShaderMaterial = (hud.get_node("UpgradePanel/Glitch") as ColorRect).material
	var cards: Node = hud.get_node("UpgradePanel/Center/Box/Cards")

	var choices: Array[Dictionary] = [
		{"id": "damage", "title": "DAMAGE", "desc": "more"},
		{"id": "move_speed", "title": "SPEED", "desc": "faster"},
		{"id": "max_health", "title": "HEALTH", "desc": "tougher"},
	]
	hud.call("show_upgrade_choices", choices, "TEST")
	for _i in 4:  # settle layout + a couple _update_glitch passes
		await get_tree().process_frame

	var base: float = mat.get_shader_parameter("base_intensity")
	_check(absf(base - 0.18) < 0.001, "idle base should be 0.18 on show, got %.3f" % base)
	_check(float(mat.get_shader_parameter("focus_intensity")) <= 0.001,
			"no card hovered -> focus should be 0")

	# Hover the middle card.
	(cards.get_child(1) as Button).mouse_entered.emit()
	await get_tree().process_frame
	var hov: float = mat.get_shader_parameter("focus_intensity")
	_check(absf(hov - 0.5) < 0.001, "hover focus should be 0.5, got %.3f" % hov)

	# Leave hover, click the first card -> a strong burst (decays from 1.0).
	(cards.get_child(1) as Button).mouse_exited.emit()
	(cards.get_child(0) as Button).button_down.emit()
	await get_tree().process_frame
	var clk: float = mat.get_shader_parameter("focus_intensity")
	_check(clk > 0.8, "click burst should spike above 0.8, got %.3f" % clk)

	# Hiding clears everything.
	hud.call("hide_upgrade_choices")
	_check(float(mat.get_shader_parameter("base_intensity")) <= 0.001,
			"base should be cleared on hide")
	_check(float(mat.get_shader_parameter("focus_intensity")) <= 0.001,
			"focus should be cleared on hide")
