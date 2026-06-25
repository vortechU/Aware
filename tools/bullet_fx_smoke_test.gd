extends Node
## Headless functional test for the BulletFX autoload (bullet tracers + impact
## decals). Run: godot --headless --path . res://tools/bullet_fx_smoke_test.tscn
##
## BulletFX parents its cosmetic nodes to the current scene (this test) and groups
## them, so we drive it purely through the GameEvents bus and count the spawned
## nodes -- no rendering needed, so it verifies the real behaviour headless:
##   1. bullet_tracer spawns one tracer; a sub-muzzle-length tracer is skipped.
##   2. bullet_impact spawns one decal.
##   3. Past MAX_DECALS, the oldest decals are recycled (count caps out).

var fails: Array[String] = []


func _ready() -> void:
	await _run()
	if fails.is_empty():
		print("BULLET_FX_SMOKE_OK")
		get_tree().quit(0)
	else:
		for f in fails:
			print("BULLET_FX_SMOKE_FAIL: ", f)
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)


func _tracers() -> int:
	return get_tree().get_nodes_in_group(BulletFX.TRACER_GROUP).size()


func _decals() -> int:
	return get_tree().get_nodes_in_group(BulletFX.DECAL_GROUP).size()


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _run() -> void:
	# Signal handlers run synchronously, so spawned nodes exist immediately.
	# 1. A normal tracer spawns.
	GameEvents.bullet_tracer.emit(Vector3.ZERO, Vector3(0, 0, -12))
	_check(_tracers() == 1, "tracer not spawned (got %d)" % _tracers())

	# A near-zero-length tracer (hit on the muzzle) is skipped.
	GameEvents.bullet_tracer.emit(Vector3.ZERO, Vector3(0, 0, -0.1))
	_check(_tracers() == 1, "sub-length tracer should be skipped (got %d)" % _tracers())

	# 2. An impact spawns a decal.
	GameEvents.bullet_impact.emit(Vector3(0, 1, -2), Vector3(0, 0, 1))
	_check(_decals() == 1, "decal not spawned (got %d)" % _decals())

	# 3. Blast well past the cap; oldest decals are recycled.
	for i in BulletFX.MAX_DECALS + 20:
		GameEvents.bullet_impact.emit(Vector3(float(i) * 0.5, 1, -2), Vector3(0, 0, 1))
	# queue_free is deferred, so let the recycled decals actually leave the tree.
	await _settle(3)
	var count := _decals()
	_check(count == BulletFX.MAX_DECALS,
			"decals should cap at %d, got %d" % [BulletFX.MAX_DECALS, count])
