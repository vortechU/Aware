class_name EnemyRig
extends Node3D
## A decorative, animated Kenney character grafted onto an enemy's `Visual` node by
## the CharacterApplicator autoload. BUILD-ALONGSIDE: enemy_ai.gd never references
## this; it reads the owning enemy's velocity from the OUTSIDE to pick idle vs run,
## and freezes its pose when the enemy dies.
##
## Tree shape (built by CharacterApplicator):
##   Visual/Rig (EnemyRig, this)   -- scaled/oriented to fit the ~1.8 m capsule
##     Model (characterMedium.fbx instance: Root/Skeleton3D/mesh)
##     AnimationPlayer              -- root_node -> Model, plays the grafted clips
##
## On death the existing ragdoll (`enemy_ai._spawn_ragdoll`) reparents the whole
## `Visual` -- this rig included -- onto a corpse RigidBody3D and tumbles it. We
## pause the AnimationPlayer on `enemy_died` so the rig tumbles as a frozen-pose
## corpse rather than a body still "idling" in mid-air.

const RUN_SPEED := 0.6   # m/s above which we switch idle -> run
const BLEND := 0.15      # crossfade time between locomotion clips
# Seat the gun in the right hand: an offset from the hand bone, in the enemy's
# local frame (so it reads aim-aligned, forward = -Z). Tuned via the preview.
const GUN_OFFSET := Vector3(0.04, -0.02, -0.16)

# Death "crumple": on death we blend key bones from the frozen pose toward a limp,
# collapsed pose while the existing corpse tumble carries the body -- a believable
# "goes slack and falls" without physics bodies (true ragdoll is blocked by the
# FBX's 1/100 import scale, which makes physics shapes sub-millimetre). Each entry
# is a bone-local euler offset (degrees), tuned via tools/char_ragdoll_preview.tscn.
const CRUMPLE_TIME := 0.5
const SLUMP := {
	"Spine": Vector3(35, 0, 0),
	"Chest": Vector3(22, 0, 0),
	"Neck": Vector3(35, 0, 0),
	"Head": Vector3(25, 0, 0),
	"LeftUpLeg": Vector3(55, 0, 8),
	"RightUpLeg": Vector3(55, 0, -8),
	"LeftLeg": Vector3(-65, 0, 0),
	"RightLeg": Vector3(-65, 0, 0),
	"LeftArm": Vector3(15, 0, 35),
	"RightArm": Vector3(15, 0, -35),
	"LeftForeArm": Vector3(45, 0, 0),
	"RightForeArm": Vector3(45, 0, 0),
}

var _anim: AnimationPlayer
var _enemy: Node3D       # the EnemyAI (CharacterBody3D); set at setup, valid as the husk
var _gun: Node3D         # the primitive Visual/Gun, KEPT for the gun-drop ragdoll
var _skel: Skeleton3D
var _hand_idx := -1
var _dead := false


## Wired by CharacterApplicator after the model + player are parented in.
func setup(anim: AnimationPlayer, enemy: Node3D, gun: Node3D, skel: Skeleton3D, hand_idx: int) -> void:
	_anim = anim
	_enemy = enemy
	_gun = gun
	_skel = skel
	_hand_idx = hand_idx
	if _enemy != null and _enemy.has_signal("enemy_died"):
		_enemy.enemy_died.connect(_on_enemy_died)
	if _anim != null and _anim.has_animation("idle"):
		_anim.play("idle")


func _process(_delta: float) -> void:
	if _dead or not is_instance_valid(_enemy):
		return
	_drive_locomotion()
	_drive_gun()


func _drive_locomotion() -> void:
	if _anim == null:
		return
	var speed := Vector2(_enemy.velocity.x, _enemy.velocity.z).length()
	var want := "run" if speed > RUN_SPEED else "idle"
	if _anim.current_animation != want and _anim.has_animation(want):
		_anim.play(want, BLEND)


## Keep the (still Visual-parented, drop-ready) gun glued to the hand bone, aimed
## along the enemy's facing. We DON'T reparent it under a BoneAttachment3D so the
## death ragdoll's `_drop_gun` still finds `Visual/Gun` and detaches it normally.
func _drive_gun() -> void:
	if _gun == null or not is_instance_valid(_gun) or _skel == null or _hand_idx < 0:
		return
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_hand_idx)
	var aim := (_enemy as Node3D).global_transform.basis
	_gun.global_transform = Transform3D(aim, hand.origin + aim * GUN_OFFSET)


# Per bone: [bone_idx, base_rotation, slumped_rotation]; lerped by the crumple tween.
var _slump: Array = []


## On death, freeze the animation and blend the skeleton from its current pose into
## a limp/collapsed pose over CRUMPLE_TIME, so the existing corpse tumble carries a
## body that goes slack rather than a stiff statue. Pose-rotation only (no physics)
## -- robust against the FBX's 1/100 scale. The tween rides the skeleton, which the
## ragdoll reparents onto the corpse, so it survives until the corpse frees itself.
func _on_enemy_died(_e: Variant = null) -> void:
	_dead = true
	if _anim != null:
		_anim.pause()
	if _skel == null:
		return
	_slump.clear()
	for bone_name in SLUMP:
		var bi: int = _skel.find_bone(bone_name)
		if bi < 0:
			continue
		var base_q := _skel.get_bone_pose_rotation(bi)
		var off := Quaternion(Basis.from_euler((SLUMP[bone_name] as Vector3) * (PI / 180.0)))
		_slump.append([bi, base_q, base_q * off])
	var t := _skel.create_tween()
	t.tween_method(_apply_slump, 0.0, 1.0, CRUMPLE_TIME).set_ease(Tween.EASE_OUT)


func _apply_slump(amount: float) -> void:
	if not is_instance_valid(_skel):
		return
	for e in _slump:
		_skel.set_bone_pose_rotation(e[0], (e[1] as Quaternion).slerp(e[2] as Quaternion, amount))
