extends Node3D
## Main scene driver: bakes the navmesh at runtime (CSG geometry needs a
## frame to build its colliders), spawns enemies, and runs the win/lose flow.
## Win: all enemies down. Lose: out of lives.

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const MAX_LIVES := 3
const RESPAWN_SECONDS := 3.0

var lives := MAX_LIVES
var enemies_remaining := 0
var game_over := false

@onready var nav_region: NavigationRegion3D = $NavRegion
@onready var player: Player = $Player
@onready var player_spawn: Marker3D = $PlayerSpawn


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	# Give CSG nodes a couple of physics frames to build collision, then bake.
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav_region.bake_navigation_mesh()
	await nav_region.bake_finished
	print("[GameManager] navmesh polygons: ",
			nav_region.navigation_mesh.get_polygon_count())
	_spawn_enemies()


func _unhandled_input(event: InputEvent) -> void:
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _spawn_enemies() -> void:
	var index := 0
	for marker in get_tree().get_nodes_in_group("enemy_spawn"):
		index += 1
		var enemy := ENEMY_SCENE.instantiate() as EnemyAI
		enemy.name = "Enemy %d" % index
		add_child(enemy)
		enemy.global_position = (marker as Node3D).global_position
		enemy.enemy_died.connect(_on_enemy_died)
	enemies_remaining = index
	GameEvents.enemies_remaining_changed.emit(enemies_remaining)
	# TODO: wave spawning / reinforcements after the first squad is cleared.


func _on_enemy_died(_enemy: EnemyAI) -> void:
	enemies_remaining -= 1
	GameEvents.enemies_remaining_changed.emit(enemies_remaining)
	if enemies_remaining <= 0 and not game_over and not player.is_dead:
		game_over = true
		GameEvents.game_won.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_died() -> void:
	if game_over:
		return
	lives -= 1
	if lives <= 0:
		game_over = true
		GameEvents.game_lost.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	if game_over:
		return
	player.respawn_at(player_spawn.global_position)
