extends Node
## Roguelite run state singleton. Tracks the current room, kill count and the
## upgrades taken this run, and decides when a room counts as cleared.
## Scene-side orchestration (spawning, transitions, UI) lives in RunDirector;
## this autoload only owns state and run-level signals. No meta progression:
## start_run() wipes everything, so every run begins fresh.

signal run_started
signal room_cleared
signal run_ended(won: bool)
## Extra signals for the HUD beyond the core three.
signal room_advanced(room: int)
signal modifiers_changed(modifiers: Array)

## ENDLESS is the legacy flat-infinite roguelite (the shipped game, and what every
## existing harness exercises). CAMPAIGN walks the GDD's narrative layers
## (LayerCatalog) toward an ending. Hybrid: endless is preserved as-is; campaign
## is the new path, opted into via `selected_mode` before the main scene loads.
enum RunMode { ENDLESS, CAMPAIGN }

const BASE_ENEMY_COUNT := 5
const EXTRA_ENEMIES_PER_ROOM := 1
const STAT_GAIN_PER_ROOM := 0.10  # +10% enemy health/damage per room
const MILESTONE_INTERVAL := 5     # every Nth room is an elite/milestone room
const MILESTONE_UPGRADE_PICKS := 2
const RUSHER_FIRST_ROOM := 3      # rushers start appearing from this room
const RUSHER_MAX_SHARE := 3.0     # at most ~1/3 of a squad are rushers
const SNIPER_FIRST_ROOM := 4      # snipers start appearing from this room
const SNIPER_MAX := 2             # never more than this many snipers in a room
const GRENADIER_FIRST_ROOM := 5   # grenadiers start appearing from this room
const GRENADIER_MAX := 2          # never more than this many grenadiers in a room

## Upgrade pool. PlayerUpgrades (child of Player) knows how to apply each id.
const UPGRADE_POOL: Array[Dictionary] = [
	{"id": "max_health", "title": "Reinforced Vitals", "desc": "Max health +25"},
	{"id": "move_speed", "title": "Light Feet", "desc": "Move speed +10%"},
	{"id": "damage", "title": "Hollow Points", "desc": "Damage +20%"},
	{"id": "fire_rate", "title": "Hair Trigger", "desc": "Fire rate +15%"},
	{"id": "armor", "title": "Armor Plate", "desc": "+30 armor instantly"},
	{"id": "stamina", "title": "Cardio", "desc": "Max stamina +25"},
	{"id": "health_drop", "title": "Scavenger", "desc": "Kills may drop a health pack"},
	{"id": "ads_speed", "title": "Quickdraw", "desc": "Aim down sights 25% faster"},
	{"id": "stack_smash", "title": "Stack Smash", "kind": "ability",
		"desc": "ABILITY (F): air-slam for an AoE shockwave. Repeat picks rank it up."},
	{"id": "overclock", "title": "Overclock", "kind": "ability",
		"desc": "ABILITY (F): throttle every enemy into slow-motion. Repeat picks rank it up."},
	{"id": "heavy", "title": "Heavier", "kind": "trait",
		"desc": "HACK (V): rank up Heavy -- more mass & crush. Grants it if you haven't."},
	{"id": "shocking", "title": "More Shocking", "kind": "trait",
		"desc": "HACK (V): rank up Shocking -- stronger zaps. Grants it if you haven't."},
]

var current_room := 1
var enemies_killed := 0
var run_active := false
var current_run_modifiers: Array = []  # upgrade ids, one entry per stack taken
## Seed for procedural room layouts; RoomBuilder derives a per-room RNG from
## hash([run_seed, room]) so a whole run is reproducible from one number.
var run_seed := 0

## Chosen by the menu/lobby (or a test) BEFORE main.tscn loads; start_run() copies
## it into the active run_mode. Defaults to ENDLESS so the legacy flow and every
## existing harness behave exactly as before until campaign is explicitly picked.
var selected_mode := RunMode.ENDLESS
var run_mode := RunMode.ENDLESS
## CAMPAIGN-only view over current_room: which narrative layer (1..N) and which
## room within it (the "sector", 1..room_count). ENDLESS leaves both at 0.
var current_layer := 0
var room_in_layer := 0

var _alive_in_room := 0


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)


## Reset all run state. Called by RunDirector when the main scene (re)loads.
func start_run() -> void:
	run_mode = selected_mode
	current_room = 1
	enemies_killed = 0
	current_run_modifiers = []
	_alive_in_room = 0
	run_seed = randi()
	_sync_layer_state()
	print("[RunManager] run seed: ", run_seed, " mode: ", RunMode.keys()[run_mode])
	run_active = true
	run_started.emit()
	room_advanced.emit(current_room)
	modifiers_changed.emit(current_run_modifiers)


## RunDirector reports how many enemies the room started with.
func register_room_enemies(count: int) -> void:
	_alive_in_room = count


## RunDirector reports each enemy death; the last one clears the room.
func notify_enemy_dead() -> void:
	if not run_active:
		return
	enemies_killed += 1
	_alive_in_room -= 1
	GameEvents.enemies_remaining_changed.emit(maxi(_alive_in_room, 0))
	if _alive_in_room <= 0:
		room_cleared.emit()


func advance_room() -> void:
	current_room += 1
	_sync_layer_state()
	room_advanced.emit(current_room)


## Derive the layer/sector view from current_room (CAMPAIGN only). The global
## room counter is the source of truth in both modes; this is just a named window
## over it, so nothing in the existing scaling/spawn logic has to change.
func _sync_layer_state() -> void:
	if run_mode == RunMode.CAMPAIGN:
		current_layer = LayerCatalog.layer_index_for_room(current_room)
		room_in_layer = LayerCatalog.room_in_layer_for_room(current_room)
	else:
		current_layer = 0
		room_in_layer = 0


## The LayerProfile to flavour the current room's generation with, or {} in
## ENDLESS mode (RoomBuilder treats {} as "no re-skin", i.e. legacy behaviour).
func active_layer_profile() -> Dictionary:
	if run_mode == RunMode.CAMPAIGN:
		return LayerCatalog.profile_for_room(current_room)
	return {}


## Kind of the current room (combat vs a non-combat breather). ENDLESS is always
## COMBAT, so the legacy loop is unaffected; CAMPAIGN reads the layer's sequence.
func current_room_type() -> int:
	if run_mode == RunMode.CAMPAIGN:
		return LayerCatalog.room_type_for(current_room)
	return LayerCatalog.RoomType.COMBAT


func record_upgrade(id: String) -> void:
	current_run_modifiers.append(id)
	modifiers_changed.emit(current_run_modifiers)


## Milestone rooms swap the regular squad for one elite plus a guard escort.
## CAMPAIGN has no every-5th milestones: narrative layers gate progress with their
## own layer-end rooms instead (Proving Grounds returns as a later-pass layer boss),
## so the Heap stays a cohesive opening rather than a red elite arena at room 5.
func is_milestone_room(room: int) -> bool:
	if run_mode == RunMode.CAMPAIGN:
		return false
	return room >= MILESTONE_INTERVAL and room % MILESTONE_INTERVAL == 0


func enemy_count_for_room(room: int) -> int:
	if is_milestone_room(room):
		return 1 + elite_guard_count(room)
	return BASE_ENEMY_COUNT + EXTRA_ENEMIES_PER_ROOM * (room - 1)


## Guards accompanying the elite: half the regular squad, rounded up.
func elite_guard_count(room: int) -> int:
	return ceili(float(BASE_ENEMY_COUNT + EXTRA_ENEMIES_PER_ROOM * (room - 1)) / 2.0)


## How many of a normal room's squad are aggressive "Rusher" enemies (close fast,
## fight at point-blank). None before RUSHER_FIRST_ROOM and none in milestone
## rooms (those are elite showcases). The count ramps with depth but is capped to
## a fraction of the squad so a room is never all rushers. Deterministic (depends
## only on the room number) so the spawn is reproducible and easy to test.
func rusher_count_for_room(room: int) -> int:
	if is_milestone_room(room) or room < RUSHER_FIRST_ROOM:
		return 0
	var squad := enemy_count_for_room(room)
	var by_depth := 1 + (room - RUSHER_FIRST_ROOM) / 3  # +1 every 3 rooms (int div)
	return clampi(by_depth, 1, maxi(1, int(float(squad) / RUSHER_MAX_SHARE)))


## How many of a normal room's squad are long-range Snipers. Rarer and later than
## rushers: none before SNIPER_FIRST_ROOM or in milestone rooms, +1 every 6 rooms,
## hard-capped at SNIPER_MAX. Deterministic (depends only on the room number).
func sniper_count_for_room(room: int) -> int:
	if is_milestone_room(room) or room < SNIPER_FIRST_ROOM:
		return 0
	return clampi(1 + (room - SNIPER_FIRST_ROOM) / 6, 1, SNIPER_MAX)


## How many of a normal room's squad are Grenadiers (lob arcing grenades to flush
## the player out of cover). The last archetype to appear: none before
## GRENADIER_FIRST_ROOM or in milestone rooms, +1 every 7 rooms, hard-capped at
## GRENADIER_MAX. Deterministic (depends only on the room number).
func grenadier_count_for_room(room: int) -> int:
	if is_milestone_room(room) or room < GRENADIER_FIRST_ROOM:
		return 0
	return clampi(1 + (room - GRENADIER_FIRST_ROOM) / 7, 1, GRENADIER_MAX)


## Clearing a milestone room is rewarded with extra upgrade picks.
func upgrade_picks_for_room(room: int) -> int:
	return MILESTONE_UPGRADE_PICKS if is_milestone_room(room) else 1


func enemy_stat_multiplier(room: int) -> float:
	return 1.0 + STAT_GAIN_PER_ROOM * float(room - 1)


## Three distinct random upgrades for the selection screen.
func roll_upgrade_choices(count := 3) -> Array[Dictionary]:
	var pool := UPGRADE_POOL.duplicate()
	pool.shuffle()
	var choices: Array[Dictionary] = []
	for i in mini(count, pool.size()):
		choices.append(pool[i])
	return choices


func upgrade_def(id: String) -> Dictionary:
	for def in UPGRADE_POOL:
		if def.id == id:
			return def
	return {}


func _on_player_died() -> void:
	if not run_active:
		return
	run_active = false
	run_ended.emit(false)
