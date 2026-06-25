extends Node
## Global audio system. A sibling observer like SettingsManager: it never edits
## the base gameplay scripts, it only listens to the autoload signal buses
## (GameEvents / RunManager / MetaProgression) and plays the mapped sound.
##
## Sounds live under res://audio/ and are referenced by logical KEY through the
## STREAMS registry below. A key whose file is missing simply does not play, so
## the whole system is silent-but-wired until real audio files are dropped in --
## no code change is needed when they arrive (drop file -> let Godot import it
## -> it plays). The registry doubles as the canonical "sounds wanted" list.
##
## Mixing goes through four runtime buses: Master -> {Music, SFX, UI}. Volumes
## persist to user://audio.cfg (kept separate from settings.cfg on purpose).
##
## Headless guard: under --headless the manager goes fully inert so the smoke
## harnesses stay green and fast.

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"

const CONFIG_PATH := "user://audio.cfg"

## Accepted file extensions, probed in order. Store registry paths WITHOUT an
## extension so any of these formats can be dropped in interchangeably.
const EXTS := [".ogg", ".wav", ".mp3"]

## logical key -> res:// base path (no extension). This is the wishlist: every
## entry is one sound file you can provide. "[live]" entries are already wired
## to a trigger; the rest load if present but are hooked in a later pass.
const STREAMS := {
	# --- weapons (SFX bus) ---
	"pistol_fire": "res://audio/sfx/weapons/pistol_fire",        # [live] player fires pistol
	"rifle_fire": "res://audio/sfx/weapons/rifle_fire",          # [live] player fires rifle (auto)
	"shotgun_fire": "res://audio/sfx/weapons/shotgun_fire",      # [live] player fires shotgun
	"enemy_fire": "res://audio/sfx/weapons/enemy_fire",          # [live] any enemy gunshot (3D)
	"weapon_switch": "res://audio/sfx/weapons/weapon_switch",    # [live] swap weapons
	"reload": "res://audio/sfx/weapons/reload",                  # later: reload start
	"dry_fire": "res://audio/sfx/weapons/dry_fire",              # later: empty-mag click
	# --- impacts / hit feedback (SFX bus) ---
	"hitmarker": "res://audio/sfx/impacts/hitmarker",            # [live] shot connects (body)
	"headshot": "res://audio/sfx/impacts/headshot",              # [live] shot connects (head)
	"bullet_impact": "res://audio/sfx/impacts/bullet_impact",    # later: round hits geometry
	# --- enemies (SFX bus) ---
	"enemy_death": "res://audio/sfx/enemies/enemy_death",        # [live] an enemy dies (3D)
	"enemy_alert": "res://audio/sfx/enemies/enemy_alert",        # later: enemy spots player
	# --- player (SFX bus) ---
	"player_hurt": "res://audio/sfx/player/player_hurt",         # [live] player takes damage
	"player_death": "res://audio/sfx/player/player_death",       # [live] player dies
	"low_health": "res://audio/sfx/player/low_health",           # [live] crosses low-HP threshold
	"footstep": "res://audio/sfx/player/footstep",               # later: movement
	"jump": "res://audio/sfx/player/jump",                       # later: jump
	"land": "res://audio/sfx/player/land",                       # later: landing
	"dash": "res://audio/sfx/player/dash",                       # later: dash burst
	"slide": "res://audio/sfx/player/slide",                     # later: slide start
	# --- pickups (SFX bus) ---
	"pickup_ammo": "res://audio/sfx/pickups/pickup_ammo",        # later: ammo crate
	"pickup_health": "res://audio/sfx/pickups/pickup_health",    # later: health pack
	"pickup_armor": "res://audio/sfx/pickups/pickup_armor",      # later: armor pack
	"core_gained": "res://audio/sfx/pickups/core_gained",        # [live] meta currency gained
	# --- ui / run flow (UI bus) ---
	"ui_click": "res://audio/ui/ui_click",                       # later: menu button press
	"ui_hover": "res://audio/ui/ui_hover",                       # later: menu hover
	"run_start": "res://audio/ui/run_start",                     # [live] a run begins
	"room_cleared": "res://audio/ui/room_cleared",               # [live] room cleared jingle
	"upgrade_select": "res://audio/ui/upgrade_select",           # later: pick an upgrade
	# --- music / stings (Music bus) ---
	"victory": "res://audio/music/victory",                      # [live] run won / game won
	"defeat": "res://audio/music/defeat",                        # [live] run lost / game lost
	"music_menu": "res://audio/music/menu",                      # later: looping menu track
	"music_combat": "res://audio/music/combat",                  # later: looping combat track
}

## How quiet two end-of-run stings can land before we treat them as one event
## (player_died -> run_ended can both fire within a frame or two).
const END_STING_DEBOUNCE_MS := 1500
## Fraction of max health that arms / disarms the low-health warning (hysteresis).
const LOW_HEALTH_ENTER := 0.25
const LOW_HEALTH_EXIT := 0.35

# --- volumes (0..1 linear), persisted ---
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 1.0
var ui_volume := 0.9

var _enabled := true
var _streams := {}
var _player: Node3D = null
var _current_weapon_key := "pistol"
var _low_health_armed := false
var _last_end_sting_ms := -100000


func _ready() -> void:
	# ALWAYS so room-cleared / UI / end stings still play while RunDirector has
	# the tree paused during transitions and the upgrade screen.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# No audio device under --headless: stay completely inert for the harnesses.
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return

	_ensure_buses()
	_load_volumes()
	_apply_all_volumes()
	_load_streams()
	_connect_signals()


# ---------------------------------------------------------------- buses

func _ensure_buses() -> void:
	# Master (index 0) always exists; add the three sub-buses if missing.
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_UI)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)


func _apply_all_volumes() -> void:
	_apply_bus_volume(BUS_MASTER, master_volume)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_apply_bus_volume(BUS_UI, ui_volume)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


# ---------------------------------------------------------------- stream registry

func _load_streams() -> void:
	for key in STREAMS:
		var base: String = STREAMS[key]
		_streams[key] = _try_load(base)


## Probe the accepted extensions; return the first importable stream, else null.
func _try_load(base_path: String) -> AudioStream:
	for ext in EXTS:
		var path: String = base_path + ext
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is AudioStream:
				return res
	return null


# ---------------------------------------------------------------- playback

## Non-positional one-shot (player-centric feedback, UI, stings).
func _play_2d(key: String, bus: String, pitch_var := 0.0) -> void:
	if not _enabled:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	if pitch_var > 0.0:
		p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Positional one-shot at a world point (enemy gunfire, enemy deaths).
func _play_3d(key: String, world_pos: Vector3, bus: String, pitch_var := 0.0) -> void:
	if not _enabled:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.max_distance = 60.0
	p.unit_size = 10.0
	if pitch_var > 0.0:
		p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- signal wiring

func _connect_signals() -> void:
	GameEvents.sound_emitted.connect(_on_sound_emitted)
	GameEvents.hit_confirmed.connect(_on_hit_confirmed)
	GameEvents.weapon_changed.connect(_on_weapon_changed)
	GameEvents.player_damaged.connect(_on_player_damaged)
	GameEvents.player_health_changed.connect(_on_player_health_changed)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.player_respawned.connect(_on_player_respawned)
	GameEvents.game_won.connect(_on_game_won)
	GameEvents.game_lost.connect(_on_game_lost)

	RunManager.run_started.connect(_on_run_started)
	RunManager.room_cleared.connect(_on_room_cleared)
	RunManager.run_ended.connect(_on_run_ended)

	MetaProgression.cores_changed.connect(_on_cores_changed)

	# Positional enemy death: hook each enemy as it enters the tree, mirroring
	# SettingsManager's node_added approach so enemy_ai.gd stays untouched.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is EnemyAI:
		(node as EnemyAI).enemy_died.connect(_on_enemy_died, CONNECT_ONE_SHOT)


# ---------------------------------------------------------------- handlers

func _on_sound_emitted(position: Vector3, _radius: float) -> void:
	# sound_emitted fires for both the player's gun and every enemy's gun, with
	# no weapon type. The player's own shot originates at the player's position,
	# so anything essentially on top of the player is "us"; everything else is
	# an enemy out in the world.
	var pl := _player_node()
	if pl != null and position.distance_to(pl.global_position) < 1.5:
		_play_2d(_current_weapon_key + "_fire", BUS_SFX, 0.05)
	else:
		_play_3d("enemy_fire", position, BUS_SFX, 0.06)


func _on_hit_confirmed(headshot: bool, _killed: bool) -> void:
	_play_2d("headshot" if headshot else "hitmarker", BUS_SFX)


func _on_weapon_changed(weapon_name: String) -> void:
	_current_weapon_key = weapon_name.to_lower()
	_play_2d("weapon_switch", BUS_SFX)


func _on_player_damaged(_amount: float, _source_position: Vector3) -> void:
	_play_2d("player_hurt", BUS_SFX, 0.06)


func _on_player_health_changed(health: float, max_health: float) -> void:
	if max_health <= 0.0:
		return
	var frac := health / max_health
	if not _low_health_armed and frac <= LOW_HEALTH_ENTER and health > 0.0:
		_low_health_armed = true
		_play_2d("low_health", BUS_SFX)
	elif _low_health_armed and frac >= LOW_HEALTH_EXIT:
		_low_health_armed = false


func _on_player_died() -> void:
	_play_2d("player_death", BUS_SFX)


func _on_player_respawned() -> void:
	_low_health_armed = false


func _on_enemy_died(enemy: EnemyAI) -> void:
	if is_instance_valid(enemy):
		_play_3d("enemy_death", enemy.global_position, BUS_SFX, 0.05)


func _on_run_started() -> void:
	_play_ui("run_start")


func _on_room_cleared() -> void:
	_play_ui("room_cleared")


func _on_run_ended(won: bool) -> void:
	_end_sting(won)


func _on_game_won() -> void:
	_end_sting(true)


func _on_game_lost() -> void:
	_end_sting(false)


func _on_cores_changed(_total: int) -> void:
	_play_2d("core_gained", BUS_SFX)


# ---------------------------------------------------------------- helpers

func _play_ui(key: String) -> void:
	_play_2d(key, BUS_UI)


## Victory/defeat sting with debounce so a death that also ends the run does not
## stack two stings on top of each other.
func _end_sting(won: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_end_sting_ms < END_STING_DEBOUNCE_MS:
		return
	_last_end_sting_ms = now
	_play_2d("victory" if won else "defeat", BUS_MUSIC)


func _player_node() -> Node3D:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# ---------------------------------------------------------------- public volume API
# Called by the settings UI in a later pass; 0..1 linear, persisted immediately.

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_MASTER, master_volume)
	_save_volumes()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_save_volumes()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_save_volumes()


func set_ui_volume(value: float) -> void:
	ui_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_UI, ui_volume)
	_save_volumes()


# ---------------------------------------------------------------- persistence

func _save_volumes() -> void:
	var config := ConfigFile.new()
	config.set_value("volume", "master", master_volume)
	config.set_value("volume", "music", music_volume)
	config.set_value("volume", "sfx", sfx_volume)
	config.set_value("volume", "ui", ui_volume)
	config.save(CONFIG_PATH)


func _load_volumes() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return  # first run: keep defaults
	master_volume = clampf(float(config.get_value("volume", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("volume", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("volume", "sfx", sfx_volume)), 0.0, 1.0)
	ui_volume = clampf(float(config.get_value("volume", "ui", ui_volume)), 0.0, 1.0)
