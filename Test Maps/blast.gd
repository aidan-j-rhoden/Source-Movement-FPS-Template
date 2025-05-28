extends Area3D

@export var radius: float = 2.0
@export var power: float = 60.0

func _ready() -> void:
	$CollisionShape3D.shape.radius = self.radius
	$CollisionShape3D/MeshInstance3D.mesh.radius = self.radius
	$CollisionShape3D/MeshInstance3D.mesh.height = self.radius * 2.0


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.take_knockback(self.global_position, self.power)
	elif body is RigidBody3D:
		var body_position = body.global_position
		body_position.y += 0.1
		var force_div = max(0.01, body.mass)
		var force_dir = self.global_position.direction_to(body_position)
		var body_dist = (body_position - self.global_position).length()
		var explosion_vec = lerp(0.0, power, 1.0 - clampf((body_dist / 4.1), 0.0, 1.0)) / force_div * force_dir
		body.apply_impulse(explosion_vec * self.power)
