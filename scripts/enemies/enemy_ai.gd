class_name EnemyAI
extends CharacterBody3D
## Enemy soldier. State machine: PATROL -> ALERT -> CHASE -> ATTACK with
## SEARCH on lost contact, COVER when hurt/reloading and FLANK when outgunned.
## Senses: line-of-sight vision cone + hearing via GameEvents.sound_emitted.

signal enemy_died(enemy: EnemyAI)

enum State { PATROL, ALERT, CHASE, ATTACK, SEARCH, COVER, FLANK, DEAD }

# --- Movement ---
@export var patrol_speed: float = 2.2
@export var combat_speed: float = 4.6
@export var turn_speed: float = 9.0

# --- Senses ---
@export var sight_range: float = 28.0
@export var sight_half_fov_deg: float = 70.0
@export var reaction_time: float = 0.4
@export var lose_sight_time: float = 1.6
@export var search_duration: float = 8.0

# --- Weapon ---
@export var shot_damage: float = 8.0
@export var attack_range: float = 15.0
@export var burst_count: int = 3
@export var burst_shot_interval: float = 0.14
@export var burst_pause: float = 0.85
@export var mag_size: int = 12
@export var reload_time: float = 2.0
@export var aim_spread_deg: float = 2.6

# --- Tactics ---
@export var cover_health_threshold: float = 40.0

# --- Time dilation (Overclock ability; 1.0 = normal, <1 = slowed) ---
## Scales this enemy's whole update: every delta-driven timer (senses, firing
## cadence, reload, sniper charge, grenade wind-up, dodge, state timers) AND its
## locomotion speed. The player's Overclock ability drops this for a few seconds.
## Default 1.0 is inert -- a normal enemy behaves exactly as before. Driven from the
## outside by AbilityManager (build-alongside, like is_sniper / is_grenadier).
@export var ai_time_scale: float = 1.0

# --- Sniper archetype (OFF by default; RunDirector._outfit_sniper turns it on) ---
## When set, the enemy fights at long range with a single telegraphed, charged
## shot instead of the normal burst, and relocates to a fresh perch after firing.
## A regular enemy leaves this false and behaves exactly as before.
@export var is_sniper: bool = false
@export var sniper_charge_time: float = 1.2     # telegraph-beam time before the shot
@export var sniper_shot_cooldown: float = 1.0   # pause after firing before relocating
@export var sniper_relocate_time: float = 1.8   # max time spent moving to a new perch

# --- Grenadier archetype (OFF by default; RunDirector._outfit_grenadier turns on) ---
## When set, the enemy keeps its distance and lobs arcing grenades to flush the
## player out of cover instead of using its gun. A regular enemy leaves it false.
@export var is_grenadier: bool = false
@export var grenade_cooldown: float = 3.0       # pause between throws
@export var grenade_windup: float = 0.7         # telegraphed wind-up before a throw
@export var grenade_damage: float = 30.0        # AoE damage at the blast centre
@export var grenade_radius: float = 4.5         # blast radius

# --- Aim fairness ---
## Extra aim spread (degrees) added to enemy gunfire while the player is using a
## movement trick, so skilful movement is rewarded by making the enemy miss more.
## (Raw speed is penalised separately in _try_fire via the player's velocity.)
const EVADE_WALLRUN := 5.0
const EVADE_SLIDE := 3.0
const EVADE_DASH := 6.0
const EVADE_VAULT := 3.0
const EVADE_MOMENTUM := 4.0  # scaled by the player's momentum (0..1)

# --- Reactive dodge (agile units only -- snipers/grenadiers hold their ground) ---
## When a player shot passes close, an aware enemy may juke sideways, so the
## player has to track and re-aim instead of holding a bead on a static target.
@export var can_dodge: bool = true
@export var dodge_chance: float = 0.15        # chance to react to a qualifying shot
@export var dodge_react_radius: float = 2.2   # how close a player shot must pass (m)
@export var dodge_cooldown: float = 3.0       # min time between dodges
@export var dodge_duration: float = 0.32      # length of the sideways juke
@export var dodge_speed: float = 9.0          # lateral juke speed

# --- Death / ragdoll ---
const CORPSE_GROUP := "enemy_corpse"
const RAGDOLL_FORCE := 7.0    # launch along the bullet direction
const RAGDOLL_UP := 3.2       # upward lift so it leaves the ground a little
const CORPSE_SETTLE := 3.2    # tumble/lie time before the corpse shrinks out
const CORPSE_FADE := 0.6      # shrink-out duration
# Headshot: the head detaches as its own little rigid body and pops off.
const HEAD_MASS := 0.4
const HEAD_POP_UP := 2.4      # upward pop impulse
const HEAD_POP_FORWARD := 1.2 # along-the-shot pop impulse
# The gun is always dropped as a separate tumbling piece.
const GUN_MASS := 0.5
const GUN_DROP_UP := 1.2
const GUN_DROP_FORWARD := 1.0

var state: State = State.PATROL

var _player: CharacterBody3D
var _home: Vector3
var _last_known_player_pos: Vector3
var _can_see_player := false
var _sense_timer := 0.0
var _state_timer := 0.0
var _lost_sight_timer := 0.0
var _repath_timer := 0.0
var _patrol_wait := 0.0

# weapon state
var _mag := 0
var _shot_timer := 0.0
var _burst_left := 0
var _reload_left := 0.0
var _flash_left := 0.0

# tactics state
var _cover_point: Node3D
var _cover_settle := 0.0
var _strafe_timer := 0.0
var _look_timer := 0.0
var _look_target_yaw := 0.0

# sniper state (only used when is_sniper)
var _sniper_charging := false
var _sniper_charge_left := 0.0
var _sniper_aim_point := Vector3.ZERO  # world point locked at charge start
var _sniper_cooldown := 0.0
var _sniper_relocate_left := 0.0
var _sniper_beam: MeshInstance3D

# grenadier state (only used when is_grenadier)
const GRENADE_SCENE := preload("res://scripts/enemies/grenade.gd")
var _gren_cooldown := 0.0
var _gren_winding := false
var _gren_windup_left := 0.0

# reactive-dodge state
var _dodge_time_left := 0.0
var _dodge_cooldown := 0.0
var _dodge_dir := Vector3.ZERO

# last-shot record (for the directional death ragdoll); set by register_hit
var _last_hit_point := Vector3.INF
var _last_hit_dir := Vector3.ZERO
var _last_hit_head := false

@onready var agent: NavigationAgent3D = $NavAgent
@onready var eyes: Marker3D = $Eyes
@onready var muzzle: Marker3D = $Muzzle
@onready var visual: Node3D = $Visual
@onready var health: HealthComponent = $Health

var _muzzle_light: OmniLight3D


func _ready() -> void:
	_home = global_position
	_mag = mag_size
	_burst_left = burst_count
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	health.died.connect(_die)
	agent.velocity_computed.connect(_on_velocity_computed)
	GameEvents.sound_emitted.connect(_on_sound_heard)
	# React to the player's gunfire passing nearby (used for reactive dodging).
	if GameEvents.has_signal("bullet_tracer"):
		GameEvents.bullet_tracer.connect(_on_player_shot)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.7, 0.3)
	_muzzle_light.light_energy = 2.5
	_muzzle_light.omni_range = 4.0
	_muzzle_light.visible = false
	muzzle.add_child(_muzzle_light)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Overclock: scale the whole AI update. Every delta-driven timer below slows with
	# it; locomotion is scaled in _navigate / _process_dodge. 1.0 leaves it untouched.
	delta *= ai_time_scale

	if not is_on_floor():
		velocity += get_gravity() * delta

	# A reactive dodge briefly overrides the normal AI: juke sideways, then resume.
	if _dodge_time_left > 0.0:
		_process_dodge(delta)
		return

	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.2
		_update_senses()

	_update_weapon_timers(delta)

	# Lost the target entirely (player died): stand down.
	if _player_dead() and state != State.PATROL:
		_change_state(State.PATROL)

	match state:
		State.PATROL:
			_state_patrol(delta)
		State.ALERT:
			_state_alert(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.SEARCH:
			_state_search(delta)
		State.COVER:
			_state_cover(delta)
		State.FLANK:
			_state_flank(delta)


# ---------------------------------------------------------------- states

func _change_state(new_state: State) -> void:
	if state == State.DEAD:
		return
	if _cover_point and new_state != State.COVER:
		_cover_point.remove_meta("claimed_by")
		_cover_point = null
	# Leaving combat cancels any in-progress sniper charge + clears its telegraph.
	if _sniper_charging and new_state != State.ATTACK:
		_cancel_sniper_charge()
	# Same for a grenadier mid wind-up.
	if _gren_winding and new_state != State.ATTACK:
		_gren_winding = false
	state = new_state
	_state_timer = 0.0
	match new_state:
		State.ALERT:
			pass
		State.SEARCH:
			agent.target_position = _last_known_player_pos
		State.COVER:
			if _cover_point:
				agent.target_position = _cover_point.global_position
			_cover_settle = 0.0
		State.FLANK:
			agent.target_position = _flank_position()


func _state_patrol(delta: float) -> void:
	if _can_see_player:
		_change_state(State.ALERT)
		return
	if agent.is_navigation_finished():
		_stand_still(delta)
		_patrol_wait -= delta
		if _patrol_wait <= 0.0:
			_patrol_wait = randf_range(1.5, 3.5)
			agent.target_position = _random_point_near(_home, 9.0)
	else:
		_navigate(patrol_speed, delta)


func _state_alert(delta: float) -> void:
	_state_timer += delta
	_stand_still(delta)
	_face_point(_last_known_player_pos, delta)
	if _state_timer >= reaction_time:
		if _can_see_player:
			_change_state(State.CHASE)
		else:
			_change_state(State.SEARCH)


func _state_chase(delta: float) -> void:
	if _can_see_player:
		_lost_sight_timer = 0.0
		_last_known_player_pos = _player.global_position
		if _distance_to_player() < attack_range:
			_change_state(State.ATTACK)
			return
	else:
		_lost_sight_timer += delta
		if _lost_sight_timer > lose_sight_time * 2.0:
			_change_state(State.SEARCH)
			return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 0.3
		agent.target_position = _last_known_player_pos
	_navigate(combat_speed, delta)

	# Opportunistic fire while closing in. Snipers never hip-fire (they only take
	# their charged shot from ATTACK); grenadiers only ever lob from ATTACK too.
	if not is_sniper and not is_grenadier \
			and _can_see_player and _distance_to_player() < attack_range * 1.25:
		_face_point(_player.global_position, delta)
		_try_fire(delta)


func _state_attack(delta: float) -> void:
	if is_sniper:
		_sniper_attack(delta)
		return
	if is_grenadier:
		_grenadier_attack(delta)
		return
	if _can_see_player:
		_lost_sight_timer = 0.0
		_last_known_player_pos = _player.global_position
	else:
		_lost_sight_timer += delta
		if _lost_sight_timer > lose_sight_time:
			_change_state(State.SEARCH)
			return

	if _distance_to_player() > attack_range * 1.35:
		_change_state(State.CHASE)
		return

	# Hurt or empty mag: try to break contact.
	if _reload_left > 0.0 or health.health <= cover_health_threshold:
		if _should_flank():
			_change_state(State.FLANK)
			return
		if _try_take_cover():
			return

	_face_point(_player.global_position, delta)
	_try_fire(delta)

	# Slow strafe to be a harder target.
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.6, 2.6)
		var side := global_transform.basis.x * (2.5 if randf() > 0.5 else -2.5)
		agent.target_position = global_position + side
	if agent.is_navigation_finished():
		_stand_still(delta, false)
	else:
		_navigate(patrol_speed, delta, false)


func _state_search(delta: float) -> void:
	_state_timer += delta
	if _can_see_player:
		_change_state(State.CHASE)
		return
	if _state_timer > search_duration:
		agent.target_position = _home
		_change_state(State.PATROL)
		return

	if agent.is_navigation_finished():
		# Look around, then poke at nearby spots.
		_stand_still(delta, false)
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = randf_range(1.0, 1.8)
			_look_target_yaw = randf_range(-PI, PI)
			if randf() > 0.6:
				agent.target_position = _random_point_near(_last_known_player_pos, 5.0)
		rotation.y = lerp_angle(rotation.y, _look_target_yaw, turn_speed * 0.4 * delta)
	else:
		_navigate(combat_speed * 0.7, delta)


func _state_cover(delta: float) -> void:
	if _cover_point == null:
		_change_state(State.CHASE)
		return
	if not agent.is_navigation_finished():
		_navigate(combat_speed, delta)
		return

	# In cover: crouch visually, finish reload, then re-engage.
	_stand_still(delta, false)
	visual.scale.y = lerpf(visual.scale.y, 0.62, 8.0 * delta)
	_face_point(_last_known_player_pos, delta)
	_cover_settle += delta
	if _reload_left <= 0.0 and _cover_settle > 1.2:
		visual.scale.y = 1.0
		_change_state(State.CHASE)


func _state_flank(delta: float) -> void:
	_state_timer += delta
	if _state_timer > 7.0 or agent.is_navigation_finished():
		_change_state(State.CHASE)
		return
	_navigate(combat_speed, delta)
	if _can_see_player and _distance_to_player() < attack_range * 0.7:
		_change_state(State.ATTACK)


# ---------------------------------------------------------------- senses

func _update_senses() -> void:
	_can_see_player = _check_line_of_sight()
	if _can_see_player:
		_last_known_player_pos = _player.global_position
		if state == State.PATROL or state == State.SEARCH:
			if state == State.PATROL:
				_change_state(State.ALERT)
			else:
				_change_state(State.CHASE)


func _check_line_of_sight() -> bool:
	if _player_dead():
		return false
	var eye_pos := eyes.global_position
	var target := _player.global_position + Vector3.UP * 1.3
	var to := target - eye_pos
	if to.length() > sight_range:
		return false
	# Vision cone only matters when unaware; in combat use full awareness.
	if state == State.PATROL or state == State.SEARCH or state == State.ALERT:
		var forward := -global_transform.basis.z
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		if rad_to_deg(forward.angle_to(flat)) > sight_half_fov_deg:
			return false
	var params := PhysicsRayQueryParameters3D.create(eye_pos, target, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(params).is_empty()


func _on_sound_heard(sound_position: Vector3, radius: float) -> void:
	if state == State.DEAD:
		return
	if global_position.distance_to(sound_position) > radius:
		return
	if state == State.PATROL or state == State.SEARCH or state == State.ALERT:
		_last_known_player_pos = sound_position
		if state == State.PATROL:
			_change_state(State.ALERT)
		else:
			agent.target_position = sound_position
			_state_timer = 0.0


## Called by HitboxComponent when a bullet lands; getting shot reveals the shooter.
func on_hit(attacker_position: Vector3) -> void:
	if state == State.DEAD:
		return
	_last_known_player_pos = attacker_position
	if state == State.PATROL or state == State.SEARCH or state == State.ALERT:
		_change_state(State.CHASE)
	elif state == State.ATTACK and health.health <= cover_health_threshold:
		if _should_flank():
			_change_state(State.FLANK)
		else:
			_try_take_cover()


## Called by HitboxComponent the instant a bullet lands (BEFORE damage is applied),
## recording this shot's contact point + travel direction + whether it was a head
## hit, so a fatal shot's ragdoll can react to the precise shot.
func register_hit(point: Vector3, direction: Vector3, is_head: bool) -> void:
	_last_hit_point = point
	_last_hit_dir = direction
	_last_hit_head = is_head


# ---------------------------------------------------------------- weapon

func _update_weapon_timers(delta: float) -> void:
	_shot_timer = maxf(_shot_timer - delta, 0.0)
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_mag = mag_size
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_muzzle_light.visible = false


func _try_fire(delta: float) -> void:
	if _shot_timer > 0.0 or _reload_left > 0.0 or _player_dead():
		return
	if _mag <= 0:
		_reload_left = reload_time
		_burst_left = burst_count
		return
	_mag -= 1
	_burst_left -= 1
	if _burst_left <= 0:
		_burst_left = burst_count
		_shot_timer = burst_pause + randf() * 0.5
	else:
		_shot_timer = burst_shot_interval

	# Aim at the player's chest with spread; harder to hit a fast player, and
	# harder still while they're pulling movement tricks (wall-run/dash/slide/...).
	var target := _player.global_position + Vector3.UP * 1.1
	var to := (target - muzzle.global_position).normalized()
	var miss := aim_spread_deg + _player.velocity.length() * 0.35 + _player_evasion_spread()
	var spread_rad := deg_to_rad(miss)
	var pitch_axis := to.cross(Vector3.UP)
	if pitch_axis.length_squared() < 0.001:
		pitch_axis = Vector3.RIGHT
	var perturbed := to.rotated(pitch_axis.normalized(),
			randf_range(-spread_rad, spread_rad))
	perturbed = perturbed.rotated(Vector3.UP, randf_range(-spread_rad, spread_rad))

	var from := muzzle.global_position
	var params := PhysicsRayQueryParameters3D.create(
		from, from + perturbed * sight_range * 1.5, 0b11, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty() and hit.collider is CharacterBody3D \
			and (hit.collider as Node).is_in_group("player"):
		(hit.collider as Node).call("take_damage", shot_damage, global_position)

	_muzzle_light.visible = true
	_flash_left = 0.05
	# Gunfire is loud: nearby allies will come investigate the fight.
	GameEvents.sound_emitted.emit(global_position, 18.0)


## Extra aim spread (degrees) reflecting the player's evasive movement. Wall-running,
## sliding, dashing, vaulting and high momentum each make this enemy's shots less
## accurate, so skilful movement is rewarded. Read off the player without touching
## player.gd; the raw-speed penalty is applied separately in _try_fire.
func _player_evasion_spread() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var extra := 0.0
	match int(_player.get("move_state")):
		5: extra += EVADE_WALLRUN  # MoveState.WALLRUN
		4: extra += EVADE_SLIDE    # MoveState.SLIDE
		6: extra += EVADE_VAULT    # MoveState.VAULT
	if float(_player.get("_dash_time_left")) > 0.0:
		extra += EVADE_DASH
	extra += clampf(float(_player.get("momentum")), 0.0, 1.0) * EVADE_MOMENTUM
	return extra


# ---------------------------------------------------------------- reactive dodge

## A player shot was fired (GameEvents.bullet_tracer). If it came from the player
## and passed close to an already-aware, agile enemy, it may juke sideways. Snipers
## and grenadiers hold their ground (their counterplay is punishing the telegraph).
func _on_player_shot(from: Vector3, to: Vector3) -> void:
	if not can_dodge or state == State.DEAD or is_sniper or is_grenadier:
		return
	if _dodge_time_left > 0.0 or _dodge_cooldown > 0.0 or _player_dead():
		return
	if state == State.PATROL:
		return  # unaware: no psychic dodging before it even notices the player
	# Enemy gunfire also emits a tracer (e.g. the sniper), so only react to shots
	# that originate at the player.
	if from.distance_to(_player.global_position) > 3.0:
		return
	if _segment_point_distance(from, to, global_position + Vector3.UP * 0.9) > dodge_react_radius:
		return
	if randf() > dodge_chance:
		return
	_start_dodge()


## Begin a sideways juke, perpendicular to the line to the player, random side.
func _start_dodge() -> void:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dir := to_player.normalized().cross(Vector3.UP)
	if dir.length_squared() < 0.01:
		dir = global_transform.basis.x
	if randf() > 0.5:
		dir = -dir
	_dodge_dir = dir.normalized()
	_dodge_time_left = dodge_duration
	_dodge_cooldown = dodge_cooldown


## Drive the sideways juke; keep facing the player so it strafes rather than turns.
func _process_dodge(delta: float) -> void:
	_dodge_time_left -= delta
	velocity.x = _dodge_dir.x * dodge_speed * ai_time_scale
	velocity.z = _dodge_dir.z * dodge_speed * ai_time_scale
	if not _player_dead():
		_face_point(_player.global_position, delta)
	move_and_slide()


## Shortest distance from point p to the segment a->b.
func _segment_point_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.0001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------- tactics

func _should_flank() -> bool:
	# "Outgunned but not alone": hurt while an ally is still fighting.
	if health.health > cover_health_threshold:
		return false
	var allies := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e is EnemyAI and (e as EnemyAI).state != State.DEAD:
			allies += 1
	return allies >= 1 and randf() > 0.5


func _try_take_cover() -> bool:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("cover_point"):
		var point := node as Node3D
		if point.has_meta("claimed_by"):
			continue
		var pos := point.global_position
		if not _player_dead() and pos.distance_to(_player.global_position) < 5.0:
			continue  # cover right next to the player is no cover at all
		if not _is_hidden_from_player(pos):
			continue
		var d := global_position.distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = point
	if best == null:
		return false
	best.set_meta("claimed_by", get_instance_id())
	_cover_point = best
	_change_state(State.COVER)
	return true


func _is_hidden_from_player(pos: Vector3) -> bool:
	if _player_dead():
		return true
	var from := _player.global_position + Vector3.UP * 1.5
	var to := pos + Vector3.UP * 0.8
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()


func _flank_position() -> Vector3:
	if _player_dead():
		return global_position
	var to_me := (global_position - _player.global_position)
	to_me.y = 0.0
	var side := to_me.normalized().rotated(
		Vector3.UP, (PI / 2.0) if randf() > 0.5 else (-PI / 2.0))
	return _player.global_position + side * 8.0


# ---------------------------------------------------------------- sniper

## Long-range attack loop used in place of _state_attack when is_sniper. Cycle:
## relocate to a perch -> (line of sight) -> charge a telegraphed beam -> fire a
## single accurate shot -> cooldown -> relocate again. The locked aim direction +
## the visible beam are the player's cue to step out of the lane.
func _sniper_attack(delta: float) -> void:
	# Same LoS / range bookkeeping as the normal ATTACK so it still drops to
	# SEARCH when it loses the player or CHASE when the player closes in.
	if _can_see_player:
		_lost_sight_timer = 0.0
		_last_known_player_pos = _player.global_position
	else:
		_lost_sight_timer += delta
		if _lost_sight_timer > lose_sight_time:
			_change_state(State.SEARCH)
			return
	if _distance_to_player() > attack_range * 1.35:
		_change_state(State.CHASE)
		return

	# Moving to a fresh perch after the last shot.
	if _sniper_relocate_left > 0.0:
		_sniper_relocate_left -= delta
		if not agent.is_navigation_finished() and _sniper_relocate_left > 0.0:
			_navigate(combat_speed, delta)
			return
		_sniper_relocate_left = 0.0

	# Without line of sight it can't aim: hold and face the last known spot.
	if not _can_see_player:
		if _sniper_charging:
			_cancel_sniper_charge()
		_stand_still(delta, false)
		_face_point(_last_known_player_pos, delta)
		return

	# Cooldown between shots.
	if _sniper_cooldown > 0.0:
		_sniper_cooldown -= delta
		_stand_still(delta, false)
		_face_point(_player.global_position, delta)
		return

	# Charging the telegraphed shot: hold still, aim at the locked point.
	_stand_still(delta, false)
	if not _sniper_charging:
		_sniper_begin_charge()
	_face_point(_sniper_aim_point, delta)
	_sniper_charge_left -= delta
	var t := 1.0 - clampf(_sniper_charge_left / maxf(sniper_charge_time, 0.01), 0.0, 1.0)
	_update_sniper_beam(true, t)
	if _sniper_charge_left <= 0.0:
		_sniper_fire()
		_cancel_sniper_charge()
		_sniper_cooldown = sniper_shot_cooldown
		_sniper_begin_relocate()


## Lock the aim at the player's chest as a fixed WORLD POINT (not a direction):
## the shot is fired toward this point even if the player then moves, so stepping
## off the line dodges it. Locking a point (and deriving the direction live from
## the muzzle) keeps the shot accurate even as the body turns to aim during the
## charge, which moves the muzzle.
func _sniper_begin_charge() -> void:
	_sniper_charging = true
	_sniper_charge_left = sniper_charge_time
	_sniper_aim_point = _player.global_position + Vector3.UP * 1.1
	_ensure_sniper_beam()


## Fire one accurate hitscan from the muzzle through the locked aim point.
func _sniper_fire() -> void:
	var from := muzzle.global_position
	var dir := _sniper_aim_point - from
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var end := _sniper_aim_point + dir * 1.0  # reach a touch past the point
	var params := PhysicsRayQueryParameters3D.create(from, end, 0b11, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var hit_point := end
	if not hit.is_empty():
		hit_point = hit.position
		if hit.collider is CharacterBody3D and (hit.collider as Node).is_in_group("player"):
			(hit.collider as Node).call("take_damage", shot_damage, global_position)
	_muzzle_light.visible = true
	_flash_left = 0.08
	GameEvents.sound_emitted.emit(global_position, 22.0)  # a rifle crack carries far
	if GameEvents.has_signal("bullet_tracer"):
		GameEvents.bullet_tracer.emit(from, hit_point)


func _cancel_sniper_charge() -> void:
	_sniper_charging = false
	_sniper_charge_left = 0.0
	_update_sniper_beam(false, 0.0)


## Pick a perch offset laterally from the player line so the sniper keeps moving.
func _sniper_begin_relocate() -> void:
	if _player_dead():
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var side := 1.0 if randf() > 0.5 else -1.0
	var perp := to_player.normalized().cross(Vector3.UP) * side * randf_range(4.0, 8.0)
	agent.target_position = _random_point_near(global_position + perp, 3.0)
	_sniper_relocate_left = sniper_relocate_time


## Build the telegraph beam once (a thin unshaded box, top_level so we drive its
## world transform directly). Kept hidden until a charge starts.
func _ensure_sniper_beam() -> void:
	if _sniper_beam != null:
		return
	_sniper_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 1.0)  # unit length along local Z; scaled per frame
	_sniper_beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.1)
	mat.emission_energy_multiplier = 2.0
	_sniper_beam.material_override = mat
	_sniper_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sniper_beam.top_level = true  # ignore the body's transform; we set world space
	add_child(_sniper_beam)
	_sniper_beam.visible = false


## Stretch/aim the beam from the muzzle along the locked direction, stopping at the
## first wall, and intensify it (brighter + thicker) as the charge nears firing.
func _update_sniper_beam(active: bool, t: float) -> void:
	if _sniper_beam == null:
		return
	if not active:
		_sniper_beam.visible = false
		return
	var from := muzzle.global_position
	var dir := _sniper_aim_point - from
	if dir.length_squared() < 0.0001:
		_sniper_beam.visible = false
		return
	dir = dir.normalized()
	var end := _sniper_aim_point
	var params := PhysicsRayQueryParameters3D.create(from, end, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		end = hit.position  # stop the beam at a wall in front of the locked point
	var length := from.distance_to(end)
	if length < 0.1:
		_sniper_beam.visible = false
		return
	_sniper_beam.visible = true
	_sniper_beam.global_position = (from + end) * 0.5
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	_sniper_beam.look_at(end, up)  # local -Z faces 'end'; the box spans along Z
	var thick := lerpf(0.6, 1.6, t)
	_sniper_beam.scale = Vector3(thick, thick, length)
	var mat := _sniper_beam.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = lerpf(0.25, 0.9, t)
		mat.emission_energy_multiplier = lerpf(1.0, 4.0, t)


# ---------------------------------------------------------------- grenadier

## Mid-range attack loop used in place of _state_attack when is_grenadier. It
## keeps its distance and lobs arcing grenades (after a brief telegraphed wind-up)
## to flush the player out of cover, never using its gun. The grenade itself
## (scripts/enemies/grenade.gd) owns the arc, the ground danger ring and the AoE.
func _grenadier_attack(delta: float) -> void:
	# Same LoS / range bookkeeping as the normal ATTACK.
	if _can_see_player:
		_lost_sight_timer = 0.0
		_last_known_player_pos = _player.global_position
	else:
		_lost_sight_timer += delta
		if _lost_sight_timer > lose_sight_time:
			_change_state(State.SEARCH)
			return
	if _distance_to_player() > attack_range * 1.5:
		_change_state(State.CHASE)
		return

	# Throw cycle takes priority over movement.
	if _gren_winding:
		_gren_windup_left -= delta
		_stand_still(delta, false)
		_face_point(_last_known_player_pos, delta)
		if _gren_windup_left <= 0.0:
			_gren_winding = false
			_throw_grenade()
			_gren_cooldown = grenade_cooldown
		return
	_gren_cooldown -= delta
	if _gren_cooldown <= 0.0 and _can_see_player:
		_gren_winding = true
		_gren_windup_left = grenade_windup
		return

	# Between throws: keep distance (back off if the player closes) and face them.
	_face_point(_player.global_position, delta)
	if _distance_to_player() < attack_range * 0.6 and not _player_dead():
		var away := global_position - _player.global_position
		away.y = 0.0
		if away.length_squared() > 0.01:
			agent.target_position = global_position + away.normalized() * 5.0
			_navigate(combat_speed, delta, false)
			return
	_stand_still(delta, false)


## Lob a grenade at the player's last known position (arcs over low cover).
func _throw_grenade() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var grenade: Node3D = GRENADE_SCENE.new()
	grenade.set("damage", grenade_damage)
	grenade.set("blast_radius", grenade_radius)
	scene.add_child(grenade)
	grenade.global_position = muzzle.global_position
	grenade.call("launch_at", _last_known_player_pos)
	_muzzle_light.visible = true
	_flash_left = 0.05
	GameEvents.sound_emitted.emit(global_position, 14.0)  # the thunk of a launcher


# ---------------------------------------------------------------- movement

func _navigate(speed: float, delta: float, face_movement := true) -> void:
	if agent.is_navigation_finished():
		_stand_still(delta, face_movement)
		return
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var move_speed := speed * ai_time_scale  # Overclock slows locomotion too
	var desired := dir * move_speed
	if face_movement:
		_face_point(global_position + dir * 2.0, delta)
	agent.max_speed = maxf(move_speed, 0.01)
	agent.velocity = desired  # XZ only; gravity stays in velocity.y


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if state == State.DEAD:
		return
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


func _stand_still(delta: float, _face := true) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	move_and_slide()


func _face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length_squared() < 0.01:
		return
	var target_yaw := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _random_point_near(center: Vector3, radius: float) -> Vector3:
	var offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, center + offset)


# ---------------------------------------------------------------- misc

func _distance_to_player() -> float:
	if _player_dead():
		return INF
	return global_position.distance_to(_player.global_position)


func _player_dead() -> bool:
	# `== true` (not bool(...)) so a player without an `is_dead` property reads as
	# alive instead of erroring on bool(null).
	return _player == null or _player.get("is_dead") == true


func _die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	if _cover_point:
		_cover_point.remove_meta("claimed_by")
		_cover_point = null
	if _sniper_beam != null:
		_sniper_beam.visible = false  # don't leave a telegraph hanging on the husk
	set_collision_layer_value(3, false)
	set_collision_mask_value(2, false)
	agent.avoidance_enabled = false
	# Hitboxes off so corpses don't soak bullets.
	for child in get_children():
		if child is HitboxComponent:
			(child as HitboxComponent).set_deferred("monitorable", false)
			(child as CollisionObject3D).set_deferred("collision_layer", 0)
	_spawn_ragdoll()
	enemy_died.emit(self)
	# The corpse lives on its own (separate node); free the now-empty husk once it
	# has had time to fall and shrink out.
	await get_tree().create_timer(CORPSE_SETTLE + CORPSE_FADE + 0.5).timeout
	queue_free()


## Hand the visual meshes to a physics "corpse" (a RigidBody3D) that is knocked
## away from the shooter, tumbles on the world, then shrinks out. Enemies are
## primitive-mesh (no skeleton), so a single rigid body reads as a ragdoll
## without a bone rig. The corpse ignores the player/enemies (collision_layer 0)
## so it never nudges gameplay, but still rests on the floor/walls (mask = world).
func _spawn_ragdoll() -> void:
	var parent := get_parent()
	if parent == null or not is_instance_valid(visual):
		return
	var corpse := RigidBody3D.new()
	corpse.add_to_group(CORPSE_GROUP)
	corpse.collision_layer = 0  # nothing detects the corpse
	corpse.collision_mask = 1   # but it collides with the world (floor/walls/crates)
	corpse.mass = 1.0
	corpse.angular_damp = 0.6
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.3
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)  # match the body capsule offset
	corpse.add_child(shape)
	parent.add_child(corpse)
	corpse.global_transform = global_transform

	# Move the meshes onto the corpse (keeps their toon materials + elite look).
	visual.reparent(corpse)  # keep_global_transform = true; corpse == enemy here

	# Launch along the actual bullet direction if this shot was recorded, else fall
	# back to "away from the shooter" (player -> enemy). Flatten the vertical a bit
	# so a steep downward shot still mostly knocks the corpse along the ground.
	var dir: Vector3
	if _last_hit_dir.length_squared() > 0.01:
		dir = _last_hit_dir
		dir.y *= 0.3
	else:
		var shooter := _shooter_pos()
		dir = Vector3(global_position.x - shooter.x, 0.0, global_position.z - shooter.z)
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	dir = dir.normalized()

	# Apply the impulse AT the hit point (offset from the corpse origin) so where
	# you hit shapes the tumble: a high hit topples it backward, a low hit flips it
	# up, an off-centre hit spins it -- the body reacts to the actual shot.
	var impulse := dir * RAGDOLL_FORCE + Vector3.UP * RAGDOLL_UP
	var offset := Vector3(0.0, 0.9, 0.0)  # default: roughly centre of mass
	if _last_hit_point != Vector3.INF:
		offset = _last_hit_point - corpse.global_position
	corpse.apply_impulse(impulse, offset)
	# A little extra randomness on top (the off-centre hit gives the main tumble).
	corpse.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0),
			randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)))

	# A headshot pops the head clean off as its own little rigid body.
	if _last_hit_head:
		_pop_head(corpse)
	# The gun always drops as a separate tumbling piece.
	_drop_gun(corpse)

	# Lie there, then shrink the meshes out and free the corpse independently.
	var moved_visual := corpse.get_node_or_null("Visual") as Node3D
	var tween := corpse.create_tween()
	tween.tween_interval(CORPSE_SETTLE)
	if moved_visual != null:
		tween.tween_property(moved_visual, "scale", Vector3.ZERO, CORPSE_FADE) \
			.set_ease(Tween.EASE_IN)
	tween.tween_callback(corpse.queue_free)


## Detach the head mesh from the body corpse onto its own small rigid body and pop
## it off (up + along the shot). The body corpse is left headless. The head joins
## the corpse group so it's cleared on a room transition too.
func _pop_head(corpse: RigidBody3D) -> void:
	var head := corpse.get_node_or_null("Visual/Head") as MeshInstance3D
	if head == null:
		return
	var head_body := RigidBody3D.new()
	head_body.add_to_group(CORPSE_GROUP)
	head_body.collision_layer = 0
	head_body.collision_mask = 1
	head_body.mass = HEAD_MASS
	head_body.angular_damp = 0.3
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	shape.shape = sphere
	head_body.add_child(shape)
	corpse.get_parent().add_child(head_body)
	head_body.global_position = head.global_position
	head.reparent(head_body, true)  # keep its world transform + toon material

	var dir := _last_hit_dir
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	head_body.apply_central_impulse(dir * HEAD_POP_FORWARD + Vector3.UP * HEAD_POP_UP)
	head_body.apply_torque_impulse(Vector3(randf_range(-1.5, 1.5),
			randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))

	var tween := head_body.create_tween()
	tween.tween_interval(CORPSE_SETTLE)
	tween.tween_property(head, "scale", Vector3.ZERO, CORPSE_FADE).set_ease(Tween.EASE_IN)
	tween.tween_callback(head_body.queue_free)


## Detach the gun mesh onto its own rigid body so it clatters to the floor instead
## of vanishing with the body. Joins the corpse group so it's cleared on a room
## transition too.
func _drop_gun(corpse: RigidBody3D) -> void:
	var gun := corpse.get_node_or_null("Visual/Gun") as MeshInstance3D
	if gun == null:
		return
	var gun_body := RigidBody3D.new()
	gun_body.add_to_group(CORPSE_GROUP)
	gun_body.collision_layer = 0
	gun_body.collision_mask = 1
	gun_body.mass = GUN_MASS
	gun_body.angular_damp = 0.2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.14, 0.14, 0.5)
	shape.shape = box
	gun_body.add_child(shape)
	corpse.get_parent().add_child(gun_body)
	gun_body.global_transform = gun.global_transform
	gun.reparent(gun_body, true)  # keep world transform + toon material

	var dir := _last_hit_dir
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	gun_body.apply_central_impulse(dir * GUN_DROP_FORWARD + Vector3.UP * GUN_DROP_UP)
	gun_body.apply_torque_impulse(Vector3(randf_range(-2.0, 2.0),
			randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)))

	var tween := gun_body.create_tween()
	tween.tween_interval(CORPSE_SETTLE)
	tween.tween_property(gun, "scale", Vector3.ZERO, CORPSE_FADE).set_ease(Tween.EASE_IN)
	tween.tween_callback(gun_body.queue_free)


## Best estimate of where the killing shot came from (the player is the only
## shooter), used to launch the corpse away from the muzzle.
func _shooter_pos() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return _last_known_player_pos
