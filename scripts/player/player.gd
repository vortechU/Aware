class_name Player
extends CharacterBody3D
## First-person player controller: movement states (walk/sprint/crouch/prone/
## slide), stamina, camera bob, plus health/armor/regen and death handling.
## Weapon handling lives in WeaponManager (child of the camera).

enum MoveState { WALK, SPRINT, CROUCH, PRONE, SLIDE, WALLRUN, VAULT }

# --- Look ---
@export var mouse_sensitivity: float = 0.0022
@export var base_fov: float = 75.0
@export var sprint_fov_add: float = 9.0

# --- Speeds (m/s) ---
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.2
@export var crouch_speed: float = 2.6
@export var prone_speed: float = 1.2

# --- Acceleration / friction (m/s^2) ---
@export var ground_acceleration: float = 45.0
@export var ground_friction: float = 38.0
@export var air_acceleration: float = 12.0
@export var jump_velocity: float = 4.6

# --- Air jump (double jump) ---
@export var max_air_jumps: int = 1            # extra mid-air jumps (1 = double jump; bump for more)
@export var air_jump_velocity: float = 4.4    # absolute upward speed per air jump (cancels any fall)
@export var air_jump_stamina_cost: float = 10.0

# --- Slide ---
@export var slide_boost_speed: float = 9.8
@export var slide_friction: float = 5.5
@export var slide_max_time: float = 1.25
@export var slide_min_enter_speed: float = 6.0
@export var slide_camera_tilt_deg: float = 5.0

# --- Wall-run ---
@export var wallrun_speed: float = 9.0
@export var wallrun_accel: float = 16.0
@export var wallrun_gravity: float = 2.0       # near-zero "stick" gravity
@export var wallrun_max_time: float = 1.6
@export var wallrun_min_speed: float = 4.0
@export var wallrun_stick_force: float = 2.0
@export var wallrun_jump_up: float = 5.0
@export var wallrun_jump_push: float = 6.0      # launch away from the wall
@export var wallrun_camera_tilt_deg: float = 12.0
@export var wallrun_stamina_drain: float = 12.0
@export var wallrun_cooldown: float = 0.3

# --- Dash ---
@export var dash_speed: float = 16.0
@export var dash_duration: float = 0.16
@export var dash_max_charges: int = 2
@export var dash_recharge_time: float = 1.4   # seconds to refill one charge
@export var dash_stamina_cost: float = 12.0
@export var dash_fov_add: float = 8.0

# --- Vault ---
@export var vault_max_height: float = 1.6      # tallest obstacle we can mantle (crates are 1.4)
@export var vault_min_height: float = 0.4      # below this you just step over
@export var vault_check_distance: float = 1.2  # how far ahead to look for an obstacle
@export var vault_duration: float = 0.32       # time to clear the obstacle
@export var vault_arc_height: float = 0.45     # extra lift so we clear the front edge
@export var vault_forward_clearance: float = 1.4  # land this far past the near face
@export var vault_exit_speed: float = 6.0      # forward speed restored on landing
@export var vault_stamina_cost: float = 10.0

# --- Momentum (smooth continuous movement builds speed, up to a cap) ---
@export var momentum_max_bonus: float = 0.5        # +50% top speed at full momentum
@export var momentum_build_rate: float = 0.35      # per second while moving smoothly
@export var momentum_decay_rate: float = 1.2       # per second when the flow breaks
@export var momentum_align_threshold: float = 0.6  # wish·velocity dot above this = smooth
@export var momentum_min_speed: float = 3.0        # must move this fast to build
@export var momentum_fov_add: float = 7.0          # extra FOV at full momentum

# --- Stamina ---
@export var max_stamina: float = 100.0
@export var stamina_drain_per_sec: float = 22.0
@export var stamina_regen_per_sec: float = 16.0
@export var stamina_regen_delay: float = 1.0
@export var slide_stamina_cost: float = 15.0
@export var jump_stamina_cost: float = 8.0

# --- Health / armor ---
@export var max_health: float = 100.0
@export var max_armor: float = 100.0
@export var start_armor: float = 25.0
@export var health_regen_delay: float = 5.0
@export var health_regen_per_sec: float = 12.0
const ARMOR_ABSORB := 0.3  # armor soaks 30% of incoming damage

# --- Body dimensions per stance ---
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const PRONE_HEIGHT := 0.7
const EYE_STAND := 1.62
const EYE_CROUCH := 1.02
const EYE_PRONE := 0.42
const EYE_SLIDE := 0.85

# --- Camera bob ---
@export var bob_frequency: float = 1.85  # cycles scale vs speed
var _bob_amplitudes := {
	MoveState.WALK: 0.045,
	MoveState.SPRINT: 0.075,
	MoveState.CROUCH: 0.024,
	MoveState.PRONE: 0.012,
	MoveState.SLIDE: 0.0,
	MoveState.WALLRUN: 0.0,
	MoveState.VAULT: 0.0,
}

var move_state: MoveState = MoveState.WALK
var stamina: float
var health: float
var armor: float
var is_dead: bool = false
var momentum: float = 0.0  # 0..1 smooth-movement speed bonus (read by HUD/FOV)

var _prone_toggled := false
var _can_sprint := true
var _stamina_use_time := -100.0
var _last_damage_time := -100.0
var _slide_dir := Vector3.ZERO
var _slide_speed := 0.0
var _slide_time := 0.0
var _bob_time := 0.0

# --- Wall-run state ---
var _wall_normal := Vector3.ZERO
var _wallrun_time := 0.0
var _wallrun_side := 1            # -1 / +1, which side the wall is on (camera roll)
var _wallrun_cd_time := 0.0       # remaining cooldown before re-entry
var _last_wallrun_normal := Vector3.ZERO

# --- Dash state ---
var _dash_charges := 0
var _dash_recharge_timer := 0.0
var _dash_time_left := 0.0
var _dash_dir := Vector3.ZERO

# --- Air jump state ---
var _air_jumps_left := 0

# --- Vault state ---
const VAULT_MASK := 1  # "world" physics layer (crates + procedural boxes)
var _vault_start := Vector3.ZERO
var _vault_target := Vector3.ZERO
var _vault_dir := Vector3.ZERO
var _vault_time := 0.0

@onready var head: Node3D = $Head
@onready var bob_node: Node3D = $Head/Bob
@onready var camera: Camera3D = $Head/Bob/Recoil/Camera
@onready var weapon_manager: Node3D = $Head/Bob/Recoil/Camera/WeaponManager
@onready var collider: CollisionShape3D = $Collider
@onready var stand_check: ShapeCast3D = $StandCheck
@onready var capsule: CapsuleShape3D = collider.shape as CapsuleShape3D


func _ready() -> void:
	stamina = max_stamina
	health = max_health
	armor = start_armor
	_dash_charges = dash_max_charges
	_air_jumps_left = max_air_jumps
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_emit_vitals()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_dead:
			return
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity, -1.5, 1.5)
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = velocity.move_toward(Vector3.ZERO, ground_friction * delta)
		move_and_slide()
		return

	# Vault fully owns position along a scripted arc; no gravity / collision.
	if move_state == MoveState.VAULT:
		_process_vault(delta)
		return

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()

	_update_move_state(input_2d)
	_update_stamina(delta, input_2d)
	_update_health_regen(delta)
	if _wallrun_cd_time > 0.0:
		_wallrun_cd_time = maxf(_wallrun_cd_time - delta, 0.0)
	_update_dash_recharge(delta)

	# Refill air jumps while grounded or wall-running (wall contact refreshes the
	# double jump, so chaining wall-run -> air jump stays generous).
	if is_on_floor() or move_state == MoveState.WALLRUN:
		_air_jumps_left = max_air_jumps

	# Dash start: a charged burst, on the ground or in the air, but not while
	# sliding or wall-running. The active dash itself is handled in the branch.
	if Input.is_action_just_pressed("dash") and _dash_time_left <= 0.0 \
			and _dash_charges > 0 and stamina >= dash_stamina_cost \
			and move_state != MoveState.SLIDE and move_state != MoveState.WALLRUN:
		_start_dash(wish_dir)

	# Vault: jump into a low obstacle to mantle over it (takes priority over a
	# normal jump). Falls through to a normal jump when nothing is vaultable.
	if Input.is_action_just_pressed("jump") and _dash_time_left <= 0.0 \
			and move_state != MoveState.SLIDE and move_state != MoveState.WALLRUN:
		if _try_start_vault():
			_process_vault(delta)
			return

	# Gravity (wall-run applies its own reduced gravity internally)
	if not is_on_floor() and move_state != MoveState.WALLRUN:
		velocity += get_gravity() * delta

	if move_state == MoveState.SLIDE:
		_process_slide(delta)
	elif move_state == MoveState.WALLRUN:
		_process_wallrun(delta)
	elif _dash_time_left > 0.0:
		# Active dash overrides horizontal control; gravity still owns vertical.
		_dash_time_left -= delta
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed
	else:
		_try_enter_wallrun(wish_dir)
		if move_state == MoveState.WALLRUN:
			_process_wallrun(delta)
		else:
			# Jump: a ground jump off the floor, or an air (double) jump while
			# airborne with a charge left. Not allowed from prone.
			if Input.is_action_just_pressed("jump") and move_state != MoveState.PRONE:
				if is_on_floor() and stamina > jump_stamina_cost:
					velocity.y = jump_velocity
					_spend_stamina(jump_stamina_cost)
				elif not is_on_floor() and _air_jumps_left > 0 \
						and stamina > air_jump_stamina_cost:
					velocity.y = air_jump_velocity  # absolute: cancels any fall for a clean pop
					_air_jumps_left -= 1
					_spend_stamina(air_jump_stamina_cost)

			var target_speed := _current_max_speed()
			var target_vel := wish_dir * target_speed
			var accel := ground_acceleration if wish_dir != Vector3.ZERO else ground_friction
			if not is_on_floor():
				accel = air_acceleration
			velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
			velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	move_and_slide()
	_update_momentum(delta, wish_dir)
	_update_body_shape(delta)


func _process(delta: float) -> void:
	if is_dead:
		return
	_update_camera_bob(delta)
	_update_fov(delta)
	_update_camera_tilt(delta)


# ---------------------------------------------------------------- movement

func _current_max_speed() -> float:
	# Crouch/prone are deliberate, slow stances — no momentum bonus.
	match move_state:
		MoveState.CROUCH:
			return crouch_speed
		MoveState.PRONE:
			return prone_speed
	var base := sprint_speed if move_state == MoveState.SPRINT else walk_speed
	return base * (1.0 + momentum * momentum_max_bonus)


func _update_move_state(input_2d: Vector2) -> void:
	if move_state == MoveState.SLIDE or move_state == MoveState.WALLRUN \
			or move_state == MoveState.VAULT:
		return  # slide / wall-run / vault manage their own exit

	# Prone toggle
	if Input.is_action_just_pressed("prone"):
		if move_state == MoveState.PRONE:
			if _has_headroom(CROUCH_HEIGHT):
				_prone_toggled = false
		else:
			_prone_toggled = true
	if _prone_toggled:
		_set_state(MoveState.PRONE)
		return

	var crouch_held := Input.is_action_pressed("crouch")
	var sprinting := Input.is_action_pressed("sprint") and _can_sprint \
			and input_2d.y < -0.1 and is_on_floor() \
			and not _is_aiming()

	# Enter slide: crouch pressed while sprinting fast enough
	if Input.is_action_just_pressed("crouch") and move_state == MoveState.SPRINT \
			and is_on_floor() and _horizontal_speed() > slide_min_enter_speed:
		_enter_slide()
		return

	if crouch_held:
		_set_state(MoveState.CROUCH)
	elif move_state == MoveState.CROUCH and not _has_headroom(STAND_HEIGHT):
		_set_state(MoveState.CROUCH)  # forced to stay crouched under low ceiling
	elif sprinting:
		_set_state(MoveState.SPRINT)
	else:
		_set_state(MoveState.WALK)


func _set_state(state: MoveState) -> void:
	move_state = state


func _enter_slide() -> void:
	_set_state(MoveState.SLIDE)
	_slide_dir = Vector3(velocity.x, 0.0, velocity.z).normalized()
	if _slide_dir == Vector3.ZERO:
		_slide_dir = -transform.basis.z
	_slide_speed = maxf(_horizontal_speed(), slide_boost_speed)
	_slide_time = 0.0
	_spend_stamina(slide_stamina_cost)


func _process_slide(delta: float) -> void:
	_slide_time += delta
	_slide_speed = maxf(_slide_speed - slide_friction * delta, 0.0)
	velocity.x = _slide_dir.x * _slide_speed
	velocity.z = _slide_dir.z * _slide_speed

	# Slide-jump keeps momentum
	if Input.is_action_just_pressed("jump") and is_on_floor() and stamina > jump_stamina_cost:
		velocity.y = jump_velocity
		_spend_stamina(jump_stamina_cost)
		_exit_slide()
		return

	if _slide_time >= slide_max_time or _slide_speed <= crouch_speed + 0.4 \
			or not is_on_floor():
		_exit_slide()


func _exit_slide() -> void:
	if Input.is_action_pressed("crouch") or not _has_headroom(STAND_HEIGHT):
		_set_state(MoveState.CROUCH)
	else:
		_set_state(MoveState.WALK)


# ---------------------------------------------------------------- wall-run

## Stick to a wall and run along it when the player jumps into one while moving.
## Detection uses the body's own last-frame wall contact, so no extra raycast
## nodes are needed. Re-entry on the same wall is gated by a cooldown plus the
## last wall normal, so you can chain between opposite walls but not spam one.
func _try_enter_wallrun(wish_dir: Vector3) -> void:
	if is_on_floor() or _wallrun_cd_time > 0.0:
		return
	if not is_on_wall_only() or wish_dir == Vector3.ZERO:
		return
	if _horizontal_speed() < wallrun_min_speed:
		return
	var normal := get_wall_normal()
	# Same wall we just left? Block until we touch ground or a different wall.
	if _last_wallrun_normal != Vector3.ZERO and normal.dot(_last_wallrun_normal) > 0.9:
		return
	_set_state(MoveState.WALLRUN)
	_wall_normal = normal
	_wallrun_time = 0.0
	# Lean the camera toward whichever side the wall is on.
	_wallrun_side = -1 if transform.basis.x.dot(normal) > 0.0 else 1


func _process_wallrun(delta: float) -> void:
	_wallrun_time += delta

	# Wall-jump off the wall.
	if Input.is_action_just_pressed("jump") and stamina > 0.0:
		_wall_jump()
		return

	# Drop off when the run runs out, we land, lose the wall, or gas out.
	if _wallrun_time >= wallrun_max_time or is_on_floor() \
			or not is_on_wall_only() or stamina <= 0.0:
		_exit_wallrun()
		return

	_wall_normal = get_wall_normal()

	# Reduced gravity keeps the player pinned to the wall.
	velocity.y -= wallrun_gravity * delta

	# Run along the wall in the look/wish direction.
	var tangent := _wall_normal.cross(Vector3.UP)
	if tangent.dot(-transform.basis.z) < 0.0:
		tangent = -tangent
	tangent = tangent.normalized()
	var target := tangent * wallrun_speed
	velocity.x = move_toward(velocity.x, target.x, wallrun_accel * delta)
	velocity.z = move_toward(velocity.z, target.z, wallrun_accel * delta)

	# Gentle pull into the wall to keep contact.
	velocity += -_wall_normal * wallrun_stick_force * delta

	_spend_stamina(wallrun_stamina_drain * delta)

	# Lost too much speed to keep running.
	if _horizontal_speed() < wallrun_min_speed:
		_exit_wallrun()


func _wall_jump() -> void:
	# Keep the along-wall momentum, kick off the wall and upward.
	var along := velocity - velocity.dot(_wall_normal) * _wall_normal
	along.y = 0.0
	velocity = along + _wall_normal * wallrun_jump_push + Vector3.UP * wallrun_jump_up
	_spend_stamina(wallrun_stamina_drain)
	_wallrun_cd_time = wallrun_cooldown
	_last_wallrun_normal = _wall_normal
	_set_state(MoveState.WALK)


func _exit_wallrun() -> void:
	_wallrun_cd_time = wallrun_cooldown
	_last_wallrun_normal = _wall_normal
	_set_state(MoveState.WALK)


# ---------------------------------------------------------------- dash

## A charged dash burst, usable on the ground or in the air. Direction is the
## movement input, or the body's facing when there is no input. Horizontal only,
## so air-dashes keep their vertical momentum.
func _start_dash(wish_dir: Vector3) -> void:
	var dir := wish_dir
	if dir == Vector3.ZERO:
		dir = (-transform.basis.z).normalized()  # body forward (always horizontal)
	_dash_dir = dir
	_dash_time_left = dash_duration
	_dash_charges -= 1
	_spend_stamina(dash_stamina_cost)


## Refills one charge every dash_recharge_time while below the cap.
func _update_dash_recharge(delta: float) -> void:
	if _dash_charges >= dash_max_charges:
		_dash_recharge_timer = 0.0
		return
	_dash_recharge_timer += delta
	if _dash_recharge_timer >= dash_recharge_time:
		_dash_recharge_timer -= dash_recharge_time
		_dash_charges = mini(_dash_charges + 1, dash_max_charges)


# ---------------------------------------------------------------- momentum

## Smooth continuous movement (fast enough, wish input aligned to velocity, not
## smacking a wall head-on) builds momentum toward 1.0, which raises the running
## top speed through _current_max_speed (capped at +momentum_max_bonus). Wall-run,
## slide and the dash window all count as "in flow"; stopping, hard-reversing or
## hitting a wall decays it faster than it builds.
func _update_momentum(delta: float, wish_dir: Vector3) -> void:
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var hspeed := hvel.length()
	var smooth := false
	if hspeed > momentum_min_speed and wish_dir != Vector3.ZERO:
		var dir := hvel / hspeed
		var aligned := wish_dir.dot(dir) > momentum_align_threshold
		var smacked := is_on_wall() and get_wall_normal().dot(dir) < -0.5
		smooth = aligned and not smacked
	if move_state == MoveState.WALLRUN or move_state == MoveState.SLIDE \
			or _dash_time_left > 0.0:
		smooth = true
	if smooth:
		momentum = minf(momentum + momentum_build_rate * delta, 1.0)
	else:
		momentum = maxf(momentum - momentum_decay_rate * delta, 0.0)


# ---------------------------------------------------------------- vault

## Mantle over a low obstacle (crates, low cover) directly in front. Probes the
## "world" layer with three rays: a low ray must hit an obstacle, a high ray must
## be clear (so tall walls/pillars are rejected), and a downward ray finds the
## top surface and confirms it sits within the vault height range. On success it
## sets up the scripted mantle and switches to MoveState.VAULT.
func _try_start_vault() -> bool:
	var forward := -transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]

	# 1. A low obstacle right in front?
	var low_from := global_position + Vector3(0.0, 0.5, 0.0)
	var low_q := PhysicsRayQueryParameters3D.create(
			low_from, low_from + forward * vault_check_distance, VAULT_MASK, exclude)
	var low_hit := space.intersect_ray(low_q)
	if low_hit.is_empty():
		return false

	# 2. Above vault height must be clear, else it is a wall/pillar.
	var high_from := global_position + Vector3(0.0, vault_max_height + 0.1, 0.0)
	var high_q := PhysicsRayQueryParameters3D.create(
			high_from, high_from + forward * vault_check_distance, VAULT_MASK, exclude)
	if not space.intersect_ray(high_q).is_empty():
		return false

	# 3. Find the top surface just past the near face.
	var face: Vector3 = low_hit.position
	var top_from := face + forward * 0.35 + Vector3(0.0, vault_max_height + 0.5, 0.0)
	var top_q := PhysicsRayQueryParameters3D.create(
			top_from, top_from + Vector3(0.0, -(vault_max_height + 1.0), 0.0), VAULT_MASK, exclude)
	var top_hit := space.intersect_ray(top_q)
	if top_hit.is_empty():
		return false
	var top_y: float = top_hit.position.y
	var rise := top_y - global_position.y
	if rise < vault_min_height or rise > vault_max_height:
		return false

	# Set up the mantle to a point just past the obstacle, on top of it.
	var horiz_dist := Vector2(face.x - global_position.x, face.z - global_position.z).length()
	_vault_start = global_position
	_vault_dir = forward
	_vault_target = global_position + forward * (horiz_dist + vault_forward_clearance)
	_vault_target.y = top_y
	_vault_time = 0.0
	_spend_stamina(vault_stamina_cost)
	_set_state(MoveState.VAULT)
	return true


func _process_vault(delta: float) -> void:
	_vault_time += delta
	var t := clampf(_vault_time / vault_duration, 0.0, 1.0)
	var pos := _vault_start.lerp(_vault_target, t)
	pos.y += vault_arc_height * sin(PI * t)  # bow up to clear the front edge
	global_position = pos
	velocity = Vector3.ZERO
	if t >= 1.0:
		_exit_vault()


func _exit_vault() -> void:
	velocity = _vault_dir * vault_exit_speed
	_set_state(MoveState.WALK)


func _horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _has_headroom(required_height: float) -> bool:
	# Sphere (r=0.3) casts up from y=0.6; covered top = 0.6 + target_y + 0.3
	stand_check.target_position = Vector3(0.0, maxf(required_height - 0.9, 0.05), 0.0)
	stand_check.force_shapecast_update()
	return not stand_check.is_colliding()


func _update_body_shape(delta: float) -> void:
	var target_height := STAND_HEIGHT
	match move_state:
		MoveState.CROUCH, MoveState.SLIDE:
			target_height = CROUCH_HEIGHT
		MoveState.PRONE:
			target_height = PRONE_HEIGHT
	capsule.height = lerpf(capsule.height, target_height, 12.0 * delta)
	collider.position.y = capsule.height * 0.5

	var eye := EYE_STAND
	match move_state:
		MoveState.CROUCH:
			eye = EYE_CROUCH
		MoveState.PRONE:
			eye = EYE_PRONE
		MoveState.SLIDE:
			eye = EYE_SLIDE
	head.position.y = lerpf(head.position.y, eye, 12.0 * delta)


# ---------------------------------------------------------------- stamina

func _update_stamina(delta: float, input_2d: Vector2) -> void:
	var draining := move_state == MoveState.SPRINT and input_2d != Vector2.ZERO \
			and is_on_floor()
	if draining:
		_spend_stamina(stamina_drain_per_sec * delta)
	elif _now() - _stamina_use_time > stamina_regen_delay:
		stamina = minf(stamina + stamina_regen_per_sec * delta, max_stamina)

	if stamina <= 1.0:
		_can_sprint = false
	elif stamina >= 15.0:
		_can_sprint = true
	GameEvents.player_stamina_changed.emit(stamina, max_stamina)


func _spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_use_time = _now()


# ---------------------------------------------------------------- camera

func _update_camera_bob(delta: float) -> void:
	var hspeed := _horizontal_speed()
	var amp: float = _bob_amplitudes.get(move_state, 0.045)
	amp *= 1.0 - _ads_amount() * 0.85
	var target := Vector3.ZERO
	if is_on_floor() and hspeed > 0.6:
		_bob_time += delta * hspeed * bob_frequency
		target.y = sin(_bob_time * 2.0) * amp
		target.x = cos(_bob_time) * amp * 1.3
		bob_node.position = bob_node.position.lerp(target, 14.0 * delta)
	else:
		# gentle idle breathing
		_bob_time = 0.0
		target.y = sin(Time.get_ticks_msec() / 1000.0 * 1.4) * 0.006
		bob_node.position = bob_node.position.lerp(target, 4.0 * delta)


func _update_fov(delta: float) -> void:
	var speed_factor := clampf(_horizontal_speed() / sprint_speed, 0.0, 1.0)
	var move_fov := base_fov
	if move_state == MoveState.SPRINT or move_state == MoveState.SLIDE:
		move_fov += sprint_fov_add * speed_factor
	if _dash_time_left > 0.0:
		move_fov += dash_fov_add
	move_fov += momentum * momentum_fov_add
	var target_fov: float = weapon_manager.blend_fov(move_fov)
	camera.fov = lerpf(camera.fov, target_fov, 12.0 * delta)


func _update_camera_tilt(delta: float) -> void:
	var target_roll := 0.0
	if move_state == MoveState.SLIDE:
		target_roll = deg_to_rad(slide_camera_tilt_deg)
	elif move_state == MoveState.WALLRUN:
		target_roll = deg_to_rad(wallrun_camera_tilt_deg) * float(_wallrun_side)
	head.rotation.z = lerpf(head.rotation.z, target_roll, 8.0 * delta)


func _ads_amount() -> float:
	return weapon_manager.ads_amount


func _is_aiming() -> bool:
	return _ads_amount() > 0.2


# ---------------------------------------------------------------- health

func take_damage(amount: float, source_position: Vector3) -> void:
	if is_dead:
		return
	var absorbed := 0.0
	if armor > 0.0:
		absorbed = minf(amount * ARMOR_ABSORB, armor)
		armor -= absorbed
	health -= amount - absorbed
	_last_damage_time = _now()
	GameEvents.player_damaged.emit(amount, source_position)
	_emit_vitals()
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)
	_emit_vitals()


func add_armor(amount: float) -> void:
	if is_dead:
		return
	armor = minf(armor + amount, max_armor)
	_emit_vitals()


func _update_health_regen(delta: float) -> void:
	if health < max_health and _now() - _last_damage_time > health_regen_delay:
		health = minf(health + health_regen_per_sec * delta, max_health)
		_emit_vitals()


func _die() -> void:
	health = 0.0
	is_dead = true
	_emit_vitals()
	GameEvents.player_died.emit()


func respawn_at(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	health = max_health
	armor = start_armor
	stamina = max_stamina
	is_dead = false
	_prone_toggled = false
	_wallrun_time = 0.0
	_wall_normal = Vector3.ZERO
	_wallrun_cd_time = 0.0
	_last_wallrun_normal = Vector3.ZERO
	_dash_charges = dash_max_charges
	_air_jumps_left = max_air_jumps
	_dash_time_left = 0.0
	_dash_recharge_timer = 0.0
	_vault_time = 0.0
	momentum = 0.0
	move_state = MoveState.WALK
	weapon_manager.reset_loadout()
	_emit_vitals()
	GameEvents.player_respawned.emit()


func _emit_vitals() -> void:
	GameEvents.player_health_changed.emit(maxf(health, 0.0), max_health)
	GameEvents.player_armor_changed.emit(armor, max_armor)
	GameEvents.player_stamina_changed.emit(stamina, max_stamina)


## Pickup facade. kind matches Pickup.Type (0 ammo, 1 health, 2 armor).
## Returns false when the pickup would be wasted so it stays in the world.
func try_pickup(kind: int, amount: float) -> bool:
	if is_dead:
		return false
	match kind:
		0:
			weapon_manager.add_reserve_ammo()
			return true
		1:
			if health >= max_health:
				return false
			heal(amount)
			return true
		2:
			if armor >= max_armor:
				return false
			add_armor(amount)
			return true
	return false


# HUD polls this for the dynamic crosshair.
func get_current_spread_deg() -> float:
	return weapon_manager.get_current_spread_deg()


# Extra weapon spread caused by movement, in degrees.
func get_movement_bloom_deg() -> float:
	var bloom := _horizontal_speed() * 0.28
	if not is_on_floor():
		bloom += 2.5
	if move_state == MoveState.CROUCH or move_state == MoveState.PRONE:
		bloom *= 0.45
	return bloom


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
