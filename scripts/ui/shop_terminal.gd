class_name ShopTerminal
extends Control
## In-world holographic shop panel, modelled on the reference Roblox "Tuck Shop":
## a title, a left column of category tabs, a scrollable grid of item cards, a
## currency footer + a CLOSE button, all glowing on the `hologram_panel` shader.
##
## Build-alongside + self-contained: the whole tree is built in code (the lobby /
## speed_lines convention) and it owns no game state coupling -- the catalog is
## plain data and the currency is a local `cores` int, so it runs in a preview,
## a sandbox, or (later) wired to MetaProgression with no structural change. It
## reports up via signals; a host (preview / lobby station) drives the 3D
## turntable from `item_focused` and persists purchases from `item_purchased`.

signal item_focused(item: Dictionary)   # a card was hovered -> drive the turntable
signal item_purchased(item: Dictionary) # a successful buy
signal item_equipped(item: Dictionary)  # an owned item was equipped into its slot
signal purchase_denied(item: Dictionary) # too poor / already owned (for SFX/flash)
signal closed                            # CLOSE pressed

const PANEL_SHADER := preload("res://shaders/hologram_panel.gdshader")
const TILT_SHADER := preload("res://shaders/panel_tilt.gdshader")
const CARD := preload("res://scripts/ui/shop_item_card.gd")

const COLUMNS := 2
const CORES_TWEEN_TIME := 0.4
const TILT_SMOOTHING := 10.0  # how fast the lean eases toward the cursor (per second)
const TILT_MAX := 0.9         # clamp so the panel never over-warps at the very edge

var cores := 28200            # local currency (homage to the reference's 28,200)
var title_text := "CORE EXCHANGE"

var _cores_display := 0.0     # eased toward `cores` -- what the label actually shows
var _cores_tween: Tween

var _catalog: Array[Dictionary] = []
var _category := "ALL"
var _owned := {}              # id -> true
var _equipped := {}           # category -> equipped id (mirror of MetaProgression)
var _selected_id := ""        # item shown on the turntable -> its card stays lit
var _cards: Array[ShopItemCard] = []

var _grid: GridContainer
var _tabs: VBoxContainer
var _cores_label: Label
var _title_label: Label
var _tab_buttons := {}        # category -> Button
var _tab_group: ButtonGroup
var _frame: Control             # the visible glass panel -- animated on open/close
var _open_tween: Tween
var _tilt_view: SubViewportContainer  # displays the panel's render, warped by TILT_SHADER
var _tilt_material: ShaderMaterial
var _tilt := Vector2.ZERO       # current eased lean, fed to the shader each frame


func _ready() -> void:
	# set_anchors_AND_OFFSETS: anchors-only keeps the (0,0) offsets and the rect
	# stays 0x0, collapsing every container to content-min size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the panel eats input, not the full rect
	_build_chrome()


## Eases the panel's "3D tilt" toward the cursor while it's over the panel (and
## back to flat once it isn't), the SpeedLines/glitch-overlay smoothing pattern:
## a target computed straight from the mouse, lerped in every frame so the lean
## reads as reactive rather than snapping to the cursor.
func _process(delta: float) -> void:
	if not visible or _tilt_view == null:
		return
	var rect := _tilt_view.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var mouse := get_global_mouse_position()
	var target := Vector2.ZERO
	if rect.has_point(mouse):
		var center := rect.position + rect.size * 0.5
		var offset := (mouse - center) / (rect.size * 0.5)
		target = Vector2(clampf(offset.x, -1.0, 1.0), clampf(offset.y, -1.0, 1.0)) * TILT_MAX
	_tilt = _tilt.lerp(target, clampf(TILT_SMOOTHING * delta, 0.0, 1.0))
	if _tilt_material != null:
		_tilt_material.set_shader_parameter("tilt", _tilt)
		_tilt_material.set_shader_parameter("panel_size", rect.size)


# ------------------------------------------------------------------ public API

func set_catalog(items: Array) -> void:
	_catalog.clear()
	for it: Dictionary in items:
		_catalog.append(it)
	if _grid != null:
		_rebuild_tabs()
		_rebuild_grid()


func select_category(category: String) -> void:
	_category = category
	for cat: String in _tab_buttons:
		(_tab_buttons[cat] as Button).button_pressed = (cat == category)
	_rebuild_grid()


## Hover entry point (cards call this; also public so a host/test can drive it).
## Also lights the matching card as the persistent "selected" one (turntable item).
func focus_item(item: Dictionary) -> void:
	_selected_id = String(item.get("id", ""))
	for c in _cards:
		c.set_selected(String(c.item.get("id", "")) == _selected_id)
	item_focused.emit(item)


## Attempt a purchase. Returns true on success. Cards route here; public so a
## host/test can drive the economy without synthesising mouse clicks.
func attempt_buy(item: Dictionary) -> bool:
	var id := String(item.get("id", ""))
	if _owned.has(id) or cores < int(item.get("cost", 0)):
		var denied_card := _card_for(id)
		if denied_card != null:
			denied_card.shake()
		purchase_denied.emit(item)
		return false
	cores -= int(item.get("cost", 0))
	_owned[id] = true
	var card := _card_for(id)
	if card != null:
		card.set_owned(true)
		card.pulse()
	_animate_cores(cores)
	item_purchased.emit(item)
	return true


func _card_for(id: String) -> ShopItemCard:
	for c in _cards:
		if String(c.item.get("id", "")) == id:
			return c
	return null


## Equip an owned item into its category slot (swaps out whatever was equipped
## there). Cards route here; public so a host/test can drive it. The terminal only
## tracks the choice + UI state -- a host commits + persists it.
func attempt_equip(item: Dictionary) -> bool:
	var id := String(item.get("id", ""))
	if not _owned.has(id):
		return false
	_equipped[String(item.get("category", ""))] = id
	_refresh_equipped()
	item_equipped.emit(item)
	return true


## Pre-seed equipped state (a host syncs this from MetaProgression on open).
func mark_equipped(id: String, category: String) -> void:
	_equipped[category] = id
	_refresh_equipped()


func is_equipped(id: String) -> bool:
	for cat in _equipped:
		if String(_equipped[cat]) == id:
			return true
	return false


func is_owned(id: String) -> bool:
	return _owned.has(id)


## Set the displayed currency (a host syncs this from MetaProgression.cores).
## `animate = false` snaps instantly (used for the initial per-open resync, so
## reopening the shop never plays a spurious count-up/down); a real spend or
## reward (the `_animate_cores` path below) always eases the number.
func set_cores(amount: int, animate: bool = true) -> void:
	cores = amount
	if animate and _cores_label != null:
		_animate_cores(amount)
	else:
		_cores_display = float(amount)
		_refresh_cores()


func _animate_cores(amount: int) -> void:
	if _cores_tween != null:
		_cores_tween.kill()
	_cores_tween = create_tween()
	_cores_tween.tween_method(_set_cores_display, _cores_display, float(amount), CORES_TWEEN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_cores_display(v: float) -> void:
	_cores_display = v
	_refresh_cores()


## Mark an item as already owned (a host pre-seeds this from saved purchases).
func mark_owned(id: String) -> void:
	_owned[id] = true
	for c in _cards:
		if String(c.item.get("id", "")) == id:
			c.set_owned(true)


func visible_cards() -> Array[ShopItemCard]:
	return _cards


## Show the panel with a quick fade+scale-in (instead of a hard visible=true snap).
func animate_open() -> void:
	visible = true
	if _frame == null:
		return
	if _open_tween != null:
		_open_tween.kill()
	_frame.pivot_offset = _frame.size * 0.5
	_frame.modulate = Color(1, 1, 1, 0)
	_frame.scale = Vector2(0.94, 0.94)
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(_frame, "modulate:a", 1.0, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_frame, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fade+scale the panel out, then hide (a host calls this instead of setting
## visible=false directly, so closing the shop doesn't just vanish instantly).
func animate_close() -> void:
	if _frame == null:
		visible = false
		return
	if _open_tween != null:
		_open_tween.kill()
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(_frame, "modulate:a", 0.0, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_open_tween.tween_property(_frame, "scale", Vector2(0.94, 0.94), 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_open_tween.chain().tween_callback(func() -> void: visible = false)


# ------------------------------------------------------------------ build

func _build_chrome() -> void:
	theme = ShopTheme.build()  # styles only this subtree (buttons / tabs / scrollbar)

	# Left-anchored frame, leaving the right side of the screen open for the 3D
	# pedestal -- resolution-relative so it holds at any window size.
	var frame := Control.new()
	frame.name = "Frame"
	frame.anchor_left = 0.04
	frame.anchor_right = 0.62
	frame.anchor_top = 0.10
	frame.anchor_bottom = 0.92
	add_child(frame)
	_frame = frame

	# The whole panel -- holo backing, edge frame, every control -- renders into
	# this SubViewport, then TiltView shows that single flattened image through
	# panel_tilt.gdshader, so the "3D tilt" warps the panel as one glass slab
	# instead of needing per-node transforms. Input still forwards through
	# correctly (SubViewportContainer's normal behaviour); only the visuals warp.
	_tilt_view = SubViewportContainer.new()
	_tilt_view.name = "TiltView"
	_tilt_view.stretch = true
	_tilt_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tilt_material = ShaderMaterial.new()
	_tilt_material.shader = TILT_SHADER
	_tilt_view.material = _tilt_material
	frame.add_child(_tilt_view)

	var vp := SubViewport.new()
	vp.name = "Viewport"
	vp.transparent_bg = true  # keep the glass panel translucent over the lobby behind it
	vp.size = Vector2i(900, 700)  # placeholder; `stretch` resizes this to match TiltView
	_tilt_view.add_child(vp)

	var holo := ColorRect.new()
	holo.name = "Holo"
	holo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PANEL_SHADER
	holo.material = mat
	vp.add_child(holo)

	# Crisp glowing edge over the soft shader fill (the reference's panel border).
	var edge := Panel.new()
	edge.name = "Edge"
	edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.add_theme_stylebox_override("panel", ShopTheme.panel_edge())
	vp.add_child(edge)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	vp.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	pad.add_child(col)

	col.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)

	_tabs = VBoxContainer.new()
	_tabs.custom_minimum_size = Vector2(150, 0)
	_tabs.add_theme_constant_override("separation", 6)
	body.add_child(_tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	# A thin divider above the footer.
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.add_theme_stylebox_override("panel", ShopTheme.card_sb(ShopTheme.ACCENT, 0))
	col.add_child(rule)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	col.add_child(footer)

	_cores_label = Label.new()  # bright running total
	_cores_label.add_theme_font_size_override("font_size", 26)
	_cores_label.add_theme_color_override("font_color", ShopTheme.ACCENT_HOT)
	footer.add_child(_cores_label)

	var cores_suffix := Label.new()
	cores_suffix.text = "CORES OWNED"
	cores_suffix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cores_suffix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cores_suffix.add_theme_font_size_override("font_size", 15)
	cores_suffix.add_theme_color_override("font_color", ShopTheme.TEXT_DIM)
	footer.add_child(cores_suffix)

	var close := Button.new()
	close.text = "CLOSE  [ESC]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: closed.emit())
	footer.add_child(close)

	_cores_display = float(cores)  # seed before the first refresh (no count-up on build)
	_refresh_cores()
	if not _catalog.is_empty():
		_rebuild_tabs()
		_rebuild_grid()


## Title + subtitle + an accent underline -- a header block instead of a lone label.
func _build_header() -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)

	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.add_theme_font_size_override("font_size", 46)
	_title_label.add_theme_color_override("font_color", ShopTheme.TEXT_BRIGHT)
	_title_label.add_theme_constant_override("outline_size", 6)
	_title_label.add_theme_color_override("font_outline_color", Color(0.1, 0.5, 0.4, 0.7))
	header.add_child(_title_label)

	var subtitle := Label.new()
	subtitle.text = "COSMETIC CACHE  //  SPEND YOUR CORES"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", ShopTheme.TEXT_DIM)
	header.add_child(subtitle)

	var underline := Panel.new()
	underline.custom_minimum_size = Vector2(0, 3)
	var ul := StyleBoxFlat.new()
	ul.bg_color = ShopTheme.ACCENT
	ul.set_corner_radius_all(2)
	underline.add_theme_stylebox_override("panel", ul)
	header.add_child(underline)
	return header


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	_tab_buttons.clear()
	_tab_group = ButtonGroup.new()  # keeps exactly one tab lit

	var cats: Array[String] = ["ALL"]
	for it: Dictionary in _catalog:
		var c := String(it.get("category", "ITEM")).to_upper()
		if not cats.has(c):
			cats.append(c)

	for cat: String in cats:
		var b := Button.new()
		b.text = cat
		b.theme_type_variation = "ShopTab"
		b.toggle_mode = true
		b.button_group = _tab_group
		b.button_pressed = (cat == _category)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(select_category.bind(cat))
		_tabs.add_child(b)
		_tab_buttons[cat] = b


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()

	for it: Dictionary in _catalog:
		if _category != "ALL" and String(it.get("category", "ITEM")).to_upper() != _category:
			continue
		var card := CARD.new() as ShopItemCard
		_grid.add_child(card)        # add before setup so theme overrides settle
		card.setup(it)
		card.set_owned(_owned.has(String(it.get("id", ""))))
		card.set_equipped(is_equipped(String(it.get("id", ""))))
		card.set_selected(String(it.get("id", "")) == _selected_id)
		card.focused.connect(focus_item)
		card.buy_pressed.connect(attempt_buy)
		card.equip_pressed.connect(attempt_equip)
		_cards.append(card)


func _refresh_equipped() -> void:
	for c in _cards:
		c.set_equipped(is_equipped(String(c.item.get("id", ""))))


func _refresh_cores() -> void:
	if _cores_label != null:
		_cores_label.text = commas(int(round(_cores_display)))


## Thousands-separated integer (shared with ShopItemCard's price line).
static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
