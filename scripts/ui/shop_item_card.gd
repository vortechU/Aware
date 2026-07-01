class_name ShopItemCard
extends PanelContainer
## One item tile in the holographic ShopTerminal grid: a category sub-label, a
## custom-drawn item glyph (ShopItemIcon), the item name, a PURCHASE button + a
## small gift button -- the layout of the reference Roblox "Tuck Shop" card.
## Themed via ShopTheme (button variations + per-item styleboxes); self-contained
## and asset-free. Owns no shop logic: it reports hover (`focused`) and intent
## (`buy_pressed`) up to the terminal, and reflects owned / selected state.

signal focused(item: Dictionary)
signal buy_pressed(item: Dictionary)
signal equip_pressed(item: Dictionary)

const HOVER_SCALE := 1.035
const COLOR_TWEEN_TIME := 0.14
const SCALE_TWEEN_TIME := 0.13
const PUNCH_TIME := 0.30

var item: Dictionary
var _owned := false
var _equipped := false
var _hovered := false
var _selected := false

var _icon: ShopItemIcon
var _buy_btn: Button
var _name_label: Label

## One persistent StyleBoxFlat, tweened in place on state changes (rather than
## swapping stylebox instances each time) so the border/bg colors ease smoothly
## instead of snapping. `_fx_tween` is separate from the color tween so a
## pulse/shake punch never fights an in-flight hover-color transition.
var _panel_sb: StyleBoxFlat
var _color_tween: Tween
var _fx_tween: Tween


func setup(data: Dictionary) -> void:
	item = data
	custom_minimum_size = Vector2(216, 168)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func() -> void: pivot_offset = size * 0.5)

	_panel_sb = StyleBoxFlat.new()
	_panel_sb.set_corner_radius_all(6)
	_panel_sb.set_content_margin_all(4.0)
	add_theme_stylebox_override("panel", _panel_sb)
	_apply_panel(false)  # snap to the idle state -- nothing to animate from yet
	mouse_entered.connect(_on_hover)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 9)
	add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)

	var cat := Label.new()
	cat.text = String(item.get("category", "ITEM")).to_upper()
	cat.add_theme_font_size_override("font_size", 11)
	cat.add_theme_color_override("font_color", ShopTheme.TEXT_FAINT)
	cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cat)

	var color := item.get("color", ShopTheme.ACCENT) as Color
	var thumb := Panel.new()
	thumb.custom_minimum_size = Vector2(0, 70)
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_theme_stylebox_override("panel", ShopTheme.thumb_sb(color))
	box.add_child(thumb)

	_icon = ShopItemIcon.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb.add_child(_icon)
	_icon.setup(String(item.get("shape", "box")), color)

	_name_label = Label.new()
	_name_label.text = String(item.get("name", item.get("id", "???"))).to_upper()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", ShopTheme.TEXT_BRIGHT)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	_buy_btn = Button.new()
	_buy_btn.theme_type_variation = "ShopBuy"
	_buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_btn.focus_mode = Control.FOCUS_NONE
	_buy_btn.pressed.connect(_on_primary)
	_buy_btn.mouse_entered.connect(_on_hover)  # hovering the button still selects the item
	row.add_child(_buy_btn)

	var gift := Button.new()
	gift.theme_type_variation = "ShopGift"
	gift.text = "+"
	gift.custom_minimum_size = Vector2(34, 0)
	gift.focus_mode = Control.FOCUS_NONE
	gift.tooltip_text = "Gift to a friend"
	gift.mouse_entered.connect(_on_hover)
	row.add_child(gift)

	_refresh_buy()


func price_text() -> String:
	return ShopTerminal.commas(int(item.get("cost", 0)))


func set_owned(owned: bool) -> void:
	_owned = owned
	_refresh_buy()


func set_equipped(equipped: bool) -> void:
	if _equipped == equipped:
		return
	_equipped = equipped
	_refresh_buy()
	_apply_panel()


## Persistent highlight on the card whose item is shown on the turntable.
func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_apply_panel()


## Positive feedback for a successful purchase: a quick scale punch + bright flash.
func pulse() -> void:
	if _fx_tween != null:
		_fx_tween.kill()
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "scale", Vector2(1.10, 1.10), PUNCH_TIME * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fx_tween.parallel().tween_property(self, "modulate", Color(1.5, 1.7, 1.55, 1), PUNCH_TIME * 0.3)
	_fx_tween.tween_property(self, "scale", Vector2.ONE, PUNCH_TIME * 0.7) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_fx_tween.parallel().tween_property(self, "modulate", Color(1, 1, 1, 1), PUNCH_TIME * 0.7)
	# The mouse is usually still over the card right after a click; restore the
	# hover bump once the punch settles instead of leaving it at rest scale.
	_fx_tween.tween_callback(func() -> void: _tween_hover_scale(_hovered))


## Negative feedback for a denied purchase (too poor / already owned): a shake.
func shake() -> void:
	if _fx_tween != null:
		_fx_tween.kill()
	var base_x := position.x
	_fx_tween = create_tween()
	for i in 5:
		var dir := 1.0 if i % 2 == 0 else -1.0
		var amount := 6.0 * (1.0 - float(i) / 5.0)
		_fx_tween.tween_property(self, "position:x", base_x + dir * amount, 0.035)
	_fx_tween.tween_property(self, "position:x", base_x, 0.035)


## Primary button drives the lifecycle: buy an unowned item, then equip it.
func _on_primary() -> void:
	if not _owned:
		buy_pressed.emit(item)
	elif not _equipped:
		equip_pressed.emit(item)


func _refresh_buy() -> void:
	if _buy_btn == null:
		return
	if not _owned:
		_buy_btn.text = "PURCHASE  %s" % price_text()
		_buy_btn.disabled = false
	elif _equipped:
		_buy_btn.text = "EQUIPPED"
		_buy_btn.disabled = true
	else:
		_buy_btn.text = "EQUIP"
		_buy_btn.disabled = false
	modulate = Color(1, 1, 1, 1)


func _on_hover() -> void:
	focused.emit(item)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		_apply_panel()
		_tween_hover_scale(true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		_apply_panel()
		_tween_hover_scale(false)


## Eases the card's own scale up/down on hover (on top of any pulse/shake punch,
## which use the same `scale`/`position` properties but run on `_fx_tween`).
func _tween_hover_scale(hovered: bool) -> void:
	if _fx_tween != null:
		_fx_tween.kill()
	_fx_tween = create_tween()
	var target := Vector2(HOVER_SCALE, HOVER_SCALE) if hovered else Vector2.ONE
	_fx_tween.tween_property(self, "scale", target, SCALE_TWEEN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Eases the persistent stylebox toward the target state's colors (`animate =
## false` snaps instantly, used only for the very first build).
func _apply_panel(animate: bool = true) -> void:
	var accent := item.get("color", ShopTheme.ACCENT) as Color
	var state := 0
	if _hovered:
		state = 1
	elif _equipped:
		state = 3
	elif _selected:
		state = 2
	var target := ShopTheme.card_state_colors(accent, state)

	if _color_tween != null:
		_color_tween.kill()
	if not animate:
		_panel_sb.bg_color = target.bg
		_panel_sb.border_color = target.border
		_panel_sb.set_border_width_all(int(target.bw))
		return
	_color_tween = create_tween()
	_color_tween.set_parallel(true)
	_color_tween.tween_property(_panel_sb, "bg_color", target.bg, COLOR_TWEEN_TIME)
	_color_tween.tween_property(_panel_sb, "border_color", target.border, COLOR_TWEEN_TIME)
	_color_tween.tween_method(_set_border_width, _panel_sb.border_width_left,
			target.bw, COLOR_TWEEN_TIME)


func _set_border_width(w: float) -> void:
	_panel_sb.set_border_width_all(int(round(w)))
