class_name AbilityManager
extends Node
## Active, hotkey-triggered abilities for the player. Build-alongside: a child of
## Player (sibling of PlayerUpgrades) that owns the equipped abilities, their
## cooldowns, the input, and the effects. Nothing in player.gd references this node;
## it reads/writes the player's public state from the outside (the same approach
## DevTools and the smoke tests use).
##
## Abilities are UNLOCKED in-run through the upgrade-card flow:
## PlayerUpgrades.apply_upgrade routes any id it does not recognise as a stat
## upgrade to grant(), where the FIRST grant equips the ability (in the first free
## slot) and each REPEAT ranks it up (shorter cooldown, stronger effect).
## Cooldown-only -- no resource meter.
##
## MULTI-SLOT: there are MAX_SLOTS independent ability slots, each on its own hotkey
## (SLOT_ACTIONS) and its own cooldown. Slot 0 = "ability" (F), slot 1 = "ability_2"
## (G). granting an id already equipped ranks that slot; a new id fills the next free
## slot; if every slot is full it replaces slot 0.

const MAX_SLOTS := 2
const SLOT_ACTIONS := ["ability", "ability_2"]

## Ability catalog. Per rank (repeat picks), the cooldown shrinks by
## `cooldown_rank_factor` and the effect grows by the `*_per_rank` values.
const CATALOG := {
	"stack_smash": {
		"title": "Stack Smash",
		"desc": "Air-slam the ground for an AoE shockwave.",
		"base_cooldown": 6.0,
		"cooldown_rank_factor": 0.85,  # x per extra rank (rank 2 = 0.85x, rank 3 = 0.72x, ...)
		"min_cooldown": 2.0,
		"slam_speed": 24.0,            # downward launch speed when the slam starts
		"base_radius": 5.0,            # blast radius at rank 1
		"radius_per_rank": 0.75,       # +m per extra rank
		"base_damage": 60.0,           # blast damage at rank 1
		"damage_per_rank": 30.0,       # +damage per extra rank
	},
	"overclock": {
		"title": "Overclock",
		"desc": "Throttle every enemy into slow-motion for a few seconds.",
		"base_cooldown": 12.0,
		"cooldown_rank_factor": 0.88,
		"min_cooldown": 6.0,
		"duration": 4.0,               # seconds of slow at rank 1
		"duration_per_rank": 0.75,     # +seconds per extra rank
		"slow_factor": 0.35,           # enemy ai_time_scale during the effect (rank 1)
		"slow_per_rank": 0.05,         # stronger (lower) per rank, floored at min_slow
		"min_slow": 0.15,
	},
}

# One entry per slot: {id, rank, cd_left, cd_total}. id "" means the slot is empty.
var _slots: Array[Dictionary] = []

# Stack Smash effect state (one slam in flight at a time; remembers its rank).
var _slam_active := false
var _slam_rank := 1
# Overclock effect state: while active, every enemy's ai_time_scale is held here.
var _overclock_time_left := 0.0
var _overclock_slow := 1.0

@onready var player: Player = get_parent() as Player


func _ready() -> void:
	for _i in MAX_SLOTS:
		_slots.append({"id": "", "rank": 0, "cd_left": 0.0, "cd_total": 0.0})


## Equip on the first grant (first free slot), rank up on each repeat. Returns false
## for an id that is not an ability, so PlayerUpgrades can still warn on a genuinely
## unknown id.
func grant(id: String) -> bool:
	if not CATALOG.has(id):
		return false
	if _slots.is_empty():
		_ready()  # defensive: grant() before _ready ran
	var slot := slot_of(id)
	if slot == -1:
		slot = _first_empty_slot()
	if slot == -1:
		slot = 0  # every slot full (only possible with > MAX_SLOTS abilities): replace slot 0
	var s: Dictionary = _slots[slot]
	if s["id"] != id:
		s["id"] = id
		s["rank"] = 1
	else:
		s["rank"] += 1
	s["cd_total"] = _current_cooldown(id, int(s["rank"]))
	s["cd_left"] = 0.0  # a fresh grant leaves the ability ready to use
	GameEvents.ability_granted.emit(slot, id, int(s["rank"]))
	GameEvents.ability_cooldown_changed.emit(slot, id, 0.0, float(s["cd_total"]))
	return true


func _physics_process(delta: float) -> void:
	# Per-slot cooldowns.
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		if float(s["cd_left"]) > 0.0:
			s["cd_left"] = maxf(float(s["cd_left"]) - delta, 0.0)
			if float(s["cd_left"]) == 0.0:
				GameEvents.ability_cooldown_changed.emit(i, s["id"], 0.0, float(s["cd_total"]))

	# Overclock: hold every live enemy's time scale down for the duration, then
	# release them on the frame it ends (re-applied each frame so it covers the whole
	# current squad regardless of who died or spawned).
	if _overclock_time_left > 0.0:
		_overclock_time_left = maxf(_overclock_time_left - delta, 0.0)
		var scale: float = _overclock_slow if _overclock_time_left > 0.0 else 1.0
		for node in get_tree().get_nodes_in_group("enemies"):
			node.set("ai_time_scale", scale)

	# Resolve an in-flight Stack Smash the instant the player touches down. This runs
	# after the player's own _physics_process (parent before child), so is_on_floor()
	# already reflects this frame's move_and_slide.
	if _slam_active and player != null and player.is_on_floor():
		_resolve_stack_smash()

	# Per-slot input.
	for i in _slots.size():
		if Input.is_action_just_pressed(SLOT_ACTIONS[i]) and can_cast(i):
			_cast(i)


## True when the slot holds an ability that is off cooldown and its launch
## conditions hold.
func can_cast(slot := 0) -> bool:
	if slot < 0 or slot >= _slots.size():
		return false
	var s: Dictionary = _slots[slot]
	var id: String = s["id"]
	if id == "" or float(s["cd_left"]) > 0.0 or player == null or player.is_dead:
		return false
	match id:
		"stack_smash":
			# An air-slam: only castable while airborne, never mid-vault.
			return not player.is_on_floor() and player.move_state != Player.MoveState.VAULT
		"overclock":
			# Castable any time it is off cooldown (no positional requirement).
			return true
	return false


func _cast(slot: int) -> void:
	var s: Dictionary = _slots[slot]
	var id: String = s["id"]
	match id:
		"stack_smash":
			_start_stack_smash(slot)
		"overclock":
			_start_overclock(slot)
	s["cd_total"] = _current_cooldown(id, int(s["rank"]))
	s["cd_left"] = float(s["cd_total"])
	GameEvents.ability_used.emit(slot, id)
	GameEvents.ability_cooldown_changed.emit(slot, id, float(s["cd_total"]), float(s["cd_total"]))


# ---------------------------------------------------------------- stack smash

## Kill horizontal drift and drive the player straight down. The AoE resolves on
## landing (see _resolve_stack_smash), so the harder you fall the more committal it is.
func _start_stack_smash(slot: int) -> void:
	var def: Dictionary = CATALOG["stack_smash"]
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.velocity.y = -float(def.slam_speed)
	_slam_active = true
	_slam_rank = int(_slots[slot]["rank"])


func _resolve_stack_smash() -> void:
	_slam_active = false
	var def: Dictionary = CATALOG["stack_smash"]
	var center: Vector3 = player.global_position
	var radius := float(def.base_radius) + float(def.radius_per_rank) * float(_slam_rank - 1)
	var damage := float(def.base_damage) + float(def.damage_per_rank) * float(_slam_rank - 1)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.global_position.distance_to(center) > radius:
			continue
		var hitbox := enemy.get_node_or_null("BodyHitbox")
		if hitbox != null and hitbox.has_method("take_hit"):
			hitbox.take_hit(damage, center)
	# The slam is loud: feed the world hearing sense so nearby enemies are alerted.
	GameEvents.sound_emitted.emit(center, radius * 1.5)
	GameEvents.ability_impact.emit("stack_smash", center, radius)


# ---------------------------------------------------------------- overclock

## Drop every enemy's time scale for the (rank-scaled) duration. The per-frame hold
## + release lives in _physics_process; this just sets the strength and the clock and
## applies it immediately so the slow is visible on the cast frame.
func _start_overclock(slot: int) -> void:
	var def: Dictionary = CATALOG["overclock"]
	var rank := int(_slots[slot]["rank"])
	_overclock_slow = maxf(
			float(def.slow_factor) - float(def.slow_per_rank) * float(rank - 1),
			float(def.min_slow))
	_overclock_time_left = float(def.duration) + float(def.duration_per_rank) * float(rank - 1)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.set("ai_time_scale", _overclock_slow)
	GameEvents.ability_impact.emit("overclock", player.global_position, 0.0)


# ---------------------------------------------------------------- queries

func _current_cooldown(id: String, rank: int) -> float:
	var def: Dictionary = CATALOG.get(id, {})
	if def.is_empty():
		return 0.0
	var cd := float(def.base_cooldown) * pow(float(def.cooldown_rank_factor), float(rank - 1))
	return maxf(cd, float(def.min_cooldown))


func slot_of(id: String) -> int:
	for i in _slots.size():
		if _slots[i]["id"] == id:
			return i
	return -1


func _first_empty_slot() -> int:
	for i in _slots.size():
		if _slots[i]["id"] == "":
			return i
	return -1


func equipped_id(slot := 0) -> String:
	if slot < 0 or slot >= _slots.size():
		return ""
	return String(_slots[slot]["id"])


func rank_of(slot := 0) -> int:
	if slot < 0 or slot >= _slots.size():
		return 0
	return int(_slots[slot]["rank"])


func cooldown_left(slot := 0) -> float:
	if slot < 0 or slot >= _slots.size():
		return 0.0
	return float(_slots[slot]["cd_left"])


func cooldown_total(slot := 0) -> float:
	if slot < 0 or slot >= _slots.size():
		return 0.0
	return float(_slots[slot]["cd_total"])


## 1.0 right after a cast, falling to 0.0 when ready. (HUD polls per-slot signals
## for its sweep; this is for tests / convenience.)
func cooldown_ratio(slot := 0) -> float:
	var total := cooldown_total(slot)
	if total <= 0.0:
		return 0.0
	return clampf(cooldown_left(slot) / total, 0.0, 1.0)


func is_ready(slot := 0) -> bool:
	return equipped_id(slot) != "" and cooldown_left(slot) <= 0.0
