extends Control
## Dynamic crosshair: gap expands with the player's current weapon spread
## (movement + bloom + recoil). Also draws the hit marker.

var spread_deg := 2.0

var _marker_left := 0.0
var _marker_color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameEvents.hit_confirmed.connect(_on_hit_confirmed)


func _on_hit_confirmed(headshot: bool, killed: bool) -> void:
	_marker_left = 0.16
	_marker_color = Color(1.0, 0.85, 0.2) if headshot else Color.WHITE
	if killed:
		_marker_color = Color(1.0, 0.25, 0.2)


func _process(delta: float) -> void:
	_marker_left = maxf(_marker_left - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var gap := minf(5.0 + spread_deg * 7.0, 90.0)
	var line_len := 9.0
	var col := Color(1.0, 1.0, 1.0, 0.9)

	draw_circle(c, 1.4, col)
	draw_line(c + Vector2(0, -gap), c + Vector2(0, -gap - line_len), col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + line_len), col, 2.0)
	draw_line(c + Vector2(-gap, 0), c + Vector2(-gap - line_len, 0), col, 2.0)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + line_len, 0), col, 2.0)

	if _marker_left > 0.0:
		var m := _marker_color
		m.a = clampf(_marker_left / 0.16, 0.0, 1.0)
		var inner := 5.0
		var outer := 13.0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var dirv := Vector2(sx, sy)
				draw_line(c + dirv * inner, c + dirv * outer, m, 2.0)
