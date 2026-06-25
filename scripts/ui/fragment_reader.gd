class_name FragmentReader
extends CanvasLayer
## Non-modal overlay that surfaces a Memory Fragment when one is read. Per the GDD,
## fragments "never interrupt gameplay": this is a corner panel that fades in, holds
## a few seconds, and fades out -- no pause, no input capture. Listens to
## GameEvents.fragment_read and self-builds its UI (no .tscn to maintain).

const ACCENT := Color(0.0, 0.9, 1.0)
const HOLD_SECONDS := 7.0
const FADE_SECONDS := 0.4

## Last fragment shown (for tests / a future codex). {} until the first read.
var last_fragment: Dictionary = {}

var _root: Control
var _header: Label
var _body: Label
var _show_token := 0


func _ready() -> void:
	layer = 3  # above RunHUD (layer 2)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_ui()
	visible = false
	GameEvents.fragment_read.connect(_on_fragment_read)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 48
	panel.offset_right = -48
	panel.offset_top = -190
	panel.offset_bottom = -44
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.07, 0.88)
	style.border_color = ACCENT
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_header = Label.new()
	_header.add_theme_color_override("font_color", ACCENT)
	_header.add_theme_font_size_override("font_size", 16)
	box.add_child(_header)

	_body = Label.new()
	_body.add_theme_color_override("font_color", Color(0.78, 0.88, 0.95))
	_body.add_theme_font_size_override("font_size", 18)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)


func _on_fragment_read(fragment: Dictionary) -> void:
	show_fragment(fragment)


## Display a fragment: set the text, fade in, hold, fade out. A newer fragment
## supersedes an in-flight one (the token guards the awaited fade-out).
func show_fragment(fragment: Dictionary) -> void:
	last_fragment = fragment
	_header.text = String(fragment.get("header", "MEMORY FRAGMENT"))
	_body.text = String(fragment.get("body", ""))
	visible = true
	_root.modulate.a = 0.0
	_show_token += 1
	var token := _show_token
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SECONDS)
	await get_tree().create_timer(FADE_SECONDS + HOLD_SECONDS).timeout
	if token != _show_token:
		return  # a newer fragment took over
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	await out.finished
	if token == _show_token:
		visible = false
