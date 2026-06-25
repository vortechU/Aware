extends Control
## Main menu: PLAY / SETTINGS / QUIT plus a tabbed settings screen
## (Graphics / Controls / Mouse). All widgets read from and write through the
## SettingsManager autoload, which applies and persists every change
## immediately. Control rows are built in code from the rebindable action list.

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const SANDBOX_SCENE := "res://scenes/ui/sandbox.tscn"

const ACTION_LABELS := [
	["move_forward", "Move Forward"],
	["move_back", "Move Back"],
	["move_left", "Move Left"],
	["move_right", "Move Right"],
	["jump", "Jump"],
	["sprint", "Sprint"],
	["crouch", "Crouch"],
	["prone", "Prone"],
	["fire", "Fire"],
	["ads", "Aim Down Sights"],
	["reload", "Reload"],
	["weapon_1", "Weapon 1"],
	["weapon_2", "Weapon 2"],
	["weapon_3", "Weapon 3"],
	["weapon_next", "Next Weapon"],
	["weapon_prev", "Previous Weapon"],
]

var _rebind_action := ""
var _bind_buttons := {}  # action -> Button

@onready var menu_root: Control = $MenuRoot
@onready var play_button: Button = $MenuRoot/Center/Buttons/PlayBtn
@onready var test_map_button: Button = $MenuRoot/Center/Buttons/TestMapBtn
@onready var settings_button: Button = $MenuRoot/Center/Buttons/SettingsBtn
@onready var quit_button: Button = $MenuRoot/Center/Buttons/QuitBtn
@onready var settings_panel: Control = $SettingsPanel
@onready var back_button: Button = $SettingsPanel/Margin/VBox/BackBtn

@onready var fullscreen_check: CheckButton = $SettingsPanel/Margin/VBox/Tabs/Graphics/FullscreenCheck
@onready var vsync_check: CheckButton = $SettingsPanel/Margin/VBox/Tabs/Graphics/VsyncCheck
@onready var scale_slider: HSlider = $SettingsPanel/Margin/VBox/Tabs/Graphics/ScaleRow/ScaleSlider
@onready var scale_value: Label = $SettingsPanel/Margin/VBox/Tabs/Graphics/ScaleRow/ScaleValue
@onready var shadow_option: OptionButton = $SettingsPanel/Margin/VBox/Tabs/Graphics/ShadowRow/ShadowOption
@onready var fov_slider: HSlider = $SettingsPanel/Margin/VBox/Tabs/Graphics/FovRow/FovSlider
@onready var fov_value: Label = $SettingsPanel/Margin/VBox/Tabs/Graphics/FovRow/FovValue
@onready var bind_list: VBoxContainer = $SettingsPanel/Margin/VBox/Tabs/Controls/BindScroll/BindList
@onready var reset_binds_button: Button = $SettingsPanel/Margin/VBox/Tabs/Controls/ResetBinds
@onready var sens_slider: HSlider = $SettingsPanel/Margin/VBox/Tabs/Mouse/SensRow/SensSlider
@onready var sens_value: Label = $SettingsPanel/Margin/VBox/Tabs/Mouse/SensRow/SensValue


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # back from a captured-mouse run
	play_button.pressed.connect(_on_play_pressed)
	test_map_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SANDBOX_SCENE))
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	back_button.pressed.connect(_on_back_pressed)

	fullscreen_check.toggled.connect(func(on: bool) -> void: SettingsManager.set_fullscreen(on))
	vsync_check.toggled.connect(func(on: bool) -> void: SettingsManager.set_vsync(on))
	scale_slider.value_changed.connect(_on_scale_changed)
	shadow_option.item_selected.connect(func(index: int) -> void: SettingsManager.set_shadow_quality(index))
	fov_slider.value_changed.connect(_on_fov_changed)
	sens_slider.value_changed.connect(_on_sensitivity_changed)
	reset_binds_button.pressed.connect(_on_reset_binds_pressed)

	for option in ["Off", "Low", "Medium", "High"]:
		shadow_option.add_item(option)
	_build_bind_list()
	_sync_widgets()


## Reflect the current SettingsManager state into every widget.
func _sync_widgets() -> void:
	fullscreen_check.set_pressed_no_signal(SettingsManager.fullscreen)
	vsync_check.set_pressed_no_signal(SettingsManager.vsync)
	scale_slider.set_value_no_signal(SettingsManager.render_scale)
	scale_value.text = "%d%%" % roundi(SettingsManager.render_scale * 100.0)
	shadow_option.select(SettingsManager.shadow_quality)
	fov_slider.set_value_no_signal(SettingsManager.fov)
	fov_value.text = "%d" % roundi(SettingsManager.fov)
	sens_slider.set_value_no_signal(SettingsManager.mouse_sensitivity)
	sens_value.text = "%.2f" % SettingsManager.mouse_sensitivity
	_refresh_bind_buttons()


# ---------------------------------------------------------------- navigation

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_settings_pressed() -> void:
	_sync_widgets()
	menu_root.visible = false
	settings_panel.visible = true


func _on_back_pressed() -> void:
	_cancel_rebind()
	settings_panel.visible = false
	menu_root.visible = true


# ---------------------------------------------------------------- graphics / mouse

func _on_scale_changed(value: float) -> void:
	SettingsManager.set_render_scale(value)
	scale_value.text = "%d%%" % roundi(value * 100.0)


func _on_fov_changed(value: float) -> void:
	SettingsManager.set_fov(value)
	fov_value.text = "%d" % roundi(value)


func _on_sensitivity_changed(value: float) -> void:
	SettingsManager.set_mouse_sensitivity(value)
	sens_value.text = "%.2f" % value


# ---------------------------------------------------------------- key binds

func _build_bind_list() -> void:
	for pair in ACTION_LABELS:
		var action: String = pair[0]
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = pair[1]
		name_label.custom_minimum_size = Vector2(240, 0)
		row.add_child(name_label)
		var bind_button := Button.new()
		bind_button.custom_minimum_size = Vector2(240, 34)
		bind_button.pressed.connect(_on_bind_button_pressed.bind(action))
		row.add_child(bind_button)
		bind_list.add_child(row)
		_bind_buttons[action] = bind_button
	_refresh_bind_buttons()


func _refresh_bind_buttons() -> void:
	for action in _bind_buttons:
		(_bind_buttons[action] as Button).text = SettingsManager.action_event_text(action)


func _on_bind_button_pressed(action: String) -> void:
	_cancel_rebind()
	_rebind_action = action
	(_bind_buttons[action] as Button).text = "Press a key or mouse button..."


func _on_reset_binds_pressed() -> void:
	_cancel_rebind()
	SettingsManager.reset_controls()
	_refresh_bind_buttons()


func _cancel_rebind() -> void:
	_rebind_action = ""
	_refresh_bind_buttons()


## Capture the next key / mouse button while a rebind is armed; ESC cancels.
func _input(event: InputEvent) -> void:
	if _rebind_action.is_empty():
		return
	var captured: InputEvent = null
	if event is InputEventKey and event.pressed:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_cancel_rebind()
			get_viewport().set_input_as_handled()
			return
		captured = event
	elif event is InputEventMouseButton and event.pressed:
		captured = event
	if captured != null:
		SettingsManager.rebind_action(_rebind_action, captured)
		_rebind_action = ""
		_refresh_bind_buttons()
		get_viewport().set_input_as_handled()
