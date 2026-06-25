extends Node
## Persistent meta-progression singleton: Cores currency plus permanent
## upgrade levels, saved to user://meta_progress.cfg (same ConfigFile pattern
## as SettingsManager). Sits alongside the run system without touching it:
## Cores are awarded by listening to RunManager.run_ended, and the permanent
## bonuses are pushed onto the Player's exported vars via the same node_added
## hook pattern SettingsManager uses, so player.gd / weapon_manager.gd /
## run_manager.gd stay untouched.
##
## The meta layer only acts on runs armed by the Lobby's START RUN button.
## Scenes instanced directly (editor F5 on main.tscn, the older smoke
## harnesses) spawn a vanilla player and pay no Cores on death, which keeps
## those harnesses deterministic and keeps test deaths out of the real save.

signal cores_changed(total: int)

const SAVE_PATH := "user://meta_progress.cfg"

# --- Cores payout on permadeath ---
const CORES_PER_ROOM := 10
const MILESTONE_BONUS := 50  # extra per cleared milestone room (every 5th)

# --- Per-level bonus values ---
const HP_PER_LEVEL := 10.0
const ARMOR_PER_LEVEL := 10.0
const MOVE_SPEED_PER_LEVEL := 0.03    # +3% on every movement speed export
const RELOAD_SPEED_PER_LEVEL := 0.06  # reload_time shrinks by this per level
const AMMO_CAPACITY_PER_LEVEL := 0.10 # +10% mag size and reserves per level
const MIN_RELOAD_TIME := 0.2

## Permanent upgrade pool, separate from RunManager.UPGRADE_POOL (in-run).
## Cost of the next level = base_cost * (current level + 1).
const META_UPGRADES: Array[Dictionary] = [
	{"id": "starting_hp", "title": "Hardened Vitals",
		"desc": "+10 starting max health per level", "max_level": 5, "base_cost": 40},
	{"id": "starting_armor", "title": "Field Plating",
		"desc": "+10 starting armor per level", "max_level": 5, "base_cost": 40},
	{"id": "move_speed", "title": "Conditioning",
		"desc": "+3% move speed per level", "max_level": 5, "base_cost": 60},
	{"id": "reload_speed", "title": "Drill Practice",
		"desc": "+6% reload speed per level", "max_level": 5, "base_cost": 50},
	{"id": "ammo_capacity", "title": "Extended Mags",
		"desc": "+10% ammo capacity per level", "max_level": 5, "base_cost": 50},
	# Environment-hacking adjectives: a one-time unlock (max_level 1) of a word the player
	# can inject in every run. `kind`/`adjective` route to the HackManager on spawn.
	{"id": "hack_heavy", "title": "Adjective: Heavy",
		"desc": "Unlock the Heavy environment hack", "max_level": 1, "base_cost": 80,
		"kind": "adjective", "adjective": "heavy"},
	{"id": "hack_shocking", "title": "Adjective: Shocking",
		"desc": "Unlock the Shocking environment hack", "max_level": 1, "base_cost": 100,
		"kind": "adjective", "adjective": "shocking"},
]

var cores := 0
var upgrade_levels := {}  # id -> level owned (0 = not bought)
## Set by the Lobby's START RUN and never cleared, so Try Again reloads of
## main.tscn keep their bonuses. Direct main.tscn launches stay unarmed.
var run_bonuses_armed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for def in META_UPGRADES:
		upgrade_levels[def.id] = 0
	_load()
	RunManager.run_ended.connect(_on_run_ended)
	# Push permanent bonuses onto every Player that spawns in an armed run.
	get_tree().node_added.connect(_on_node_added)


# ---------------------------------------------------------------- queries

func upgrade_def(id: String) -> Dictionary:
	for def in META_UPGRADES:
		if def.id == id:
			return def
	return {}


func level_of(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


## Cost of the next level for an upgrade, or -1 when it is maxed out.
func next_cost(id: String) -> int:
	var def := upgrade_def(id)
	if def.is_empty() or level_of(id) >= int(def.max_level):
		return -1
	return int(def.base_cost) * (level_of(id) + 1)


func buy(id: String) -> bool:
	var cost := next_cost(id)
	if cost < 0 or cores < cost:
		return false
	cores -= cost
	upgrade_levels[id] = level_of(id) + 1
	_save()
	cores_changed.emit(cores)
	return true


## The Lobby's START RUN arms the meta layer for the upcoming run(s).
func arm_run_bonuses() -> void:
	run_bonuses_armed = true


# ---------------------------------------------------------------- cores payout

## Permadeath payout. RunManager.current_room is the room the player died IN
## (the RunHUD summary already shows current_room - 1 as rooms cleared), so
## rooms cleared = current_room - 1: 10 Cores per cleared room plus a 50 bonus
## for every cleared milestone room.
func _on_run_ended(won: bool) -> void:
	if won or not run_bonuses_armed:
		return
	var rooms_cleared := maxi(RunManager.current_room - 1, 0)
	var earned := CORES_PER_ROOM * rooms_cleared
	for room in range(1, rooms_cleared + 1):
		if RunManager.is_milestone_room(room):
			earned += MILESTONE_BONUS
	if earned <= 0:
		return
	cores += earned
	_save()
	cores_changed.emit(cores)


# ---------------------------------------------------------------- apply

func _on_node_added(node: Node) -> void:
	if node is Player and run_bonuses_armed:
		# Deferred: runs after the whole scene is ready, i.e. after the
		# player's _ready set its vitals and after PlayerUpgrades swapped the
		# shared WeaponData .tres for per-run duplicates — so the weapon stat
		# changes below never leak into the resource cache.
		_apply_player_deferred.call_deferred(node)


func _apply_player_deferred(player: Node) -> void:
	if is_instance_valid(player):
		_apply_player(player as Player)


func _apply_player(player: Player) -> void:
	var hp_bonus := HP_PER_LEVEL * float(level_of("starting_hp"))
	if hp_bonus > 0.0:
		player.max_health += hp_bonus
		player.heal(hp_bonus)
	var armor_bonus := ARMOR_PER_LEVEL * float(level_of("starting_armor"))
	if armor_bonus > 0.0:
		player.add_armor(armor_bonus)
	var speed_levels := level_of("move_speed")
	if speed_levels > 0:
		var factor := 1.0 + MOVE_SPEED_PER_LEVEL * float(speed_levels)
		player.walk_speed *= factor
		player.sprint_speed *= factor
		player.crouch_speed *= factor
		player.prone_speed *= factor
		player.slide_boost_speed *= factor
	_apply_weapons(player)
	_apply_hacks(player)


## Unlock every owned environment-hacking adjective on the player's HackManager, so a
## bought "word" is available (and the wheel populated) from room 1 of an armed run.
func _apply_hacks(player: Player) -> void:
	var hack_manager := player.get_node_or_null("HackManager")
	if hack_manager == null:
		return
	for def in META_UPGRADES:
		if def.get("kind", "") == "adjective" and level_of(def.id) > 0:
			hack_manager.unlock(String(def.adjective))


func _apply_weapons(player: Player) -> void:
	var reload_levels := level_of("reload_speed")
	var ammo_levels := level_of("ammo_capacity")
	if reload_levels == 0 and ammo_levels == 0:
		return
	var weapon_manager := player.get_node_or_null(
			"Head/Bob/Recoil/Camera/WeaponManager") as WeaponManager
	if weapon_manager == null:
		return
	var reload_factor := 1.0 + RELOAD_SPEED_PER_LEVEL * float(reload_levels)
	var ammo_factor := 1.0 + AMMO_CAPACITY_PER_LEVEL * float(ammo_levels)
	for data in weapon_manager.weapon_datas:
		data.reload_time = maxf(data.reload_time / reload_factor, MIN_RELOAD_TIME)
		data.mag_size = roundi(float(data.mag_size) * ammo_factor)
		data.start_reserve = roundi(float(data.start_reserve) * ammo_factor)
		data.max_reserve = roundi(float(data.max_reserve) * ammo_factor)
	if ammo_levels > 0:
		# Refill through the existing public API so the bigger magazines are
		# loaded from room 1 instead of only after the first manual reload.
		weapon_manager.reset_loadout()


# ---------------------------------------------------------------- persistence

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "cores", cores)
	for id in upgrade_levels:
		config.set_value("upgrades", id, upgrade_levels[id])
	config.save(SAVE_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return  # first run: keep defaults
	cores = maxi(int(config.get_value("meta", "cores", cores)), 0)
	for def in META_UPGRADES:
		var id: String = def.id
		var level := int(config.get_value("upgrades", id, upgrade_levels[id]))
		upgrade_levels[id] = clampi(level, 0, int(def.max_level))
