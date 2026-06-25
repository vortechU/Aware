class_name AbilityWidget
extends Control
## A small radial cooldown indicator for the player's equipped active ability.
## Self-contained and asset-free: the ring is custom-drawn (no textures), so it has
## no external dependencies. RunHUD owns it and feeds it from the GameEvents
## ability_* signals; the widget itself knows nothing about the AbilityManager. It
## stays hidden until an ability is granted.

const RING_RADIUS := 30.0
const BG_COLOR := Color(0.10, 0.12, 0.18, 0.85)
const FILL_READY := Color(0.30, 0.95, 0.55, 0.85)     # bright when ready to cast
const FILL_CHARGING := Color(0.35, 0.60, 0.95, 0.80)  # the pie that fills as it cools
const RING_OUTLINE := Color(0.75, 0.85, 1.0, 0.90)

var _fill := 0.0          # 1.0 = just cast (ring empty), 0.0 = fully charged / ready
var _ready_state := true
var _flash := 0.0         # brief brighten pulse on cast

@onready var key_label: Label = $KeyLabel
@onready var title_label: Label = $TitleLabel


func _ready() -> void:
	resized.connect(queue_redraw)  # re-centre the ring when the container lays us out


func set_ability(key: String, title: String) -> void:
	key_label.text = key
	title_label.text = title
	queue_redraw()


## ratio: 1.0 right after a cast, falling to 0.0 when the ability is ready again.
func set_cooldown(ratio: float) -> void:
	_fill = clampf(ratio, 0.0, 1.0)
	_ready_state = _fill <= 0.001
	key_label.modulate = Color(1, 1, 1, 1) if _ready_state else Color(0.70, 0.78, 0.90, 0.8)
	queue_redraw()


func pulse() -> void:
	_flash = 1.0


func is_ability_ready() -> bool:
	return _ready_state


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		modulate = Color(1, 1, 1).lerp(Color(1.6, 1.6, 1.6), _flash)


func _draw() -> void:
	# Centre the ring horizontally so the widget works at any container width.
	var center := Vector2(maxf(size.x * 0.5, RING_RADIUS), RING_RADIUS)
	draw_circle(center, RING_RADIUS, BG_COLOR)
	if _ready_state:
		draw_circle(center, RING_RADIUS, FILL_READY)
	else:
		# A pie that grows from nothing (just cast) up to the full disk (ready).
		_draw_pie(center, RING_RADIUS, 1.0 - _fill, FILL_CHARGING)
	draw_arc(center, RING_RADIUS, 0.0, TAU, 64, RING_OUTLINE, 2.0, true)


func _draw_pie(center: Vector2, radius: float, fraction: float, color: Color) -> void:
	if fraction <= 0.0:
		return
	var sweep := TAU * clampf(fraction, 0.0, 1.0)
	var steps := maxi(3, int(48.0 * fraction))
	var start := -PI / 2.0  # 12 o'clock
	var pts := PackedVector2Array()
	pts.append(center)
	for i in steps + 1:
		var a := start + sweep * (float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, color)
