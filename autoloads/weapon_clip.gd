extends Node
## Stops the first-person weapon from poking through walls and other world
## geometry when the player stands close ("gun clips through the wall").
##
## Approach: render the viewmodel ON TOP of the world instead of pushing it back
## toward the eye. The gun simply ignores walls -- it never moves -- which is the
## standard FPS technique and what reads correctly to the player. (The previous
## version raycast every frame and slid the model roots back; that retraction
## looked wrong, so it was replaced.)
##
## A sibling observer in the SettingsManager / AudioManager / ToonApplicator
## mould: it never touches weapon_manager.gd, player.tscn or toon_applicator.gd.
## It catches each WeaponManager through get_tree().node_added and, once, flips
## the viewmodel meshes to draw without a depth test:
##   - Body + barrel are cel-shaded by ToonApplicator (a toon ShaderMaterial), so
##     we swap their shader to toon_viewmodel.gdshader -- the same cel look with
##     `depth_test_disabled` baked into its render_mode. The material's uniforms
##     and its outline next_pass carry over untouched.
##   - The muzzle flash keeps its unshaded StandardMaterial3D billboard; we just
##     set no_depth_test on it so the flash draws over walls too.
##   - Fallback: if cel-shading ever leaves a body/barrel on a StandardMaterial3D,
##     no_depth_test handles it the same way.
##
## Runs AFTER ToonApplicator (autoload order: ToonApplicator 6th, WeaponClip 7th),
## so by the time our deferred adopt fires the toon material is already in place.
## Purely a material setup -- no per-frame work, no rendering needed -- so it stays
## valid under --headless (the smoke harness checks the shader/flag assignment).

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const VIEWMODEL_SHADER: Shader = preload("res://shaders/toon_viewmodel.gdshader")


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is WeaponManager:
		# Viewmodels are built in WeaponManager._ready and cel-shaded by
		# ToonApplicator's own deferred pass; defer ours so both have run.
		_adopt.call_deferred(node)


func _adopt(wm: Node) -> void:
	if not is_instance_valid(wm):
		return
	# Each direct child of the manager is a weapon model root. Its body + barrel
	# are direct MeshInstance3D children; the muzzle flash lives one level deeper
	# under a "MuzzleFlash" node.
	for model in wm.get_children():
		if not (model is Node3D):
			continue
		for child in (model as Node3D).get_children():
			if child is MeshInstance3D:
				_render_on_top(child as MeshInstance3D)
			elif child.name == "MuzzleFlash":
				for sub in child.get_children():
					if sub is MeshInstance3D:
						_disable_depth_test(sub as MeshInstance3D)


## Body / barrel: swap the cel fill shader for its depth-test-disabled twin, or
## fall back to no_depth_test on a plain material. Idempotent.
func _render_on_top(mesh: MeshInstance3D) -> void:
	var mat: Material = mesh.material_override
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader == TOON_SHADER:
			sm.shader = VIEWMODEL_SHADER  # uniforms + outline next_pass preserved
	elif mat is StandardMaterial3D:
		(mat as StandardMaterial3D).no_depth_test = true


## Muzzle flash: keep the unshaded billboard, just let it draw over walls.
func _disable_depth_test(mesh: MeshInstance3D) -> void:
	var mat: Material = mesh.material_override
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).no_depth_test = true
