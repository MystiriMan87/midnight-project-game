extends CharacterBody3D
signal died


@export var max_health = 50
@export var move_speed = 5.0
@export var detection_range = 30.0
@export var shoot_range = 25.0
@export var hover_height = 4.0
@export var projectile_speed = 20.0
@export var projectile_damage = 15
@export var keep_distance = 15.0

var health = max_health
var player = null
var hover_time = 0.0
var gravity = 5.0
var projectile_scene = preload("res://scenes/enemy_projectile.tscn")

@onready var shoot_timer = $ShootTimer
@onready var mesh = $MeshInstance3D

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	if shoot_timer:
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)

func _physics_process(delta):
	hover_time += delta
	
	if global_position.y < hover_height:
		velocity.y = gravity
	else:
		velocity.y = 0
	
	if not player:
		move_and_slide()
		return
	
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player < detection_range:
		var target_pos = player.global_position
		target_pos.y += hover_height
		
		var direction = (target_pos - global_position).normalized()
		
		if distance_to_player > keep_distance:
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
		elif distance_to_player < keep_distance - 2.0:
			velocity.x = -direction.x * move_speed
			velocity.z = -direction.z * move_speed
		else:
			velocity.x = 0
			velocity.z = 0
		
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
		
		var bob = sin(hover_time * 3.0) * 0.15
		velocity.y += bob
	
	move_and_slide()

func _on_shoot_timer_timeout():
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance < shoot_range:
		shoot_projectile()

func shoot_projectile():
	if not projectile_scene:
		print("No projectile scene loaded!")
		return
	
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
	
	projectile.global_position = global_position
	
	var direction = (player.global_position - global_position).normalized()
	
	if projectile.has_method("setup"):
		projectile.setup(direction, projectile_speed, projectile_damage)

func take_damage(amount):
	health -= amount
	
	var hitmarker = get_tree().get_first_node_in_group("hitmarker")
	if hitmarker:
		hitmarker.show_hit(health <= 0)
	
	
	if mesh:
		mesh.scale = Vector3.ONE * 0.8
		var tween = create_tween()
		tween.tween_property(mesh, "scale", Vector3.ONE, 0.2)
	
	print("Flying enemy took ", amount, " damage. Health: ", health)
	
	if health <= 0:
		die()

func apply_knockback(force: Vector3):
	velocity += force * 0.3

func die():
	died.emit() 
	visible = false
	set_physics_process(false)
	set_process(false)
	
	if shoot_timer:
		shoot_timer.stop()
	
	await spawn_death_effect()
	
	queue_free()

func spawn_death_effect():
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 40
	particles.lifetime = 0.8
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5
	material.direction = Vector3(0, 0, 0)
	material.spread = 180
	material.initial_velocity_min = 6.0
	material.initial_velocity_max = 12.0
	material.gravity = Vector3(0, -15, 0)
	material.damping_min = 1.0
	material.damping_max = 3.0
	
	material.scale_min = 0.12
	material.scale_max = 0.25
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 0.3, 0.2, 1))  # Bright red-orange
	gradient.add_point(0.4, Color(0.9, 0.1, 0.1, 1))  # Deep red
	gradient.add_point(1.0, Color(0.4, 0.0, 0.0, 0))  # Dark fade
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	material.angle_min = 0
	material.angle_max = 360
	
	particles.process_material = material
	
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.25, 0.25)
	
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.albedo_color = Color.WHITE
	
	quad_mesh.material = mesh_mat
	particles.draw_pass_1 = quad_mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	flash.mesh = sphere
	
	var flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.2, 0.2, 0.7)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color.RED
	flash_mat.emission_energy_multiplier = 4.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	
	get_tree().root.add_child(flash)
	flash.global_position = global_position
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.25).from(Vector3.ONE * 0.25)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.25)
	
	await get_tree().create_timer(1.0).timeout
	particles.queue_free()
	flash.queue_free()
