class_name HackWheel
extends Control
## The radial adjective selector -- the "autocomplete terminal" skin over a hold-to-open
## wheel. Asset-free custom drawing (no textures), owned + driven by the HackManager
## (open / set_index / set_ram / close). The look needs a real renderer, so it's eyeballed
## in play, like the AbilityWidget ring; the selection STATE machine lives in HackManager
## and is what the smoke test asserts.

const RADIUS := 150.0

var _open := false
var _names: PackedStringArray = []
var _index := 0
var _ram := 1.0


func _ready() -> void:
	visible = false
	resized.connect(queue_redraw)


func open_wheel(names: PackedStringArray, index: int, ram_ratio: float) -> void:
	_names = names
	_index = index
	_ram = ram_ratio
	_open = true
	visible = true
	queue_redraw()


func set_index(index: int) -> void:
	_index = index
	queue_redraw()


func set_ram(ram_ratio: float) -> void:
	if is_equal_approx(ram_ratio, _ram):
		return
	_ram = ram_ratio
	queue_redraw()


func close_wheel() -> void:
	_open = false
	visible = false
	queue_redraw()


func _draw() -> void:
	if not _open or _names.is_empty():
		return
	var center := size * 0.5
	var font := ThemeDB.fallback_font

	# Backdrop ring + a RAM arc that depletes clockwise from the top.
	draw_arc(center, RADIUS, 0.0, TAU, 64, Color(0.5, 0.8, 1.0, 0.22), 3.0, true)
	if _ram > 0.0:
		draw_arc(center, RADIUS + 10.0, -PI / 2.0, -PI / 2.0 + TAU * _ram, 64,
				Color(0.2, 0.72, 1.0, 0.8), 4.0, true)

	var step := TAU / float(_names.size())
	for i in _names.size():
		var ang := -PI / 2.0 + i * step  # top, clockwise
		var pos := center + Vector2(cos(ang), sin(ang)) * RADIUS
		var selected := i == _index
		if selected:
			draw_circle(pos, 28.0, Color(0.2, 0.6, 0.9, 0.4))
		var col := Color(0.6, 1.0, 1.0) if selected else Color(0.72, 0.82, 0.95, 0.7)
		var label: String = _names[i]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, pos - Vector2(w * 0.5, -7.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)

	# Center "terminal" readout -- the autocomplete skin over the picked wedge.
	var readout := "> %s_" % String(_names[_index]).to_upper()
	var rw := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(font, center - Vector2(rw * 0.5, -8.0), readout,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 1.0, 0.7))
