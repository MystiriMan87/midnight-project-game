extends CharacterBody3D

signal died

@export var max_health = 100
@export var move_speed = 3.0
@export var detection_range = 20.0

var health = max_health
var player = null
var gravity = 20.0
var knockback_velocity = Vector3.ZERO
var is_dead = false

@onready var nav_agent = $NavigationAgent3D
@onready var model = get_node_or_null("Unarmed_Walk_Forward")
@onready var anim_player = get_node_or_null("Unarmed_Walk_Forward/AnimationPlayer")
@onready var skeleton = get_node_or_null("Unarmed_Walk_Forward/Armature/Skeleton3D")
@onready var collision_shape = $CollisionShape3D


func _ready():
	if skeleton:
		skeleton.physical_bones_stop_simulation()
		print("✓ Physical bones disabled at start")

	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	add_to_group("enemy")

	if anim_player:
		if anim_player.has_animation("mixamo_com"):
			anim_player.play("mixamo_com")


func _physics_process(delta):
	if is_dead:
		return

	# basic gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 3.0 * delta)
	velocity += knockback_velocity * delta * 10.0

	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player:
		var distance = global_position.distance_to(player.global_position)

		if distance < detection_range:
			nav_agent.target_position = player.global_position

			if nav_agent.is_navigation_finished():
				velocity.x = 0
				velocity.z = 0

				if anim_player:
					anim_player.pause()
			else:
				var next_pos = nav_agent.get_next_path_position()
				var direction = (next_pos - global_position).normalized()

				velocity.x = direction.x * move_speed
				velocity.z = direction.z * move_speed

				if anim_player and anim_player.has_animation("mixamo_com"):
					if not anim_player.is_playing():
						anim_player.play("mixamo_com")

				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))

	move_and_slide()


func take_damage(amount):
	if is_dead:
		return

	health -= amount
	if health <= 0:
		die()


func apply_knockback(force: Vector3):
	if is_dead:
		return
	knockback_velocity = force


func die():
	if is_dead:
		return

	is_dead = true
	died.emit()

	set_physics_process(false)
	set_process(false)
	set_physics_process_internal(false)

	velocity = Vector3.ZERO

	if nav_agent:
		nav_agent.enabled = false
		nav_agent.velocity = Vector3.ZERO

	if collision_shape:
		collision_shape.disabled = true

	# Remove all collision for safety
	collision_layer = 0
	collision_mask = 0

	# optional: shake screen
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("shake_from_position"):
		player_node.shake_from_position(global_position, 15.0)

	spawn_death_explostion()

	if skeleton:
		activate_ragdoll()
		await get_tree().create_timer(5.0).timeout
		queue_free()
	else:
		queue_free()



func activate_ragdoll():
	if anim_player:
		anim_player.stop()

	if not skeleton:
		print("ERROR: No skeleton for ragdoll!")
		return

	skeleton.physical_bones_start_simulation()

	await get_tree().process_frame

	# Small impulse so the body collapses naturally
	for bone in skeleton.get_children():
		if bone is PhysicalBone3D:
			bone.apply_central_impulse(Vector3(0, 1.5, 0))

	await get_tree().process_frame
	await get_tree().process_frame


	print("✓ Ragdoll activated")


func spawn_death_explostion():
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
	gradient.add_point(0.0, Color.RED)
	gradient.add_point(0.3, Color(0.8, 0.1, 0.1, 1))
	gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.2, 0.3)
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
	flash_mat.albedo_color = Color(1, 0.2, 0.2, 0.8)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color.RED
	flash_mat.emission_energy_multiplier = 5.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat

	get_tree().root.add_child(flash)
	flash.global_position = global_position

	var tween = create_tween()
	tween.se_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.3).from(Vector3.ONE * 0.3)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)

	await get_tree().create_timer(1.2).timeout
	particles.queue_free()
	flash.queue_free()


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
