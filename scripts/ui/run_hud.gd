extends CanvasLayer
## Roguelite overlay on its own layer above the base HUD: room counter,
## active-upgrade list, "ROOM CLEARED" banner, upgrade selection screen and
## the permadeath run summary. Listens to RunManager; RunDirector drives the
## banner/choice flow directly and awaits upgrade_chosen.

signal upgrade_chosen(id: String)

const TRANSITION_FADE_SPEED := 3.2  # cover/reveal units per second

# Glitch animation on the upgrade cards: a resting idle shimmer, a stronger
# sustained hover, and a sharp click burst that the card also "glitches out" on.
const GLITCH_IDLE := 0.18
const GLITCH_HOVER := 0.5
const GLITCH_CLICK := 1.0
const GLITCH_CLICK_TIME := 0.32   # seconds a click burst takes to fade

var _choice_ids: Array[String] = []
var _transition_cover := 0.0
var _transition_target := 0.0
var _transition_mat: ShaderMaterial

var _glitch_mat: ShaderMaterial                      # single overlay above the cards
var _glitch_click_t: Array[float] = [0.0, 0.0, 0.0]  # remaining click-burst time per card
var _glitch_hovered: Array[bool] = [false, false, false]

# Active-ability cooldown readout, one entry per slot (driven by the GameEvents
# ability_* signals). The local countdown is just for a smooth sweep; the
# AbilityManager's ready signal re-syncs it to 0, so the two never drift far.
const ABILITY_SLOT_ACTIONS := ["ability", "ability_2"]
var _ability_cd_left: Array[float] = [0.0, 0.0]
var _ability_cd_total: Array[float] = [0.0, 0.0]

@onready var room_label: Label = $RoomLabel
@onready var gate_hint: Label = $GateHint
@onready var transition: ColorRect = $Transition
@onready var upgrade_list: VBoxContainer = $UpgradeList
@onready var banner: Label = $Banner
@onready var upgrade_panel: Control = $UpgradePanel
@onready var glitch_overlay: ColorRect = $UpgradePanel/Glitch
@onready var upgrade_title: Label = $UpgradePanel/Center/Box/Title
@onready var cards: Array[Button] = [
	$UpgradePanel/Center/Box/Cards/Card1,
	$UpgradePanel/Center/Box/Cards/Card2,
	$UpgradePanel/Center/Box/Cards/Card3,
]
@onready var ability_widgets: Array[AbilityWidget] = [
	$AbilityBar/Slot0,
	$AbilityBar/Slot1,
]
@onready var ram_meter: VBoxContainer = $RamMeter
@onready var ram_bar: ProgressBar = $RamMeter/Bar
@onready var run_end_panel: Control = $RunEndPanel
@onready var stats_label: Label = $RunEndPanel/Center/Box/StatsLabel
@onready var try_again_button: Button = $RunEndPanel/Center/Box/Buttons/TryAgain
@onready var quit_button: Button = $RunEndPanel/Center/Box/Buttons/Quit


func _ready() -> void:
	# The upgrade screen and end screen must keep working while the tree is
	# paused for a room transition.
	process_mode = Node.PROCESS_MODE_ALWAYS
	RunManager.run_started.connect(_on_run_started)
	RunManager.room_advanced.connect(_on_room_advanced)
	RunManager.modifiers_changed.connect(_on_modifiers_changed)
	RunManager.run_ended.connect(_on_run_ended)
	GameEvents.ability_granted.connect(_on_ability_granted)
	GameEvents.ability_used.connect(_on_ability_used)
	GameEvents.ability_cooldown_changed.connect(_on_ability_cooldown_changed)
	GameEvents.ram_changed.connect(_on_ram_changed)
	GameEvents.trait_applied.connect(_on_trait_applied)
	for i in cards.size():
		cards[i].pressed.connect(_on_card_pressed.bind(i))
		cards[i].mouse_entered.connect(_on_card_mouse_entered.bind(i))
		cards[i].mouse_exited.connect(_on_card_mouse_exited.bind(i))
		cards[i].button_down.connect(_on_card_button_down.bind(i))
	_glitch_mat = glitch_overlay.material as ShaderMaterial
	_glitch_off()
	try_again_button.pressed.connect(_on_try_again_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_transition_mat = transition.material as ShaderMaterial
	_set_transition_cover(0.0)
	# Defensive init in case start_run() ran before this node was ready.
	_on_room_advanced(RunManager.current_room)
	_on_modifiers_changed(RunManager.current_run_modifiers)
	banner.visible = false
	gate_hint.visible = false
	upgrade_panel.visible = false
	run_end_panel.visible = false
	for w in ability_widgets:
		w.visible = false
	ram_meter.visible = false


func _process(delta: float) -> void:
	# Smoothly bleed each ability cooldown down for the ring sweep (paused-safe: the
	# AbilityManager freezes its own cooldowns during transitions, so we do too).
	if not get_tree().paused:
		for i in ability_widgets.size():
			if ability_widgets[i].visible and _ability_cd_left[i] > 0.0:
				_ability_cd_left[i] = maxf(_ability_cd_left[i] - delta, 0.0)
				_refresh_ability_widget(i)
	_update_glitch(delta)
	if is_equal_approx(_transition_cover, _transition_target):
		return
	_transition_cover = move_toward(_transition_cover, _transition_target,
			delta * TRANSITION_FADE_SPEED)
	_set_transition_cover(_transition_cover)
	if _transition_cover <= 0.001 and _transition_target == 0.0:
		transition.visible = false


# ---------------------------------------------------------------- run state

func _on_run_started() -> void:
	_on_room_advanced(RunManager.current_room)
	_on_modifiers_changed(RunManager.current_run_modifiers)
	banner.visible = false
	gate_hint.visible = false
	upgrade_panel.visible = false
	run_end_panel.visible = false
	# Abilities are per-run: a fresh run starts with no ability equipped.
	for i in ability_widgets.size():
		ability_widgets[i].visible = false
		_ability_cd_left[i] = 0.0
		_ability_cd_total[i] = 0.0
	# Hacking RAM is per-run too: hidden until the first hack of the run.
	ram_meter.visible = false
	_transition_target = 0.0
	_set_transition_cover(0.0)
	transition.visible = false


func _on_room_advanced(room: int) -> void:
	if RunManager.run_mode == RunManager.RunMode.CAMPAIGN:
		# e.g. "HEAP - SECTOR 2"; endless keeps the legacy flat "ROOM N".
		var profile: Dictionary = LayerCatalog.profile_for_room(room)
		room_label.text = "%s - SECTOR %d" % [profile.get("tag", "?"), RunManager.room_in_layer]
	else:
		room_label.text = "ROOM %d" % room


func _on_modifiers_changed(modifiers: Array) -> void:
	for child in upgrade_list.get_children():
		child.queue_free()
	var counts := {}
	for id in modifiers:
		counts[id] = int(counts.get(id, 0)) + 1
	for id in counts:
		var def: Dictionary = RunManager.upgrade_def(id)
		var title: String = def.get("title", id)
		var entry := Label.new()
		entry.text = ("%s x%d" % [title, counts[id]]) if counts[id] > 1 else title
		entry.add_theme_font_size_override("font_size", 15)
		entry.modulate = Color(0.8, 0.9, 1.0, 0.85)
		upgrade_list.add_child(entry)


func _on_run_ended(_won: bool) -> void:
	banner.visible = false
	upgrade_panel.visible = false
	var counts := {}
	for id in RunManager.current_run_modifiers:
		counts[id] = int(counts.get(id, 0)) + 1
	var lines := PackedStringArray([
		"Rooms cleared: %d" % (RunManager.current_room - 1),
		"Enemies killed: %d" % RunManager.enemies_killed,
		"Upgrades collected: %d" % RunManager.current_run_modifiers.size(),
	])
	for id in counts:
		var def: Dictionary = RunManager.upgrade_def(id)
		lines.append("  %s x%d" % [def.get("title", id), counts[id]])
	stats_label.text = "\n".join(lines)
	run_end_panel.visible = true
	for w in ability_widgets:
		w.visible = false
	ram_meter.visible = false


# ---------------------------------------------------------------- hacking RAM

## The hack RAM pool changed; set the bar even while hidden so it reads right on reveal.
func _on_ram_changed(current: float, maximum: float) -> void:
	ram_bar.max_value = maximum
	ram_bar.value = current


## Reveal the RAM meter on the first hack of the run (it stays up for the rest).
func _on_trait_applied(_adjective: String, _rank: int) -> void:
	ram_meter.visible = true


# ---------------------------------------------------------------- abilities

## A slot's ability changed (unlock or rank-up): label it and reveal that widget.
func _on_ability_granted(slot: int, id: String, _rank: int) -> void:
	if slot < 0 or slot >= ability_widgets.size():
		return
	var title := String(RunManager.upgrade_def(id).get("title", id))
	ability_widgets[slot].set_ability(_ability_key_label(slot), title)
	_ability_cd_left[slot] = 0.0
	_ability_cd_total[slot] = 0.0
	ability_widgets[slot].set_cooldown(0.0)
	ability_widgets[slot].visible = true


func _on_ability_used(slot: int, _id: String) -> void:
	if slot >= 0 and slot < ability_widgets.size():
		ability_widgets[slot].pulse()


func _on_ability_cooldown_changed(slot: int, _id: String, remaining: float, total: float) -> void:
	if slot < 0 or slot >= ability_widgets.size():
		return
	_ability_cd_total[slot] = total
	_ability_cd_left[slot] = remaining
	_refresh_ability_widget(slot)


func _refresh_ability_widget(slot: int) -> void:
	var ratio := 0.0
	if _ability_cd_total[slot] > 0.0:
		ratio = clampf(_ability_cd_left[slot] / _ability_cd_total[slot], 0.0, 1.0)
	ability_widgets[slot].set_cooldown(ratio)


## The label for whatever key a slot's action is bound to (tracks rebinds).
func _ability_key_label(slot: int) -> String:
	var action: String = ABILITY_SLOT_ACTIONS[slot] if slot < ABILITY_SLOT_ACTIONS.size() else ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(code)
	return "ABILITY"


# ---------------------------------------------------------------- transitions

func show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true


func hide_banner() -> void:
	banner.visible = false


## Persistent prompt shown while the exit gate is up and the player is free to
## roam for leftover pickups (RunDirector drives it).
func show_hint(text: String) -> void:
	gate_hint.text = text
	gate_hint.visible = true


func hide_hint() -> void:
	gate_hint.visible = false


# ---------------------------------------------------------------- matrix wipe

## Fade the matrix-spiral overlay up to full cover; awaits until it is opaque.
## RunDirector calls this as the player crosses the exit gate, hides the room
## change behind it, then calls reveal() once the new room is built.
func cover() -> void:
	transition.visible = true
	_transition_target = 1.0
	while _transition_cover < 0.999:
		await get_tree().process_frame


## Fade the overlay back out, revealing the freshly built room; awaits the fade.
func reveal() -> void:
	_transition_target = 0.0
	while _transition_cover > 0.001:
		await get_tree().process_frame
	transition.visible = false


func _set_transition_cover(value: float) -> void:
	_transition_cover = value
	if _transition_mat != null:
		_transition_mat.set_shader_parameter("cover", value)


func show_upgrade_choices(choices: Array[Dictionary], title := "CHOOSE AN UPGRADE") -> void:
	upgrade_title.text = title
	_choice_ids.clear()
	for i in cards.size():
		var def := choices[i]
		_choice_ids.append(def.id)
		cards[i].text = "%s\n\n%s" % [def.title, def.desc]
		_glitch_hovered[i] = false
		_glitch_click_t[i] = 0.0
	upgrade_panel.visible = true


# Hide is synchronous: RunDirector hides, applies the pick, and (for milestone
# rooms) re-shows the second card set in the same resume, so this must not defer.
func hide_upgrade_choices() -> void:
	upgrade_panel.visible = false
	for i in cards.size():
		_glitch_hovered[i] = false
		_glitch_click_t[i] = 0.0
	_glitch_off()


# ---------------------------------------------------------------- card glitch
# One overlay above the cards: a resting idle shimmer over the whole card row,
# the hovered card pushed to HOVER, and the just-clicked card spiked to a CLICK
# burst that decays. The shader does the actual animated tearing off TIME.

func _update_glitch(delta: float) -> void:
	if not upgrade_panel.visible or _glitch_mat == null:
		return

	# The hovered or mid-click card becomes the focus; click outranks hover and a
	# single mouse only touches one card at a time, so one focus rect is enough.
	var focus := -1
	var focus_level := 0.0
	for i in cards.size():
		var level := GLITCH_HOVER if _glitch_hovered[i] else 0.0
		if _glitch_click_t[i] > 0.0:
			_glitch_click_t[i] = maxf(_glitch_click_t[i] - delta, 0.0)
			level = maxf(level, GLITCH_CLICK * (_glitch_click_t[i] / GLITCH_CLICK_TIME))
		if level > focus_level:
			focus_level = level
			focus = i

	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var first := cards[0].get_global_rect()
	var last := cards[cards.size() - 1].get_global_rect()
	_glitch_mat.set_shader_parameter("cards_min", first.position / vp)
	_glitch_mat.set_shader_parameter("cards_max", (last.position + last.size) / vp)
	_glitch_mat.set_shader_parameter("base_intensity", GLITCH_IDLE)
	_glitch_mat.set_shader_parameter("focus_intensity", focus_level)
	if focus >= 0:
		var fr := cards[focus].get_global_rect()
		_glitch_mat.set_shader_parameter("focus_rect",
				Vector4(fr.position.x / vp.x, fr.position.y / vp.y,
						(fr.position.x + fr.size.x) / vp.x, (fr.position.y + fr.size.y) / vp.y))


func _glitch_off() -> void:
	if _glitch_mat == null:
		return
	_glitch_mat.set_shader_parameter("base_intensity", 0.0)
	_glitch_mat.set_shader_parameter("focus_intensity", 0.0)


func _on_card_mouse_entered(index: int) -> void:
	_glitch_hovered[index] = true


func _on_card_mouse_exited(index: int) -> void:
	_glitch_hovered[index] = false


func _on_card_button_down(index: int) -> void:
	_glitch_click_t[index] = GLITCH_CLICK_TIME


func _on_card_pressed(index: int) -> void:
	if not upgrade_panel.visible or index >= _choice_ids.size():
		return
	upgrade_chosen.emit(_choice_ids[index])


# ---------------------------------------------------------------- end screen

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
