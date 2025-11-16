extends Node3D

# Signal for camera shake
signal weapon_fired

@export var damage = 25
@export var fire_rate = 0.15
@export var max_ammo = 12
var current_ammo = 12

var can_shoot = true

@onready var raycast = $RayCast3D
@onready var muzzle_flash = $MuzzleFlash if has_node("MuzzleFlash") else null
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null

func _ready():
	if muzzle_flash:
		muzzle_flash.emitting = false
		muzzle_flash.one_shot = true

func _process(_delta):
	if Input.is_action_just_pressed("fire") and can_shoot and current_ammo > 0:
		shoot()

func shoot():
	can_shoot = false
	current_ammo -= 1
	
	# Emit signal for camera shake
	weapon_fired.emit()
	
	# Play animation
	if animation_player and animation_player.has_animation("shoot"):
		animation_player.play("shoot")
	
	# Muzzle flash
	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	
	# Get shoot origin and direction
	var shoot_origin = global_position
	var shoot_direction = -global_transform.basis.z
	
	# Raycast check
	var hit_point = shoot_origin + shoot_direction * 100.0
	
	if raycast.is_colliding():
		hit_point = raycast.get_collision_point()
		var hit_object = raycast.get_collider()
		
		print("Hit: ", hit_object.name, " at ", hit_point)
		
		# Damage
		if hit_object.has_method("take_damage"):
			hit_object.take_damage(damage)
		
		# Spawn impact effect at hit point
		spawn_impact_effect(hit_point)
	
	# Spawn bullet tracer
	spawn_tracer(shoot_origin, hit_point)
	
	# Fire rate cooldown
	await get_tree().create_timer(fire_rate, false).timeout
	can_shoot = true

func spawn_tracer(from: Vector3, to: Vector3):
	var tracer = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.height = from.distance_to(to)
	mesh.top_radius = 0.01
	mesh.bottom_radius = 0.01
	tracer.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	material.emission_enabled = true
	material.emission = Color.YELLOW
	material.emission_energy_multiplier = 2.0
	tracer.material_override = material
	
	get_tree().root.add_child(tracer)
	tracer.global_position = from.lerp(to, 0.5)
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
	await get_tree().create_timer(0.05, false).timeout
	tracer.queue_free()

func spawn_impact_effect(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 10
	particles.lifetime = 0.3
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.1
	material.direction = Vector3(0, 1, 0)
	material.spread = 45
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 4.0
	material.gravity = Vector3(0, -5, 0)
	material.scale_min = 0.02
	material.scale_max = 0.05
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = pos
	
	await get_tree().create_timer(0.5, false).timeout
	particles.queue_free()

func reload():
	current_ammo = max_ammo
	print("Reloaded! Ammo: ", current_ammo, "/", max_ammo)
