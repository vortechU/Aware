extends Node3D
## Throwaway visual harness (NOT shipped game code): renders a normal + an elite
## enemy so the cel look + inverted-hull outline can be eyeballed without playing
## through to a milestone room. Must run NON-headless (real D3D12) so the toon
## shader actually compiles:
##   Godot.exe --path <proj> res://tools/toon_preview.tscn
## Saves res://tools/toon_preview_out.png, then quits.

const ENEMY := preload("res://scenes/enemies/enemy.tscn")
const PICKUP := preload("res://scenes/pickups/pickup.tscn")


func _ready() -> void:
	# Flat-ish ambient so the darkest band reads as shadow, not pure black.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.23)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.43, 0.52)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -50.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.45, 3.4)
	cam.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()

	_add_enemy(Vector3(-0.85, 0.0, 0.0), false)
	_add_enemy(Vector3(0.95, 0.0, 0.0), true)

	# Ammo / health / armor crates in the foreground.
	_add_pickup(Pickup.Type.AMMO, Vector3(-1.25, 0.0, 1.5))
	_add_pickup(Pickup.Type.HEALTH, Vector3(0.0, 0.0, 1.6))
	_add_pickup(Pickup.Type.ARMOR, Vector3(1.25, 0.0, 1.5))

	# World geometry: banding-only (no outline). A floor, two CSG arena props and
	# one procedural-style StaticBody box, to show the calm world the outlined
	# characters/pickups read against.
	_add_csg_box(Vector3(30.0, 0.5, 30.0), Vector3(0.0, -0.25, -5.0), Color(0.30, 0.33, 0.38))
	_add_csg_box(Vector3(1.2, 4.0, 1.2), Vector3(-2.7, 2.0, -2.6), Color(0.40, 0.42, 0.46))
	_add_csg_box(Vector3(1.5, 1.5, 1.5), Vector3(2.5, 0.75, -2.3), Color(0.52, 0.38, 0.24))
	_add_static_box(Vector3(1.5, 1.5, 1.5), Vector3(0.2, 0.75, -3.3), Color(0.40, 0.42, 0.46))

	# Let the shader compile and at least one frame draw before grabbing pixels.
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/toon_preview_out.png")
	img.save_png(path)
	print("TOON_PREVIEW_SAVED ", path)
	get_tree().quit()


func _add_enemy(pos: Vector3, elite: bool) -> void:
	var e := ENEMY.instantiate()
	e.process_mode = Node.PROCESS_MODE_DISABLED  # no AI / gravity in the preview
	e.position = pos
	if elite:
		# Mirror RunDirector's elite outfit (set BEFORE add_child, like it does)
		# so ToonApplicator copies the crimson/gold glow into the toon material.
		(e.get_node("Visual") as Node3D).scale = Vector3(1.25, 1.0, 1.25)
		_emissive(e.get_node("Visual/Body"), Color(0.32, 0.05, 0.09), Color(0.8, 0.1, 0.1), 0.35)
		_emissive(e.get_node("Visual/Head"), Color(0.95, 0.78, 0.3), Color(1.0, 0.75, 0.2), 0.6)
	add_child(e)  # ToonApplicator toonifies on node_added


func _add_pickup(t: int, pos: Vector3) -> void:
	var p := PICKUP.instantiate()
	p.type = t
	p.position = pos
	add_child(p)  # ToonApplicator toonifies on node_added (deferred)


func _add_csg_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	b.material = m
	add_child(b)  # ToonApplicator banding-only on CSGShape3D node_added


func _add_static_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	body.add_child(mi)
	add_child(body)  # ToonApplicator banding-only on StaticBody3D node_added
	body.position = pos


func _emissive(mi: MeshInstance3D, albedo: Color, em: Color, energy: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = em
	m.emission_energy_multiplier = energy
	mi.material_override = m
