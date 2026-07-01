class_name ShopTurntable
extends Node3D
## The 3D item display beside the ShopTerminal: a dark pedestal with a glowing
## rim ring + spotlight, and a slowly-spinning display model that swaps to match
## the hovered shop item (the reference Roblox shop's lit chair-on-a-turntable).
## Asset-free -- the display models are built from primitives + emissive
## StandardMaterials, tinted per item, so it needs no imported meshes. A host
## connects ShopTerminal.item_focused -> show_item.

@export var spin_speed := 0.6          # rad/sec
@export var float_height := 1.45        # display centre height above the base

var _pivot: Node3D
var _name_label: Label3D


func _ready() -> void:
	_build_pedestal()


func _process(delta: float) -> void:
	if _pivot != null:
		_pivot.rotate_y(spin_speed * delta)


## Swap the displayed model + floating name to the given item dictionary
## (shape/color/name). Safe to call every hover; rebuilds the model cheaply.
func show_item(item: Dictionary) -> void:
	if _pivot == null:
		return
	for child in _pivot.get_children():
		child.queue_free()
	var color := item.get("color", Color(0.3, 0.9, 0.8)) as Color
	var model := _build_model(String(item.get("shape", "box")), color)
	model.position = Vector3(0, float_height, 0)
	_pivot.add_child(model)
	if _name_label != null:
		_name_label.text = String(item.get("name", item.get("id", "")))
		_name_label.modulate = color.lightened(0.4)


## Number of display models currently mounted (test hook).
func display_count() -> int:
	return _pivot.get_child_count() if _pivot != null else 0


# ------------------------------------------------------------------ build

func _build_pedestal() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.9
	base_mesh.bottom_radius = 1.1
	base_mesh.height = 0.9
	base.mesh = base_mesh
	base.position = Vector3(0, 0.45, 0)
	base.material_override = _emissive(Color(0.10, 0.16, 0.18), Color(0.1, 0.5, 0.55), 0.4)
	add_child(base)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.95
	ring_mesh.outer_radius = 1.15
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0.92, 0)
	ring.material_override = _emissive(Color(0.2, 1.0, 0.7), Color(0.2, 1.0, 0.7), 3.0)
	add_child(ring)

	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 3.4, 0.2)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.light_color = Color(0.6, 1.0, 0.85)
	lamp.light_energy = 6.0
	lamp.spot_range = 6.0
	lamp.spot_angle = 32.0
	add_child(lamp)

	_pivot = Node3D.new()
	_pivot.name = "DisplayPivot"
	add_child(_pivot)

	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.pixel_size = 0.005
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 48
	_name_label.outline_size = 10
	_name_label.position = Vector3(0, 2.5, 0)
	add_child(_name_label)


func _build_model(shape: String, color: Color) -> Node3D:
	var root := Node3D.new()
	match shape:
		"chair":
			_build_chair(root, color)
		"helmet":
			var m := _mesh_node(SphereMesh.new(), color)
			m.scale = Vector3(0.55, 0.5, 0.55)
			root.add_child(m)
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.45
			sm.height = 0.9
			root.add_child(_mesh_node(sm, color))
		"torus":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.25
			tm.outer_radius = 0.5
			var tn := _mesh_node(tm, color)
			tn.rotation_degrees = Vector3(70, 0, 0)
			root.add_child(tn)
		"capsule":
			var cm := CapsuleMesh.new()
			cm.radius = 0.3
			cm.height = 1.0
			root.add_child(_mesh_node(cm, color))
		"prism":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.8, 0.9, 0.8)
			root.add_child(_mesh_node(pm, color))
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7, 0.7, 0.7)
			root.add_child(_mesh_node(bm, color))
	return root


## A little composite chair, echoing the reference shop's hero item.
func _build_chair(root: Node3D, color: Color) -> void:
	var mat := _emissive(color.darkened(0.2), color, 1.4)
	var seat := _box(Vector3(0.5, 0.07, 0.5), Vector3(0, 0, 0), mat)
	root.add_child(seat)
	var back := _box(Vector3(0.5, 0.55, 0.07), Vector3(0, 0.31, -0.215), mat)
	root.add_child(back)
	var lx := 0.2
	var lz := 0.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			root.add_child(_box(Vector3(0.06, 0.45, 0.06),
					Vector3(lx * sx, -0.26, lz * sz), mat))


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	return mi


func _mesh_node(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _emissive(color.darkened(0.2), color, 1.4)
	return mi


func _emissive(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat
