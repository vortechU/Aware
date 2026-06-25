extends Node
## Headless verification harness. Loads every script (and optionally scenes +
## resources) so compile errors surface with autoloads registered, then quits
## with a non-zero exit code on failure.
## Run: godot --headless res://tools/script_check.tscn -- scripts-only

func _ready() -> void:
	var scripts_only := OS.get_cmdline_user_args().has("scripts-only")
	var failures: Array[String] = []

	var scripts: Array[String] = []
	_scan("res://autoloads", scripts, ".gd")
	_scan("res://scripts", scripts, ".gd")
	for p in scripts:
		var s: Resource = load(p)
		if s == null or not (s as GDScript).can_instantiate():
			failures.append(p)

	if not scripts_only:
		var others: Array[String] = []
		_scan("res://scenes", others, ".tscn")
		_scan("res://data", others, ".tres")
		for p in others:
			if load(p) == null:
				failures.append(p)

	if failures.is_empty():
		print("CHECK_OK")
		get_tree().quit(0)
	else:
		for f in failures:
			print("CHECK_FAIL ", f)
		get_tree().quit(1)


func _scan(dir_path: String, out: Array[String], ext: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir():
			if not f.begins_with("."):
				_scan(full, out, ext)
		elif f.ends_with(ext):
			out.append(full)
		f = dir.get_next()
