extends Node
## Modular-kit room skin Pass B: a layer profile carrying a "kit" re-skins the
## rectangular shell with the Kenney space-station kit, recoloured by the layer palette,
## WITHOUT touching collision, navmesh, spawns or validation.
## Run: godot --headless --path . res://tools/kit_room_test.tscn
##
## Pure section: RoomKit loads its 1 m floor/wall modules and builds a tint material
## (colormap atlas x per-layer colour -- the recolouring the major-transition variety
## relies on).
## Scene section: force a kit'd rectangular room through the REAL build_room and assert
##   - it still validates OK (the visual overlay didn't disturb the collider-baked navmesh)
##   - the kit overlay meshes are present under the shell (KitFloor + four KitWall* runs)
##   - the gray shell box visuals are hidden but their StaticBody collision survives
##   - an ENDLESS build (no "kit") is left on the gray shell, byte-for-byte (the gate).

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("KIT_ROOM_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("KIT_ROOM_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	_part_pure()
	await _part_scene()


# ---------------------------------------------------------------- A. pure data

func _part_pure() -> void:
	var kit := RoomKit.space_station()
	_check(kit != null, "RoomKit.space_station() returned null")

	# The 1 m floor + wall modules load and measure ~1 m on the grid axes.
	var floor_info: Dictionary = kit._piece(kit.floor_piece)
	var wall_info: Dictionary = kit._piece(kit.wall_piece)
	_check(floor_info.mesh != null, "kit floor piece failed to load")
	_check(wall_info.mesh != null, "kit wall piece failed to load")
	_check(absf((floor_info.size as Vector3).x - 1.0) < 0.01, "kit floor module is not 1 m wide")
	_check(absf((wall_info.size as Vector3).y - 1.0) < 0.01, "kit wall course is not 1 m tall")

	# The recolour material = colormap atlas multiplied by the layer tint.
	var tint := Color(0.2, 0.35, 0.45)
	var mat := kit._tint_material(tint)
	_check(mat is StandardMaterial3D, "tint material is not a StandardMaterial3D")
	_check(mat.albedo_color.is_equal_approx(tint), "tint material did not take the layer colour")
	_check(mat.albedo_texture != null, "tint material lost the colormap atlas (would kill detail)")
	# Two distinct layer tints yield two distinct materials (Heap != Stack recolour).
	var heap_tint: Color = LayerCatalog.profile_for_room(1).get("wall_color", Color.WHITE)
	var stack_tint: Color = LayerCatalog.profile_for_room(7).get("wall_color", Color.WHITE)
	_check(not heap_tint.is_equal_approx(stack_tint), "Heap and Stack wall tints are identical")


# ---------------------------------------------------------------- B. scene build

func _part_scene() -> void:
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var tries := 0
	while get_tree().get_nodes_in_group("enemies").size() < 5 and tries < 900:
		tries += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set("sight_range", 0.0)  # idle the starting squad

	var builder: Node = main.get_node("RoomBuilder")
	var shell: Node = main.get_node("NavRegion/GeneratedShell")

	# --- A kit'd rectangular room (footprint 1 = the standard square) ---------------
	RunManager.run_seed = 55501
	var heap: Dictionary = LayerCatalog.profile_for_room(1)
	var kit_profile := {
		"kit": "space_station",
		"footprint_pool": [1],
		"archetype_pool": ["scattered_cover"],
		"floor_color": heap.get("floor_color", Color.WHITE),
		"wall_color": heap.get("wall_color", Color.WHITE),
	}
	var result: Dictionary = await builder.build_room(2, kit_profile)
	_check(result.ok, "kit'd room failed validation -- overlay disturbed the collider-baked navmesh")
	_check(String(builder.get("_shape")) == "rect", "test footprint was not the rectangular shell")

	# Kit overlay present: a tiled floor + four wall runs, all MultiMeshInstance3D.
	var kit_floor := shell.get_node_or_null("KitFloor")
	_check(kit_floor is MultiMeshInstance3D, "no KitFloor MultiMesh overlay under the shell")
	for w in ["KitWallN", "KitWallS", "KitWallE", "KitWallW"]:
		_check(shell.get_node_or_null(w) is MultiMeshInstance3D, "missing kit wall overlay %s" % w)

	# The kit floor's MultiMesh actually has instances (it tiled something).
	if kit_floor is MultiMeshInstance3D:
		_check((kit_floor as MultiMeshInstance3D).multimesh.instance_count > 0,
				"KitFloor overlay has zero tiles")

	# Gray shell box visuals hidden, but their collision survives (drives the bake).
	var gray_floor := shell.get_node_or_null("Floor") as StaticBody3D
	_check(gray_floor != null, "shell lost its collision Floor StaticBody")
	if gray_floor != null:
		var gray_mesh := _first_child_mesh(gray_floor)
		_check(gray_mesh != null and not gray_mesh.visible,
				"gray shell Floor mesh is still visible under the kit (z-fight)")
		_check(_has_collision_shape(gray_floor), "shell Floor lost its CollisionShape3D")

	# --- Pass C: a kit'd NOTCHED room (T-shape) is skinned per shell box -------------
	# (CSG arena was already retired by the rect build above, so the notch is a real hole.)
	var rb: GDScript = load("res://scripts/run/room_builder.gd")
	var t_idx: int = rb.FOOTPRINTS.size() + rb.L_FOOTPRINTS.size()  # first T in the combined list
	RunManager.run_seed = 55777
	var t_profile := {
		"kit": "space_station",
		"footprint_pool": [t_idx],
		"archetype_pool": ["scattered_cover"],
		"floor_color": heap.get("floor_color", Color.WHITE),
		"wall_color": heap.get("wall_color", Color.WHITE),
	}
	var t_result: Dictionary = await builder.build_room(2, t_profile)
	_check(t_result.ok, "kit'd T room failed validation")
	_check(String(builder.get("_shape")) == "T", "forced T footprint did not build the T shell")
	# Both T floor boxes get a kit floor overlay (so the wide crossbar + narrow stem are tiled).
	_check(shell.get_node_or_null("KitFloor") is MultiMeshInstance3D, "T missing KitFloor overlay")
	_check(shell.get_node_or_null("KitFloor2") is MultiMeshInstance3D, "T missing KitFloor2 (stem) overlay")
	# The concave notch walls get kit overlays too (proof the generic skin handled them).
	var notch_walls := 0
	for c in shell.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("KitWallNotch"):
			notch_walls += 1
	_check(notch_walls >= 2, "T notch walls were not skinned (got %d kit notch walls)" % notch_walls)
	# A bare north corner stays floorless: no kit floor tile lands deep in the corner.
	var hx: float = builder.get("_room_half").x
	var hz: float = builder.get("_room_half").y
	_check(not _floor_tile_near(shell, Vector3((hx - 1.0), 0.0, -hz + 1.0), 1.4),
			"a kit floor tile leaked into the T's bare NE corner")

	# --- The gate: an ENDLESS build (no "kit") keeps the plain gray shell ------------
	RunManager.run_seed = 55502
	var plain := {"footprint_pool": [1], "archetype_pool": ["scattered_cover"]}
	var result2: Dictionary = await builder.build_room(2, plain)
	_check(result2.ok, "plain ENDLESS room failed to build")
	_check(shell.get_node_or_null("KitFloor") == null,
			"ENDLESS room got a kit overlay -- the 'kit' gate leaked")
	var gray_floor2 := shell.get_node_or_null("Floor") as StaticBody3D
	if gray_floor2 != null:
		var gm := _first_child_mesh(gray_floor2)
		_check(gm != null and gm.visible, "ENDLESS shell Floor mesh was hidden (skin ran without a kit)")


## True if any kit floor tile (across all KitFloor* overlays) sits within `radius` (XZ)
## of `point` -- used to prove a bare notch corner stays floorless.
func _floor_tile_near(shell: Node, point: Vector3, radius: float) -> bool:
	var target := Vector2(point.x, point.z)
	for c in shell.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("KitFloor"):
			var mm := (c as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var o := mm.get_instance_transform(i).origin
				if Vector2(o.x, o.z).distance_to(target) <= radius:
					return true
	return false


func _first_child_mesh(node: Node) -> MeshInstance3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			return c
	return null


func _has_collision_shape(node: Node) -> bool:
	for c in node.get_children():
		if c is CollisionShape3D:
			return true
	return false
