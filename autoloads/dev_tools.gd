extends Node
## Developer / playtest helpers -- a debug observer in the SettingsManager /
## ToonApplicator mould. Build-alongside: it NEVER edits player.gd, enemy_ai.gd or
## run_director.gd. It only reads/writes their public state from the outside and
## routes enemy kills through the normal HitboxComponent, so the room-clear / exit-
## gate flow fires exactly as in real play.
##
## Gameplay keys (no effect in menus / when no player exists):
##   F1 - toggle GOD MODE (no death; max health/armor raised so nothing can kill)
##   F2 - KILL ALL enemies in the current room (clears it -> the exit gate appears)
##   F3 - REFILL health, armor + ammo
##   F5 / F6 - JUMP to the next / previous room (rebuilds it via the real pipeline)
##   F7 - JUMP to the next narrative LAYER's first room (cycles; e.g. Heap -> Stack)
##
## A small CanvasLayer shows the binds + god state during gameplay. The whole tool
## is gated to debug builds (OS.is_debug_build()), so it is inert in a release export.

const GOD_POOL := 1.0e9  # absurd health/armor headroom so nothing one-shots the player
const KILL_DAMAGE := 1.0e6

var enabled := false
var god_mode := false

var _player: Node = null
var _orig_max_health := 0.0
var _orig_max_armor := 0.0
var _label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = OS.is_debug_build()  # never active in a release export
	if not enabled:
		return
	_build_overlay()
	_refresh_label()


func _input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_toggle_god()
		KEY_F2:
			_kill_all_enemies()
		KEY_F3:
			_refill()
		KEY_F5:
			_jump_rooms(1)
		KEY_F6:
			_jump_rooms(-1)
		KEY_F7:
			_jump_next_layer()


func _process(_delta: float) -> void:
	if not enabled:
		return
	var player := _get_player()
	if _label != null:
		_label.visible = player != null  # only show the overlay in gameplay
	# Re-arm god on a fresh player (a new run reloads main.tscn with a new Player).
	if god_mode and player != null and float(player.get("max_health")) < GOD_POOL:
		_apply_god(player)


# ---------------------------------------------------------------- actions

func _toggle_god() -> void:
	god_mode = not god_mode
	var player := _get_player()
	if player != null:
		if god_mode:
			_apply_god(player)
		else:
			_remove_god(player)
	_refresh_label()


## Raise max health/armor to an absurd pool and top them off, so no single hit can
## drop the player to 0 (take_damage never calls _die). Captures the real maxima once
## so _remove_god can restore them. Purely external -- player.gd is untouched.
func _apply_god(player: Node) -> void:
	if _orig_max_health <= 0.0:
		_orig_max_health = float(player.get("max_health"))
		_orig_max_armor = float(player.get("max_armor"))
	player.set("is_dead", false)
	player.set("max_health", GOD_POOL)
	player.set("max_armor", GOD_POOL)
	player.set("health", GOD_POOL)
	player.set("armor", GOD_POOL)
	if player.has_method("_emit_vitals"):
		player.call("_emit_vitals")


func _remove_god(player: Node) -> void:
	if _orig_max_health <= 0.0:
		return
	player.set("max_health", _orig_max_health)
	player.set("max_armor", _orig_max_armor)
	player.set("health", _orig_max_health)
	player.set("armor", minf(float(player.get("armor")), _orig_max_armor))
	if player.has_method("_emit_vitals"):
		player.call("_emit_vitals")


## Lethal hit on every live enemy via its BodyHitbox -- the same path the smoke
## tests use -- so the normal death (ragdoll, enemy_died, room-clear) all run.
func _kill_all_enemies() -> int:
	var killed := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if int(enemy.get("state")) == 7:  # EnemyAI.State.DEAD
			continue
		var hitbox := (enemy as Node).get_node_or_null("BodyHitbox")
		if hitbox != null and hitbox.has_method("take_hit"):
			hitbox.call("take_hit", KILL_DAMAGE, Vector3.ZERO)
			killed += 1
	_flash("KILLED %d ENEMIES" % killed)
	return killed


func _refill() -> void:
	var player := _get_player()
	if player == null:
		return
	if player.has_method("heal"):
		player.call("heal", GOD_POOL)
	if player.has_method("add_armor"):
		player.call("add_armor", GOD_POOL)
	var wm := player.find_child("WeaponManager", true, false)
	if wm != null and wm.has_method("reset_loadout"):
		wm.call("reset_loadout")
	_flash("REFILLED HEALTH / ARMOR / AMMO")


## Warp `delta` rooms from the current one (clamped to room 1+), rebuilding the
## target room through RunDirector's real transition pipeline.
func _jump_rooms(delta: int) -> void:
	_do_jump(maxi(1, RunManager.current_room + delta))


## Warp to the first room of the NEXT narrative layer (cycles back to layer 1 past
## the last). The headline level-testing key: drop straight into the Stack from the Heap.
func _jump_next_layer() -> void:
	var starts := _layer_start_rooms()
	if starts.is_empty():
		return
	var current: int = RunManager.current_room
	var target: int = starts[0]  # wrap target if none lie ahead
	for start in starts:
		if start > current:
			target = start
			break
	_do_jump(target)


## First global room of each defined layer, e.g. [1, 7] for Heap + Stack.
func _layer_start_rooms() -> Array:
	var starts: Array = []
	var room := 1
	for layer in LayerCatalog.LAYERS:
		starts.append(room)
		room += int(layer.room_count)
	return starts


func _do_jump(target: int) -> void:
	if not RunManager.run_active:
		_flash("JUMP NEEDS AN ACTIVE RUN")
		return
	var director := _get_run_director()
	if director == null or not director.has_method("dev_jump_to_room"):
		_flash("NO RUN DIRECTOR TO JUMP WITH")
		return
	director.call("dev_jump_to_room", target)
	_flash("JUMP -> ROOM %d%s" % [target, _room_tag(target)])


## " (HEAP s2)"-style suffix for the jump confirmation, CAMPAIGN only.
func _room_tag(room: int) -> String:
	if RunManager.run_mode != RunManager.RunMode.CAMPAIGN:
		return ""
	var profile: Dictionary = LayerCatalog.profile_for_room(room)
	return "  (%s s%d)" % [profile.get("tag", "?"), LayerCatalog.room_in_layer_for_room(room)]


func _get_run_director() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("RunDirector")


# ---------------------------------------------------------------- helpers

func _get_player() -> Node:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player")
	return _player


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DevOverlay"
	layer.layer = 64  # above the HUD
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12.0, 70.0)  # under the controls hint
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = "[DEV]  F1 god: %s   F2 kill all   F3 refill\n       F5 +room   F6 -room   F7 next layer" \
			% ("ON" if god_mode else "off")
	_label.modulate = Color(0.4, 1.0, 0.5) if god_mode else Color(0.82, 0.82, 0.88)


## Briefly show an action confirmation, then revert to the bind list.
func _flash(message: String) -> void:
	if _label == null:
		return
	_label.text = "[DEV]  " + message
	_label.modulate = Color(1.0, 0.95, 0.4)
	await get_tree().create_timer(1.3).timeout
	_refresh_label()
