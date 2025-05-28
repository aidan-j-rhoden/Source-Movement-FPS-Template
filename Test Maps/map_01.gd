extends Node3D

@onready var character = preload("res://Character/characterController.tscn")

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		var old_char = $CharacterController
		old_char.name = "OldChar"
		var new_char = character.instantiate()
		add_child(new_char, true)
		new_char.global_position.y = 1.0
		new_char.name = "CharacterController"
		old_char.get_node("WorldModel").queue_free()
		old_char.get_node("AnimationUtils").queue_free()
		old_char.queue_free()
