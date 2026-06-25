extends Node
## Diagnostic (not a pass/fail test): dump the archetype + footprint the generator
## actually picks for each room, in both modes, across a few run seeds. Replicates
## build_room's exact pick order (seed rng -> _pick_archetype -> _pick_footprint) so
## the printout matches a real build without paying for the navmesh bakes.
## Run: godot --headless --path . res://tools/layout_diag.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	get_tree().quit(0)


func _shape(fp: Dictionary) -> String:
	var half: Vector2 = fp.half
	if fp.get("notch", Vector2.ZERO) != Vector2.ZERO:
		return "L-SHAPE  (bbox %.0fx%.0f, notch %.0fx%.0f)" % [half.x * 2, half.y * 2,
				fp.notch.x, fp.notch.y]
	if is_equal_approx(half.x, half.y):
		return "SQUARE   %.0fx%.0f" % [half.x * 2, half.y * 2]
	return "RECT     %.0fx%.0f" % [half.x * 2, half.y * 2]


func _run() -> void:
	var main: Node = (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 6:
		await get_tree().process_frame
	var builder: Node = main.get_node("RoomBuilder")

	for mode in [RunManager.RunMode.ENDLESS, RunManager.RunMode.CAMPAIGN]:
		RunManager.run_mode = mode
		print("\n========== MODE: ", RunManager.RunMode.keys()[mode], " ==========")
		print("(room 1 is always the authored 42x42 arena; the builder owns rooms 2+)")
		for run_seed in [111, 222, 333]:
			RunManager.run_seed = run_seed
			print("  --- run_seed %d ---" % run_seed)
			for room in range(2, 13):
				var profile: Dictionary = {}
				if mode == RunManager.RunMode.CAMPAIGN:
					profile = LayerCatalog.profile_for_room(room)
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([RunManager.run_seed, room])
				var arch: Dictionary = builder._pick_archetype(room, rng, profile)
				var fp: Dictionary
				if bool(arch.get("milestone", false)):
					fp = {"half": builder.MILESTONE_FOOTPRINT, "notch": Vector2.ZERO}
				else:
					fp = builder._pick_footprint(rng, profile)
				var tag := ""
				if mode == RunManager.RunMode.CAMPAIGN:
					tag = "%s s%d  " % [profile.get("tag", "?"),
							LayerCatalog.room_in_layer_for_room(room)]
				print("    room %2d  %-9s%-16s %s" % [room, tag, arch.id, _shape(fp)])
