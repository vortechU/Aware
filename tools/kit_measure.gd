extends Node
## Diagnostic: prints the local-space AABB (size + position) of the key Kenney
## space-station kit pieces, so the RoomKit tiler knows the module grid. Not an
## assertion harness -- just a measurement dump. Safe to delete.
## Run: godot --headless --path . res://tools/kit_measure.tscn

const BASE := "res://Assets/kenney_space-station-kit/Models/GLB format/"
const PIECES := [
	"floor", "floor-panel", "floor-detail",
	"wall", "wall-corner", "wall-pillar", "wall-door", "wall-window", "wall-detail",
	"container", "container-tall", "container-wide", "container-flat",
	"structure-barrier", "structure-barrier-high", "structure", "structure-panel",
	"computer", "table", "pipe",
]


func _ready() -> void:
	for p in PIECES:
		var path: String = BASE + String(p) + ".glb"
		var packed := load(path) as PackedScene
		if packed == null:
			print("MISS  %s (failed to load)" % p)
			continue
		var inst := packed.instantiate()
		add_child(inst)
		var aabb := _merged_aabb(inst)
		print("%-24s size=(%6.3f, %6.3f, %6.3f)  pos=(%6.3f, %6.3f, %6.3f)  end=(%6.3f, %6.3f, %6.3f)" % [
			p,
			aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.position.x, aabb.position.y, aabb.position.z,
			aabb.end.x, aabb.end.y, aabb.end.z,
		])
		inst.queue_free()
	print("KIT_MEASURE_DONE")
	get_tree().quit(0)


## Union of every MeshInstance3D's AABB in the subtree, in the root's local space.
func _merged_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all_mesh_instances(root):
		var local: AABB = mi.mesh.get_aabb()
		# Transform the mesh AABB into `root` space (relative to the instance root).
		var xf: Transform3D = mi.global_transform
		var world := xf * local
		if first:
			out = world
			first = false
		else:
			out = out.merge(world)
	return out


func _all_mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node)
	for c in node.get_children():
		found.append_array(_all_mesh_instances(c))
	return found
