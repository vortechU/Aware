class_name HackManager
extends Node
## Environment hacking ("Injection"): the player aims at a world prop (a Hackable) and
## injects an adjective that rewrites its behaviour for a few seconds. Build-alongside,
## the AbilityManager way: a child of Player (sibling of PlayerUpgrades / AbilityManager)
## that reads the player's public state from the OUTSIDE and owns the trait catalog, the
## known-adjective set, and the live TraitInstances. Nothing in player.gd references it.
##
## OBJECTS ONLY: effects act on world props and route any damage through the existing
## enemy `BodyHitbox.take_hit` path, so enemy_ai.gd is untouched.
##
## SELECTOR (P4): HOLD `hack` to open a radial wheel of your unlocked adjectives; the aimed
## Hackable LOCKS, the world dips into slow-mo, mouse-flick / scroll picks a wedge, and
## RELEASE injects the picked adjective into the locked target. Adjectives are UNLOCKED via
## unlock() (P5 wires that into the upgrade-card / Cores flow).

const TARGET_RANGE := 30.0
const WORLD_MASK := 1  ## raycast only the "world" physics layer (props + walls block it)
const FLICK_DEADZONE := 40.0  ## px of accumulated mouse motion before a flick re-aims the wheel

## Adjective catalog. Per rank the effect grows (duration / crush) via the `*_per_rank`
## values. A const dict in P1; promote to TraitDef .tres later, like WeaponData.
const CATALOG := {
	"heavy": {
		"adjective": "Heavy",
		"desc": "Inject mass -- the object drops and crushes whatever is beneath it.",
		"duration": 6.0,
		"duration_per_rank": 1.0,
		"ram_cost": 35.0,          # RAM spent to inject it
		"ram_upkeep": 6.0,         # RAM/sec drained while it is live
		"mass": 60.0,
		"gravity_scale": 4.0,
		"crush_min_speed": 2.0,    # downward speed before a fall counts as a crush
		"crush_radius": 1.8,
		"crush_damage": 80.0,
		"crush_damage_per_rank": 30.0,
	},
	"shocking": {
		"adjective": "Shocking",
		"desc": "Electrify the object -- it zaps nearby enemies on a pulse.",
		"duration": 5.0,
		"duration_per_rank": 1.0,
		"ram_cost": 30.0,
		"ram_upkeep": 8.0,
		"shock_damage": 18.0,         # per pulse at rank 1
		"shock_damage_per_rank": 8.0,
		"shock_radius": 4.0,
		"shock_period": 0.5,          # seconds between pulses
	},
}

## RAM: the hacking resource. A pool that always regenerates; injecting a trait costs
## RAM up front and every live trait drains upkeep/sec. If upkeep drives RAM to empty the
## OLDEST trait collapses to free memory. (P2 -- HUD bar reads `ram_changed`.)
var ram_max := 100.0
var ram_regen := 18.0  # per second, always
var ram := 100.0
var _last_ram_emit := -1.0

var _known: Dictionary = {}             # id -> rank (the player's unlocked vocabulary)
var _active: Array[TraitInstance] = []  # live traits across all hosts
var _selected_id := ""                  # the adjective the selector last committed

# Selector (P4) state.
var select_time_scale := 0.3            # Engine.time_scale while the wheel is open (1.0 = off)
var _selecting := false
var _locked_target: Hackable = null     # the Hackable the wheel will inject into
var _ordered_ids: Array[String] = []    # unlocked adjectives, stable ring order
var _sel_index := 0
var _flick := Vector2.ZERO              # accumulated mouse motion since the wheel opened
var _highlighted: Hackable = null       # the Hackable glowing under the crosshair
var _wheel: HackWheel = null

@onready var player: Player = get_parent() as Player


func _ready() -> void:
	ram = ram_max
	_build_wheel()


## The selector wheel is owned by the HackManager (built in code -- no .tscn / HUD edit) so
## it shows wherever the player is: real runs and the sandbox alike.
func _build_wheel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3  # above the base HUD
	_wheel = HackWheel.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_wheel)
	add_child(layer)


## Add an adjective to the player's vocabulary, or rank an existing one up. Returns false
## for an id that is not in the catalog. The first unlock becomes the selected adjective.
func unlock(id: String, rank := 1) -> bool:
	if not CATALOG.has(id):
		return false
	_known[id] = maxi(int(_known.get(id, 0)), rank)
	if _selected_id == "":
		_selected_id = id
	return true


func is_unlocked(id: String) -> bool:
	return _known.has(id)


func rank_of(id: String) -> int:
	return int(_known.get(id, 0))


## Rank a known adjective up one (or grant it at rank 1 the first time). The in-run trait
## cards route here via PlayerUpgrades; returns false for an id that isn't an adjective.
func rank_up(id: String) -> bool:
	if not CATALOG.has(id):
		return false
	return unlock(id, rank_of(id) + 1)


func _physics_process(delta: float) -> void:
	# Tick live traits; drop the ones that decayed (reverting their host).
	for i in range(_active.size() - 1, -1, -1):
		if not _active[i].tick(delta):
			_expire_at(i)

	# RAM: always regen, drain each live trait's upkeep, emit on change.
	var upkeep := 0.0
	for ti in _active:
		upkeep += float(ti.def.get("ram_upkeep", 0.0))
	var raw := ram + (ram_regen - upkeep) * delta
	var new_ram := clampf(raw, 0.0, ram_max)
	if not is_equal_approx(new_ram, ram):
		ram = new_ram
		_emit_ram()
	# Overdrawn -- upkeep tried to pull RAM below empty: collapse the oldest trait to
	# free memory (the `raw < 0` test is robust to RAM settling at a tiny float, not 0).
	if raw < 0.0 and not _active.is_empty():
		_expire_at(0)

	# Selector: hold `hack` to open + lock the aimed target, release to inject the pick.
	if _selecting:
		if _wheel != null:
			_wheel.set_ram(ram_ratio())
		if Input.is_action_just_released("hack"):
			_close_selector(true)
	else:
		_update_highlight(current_target())
		if Input.is_action_just_pressed("hack"):
			_open_selector()


## The Hackable the player is currently aiming at, or null. A camera ray against the
## world layer (so walls block it -- no hacking through cover); the host body carries a
## "hackable" meta back-reference set by its Hackable component, found by walking up from
## the hit collider (covers nested collision shapes).
func current_target() -> Hackable:
	if player == null:
		return null
	var cam: Camera3D = player.camera
	if cam == null:
		return null
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * TARGET_RANGE
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var node: Node = hit.get("collider") as Node
	while node != null:
		if node.has_meta("hackable"):
			return node.get_meta("hackable") as Hackable
		node = node.get_parent()
	return null


## Inject `id` (default: the selected adjective) into the AIMED target. Returns true on a
## successful apply. (The selector injects into the LOCKED target via _inject directly.)
func try_hack(id := "") -> bool:
	return _inject(current_target(), id if id != "" else _selected_id)


## The actual injection, against an explicit target.
func _inject(target: Hackable, id: String) -> bool:
	if not is_unlocked(id):
		return false
	if target == null or target.body == null:
		return false
	if not target.accepts_adjective(id):
		return false
	var def: Dictionary = CATALOG[id]
	if ram < float(def.get("ram_cost", 0.0)):
		return false  # not enough RAM to inject it
	if target.active_trait != null:
		_remove(target.active_trait)  # one trait per host: the new one replaces it
	ram = maxf(ram - float(def.get("ram_cost", 0.0)), 0.0)
	_emit_ram()
	var ti := TraitInstance.new()
	ti.apply(target, id, rank_of(id), def)
	target.active_trait = ti
	_active.append(ti)
	GameEvents.trait_applied.emit(String(def["adjective"]), rank_of(id))
	return true


## Revert every live trait. Called by RunDirector at a room transition so nothing leaks
## across rooms (and before the old room's props are freed).
func clear_all() -> void:
	if _selecting:
		_close_selector(false)  # never leave the wheel open / time scaled across a transition
	_update_highlight(null)
	for ti in _active:
		ti.expire()
		if ti.host != null and is_instance_valid(ti.host):
			ti.host.active_trait = null
	_active.clear()
	ram = ram_max  # a fresh room starts with full memory
	_emit_ram()


func active_count() -> int:
	return _active.size()


func selected_id() -> String:
	return _selected_id


func ram_current() -> float:
	return ram


func ram_ratio() -> float:
	return clampf(ram / ram_max, 0.0, 1.0) if ram_max > 0.0 else 0.0


func _emit_ram() -> void:
	_last_ram_emit = ram
	GameEvents.ram_changed.emit(ram, ram_max)


func _expire_at(i: int) -> void:
	var ti := _active[i]
	ti.expire()
	if ti.host != null and is_instance_valid(ti.host):
		ti.host.active_trait = null
	_active.remove_at(i)
	GameEvents.trait_expired.emit(String(ti.def.get("adjective", ti.adjective_id)))


func _remove(ti: TraitInstance) -> void:
	var i := _active.find(ti)
	if i != -1:
		_expire_at(i)


# ---------------------------------------------------------------- selector (P4)

## Open the wheel: gather the unlocked adjectives, lock the aimed target, dip into slow-mo.
func _open_selector() -> void:
	_ordered_ids = _ordered_unlocked()
	if _ordered_ids.is_empty():
		return  # nothing to choose -- no vocabulary yet
	_locked_target = current_target()
	_update_highlight(_locked_target)
	_sel_index = maxi(0, _ordered_ids.find(_selected_id))
	_flick = Vector2.ZERO
	_selecting = true
	if _wheel != null:
		_wheel.open_wheel(_adjective_names(), _sel_index, ram_ratio())
	if select_time_scale < 1.0:
		Engine.time_scale = select_time_scale


## Close the wheel; if `apply`, inject the picked adjective into the LOCKED target.
func _close_selector(apply: bool) -> void:
	if not _selecting:
		return
	_selecting = false
	Engine.time_scale = 1.0
	if _wheel != null:
		_wheel.close_wheel()
	if apply and not _ordered_ids.is_empty():
		_selected_id = _ordered_ids[_sel_index]
		_inject(_locked_target, _selected_id)
	_locked_target = null
	_update_highlight(null)  # re-acquired next frame from the live crosshair


## Step the wheel selection (scroll / d-pad). Public so the selector input + tests drive it.
func cycle_selection(dir: int) -> void:
	if not _selecting or _ordered_ids.is_empty():
		return
	_sel_index = wrapi(_sel_index + dir, 0, _ordered_ids.size())
	if _wheel != null:
		_wheel.set_index(_sel_index)


## While the wheel is open, mouse motion re-aims it (flick) and scroll cycles it; both are
## consumed here in _input (which runs before the player's _unhandled_input), so the camera
## look and weapon switch are suppressed for the duration -- no player.gd / weapon edits.
func _input(event: InputEvent) -> void:
	if not _selecting:
		return
	if event is InputEventMouseMotion:
		_flick += (event as InputEventMouseMotion).relative
		var idx := _index_for_flick(_flick)
		if idx != -1 and idx != _sel_index:
			_sel_index = idx
			if _wheel != null:
				_wheel.set_index(_sel_index)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("weapon_next"):
		cycle_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("weapon_prev"):
		cycle_selection(-1)
		get_viewport().set_input_as_handled()


## Which wedge a mouse-flick points at, or -1 if it's too small to count. Wedges are evenly
## spaced clockwise from the top; on screen +y is down, so the angle is measured from "up".
func _index_for_flick(flick: Vector2) -> int:
	if _ordered_ids.is_empty() or flick.length() < FLICK_DEADZONE:
		return -1
	var ang := atan2(flick.x, -flick.y)  # 0 at top, increasing clockwise
	if ang < 0.0:
		ang += TAU
	var step := TAU / float(_ordered_ids.size())
	return wrapi(int(round(ang / step)), 0, _ordered_ids.size())


func _update_highlight(target: Hackable) -> void:
	if target == _highlighted:
		return
	if _highlighted != null and is_instance_valid(_highlighted):
		_highlighted.set_highlighted(false)
	_highlighted = target
	if _highlighted != null:
		_highlighted.set_highlighted(true)


func _ordered_unlocked() -> Array[String]:
	var ids: Array[String] = []
	for id in CATALOG:  # catalog order == stable ring order
		if _known.has(id):
			ids.append(id)
	return ids


func _adjective_names() -> PackedStringArray:
	var names := PackedStringArray()
	for id in _ordered_ids:
		names.append(String(CATALOG[id]["adjective"]))
	return names


# --- introspection (tests / debug) ---
func is_selecting() -> bool:
	return _selecting

func selection_index() -> int:
	return _sel_index

func ordered_ids() -> Array[String]:
	return _ordered_ids.duplicate()

func locked_target() -> Hackable:
	return _locked_target
