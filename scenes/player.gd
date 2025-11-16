extends CharacterBody3D

# Movement - ULTRAKILL style
const WALK_SPEED = 10.0
const SPRINT_SPEED = 15.0
const SLIDE_SPEED = 18.0
const JUMP_VELOCITY = 6.5
const GROUND_ACCELERATION = 15.0
const GROUND_FRICTION = 8.0
const AIR_ACCELERATION = 12.0
const AIR_FRICTION = 2.0

# Slide
const SLIDE_DURATION = 0.8
const SLIDE_TRANSITION = 5.0
var slide_timer = 0.0
var is_sliding = false

# Dash
const DASH_SPEED = 25.0
const DASH_DURATION = 0.2
var dash_timer = 0.0
var is_dashing = false
var can_dash = true

# Mouse
const MOUSE_SENSITIVITY = 0.003

# Health
@export var max_health = 100
var health = max_health

# Physics
var gravity = 25.0
var wish_dir = Vector3.ZERO

# Camera shake
var camera_shake_intensity = 0.0
var camera_shake_decay = 5.0

# Camera tilt
var camera_tilt = 0.0
const MAX_TILT = 5.0
const TILT_SPEED = 8.0

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
	
	# Get weapon reference
	if weapon_holder.get_child_count() > 0:
		current_weapon = weapon_holder.get_child(0)
		if current_weapon.has_signal("weapon_fired"):
			current_weapon.weapon_fired.connect(_on_weapon_fired)
	
	# Initialize HUD
	if hud:
		hud.update_health(health)
		if current_weapon:
			hud.update_ammo(current_weapon.current_ammo, current_weapon.max_ammo)

func _input(event):
	if event is InputEventMouseMotion:
		mouse_motion = event.relative

func _physics_process(delta):
	# Mouse look
	handle_mouse_look()
	
	# Camera effects
	apply_camera_shake(delta)
	apply_camera_tilt(delta)
	
	# Dash
	if Input.is_action_just_pressed("sprint") and can_dash and not is_on_floor():
		start_dash()
	
	# Slide
	if Input.is_action_just_pressed("sprint") and is_on_floor() and not is_sliding:
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed > WALK_SPEED:
			start_slide()
	
	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0 or not Input.is_action_pressed("sprint"):
			end_slide()
	
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			end_dash()
	
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Jump
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			if is_sliding:
				end_slide()
	
	# Get input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Movement
	if is_dashing:
		# Dash maintains direction
		pass
	elif is_sliding:
		apply_slide_movement(delta)
	else:
		apply_ground_movement(delta)
	
	# Apply velocity
	move_and_slide()
	
	# Reset dash when touching ground
	if is_on_floor():
		can_dash = true
	
	# Update HUD
	if hud and current_weapon:
		hud.update_ammo(current_weapon.current_ammo, current_weapon.max_ammo)
	
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
	var target_speed = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	
	if is_on_floor():
		# Ground movement with momentum preservation
		if wish_dir:
			var accel = GROUND_ACCELERATION
			velocity.x = lerp(velocity.x, wish_dir.x * target_speed, accel * delta)
			velocity.z = lerp(velocity.z, wish_dir.z * target_speed, accel * delta)
		else:
			# Friction
			velocity.x = lerp(velocity.x, 0.0, GROUND_FRICTION * delta)
			velocity.z = lerp(velocity.z, 0.0, GROUND_FRICTION * delta)
	else:
		# Air control - maintain momentum but allow direction change
		if wish_dir:
			var current_speed = Vector2(velocity.x, velocity.z).length()
			var air_accel = AIR_ACCELERATION if current_speed < target_speed else AIR_ACCELERATION * 0.3
			
			velocity.x = lerp(velocity.x, wish_dir.x * max(current_speed, target_speed), air_accel * delta)
			velocity.z = lerp(velocity.z, wish_dir.z * max(current_speed, target_speed), air_accel * delta)
		else:
			# Air friction (minimal)
			velocity.x = lerp(velocity.x, velocity.x, 1.0 - (AIR_FRICTION * delta))
			velocity.z = lerp(velocity.z, velocity.z, 1.0 - (AIR_FRICTION * delta))

func start_slide():
	is_sliding = true
	slide_timer = SLIDE_DURATION
	
	# Crouch collision
	if collision_shape and collision_shape.shape:
		collision_shape.shape.height = original_collision_height * 0.5
		collision_shape.position.y = original_collision_height * 0.25
	
	# Camera down
	var tween = create_tween()
	tween.tween_property(camera, "position:y", original_camera_position.y - 0.5, 0.2)

func end_slide():
	is_sliding = false
	
	# Reset collision
	if collision_shape and collision_shape.shape:
		collision_shape.shape.height = original_collision_height
		collision_shape.position.y = original_collision_height * 0.5
	
	# Camera up
	var tween = create_tween()
	tween.tween_property(camera, "position:y", original_camera_position.y, 0.2)

func apply_slide_movement(delta):
	# Maintain and boost speed during slide
	var slide_direction = Vector3(velocity.x, 0, velocity.z).normalized()
	var current_speed = Vector2(velocity.x, velocity.z).length()
	
	# Gradually slow down but maintain high speed
	var target_speed = lerp(SLIDE_SPEED, WALK_SPEED, 1.0 - (slide_timer / SLIDE_DURATION))
	
	if wish_dir:
		# Allow slight direction change during slide
		slide_direction = lerp(slide_direction, wish_dir, 0.3 * delta)
	
	velocity.x = slide_direction.x * target_speed
	velocity.z = slide_direction.z * target_speed

func start_dash():
	is_dashing = true
	dash_timer = DASH_DURATION
	can_dash = false
	
	# Dash in camera forward direction or movement direction
	var dash_direction = wish_dir if wish_dir != Vector3.ZERO else -transform.basis.z
	dash_direction.y = 0
	dash_direction = dash_direction.normalized()
	
	velocity.x = dash_direction.x * DASH_SPEED
	velocity.z = dash_direction.z * DASH_SPEED
	velocity.y = 0  # Cancel vertical velocity
	
	add_camera_shake(0.15)

func end_dash():
	is_dashing = false

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
	# Tilt based on horizontal velocity
	var horizontal_velocity = Vector2(velocity.x, velocity.z)
	var strafe_input = Input.get_axis("move_left", "move_right")
	
	var target_tilt = -strafe_input * MAX_TILT
	camera_tilt = lerp(camera_tilt, target_tilt, TILT_SPEED * delta)
	
	camera.rotation.z = deg_to_rad(camera_tilt)

func add_camera_shake(intensity: float):
	camera_shake_intensity += intensity

func _on_weapon_fired():
	add_camera_shake(0.05)

func take_damage(amount):
	health -= amount
	add_camera_shake(0.2)
	if hud:
		hud.update_health(health)
	
	if health <= 0:
		die()

func die():
	print("Player died!")
