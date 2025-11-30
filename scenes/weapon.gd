extends Node3D

signal weapon_fired
signal weapon_reloaded
signal reload_started

@export var damage = 25
@export var fire_rate = 0.08
@export var max_ammo = 18
@export var reserve_ammo = 90
var current_ammo = 18

@export var explosive_damage = 100
@export var explosion_radius = 5.0
@export var explosion_force = 20.0
@export var secondary_fire_rate = 0.8
@export var secondary_ammo_cost = 3

@export var reload_time = 1.2
var is_reloading = false

var sway_amount = 0.02
var sway_speed = 5.0
var bob_amount = 0.03
var bob_speed = 0.15
var bob_time = 0.0

var can_shoot = true
var can_secondary_fire = true

var default_position = Vector3.ZERO
var default_rotation = Vector3.ZERO

@onready var raycast = $RayCast3D
@onready var muzzle_flash = $MuzzleFlash if has_node("MuzzleFlash") else null
@onready var muzzle_flash_ring = $MuzzleFlashRing if has_node("MuzzleFlashRing") else null
@onready var shell_ejection = $ShellEjection if has_node("ShellEjection") else null
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var shoot_point = $ShootPoint if has_node("ShootPoint") else null
@onready var gun_pivot = $GunPivot if has_node("GunPivot") else null

func _ready():
	if muzzle_flash:
		muzzle_flash.emitting = false
		muzzle_flash.one_shot = true
	if muzzle_flash_ring:
		muzzle_flash_ring.emitting = false
		muzzle_flash_ring.one_shot = true
	
	if not shoot_point:
		print("WARNING: No ShootPoint found!")
	
	if gun_pivot:
		default_position = gun_pivot.position
		default_rotation = gun_pivot.rotation
	else:
		default_position = position
		default_rotation = rotation

func _process(delta):
	apply_weapon_sway(delta)
	
	if Input.is_action_just_pressed("reload") and not is_reloading:
		reload()
	
	if is_reloading:
		return
	
	if Input.is_action_pressed("fire") and can_shoot and current_ammo > 0:
		shoot()
	
	if Input.is_action_just_pressed("secondary_fire") and can_secondary_fire and current_ammo >= secondary_ammo_cost:
		shoot_explosive()
	
	if current_ammo <= 0 and not is_reloading and reserve_ammo > 0:
		reload()

func apply_weapon_sway(delta):
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var target_node = gun_pivot if gun_pivot else self
	
	var velocity = Vector2(player.velocity.x, player.velocity.z)
	var speed = velocity.length()
	
	if player.is_on_floor() and speed > 1.0:
		bob_time += delta * speed * bob_speed
		
		var sway_x = sin(bob_time) * bob_amount
		var bob_y = sin(bob_time * 2.0) * bob_amount * 0.5
		
		target_node.position.x = lerp(target_node.position.x, default_position.x + sway_x, 10.0 * delta)
		target_node.position.y = lerp(target_node.position.y, default_position.y + bob_y, 10.0 * delta)
	else:
		target_node.position.x = lerp(target_node.position.x, default_position.x, 5.0 * delta)
		target_node.position.y = lerp(target_node.position.y, default_position.y, 5.0 * delta)
	
	var strafe_input = Input.get_axis("move_left", "move_right")
	var target_tilt = strafe_input * 2.0
	target_node.rotation_degrees.z = lerp(target_node.rotation_degrees.z, target_tilt, 8.0 * delta)

func shoot():
	can_shoot = false
	current_ammo -= 1
	
	weapon_fired.emit()
	
	if animation_player and animation_player.has_animation("shoot"):
		animation_player.play("shoot", -1, 1.5)
	
	
	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	if muzzle_flash_ring:
		muzzle_flash_ring.restart()
		muzzle_flash_ring.emitting = true
	if shell_ejection:
		shell_ejection.restart()
		shell_ejection.emitting = true
	
	var shoot_origin = shoot_point.global_position if shoot_point else global_position
	var shoot_direction = -shoot_point.global_transform.basis.z if shoot_point else -global_transform.basis.z
	
	var hit_point = shoot_origin + shoot_direction * 100.0
	
	if raycast.is_colliding():
		hit_point = raycast.get_collision_point()
		var hit_object = raycast.get_collider()
		
		if hit_object.has_method("take_damage"):
			hit_object.take_damage(damage)
		
		spawn_impact_effect(hit_point)
	
	spawn_tracer(shoot_origin, hit_point)
	
	var adjusted_fire_rate = fire_rate * Engine.time_scale
	await get_tree().create_timer(adjusted_fire_rate, false).timeout
	can_shoot = true
	
	await get_tree().create_timer(fire_rate, false).timeout
	can_shoot = true

func shoot_explosive():
	can_secondary_fire = false
	current_ammo -= secondary_ammo_cost
	
	weapon_fired.emit()
	
	if animation_player and animation_player.has_animation("shoot"):
		animation_player.play("shoot")
	
	if muzzle_flash:
		muzzle_flash.amount = 25
		muzzle_flash.restart()
		muzzle_flash.emitting = true
		await get_tree().create_timer(0.1, false).timeout
		if muzzle_flash:
			muzzle_flash.amount = 8
	
	var shoot_origin = shoot_point.global_position if shoot_point else global_position
	var shoot_direction = -shoot_point.global_transform.basis.z if shoot_point else -global_transform.basis.z
	
	var explosion_point = shoot_origin + shoot_direction * 50.0
	
	if raycast.is_colliding():
		explosion_point = raycast.get_collision_point()
	
	create_explosion(explosion_point)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_knockback"):
		var knockback_dir = (shoot_origin - explosion_point).normalized()
		player.apply_knockback(knockback_dir * explosion_force)
	
	spawn_explosive_tracer(shoot_origin, explosion_point)
	
	await get_tree().create_timer(secondary_fire_rate, false).timeout
	can_secondary_fire = true
	
	var adjusted_cooldown = secondary_fire_rate * Engine.time_scale
	await get_tree().create_timer(adjusted_cooldown, false).timeout
	can_secondary_fire = true

func create_explosion(pos: Vector3):
	spawn_explosion_effect(pos)
	
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
			var distance = pos.distance_to(hit_object.global_position)
			var damage_multiplier = 1.0 - (distance / explosion_radius)
			var final_damage = explosive_damage * damage_multiplier
			hit_object.take_damage(final_damage)
			
			if hit_object.has_method("apply_knockback"):
				var knockback_dir = (hit_object.global_position - pos).normalized()
				hit_object.apply_knockback(knockback_dir * explosion_force * 0.5)

func reload():
	if reserve_ammo <= 0:
		return
	
	if current_ammo >= max_ammo:
		return
	
	is_reloading = true
	reload_started.emit()
	
	if animation_player and animation_player.has_animation("reload"):
		animation_player.play("reload")
	
	await get_tree().create_timer(reload_time, false).timeout
	
	var ammo_needed = max_ammo - current_ammo
	var ammo_to_add = min(ammo_needed, reserve_ammo)
	
	current_ammo += ammo_to_add
	reserve_ammo -= ammo_to_add
	
	is_reloading = false
	weapon_reloaded.emit()
	
	if has_node("GunPivot"):
		var gun_model = get_node("GunPivot")
		gun_model.rotation.z = 0
		
	var adjusted_reload = reload_time * Engine.time_scale
	await get_tree().create_timer(adjusted_reload, false).timeout

func spawn_tracer(from: Vector3, to: Vector3):
	var tracer = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.height = from.distance_to(to)
	mesh.top_radius = 0.015
	mesh.bottom_radius = 0.015
	tracer.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	material.emission_enabled = true
	material.emission = Color.YELLOW
	material.emission_energy_multiplier = 3.0
	tracer.material_override = material
	
	get_tree().root.add_child(tracer)
	tracer.global_position = from.lerp(to, 0.5)
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
	await get_tree().create_timer(0.03, false).timeout
	tracer.queue_free()

func spawn_explosive_tracer(from: Vector3, to: Vector3):
	var tracer = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.height = from.distance_to(to)
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.08
	tracer.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.ORANGE
	material.emission_enabled = true
	material.emission = Color.ORANGE
	material.emission_energy_multiplier = 4.0
	tracer.material_override = material
	
	get_tree().root.add_child(tracer)
	tracer.global_position = from.lerp(to, 0.5)
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
	await get_tree().create_timer(0.15, false).timeout
	tracer.queue_free()

func spawn_impact_effect(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 25
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.15
	material.direction = Vector3(0, 1, 0)
	material.spread = 60
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 12.0
	material.gravity = Vector3(0, -15, 0)
	material.scale_min = 0.08
	material.scale_max = 0.15
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.WHITE)
	gradient.add_point(0.3, Color.ORANGE)
	gradient.add_point(1.0, Color(0.3, 0.1, 0, 0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = pos
	
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	flash.mesh = sphere
	
	var flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.8, 0.3, 0.8)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color.ORANGE
	flash_mat.emission_energy_multiplier = 4.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	
	get_tree().root.add_child(flash)
	flash.global_position = pos
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.15).from(Vector3.ONE * 0.5)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.15)
	
	spawn_smoke_puff(pos)
	
	await get_tree().create_timer(0.6, false).timeout
	particles.queue_free()
	flash.queue_free()

func spawn_smoke_puff(pos: Vector3):
	var smoke = GPUParticles3D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.amount = 8
	smoke.lifetime = 1.0
	smoke.explosiveness = 0.8
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.1
	material.direction = Vector3(0, 1, 0)
	material.spread = 45
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0, 2, 0)
	material.damping_min = 1.0
	material.damping_max = 2.0
	
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0, 0.5))
	scale_curve.add_point(Vector2(1, 2.0))
	var curve_texture = CurveTexture.new()
	curve_texture.curve = scale_curve
	material.scale_curve = curve_texture
	material.scale_min = 0.2
	material.scale_max = 0.4
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.4, 0.4, 0.4, 0.8))
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	smoke.process_material = material
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3)
	smoke.draw_pass_1 = mesh
	
	get_tree().root.add_child(smoke)
	smoke.global_position = pos
	
	await get_tree().create_timer(1.5, false).timeout
	smoke.queue_free()

func spawn_explosion_effect(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 100
	particles.lifetime = 1.5
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 1.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 180
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 18.0
	material.gravity = Vector3(0, -20, 0)
	material.damping_min = 0.5
	material.damping_max = 1.5
	
	material.scale_min = 0.3
	material.scale_max = 0.6
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.WHITE)
	gradient.add_point(0.2, Color.ORANGE)
	gradient.add_point(0.5, Color(1, 0.3, 0, 1))
	gradient.add_point(1.0, Color(0.2, 0.1, 0, 0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3)
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = pos
	
	var flash = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = explosion_radius * 1.5
	sphere_mesh.height = explosion_radius * 3
	flash.mesh = sphere_mesh
	
	var flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1, 0.7, 0.3, 0.9)
	flash_material.emission_enabled = true
	flash_material.emission = Color.ORANGE
	flash_material.emission_energy_multiplier = 8.0
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_material
	
	get_tree().root.add_child(flash)
	flash.global_position = pos
	
	var ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.1
	ring_mesh.outer_radius = 0.3
	ring.mesh = ring_mesh
	
	var ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1, 0.5, 0.2, 0.7)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color.ORANGE
	ring_mat.emission_energy_multiplier = 5.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	
	get_tree().root.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3(0.1, 0.1, 0.1)
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.5).from(Vector3.ONE * 0.2)
	tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.5)
	
	tween.tween_property(ring, "scale", Vector3.ONE * explosion_radius * 2, 0.4)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
	
	await get_tree().create_timer(1.8, false).timeout
	particles.queue_free()
	flash.queue_free()
	ring.queue_free()
