extends Node

@export var movement_transition: float = 0.0 ## 0.0 is walk, 1 is run, -1.0 is idle. 
@export var crouching: bool = false ## Duh
@export var jump_trigger: bool = false ## A signal-like event to start the jump animation
@export var in_air: bool = false ## Control falling animation
@export var direction: Vector2 = Vector2(0, 0) # Normalized input direction smoothly blended
