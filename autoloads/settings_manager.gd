extends Node
## User settings singleton: loads/saves user://settings.cfg and applies
## everything live. Graphics apply through DisplayServer/RenderingServer and
## the root viewport; player-specific values (sensitivity, FOV) are pushed
## onto the Player's exported vars whenever one enters the tree, so player.gd
## stays untouched. Control rebinds go through InputMap and persist as
## serialized InputEvents in the config file.

const SAVE_PATH := "user://settings.cfg"
const PLAYER_BASE_SENSITIVITY := 0.0022  # matches the player.gd export default
const SHADOW_ATLAS_SIZES := [0, 1024, 2048, 4096]  # indexed by shadow_quality

## Actions the settings screen exposes for rebinding ("restart" is legacy).
const REBINDABLE_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "crouch", "prone",
	"fire", "ads", "reload",
	"weapon_1", "weapon_2", "weapon_3", "weapon_next", "weapon_prev",
]

# --- Graphics ---
var fullscreen := false
var vsync := true
var render_scale := 1.0   # 3D resolution scale, 0.5 - 1.0
var shadow_quality := 2   # 0 off / 1 low / 2 medium / 3 high
var fov := 75.0

# --- Mouse ---
var mouse_sensitivity := 1.0  # multiplier on the player's base sensitivity


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	apply_graphics()
	# Push player settings onto every Player that spawns, in any scene.
	get_tree().node_added.connect(_on_node_added)


# ---------------------------------------------------------------- setters

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_graphics()
	_save()


func set_vsync(value: bool) -> void:
	vsync = value
	apply_graphics()
	_save()


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	apply_graphics()
	_save()


func set_shadow_quality(value: int) -> void:
	shadow_quality = clampi(value, 0, 3)
	apply_graphics()
	_save()


func set_fov(value: float) -> void:
	fov = clampf(value, 60.0, 100.0)
	apply_player_settings()
	_save()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.2, 3.0)
	apply_player_settings()
	_save()


## Replace an action's bindings with a single new event and persist it.
func rebind_action(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	_save()


func reset_controls() -> void:
	InputMap.load_from_project_settings()
	_save()


## Display text for an action's first binding, e.g. "W (Physical)".
func action_event_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "Unbound"
	return events[0].as_text()


# ---------------------------------------------------------------- apply

func apply_graphics() -> void:
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	get_tree().root.scaling_3d_scale = render_scale
	var atlas: int = SHADOW_ATLAS_SIZES[shadow_quality]
	RenderingServer.directional_shadow_atlas_set_size(maxi(atlas, 256), true)
	match shadow_quality:
		1:
			RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
		2:
			RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		3:
			RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	_apply_shadow_toggle(get_tree().root)
	apply_player_settings()


func apply_player_settings() -> void:
	for player in get_tree().get_nodes_in_group("player"):
		_apply_player(player)


func _apply_player(player: Node) -> void:
	player.set("mouse_sensitivity", PLAYER_BASE_SENSITIVITY * mouse_sensitivity)
	player.set("base_fov", fov)


func _apply_shadow_toggle(node: Node) -> void:
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).shadow_enabled = shadow_quality > 0
	for child in node.get_children():
		_apply_shadow_toggle(child)


func _on_node_added(node: Node) -> void:
	if node is Player:
		# Deferred so the player's own _ready never races the override.
		_apply_player_deferred.call_deferred(node)
	elif node is DirectionalLight3D:
		(node as DirectionalLight3D).shadow_enabled = shadow_quality > 0


func _apply_player_deferred(player: Node) -> void:
	if is_instance_valid(player):
		_apply_player(player)


# ---------------------------------------------------------------- persistence

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "fullscreen", fullscreen)
	config.set_value("graphics", "vsync", vsync)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "shadow_quality", shadow_quality)
	config.set_value("graphics", "fov", fov)
	config.set_value("mouse", "sensitivity", mouse_sensitivity)
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			config.set_value("controls", action, InputMap.action_get_events(action))
	config.save(SAVE_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return  # first run: keep defaults
	fullscreen = bool(config.get_value("graphics", "fullscreen", fullscreen))
	vsync = bool(config.get_value("graphics", "vsync", vsync))
	render_scale = clampf(float(config.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	shadow_quality = clampi(int(config.get_value("graphics", "shadow_quality", shadow_quality)), 0, 3)
	fov = clampf(float(config.get_value("graphics", "fov", fov)), 60.0, 100.0)
	mouse_sensitivity = clampf(float(config.get_value("mouse", "sensitivity", mouse_sensitivity)), 0.2, 3.0)
	if config.has_section("controls"):
		for action in config.get_section_keys("controls"):
			if not InputMap.has_action(action):
				continue
			var events: Variant = config.get_value("controls", action, [])
			if events is Array and not (events as Array).is_empty():
				InputMap.action_erase_events(action)
				for event in events:
					if event is InputEvent:
						InputMap.action_add_event(action, event)
