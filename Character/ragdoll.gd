extends PhysicalBoneSimulator3D

@export var freeze_time: float = 120.0 ## The time, in seconds, before the ragdoll is frozen.[br]Set to zero to disable.
# TODO @export var preserve_collision_on_freeze: bool = false ## Leave the collision enabled after freezing.[br](decreases performance)
@export var lifetime: float = 300.0 ## The lifetime, in seconds, before the ragdoll is removed.[br]Set to zero to disable.

func start_sim(): ## Activate the ragdoll
	physical_bones_start_simulation()

	if freeze_time != 0.0: # Start the freeze time timer
		var Timer_freeze = Timer.new() # Create a new timer node
		Timer_freeze.one_shot = true # It needs to be one_shot, we don't want it restarting
		Timer_freeze.connect("timeout", _freeze) # Connect the "timeout" signal to the _freeze() function, so when the time is up, _freeze is called.
		self.add_child(Timer_freeze) # Add the timer to the scene.  Otherwise, it can't be used.
		Timer_freeze.start(freeze_time) # Start the timer with the given time.
	if lifetime != 0.0: # Start the lifetime time timer ;)
		var Timer_death = Timer.new()
		Timer_death.one_shot = true
		Timer_death.connect("timeout", _remove)
		self.add_child(Timer_death)
		Timer_death.start(lifetime)


func _freeze(): ## Freeze the ragdoll, preserving the mesh shape.
	var bone_positions: Dictionary = {} # Dictionary for all the bone's locations

	for bone in get_children():
		if bone is PhysicalBone3D:
			bone_positions[bone.name] = [bone.position, bone.rotation]

	physical_bones_stop_simulation()

	for bone in get_children(): # For some reason the bones all reset after stopping the physical simulation.  We un-reset them here.
		if bone is PhysicalBone3D:
			bone.collision_layer = 0
			bone.global_position = bone_positions[bone.name][0]
			bone.global_rotation = bone_positions[bone.name][1]


func _remove(): ## Delete the entire visual instance, the WorldModel scene.
	get_parent().get_parent().queue_free()
