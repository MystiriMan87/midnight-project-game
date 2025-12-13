extends CharacterBody3D

@export var max_health: int = 100
@export var move_speed: float = 3.0
@export var detection_range: float = 20.0
@export var gravity: float = 20.0

var health: int
var is_dead: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO
var player = null

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var skeleton: Skeleton3D = _get_skeleton()
@onready var anim_player: AnimationPlayer = _get_animation_player()

func _get_skeleton() -> Skeleton3D:
	var skel = get_node_or_null("Unarmed_Walk_Forward/Armature/Skeleton3D")
	if skel:
		return skel
	skel = get_node_or_null("Armature/Skeleton3D")
	if skel:
		return skel
	return get_node_or_null("Skeleton3D")

func _get_animation_player() -> AnimationPlayer:
	var anim = get_node_or_null("Unarmed_Walk_Forward/AnimationPlayer")
	if anim:
		return anim
	return get_node_or_null("AnimationPlayer")

func _ready() -> void:
	health = max_health
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	add_to_group("enemy")
	if anim_player and anim_player.has_animation("mixamo_com"):
		anim_player.play("mixamo_com")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 3.0 * delta)
	velocity += knockback_velocity * delta * 10.0

	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player:
		var distance = global_position.distance_to(player.global_position)
		if distance < detection_range:
			if nav_agent:
				nav_agent.target_position = player.global_position
			if nav_agent and not nav_agent.is_navigation_finished():
				var next_pos = nav_agent.get_next_path_position()
				var dir = (next_pos - global_position)
				if dir.length() > 0.01:
					dir = dir.normalized()
					velocity.x = dir.x * move_speed
					velocity.z = dir.z * move_speed
					if anim_player and anim_player.has_animation("mixamo_com") and not anim_player.is_playing():
						anim_player.play("mixamo_com")
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
			else:
				velocity.x = 0
				velocity.z = 0
				if anim_player:
					anim_player.pause()

	move_and_slide()

func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	
	var hitmarker = get_tree().get_first_node_in_group("hitmarker")
	if hitmarker:
		hitmarker.show_hit(health <= 0)
	
	if health <= 0:
		die()

func apply_knockback(force: Vector3) -> void:
	if is_dead:
		return
	knockback_velocity = force

func die() -> void:
	if is_dead:
		return
	is_dead = true
	
	if anim_player:
		anim_player.stop()
	
	if collision_shape:
		collision_shape.disabled = true
	
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	
	if nav_agent:
		nav_agent.set_target_position(global_position)  
		nav_agent.set_velocity(Vector3.ZERO)
	
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake_from_position"):
		p.shake_from_position(global_position, 15.0)
	
	_spawn_death_particles()
	
	queue_free()

func _spawn_death_particles() -> void:
	var particles = GPUParticles3D.new()
	get_parent().add_child(particles)
	particles.global_position = global_position
	
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 50
	particles.lifetime = 1.0
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -9.8, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.0, 0.0, 1.0))  # Red
	gradient.set_color(1, Color(0.5, 0.0, 0.0, 0.0))  # Fade to transparent
	material.color_ramp = gradient
	
	particles.process_material = material
	particles.draw_pass_1 = SphereMesh.new()
	
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()
