class_name Hackable
extends Node
## Marks a world prop as hackable -- drop it as a CHILD of the PhysicsBody3D you want the
## player to be able to inject an adjective into. The body it governs is its parent (a
## RigidBody3D so mutate-body adjectives like Heavy can release it under gravity; it
## usually starts `freeze = true` so it reads as a static/floating prop until hacked).
##
## Build-alongside: purely additive. The prop needs no script of its own -- this component
## sets a "hackable" meta back-reference on the body, which the HackManager reads after a
## targeting raycast to map a hit collider back to its Hackable.

## Which adjectives this object will accept. Empty == accepts any unlocked adjective.
@export var accepts: PackedStringArray = []

var body: PhysicsBody3D
var active_trait: TraitInstance = null
var highlighted := false

var _glow: MeshInstance3D = null


func _ready() -> void:
	body = get_parent() as PhysicsBody3D
	if body == null:
		push_warning("Hackable expects a PhysicsBody3D parent; got %s" % str(get_parent()))
		return
	body.add_to_group("hackable")
	body.set_meta("hackable", self)


func accepts_adjective(id: String) -> bool:
	return accepts.is_empty() or id in accepts


## Toggle the aimed-at glow (HackManager drives this as the crosshair moves over hackables).
## A translucent emissive shell around the prop -- size-independent, non-destructive (it
## doesn't touch the host's own material), built lazily the first time it's needed.
func set_highlighted(on: bool) -> void:
	highlighted = on
	if body == null:
		return
	if on and _glow == null:
		_glow = _make_glow()
		body.add_child(_glow)
	if _glow != null:
		_glow.visible = on


func _make_glow() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.95
	sphere.height = 1.9
	m.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.9, 1.0, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	return m
