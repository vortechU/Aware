extends CanvasLayer
## Main HUD: vitals bars, ammo, kill feed, damage vignette, death/end screens.
## Listens to GameEvents only; polls the player just for the crosshair spread.

const KILL_FEED_MAX := 6
const RESPAWN_SECONDS := 3.0

var _vignette_alpha := 0.0
var _respawn_left := 0.0

@onready var health_bar: ProgressBar = $Vitals/HealthBar
@onready var armor_bar: ProgressBar = $Vitals/ArmorBar
@onready var stamina_bar: ProgressBar = $Vitals/StaminaBar
@onready var weapon_label: Label = $AmmoBox/WeaponName
@onready var ammo_label: Label = $AmmoBox/AmmoLabel
@onready var crosshair: Control = $Crosshair
@onready var kill_feed: VBoxContainer = $KillFeed
@onready var vignette: ColorRect = $Vignette
@onready var death_screen: Control = $DeathScreen
@onready var respawn_label: Label = $DeathScreen/Center/Box/RespawnLabel
@onready var end_screen: Control = $EndScreen
@onready var end_title: Label = $EndScreen/Center/Box/EndTitle


func _ready() -> void:
	GameEvents.player_health_changed.connect(_on_health_changed)
	GameEvents.player_armor_changed.connect(_on_armor_changed)
	GameEvents.player_stamina_changed.connect(_on_stamina_changed)
	GameEvents.player_damaged.connect(_on_player_damaged)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.player_respawned.connect(_on_player_respawned)
	GameEvents.ammo_changed.connect(_on_ammo_changed)
	GameEvents.weapon_changed.connect(_on_weapon_changed)
	GameEvents.enemy_killed.connect(_on_enemy_killed)
	GameEvents.game_won.connect(_on_game_won)
	GameEvents.game_lost.connect(_on_game_lost)
	death_screen.visible = false
	end_screen.visible = false


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and not bool(player.get("is_dead")):
		crosshair.set("spread_deg", player.call("get_current_spread_deg"))

	_vignette_alpha = maxf(_vignette_alpha - delta * 0.8, 0.0)
	vignette.color.a = _vignette_alpha

	if death_screen.visible and _respawn_left > 0.0:
		_respawn_left = maxf(_respawn_left - delta, 0.0)
		respawn_label.text = "Respawning in %.1f..." % _respawn_left


# ---------------------------------------------------------------- vitals

func _on_health_changed(health: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = health


func _on_armor_changed(armor: float, max_armor: float) -> void:
	armor_bar.max_value = max_armor
	armor_bar.value = armor


func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina


func _on_player_damaged(amount: float, _source_position: Vector3) -> void:
	_vignette_alpha = clampf(_vignette_alpha + 0.12 + amount * 0.01, 0.0, 0.5)


# ---------------------------------------------------------------- ammo

func _on_ammo_changed(in_mag: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_mag, reserve]


func _on_weapon_changed(weapon_name: String) -> void:
	weapon_label.text = weapon_name


# ---------------------------------------------------------------- kill feed

func _on_enemy_killed(enemy_name: String, headshot: bool, weapon_name: String) -> void:
	var entry := Label.new()
	var text := "[%s]  You  >  %s" % [weapon_name, enemy_name]
	if headshot:
		text += "   HEADSHOT"
		entry.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
	entry.text = text
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.add_theme_font_size_override("font_size", 16)
	kill_feed.add_child(entry)
	kill_feed.move_child(entry, 0)

	while kill_feed.get_child_count() > KILL_FEED_MAX:
		var oldest := kill_feed.get_child(kill_feed.get_child_count() - 1)
		kill_feed.remove_child(oldest)
		oldest.queue_free()

	var tween := entry.create_tween()
	tween.tween_interval(3.2)
	tween.tween_property(entry, "modulate:a", 0.0, 0.8)
	tween.tween_callback(entry.queue_free)


# ---------------------------------------------------------------- screens

func _on_player_died() -> void:
	_respawn_left = RESPAWN_SECONDS
	respawn_label.text = "Respawning in %.1f..." % RESPAWN_SECONDS
	death_screen.visible = true
	crosshair.visible = false


func _on_player_respawned() -> void:
	death_screen.visible = false
	crosshair.visible = true


func _on_game_won() -> void:
	death_screen.visible = false
	crosshair.visible = false
	end_title.text = "VICTORY"
	end_title.add_theme_color_override("font_color", Color(0.45, 0.9, 0.45))
	end_screen.visible = true


func _on_game_lost() -> void:
	death_screen.visible = false
	crosshair.visible = false
	end_title.text = "DEFEAT"
	end_title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.25))
	end_screen.visible = true
