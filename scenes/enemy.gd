extends CharacterBody3D

@export var max_health = 100
@export var move_speed = 3.0
@export var detection_range = 20.0

var health = max_health
var player = null
var gravity = 20.0
var knockback_velocity = Vector3.ZERO

@onready var nav_agent = $NavigationAgent3D

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 3.0 * delta)
	velocity += knockback_velocity * delta * 10.0
	
	if player:
		var distance = global_position.distance_to(player.global_position)
		
		if distance < detection_range:
			nav_agent.target_position = player.global_position
			
			if nav_agent.is_navigation_finished():
				velocity.x = 0
				velocity.z = 0
			else:
				var next_pos = nav_agent.get_next_path_position()
				var direction = (next_pos - global_position).normalized()
				
				velocity.x = direction.x * move_speed
				velocity.z = direction.z * move_speed
				
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	
	move_and_slide()

func take_damage(amount):
	health -= amount
	
	var hitmarker = get_tree().get_first_node_in_group("hitmarker")
	if hitmarker:
		hitmarker.show_hit(health <= 0)
		
	print("Enemy took ", amount, " damage. Health: ", health)
	
	if health <= 0:
		die()

func apply_knockback(force: Vector3):
	knockback_velocity = force

func die():
	visible = false
	set_physics_process(false)
	set_process(false)
	
	await spawn_death_explosion()
	
	queue_free()

func spawn_shockwave(pos: Vector3):
	var ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.2
	ring_mesh.outer_radius = 0.4
	ring.mesh = ring_mesh
	
	var ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1, 0.3, 0.3, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color.RED
	ring_mat.emission_energy_multiplier = 4.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	
	get_tree().root.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3(0.1, 0.1, 0.1)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(4, 4, 4), 0.4)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
	
	await get_tree().create_timer(0.5).timeout
	ring.queue_free()

func spawn_death_explosion():
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 50
	particles.lifetime = 1.0
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5
	material.direction = Vector3(0, 1, 0)
	material.spread = 180
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0, -20, 0)
	material.damping_min = 2.0
	material.damping_max = 4.0
	
	material.scale_min = 0.15
	material.scale_max = 0.35
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 0.1, 0.0, 1))  # Intense bright red
	gradient.add_point(0.3, Color(0.9, 0.0, 0.0, 1))  # Pure deep red
	gradient.add_point(1.0, Color(0.5, 0.0, 0.0, 0))  # Dark red fade
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	material.angle_min = 0
	material.angle_max = 360
	
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3)
	
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.albedo_color = Color.WHITE
	
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	spawn_shockwave(global_position)
	
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.5
	sphere.height = 3.0
	flash.mesh = sphere
	
	var flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.05, 0.05, 0.9)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1, 0, 0)
	flash_mat.emission_energy_multiplier = 6.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	
	get_tree().root.add_child(flash)
	flash.global_position = global_position
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.3).from(Vector3.ONE * 0.3)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
	
	await get_tree().create_timer(1.2).timeout
	particles.queue_free()
	flash.queue_free()
