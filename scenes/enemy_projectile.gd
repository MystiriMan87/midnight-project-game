extends Area3D

var velocity = Vector3.ZERO
var speed = 20.0
var damage = 15
var lifetime = 5.0

func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	await get_tree().create_timer(lifetime).timeout
	queue_free()
	
func _process(delta):
	global_position += velocity * delta

func setup(direction: Vector3, proj_speed: float, proj_damage: int):
	velocity = direction * proj_speed
	speed = proj_speed
	damage = proj_damage
	
	look_at(global_position + direction)
	
func _on_body_entered(body):
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		explode()
	elif body is StaticBody3D or body is CharacterBody3D:
		explode()
	
func _on_area_entered(area):
	if area.name == "Player":
		explode()
		
func explode():
	spawn_explosion_effect()
	queue_free()
	
func spawn_explosion_effect():
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 15
	particles.lifetime = 0.4
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.2
	material.direction = Vector3(0, 1, 0)
	material.spread = 100
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -10, 0)
	material.scale_min = 0.05
	material.scale_max = 0.1
	material.color = Color.ORANGE
	
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	await get_tree().create_timer(0.5).timeout
	particles.queue_free()
