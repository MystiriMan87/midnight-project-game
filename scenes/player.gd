extends CharacterBody3D

# Movement - Faster and more fluid
const WALK_SPEED = 12.0
const SPRINT_SPEED = 20.0
const SLIDE_SPEED = 25.0
const JUMP_VELOCITY = 7.0
const GROUND_ACCELERATION = 20.0  # Faster acceleration
const GROUND_FRICTION = 10.0
const AIR_ACCELERATION = 15.0  # Better air control
const AIR_FRICTION = 1.0

# Slide
const SLIDE_DURATION = 1.0
const SLIDE_TRANSITION = 5.0
var slide_timer = 0.0
var is_sliding = false
var slide_direction = Vector3.ZERO

# Dash
const DASH_SPEED = 30.0
const DASH_DURATION = 0.25
var dash_timer = 0.0
var is_dashing = false
var can_dash = true
var dash_direction = Vector3.ZERO

# Bunny hop / momentum preservation
var last_jump_time = 0.0
const BHOP_WINDOW = 0.1
const SPEED_BOOST_MULTIPLIER = 1.15

# Mouse
const MOUSE_SENSITIVITY = 0.003

# Health
@export var max_health = 100
var health = max_health

# Physics
var gravity = 30.0
var wish_dir = Vector3.ZERO

# Camera shake
var camera_shake_intensity = 0.0
var camera_shake_decay = 8.0

# Camera tilt
var camera_tilt = 0.0
const MAX_TILT = 8.0
const TILT_SPEED = 12.0

# FOV changes for speed
const BASE_FOV = 90.0
const SPRINT_FOV = 100.0
const SLIDE_FOV = 105.0
var target_fov = BASE_FOV

# Knockback
var knockback_velocity = Vector3.ZERO

# References
@onready var camera = $Camera3D
@onready var weapon_holder = $Camera3D/WeaponHolder
@onready var hud = $CanvasLayer/HUD
@onready var collision_shape = $CollisionShape3D

# State
var mouse_motion = Vector2.ZERO
var current_weapon = null
var original_camera_position = Vector3.ZERO
var original_camera_rotation = Vector3.ZERO
var original_collision_height = 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	
	# Store originals
	original_camera_position = camera.position
	original_camera_rotation = camera.rotation
	if collision_shape and collision_shape.shape:
		original_collision_height = collision_shape.shape.height
	
	# Set initial FOV
	camera.fov = BASE_FOV
	
	# Wait a frame for everything to be ready
	await get_tree().process_frame
	
	# Get weapon reference
	if weapon_holder.get_child_count() > 0:
		current_weapon = weapon_holder.get_child(0)
		
		# Only connect if weapon exists
		if current_weapon != null:
			if current_weapon.has_signal("weapon_fired"):
				current_weapon.weapon_fired.connect(_on_weapon_fired)
			if current_weapon.has_signal("weapon_reloaded"):
				current_weapon.weapon_reloaded.connect(_on_weapon_reloaded)
	
	# Initialize HUD
	if hud:
		hud.update_health(health)
		if current_weapon:
			hud.update_ammo(current_weapon.current_ammo, current_weapon.max_ammo, current_weapon.reserve_ammo)

func _input(event):
	if event is InputEventMouseMotion:
		mouse_motion = event.relative

func _physics_process(delta):
	# Mouse look
	handle_mouse_look()
	
	# Camera effects
	apply_camera_shake(delta)
	apply_camera_tilt(delta)
	apply_fov_change(delta)
	
	# Dash (in air or ground)
	if Input.is_action_just_pressed("sprint") and can_dash and not is_sliding:
		start_dash()
	
	# Slide (ground only, while moving)
	if Input.is_action_pressed("sprint") and is_on_floor() and not is_sliding and not is_dashing:
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed > WALK_SPEED * 0.8:
			start_slide()
	
	# Update slide
	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0 or not Input.is_action_pressed("sprint"):
			end_slide()
	
	# Update dash
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			end_dash()
	
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Decay knockback
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 5.0 * delta)
	
	# Jump with bunny hop boost
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			
			# Bunny hop: if jumped recently, get speed boost
			var time_since_jump = Time.get_ticks_msec() / 1000.0 - last_jump_time
			if time_since_jump < BHOP_WINDOW:
				var horizontal_vel = Vector2(velocity.x, velocity.z)
				horizontal_vel *= SPEED_BOOST_MULTIPLIER
				velocity.x = horizontal_vel.x
				velocity.z = horizontal_vel.y
				print("BHOP BOOST!")
			
			last_jump_time = Time.get_ticks_msec() / 1000.0
			
			if is_sliding:
				end_slide()
	
	# Get input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Movement
	if is_dashing:
		# Maintain dash velocity
		pass
	elif is_sliding:
		apply_slide_movement(delta)
	else:
		apply_ground_movement(delta)
	
	# Apply velocity
	move_and_slide()
	
	# Reset dash when touching ground
	if is_on_floor() and not can_dash:
		can_dash = true
	
	# Update HUD
	if hud and current_weapon:
		hud.update_ammo(current_weapon.current_ammo, current_weapon.max_ammo, current_weapon.reserve_ammo)
	
	# ESC to free mouse
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func handle_mouse_look():
	if mouse_motion != Vector2.ZERO:
		rotate_y(-mouse_motion.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-mouse_motion.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(89), deg_to_rad(89))
		mouse_motion = Vector2.ZERO

func apply_ground_movement(delta):
	var is_sprinting = Input.is_action_pressed("sprint") and wish_dir != Vector3.ZERO
	var target_speed = SPRINT_SPEED if is_sprinting else WALK_SPEED
	
	if is_on_floor():
		# Ground movement with quick acceleration
		if wish_dir:
			var accel = GROUND_ACCELERATION
			velocity.x = lerp(velocity.x, wish_dir.x * target_speed, accel * delta)
			velocity.z = lerp(velocity.z, wish_dir.z * target_speed, accel * delta)
		else:
			# Friction
			velocity.x = lerp(velocity.x, 0.0, GROUND_FRICTION * delta)
			velocity.z = lerp(velocity.z, 0.0, GROUND_FRICTION * delta)
	else:
		# Air control - ULTRAKILL style momentum preservation
		if wish_dir:
			var current_speed = Vector2(velocity.x, velocity.z).length()
			var target_air_speed = max(current_speed, target_speed)
			
			# Strong air control
			velocity.x = lerp(velocity.x, wish_dir.x * target_air_speed, AIR_ACCELERATION * delta)
			velocity.z = lerp(velocity.z, wish_dir.z * target_air_speed, AIR_ACCELERATION * delta)
		else:
			# Minimal air friction to preserve momentum
			velocity.x = lerp(velocity.x, velocity.x, 1.0 - (AIR_FRICTION * delta))
			velocity.z = lerp(velocity.z, velocity.z, 1.0 - (AIR_FRICTION * delta))

func start_slide():
	is_sliding = true
	slide_timer = SLIDE_DURATION
	
	# Store slide direction based on current velocity
	slide_direction = Vector3(velocity.x, 0, velocity.z).normalized()
	if slide_direction == Vector3.ZERO:
		slide_direction = -transform.basis.z
	
	# Boost speed
	var boost_speed = max(Vector2(velocity.x, velocity.z).length(), SLIDE_SPEED)
	velocity.x = slide_direction.x * boost_speed
	velocity.z = slide_direction.z * boost_speed
	
	# Crouch collision
	if collision_shape and collision_shape.shape:
		collision_shape.shape.height = original_collision_height * 0.5
		collision_shape.position.y = original_collision_height * 0.25
	
	# Camera down quickly
	var tween = create_tween()
	tween.tween_property(camera, "position:y", original_camera_position.y - 0.6, 0.15)
	
	# Set FOV
	target_fov = SLIDE_FOV
	
	add_camera_shake(0.1)

func end_slide():
	is_sliding = false
	
	# Reset collision
	if collision_shape and collision_shape.shape:
		collision_shape.shape.height = original_collision_height
		collision_shape.position.y = original_collision_height * 0.5
	
	# Camera up
	var tween = create_tween()
	tween.tween_property(camera, "position:y", original_camera_position.y, 0.2)
	
	# Reset FOV
	target_fov = BASE_FOV

func apply_slide_movement(delta):
	# Allow direction adjustment during slide
	if wish_dir != Vector3.ZERO:
		slide_direction = lerp(slide_direction, wish_dir, 2.0 * delta).normalized()
	
	# Maintain speed with slight decay
	var slide_progress = 1.0 - (slide_timer / SLIDE_DURATION)
	var current_speed = lerp(SLIDE_SPEED, SPRINT_SPEED, slide_progress)
	
	velocity.x = slide_direction.x * current_speed
	velocity.z = slide_direction.z * current_speed

func start_dash():
	is_dashing = true
	dash_timer = DASH_DURATION
	can_dash = false
	
	# Dash in movement direction or camera direction
	dash_direction = wish_dir if wish_dir != Vector3.ZERO else -transform.basis.z
	dash_direction.y = 0
	dash_direction = dash_direction.normalized()
	
	velocity.x = dash_direction.x * DASH_SPEED
	velocity.z = dash_direction.z * DASH_SPEED
	velocity.y = 0  # Cancel vertical velocity
	
	add_camera_shake(0.2)
	print("DASH!")

func end_dash():
	is_dashing = false
	# Don't kill velocity - maintain momentum!

func apply_camera_shake(delta):
	camera_shake_intensity = lerp(camera_shake_intensity, 0.0, camera_shake_decay * delta)
	
	if camera_shake_intensity > 0.01:
		var shake_offset = Vector3(
			randf_range(-1, 1) * camera_shake_intensity,
			randf_range(-1, 1) * camera_shake_intensity,
			0
		)
		camera.position = original_camera_position + shake_offset
	else:
		if not is_sliding:
			camera.position = original_camera_position

func apply_camera_tilt(delta):
	# Tilt based on strafe input
	var strafe_input = Input.get_axis("move_left", "move_right")
	
	var target_tilt = -strafe_input * MAX_TILT
	camera_tilt = lerp(camera_tilt, target_tilt, TILT_SPEED * delta)
	
	camera.rotation.z = deg_to_rad(camera_tilt)

func apply_fov_change(delta):
	# Dynamic FOV based on movement state
	if is_sliding:
		target_fov = SLIDE_FOV
	elif Input.is_action_pressed("sprint") and wish_dir != Vector3.ZERO:
		target_fov = SPRINT_FOV
	else:
		target_fov = BASE_FOV
	
	camera.fov = lerp(camera.fov, target_fov, 8.0 * delta)

func add_camera_shake(intensity: float):
	camera_shake_intensity += intensity

func apply_knockback(force: Vector3):
	knockback_velocity = force
	velocity += knockback_velocity
	add_camera_shake(0.3)

func _on_weapon_fired():
	add_camera_shake(0.05)

func _on_weapon_reloaded():
	print("Weapon reloaded!")
	add_camera_shake(0.08)

func take_damage(amount):
	health -= amount
	add_camera_shake(0.25)
	if hud:
		hud.update_health(health)
	
	if health <= 0:
		die()

func die():
	print("Player died!")
