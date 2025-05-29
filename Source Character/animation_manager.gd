extends Node3D

@export var CHARACTER_RAGDOLL: PhysicalBoneSimulator3D ## The PhysicalBoneSimulator3D node that contains all the bones and collisions.
@export var TARGET_BONE: PhysicalBone3D ## The bone that the death camera will track too.[br]A spine or hip bone works great.

@onready var anim_utils = get_parent().get_parent().get_node("AnimationUtils")
@onready var anim_tree = $AnimationTree

## Anim Strings
var crouch_blend: String = "parameters/crouch_blend/blend_position" ## Strafe direcitons for the crouched state
var walk_blend: String = "parameters/walk_blend/blend_position" ## Strafe directions for the walking state
var run_blend: String = "parameters/run_blend/blend_position" ## Strafe directions for the sprinting state
var movement_blend: String = "parameters/movement_blend/blend_amount" ## -1.0 is idle, 0.0 is walk, 1.0 is run
var crouch_movement_blend: String = "parameters/crouch_movement_blend/blend_amount" ## idle or walking at crouched speed
var jump: String = "parameters/jump/request" ## set to AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE to fire, 0.0 to 1.0
var on_air: String = "parameters/on_air/transition_request" ## set to either air or ground
var crouched: String = "parameters/crouched/transition_request" ## set to either crouched or not

func _process(_delta: float) -> void:
	if not anim_tree.active:
		return

	anim_tree[movement_blend] = anim_utils.movement_transition
	anim_tree[crouch_movement_blend] = remap(clamp(anim_utils.movement_transition, -1.0, 0.0), -1.0, 0.0, 0.0, 1.0)

	anim_tree[crouch_blend] = anim_utils.direction
	anim_tree[walk_blend] = anim_utils.direction
	anim_tree[run_blend] = anim_utils.direction

	if anim_utils.crouching:
		anim_tree[crouched] = "crouched"
	else:
		anim_tree[crouched] = "not"

	if anim_utils.in_air:
		anim_tree[on_air] = "air"
	else:
		anim_tree[on_air] = "ground"

	if anim_utils.jump_trigger:
		anim_tree[jump] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
		anim_utils.jump_trigger = false


func die() -> void: ## Activate the ragdoll
	anim_tree.active = false
	self.CHARACTER_RAGDOLL.start_sim()
	get_node("DeathCam").activate()
