extends CharacterBody3D

## Required Input Mappings:
# forward
# backward
# left
# right
# jump
# walk
# crouch
# look_up (controller)
# look_down (controller)
# look_left (controller)
# look_right (controller)

var dead: bool = false ## Track if the character has died or not

@export var mouse_sensitivity:      float = 0.15 ## Mouse sensitivity.  Should be a pretty small number.[br]This number is divided by 100 whenever it is used, just to make the input more human-readable.
@export var controller_sensitivity: float = 0.05  ## Controller camera sensitivity.  Should be a small number.

@export var health: float = 100.0
@export var enable_fall_damage: bool = true ## Enable or disable fall damage.
@export var start_fall_damage_velocity: float = 10.0 ## No fall damage will be taken if the falling velocity was this, or lower.
@export var end_fall_damage_velocity: float = 20.0 ## This velocity and higher will insta-kill the player.[br][br]Although technically these values are being interpolated linearly, due to the gravitational acceleration velocity being an inverse square formula, the upper limit is actually quite close to the lower limit.[br]The physical distance traveled, however, will increase significantly.  
var last_speed: float ## This keeps track of the previous vertical velocity. (from [param velocity.y])
var last_last_speed: float ## This velocity tracker is updated one physics frame after  

@export var JUMP_VELOCITY:  float = 6.0 ## Jump power.  Higher is, well, higher.
@export var auto_bhop:       bool = false ## If enabled, the character will continue to jump while the jump key is pressed.
@export var CHARACTER_MASS: float = 80.0 ## The mass of the character, in kg.  Used only for [RigidBody3D] interactions.

## Ground movement settings
@export var WALK_SPEED:          float = 4.2 ## Walking velocity (holding shift).
@export var SPRINT_SPEED:        float = 8.0 ## Running velocity (just [kbd]W[/kbd]).
@export var ground_acceleration: float = 15.0 ## Time to get up to the target speed.  Higher is faster.
@export var ground_deceleration: float = 2.0 ## Time to stop.  Higher is faster.  For some reason this is way lower than ground_acceleration.
@export var ground_friction:     float = 5.0 ## How much velocity you lose on ground.  This is probably why ground_deceleration doesn't need to be as high.

## Air movement settings
@export var air_cap:          float = 0.85 ## Can surf steeper ramps if this is higher, makes it easier to stick and bhop
@export var air_acceleration: float = 800.0
@export var air_move_speed:   float = 500.0

## Crouch settings
@export var CROUCH_TRANSLATE:         float = 0.7 ## Crouch by this distance, from the original height.
@export var CROUCH_SPEED_MULT:        float = 0.55 ## Multiply walking speed by this value while crouching
@export var CROUCH_SWITCH_SPEED:      float = 4.0 ## How quickly to crouch.  Higher is faster.
var CROUCH_JUMP_ADD:                  float = CROUCH_TRANSLATE * 0.9 ## * 0.9 for sourcelike camera jiter in air on crouch, makes for a nice notifier
var is_crouched:                       bool = false ## This is used to keep track of the crouched state, mostly for updating animations, but also to properly calculate velocity. (slower while crouching)
@onready var original_capsule_height: float = $CollisionShape3D.shape.height ## Save the origonal height set in the editor. (to return to after crouching)

## Headbob settings
@export var use_headbob:    bool = false ## Bob the camera along a sine wave while moving
const HEADBOB_MOVE_AMOUNT: float = 0.06
const HEADBOB_FREQUENCY:   float = 2.4
var headbob_time:          float = 0.0

## Smooth sliding over bumps settings
const MAX_STEP_HEIGHT:           float = 0.5
var snapped_to_stairs_last_frame: bool = false
var last_frame_was_on_floor:     float = -INF

var wish_dir: Vector3 = Vector3.ZERO
var anim_dir: Vector2 = Vector2(0, 0)

func _ready() -> void:
	if not OS.is_debug_build():
		$CanvasLayerDebug.queue_free()

	%Camera3D.current = true # There may be other cameras in the scene.  When we spawn, we usin' THIS camera.

	for child in %WorldModel.find_children("*", "VisualInstance3D"): # Remove the visual model from the camera's view.
		child.set_layer_mask_value(1, false)
		child.set_layer_mask_value(2, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: # Disable this later, and simply let logic check for the current mouse mode.
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if dead: # Don't take mouse input if the player has died.
		return

	if Input.get_mouse_mode( ) == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * mouse_sensitivity / 100)
			%Camera3D.rotate_x(-event.relative.y * mouse_sensitivity / 100)
			%Camera3D.rotation.x = clamp(%Camera3D.rotation.x, deg_to_rad(-89.9), deg_to_rad(89.9))


func _handle_controller_look(_delta) -> void: ## If the player is using a controller, this handles camera motion from the joysticks.
	if dead: # Don't take controller input if the player has died.
		return

	var target_look = Input.get_vector("look_left", "look_right", "look_up", "look_down").normalized()
	rotate_y(target_look.x * controller_sensitivity)
	%Camera3D.rotate_x(target_look.y * controller_sensitivity)
	%Camera3D.rotation.x = clamp(%Camera3D.rotation.x, deg_to_rad(-89.9), deg_to_rad(89.9))


func _get_move_speed() -> float: ## Return the desired move speed, depending on three states:[br]Crouching[br]Walking[br]Sprinting
	if is_crouched:
		return WALK_SPEED * CROUCH_SPEED_MULT
	return WALK_SPEED if Input.is_action_pressed("walk") else SPRINT_SPEED


func _physics_process(delta: float) -> void:
	# Debug only
	$CanvasLayerDebug/VBoxContainer/HBoxContainer/vel.text = str((velocity * Vector3(1, 0, 1)).length()) 
	$CanvasLayerDebug/VBoxContainer/HBoxContainer2/fps.text = str(Engine.get_frames_per_second())
	$CanvasLayerDebug/VBoxContainer/HBoxContainer3/health.text = str(health)
	# end Debug only

	update_animation_utils(delta) # Calculate and send the necessary data over to the animation manager.

	if is_on_floor():
		last_frame_was_on_floor = Engine.get_physics_frames()

	var input_dir: Vector2
	if dead: # Immeditatly stop (don't preserve momentum) upon death.
		input_dir = Vector2.ZERO
	else:
		input_dir = Input.get_vector("left", "right", "forward", "backward").normalized()
	wish_dir = self.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	handle_crouch(delta)

	if is_on_floor() or snapped_to_stairs_last_frame:
		if Input.is_action_just_pressed("jump") or (auto_bhop and Input.is_action_pressed("jump")):
			self.velocity.y = JUMP_VELOCITY
			update_animation_utils(delta, true)
		_handle_ground_physics(delta)
	else:
		_handle_air_physics(delta)

	last_speed = abs(velocity.y)

	if not snap_up_to_stairs_check(delta):
		push_away_rigid_bodies()
		move_and_slide()
		snap_down_to_stairs_check()

	if is_on_floor() or snapped_to_stairs_last_frame:
		if last_speed > 0.0:
			if last_speed >= start_fall_damage_velocity:
				health -= remap(last_speed, start_fall_damage_velocity, end_fall_damage_velocity, 0.0, 100.0)
	elif last_speed == 0.0 and last_last_speed > 0.0: # Because ramps uhhhh idk man this part is need
		if last_last_speed >= start_fall_damage_velocity:
			health -= remap(last_last_speed, start_fall_damage_velocity, end_fall_damage_velocity, 0.0, 100.0)

	last_last_speed = last_speed

	if not dead and health <= 0.0:
		die()

	if Input.is_action_just_pressed("suicide"):
		die()


func _process(delta: float) -> void:
	_handle_controller_look(delta)


func update_animation_utils(delta, just_jumped: bool = false) -> void: ## This funcion is where the animation magic happens.[br]All the necessary data is transfered to the AnimationUtils scrip for ease of access.
	# Crouching
	%AnimationUtils.crouching = is_crouched

	var real_sprint_speed = friction(SPRINT_SPEED, delta) * SPRINT_SPEED
	var real_walk_speed = friction(WALK_SPEED, delta) * WALK_SPEED
	if (velocity * Vector3(1.0, 0.0, 1.0)).length() >= real_sprint_speed:
		%AnimationUtils.movement_transition = remap((velocity * Vector3(1.0, 0.0, 1.0)).length(), real_walk_speed, real_sprint_speed, 0.0, 1.0)
	else:
		%AnimationUtils.movement_transition = remap((velocity * Vector3(1.0, 0.0, 1.0)).length(), 0.0, real_walk_speed, -1.0, 0.0)
	%AnimationUtils.movement_transition = clamp(%AnimationUtils.movement_transition, -1.0, 1.0)

	# Animation direction
	var input_dir: Vector2 = Input.get_vector("left", "right", "backward", "forward").normalized()
	anim_dir = (anim_dir.lerp(input_dir, delta * 20.0)).clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	anim_dir *= (remap(self.velocity.length(), 0.0, friction(_get_move_speed(), delta) * _get_move_speed(), 0.0, 1.0))
	%AnimationUtils.direction = anim_dir

	# on floor, for falling animation
	if not is_on_floor() and not snapped_to_stairs_last_frame:
		%AnimationUtils.in_air = true
	else:
		%AnimationUtils.in_air = false

	# Trigger the jump animation
	if just_jumped:
		%AnimationUtils.jump_trigger = true


func handle_crouch(delta) -> void: ## Adjust the collision box and the camera on crouch.[br]The viewmodel is moved oppositely to the collision, so it appears static.
	var was_crouched_last_frame: bool = is_crouched

	if Input.is_action_pressed("crouch"):
		is_crouched = true
	elif is_crouched and not self.test_move(self.transform, Vector3(0, CROUCH_TRANSLATE, 0)):
		is_crouched = false

	var translate_y_if_possible: float = 0.0
	if was_crouched_last_frame != is_crouched and not is_on_floor() and not snapped_to_stairs_last_frame:
		translate_y_if_possible = CROUCH_JUMP_ADD if is_crouched else -CROUCH_JUMP_ADD

	# Make sure to not get player stuck in floor/ceiling curing crouch jumps
	if translate_y_if_possible != 0.0:
		var result = KinematicCollision3D.new()
		self.test_move(self.transform, Vector3(0, translate_y_if_possible, 0), result)
		self.position.y += result.get_travel().y
		$WorldModel.position.y -= result.get_travel().y # Move the viewmodel down by however much the collision got moved up (and vice-versa) so my guy doens't absolutely die from instantaneous acceleration.
		%Head.position.y -= result.get_travel().y
		%Head.position.y = clamp(%Head.position.y, -CROUCH_TRANSLATE, 0.0)

	$WorldModel.position.y = move_toward($WorldModel.position.y, 0.0, delta * CROUCH_SWITCH_SPEED)

	%Head.position.y = move_toward(%Head.position.y, -CROUCH_TRANSLATE if is_crouched else 0.0, CROUCH_SWITCH_SPEED * delta)
	$CollisionShape3D.shape.height = original_capsule_height - CROUCH_TRANSLATE if is_crouched else original_capsule_height
	$CollisionShape3D.position.y = $CollisionShape3D.shape.height / 2 # The character's collision shape must start level with the floor!


func push_away_rigid_bodies() -> void: ## Custom physics interactions to interact with [RigidBody3D].
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			var push_dir = -c.get_normal()
			var velocity_diff_in_push_dir = self.velocity.dot(push_dir) - c.get_collider().linear_velocity.dot(push_dir)
			velocity_diff_in_push_dir = max(0, velocity_diff_in_push_dir)
			var mass_ratio = min(1.0, CHARACTER_MASS / c.get_collider().mass) # heavier object harder to push
			push_dir.y = 0 # don't push objects from below or above
			var push_force = mass_ratio * 5.0 # magic number. :(
			c.get_collider().apply_impulse(push_dir * velocity_diff_in_push_dir * push_force, c.get_position() - c.get_collider().global_position)


func take_knockback(from: Vector3, power: float) -> void: ## Apply an impulse to the CharacterBody3D from the given direction.
	var body_position = self.global_position
	if not is_crouched:
		body_position.y += 0.3 # uhhh idk
	var force_div = max(0.01, self.CHARACTER_MASS)
	var force_dir = from.direction_to(body_position)
	var body_dist = (body_position - from).length()
	var explosion_vec = lerp(0.0, power, 1.0 - clampf((body_dist / 4.1), 0.0, 1.0)) / force_div * force_dir # 4.1 needs to be changed to the max radius of the explosion.
	self.velocity += explosion_vec * power


func _handle_ground_physics(delta: float) -> void: ## Custom movement and bhop physics while on the ground.
	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var add_speed_till_cap = _get_move_speed() - cur_speed_in_wish_dir
	if add_speed_till_cap > 0.0:
		var accel_speed = ground_acceleration * delta * _get_move_speed()
		accel_speed = min(accel_speed, add_speed_till_cap)
		self.velocity += accel_speed * wish_dir

	# Apply friction
	self.velocity *= friction(self.velocity.length(), delta)

	if use_headbob:
		headbob_effect(delta)


func snap_up_to_stairs_check(delta) -> bool: ## Check if we can snap up to the stairs.  This uses the raycast that is positioned in front of the character.[br]It returns true if we can glide up, and false if the gap is too high.
	if not is_on_floor() and not snapped_to_stairs_last_frame: return false
	var expected_move_motion = self.velocity * Vector3(1, 0, 1) * delta
	var step_pos_with_clearance = self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	var down_check_result = PhysicsTestMotionResult3D.new()
	if (
		run_body_test_motion(step_pos_with_clearance, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), down_check_result)
		and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))
	):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y

		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT:
			return false
		%StairsAheadRayCast3D.global_position = down_check_result.get_collision_point() + Vector3(0, MAX_STEP_HEIGHT, 0) + expected_move_motion.normalized() * 0.1
		%StairsAheadRayCast3D.force_raycast_update()
		if %StairsAheadRayCast3D.is_colliding() and not is_surface_too_steep(%StairsAheadRayCast3D.get_collision_normal()):
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			snapped_to_stairs_last_frame = true
			return true
	return false


func snap_down_to_stairs_check() -> void: ## After walking off a ledge, check to see if there is a step close enough below.[br]If so, smoothly snap down to it.  If not, fall.
	var did_snap: bool = false
	var floor_below: bool = %StairsBelowRayCast3D.is_colliding() and not is_surface_too_steep(%StairsBelowRayCast3D.get_collision_normal())
	var was_on_floor_last_frame = Engine.get_physics_frames() - last_frame_was_on_floor == 1
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	snapped_to_stairs_last_frame = did_snap


func _handle_air_physics(delta: float) -> void:  ## Custom surf and bhop physics while in the air.
	self.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	# The magic part

	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	# Wish speed capped to air_cap
	var capped_speed = min((air_move_speed * wish_dir).length(), air_cap)
	# Cool airstrafe stuff
	var add_speed_till_cap = capped_speed - cur_speed_in_wish_dir
	if add_speed_till_cap > 0.0:
		var accel_speed = air_acceleration * air_move_speed * delta
		accel_speed = min(accel_speed, add_speed_till_cap)
		self.velocity += accel_speed * wish_dir

	if is_on_wall():
		if is_surface_too_steep(get_wall_normal()):
			self.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		else:
			self.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		clip_velocity(get_wall_normal(), 1.0, delta) # surf :)


func friction(velLen, delta) -> float: ## A utility function that applies friction.[br]It takes the given velocity and decays it with property ground_friction.
	var control = max(velLen, ground_deceleration)
	var drop = control * ground_friction * delta
	var new_speed = max(velLen - drop, 0.0)
	if self.velocity.length() > 0.0:
		new_speed /= velLen
	return new_speed


func clip_velocity(normal: Vector3, overbounce: float, _delta: float) -> void: ## If the character velocity gets too high, smoothly bring it back down.
	var backoff = self.velocity.dot(normal) * overbounce
	if backoff >= 0.0:
		return

	var change = normal * backoff
	self.velocity -= change
	
	var adjust = self.velocity.dot(normal)
	if adjust < 0.0:
		self.velocity -= normal * adjust


func is_surface_too_steep(normal: Vector3) -> bool: ## Check and see if the given normal is too steep to walk on.  This uses the CharcterDody3D's floor_max_angle value.
	return normal.angle_to(Vector3.UP) > self.floor_max_angle


func run_body_test_motion(from: Transform3D, motion: Vector3, result = null) -> bool: ## With the given parameters, run a simulation and return true if there is a collision.
	if not result: result = PhysicsTestMotionResult3D.new()
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(self.get_rid(), params, result)


func headbob_effect(delta) -> void: ## Bob the camera along a sin wave to imitate footsteps.
	headbob_time += delta * self.velocity.length()
	%Camera3D.transform.origin = Vector3(
		cos(headbob_time * HEADBOB_FREQUENCY * 0.5) * HEADBOB_MOVE_AMOUNT,
		sin(headbob_time * HEADBOB_FREQUENCY) * HEADBOB_MOVE_AMOUNT,
		0
	)


func die() -> void: ## Kill the player, for physics
	if dead:
		return

	dead = true
	self.collision_layer = 0 # Disable the origonal player collision

	for child in %WorldModel.find_children("*", "VisualInstance3D"): # Reenable visiblility
		child.set_layer_mask_value(1, true)
		child.set_layer_mask_value(2, false)

	var ragdoll = %WorldModel.get_child(0) # Get the viewmodel, which we are now calling ragdoll
	ragdoll.reparent(get_node("../ragdolls"), true) # Reparent the ragdoll to a ragdoll-only node in the map.
	ragdoll.die() # Activate the ragdoll

	%Camera3D.current = false # Disable the player camera (another one is spawned and used to highlight the death)
