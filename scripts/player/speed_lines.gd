class_name SpeedLines
extends Node
## Speed-line / wind-streak overlay that kicks in when the player moves fast.
## Build-alongside, the HackManager way: a child of Player that reads the player's
## public `velocity` from the OUTSIDE (no player.gd edit) and owns its own
## CanvasLayer + full-rect ColorRect with the `speed_lines.gdshader` material,
## built in code so it shows in real runs AND the sandbox with no HUD edit.
##
## Horizontal speed maps (smoothstep) to a 0..1 target intensity that the shader
## fades the screen-edge streaks by; the value is temporally smoothed so the
## effect eases in/out rather than popping. Decays to 0 while the tree is paused
## (room transition / upgrade screen) so no streaks linger on a frozen frame.

const SHADER := preload("res://shaders/speed_lines.gdshader")

# --- Speed -> intensity mapping (m/s of horizontal speed) ---
@export var speed_start: float = 7.5   # below this: no streaks (a brisk sprint tops ~8.2)
@export var speed_full: float = 15.0   # at/above this: full intensity (dash 16, max-momentum sprint)

# --- Temporal smoothing (intensity units / sec) ---
@export var rise_rate: float = 6.0     # how fast the effect eases in
@export var fall_rate: float = 4.0     # how fast it eases out

@onready var player: Player = get_parent() as Player

var _intensity: float = 0.0
var _mat: ShaderMaterial = null
var _rect: ColorRect = null


func _ready() -> void:
	# Keep ticking while the tree is paused so the effect decays out cleanly on
	# the (frozen) transition / upgrade screens instead of freezing mid-streak.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()


## The overlay is owned here (built in code, no .tscn / HUD edit) so it travels
## with the player into every context. Layer 0 sits beneath the HUD (layer 1+),
## keeping the crosshair / vitals on top; the streaks live at the edges anyway.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("intensity", 0.0)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(0, 0, 0, 0)
	_rect.material = _mat
	layer.add_child(_rect)
	add_child(layer)


func _process(delta: float) -> void:
	tick(delta)


## Per-frame update, split out so the headless harness can drive it deterministically.
func tick(delta: float) -> void:
	_mat.set_shader_parameter("intensity", _intensity)  # push last frame's value first
	var target := 0.0
	if player != null and player.is_inside_tree() and not get_tree().paused \
			and not bool(player.is_dead):
		target = compute_target(_player_speed())
	var rate := rise_rate if target > _intensity else fall_rate
	_intensity = move_toward(_intensity, target, rate * delta)
	_mat.set_shader_parameter("intensity", _intensity)
	_refresh_aspect()


## Pure speed -> intensity curve (smoothstep ramp between the thresholds). Public
## so the test can assert it without a live viewport.
func compute_target(hspeed: float) -> float:
	return smoothstep(speed_start, speed_full, hspeed)


func current_intensity() -> float:
	return _intensity


func _player_speed() -> float:
	var v: Vector3 = player.velocity
	return Vector2(v.x, v.z).length()


func _refresh_aspect() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size
	if size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)
