extends Control
## Red arcs around the screen center pointing toward where damage came from.

const LIFETIME := 1.6
const RADIUS := 72.0

var _hits: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameEvents.player_damaged.connect(_on_player_damaged)


func _on_player_damaged(_amount: float, source_position: Vector3) -> void:
	_hits.append({"pos": source_position, "t": LIFETIME})


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for h in _hits:
		h.t -= delta
	_hits = _hits.filter(func(h: Dictionary) -> bool: return h.t > 0.0)
	queue_redraw()


func _draw() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var center := size / 2.0
	for h in _hits:
		var to: Vector3 = h.pos - player.global_position
		if Vector2(to.x, to.z).length_squared() < 0.01:
			continue
		var threat_yaw := atan2(-to.x, -to.z)
		var delta_ang := wrapf(threat_yaw - player.rotation.y, -PI, PI)
		var theta := -delta_ang - PI / 2.0
		var alpha: float = clampf(h.t / LIFETIME, 0.0, 1.0)
		draw_arc(center, RADIUS, theta - 0.35, theta + 0.35, 12,
				Color(1.0, 0.2, 0.15, alpha), 5.0, true)
