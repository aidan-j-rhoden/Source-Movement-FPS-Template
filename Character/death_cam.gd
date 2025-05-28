extends Camera3D

@export var rotation_follow_speed: float = 8.0
var tracking: bool = false
var now_die: bool = false

func _ready() -> void:
	self.current = false # Disable this camera


func _physics_process(delta: float) -> void:
	if not tracking:
		self.look_at(get_parent().TARGET_BONE.global_position)

	if self.current:
		now_die = true
	elif now_die:
		queue_free()

	$CanvasLayer.visible = self.current

	var target_position = get_parent().TARGET_BONE.global_position
	var direction_to_target = (target_position - global_transform.origin).normalized()
	if direction_to_target.length() > 0:  # Ensure direction is valid
		var desired_transform = Transform3D().looking_at(direction_to_target, Vector3.UP)
		var desired_basis = desired_transform.basis

		# Smoothly interpolate the camera's rotation using slerp
		var current_basis = global_transform.basis
		var new_basis = current_basis.slerp(desired_basis, rotation_follow_speed * delta)
		global_transform.basis = new_basis


func activate():
	tracking = true
