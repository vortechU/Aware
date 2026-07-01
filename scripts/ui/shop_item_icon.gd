class_name ShopItemIcon
extends Control
## A tiny asset-free vector emblem for a shop item, custom-drawn from the item's
## `shape` tag (chair / sphere / helmet / torus / capsule / prism / box) in the
## item's tint -- so each card shows a recognisable little glyph instead of a flat
## colour swatch, echoing the reference shop's per-item thumbnails. Mirrors the
## ShopTurntable's shape vocabulary, on the cheap (no meshes/textures).

var _shape := "box"
var _color := Color(0.4, 1.0, 0.8)


func setup(shape: String, color: Color) -> void:
	_shape = shape
	_color = color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var s: float = minf(size.x, size.y)
	var w: float = maxf(2.0, s * 0.045)
	var bright := _color.lightened(0.15)
	var glow := _color
	glow.a = 0.35
	match _shape:
		"chair":
			_chair(c, s, bright, w)
		"sphere":
			draw_circle(c, s * 0.27, glow)
			draw_arc(c, s * 0.27, 0.0, TAU, 48, bright, w, true)
			draw_arc(c + Vector2(-s * 0.07, -s * 0.07), s * 0.10, PI, TAU, 16, bright, w * 0.6, true)
		"helmet":
			draw_arc(c + Vector2(0, s * 0.04), s * 0.26, PI, TAU, 32, bright, w, true)
			_seg(c + Vector2(-s * 0.26, s * 0.04), c + Vector2(s * 0.26, s * 0.04), bright, w)
			_seg(c + Vector2(-s * 0.18, s * 0.04), c + Vector2(-s * 0.18, s * 0.16), bright, w)
		"torus":
			draw_arc(c, s * 0.28, 0.0, TAU, 48, bright, w, true)
			draw_arc(c, s * 0.13, 0.0, TAU, 32, bright, w, true)
		"capsule":
			var hw := s * 0.12
			var hh := s * 0.16
			draw_circle(c + Vector2(0, -hh), hw, glow)
			draw_circle(c + Vector2(0, hh), hw, glow)
			draw_rect(Rect2(c.x - hw, c.y - hh, hw * 2.0, hh * 2.0), glow)
			draw_arc(c + Vector2(0, -hh), hw, PI, TAU, 16, bright, w, true)
			draw_arc(c + Vector2(0, hh), hw, 0.0, PI, 16, bright, w, true)
			_seg(c + Vector2(-hw, -hh), c + Vector2(-hw, hh), bright, w)
			_seg(c + Vector2(hw, -hh), c + Vector2(hw, hh), bright, w)
		"prism":
			var pts := PackedVector2Array([
				c + Vector2(0, -s * 0.28), c + Vector2(s * 0.26, s * 0.20),
				c + Vector2(-s * 0.26, s * 0.20)])
			draw_colored_polygon(pts, glow)
			_poly(pts, bright, w)
		_:
			var r := s * 0.24
			_poly(PackedVector2Array([
				c + Vector2(-r, -r), c + Vector2(r, -r),
				c + Vector2(r, r), c + Vector2(-r, r)]), bright, w)


func _chair(c: Vector2, s: float, col: Color, w: float) -> void:
	var seat_y := c.y + s * 0.06
	var lx := c.x - s * 0.17
	var rx := c.x + s * 0.17
	_seg(Vector2(lx, seat_y), Vector2(rx, seat_y), col, w)            # seat
	_seg(Vector2(rx, seat_y), Vector2(rx, c.y - s * 0.30), col, w)    # backrest
	_seg(Vector2(lx, seat_y), Vector2(lx, c.y + s * 0.28), col, w)    # front leg
	_seg(Vector2(rx, seat_y), Vector2(rx, c.y + s * 0.28), col, w)    # back leg


func _seg(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w, true)


func _poly(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts
	closed.append(pts[0])
	draw_polyline(closed, col, w, true)
