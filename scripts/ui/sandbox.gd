extends Node3D
## A free-form SANDBOX / test map. You spawn in as the first-person player in a plain
## walled arena to try new mechanics in a real 3D space -- hackable props to inject
## adjectives into, target dummies to crush and shoot, and room to move. Reached from
## the main menu's TEST MAP button; NOT part of the run / campaign flow.
##
## Because the progression systems that normally hand out powers (in-run cards, lobby
## Cores) aren't part of this scene, the sandbox just KITS the player on spawn: every
## hacking adjective unlocked + both abilities granted, so everything is immediately
## testable. The world (floor, walls, props, dummies, exit door) is built in code, the
## project's self-building convention -- the .tscn only holds the player, lights, HUD
## and hint labels.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DOOR_POS := Vector3(0.0, 0.0, 12.0)
const DOOR_RANGE := 3.0

@onready var player: Player = $Player
@onready var prompt_label: Label = $SandboxHUD/Prompt

var _near_door := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_arena()
	_build_hackables()
	_build_door()
	_kit_player()  # the player's child managers ready before this parent, so it's safe


func _process(_delta: float) -> void:
	var near := player.global_position.distance_to(DOOR_POS) <= DOOR_RANGE
	if near != _near_door:
		_near_door = near
		prompt_label.visible = near
	if Input.is_action_just_pressed("interact") and _near_door:
		get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	# ESC frees / re-captures the cursor so you can alt-tab around while testing.
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				else Input.MOUSE_MODE_CAPTURED


## Hand the player a fully-kitted loadout so every new system is testable on spawn.
func _kit_player() -> void:
	var hack: HackManager = player.get_node_or_null("HackManager")
	if hack != null:
		for id in HackManager.CATALOG:
			hack.unlock(id)
	var ability: AbilityManager = player.get_node_or_null("AbilityManager")
	if ability != null:
		ability.grant("stack_smash")
		ability.grant("overclock")


# ---------------------------------------------------------------- world build

func _build_arena() -> void:
	var floor_mat := _flat_mat(Color(0.12, 0.13, 0.16))
	_add_static_box(Vector3(50, 1, 50), Vector3(0, -0.5, 0), floor_mat)
	var wall_mat := _flat_mat(Color(0.17, 0.18, 0.22))
	var h := 5.0
	_add_static_box(Vector3(50, h, 1), Vector3(0, h * 0.5, -25), wall_mat)
	_add_static_box(Vector3(50, h, 1), Vector3(0, h * 0.5, 25), wall_mat)
	_add_static_box(Vector3(1, h, 50), Vector3(-25, h * 0.5, 0), wall_mat)
	_add_static_box(Vector3(1, h, 50), Vector3(25, h * 0.5, 0), wall_mat)


## Three floating hackable cubes, each over a target dummy: aim at the glowing cube,
## press the hack key, and Heavy drops it to crush the dummy below. Plus two free-
## standing dummies to shoot at.
func _build_hackables() -> void:
	_add_hackable_cube(Vector3(-4, 2.6, -6))
	_add_hackable_cube(Vector3(0, 2.6, -8))
	_add_hackable_cube(Vector3(4, 2.6, -6))
	_add_dummy(Vector3(-4, 0.1, -6))
	_add_dummy(Vector3(0, 0.1, -8))
	_add_dummy(Vector3(4, 0.1, -6))
	_add_dummy(Vector3(-2, 0.1, -13))
	_add_dummy(Vector3(2, 0.1, -13))


func _build_door() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.7, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.6, 0.2)
	mat.emission_energy_multiplier = 1.6
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.4, 3.2, 0.3)
	door.mesh = dm
	door.material_override = mat
	door.position = DOOR_POS + Vector3(0, 1.6, 0)
	add_child(door)
	var label := Label3D.new()
	label.text = "MAIN MENU  [E]"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 44
	label.outline_size = 10
	label.modulate = Color(1, 0.8, 0.5)
	label.position = DOOR_POS + Vector3(0, 3.6, 0)
	add_child(label)


# ---------------------------------------------------------------- builders

func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _add_static_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # "world"
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)


## A frozen RigidBody3D on the world layer with a Hackable component -- reads as a
## floating prop until the player injects an adjective. Glows cyan so it reads as
## hackable. (Mask = world only, so a falling Heavy cube passes through dummies and
## the crush is resolved by proximity, not a physics bounce.)
func _add_hackable_cube(pos: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.freeze = true
	rb.mass = 8.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.2
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mesh.mesh = bm
	mesh.material_override = mat
	rb.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	col.shape = shape
	rb.add_child(col)
	var h := Hackable.new()
	h.name = "Hackable"
	rb.add_child(h)
	# Set the spawn transform BEFORE entering the tree: a frozen RigidBody3D ignores a
	# global_position written after add_child.
	rb.position = pos
	add_child(rb)


## A real enemy made inert (sight_range 0 + process off) so it stays put as a target
## dummy. take_hit still routes damage to its HealthComponent, so it can be crushed or
## shot to death (and ragdolls normally).
func _add_dummy(pos: Vector3) -> void:
	var enemy := (preload("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Node3D
	add_child(enemy)
	enemy.global_position = pos
	enemy.set("sight_range", 0.0)
	enemy.set_physics_process(false)
	enemy.set_process(false)
