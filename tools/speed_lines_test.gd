extends Node
## Headless functional test for the speed-line / wind overlay (SPEED_LINES_OK).
## Run: godot --headless --path . res://tools/speed_lines_test.tscn
##
## The shader LOOK can't be verified headless (shaders don't compile -- eyeballed
## via tools/speed_lines_preview.tscn), but the speed -> intensity driver can, the
## glitch_smoke way. Pure: the smoothstep speed curve. Scene: the live player.tscn
## carries a SpeedLines child that built its CanvasLayer + ColorRect + shader
## material; driving its tick() with the player's `velocity` ramps the shader
## `intensity` uniform up when fast and decays it when slow / dead / paused.

const PLAYER := preload("res://scenes/player/player.tscn")
const SHADER := preload("res://shaders/speed_lines.gdshader")

var fails: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	if fails.is_empty():
		print("SPEED_LINES_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("SPEED_LINES_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _run() -> void:
	# ---------------------------------------------------------------- pure: curve
	var player := PLAYER.instantiate()
	player.set_physics_process(false)
	player.set_process(false)
	add_child(player)
	await get_tree().process_frame

	var sl := player.get_node("SpeedLines") as SpeedLines
	_check(sl != null, "player.tscn should carry a SpeedLines child")
	if sl == null:
		return
	sl.set_process(false)  # drive tick() manually for determinism

	# Below the start threshold: nothing. At/above full: maxed. Midpoint ~0.5.
	_check(is_zero_approx(sl.compute_target(sl.speed_start - 2.0)),
			"speed below speed_start should map to 0 intensity")
	_check(is_zero_approx(sl.compute_target(0.0)), "a standstill should map to 0 intensity")
	_check(absf(sl.compute_target(sl.speed_full + 5.0) - 1.0) < 0.001,
			"speed past speed_full should map to full intensity")
	var mid := (sl.speed_start + sl.speed_full) * 0.5
	_check(absf(sl.compute_target(mid) - 0.5) < 0.05, "the midpoint should read ~0.5")
	# Monotonic non-decreasing across the ramp.
	var prev := -1.0
	var monotonic := true
	for i in 12:
		var s := sl.speed_start + (sl.speed_full - sl.speed_start) * (float(i) / 11.0)
		var v := sl.compute_target(s)
		if v < prev - 0.0001:
			monotonic = false
		prev = v
	_check(monotonic, "the speed curve should be monotonic non-decreasing")

	# ---------------------------------------------------------------- overlay built
	_check(sl._rect != null and sl._rect.material is ShaderMaterial,
			"SpeedLines should build a ColorRect with a ShaderMaterial")
	var mat := sl._rect.material as ShaderMaterial
	_check(mat != null and mat.shader == SHADER, "the overlay should use the speed_lines shader")
	_check(sl.current_intensity() == 0.0 and float(mat.get_shader_parameter("intensity")) == 0.0,
			"intensity should start at 0")

	# ---------------------------------------------------------------- ramp up fast
	player.is_dead = false
	player.velocity = Vector3(20.0, 0.0, 0.0)  # well past speed_full -> target 1.0

	# One small tick from rest: rises off 0 but does NOT snap straight to the target.
	sl.tick(0.05)
	var after_one := sl.current_intensity()
	_check(after_one > 0.0, "a fast tick should raise intensity off 0")
	_check(after_one < 0.95, "intensity should ease in, not snap to full in one tick")
	_check(absf(float(mat.get_shader_parameter("intensity")) - after_one) < 0.0001,
			"the shader uniform should track the live intensity")

	# Several ticks -> approaches full.
	for i in 30:
		sl.tick(0.05)
	_check(sl.current_intensity() > 0.9, "sustained high speed should drive intensity near full")

	# ---------------------------------------------------------------- decay slow
	player.velocity = Vector3(2.0, 0.0, 0.0)  # below speed_start -> target 0
	for i in 30:
		sl.tick(0.05)
	_check(sl.current_intensity() < 0.05, "dropping below speed_start should decay the effect out")

	# ---------------------------------------------------------------- dead forces off
	player.velocity = Vector3(20.0, 0.0, 0.0)
	for i in 6:
		sl.tick(0.05)
	_check(sl.current_intensity() > 0.1, "fast again should ramp it back up")
	player.is_dead = true
	for i in 30:
		sl.tick(0.05)
	_check(sl.current_intensity() < 0.05, "death should force the effect off even at speed")
