extends Node3D

var lifetime = 0.05

func _ready():
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func set_length(length: float):
	var mesh = $MeshInstance3D
	if mesh and mesh.mesh:
		mesh.mesh.height = length
		# Position it so it extends from origin
		mesh.position.z = -length / 2.0
