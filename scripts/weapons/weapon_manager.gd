class_name WeaponManager
extends Node3D
## Sits under the player camera. Owns the three weapons, fires hitscan rays,
## applies recoil to the Recoil node above the camera, and animates the
## first-person rig (sway, ADS, kick, muzzle flash).

const HIT_MASK := 0b1001  # world (1) + hitbox (8)
const HIP_POSITION := Vector3(0.24, -0.2, -0.45)
const ADS_POSITION := Vector3(0.0, -0.09, -0.32)
const RECOIL_RESET_GAP := 0.4  # seconds without firing before pattern resets

var weapon_datas: Array[WeaponData] = [
	preload("res://data/weapons/pistol.tres"),
	preload("res://data/weapons/rifle.tres"),
	preload("res://data/weapons/shotgun.tres"),
]

var current_index := 0
var ads_amount := 0.0

var _mag: Array[int] = []
var _reserve: Array[int] = []
var _models: Array[Node3D] = []
var _flashes: Array[Node3D] = []

var _cooldown := 0.0
var _reloading := false
var _reload_left := 0.0
var _switch_left := 0.0
var _recoil_index := 0
var _last_shot_time := -100.0
var _bloom := 0.0
var _flash_left := 0.0
var _kick_z := 0.0
var _sway_target := Vector2.ZERO
var _sway_offset := Vector2.ZERO

var _impact_material: StandardMaterial3D

@onready var camera: Camera3D = get_parent() as Camera3D
@onready var recoil_node: Node3D = camera.get_parent() as Node3D
@onready var player: CharacterBody3D = owner as CharacterBody3D


func _ready() -> void:
	for data in weapon_datas:
		_mag.append(data.mag_size)
		_reserve.append(data.start_reserve)
		var model := Node3D.new()
		model.name = data.weapon_name
		# Added to the (already in-tree) manager BEFORE building: the model-fit
		# below reads global_transform on freshly-instanced children, which only
		# resolves correctly once the whole parent chain is live in the tree.
		add_child(model)
		_build_weapon_model(model, data)
		_models.append(model)

	_impact_material = StandardMaterial3D.new()
	_impact_material.albedo_color = Color(1.0, 0.85, 0.4)
	_impact_material.emission_enabled = true
	_impact_material.emission = Color(1.0, 0.7, 0.2)
	_impact_material.emission_energy_multiplier = 2.0

	position = HIP_POSITION
	_show_only_current()
	# Deferred so the HUD (readied later in the tree) catches the initial state.
	_emit_state.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_sway_target -= event.relative * 0.0006
		_sway_target = _sway_target.clampf(-0.03, 0.03)
	elif event.is_action_pressed("weapon_1"):
		_equip(0)
	elif event.is_action_pressed("weapon_2"):
		_equip(1)
	elif event.is_action_pressed("weapon_3"):
		_equip(2)
	elif event.is_action_pressed("weapon_next"):
		_equip((current_index + 1) % weapon_datas.size())
	elif event.is_action_pressed("weapon_prev"):
		_equip((current_index - 1 + weapon_datas.size()) % weapon_datas.size())


func _process(delta: float) -> void:
	if player.is_dead:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_switch_left = maxf(_switch_left - delta, 0.0)
	_update_reload(delta)
	_update_ads(delta)
	_update_fire()
	_update_rig(delta)
	_update_recoil_recovery(delta)
	_update_muzzle_flash(delta)
	_bloom = move_toward(_bloom, 0.0, 9.0 * delta)


# ---------------------------------------------------------------- firing

func _update_fire() -> void:
	var data := _data()
	var wants_fire := Input.is_action_pressed("fire") if data.auto \
			else Input.is_action_just_pressed("fire")
	if not wants_fire or _cooldown > 0.0 or _reloading or _switch_left > 0.0:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _mag[current_index] <= 0:
		_start_reload()  # dry fire -> auto reload
		return
	_fire()


func _fire() -> void:
	var data := _data()
	_mag[current_index] -= 1
	_cooldown = 1.0 / data.fire_rate

	var spread := get_current_spread_deg()
	var any_hit := false
	var any_headshot := false
	var any_kill := false
	var killed_name := ""
	for i in data.pellets:
		var result := _fire_ray(spread, data)
		if result.is_empty():
			continue
		any_hit = true
		any_headshot = any_headshot or result.headshot
		if result.killed:
			any_kill = true
			killed_name = result.target_name

	if any_hit:
		GameEvents.hit_confirmed.emit(any_headshot, any_kill)
	if any_kill:
		GameEvents.enemy_killed.emit(killed_name, any_headshot, data.weapon_name)

	_apply_recoil(data)
	_bloom = minf(_bloom + data.bloom_per_shot_deg, data.max_bloom_deg)
	_last_shot_time = _now()
	_kick_z = minf(_kick_z + 0.05, 0.13)
	_flash_left = 0.055
	_flashes[current_index].visible = true
	GameEvents.sound_emitted.emit(player.global_position, data.sound_radius)
	GameEvents.ammo_changed.emit(_mag[current_index], _reserve[current_index])

	if _mag[current_index] <= 0:
		_start_reload()


## Casts one hitscan ray. Returns {} on miss, otherwise hit info.
func _fire_ray(spread_deg: float, data: WeaponData) -> Dictionary:
	var from := camera.global_position
	var dir := _spread_dir(spread_deg)
	var params := PhysicsRayQueryParameters3D.create(
		from, from + dir * data.max_range, HIT_MASK, [player.get_rid()])
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	# Tracer is drawn from the muzzle (the flash node sits at the barrel tip), not
	# the camera, so it streaks from the gun instead of the player's face.
	var muzzle_pos: Vector3 = _flashes[current_index].global_position
	if hit.is_empty():
		GameEvents.bullet_tracer.emit(muzzle_pos, from + dir * data.max_range)
		return {}
	GameEvents.bullet_tracer.emit(muzzle_pos, hit.position)
	var collider: Object = hit.collider
	if collider is HitboxComponent:
		# Pass the contact point + bullet direction so the enemy can react to the
		# precise shot (directional death ragdoll, headshot head-pop).
		var info: Dictionary = (collider as HitboxComponent).take_hit(
			data.damage, player.global_position, hit.position, dir)
		var target: Node = (collider as HitboxComponent).owner
		return {
			"headshot": info.headshot,
			"killed": info.killed,
			"target_name": target.name if target else "Enemy",
		}
	GameEvents.bullet_impact.emit(hit.position, hit.normal)
	_spawn_impact(hit.position, hit.normal)
	return {}


func _spread_dir(spread_deg: float) -> Vector3:
	var t := tan(deg_to_rad(spread_deg) * sqrt(randf()))
	var a := randf() * TAU
	var local := Vector3(t * cos(a), t * sin(a), -1.0).normalized()
	return (camera.global_transform.basis * local).normalized()


func _apply_recoil(data: WeaponData) -> void:
	if _now() - _last_shot_time > RECOIL_RESET_GAP:
		_recoil_index = 0
	var pattern := data.recoil_pattern
	if pattern.is_empty():
		return
	var kick := pattern[mini(_recoil_index, pattern.size() - 1)]
	_recoil_index += 1
	recoil_node.rotation.x = minf(
		recoil_node.rotation.x + deg_to_rad(kick.y), deg_to_rad(18.0))
	recoil_node.rotation.y += deg_to_rad(kick.x) * (1.0 - ads_amount * 0.3)


func _update_recoil_recovery(delta: float) -> void:
	var speed := _data().recoil_recovery
	recoil_node.rotation.x = lerpf(recoil_node.rotation.x, 0.0, speed * delta)
	recoil_node.rotation.y = lerpf(recoil_node.rotation.y, 0.0, speed * delta)


# ---------------------------------------------------------------- reload / switch

func _update_reload(delta: float) -> void:
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	if not _reloading:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_finish_reload()


func _start_reload() -> void:
	var data := _data()
	if _reloading or _switch_left > 0.0:
		return
	if _mag[current_index] >= data.mag_size or _reserve[current_index] <= 0:
		return
	_reloading = true
	_reload_left = data.reload_time
	# TODO: shotgun should reload shell-by-shell and be interruptible.


func _finish_reload() -> void:
	_reloading = false
	var data := _data()
	var needed := data.mag_size - _mag[current_index]
	var taken := mini(needed, _reserve[current_index])
	_mag[current_index] += taken
	_reserve[current_index] -= taken
	GameEvents.ammo_changed.emit(_mag[current_index], _reserve[current_index])


func _equip(index: int) -> void:
	if index == current_index or player.is_dead:
		return
	current_index = index
	_reloading = false
	_recoil_index = 0
	_switch_left = 0.3
	_show_only_current()
	_emit_state()


func _show_only_current() -> void:
	for i in _models.size():
		_models[i].visible = i == current_index
	_flashes[current_index].visible = false


func reset_loadout() -> void:
	for i in weapon_datas.size():
		_mag[i] = weapon_datas[i].mag_size
		_reserve[i] = weapon_datas[i].start_reserve
	_reloading = false
	_emit_state()


## Ammo crate pickup: one magazine of reserve for every weapon.
func add_reserve_ammo() -> void:
	for i in weapon_datas.size():
		_reserve[i] = mini(_reserve[i] + weapon_datas[i].mag_size,
				weapon_datas[i].max_reserve)
	GameEvents.ammo_changed.emit(_mag[current_index], _reserve[current_index])


func _emit_state() -> void:
	GameEvents.weapon_changed.emit(_data().weapon_name)
	GameEvents.ammo_changed.emit(_mag[current_index], _reserve[current_index])


# ---------------------------------------------------------------- rig animation

func _update_ads(delta: float) -> void:
	var data := _data()
	var wants_ads := Input.is_action_pressed("ads") and not _reloading \
			and _switch_left <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var target := 1.0 if wants_ads else 0.0
	ads_amount = move_toward(ads_amount, target, delta / maxf(data.ads_time, 0.01))


func _update_rig(delta: float) -> void:
	_sway_offset = _sway_offset.lerp(_sway_target, 10.0 * delta)
	_sway_target = _sway_target.lerp(Vector2.ZERO, 10.0 * delta)
	_kick_z = lerpf(_kick_z, 0.0, 10.0 * delta)

	var base := HIP_POSITION.lerp(ADS_POSITION, ads_amount)
	var sway_scale := 1.0 - ads_amount * 0.8
	var equip_dip := _switch_left * 0.6  # weapon rises while equipping
	position = base + Vector3(
		_sway_offset.x * sway_scale,
		_sway_offset.y * sway_scale - equip_dip,
		_kick_z)
	rotation.z = lerpf(rotation.z, -_sway_offset.x * 2.0 * sway_scale, 10.0 * delta)
	rotation.x = lerpf(rotation.x, _sway_offset.y * 2.0 * sway_scale, 10.0 * delta)


func _update_muzzle_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_flashes[current_index].visible = false


# ---------------------------------------------------------------- queries

func _data() -> WeaponData:
	return weapon_datas[current_index]


func blend_fov(move_fov: float) -> float:
	return lerpf(move_fov, _data().ads_fov, ads_amount)


func get_current_spread_deg() -> float:
	var data := _data()
	var aim_spread: float = lerpf(data.hip_spread_deg, data.ads_spread_deg, ads_amount)
	var move_bloom: float = player.get_movement_bloom_deg() * (1.0 - ads_amount * 0.7)
	return aim_spread + _bloom + move_bloom


func get_reload_progress() -> float:
	if not _reloading:
		return 0.0
	return 1.0 - _reload_left / _data().reload_time


# ---------------------------------------------------------------- cosmetics

## Biggest mesh by AABB volume (ignores small decorative sub-meshes like glass/
## light bits some Sketchfab exports carry), used as the reference for cancelling
## the import chain's rotation+scale.
func _biggest_mesh(node: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_vol := -1.0
	for mi in _all_mesh_instances(node):
		var s: Vector3 = (mi as MeshInstance3D).get_aabb().size
		var vol: float = s.x * s.y * s.z
		if vol > best_vol:
			best_vol = vol
			best = mi as MeshInstance3D
	return best


func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


## AABB of every mesh under `node`, expressed in `ref`'s LOCAL frame (not world) --
## so the fit below is independent of where the camera / weapon manager happens to
## be aimed when the weapon is built.
func _mesh_tree_aabb_in(node: Node, ref: Node3D) -> AABB:
	var ref_inv := ref.global_transform.affine_inverse()
	var acc := AABB()
	var first := true
	for mi in _all_mesh_instances(node):
		var m := mi as MeshInstance3D
		var box: AABB = (ref_inv * m.global_transform) * (m.get_aabb())
		if first:
			acc = box
			first = false
		else:
			acc = acc.merge(box)
	return acc


## Populates `root` (already inside the tree -- see _ready) with either the real
## weapon mesh, auto-fit to a sane first-person size/orientation, or a procedural
## placeholder box+barrel if no mesh is authored yet.
func _build_weapon_model(root: Node3D, data: WeaponData) -> void:
	if data.model_scene != null:
		var model := data.model_scene.instantiate() as Node3D
		model.name = "Model"
		root.add_child(model)  # must be in-tree before global_transform below resolves

		var main_mesh := _biggest_mesh(model)
		if main_mesh != null:
			# Cancel the WHOLE import chain's rotation+scale (Sketchfab/fbx2gltf
			# fixups stack arbitrarily), then rotate by the small hand-derived fix
			# that points THIS asset's muzzle at -Z. Kept as a raw Basis multiply,
			# never round-tripped through Euler -- see the WeaponData comment for why.
			# Measured RELATIVE to `model` (not from the mesh's global basis), so the
			# camera's orientation when this runs at spawn can't bake a tilt into it.
			var rel := model.global_transform.affine_inverse() * main_mesh.global_transform
			var derot: Basis = rel.basis.inverse()
			var fix := Basis.from_euler(data.model_fix_rotation_deg * PI / 180.0)
			var roll := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(data.model_roll_deg))
			var corrected := roll * fix * derot
			model.transform.basis = corrected

			# Auto-scale to the target length, then auto-recentre on the bbox
			# centroid (measured in root's local frame at this unscaled-but-rotated
			# pose, then scaled).
			var aabb := _mesh_tree_aabb_in(model, root)
			var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			var scale_factor := data.model_target_length / maxf(longest, 0.0001)
			model.transform.basis = corrected * scale_factor
			model.position = -aabb.get_center() * scale_factor + data.model_offset
	else:
		# Placeholder for a weapon with no authored mesh yet: procedural box+barrel.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.model_color
		mat.metallic = 0.4
		mat.roughness = 0.55

		var body := MeshInstance3D.new()
		var body_mesh := BoxMesh.new()
		body_mesh.size = Vector3(0.07, 0.12, data.model_length)
		body.mesh = body_mesh
		body.material_override = mat
		body.position = Vector3(0.0, -0.02, -data.model_length * 0.5)
		root.add_child(body)

		var barrel := MeshInstance3D.new()
		var barrel_mesh := BoxMesh.new()
		barrel_mesh.size = Vector3(0.035, 0.035, data.model_length * 0.45)
		barrel.mesh = barrel_mesh
		barrel.material_override = mat
		barrel.position = Vector3(0.0, 0.045, -data.model_length * 0.85)
		root.add_child(barrel)

	# Muzzle flash: emissive billboard quad + light, hidden until a shot.
	var flash := Node3D.new()
	flash.name = "MuzzleFlash"
	flash.position = data.muzzle_offset

	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.75, 0.25, 0.9)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.6, 0.1)
	flash_mat.emission_energy_multiplier = 8.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flash_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	flash_mesh.mesh = quad
	flash_mesh.material_override = flash_mat
	flash.add_child(flash_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 3.0
	light.omni_range = 5.0
	flash.add_child(light)

	flash.visible = false
	root.add_child(flash)
	_flashes.append(flash)


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var particles := CPUParticles3D.new()
	# CPUParticles3D defaults to emitting = true, so a one_shot burst would fire at
	# the parent origin the instant it enters the tree -- before global_position is
	# set below. Start it off and only emit AFTER positioning at the contact point.
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 6
	particles.lifetime = 0.25
	particles.explosiveness = 1.0
	particles.direction = normal
	particles.spread = 30.0
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 3.5
	particles.gravity = Vector3(0.0, -8.0, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	mesh.material = _impact_material
	particles.mesh = mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = point + normal * 0.02
	particles.emitting = true  # burst now, at the contact point
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)
	# Bullet-hole decals are handled by the BulletFX autoload (GameEvents.bullet_impact).
	# TODO: surface-dependent impact effects (per-material spark colour).


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
