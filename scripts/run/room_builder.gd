extends Node
## Procedural interior generator for rooms 2+. The authored 44x44 arena is the
## "home" room (room 1); from room 2 on, this node owns the whole interior AND
## the shell: it builds a fresh floor + four walls sized to a seeded per-room
## footprint (variable square, rectangular and L-shaped footprints), then
## regenerates obstacles (StaticBody3D boxes so
## the navmesh bakes from collision shapes, not runtime mesh parsing),
## cover_point markers, enemy spawn points and pickup spots, rebakes the navmesh
## and validates the layout.
## On the first procedural build the authored interior AND the authored shell are
## retired at runtime (build-alongside: no original script or scene content is
## edited, only removed from the tree); room 1 still plays exactly as authored.

# --- footprint -------------------------------------------------------------
## Inner half-extents (x, z) of the authored arena: walls' inner faces sit at
## +/-21, so the playable floor is 42x42 and the player spawns 3 m off the south
## wall at z = 18. Procedural rooms reproduce this geometry at a chosen size.
const ROOM_HALF_DEFAULT := Vector2(21.0, 21.0)
## Which north corner an L-shaped room's notch is cut from (south is the spawn
## edge, so the notch always sits north, keeping the spawn + exit gate on floor).
const CORNER_NW := 0
const CORNER_NE := 1

## Seeded rectangular footprints (inner half-extents x,z): a deliberately WIDE
## spread of size + aspect ratio so consecutive rooms read as different spaces --
## a cramped chamber, a long corridor, a vast arena, not just "another square".
## The 21x21 entry matches the authored arena so the default look is preserved.
## NOTE: layer footprint_pool values index into the combined [FOOTPRINTS +
## L_FOOTPRINTS] list, so new rectangles MUST be appended (never inserted) -- an
## insert would silently shift every L-shape index in LayerCatalog.
const FOOTPRINTS: Array[Vector2] = [
	Vector2(17.0, 17.0),  # 0: compact square
	Vector2(21.0, 21.0),  # 1: standard square (authored size)
	Vector2(24.0, 24.0),  # 2: large square
	Vector2(27.0, 16.0),  # 3: wide hall (long along X)
	Vector2(16.0, 27.0),  # 4: deep hall (long along Z)
	Vector2(26.0, 18.0),  # 5: broad rectangle
	Vector2(14.0, 14.0),  # 6: tight square (close-quarters, smallest)
	Vector2(28.0, 11.0),  # 7: wide corridor (~2.5:1, long sightline along X)
	Vector2(11.0, 28.0),  # 8: deep corridor (~2.5:1, long approach along Z)
	Vector2(30.0, 28.0),  # 9: grand arena (vast open, largest)
]
## Seeded L-shaped footprints: a bounding half-extent with a rectangular notch
## (width,depth) cut from one north corner. The notch is smaller than the
## bounding box on both axes, so the north-centre (x=0) stays open for the gate.
## Combined-list indices are FOOTPRINTS.size() + position (i.e. 10, 11, 12, 13).
const L_FOOTPRINTS: Array[Dictionary] = [
	{"half": Vector2(24.0, 24.0), "notch": Vector2(16.0, 16.0), "corner": CORNER_NE},
	{"half": Vector2(24.0, 22.0), "notch": Vector2(15.0, 14.0), "corner": CORNER_NW},
	{"half": Vector2(26.0, 20.0), "notch": Vector2(16.0, 12.0), "corner": CORNER_NE},
	{"half": Vector2(26.0, 24.0), "notch": Vector2(18.0, 15.0), "corner": CORNER_NW},  # bold deep L
]
## Seeded T-shaped footprints: BOTH north corners notched (`tnotch` = per-corner
## width,depth), leaving a wide south crossbar (the player-spawn edge) and a narrow
## north stem that carries the exit gate. Symmetric across X. Combined-list indices
## continue after the L-shapes: FOOTPRINTS.size() + L_FOOTPRINTS.size() + position.
## The stem must stay wide enough for the gate, so tnotch.x < half.x by a clear margin.
const T_FOOTPRINTS: Array[Dictionary] = [
	{"half": Vector2(26.0, 22.0), "tnotch": Vector2(9.0, 12.0)},   # broad crossbar, slim stem
	{"half": Vector2(24.0, 24.0), "tnotch": Vector2(8.0, 13.0)},
]
## Seeded plus/cross footprints: ALL FOUR corners notched (`notch` = per-corner
## width,depth), leaving a central crossing + four arms (N arm = gate, S arm = spawn,
## E/W arms = flanking sightlines). Symmetric across X and Z. Combined-list indices
## continue after the T-shapes. The notch must stay small enough to leave wide arms.
const PLUS_FOOTPRINTS: Array[Dictionary] = [
	{"half": Vector2(26.0, 24.0), "notch": Vector2(10.0, 11.0)},
	{"half": Vector2(24.0, 24.0), "notch": Vector2(9.0, 10.0)},
]
## Milestone (boss) rooms always use a generous, un-notched square arena.
const MILESTONE_FOOTPRINT := Vector2(24.0, 24.0)
const EDGE_MARGIN := 2.0      # obstacles/spawns stay this far inside the wall face
const SPAWN_INSET := 3.0      # player spawn sits this far in from the south wall
const WALL_HEIGHT := 5.0
const WALL_THICKNESS := 1.0
const FLOOR_MARGIN := 1.0     # floor overhangs the inner wall face by this much
const RAMP_THICKNESS := 0.4      # ramp slab thickness (navigable verticality)

const SPAWN_KEEP_CLEAR := 4.5     # no obstacle this close to the player spawn
const MIN_ENEMY_SPAWN_DIST := 14.0  # cap; the live value scales down in small rooms
const MIN_COVER_POINTS := 6
const MIN_NAV_POLYGONS := 40   # authored arena bakes ~166; degenerate guard
const MAX_BUILD_ATTEMPTS := 3

## Layout archetypes. "early" ones have longer sightlines and lower density,
## so rooms 2-3 draw only from those; everything unlocks from room 4.
const ARCHETYPES: Array[Dictionary] = [
	{"id": "open_field", "title": "OPEN FIELD",
		"tint": Color(1.0, 0.95, 0.82), "early": true},
	{"id": "scattered_cover", "title": "SCATTERED COVER",
		"tint": Color(1.0, 1.0, 1.0), "early": true},
	{"id": "pillar_hall", "title": "PILLAR HALL",
		"tint": Color(0.78, 0.87, 1.0), "early": true},
	{"id": "bunker", "title": "BUNKER",
		"tint": Color(1.0, 0.78, 0.58), "early": false},
	{"id": "maze_lanes", "title": "MAZE LANES",
		"tint": Color(0.8, 1.0, 0.83), "early": false},
	{"id": "arena_cross", "title": "ARENA CROSS",
		"tint": Color(0.88, 0.8, 1.0), "early": false},
	# Vertical layout (player-traversable high ground). Opt-in only: a layer's
	# archetype_pool must list "tiers" -- it is skipped in the endless random
	# rotation, so endless + the un-opted layers generate byte-for-byte as before.
	{"id": "tiers", "title": "TIERS",
		"tint": Color(0.82, 0.93, 1.0), "early": false, "vertical": true},
	# Milestone-only boss arena: never in the random rotation.
	{"id": "proving_grounds", "title": "PROVING GROUNDS",
		"tint": Color(1.0, 0.55, 0.45), "early": false, "milestone": true},
]

## Archetype id of the most recent build (e.g. "proving_grounds").
var last_archetype := ""

# Per-room footprint, set by _choose_dimensions before generation.
var _room_half := ROOM_HALF_DEFAULT
var _inner_limit := ROOM_HALF_DEFAULT - Vector2(EDGE_MARGIN, EDGE_MARGIN)
var _player_spawn_pos := Vector3(0.0, 0.0, ROOM_HALF_DEFAULT.y - SPAWN_INSET)
var _min_spawn_dist := MIN_ENEMY_SPAWN_DIST
# L-shape notch: (width, depth) cut from a north corner; ZERO = plain rectangle.
# (For a T this carries the per-corner notch size; both north corners use it.)
var _notch := Vector2.ZERO
var _notch_corner := CORNER_NE
var _notch_min := Vector2.ZERO  # world XZ rect of the FIRST notch (single-notch L compat)
var _notch_max := Vector2.ZERO
# Every bare-corner rect for the current footprint, so _in_notch covers them uniformly
# (rect = 0, L = 1, T = 2). _notch_min/_max above mirror the first entry for the L tests.
var _notches: Array[Dictionary] = []  # each {min: Vector2, max: Vector2}
var _shape := "rect"                   # "rect" | "L" | "T" -- selects the shell builder

var _shell: Node3D
var _generated: Node3D
var _footprints: Array[Dictionary] = []  # {pos: Vector3, r: float} per obstacle
var _spawn_points: Array[Vector3] = []
var _pickup_points: Array[Dictionary] = []  # {position: Vector3, exposed: bool}
var _high_reward_points: Array[Vector3] = []  # elevated reward spots on tier caps
var _cover_marker_count := 0
var _authored_retired := false
var _crate_material: StandardMaterial3D
var _struct_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _hackable_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _ghost_material: StandardMaterial3D    # translucent spectral cover for Ghost rooms
var _debris_material: StandardMaterial3D   # faint floating atmosphere shards
var _base_sun_color: Color
var _base_sun_energy: float
# Active per-room surface materials. Default to the legacy gray (the ENDLESS look);
# a CAMPAIGN layer profile swaps in its own palette via _resolve_palette so each
# layer reads as a distinct place. Cached per layer id so we build each set once.
var _active_floor_mat: StandardMaterial3D
var _active_wall_mat: StandardMaterial3D
var _active_struct_mat: StandardMaterial3D
var _palette_cache: Dictionary = {}
# Optional modular-kit skin (build-alongside): when a layer profile carries a "kit",
# the gray shell is hidden and the kit's meshes are drawn over it, recoloured by the
# layer palette. Visual only -- the collision boxes still drive the navmesh bake.
# Cached per kit id (each layer can use a different pack -- Heap space-station, Stack modular).
var _kits: Dictionary = {}
# The kit for the room currently building (null = no skin), + the tint its props take.
var _active_kit: RoomKit = null
var _active_obstacle_tint: Color = Color.WHITE
# Scene environment, captured so per-layer fog/ambient can be applied + restored.
var _environment: Environment
var _base_ambient_energy := 1.0
var _base_fog_enabled := false

@onready var _nav_region: NavigationRegion3D = get_node("../NavRegion")
@onready var _arena: Node3D = get_node("../NavRegion/Arena")
@onready var _authored_cover: Node3D = get_node("../CoverPoints")
@onready var _player_spawn_node: Marker3D = get_node("../PlayerSpawn")
@onready var _sun: DirectionalLight3D = get_node("../Sun")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_sun_color = _sun.light_color
	_base_sun_energy = _sun.light_energy

	_crate_material = _make_material(Color(0.52, 0.38, 0.24), 0.85)
	_struct_material = _make_material(Color(0.4, 0.42, 0.46), 0.8)
	# Match the authored shell materials so the procedural rooms read the same.
	_floor_material = _make_material(Color(0.33, 0.34, 0.37), 0.95)
	_wall_material = _make_material(Color(0.46, 0.43, 0.4), 0.9)
	# Start on the legacy palette; build_room swaps these per layer in CAMPAIGN.
	_active_floor_mat = _floor_material
	_active_wall_mat = _wall_material
	_active_struct_mat = _struct_material
	# Capture the authored environment so per-layer fog/ambient can be set + restored.
	var world_env := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		_environment = world_env.environment
		_base_ambient_energy = _environment.ambient_light_energy
		_base_fog_enabled = _environment.fog_enabled
	# Heap identity: spectral cover for Ghost rooms + faint drifting atmosphere shards.
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = Color(0.4, 0.95, 0.7, 0.32)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.emission_enabled = true
	_ghost_material.emission = Color(0.3, 1.0, 0.6)
	_ghost_material.emission_energy_multiplier = 0.8
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debris_material = StandardMaterial3D.new()
	_debris_material.albedo_color = Color(0.5, 0.72, 0.85, 0.5)
	_debris_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debris_material.emission_enabled = true
	_debris_material.emission = Color(0.4, 0.7, 0.95)
	_debris_material.emission_energy_multiplier = 0.5

	# Generated content must live under NavRegion so the rebake parses it. The
	# shell (floor + walls) and the interior live in separate containers: the
	# shell is rebuilt once per room, the interior is cleared per build attempt.
	_shell = Node3D.new()
	_shell.name = "GeneratedShell"
	_nav_region.add_child(_shell)
	_generated = Node3D.new()
	_generated.name = "GeneratedRoom"
	_nav_region.add_child(_generated)


func _make_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	return mat


## Rebuild the interior for the given room. Must be called with the tree
## UNPAUSED: the rebake and the navigation map sync need live frames.
## Picks the footprint first (moving PlayerSpawn), builds the sized shell, then
## the interior. Returns {"id": String, "title": String, "ok": bool}.
## `profile` is the active layer's LayerProfile (CAMPAIGN) used to re-skin the
## generation -- archetype pool, footprint bias and mood. {} = no re-skin
## (ENDLESS), so the legacy behaviour is byte-for-byte unchanged.
func build_room(room: int, profile: Dictionary = {}) -> Dictionary:
	_retire_authored_interior()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([RunManager.run_seed, room])
	var archetype := _pick_archetype(room, rng, profile)
	last_archetype = archetype.id
	# A Ghost (corrupted-echo) room gets spectral cover + heavier atmosphere. Pure:
	# room_type_for is deterministic from the room number; {} profile (endless) never ghosts.
	var ghost := not profile.is_empty() \
			and LayerCatalog.room_type_for(room) == LayerCatalog.RoomType.GHOST
	_choose_dimensions(archetype, rng, profile)
	# Pick this layer's surface palette (legacy gray for ENDLESS) before the shell +
	# interior are built, so floor/walls/structures all read in the layer's colours.
	var palette := _resolve_palette(profile)
	_active_floor_mat = palette.floor
	_active_wall_mat = palette.wall
	_active_struct_mat = palette.struct
	# Resolve the layer's kit once (null = no skin). Obstacle props take the struct colour.
	_active_kit = _resolve_kit(profile)
	_active_obstacle_tint = profile.get("struct_color", Color.WHITE)
	_build_shell()
	# Optional modular-kit re-skin: only when the layer profile opts in via "kit" (so
	# ENDLESS and any un-kitted layer stay on the gray shell, byte-for-byte unchanged).
	if _active_kit != null:
		_skin_shell(profile)
	var ok := false
	for attempt in MAX_BUILD_ATTEMPTS:
		_clear_generated()
		# Vertical "Tiers": raise the platforms FIRST so their ground footprints are
		# registered before the cover scatter -- the ground crates then avoid the
		# solid mesa bases (via _try_place's footprint check).
		if archetype.id == "tiers":
			_build_tiers(rng, ghost)
		var boxes := _descriptors_for(archetype.id, rng)
		_instantiate_boxes(boxes, ghost)
		_place_cover_markers(boxes)
		await _rebake()
		if _validate_and_collect(room, rng):
			ok = true
			break
	if not ok:
		# Safety net: an open-ish layout always keeps the authored spawn
		# marker positions reachable, so fall back to those.
		push_warning("RoomBuilder: layout validation failed %d times, using authored spawns"
				% MAX_BUILD_ATTEMPTS)
		_collect_fallback_spawns(room)
	_spawn_atmosphere(rng, float(profile.get("corruption", 0.0)), ghost)
	_seed_hackables(rng)
	_apply_mood(archetype, profile, ghost)
	_apply_environment(profile, ghost)
	return {"id": archetype.id, "title": archetype.title, "ok": ok}


func get_enemy_spawn_points() -> Array[Vector3]:
	return _spawn_points.duplicate()


func get_pickup_points() -> Array[Dictionary]:
	return _pickup_points.duplicate()


## Elevated reward spots, one per Tiers platform cap (empty for every other
## archetype). RunDirector drops a bonus pickup on each -- the player's payoff for
## taking the high ground (enemies, being grounded, can't contest them).
func get_high_reward_points() -> Array[Vector3]:
	return _high_reward_points.duplicate()


# ---------------------------------------------------------------- footprint

## Pick this room's footprint and derive every size-dependent value from it:
## inner placement bounds, player spawn (moved on the live marker), and the
## minimum enemy spawn distance (which shrinks so small rooms can still place
## enemies). Consumes the seeded rng, so the size is reproducible per room.
func _choose_dimensions(archetype: Dictionary, rng: RandomNumberGenerator,
		profile: Dictionary = {}) -> void:
	var fp: Dictionary
	if bool(archetype.get("milestone", false)):
		fp = {"half": MILESTONE_FOOTPRINT, "notch": Vector2.ZERO, "corner": CORNER_NE}
	else:
		fp = _pick_footprint(rng, profile)
	_room_half = fp.half
	_notch = fp.notch
	_notch_corner = int(fp.corner)
	_shape = String(fp.get("shape", "rect"))
	_inner_limit = _room_half - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	_compute_notch_rect()
	_player_spawn_pos = Vector3(0.0, 0.0, _room_half.y - SPAWN_INSET)
	_min_spawn_dist = clampf(minf(_inner_limit.x, _inner_limit.y) * 0.7, 8.0,
			MIN_ENEMY_SPAWN_DIST)
	# Move the live spawn marker; RunDirector teleports the player onto it after
	# build_room returns. The authored marker keeps its y (0.1).
	if is_instance_valid(_player_spawn_node):
		_player_spawn_node.position = Vector3(0.0, _player_spawn_node.position.y,
				_player_spawn_pos.z)


## Pure footprint pick: {half, notch, corner, shape}. Seeded -> reproducible; isolated
## so the headless test can assert variety + determinism without side effects.
## Rectangles carry a zero notch; L-shapes carry a notch; T-shapes carry a per-corner
## notch + shape "T". A layer profile may supply `footprint_pool` (indices into the
## combined list) to bias the shape; absent/empty = the full range (endless default).
func _pick_footprint(rng: RandomNumberGenerator, profile: Dictionary = {}) -> Dictionary:
	var pool: Array = profile.get("footprint_pool", [])
	if pool.is_empty():
		return _footprint_by_index(rng.randi_range(0, FOOTPRINTS.size()
				+ L_FOOTPRINTS.size() + T_FOOTPRINTS.size() + PLUS_FOOTPRINTS.size() - 1))
	return _footprint_by_index(int(pool[rng.randi_range(0, pool.size() - 1)]))


## Resolve a combined-list index to a footprint dict. The list is four segments in
## order: FOOTPRINTS (rectangles, zero notch) then L_FOOTPRINTS (one north-corner
## notch) then T_FOOTPRINTS (both north corners) then PLUS_FOOTPRINTS (all four corners).
## Every return carries a `notch`/`corner` (so the single-notch helpers + run_smoke's
## _fp_key never KeyError) and a `shape` tag that selects the shell builder.
func _footprint_by_index(idx: int) -> Dictionary:
	if idx < FOOTPRINTS.size():
		return {"half": FOOTPRINTS[idx], "notch": Vector2.ZERO, "corner": CORNER_NE, "shape": "rect"}
	var rest := idx - FOOTPRINTS.size()
	if rest < L_FOOTPRINTS.size():
		var l: Dictionary = L_FOOTPRINTS[rest]
		return {"half": l.half, "notch": l.notch, "corner": l.corner, "shape": "L"}
	rest -= L_FOOTPRINTS.size()
	if rest < T_FOOTPRINTS.size():
		var t: Dictionary = T_FOOTPRINTS[rest]
		return {"half": t.half, "notch": t.tnotch, "corner": CORNER_NE, "shape": "T"}
	var p: Dictionary = PLUS_FOOTPRINTS[rest - T_FOOTPRINTS.size()]
	return {"half": p.half, "notch": p.notch, "corner": CORNER_NE, "shape": "plus"}


## Build `_notches` (the world-space XZ rect of every bare corner) for the current
## footprint, used to reject obstacles/cover/spawns from the bare corners. A plain
## rectangle has none; an L has one; a T has both north corners. `_notch_min/_max`
## mirror the first entry so the single-notch L tests keep reading them. Kept named
## `_compute_notch_rect` so l_room_test / room_size_preview (which call it directly
## after setting the fields by hand, without _shape) still work via the _notch path.
func _compute_notch_rect() -> void:
	_notches.clear()
	var hx := _room_half.x
	var hz := _room_half.y
	if _shape == "plus":
		# All four corners cut by the per-corner notch. Symmetric across X and Z.
		var nx := _notch.x
		var nz := _notch.y
		_notches.append({"min": Vector2(hx - nx, -hz), "max": Vector2(hx, -hz + nz)})       # NE
		_notches.append({"min": Vector2(-hx, -hz), "max": Vector2(-hx + nx, -hz + nz)})      # NW
		_notches.append({"min": Vector2(hx - nx, hz - nz), "max": Vector2(hx, hz)})          # SE
		_notches.append({"min": Vector2(-hx, hz - nz), "max": Vector2(-hx + nx, hz)})        # SW
	elif _shape == "T":
		# Both north corners cut by the per-corner notch (width, depth). Symmetric.
		_notches.append({"min": Vector2(hx - _notch.x, -hz), "max": Vector2(hx, -hz + _notch.y)})
		_notches.append({"min": Vector2(-hx, -hz), "max": Vector2(-hx + _notch.x, -hz + _notch.y)})
	elif _notch != Vector2.ZERO:
		# Single north-corner L notch (NE or NW).
		if _notch_corner == CORNER_NE:
			_notches.append({"min": Vector2(hx - _notch.x, -hz), "max": Vector2(hx, -hz + _notch.y)})
		else:  # CORNER_NW
			_notches.append({"min": Vector2(-hx, -hz), "max": Vector2(-hx + _notch.x, -hz + _notch.y)})
	if _notches.is_empty():
		_notch_min = Vector2.ZERO
		_notch_max = Vector2.ZERO
	else:
		_notch_min = _notches[0].min
		_notch_max = _notches[0].max


## True when an XZ point (x in .x, z in .y) lies in (or within `margin` of) ANY of
## the footprint's bare corners — i.e. outside the playable L/T area.
func _in_notch(xz: Vector2, margin: float) -> bool:
	for n in _notches:
		var nmin: Vector2 = n.min
		var nmax: Vector2 = n.max
		if xz.x >= nmin.x - margin and xz.x <= nmax.x + margin \
				and xz.y >= nmin.y - margin and xz.y <= nmax.y + margin:
			return true
	return false


## Build the floor + four walls for the current footprint under the persistent
## shell container. StaticBody3D boxes (like the obstacles) so the navmesh bakes
## cleanly from collision shapes. Reproduces the authored geometry at half = 21.
func _build_shell() -> void:
	# Remove old shell boxes IMMEDIATELY (not deferred): the kit re-skin runs in this same
	# frame, so a lingering queue_freed "Floor"/"Wall*" would steal the new box's name (and
	# get mis-skinned). remove_child frees the name now; queue_free still deletes safely.
	for child in _shell.get_children():
		_shell.remove_child(child)
		child.queue_free()
	if _shape == "plus":
		_build_plus_shell()
	elif _shape == "T":
		_build_t_shell()
	elif _notch == Vector2.ZERO:
		_build_box_shell()
	else:
		_build_l_shell()


## Resolve the layer's modular kit by id (cached per id). "modular_space" picks the chunky
## 4 m kit (the Stack); anything else falls back to the space-station kit (the Heap). Returns
## null when the profile opts out (no "kit" key) -- ENDLESS + un-kitted layers stay gray.
func _resolve_kit(profile: Dictionary) -> RoomKit:
	if not profile.has("kit"):
		return null
	var id := String(profile["kit"])
	if not _kits.has(id):
		_kits[id] = RoomKit.modular_space() if id == "modular_space" else RoomKit.space_station()
	return _kits[id]


## Overlay the active kit's modular meshes on the shell, recoloured by the layer palette.
## VISUAL ONLY: the shell's StaticBody collision stays (the navmesh bakes from colliders,
## NavigationMesh.geometry_parsed_geometry_type = STATIC_COLLIDERS, so these meshes are
## ignored by the bake); we just hide the gray box meshes and draw the kit over them.
## Works for EVERY shape (rect / L / T / plus): each shell box carries its own size + pos,
## so we tile floor boxes and run wall modules per box -- the bare notch corners have no
## floor box, so they stay floorless. Kit nodes live under _shell (cleared by _build_shell).
func _skin_shell(profile: Dictionary) -> void:
	var kit := _resolve_kit(profile)
	if kit == null:
		return
	var floor_tint: Color = profile.get("floor_color", Color.WHITE)
	var wall_tint: Color = profile.get("wall_color", Color.WHITE)
	for box in _shell.get_children():
		if not (box is StaticBody3D):
			continue
		var pos: Vector3 = (box as Node3D).position
		var size := _box_size(box)
		for mi in (box as Node).get_children():
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).visible = false  # hide gray, keep collision
		var bn := String(box.name)
		if bn.begins_with("Floor"):
			kit.tile_floor(_shell, Vector2(size.x * 0.5, size.z * 0.5), pos.y + size.y * 0.5,
					floor_tint, "Kit" + bn, Vector2(pos.x, pos.z))
		elif bn.begins_with("Wall"):
			kit.build_wall_box(_shell, pos, size, WALL_HEIGHT, wall_tint, "Kit" + bn)


## Half-extent box size of a shell StaticBody, read from its CollisionShape (the source
## of truth -- the navmesh bakes from this), falling back to 1 m if somehow absent.
func _box_size(body: Node) -> Vector3:
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ONE


## Plain rectangular shell: one floor box + four walls sized to the footprint.
func _build_box_shell() -> void:
	var hx := _room_half.x
	var hz := _room_half.y
	var floor_w := hx * 2.0 + FLOOR_MARGIN * 2.0
	var floor_d := hz * 2.0 + FLOOR_MARGIN * 2.0
	# Floor box top sits at y = 0 (1 m thick, centred at y = -0.5).
	_add_shell_box("Floor", Vector3(floor_w, 1.0, floor_d), Vector3(0.0, -0.5, 0.0),
			_active_floor_mat)
	var wy := WALL_HEIGHT * 0.5
	var cx := hx + WALL_THICKNESS * 0.5  # wall centre so its inner face hits +/-hx
	var cz := hz + WALL_THICKNESS * 0.5
	var span_x := hx * 2.0 + WALL_THICKNESS * 2.0
	var span_z := hz * 2.0 + WALL_THICKNESS * 2.0
	_add_shell_box("WallN", Vector3(span_x, WALL_HEIGHT, WALL_THICKNESS),
			Vector3(0.0, wy, -cz), _active_wall_mat)
	_add_shell_box("WallS", Vector3(span_x, WALL_HEIGHT, WALL_THICKNESS),
			Vector3(0.0, wy, cz), _active_wall_mat)
	_add_shell_box("WallE", Vector3(WALL_THICKNESS, WALL_HEIGHT, span_z),
			Vector3(cx, wy, 0.0), _active_wall_mat)
	_add_shell_box("WallW", Vector3(WALL_THICKNESS, WALL_HEIGHT, span_z),
			Vector3(-cx, wy, 0.0), _active_wall_mat)


## L-shaped shell: the floor is two boxes tiling the L (the notch corner is left
## bare, so the navmesh baker produces no floor/navmesh there), the four outer
## walls are shortened on the notch side, and two extra walls close the concave
## corner. Built NE-canonical, then mirrored across X for a NW notch.
func _build_l_shell() -> void:
	var hx := _room_half.x
	var hz := _room_half.y
	var nw := _notch.x
	var nd := _notch.y
	var m := FLOOR_MARGIN
	var t := WALL_THICKNESS
	var h := WALL_HEIGHT
	var wy := h * 0.5
	var parts: Array[Dictionary] = [
		# Two floor boxes tiling the L; the NE corner (x>hx-nw, z<-hz+nd) stays bare.
		{"name": "Floor", "size": Vector3(2.0 * hx - nw + m, 1.0, 2.0 * hz + 2.0 * m),
			"pos": Vector3(-(m + nw) * 0.5, -0.5, 0.0)},
		{"name": "Floor2", "size": Vector3(nw + m, 1.0, 2.0 * hz + m - nd),
			"pos": Vector3(hx + (m - nw) * 0.5, -0.5, (nd + m) * 0.5)},
		# Outer walls: south + west full, north + east shortened by the notch.
		{"name": "WallS", "size": Vector3(2.0 * hx + 2.0 * t, h, t),
			"pos": Vector3(0.0, wy, hz + t * 0.5)},
		{"name": "WallW", "size": Vector3(t, h, 2.0 * hz + 2.0 * t),
			"pos": Vector3(-hx - t * 0.5, wy, 0.0)},
		{"name": "WallN", "size": Vector3(2.0 * hx - nw + 2.0 * t, h, t),
			"pos": Vector3(-nw * 0.5, wy, -hz - t * 0.5)},
		{"name": "WallE", "size": Vector3(t, h, 2.0 * hz - nd + 2.0 * t),
			"pos": Vector3(hx + t * 0.5, wy, nd * 0.5)},
		# The two concave walls that close the L around the bare corner.
		{"name": "WallNotchA", "size": Vector3(nw + 2.0 * t, h, t),
			"pos": Vector3(hx - nw * 0.5, wy, -hz + nd - t * 0.5)},
		{"name": "WallNotchB", "size": Vector3(t, h, nd + 2.0 * t),
			"pos": Vector3(hx - nw + t * 0.5, wy, -hz + nd * 0.5)},
	]
	var mirror := -1.0 if _notch_corner == CORNER_NW else 1.0
	for part in parts:
		var pos: Vector3 = part.pos
		pos.x *= mirror
		var mat: StandardMaterial3D = _active_floor_mat \
				if String(part.name).begins_with("Floor") else _active_wall_mat
		_add_shell_box(part.name, part.size, pos, mat)


## T-shaped shell: BOTH north corners notched, leaving a wide south crossbar (the
## player-spawn edge) and a narrow north stem (the exit gate). The floor is two boxes
## -- a full-width south body + a centred north stem -- so the two bare north corners
## get no floor/navmesh there; four outer walls + four concave walls enclose it.
## Symmetric across X (no mirror). `_notch` carries the per-corner (width, depth).
func _build_t_shell() -> void:
	var hx := _room_half.x
	var hz := _room_half.y
	var nw := _notch.x
	var nd := _notch.y
	var m := FLOOR_MARGIN
	var t := WALL_THICKNESS
	var h := WALL_HEIGHT
	var wy := h * 0.5
	var stem_hx := hx - nw  # half-width of the north stem
	var parts: Array[Dictionary] = [
		# Floor: full-width south body (flush at the concave north edge z=-hz+nd) +
		# a centred north stem (flush at its concave E/W faces x=+/-stem_hx). They abut
		# coplanar at z=-hz+nd so the navmesh bakes continuous from crossbar to stem.
		{"name": "Floor", "size": Vector3(2.0 * hx + 2.0 * m, 1.0, 2.0 * hz + m - nd),
			"pos": Vector3(0.0, -0.5, (nd + m) * 0.5)},
		{"name": "Floor2", "size": Vector3(2.0 * stem_hx, 1.0, nd + m),
			"pos": Vector3(0.0, -0.5, -hz + (nd - m) * 0.5)},
		# Outer walls: south full; east + west span the body only; north spans the stem.
		{"name": "WallS", "size": Vector3(2.0 * hx + 2.0 * t, h, t),
			"pos": Vector3(0.0, wy, hz + t * 0.5)},
		{"name": "WallE", "size": Vector3(t, h, 2.0 * hz - nd + 2.0 * t),
			"pos": Vector3(hx + t * 0.5, wy, nd * 0.5)},
		{"name": "WallW", "size": Vector3(t, h, 2.0 * hz - nd + 2.0 * t),
			"pos": Vector3(-hx - t * 0.5, wy, nd * 0.5)},
		{"name": "WallN", "size": Vector3(2.0 * stem_hx + 2.0 * t, h, t),
			"pos": Vector3(0.0, wy, -hz - t * 0.5)},
		# Concave walls closing the two bare north corners: a crossbar-top segment +
		# a stem-side segment on each side.
		{"name": "WallNotchEH", "size": Vector3(nw + 2.0 * t, h, t),
			"pos": Vector3(hx - nw * 0.5, wy, -hz + nd - t * 0.5)},
		{"name": "WallNotchEV", "size": Vector3(t, h, nd + 2.0 * t),
			"pos": Vector3(stem_hx + t * 0.5, wy, -hz + nd * 0.5)},
		{"name": "WallNotchWH", "size": Vector3(nw + 2.0 * t, h, t),
			"pos": Vector3(-(hx - nw * 0.5), wy, -hz + nd - t * 0.5)},
		{"name": "WallNotchWV", "size": Vector3(t, h, nd + 2.0 * t),
			"pos": Vector3(-(stem_hx + t * 0.5), wy, -hz + nd * 0.5)},
	]
	for part in parts:
		var mat: StandardMaterial3D = _active_floor_mat \
				if String(part.name).begins_with("Floor") else _active_wall_mat
		_add_shell_box(part.name, part.size, part.pos, mat)


## Plus/cross shell: ALL FOUR corners notched, leaving a central crossing + four arms
## (south arm = player spawn, north arm = exit gate, east/west arms = flanking
## sightlines). The floor is three boxes -- a full-width central band + a north arm +
## a south arm -- so the four corners get no floor/navmesh; four arm-end walls + eight
## concave walls (two per corner) enclose it. Symmetric across X and Z. `_notch` carries
## the per-corner (width, depth).
func _build_plus_shell() -> void:
	var hx := _room_half.x
	var hz := _room_half.y
	var nw := _notch.x
	var nd := _notch.y
	var m := FLOOR_MARGIN
	var t := WALL_THICKNESS
	var h := WALL_HEIGHT
	var wy := h * 0.5
	var arm_hx := hx - nw    # half-width of the N/S arms
	var band_hz := hz - nd   # half-depth of the central E/W band
	# Floor: central full-width band + north arm + south arm (corners left floorless).
	# The arms abut the band coplanar at z=+/-band_hz so the navmesh bakes continuous.
	_add_shell_box("Floor", Vector3(2.0 * hx + 2.0 * m, 1.0, 2.0 * band_hz),
			Vector3(0.0, -0.5, 0.0), _active_floor_mat)
	_add_shell_box("Floor2", Vector3(2.0 * arm_hx, 1.0, nd + m),
			Vector3(0.0, -0.5, -hz + (nd - m) * 0.5), _active_floor_mat)
	_add_shell_box("Floor3", Vector3(2.0 * arm_hx, 1.0, nd + m),
			Vector3(0.0, -0.5, hz - (nd - m) * 0.5), _active_floor_mat)
	# Outer arm-end walls: N/S span the arm width, E/W span the band depth.
	_add_shell_box("WallN", Vector3(2.0 * arm_hx + 2.0 * t, h, t),
			Vector3(0.0, wy, -hz - t * 0.5), _active_wall_mat)
	_add_shell_box("WallS", Vector3(2.0 * arm_hx + 2.0 * t, h, t),
			Vector3(0.0, wy, hz + t * 0.5), _active_wall_mat)
	_add_shell_box("WallE", Vector3(t, h, 2.0 * band_hz + 2.0 * t),
			Vector3(hx + t * 0.5, wy, 0.0), _active_wall_mat)
	_add_shell_box("WallW", Vector3(t, h, 2.0 * band_hz + 2.0 * t),
			Vector3(-hx - t * 0.5, wy, 0.0), _active_wall_mat)
	# Eight concave walls closing the four bare corners (a band-edge + an arm-edge each).
	var i := 0
	for c in [Vector2(1.0, -1.0), Vector2(-1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var sx: float = c.x
		var sz: float = c.y
		_add_shell_box("WallNotchH%d" % i, Vector3(nw + 2.0 * t, h, t),
				Vector3(sx * (hx - nw * 0.5), wy, sz * (band_hz + t * 0.5)), _active_wall_mat)
		_add_shell_box("WallNotchV%d" % i, Vector3(t, h, nd + 2.0 * t),
				Vector3(sx * (arm_hx + t * 0.5), wy, sz * (hz - nd * 0.5)), _active_wall_mat)
		i += 1


func _add_shell_box(box_name: String, size: Vector3, pos: Vector3,
		mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = 1  # world
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	_shell.add_child(body)
	body.position = pos


# ---------------------------------------------------------------- lifecycle

## Remove the authored interior AND shell (the procedural shell replaces it),
## and take the authored cover markers out of the cover_point group. Runs once,
## on the first procedural build, so room 1 plays exactly as authored.
func _retire_authored_interior() -> void:
	if _authored_retired:
		return
	_authored_retired = true
	for child in _arena.get_children():
		child.queue_free()
	for marker in _authored_cover.get_children():
		marker.remove_from_group("cover_point")


func _clear_generated() -> void:
	for child in _generated.get_children():
		child.remove_from_group("cover_point")  # no-op for geometry
		child.queue_free()
	_footprints.clear()
	_spawn_points.clear()
	_pickup_points.clear()
	_high_reward_points.clear()
	_cover_marker_count = 0


func _rebake() -> void:
	# Let queue_freed geometry actually leave the tree before parsing.
	await get_tree().process_frame
	_nav_region.bake_navigation_mesh()
	await _nav_region.bake_finished
	# Let the region commit its freshly baked navmesh to its server region, THEN
	# force the navigation map to apply it now, so the validation queries that
	# follow read THIS room and not the previous (stale) navmesh.
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(_nav_region.get_world_3d().navigation_map)
	await get_tree().physics_frame


## Tint + dim the sun for this room. A layer profile pulls the whole layer toward
## one mood (`mood_tint` at `mood_strength`, dimmed by `sun_energy_factor`); with
## no profile this is the legacy per-archetype tint at half strength, full energy.
## Ghost (corrupted-echo) rooms pull further toward the layer's `ghost_tint` and dim more.
func _apply_mood(archetype: Dictionary, profile: Dictionary = {}, ghost := false) -> void:
	var tint: Color = profile.get("mood_tint", archetype.tint)
	var strength: float = profile.get("mood_strength", 0.5)
	var energy_factor: float = profile.get("sun_energy_factor", 1.0)
	var color: Color = _base_sun_color.lerp(tint, strength)
	if ghost:
		color = color.lerp(profile.get("ghost_tint", tint), 0.6)
		energy_factor *= 0.8
	_sun.light_color = color
	_sun.light_energy = _base_sun_energy * energy_factor


## This layer's surface materials (floor / wall / struct). Empty profile = the
## legacy gray authored materials (ENDLESS, byte-for-byte). A layer profile supplies
## its own `floor_color`/`wall_color`/`struct_color`; missing keys fall back to the
## legacy colour. Cached per layer id so each palette is built once, not per room.
func _resolve_palette(profile: Dictionary) -> Dictionary:
	var key: String = profile.get("id", "__endless__")
	if _palette_cache.has(key):
		return _palette_cache[key]
	var palette: Dictionary
	if profile.is_empty():
		palette = {"floor": _floor_material, "wall": _wall_material, "struct": _struct_material}
	else:
		palette = {
			"floor": _make_material(profile.get("floor_color", _floor_material.albedo_color), 0.95),
			"wall": _make_material(profile.get("wall_color", _wall_material.albedo_color), 0.9),
			"struct": _make_material(profile.get("struct_color", _struct_material.albedo_color), 0.8),
		}
	_palette_cache[key] = palette
	return palette


## Per-layer depth fog + ambient on the shared scene environment, so the Heap's
## organic murk and the Stack's crisp order read as different places. ENDLESS (empty
## profile) restores the authored environment, so its look is unchanged. Ghost rooms
## pull the fog toward the layer's ghost tint. Purely visual -- no gameplay/nav effect.
func _apply_environment(profile: Dictionary, ghost: bool) -> void:
	if _environment == null:
		return
	if profile.is_empty():
		_environment.fog_enabled = _base_fog_enabled
		_environment.ambient_light_energy = _base_ambient_energy
		return
	var fog_density: float = profile.get("fog_density", 0.0)
	if fog_density > 0.0:
		var fog_color: Color = profile.get("fog_color", Color(0.4, 0.45, 0.5))
		if ghost:
			fog_color = fog_color.lerp(profile.get("ghost_tint", fog_color), 0.5)
		_environment.fog_enabled = true
		_environment.fog_density = fog_density
		_environment.fog_light_color = fog_color
	else:
		_environment.fog_enabled = _base_fog_enabled
	_environment.ambient_light_energy = profile.get("ambient_energy", _base_ambient_energy)


## Decorative floating shards above the floor: the Heap's drifting-data atmosphere
## and vertical read. Count scales with the layer's `corruption` (0 = none, so
## endless rooms are untouched); Ghost rooms get a heavier swarm. Pure visuals --
## no collision, so the navmesh and gameplay are unaffected -- and children of
## GeneratedRoom, so they are swept on the next build. Grouped for the test.
func _spawn_atmosphere(rng: RandomNumberGenerator, corruption: float, ghost: bool) -> void:
	if corruption <= 0.0 and not ghost:
		return
	var count := int(round(lerpf(0.0, 14.0, clampf(corruption, 0.0, 1.0))))
	if ghost:
		count += 8
	for i in count:
		var xz := _random_xz(rng)
		if _in_notch(xz, 0.5):
			continue
		var shard := MeshInstance3D.new()
		shard.add_to_group("room_debris")
		if ghost:
			shard.add_to_group("ghost_geometry")
		var mesh := BoxMesh.new()
		var s := rng.randf_range(0.2, 0.55)
		mesh.size = Vector3(s, s * rng.randf_range(0.6, 2.2), s)
		shard.mesh = mesh
		shard.material_override = _ghost_material if ghost else _debris_material
		_generated.add_child(shard)
		shard.position = Vector3(xz.x, rng.randf_range(1.5, 8.0), xz.y)
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


## Seed a few hackable props (frozen RigidBody cubes) so the environment-hacking system
## has objects to inject. They float overhead (above the navmesh, and added AFTER the bake
## like the atmosphere) so they never block spawns or pathing; children of GeneratedRoom so
## they're swept on the next build, and grouped "hackable" by their Hackable component.
func _seed_hackables(rng: RandomNumberGenerator) -> void:
	var target := rng.randi_range(2, 3)
	var placed := 0
	var tries := 0
	while placed < target and tries < 30:
		tries += 1
		var xz := _random_xz(rng)
		if _in_notch(xz, 0.6):
			continue
		_spawn_hackable_prop(Vector3(xz.x, rng.randf_range(2.3, 3.0), xz.y))
		placed += 1


func _spawn_hackable_prop(pos: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1  # "world" -- the player can stand on / bump it, walls block aim
	rb.collision_mask = 1
	rb.freeze = true        # reads as a floating prop until hacked
	rb.mass = 8.0
	var s := 0.8
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(s, s, s)
	col.shape = shape
	rb.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s, s)
	mesh.mesh = bm
	mesh.material_override = _hackable_prop_material()
	rb.add_child(mesh)
	var h := Hackable.new()
	h.name = "Hackable"
	rb.add_child(h)
	rb.position = pos  # BEFORE add_child: a frozen RigidBody ignores a later global set
	_generated.add_child(rb)


func _hackable_prop_material() -> StandardMaterial3D:
	if _hackable_material == null:
		_hackable_material = StandardMaterial3D.new()
		_hackable_material.albedo_color = Color(0.3, 0.8, 1.0)
		_hackable_material.emission_enabled = true
		_hackable_material.emission = Color(0.2, 0.7, 1.0)
		_hackable_material.emission_energy_multiplier = 1.1
	return _hackable_material


## Pick a layout archetype. A layer profile's `archetype_pool` (a list of ids)
## restricts the choice to that layer's set; with no profile it's the legacy
## room-gated pool (early archetypes only for rooms <= 3). Milestone rooms always
## force the milestone-only arena regardless of mode.
func _pick_archetype(room: int, rng: RandomNumberGenerator, profile: Dictionary = {}) -> Dictionary:
	if RunManager.is_milestone_room(room):
		for archetype in ARCHETYPES:
			if bool(archetype.get("milestone", false)):
				return archetype
	var allowed: Array = profile.get("archetype_pool", [])
	var pool: Array[Dictionary] = []
	for archetype in ARCHETYPES:
		if bool(archetype.get("milestone", false)):
			continue
		# Vertical archetypes are opt-in: chosen only when a profile's pool lists
		# them explicitly, never in the endless room-gated random rotation.
		if bool(archetype.get("vertical", false)) and allowed.is_empty():
			continue
		if not allowed.is_empty():
			if archetype.id in allowed:
				pool.append(archetype)
			continue
		if room <= 3 and not bool(archetype.early):
			continue
		pool.append(archetype)
	if pool.is_empty():  # safety: a profile pool that matched nothing
		pool.append(ARCHETYPES[0])
	return pool[rng.randi_range(0, pool.size() - 1)]


# ---------------------------------------------------------------- generation

## Pure layout generation: rng + constants + the current bounds in, obstacle
## descriptors out. No scene access, so the same seed + bounds always reproduces
## the same layout. Structured archetypes scale their key extents off
## `_inner_limit`, so they fill rooms of any size (and reproduce the authored
## look at the default half = 21 / inner_limit = 19).
func _descriptors_for(archetype_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	match archetype_id:
		"open_field":
			return _gen_open_field(rng)
		"scattered_cover":
			return _gen_scattered_cover(rng)
		"pillar_hall":
			return _gen_pillar_hall(rng)
		"bunker":
			return _gen_bunker(rng)
		"maze_lanes":
			return _gen_maze_lanes(rng)
		"arena_cross":
			return _gen_arena_cross(rng)
		"tiers":
			return _gen_tiers(rng)
		"proving_grounds":
			return _gen_proving_grounds(rng)
	return _gen_scattered_cover(rng)


## Evenly spaced coordinates in [-extent, extent]; one point at 0 when count<=1.
func _grid(count: int, extent: float) -> Array[float]:
	var out: Array[float] = []
	if count <= 1:
		out.append(0.0)
		return out
	for i in count:
		out.append(lerpf(-extent, extent, float(i) / float(count - 1)))
	return out


func _gen_open_field(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var want := 5 + rng.randi_range(0, 2)
	var tries := 0
	while boxes.size() < want and tries < 120:
		tries += 1
		var size := Vector3(rng.randf_range(2.0, 3.0), 1.4, rng.randf_range(1.0, 1.3))
		_try_place(boxes, "crate", size, _random_xz(rng), rng.randf_range(0.0, TAU), 6.0)
	return boxes


func _gen_scattered_cover(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var want := 9 + rng.randi_range(0, 3)
	var tries := 0
	while boxes.size() < want and tries < 200:
		tries += 1
		var size := Vector3(rng.randf_range(1.8, 3.0), 1.4, rng.randf_range(1.0, 1.4))
		_try_place(boxes, "crate", size, _random_xz(rng), rng.randf_range(0.0, TAU), 3.0)
	return boxes


func _gen_pillar_hall(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var cols := _grid(5, _inner_limit.x * 0.63)  # ~ +/-12 at the default size
	var rows := _grid(5, _inner_limit.y * 0.63)
	for grid_x in cols:
		for grid_z in rows:
			if rng.randf() > 0.55:
				continue
			var jitter := Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			_try_place(boxes, "pillar", Vector3(1.6, 4.0, 1.6),
					Vector2(grid_x, grid_z) + jitter, 0.0, 1.5)
	var tries := 0
	var crates_wanted := boxes.size() + 2
	while boxes.size() < crates_wanted and tries < 60:
		tries += 1
		_try_place(boxes, "crate", Vector3(2.4, 1.4, 1.1), _random_xz(rng),
				rng.randf_range(0.0, TAU), 3.0)
	return boxes


func _gen_bunker(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	# Central strongpoint: broken square of low walls with corner/middle gaps.
	# Fixed size (a strongpoint reads as intentional at any room size); the
	# surrounding crates scatter to fill whatever room it sits in.
	for side in 4:
		var along := 2.1
		for offset in [-along, along]:
			var pos := Vector2.ZERO
			var yaw := 0.0
			match side:
				0: pos = Vector2(offset, -5.0)            # north wall, runs E-W
				1: pos = Vector2(offset, 5.0)             # south wall
				2:
					pos = Vector2(-5.0, offset)
					yaw = PI / 2.0                        # west wall, runs N-S
				3:
					pos = Vector2(5.0, offset)
					yaw = PI / 2.0                        # east wall
			_try_place(boxes, "wall", Vector3(2.8, 2.2, 0.8), pos, yaw, 0.2)
	# Crates scattered outside the strongpoint ring.
	var tries := 0
	var want := boxes.size() + 4 + rng.randi_range(0, 2)
	while boxes.size() < want and tries < 120:
		tries += 1
		var xz := _random_xz(rng)
		if xz.length() < 9.0:
			continue
		_try_place(boxes, "crate", Vector3(2.4, 1.4, 1.1), xz,
				rng.randf_range(0.0, TAU), 3.5)
	return boxes


func _gen_maze_lanes(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	# Walls run along X, lanes offset in Z. In a corridor (one axis much longer) run
	# the lanes along the LONG axis, so the long walls never span the narrow axis and
	# get rejected; near-square rooms keep the seeded coin-flip for variety.
	var east_west: bool
	if absf(_inner_limit.x - _inner_limit.y) > 6.0:
		east_west = _inner_limit.x > _inner_limit.y
	else:
		east_west = rng.randf() > 0.5
	var run_il: float = _inner_limit.x if east_west else _inner_limit.y
	var lane_il: float = _inner_limit.y if east_west else _inner_limit.x
	var lanes := _grid(5, lane_il * 0.58)  # ~ +/-11 at the default size
	for lane in lanes:
		var length := rng.randf_range(run_il * 0.42, run_il * 0.63)  # ~ 8..12
		var slide := rng.randf_range(-run_il * 0.21, run_il * 0.21)  # ~ +/-4
		var pos := Vector2(slide, lane) if east_west else Vector2(lane, slide)
		var yaw := 0.0 if east_west else PI / 2.0
		_try_place(boxes, "wall", Vector3(length, 2.2, 0.8), pos, yaw, 1.0)
	var tries := 0
	var want := boxes.size() + 3
	while boxes.size() < want and tries < 60:
		tries += 1
		_try_place(boxes, "crate", Vector3(2.2, 1.4, 1.1), _random_xz(rng),
				rng.randf_range(0.0, TAU), 3.0)
	return boxes


func _gen_arena_cross(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	_try_place(boxes, "pillar", Vector3(2.0, 4.0, 2.0), Vector2.ZERO, 0.0, 0.5)
	# Corners scale per-axis so the X opens up in rectangular rooms; the diagonal
	# wall length + central exclusion use the short axis so nothing overflows.
	var off_x := _inner_limit.x * 0.34  # ~ +/-6.5 at the default size
	var off_z := _inner_limit.y * 0.34
	var short := minf(_inner_limit.x, _inner_limit.y)
	var wall_len := short * 0.37  # ~ 7 at the default size
	for corner in [Vector2(off_x, off_z), Vector2(-off_x, off_z),
			Vector2(off_x, -off_z), Vector2(-off_x, -off_z)]:
		# Diagonal walls forming an X of channels around the center.
		var yaw := -PI / 4.0 if corner.x * corner.y > 0.0 else PI / 4.0
		_try_place(boxes, "wall", Vector3(wall_len, 2.2, 0.8), corner, yaw, 0.5)
	var tries := 0
	var exclude := short * 0.58  # keep crates outside the central X
	var want := boxes.size() + 2 + rng.randi_range(0, 2)
	while boxes.size() < want and tries < 60:
		tries += 1
		var xz := _random_xz(rng)
		if xz.length() < exclude:
			continue
		_try_place(boxes, "crate", Vector3(2.4, 1.4, 1.1), xz,
				rng.randf_range(0.0, TAU), 3.0)
	return boxes


## Ground cover for the vertical "Tiers" layout: a modest crate scatter so the
## floor still reads as a combat space (and clears MIN_COVER_POINTS) beneath the
## raised platforms. The platforms are built by _build_tiers BEFORE this runs, so
## _try_place's footprint check keeps these crates off the mesa bases + ramp feet.
func _gen_tiers(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var want := 6 + rng.randi_range(0, 2)
	var tries := 0
	while boxes.size() < want and tries < 160:
		tries += 1
		var size := Vector3(rng.randf_range(1.8, 2.8), 1.4, rng.randf_range(1.0, 1.4))
		_try_place(boxes, "crate", size, _random_xz(rng), rng.randf_range(0.0, TAU), 3.0)
	return boxes


## Milestone boss arena: tall central monument the elite orbits, a ring of
## player cover at mid radius, and an otherwise open killing floor. The ring
## leaves a natural gap near the player spawn (keep-clear rejection).
func _gen_proving_grounds(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for offset in [Vector2(-1.6, -1.6), Vector2(1.6, -1.6),
			Vector2(-1.6, 1.6), Vector2(1.6, 1.6)]:
		_try_place(boxes, "pillar", Vector3(1.4, 5.0, 1.4), offset, 0.0, 0.0)
	var count := 7 + rng.randi_range(0, 2)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.15, 0.15)
		var radius := rng.randf_range(_inner_limit.x * 0.55, _inner_limit.x * 0.68)
		var xz := Vector2(cos(angle), sin(angle)) * radius
		_try_place(boxes, "crate", Vector3(2.4, 1.4, 1.1), xz,
				angle + PI / 2.0 + rng.randf_range(-0.2, 0.2), 0.5)
	return boxes


func _random_xz(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(-_inner_limit.x, _inner_limit.x),
			rng.randf_range(-_inner_limit.y, _inner_limit.y))


## Validate a candidate against bounds, the player keep-clear zone and other
## obstacles; append the descriptor on success. Footprints are coarse circles
## (half diagonal), conservative for long walls.
func _try_place(boxes: Array[Dictionary], kind: String, size: Vector3,
		xz: Vector2, yaw: float, min_gap: float) -> bool:
	var r := Vector2(size.x, size.z).length() * 0.5
	if absf(xz.x) > _inner_limit.x - r or absf(xz.y) > _inner_limit.y - r:
		return false
	if _in_notch(xz, r + 0.5):  # keep obstacles out of the L's bare corner
		return false
	var pos := Vector3(xz.x, size.y * 0.5, xz.y)
	# Keep obstacles off already-placed structures (e.g. the Tiers platforms, which
	# are raised before the ground scatter). _footprints is empty during the normal
	# descriptor generation, so this is a no-op for the non-vertical archetypes.
	for placed in _footprints:
		if Vector2(pos.x - placed.pos.x, pos.z - placed.pos.z).length() \
				< r + float(placed.r) + 0.5:
			return false
	if Vector2(pos.x - _player_spawn_pos.x, pos.z - _player_spawn_pos.z).length() \
			< SPAWN_KEEP_CLEAR + r:
		return false
	for other in boxes:
		var other_r: float = other.r
		if Vector2(pos.x - other.pos.x, pos.z - other.pos.z).length() \
				< r + other_r + min_gap:
			return false
	boxes.append({"kind": kind, "size": size, "pos": pos, "yaw": yaw, "r": r})
	return true


# ---------------------------------------------------------------- instancing

func _instantiate_boxes(boxes: Array[Dictionary], ghost := false) -> void:
	for desc in boxes:
		var body := StaticBody3D.new()
		body.collision_layer = 1  # world
		body.collision_mask = 0
		if ghost:
			body.add_to_group("ghost_geometry")  # spectral, half-materialized echo
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = desc.size
		shape.shape = box_shape
		body.add_child(shape)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = desc.size
		mesh_instance.mesh = mesh
		if ghost:
			mesh_instance.material_override = _ghost_material
		else:
			mesh_instance.material_override = \
					_crate_material if desc.kind == "crate" else _active_struct_mat
		body.add_child(mesh_instance)
		# Kit skin: hide the gray box mesh (keep its collision + RVO) and drop a tinted kit
		# prop fitted to the box. Visual-only, like the shell skin. Ghost rooms keep their
		# spectral material (they're corrupted echoes, not furnished spaces).
		if _active_kit != null and not ghost:
			mesh_instance.visible = false
			_active_kit.skin_obstacle(body, desc.size, desc.kind, _active_obstacle_tint)
		if desc.kind == "crate":
			# Mirror the authored crates: low cover gets an RVO obstacle.
			var rvo := NavigationObstacle3D.new()
			rvo.radius = maxf(desc.size.x, desc.size.z) * 0.7
			rvo.height = 1.5
			body.add_child(rvo)
		_generated.add_child(body)
		body.position = desc.pos
		body.rotation.y = desc.yaw
		_footprints.append({"pos": desc.pos, "r": desc.r})


# ---------------------------------------------------------------- verticality
# Navigable second level: raised platforms reached by ramps. The arena navmesh
# bakes from static colliders (agent_max_slope 50, agent_max_climb 0.5), so a ramp
# whose slope is <= 50 bakes walkable and connects the ground to the platform cap --
# enemies path up it with no AI change. V1 adds + proves the builders; V2 wires them
# into a layout archetype. Pieces are StaticBody3D under GeneratedRoom, so they bake
# from collision and are swept on the next build, exactly like the obstacles.

## A generic structural box with a full rotation (the obstacle path only yaws).
func _add_structure_box(size: Vector3, pos: Vector3, rot: Vector3,
		mat: StandardMaterial3D, group: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # world
	body.collision_mask = 0
	body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	_generated.add_child(body)
	body.position = pos
	body.rotation = rot


## A raised platform whose walkable top sits at `top_y`. Built as a SOLID mesa
## (ground up to top_y), not a thin floating slab: Recast reliably bakes a walkable
## top on solid boxes (it's how the 5 m walls get walkable tops) but is flaky on
## thin platforms near agent_max_climb. Returns the top centre (a reach reference).
func _build_platform(center_xz: Vector2, half: Vector2, top_y: float) -> Vector3:
	var size := Vector3(half.x * 2.0, top_y, half.y * 2.0)
	var pos := Vector3(center_xz.x, top_y * 0.5, center_xz.y)  # spans floor (0) to top_y
	_add_structure_box(size, pos, Vector3.ZERO, _active_struct_mat, "room_platform")
	return Vector3(center_xz.x, top_y, center_xz.y)


## A straight ramp climbing to a platform's top. `dir_z` = +1 puts it on the
## platform's +Z face sloping down toward +Z; -1 mirrors it onto the -Z face. The
## slope is atan(top_y/run) -- keep `run` >= top_y so it stays under the navmesh's
## max walkable slope, so the ramp bakes connected to both the ground and the cap.
func _build_ramp(platform_top: Vector3, plat_half_z: float, top_y: float,
		run: float, width: float, dir_z: float = 1.0) -> void:
	var angle := atan2(top_y, run)
	var slope_len := sqrt(run * run + top_y * top_y) + 0.8  # 0.8 m overlap at both ends
	var z_edge := platform_top.z + dir_z * plat_half_z
	var size := Vector3(width, RAMP_THICKNESS, slope_len)
	var pos := Vector3(platform_top.x, top_y * 0.5, z_edge + dir_z * run * 0.5)
	# Rotate about X so the platform-side end is high and the ground-side end low.
	_add_structure_box(size, pos, Vector3(angle * dir_z, 0.0, 0.0), _active_struct_mat, "room_ramp")


## Vertical "Tiers" layout: 2-3 raised platforms (solid mesas) reached by ramps,
## each topped with a piece of high cover. Placed toward the room's perimeter with
## ramps pointing inward, so the ground stays open + enemy-navigable; this is
## player-only high ground (enemies stay grounded -- the navmesh routes around the
## mesa bases; see the verticality notes above). Each platform's ground + ramp-foot
## footprint is registered in _footprints so enemy spawns + pickups avoid the bases.
## Scene-touching, run inside the build loop (after _clear_generated, before the
## ground descriptors), so the pieces are swept + revalidated like the obstacles.
func _build_tiers(rng: RandomNumberGenerator, ghost := false) -> void:
	var want := 2 + rng.randi_range(0, 1)
	var placed := 0
	var tries := 0
	while placed < want and tries < 80:
		tries += 1
		var angle := rng.randf_range(0.0, TAU)
		var center := Vector2(cos(angle) * _inner_limit.x * rng.randf_range(0.5, 0.74),
				sin(angle) * _inner_limit.y * rng.randf_range(0.5, 0.74))
		var half := Vector2(rng.randf_range(2.6, 3.6), rng.randf_range(2.6, 3.6))
		var top_y := rng.randf_range(2.2, 3.0)
		var dir_z := -1.0 if center.y > 0.0 else 1.0  # ramp runs toward the room centre
		var run := top_y * rng.randf_range(1.7, 2.1)  # slope ~ 25-30 deg, comfortably climbable
		if not _platform_fits(center, half, top_y, run, dir_z):
			continue
		var top := _build_platform(center, half, top_y)
		_build_ramp(top, half.y, top_y, run, minf(half.x * 1.2, 3.0), dir_z)
		_footprints.append({"pos": Vector3(center.x, 0.0, center.y),
				"r": maxf(half.x, half.y) + 0.5})
		_footprints.append({"pos": Vector3(center.x, 0.0, center.y + dir_z * (half.y + run * 0.5)),
				"r": run * 0.5 + 1.0})
		_build_high_cover(top, half, rng, ghost)
		# Reward spot on the cap, nudged toward the far edge (away from the ramp +
		# the centre-clustered cover) so the player crosses the high ground to grab
		# it. y = cap top; the bonus pickup floats just above it. (V3 reward hook.)
		_high_reward_points.append(Vector3(top.x, top.y, top.z - dir_z * half.y * 0.45))
		placed += 1


## True if a Tiers platform (+ its inward ramp) fits inside the room without
## crossing a wall, the L-notch, the player keep-clear zone, or an already-placed
## footprint (ground obstacles + earlier platforms in this build).
func _platform_fits(center: Vector2, half: Vector2, top_y: float, run: float,
		dir_z: float) -> bool:
	if absf(center.x) + half.x > _inner_limit.x or absf(center.y) + half.y > _inner_limit.y:
		return false
	var ramp_far_z := center.y + dir_z * (half.y + run)
	if absf(ramp_far_z) > _inner_limit.y:
		return false
	if _in_notch(center, maxf(half.x, half.y) + 0.5) \
			or _in_notch(Vector2(center.x, ramp_far_z), 1.0):
		return false
	var clear := maxf(half.x, half.y) + run  # platform shouldn't loom over the spawn
	if Vector2(center.x - _player_spawn_pos.x, center.y - _player_spawn_pos.z).length() \
			< SPAWN_KEEP_CLEAR + clear:
		return false
	for fp in _footprints:
		if Vector2(center.x - fp.pos.x, center.y - fp.pos.z).length() \
				< maxf(half.x, half.y) + float(fp.r) + 2.0:
			return false
	return true


## One or two low boxes on a platform cap -- the player's reward for taking the
## high ground (a crouch-cover spot with a sightline; enemies stay below). NOT in
## the cover_point group: enemies can't path up here, so it's player cover only.
## Grouped room_high_cover for the test + the per-build sweep.
func _build_high_cover(top: Vector3, half: Vector2, rng: RandomNumberGenerator,
		ghost := false) -> void:
	var mat: StandardMaterial3D = _ghost_material if ghost else _active_struct_mat
	for i in 1 + rng.randi_range(0, 1):
		var cw := rng.randf_range(1.4, 2.0)
		var cd := rng.randf_range(0.8, 1.1)
		var margin_x := maxf(half.x - cw * 0.5 - 0.4, 0.0)
		var margin_z := maxf(half.y - cd * 0.5 - 0.4, 0.0)
		var pos := Vector3(top.x + rng.randf_range(-margin_x, margin_x), top.y + 0.5,
				top.z + rng.randf_range(-margin_z, margin_z))
		_add_structure_box(Vector3(cw, 1.0, cd), pos,
				Vector3(0.0, rng.randf_range(0.0, TAU), 0.0), mat, "room_high_cover")


## Cover markers go into the existing "cover_point" group so enemy_ai.gd picks
## them up with zero changes; it already validates line-of-sight and distance
## at claim time, so these only need to be plausible candidates.
func _place_cover_markers(boxes: Array[Dictionary]) -> void:
	for desc in boxes:
		var pos: Vector3 = desc.pos
		var outward := Vector3(pos.x, 0.0, pos.z).normalized()
		if outward.length_squared() < 0.5:  # center obstacle: any side works
			outward = Vector3.FORWARD
		var stand_off: float = desc.r + 0.8
		match desc.kind:
			"pillar":
				_add_cover_marker(pos + outward * stand_off)
			"crate":
				_add_cover_marker(pos + outward * stand_off)
				_add_cover_marker(pos - outward * stand_off)
			"wall":
				# Two spots behind the long face pointing away from center.
				var normal := Vector3(0, 0, 1).rotated(Vector3.UP, desc.yaw)
				if normal.dot(outward) < 0.0:
					normal = -normal
				var along := Vector3(1, 0, 0).rotated(Vector3.UP, desc.yaw)
				var face: Vector3 = pos + normal * (desc.size.z * 0.5 + 0.8)
				_add_cover_marker(face + along * desc.size.x * 0.25)
				_add_cover_marker(face - along * desc.size.x * 0.25)


func _add_cover_marker(pos: Vector3) -> void:
	if absf(pos.x) > _inner_limit.x or absf(pos.z) > _inner_limit.y:
		return
	if _in_notch(Vector2(pos.x, pos.z), 0.5):
		return
	var marker := Marker3D.new()
	marker.add_to_group("cover_point")
	_generated.add_child(marker)
	marker.position = Vector3(pos.x, 0.0, pos.z)
	_cover_marker_count += 1


# ---------------------------------------------------------------- validation

func _validate_and_collect(room: int, rng: RandomNumberGenerator) -> bool:
	if _cover_marker_count < MIN_COVER_POINTS:
		return false
	if _nav_region.navigation_mesh.get_polygon_count() < MIN_NAV_POLYGONS:
		return false
	var map: RID = _nav_region.get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map, _player_spawn_pos)

	# Enemy spawns: walkable, far from the player, reachable from the spawn.
	var needed: int = RunManager.enemy_count_for_room(room)
	var tries := 0
	while _spawn_points.size() < needed and tries < 250:
		tries += 1
		var xz := _random_xz(rng)
		var candidate := Vector3(xz.x, 0.0, xz.y)
		if candidate.distance_to(_player_spawn_pos) < _min_spawn_dist:
			continue
		if _in_notch(xz, 1.0):  # never spawn in the L's bare corner
			continue
		if _inside_footprint(candidate, 1.2):
			continue
		if not _spaced_apart(_spawn_points, candidate, 2.0):
			continue
		var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
		if snapped.distance_to(candidate) > 2.0:  # not on the walkable surface
			continue
		if not _reachable(map, start, snapped):
			continue
		_spawn_points.append(snapped + Vector3.UP * 0.1)
	if _spawn_points.size() < needed:
		_spawn_points.clear()
		return false

	_collect_pickup_points(map, start, rng)
	return true


## Risk/reward placement: ammo tucked behind cover, health/armor in the open.
## Best effort - RunDirector falls back to authored spots for any shortfall.
func _collect_pickup_points(map: RID, start: Vector3, rng: RandomNumberGenerator) -> void:
	var tries := 0
	while _count_pickups(false) < 2 and tries < 80 and not _footprints.is_empty():
		tries += 1
		var footprint: Dictionary = _footprints[rng.randi_range(0, _footprints.size() - 1)]
		var dir := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		if dir.length_squared() < 0.05:
			continue
		var candidate: Vector3 = footprint.pos * Vector3(1, 0, 1) \
				+ dir.normalized() * (float(footprint.r) + 1.0)
		if _in_notch(Vector2(candidate.x, candidate.z), 0.5):
			continue
		var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
		if snapped.distance_to(candidate) > 1.5 or not _reachable(map, start, snapped):
			continue
		_pickup_points.append({"position": Vector3(snapped.x, 0.0, snapped.z), "exposed": false})
	tries = 0
	while _count_pickups(true) < 4 and tries < 120:
		tries += 1
		var xz := _random_xz(rng)
		var candidate := Vector3(xz.x, 0.0, xz.y)
		if _in_notch(xz, 1.5):  # never place pickups in the L's bare corner
			continue
		if _inside_footprint(candidate, 2.5):
			continue
		if candidate.distance_to(_player_spawn_pos) < 6.0:
			continue
		if not _spaced_from_pickups(candidate, 4.0):
			continue
		var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
		if snapped.distance_to(candidate) > 1.5 or not _reachable(map, start, snapped):
			continue
		_pickup_points.append({"position": Vector3(snapped.x, 0.0, snapped.z), "exposed": true})


## Fallback enemy spawns when generation fails: authored markers, clamped into
## the (possibly smaller) procedural room so they never land in or past a wall.
func _collect_fallback_spawns(room: int) -> void:
	_spawn_points.clear()
	var markers := get_tree().get_nodes_in_group("enemy_spawn")
	if markers.is_empty():
		return
	var needed: int = RunManager.enemy_count_for_room(room)
	for i in needed:
		var base: Vector3 = (markers[i % markers.size()] as Node3D).global_position
		if i >= markers.size():
			base += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		base.x = clampf(base.x, -_inner_limit.x, _inner_limit.x)
		base.z = clampf(base.z, -_inner_limit.y, _inner_limit.y)
		if _in_notch(Vector2(base.x, base.z), 1.0):
			# Bare corner: drop the enemy on the always-walkable north centre instead.
			base = Vector3(0.0, base.y, -(_inner_limit.y - 1.0))
		_spawn_points.append(base)


func _count_pickups(exposed: bool) -> int:
	var count := 0
	for point in _pickup_points:
		if point.exposed == exposed:
			count += 1
	return count


func _inside_footprint(pos: Vector3, margin: float) -> bool:
	for footprint in _footprints:
		if Vector2(pos.x - footprint.pos.x, pos.z - footprint.pos.z).length() \
				< float(footprint.r) + margin:
			return true
	return false


func _spaced_apart(points: Array[Vector3], candidate: Vector3, min_dist: float) -> bool:
	for point in points:
		if Vector2(candidate.x - point.x, candidate.z - point.z).length() < min_dist:
			return false
	return true


func _spaced_from_pickups(candidate: Vector3, min_dist: float) -> bool:
	for point in _pickup_points:
		var pos: Vector3 = point.position
		if Vector2(candidate.x - pos.x, candidate.z - pos.z).length() < min_dist:
			return false
	return true


func _reachable(map: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(to) < 1.5
