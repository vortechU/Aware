extends Node3D
## Pre-run hub as an actual 3D space: you spawn in as the first-person player,
## walk up to the upgrade pedestals to spend Cores, then step into the green
## portal to start the run (or the amber door to return to the menu). The
## MetaProgression autoload owns the Cores/upgrade data and persistence; this
## script only drives the worldspace interaction and the heads-up display.
##
## Every interactable is an Area3D under "Stations": the five buy pedestals are
## named after their MetaProgression upgrade ids, plus "StartPortal" and
## "MenuDoor". Standing in a zone shows a prompt; pressing "interact" (E) acts
## on the nearest one. No edits to player.gd / weapon_manager.gd — the player's
## gun is silenced in the hub via the same external process-toggle pattern
## RunDirector uses for room transitions.

const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _active: Array[Area3D] = []  # zones the player is currently standing in
var _labels := {}                # Area3D -> its Label3D
## The run mode the player will launch into. Defaults to the narrative CAMPAIGN
## (the GDD's escape through the layers); the ModeToggle station switches it to the
## legacy ENDLESS run. Applied to RunManager when the toggle flips and at start_run
## (so an untouched lobby still launches CAMPAIGN). Never set in _ready, so tests
## that drive RunManager directly keep its ENDLESS default.
var _selected_mode := RunManager.RunMode.CAMPAIGN

@onready var player: Player = $Player
@onready var stations_root: Node3D = $Stations
@onready var cores_label: Label = $LobbyHUD/CoresLabel
@onready var prompt_label: Label = $LobbyHUD/Prompt


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # first-person hub navigation
	# Re-entering the lobby means configuring a fresh run: disarm until the
	# player commits at the portal, so the hub player itself stays vanilla.
	MetaProgression.run_bonuses_armed = false
	MetaProgression.cores_changed.connect(_on_cores_changed)
	_silence_weapon()
	_build_mode_station()  # added before the wiring loop so it gets wired like the rest
	_build_hack_stations()  # adjective-unlock pedestals, same code-built convention
	for child in stations_root.get_children():
		var area := child as Area3D
		if area == null:
			continue
		_labels[area] = area.get_node("Label3D")
		area.body_entered.connect(_on_zone_entered.bind(area))
		area.body_exited.connect(_on_zone_exited.bind(area))
	_refresh_all()


## Stop the weapon from firing / animating in the peaceful hub without touching
## weapon_manager.gd (same trick as RunDirector._set_player_frozen).
func _silence_weapon() -> void:
	var weapon_manager: Node = player.get_node("Head/Bob/Recoil/Camera/WeaponManager")
	weapon_manager.set_process(false)
	weapon_manager.set_process_unhandled_input(false)


## Build the run-mode selector station in code (matching the project's
## self-building convention) so the scene file needs no edit. An Area3D zone +
## a small pylon + a Label3D, set beside the start portal; the _ready wiring loop
## then hooks its body_entered/exited and label like the authored stations.
func _build_mode_station() -> void:
	var area := Area3D.new()
	area.name = "ModeToggle"
	area.collision_layer = 0
	area.collision_mask = 2  # detect the player (layer 2), like the other stations
	stations_root.add_child(area)
	area.position = Vector3(4.0, 0.0, -9.0)  # right of the StartPortal, on the way in

	var zone := CollisionShape3D.new()
	zone.name = "Zone"
	var box := BoxShape3D.new()
	box.size = Vector3(3.5, 3.0, 3.5)
	zone.shape = box
	zone.position = Vector3(0.0, 1.2, 0.0)
	area.add_child(zone)

	var pylon := MeshInstance3D.new()
	var pylon_mesh := BoxMesh.new()
	pylon_mesh.size = Vector3(1.0, 2.0, 1.0)
	pylon.mesh = pylon_mesh
	pylon.position = Vector3(0.0, 1.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.4
	pylon.material_override = mat
	area.add_child(pylon)

	var label := Label3D.new()
	label.name = "Label3D"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 8
	label.position = Vector3(0.0, 2.6, 0.0)
	area.add_child(label)


## Buy pedestals for the environment-hacking adjectives (MetaProgression `hack_*`
## one-time unlocks). Built in code like the ModeToggle, before the _ready wiring loop,
## so each gets body_entered/exited + its label hooked like the authored stations; the
## generic `_is_upgrade` / `buy` path then handles them with no extra interaction code.
func _build_hack_stations() -> void:
	_build_buy_pedestal("hack_heavy", Vector3(-3.0, 0.0, 4.0), Color(0.3, 0.8, 1.0))
	_build_buy_pedestal("hack_shocking", Vector3(3.0, 0.0, 4.0), Color(1.0, 0.9, 0.3))


func _build_buy_pedestal(id: String, pos: Vector3, color: Color) -> void:
	var area := Area3D.new()
	area.name = id
	area.collision_layer = 0
	area.collision_mask = 2  # detect the player (layer 2), like the other stations
	stations_root.add_child(area)
	area.position = pos

	var zone := CollisionShape3D.new()
	zone.name = "Zone"
	var box := BoxShape3D.new()
	box.size = Vector3(3.5, 3.0, 3.5)
	zone.shape = box
	zone.position = Vector3(0.0, 1.2, 0.0)
	area.add_child(zone)

	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := BoxMesh.new()
	pedestal_mesh.size = Vector3(1.2, 1.0, 1.2)
	pedestal.mesh = pedestal_mesh
	pedestal.position = Vector3(0.0, 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	pedestal.material_override = mat
	area.add_child(pedestal)

	var label := Label3D.new()
	label.name = "Label3D"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.position = Vector3(0.0, 2.4, 0.0)
	area.add_child(label)


func _mode_name() -> String:
	return "ESCAPE" if _selected_mode == RunManager.RunMode.CAMPAIGN else "ENDLESS"


## Flip the selected run mode and push it live to RunManager. Only ever reached by
## interacting with the ModeToggle station, so a lobby that is only inspected (the
## smoke test) never changes RunManager's mode.
func _toggle_mode() -> void:
	_selected_mode = RunManager.RunMode.ENDLESS \
			if _selected_mode == RunManager.RunMode.CAMPAIGN \
			else RunManager.RunMode.CAMPAIGN
	RunManager.selected_mode = _selected_mode
	_refresh_all()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		_interact()


# ---------------------------------------------------------------- zones

func _on_zone_entered(body: Node, area: Area3D) -> void:
	if body == player and not _active.has(area):
		_active.append(area)
		_update_prompt()


func _on_zone_exited(body: Node, area: Area3D) -> void:
	if body == player:
		_active.erase(area)
		_update_prompt()


## Nearest zone the player is currently inside, or null.
func _current_station() -> Area3D:
	var best: Area3D = null
	var best_dist := INF
	for area in _active:
		var d := player.global_position.distance_squared_to(area.global_position)
		if d < best_dist:
			best_dist = d
			best = area
	return best


func _is_upgrade(id: String) -> bool:
	return not MetaProgression.upgrade_def(id).is_empty()


# ---------------------------------------------------------------- interaction

func _interact() -> void:
	var station := _current_station()
	if station == null:
		return
	var id := String(station.name)
	if id == "StartPortal":
		start_run()
	elif id == "ModeToggle":
		_toggle_mode()
	elif id == "MenuDoor":
		get_tree().change_scene_to_file(MENU_SCENE)
	elif _is_upgrade(id):
		MetaProgression.buy(id)  # emits cores_changed -> _refresh_all on success
		_refresh_all()           # also re-sync after a failed (too-poor) buy


## Commit to a run: lock in the chosen mode (so an untouched lobby still launches
## the CAMPAIGN default), arm the permanent bonuses for the Player that spawns in
## main.tscn, then load it. Kept public so the transition harness can drive it.
func start_run() -> void:
	RunManager.selected_mode = _selected_mode
	MetaProgression.arm_run_bonuses()
	get_tree().change_scene_to_file(GAME_SCENE)


# ---------------------------------------------------------------- display

func _on_cores_changed(_total: int) -> void:
	_refresh_all()


func _refresh_all() -> void:
	cores_label.text = "CORES: %d" % MetaProgression.cores
	for area in _labels:
		_refresh_station(area as Area3D)
	_update_prompt()


func _refresh_station(station: Area3D) -> void:
	var label := _labels.get(station) as Label3D
	if label == null:
		return
	var id := String(station.name)
	if id == "StartPortal" or id == "MenuDoor":
		return  # static labels authored in the scene
	if id == "ModeToggle":
		label.text = "RUN MODE\n%s" % _mode_name()
		return
	if not _is_upgrade(id):
		return
	var def := MetaProgression.upgrade_def(id)
	var level: int = MetaProgression.level_of(id)
	var cost: int = MetaProgression.next_cost(id)
	var cost_line := "MAXED" if cost < 0 else "%d Cores" % cost
	label.text = "%s\nLv %d / %d\n%s" % [def.title, level, int(def.max_level), cost_line]


func _update_prompt() -> void:
	var station := _current_station()
	if station == null:
		prompt_label.visible = false
		return
	prompt_label.visible = true
	var id := String(station.name)
	if id == "StartPortal":
		prompt_label.text = "[E]  Begin the run  (%s)" % _mode_name()
	elif id == "ModeToggle":
		prompt_label.text = "[E]  Run mode: %s  -  switch" % _mode_name()
	elif id == "MenuDoor":
		prompt_label.text = "[E]  Back to main menu"
	elif _is_upgrade(id):
		var def := MetaProgression.upgrade_def(id)
		var cost: int = MetaProgression.next_cost(id)
		if cost < 0:
			prompt_label.text = "%s  —  fully upgraded" % def.title
		elif MetaProgression.cores < cost:
			prompt_label.text = "Need %d Cores for %s" % [cost, def.title]
		else:
			prompt_label.text = "[E]  Buy %s  (%d Cores)" % [def.title, cost]
