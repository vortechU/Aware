class_name ShopTheme
extends RefCounted
## Code-built holographic theme for the cosmetic shop -- one Theme resource (set on
## the ShopTerminal root, so it styles only that subtree) plus per-item stylebox
## helpers the cards use. Asset-free: the project ships no fonts, so the polish
## comes from styleboxes, the holo palette, and button state variations rather
## than typography. Cyan-green glass to match the hologram_panel shader + the
## computer-world palette.

# --- palette ---
const ACCENT := Color(0.30, 1.00, 0.70)        # primary holo green
const ACCENT_HOT := Color(0.62, 1.00, 0.90)    # bright edge / hover
const TEXT_BRIGHT := Color(0.88, 1.00, 0.95)
const TEXT_DIM := Color(0.55, 0.80, 0.74)
const TEXT_FAINT := Color(0.45, 0.66, 0.62)
const BORDER := Color(0.30, 0.90, 0.78, 0.55)
const BORDER_HOT := Color(0.62, 1.00, 0.90, 0.95)
const CARD_BG := Color(0.04, 0.12, 0.12, 0.55)
const CARD_BG_HOT := Color(0.07, 0.20, 0.19, 0.75)
const PANEL_EDGE := Color(0.40, 0.95, 0.80, 0.8)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16

	# --- base Button (CLOSE etc.): translucent holo button with state feedback ---
	t.set_stylebox("normal", "Button", _sb(Color(0.06, 0.16, 0.16, 0.55), BORDER, 1, 5))
	t.set_stylebox("hover", "Button", _sb(Color(0.10, 0.26, 0.25, 0.75), BORDER_HOT, 1, 5))
	t.set_stylebox("pressed", "Button", _sb(Color(0.14, 0.34, 0.30, 0.85), ACCENT_HOT, 1, 5))
	t.set_stylebox("disabled", "Button", _sb(Color(0.10, 0.12, 0.13, 0.45), Color(0.4, 0.45, 0.45, 0.4), 1, 5))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT_BRIGHT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)

	# --- category tabs: transparent until selected (toggled -> "pressed" fill) ---
	t.set_type_variation("ShopTab", "Button")
	t.set_stylebox("normal", "ShopTab", _transparent_pad(10, 8))
	t.set_stylebox("hover", "ShopTab", _tab_fill(Color(0.10, 0.24, 0.22, 0.45), BORDER))
	t.set_stylebox("pressed", "ShopTab", _tab_fill(Color(0.12, 0.30, 0.26, 0.80), ACCENT_HOT))
	t.set_stylebox("focus", "ShopTab", StyleBoxEmpty.new())
	t.set_color("font_color", "ShopTab", TEXT_DIM)
	t.set_color("font_hover_color", "ShopTab", TEXT_BRIGHT)
	t.set_color("font_pressed_color", "ShopTab", Color(1, 1, 1))
	t.set_font_size("font_size", "ShopTab", 18)

	# --- PURCHASE button: accent-tinted, brightening on hover ---
	t.set_type_variation("ShopBuy", "Button")
	t.set_stylebox("normal", "ShopBuy", _sb(Color(0.10, 0.30, 0.24, 0.65), Color(0.35, 0.95, 0.7, 0.7), 1, 4))
	t.set_stylebox("hover", "ShopBuy", _sb(Color(0.16, 0.46, 0.34, 0.85), ACCENT_HOT, 1, 4))
	t.set_stylebox("pressed", "ShopBuy", _sb(Color(0.22, 0.58, 0.42, 0.95), ACCENT_HOT, 2, 4))
	t.set_stylebox("disabled", "ShopBuy", _sb(Color(0.10, 0.14, 0.14, 0.45), Color(0.4, 0.45, 0.45, 0.35), 1, 4))
	t.set_color("font_color", "ShopBuy", Color(0.92, 1.0, 0.95))
	t.set_color("font_hover_color", "ShopBuy", Color(1, 1, 1))
	t.set_color("font_disabled_color", "ShopBuy", TEXT_FAINT)
	t.set_font_size("font_size", "ShopBuy", 14)

	# --- gift "+" button: small square ---
	t.set_type_variation("ShopGift", "Button")
	t.set_stylebox("normal", "ShopGift", _sb(Color(0.06, 0.18, 0.17, 0.5), BORDER, 1, 4))
	t.set_stylebox("hover", "ShopGift", _sb(Color(0.12, 0.30, 0.28, 0.8), BORDER_HOT, 1, 4))
	t.set_stylebox("pressed", "ShopGift", _sb(Color(0.16, 0.38, 0.32, 0.9), ACCENT_HOT, 1, 4))
	t.set_color("font_color", "ShopGift", ACCENT_HOT)
	t.set_font_size("font_size", "ShopGift", 18)

	# --- thin holo scrollbar ---
	var track := _sb(Color(0.05, 0.12, 0.12, 0.4), Color(0, 0, 0, 0), 0, 5)
	track.content_margin_left = 5.0
	track.content_margin_right = 5.0
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", _sb(Color(0.25, 0.7, 0.55, 0.7), Color(0, 0, 0, 0), 0, 5))
	t.set_stylebox("grabber_highlight", "VScrollBar", _sb(ACCENT, Color(0, 0, 0, 0), 0, 5))
	t.set_stylebox("grabber_pressed", "VScrollBar", _sb(ACCENT_HOT, Color(0, 0, 0, 0), 0, 5))
	return t


## The whole-panel edge frame (drawn over the holo shader for a crisp glowing border).
static func panel_edge() -> StyleBoxFlat:
	var sb := _sb(Color(0, 0, 0, 0), PANEL_EDGE, 2, 10)
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


## Per-card state: 0 = idle, 1 = hover, 2 = selected (turntable), 3 = equipped (a
## steady accent border so the active item reads at a glance). Raw values (not a
## built StyleBox) so ShopItemCard can TWEEN toward them on a persistent stylebox
## instance instead of swapping stylebox objects -- swapping reads as an instant
## snap, tweening the colors reads as the card "lighting up".
static func card_state_colors(accent: Color, state: int) -> Dictionary:
	var bg := CARD_BG
	var border := BORDER
	var bw := 1.0
	if state == 1:
		bg = CARD_BG_HOT
		border = BORDER_HOT
	elif state == 2:
		bg = CARD_BG_HOT
		border = accent.lightened(0.15)
		border.a = 1.0
		bw = 2.0
	elif state == 3:
		bg = CARD_BG_HOT
		border = ACCENT
		bw = 2.0
	return {"bg": bg, "border": border, "bw": bw}


## A ready-made stylebox for one-off (non-tweened) uses, e.g. the footer divider.
static func card_sb(accent: Color, state: int) -> StyleBoxFlat:
	var v := card_state_colors(accent, state)
	var sb := _sb(v.bg, v.border, int(v.bw), 6)
	sb.set_content_margin_all(4.0)
	return sb


## The item thumbnail backing (a dark recessed tile tinted toward the item).
static func thumb_sb(color: Color) -> StyleBoxFlat:
	var bg := color.darkened(0.62)
	bg.a = 0.9
	var sb := _sb(bg, color.lightened(0.1) * Color(1, 1, 1, 0.6), 1, 4)
	sb.set_border_width(SIDE_TOP, 2)  # a lit top edge for a hint of depth
	sb.border_color = color.lightened(0.2)
	return sb


# ------------------------------------------------------------------ helpers

static func _sb(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(bw)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


static func _transparent_pad(h: float, v: float) -> StyleBoxFlat:
	# A fully transparent box that still pads the tab text (a StyleBoxEmpty's
	# content margins read-only in 4.x, so use a transparent flat box instead).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## A tab fill with a thick accent bar on the left edge (the "active" indicator).
static func _tab_fill(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.border_color = border
	sb.set_border_width(SIDE_LEFT, 4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb
