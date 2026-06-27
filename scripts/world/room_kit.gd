extends Resource
class_name RoomKit
## A "skin" for procedural rooms: maps the abstract shell (floor rectangles + wall
## lines) onto a Kenney modular building kit. Floor + wall pieces are single-mesh 1 m
## modules, so they tile via MultiMeshInstance3D (thousands of modules per room, one
## draw batch each); higher-detail props are low-count and instance their scene directly.
##
## BUILD-ALONGSIDE: a kit only adds *visual*, non-colliding meshes layered over the
## existing tested collision boxes -- it never touches collision, navmesh, spawns or any
## gameplay geometry. The shell's StaticBody boxes still own physics; the kit just makes
## the room look like a place instead of gray primitives.
##
## The defaults describe the Kenney space-station kit (measured 1 m grid: floor 1x1x0.3,
## wall 1 wide x 1 tall x 0.3 thick). Per-layer kits become authored .tres later.

@export var kit_dir: String = "res://Assets/kenney_space-station-kit/Models/GLB format/"
@export var floor_piece: String = "floor"
@export var wall_piece: String = "wall"
@export var module: float = 1.0  # grid unit (this kit is 1 m)
## The kit's shared palette atlas: every piece UVs into this one texture. Per-layer
## recolouring multiplies it by a tint (albedo_color x texture), so the Heap reads
## dim green and the Stack steel-blue while the kit keeps its internal shading detail.
@export var colormap: String = "res://Assets/kenney_space-station-kit/Models/GLB format/Textures/colormap.png"
## Cover/obstacle props (full paths, shared across kits -- a container reads as a crate in
## any layer). Instanced (not MultiMesh) since they're low-count + multi-mesh, and tinted to
## the layer while KEEPING their own colormap (so their UVs sample the right atlas).
@export var crate_prop: String = "res://Assets/kenney_space-station-kit/Models/GLB format/container.glb"
@export var pillar_prop: String = "res://Assets/kenney_space-station-kit/Models/GLB format/container-tall.glb"

# Cache of {piece_name: {mesh, size, aabb}} so each GLB is loaded/measured once per kit.
var _mesh_cache: Dictionary = {}
# Cache of {prop_path: {scene, size}} for instanced props.
var _prop_cache: Dictionary = {}
# Cache of {tint_html: StandardMaterial3D} so each layer tint is built once.
var _tint_cache: Dictionary = {}


## A ready-to-use space-station kit (defaults already describe it): a fine 1 m grid,
## 1 m-tall wall courses. Used for the Heap.
static func space_station() -> RoomKit:
	return RoomKit.new()


## The Kenney modular-space kit: a chunkier 4 m grid with full-height (~4.25 m) single-piece
## walls and flat 4x4 floor planes. A whole different read from the space-station kit, so
## crossing into the layer that uses it (the Stack) swaps the entire look, not just the tint.
static func modular_space() -> RoomKit:
	var k := RoomKit.new()
	k.kit_dir = "res://Assets/kenney_modular-space-kit_1.0/Models/GLB format/"
	k.floor_piece = "template-floor"
	k.wall_piece = "template-wall"
	k.module = 4.0
	k.colormap = "res://Assets/kenney_modular-space-kit_1.0/Models/GLB format/Textures/colormap.png"
	return k


# ------------------------------------------------------------------ public tiling

## Tile floor modules across the rect [-half..half] (XZ), with the tile TOP at `top_y`
## (so it sits flush on the shell's collision floor, whose top is y = 0). Returns the
## MultiMeshInstance3D added under `parent`.
func tile_floor(parent: Node3D, half: Vector2, top_y: float, tint := Color.WHITE,
		tile_name := "KitFloor", center := Vector2.ZERO) -> MultiMeshInstance3D:
	var info := _piece(floor_piece)
	if info.mesh == null:
		return null
	var tile: float = info.size.x
	var top_off: float = (info.aabb as AABB).end.y  # local top extent (slab thickness, or 0 for a flat plane)
	var nx: int = maxi(1, int(round(half.x * 2.0 / tile)))
	var nz: int = maxi(1, int(round(half.y * 2.0 / tile)))
	var step_x := half.x * 2.0 / nx
	var step_z := half.y * 2.0 / nz
	var y := top_y - top_off  # drop the mesh so its top surface lands on top_y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = info.mesh
	mm.instance_count = nx * nz
	var i := 0
	for ix in nx:
		for iz in nz:
			var px := center.x - half.x + (ix + 0.5) * step_x
			var pz := center.y - half.y + (iz + 0.5) * step_z
			var b := Basis.IDENTITY.scaled(Vector3(step_x / tile, 1.0, step_z / tile))
			mm.set_instance_transform(i, Transform3D(b, Vector3(px, y, pz)))
			i += 1
	return _attach_mm(parent, mm, tile_name, tint)


## Build a vertical wall of modules along the XZ segment a->b (the wall's INNER-face
## line), `height` tall, its detailed face turned toward `inward`. The kit wall module
## is thinner than the shell's collision box, so we sit its inner face on the line and
## let the (thicker) collision box stay behind it.
func build_wall_run(parent: Node3D, a: Vector2, b: Vector2, height: float,
		inward: Vector2, tint := Color.WHITE, run_name := "KitWall") -> MultiMeshInstance3D:
	var info := _piece(wall_piece)
	if info.mesh == null:
		return null
	var seg := b - a
	var length := seg.length()
	if length < 0.01:
		return null
	var dir := seg / length
	var face := Vector2(-dir.y, dir.x)  # = dir x UP, the module's local +Z (detailed) face
	var start := a
	if face.dot(inward) < 0.0:           # traverse so the detailed face turns inward
		dir = -dir
		start = b
		face = -face
	var mod_w: float = info.size.x
	var course_h: float = info.size.y
	var inner_z: float = (info.aabb as AABB).end.z  # local +Z extent = the inner (detailed) face
	var n: int = maxi(1, int(round(length / mod_w)))
	var step := length / n
	# Stack the nearest whole number of courses, then scale Y so they fill `height` exactly.
	# Space-station (1 m courses) -> 5 courses x1.0; modular (~4.25 m single-piece walls) ->
	# 1 course scaled up to height. Both fit WALL_HEIGHT regardless of the kit's grid.
	var courses: int = maxi(1, int(round(height / course_h)))
	var y_scale := height / (course_h * courses)
	var dir3 := Vector3(dir.x, 0.0, dir.y)
	var face3 := Vector3(face.x, 0.0, face.y)
	var start3 := Vector3(start.x, 0.0, start.y)
	var basis := Basis(dir3 * (step / mod_w), Vector3.UP * y_scale, face3)
	var back := -face3 * inner_z  # put the module's inner (+Z) face on the line (kits differ: centred vs face-origin)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = info.mesh
	mm.instance_count = n * courses
	var i := 0
	for k in n:
		var along := start3 + dir3 * ((k + 0.5) * step)
		for j in courses:
			var origin := along + back + Vector3(0.0, j * course_h * y_scale, 0.0)
			mm.set_instance_transform(i, Transform3D(basis, origin))
			i += 1
	return _attach_mm(parent, mm, run_name, tint)


## Tint an instanced prop (or any node subtree) with the layer colour: for every
## MeshInstance3D under `node`, multiply its OWN albedo texture by `tint` (keeping the prop's
## own colormap so its UVs stay correct -- a space-station prop must not sample a different
## kit's atlas). Falls back to the kit colormap if a mesh has no texture.
func tint_node(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		(node as MeshInstance3D).material_override = _prop_tint_material(node as MeshInstance3D, tint)
	for c in node.get_children():
		tint_node(c, tint)


const OBSTACLE_CELL := 1.3  # target prop cell size (m); cells stay near-cubic so crates don't distort

## Fill an obstacle box with a small CLUSTER of tinted kit props (a pile of crates / a stack of
## tech blocks), rather than one stretched prop -- tiling near-cubic cells keeps each prop's
## scaling near-uniform, so they read as real cargo instead of a distorted box. The box is
## centred at the body origin resting on the floor; each prop's base sits on its cell bottom.
## The caller hides the gray box mesh + keeps its collision.
func skin_obstacle(parent: Node3D, size: Vector3, kind: String, tint: Color) -> void:
	var info := _prop(crate_prop if kind == "crate" else pillar_prop)
	if info.scene == null:
		return
	var nat: Vector3 = info.size
	var nx: int = maxi(1, int(round(size.x / OBSTACLE_CELL)))
	var ny: int = maxi(1, int(round(size.y / OBSTACLE_CELL)))
	var nz: int = maxi(1, int(round(size.z / OBSTACLE_CELL)))
	var cell := Vector3(size.x / nx, size.y / ny, size.z / nz)
	var scl := Vector3(cell.x / maxf(nat.x, 0.01), cell.y / maxf(nat.y, 0.01), cell.z / maxf(nat.z, 0.01))
	for ix in nx:
		for iy in ny:
			for iz in nz:
				var inst := (info.scene as PackedScene).instantiate() as Node3D
				parent.add_child(inst)
				inst.scale = scl
				inst.position = Vector3(
						-size.x * 0.5 + (ix + 0.5) * cell.x,
						-size.y * 0.5 + iy * cell.y,  # each prop's base on its cell bottom
						-size.z * 0.5 + (iz + 0.5) * cell.z)
				tint_node(inst, tint)


## Skin one shell WALL box (a StaticBody box of size `size` centred at `pos`) with kit
## wall modules. The thin horizontal axis is the wall's thickness; the long axis is its
## run; the detailed face turns toward the room (origin) -- which also points toward the
## floor for the concave notch walls, since each sits between a bare corner (outer) and
## floor (inner). Generic, so it skins rect / L / T / plus walls uniformly.
func build_wall_box(parent: Node3D, pos: Vector3, size: Vector3, height: float,
		tint := Color.WHITE, run_name := "KitWall") -> MultiMeshInstance3D:
	var center2 := Vector2(pos.x, pos.z)
	var length_dir: Vector2
	var inward: Vector2
	var half_len: float
	var half_thick: float
	if size.x <= size.z:                 # thin in X -> runs along Z, faces +/- X
		half_thick = size.x * 0.5
		half_len = size.z * 0.5
		length_dir = Vector2(0.0, 1.0)
		var sx := signf(pos.x)
		inward = Vector2(-sx if sx != 0.0 else -1.0, 0.0)  # toward origin on X
	else:                                # thin in Z -> runs along X, faces +/- Z
		half_thick = size.z * 0.5
		half_len = size.x * 0.5
		length_dir = Vector2(1.0, 0.0)
		var sz := signf(pos.z)
		inward = Vector2(0.0, -sz if sz != 0.0 else -1.0)  # toward origin on Z
	var inner_center := center2 + inward * half_thick  # the wall's inner-face line
	var a := inner_center - length_dir * half_len
	var b := inner_center + length_dir * half_len
	return build_wall_run(parent, a, b, height, inward, tint, run_name)


## Convenience: skin a plain rectangular shell (floor + four walls) under `parent`,
## floor + walls tinted independently (per-layer palette gives major-transition variety).
func skin_box(parent: Node3D, half: Vector2, height: float,
		floor_tint := Color.WHITE, wall_tint := Color.WHITE) -> void:
	var hx := half.x
	var hz := half.y
	tile_floor(parent, half, 0.0, floor_tint)
	# z- is north (the exit-gate edge); room centre is at the origin. Names are "Kit*"
	# so they never clash with the gray shell's StaticBody boxes (WallN/WallS/...).
	build_wall_run(parent, Vector2(-hx, -hz), Vector2(hx, -hz), height, Vector2(0.0, 1.0), wall_tint, "KitWallN")
	build_wall_run(parent, Vector2(-hx, hz), Vector2(hx, hz), height, Vector2(0.0, -1.0), wall_tint, "KitWallS")
	build_wall_run(parent, Vector2(hx, -hz), Vector2(hx, hz), height, Vector2(-1.0, 0.0), wall_tint, "KitWallE")
	build_wall_run(parent, Vector2(-hx, -hz), Vector2(-hx, hz), height, Vector2(1.0, 0.0), wall_tint, "KitWallW")


# ------------------------------------------------------------------ internals

func _attach_mm(parent: Node3D, mm: MultiMesh, mm_name: String, tint: Color) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	mmi.material_override = _tint_material(tint)
	parent.add_child(mmi)
	return mmi


## A material that draws the kit's colormap atlas multiplied by `tint` (so a single
## per-layer colour recolours every piece while preserving its baked palette detail).
## Cached per colour. Nearest filtering keeps the atlas swatches crisp at UV seams.
func _tint_material(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html(true)
	if _tint_cache.has(key):
		return _tint_cache[key]
	var mat := StandardMaterial3D.new()
	var tex := load(colormap) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.metallic = 0.0
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_tint_cache[key] = mat
	return mat


## The first mesh + its AABB size for a named kit piece (cached). {mesh, size}.
func _piece(piece_name: String) -> Dictionary:
	if _mesh_cache.has(piece_name):
		return _mesh_cache[piece_name]
	var out := {"mesh": null, "size": Vector3.ONE, "aabb": AABB()}
	var packed := load(kit_dir + piece_name + ".glb") as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		var mi := _first_mesh(inst)
		if mi != null:
			var ab: AABB = (mi.mesh as Mesh).get_aabb()
			out.mesh = mi.mesh
			out.size = ab.size
			out.aabb = ab
		inst.free()
	_mesh_cache[piece_name] = out
	return out


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node
	for c in node.get_children():
		var found := _first_mesh(c)
		if found != null:
			return found
	return null


## A prop scene + its natural AABB size (cached). {scene, size}.
func _prop(path: String) -> Dictionary:
	if _prop_cache.has(path):
		return _prop_cache[path]
	var out := {"scene": null, "size": Vector3.ONE}
	var packed := load(path) as PackedScene
	if packed != null:
		out.scene = packed
		var inst := packed.instantiate()
		var ab := _subtree_aabb(inst, inst)
		if ab.size != Vector3.ZERO:
			out.size = ab.size
		inst.free()
	_prop_cache[path] = out
	return out


## Merged AABB of every MeshInstance3D under `node`, in `root`'s local space.
func _subtree_aabb(node: Node, root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all_meshes(node):
		var ab: AABB = _rel_xform(root, mi) * (mi.mesh as Mesh).get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out


func _all_meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node)
	for c in node.get_children():
		found.append_array(_all_meshes(c))
	return found


## Transform of `mi` relative to `root` (product of transforms along the path, root included),
## matching the layout a fresh instance gets when added to the tree at identity.
func _rel_xform(root: Node, mi: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		if n == root:
			break
		n = n.get_parent()
	return xf


## A tint material that keeps the mesh's OWN albedo texture (so the prop's UVs sample its own
## atlas), multiplied by `tint`. Falls back to the kit colormap if the mesh has no texture.
func _prop_tint_material(mesh: MeshInstance3D, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var src := mesh.get_active_material(0)
	var tex: Texture2D = null
	if src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
	if tex == null:
		tex = load(colormap) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.metallic = 0.0
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat
