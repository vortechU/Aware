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

var _anim: AnimationPlayer
var _enemy: Node3D       # the EnemyAI (CharacterBody3D); set at setup, valid as the husk
var _dead := false


## Wired by CharacterApplicator after the model + player are parented in.
func setup(anim: AnimationPlayer, enemy: Node3D) -> void:
	_anim = anim
	_enemy = enemy
	if _enemy != null and _enemy.has_signal("enemy_died"):
		_enemy.enemy_died.connect(_on_enemy_died)
	if _anim != null and _anim.has_animation("idle"):
		_anim.play("idle")


func _process(_delta: float) -> void:
	if _dead or _anim == null or not is_instance_valid(_enemy):
		return
	var speed := Vector2(_enemy.velocity.x, _enemy.velocity.z).length()
	var want := "run" if speed > RUN_SPEED else "idle"
	if _anim.current_animation != want and _anim.has_animation(want):
		_anim.play(want, BLEND)


func _on_enemy_died(_e: Variant = null) -> void:
	_dead = true
	if _anim != null:
		_anim.pause()  # freeze the current pose; the corpse rigidbody does the tumbling
