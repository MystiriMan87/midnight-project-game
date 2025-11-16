extends Node3D

# Signals
signal weapon_fired
signal weapon_reloaded

# Primary fire
@export var damage = 25
@export var fire_rate = 0.15
@export var max_ammo = 12
@export var reserve_ammo = 60
var current_ammo = 12

# Secondary fire (explosive)
@export var explosive_damage = 100
@export var explosion_radius = 5.0
@export var explosion_force = 20.0
@export var secondary_fire_rate = 1.0
@export var secondary_ammo_cost = 3

# Reload
@export var reload_time = 1.5
var is_reloading = false

# State
var can_shoot = true
var can_secondary_fire = true

@onready var raycast = $RayCast3D
@onready var muzzle_flash = $MuzzleFlash if has_node("MuzzleFlash") else null
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null

func _ready():
	if muzzle_flash:
		muzzle_flash.emitting = false
		muzzle_flash.one_shot = true

func _process(_delta):
	# Reload
	if Input.is_action_just_pressed("reload") and not is_reloading:
		reload()
	
	# Can't shoot while reloading
	if is_reloading:
		return
	
	# Primary fire
	if Input.is_action_pressed("fire") and can_shoot and current_ammo > 0:
		shoot()
	
	# Secondary fire (explosive shot)
	if Input.is_action_just_pressed("secondary_fire") and can_secondary_fire and current_ammo >= secondary_ammo_cost:
		shoot_explosive()
	
	# Auto-reload when empty
	if current_ammo <= 0 and not is_reloading and reserve_ammo > 0:
		reload()

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

func shoot_explosive():
	can_secondary_fire = false
	current_ammo -= secondary_ammo_cost
	
	print("EXPLOSIVE SHOT!")
	
	# Bigger camera shake
	weapon_fired.emit()
	
	# Play animation (use same or create new one)
	if animation_player and animation_player.has_animation("shoot"):
		animation_player.play("shoot")
	
	# Bigger muzzle flash
	if muzzle_flash:
		muzzle_flash.amount = 20  # More particles
		muzzle_flash.restart()
		muzzle_flash.emitting = true
		# Reset amount after
		await get_tree().create_timer(0.1, false).timeout
		if muzzle_flash:
			muzzle_flash.amount = 8
	
	# Get shoot origin and direction
	var shoot_origin = global_position
	var shoot_direction = -global_transform.basis.z
	
	# Raycast check for explosion point
	var explosion_point = shoot_origin + shoot_direction * 50.0
	
	if raycast.is_colliding():
		explosion_point = raycast.get_collision_point()
	
	# Create explosion
	create_explosion(explosion_point)
	
	# Knockback player
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_knockback"):
		var knockback_dir = (shoot_origin - explosion_point).normalized()
		player.apply_knockback(knockback_dir * explosion_force)
	
	# Spawn explosion tracer (thicker beam)
	spawn_explosive_tracer(shoot_origin, explosion_point)
	
	# Secondary fire cooldown
	await get_tree().create_timer(secondary_fire_rate, false).timeout
	can_secondary_fire = true

func create_explosion(pos: Vector3):
	# Visual explosion effect
	spawn_explosion_effect(pos)
	
	# Damage all enemies in radius
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = explosion_radius
	query.shape = shape
	query.transform.origin = pos
	
	var results = space_state.intersect_shape(query)
	
	for result in results:
		var hit_object = result.collider
		if hit_object.has_method("take_damage"):
			# Calculate distance-based damage
			var distance = pos.distance_to(hit_object.global_position)
			var damage_multiplier = 1.0 - (distance / explosion_radius)
			var final_damage = explosive_damage * damage_multiplier
			hit_object.take_damage(final_damage)
			
			# Knockback enemy
			if hit_object.has_method("apply_knockback"):
				var knockback_dir = (hit_object.global_position - pos).normalized()
				hit_object.apply_knockback(knockback_dir * explosion_force * 0.5)

func reload():
	if reserve_ammo <= 0:
		print("No reserve ammo!")
		return
	
	if current_ammo >= max_ammo:
		print("Already full!")
		return
	
	is_reloading = true
	print("Reloading...")
	
	# Play reload animation if you have one
	if animation_player and animation_player.has_animation("reload"):
		animation_player.play("reload")
	
	# Wait for reload time
	await get_tree().create_timer(reload_time, false).timeout
	
	# Calculate ammo to reload
	var ammo_needed = max_ammo - current_ammo
	var ammo_to_add = min(ammo_needed, reserve_ammo)
	
	current_ammo += ammo_to_add
	reserve_ammo -= ammo_to_add
	
	is_reloading = false
	weapon_reloaded.emit()
	print("Reload complete! Ammo: ", current_ammo, "/", max_ammo, " Reserve: ", reserve_ammo)

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

func spawn_explosive_tracer(from: Vector3, to: Vector3):
	# Thicker, orange beam for explosive
	var tracer = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.height = from.distance_to(to)
	mesh.top_radius = 0.05  # Much thicker
	mesh.bottom_radius = 0.05
	tracer.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.ORANGE
	material.emission_enabled = true
	material.emission = Color.ORANGE
	material.emission_energy_multiplier = 3.0
	tracer.material_override = material
	
	get_tree().root.add_child(tracer)
	tracer.global_position = from.lerp(to, 0.5)
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
	await get_tree().create_timer(0.1, false).timeout
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

func spawn_explosion_effect(pos: Vector3):
	# Large explosion particles
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
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 10.0
	material.gravity = Vector3(0, -10, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	material.color = Color.ORANGE
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = pos
	
	# Explosion flash sphere
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = explosion_radius
	sphere_mesh.height = explosion_radius * 2
	flash.mesh = sphere_mesh
	
	var flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color.ORANGE
	flash_material.emission_enabled = true
	flash_material.emission = Color.ORANGE
	flash_material.emission_energy_multiplier = 5.0
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color.a = 0.5
	flash.material_override = flash_material
	
	get_tree().root.add_child(flash)
	flash.global_position = pos
	
	# Animate flash
	var tween = create_tween()
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.3).from(Vector3.ONE * 0.1)
	
	await get_tree().create_timer(1.0, false).timeout
	particles.queue_free()
	flash.queue_free()
