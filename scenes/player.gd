extends CharacterBody3D

const WALK_SPEED = 10.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 8.5
const GROUND_ACCEL = 50.0
const FRICTION = 6.0
const AIR_ACCEL = 15.0
const AIR_STRAFE_ACCEL = 25.0
const MAX_AIR_SPEED = 15.0

const SLIDE_SPEED_BOOST = 1.5
const SLIDE_FRICTION = 2.0
var is_sliding = false
var slide_time = 0.0
const MAX_SLIDE_TIME = 0.6

const DASH_SPEED = 28.0
const DASH_TIME = 0.15
const MAX_CONSECUTIVE_DASHES = 3
const DASH_RESET_TIME = 0.8
var dash_timer = 0.0
var dash_reset_timer = 0.0
var dash_cooldown_timer = 0.0
var is_dashing = false
var dash_direction = Vector3.ZERO
var consecutive_dashes = 0

var last_jump_time = 0.0
const BHOP_WINDOW = 0.1
const SPEED_BOOST_MULTIPLIER = 1.15

const MOUSE_SENSITIVITY = 0.003
const LOOK_UP_LIMIT = -80.0
const LOOK_DOWN_LIMIT = 80.0

const TIME_SLOW_SCALE = 0.3
const TIME_SLOW_DURATION = 5.0
const TIME_SLOW_COOLDOWN = 10.0

var time_slow_active = false
var time_slow_timer = 0.0
var time_slow_cooldown_timer = 0.0
var can_use_time_slow = true

@export var max_health = 100
var health = max_health

const NORMAL_GRAVITY = 25.0
var gravity = NORMAL_GRAVITY
var wish_dir = Vector3.ZERO

var camera_shake_intensity = 0.0
var camera_shake_decay = 8.0

var camera_tilt = 0.0
const MAX_TILT = 3.0
const TILT_SPEED = 10.0

var camera_pitch = 0.0

const BASE_FOV = 90.0
const SPEED_FOV_MULTIPLIER = 0.05
var target_fov = BASE_FOV

var knockback_velocity = Vector3.ZERO

@onready var camera = $Camera3D
@onready var weapon_holder = $Camera3D/WeaponHolder
@onready var collision_shape = $CollisionShape3D

var hud = null
var current_weapon = null
var mouse_motion = Vector2.ZERO
var original_camera_position = Vector3.ZERO
var original_collision_height = 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	
	original_camera_position = camera.position
	if collision_shape and collision_shape.shape:
		original_collision_height = collision_shape.shape.height
	
	camera.fov = BASE_FOV
	
	await get_tree().process_frame
	
	hud = get_node_or_null("CanvasLayer/HUD")
	if not hud:
		var canvas_layer = get_node_or_null("CanvasLayer")
		if canvas_layer:
			for child in canvas_layer.get_children():
				if child.name == "HUD" or child is Control:
					hud = child
					break
	
	if weapon_holder.get_child_count() > 0:
		current_weapon = weapon_holder.get_child(0)
		
		if current_weapon != null:
			if current_weapon.has_signal("weapon_fired"):
				current_weapon.weapon_fired.connect(_on_weapon_fired)
			if current_weapon.has_signal("weapon_reloaded"):
				current_weapon.weapon_reloaded.connect(_on_weapon_reloaded)
			if current_weapon.has_signal("reload_started"):
				current_weapon.reload_started.connect(_on_reload_started)
	
	update_hud()

func update_hud():
	if not hud:
		return
	
	hud.update_health(health, max_health)
	
	if current_weapon:
		hud.update_ammo(current_weapon.current_ammo, current_weapon.max_ammo, current_weapon.reserve_ammo)
	
	if hud.has_method("update_time_slow_cooldown"):
		if time_slow_cooldown_timer > 0:
			hud.update_time_slow_cooldown(time_slow_cooldown_timer, TIME_SLOW_COOLDOWN)
		else:
			hud.update_time_slow_cooldown(0, TIME_SLOW_COOLDOWN)

func _input(event):
	if event is InputEventMouseMotion:
		mouse_motion = event.relative

func _physics_process(delta):
	handle_mouse_look()
	apply_camera_effects(delta)
	
	handle_time_slow(delta)
	
	# Apply gravity ALWAYS at normal rate
	if not is_on_floor():
		velocity.y -= NORMAL_GRAVITY * delta
	
	# Knockback at normal rate
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 5.0 * delta)
	
	if dash_reset_timer > 0:
		dash_reset_timer -= delta
		if dash_reset_timer <= 0:
			consecutive_dashes = 0
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	# Jump at full strength regardless of time scale
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
		var time_since_jump = Time.get_ticks_msec() / 1000.0 - last_jump_time
		if time_since_jump < BHOP_WINDOW:
			var horizontal_vel = Vector2(velocity.x, velocity.z)
			horizontal_vel *= SPEED_BOOST_MULTIPLIER
			velocity.x = horizontal_vel.x
			velocity.z = horizontal_vel.y
		
		last_jump_time = Time.get_ticks_msec() / 1000.0
		
		if is_sliding:
			end_slide()
	
	if Input.is_action_just_pressed("sprint") and consecutive_dashes < MAX_CONSECUTIVE_DASHES and dash_cooldown_timer <= 0 and not is_sliding and not is_dashing:
		start_dash()
	
	if Input.is_action_just_pressed("sprint") and is_on_floor() and not is_sliding:
		var speed = Vector2(velocity.x, velocity.z).length()
		if speed > 5.0:
			start_slide()
	
	if is_on_floor():
		consecutive_dashes = 0
		dash_cooldown_timer = 0.0
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_sliding:
		slide_time += delta
		if slide_time > MAX_SLIDE_TIME or not Input.is_action_pressed("sprint"):
			end_slide()
		update_slide(delta)
	elif is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			end_dash()
	else:
		handle_movement(delta)
	
	move_and_slide()
	update_hud()
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func handle_mouse_look():
	if mouse_motion != Vector2.ZERO:
		rotate_y(-mouse_motion.x * MOUSE_SENSITIVITY)
		
		camera_pitch -= mouse_motion.y * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch, deg_to_rad(LOOK_UP_LIMIT), deg_to_rad(LOOK_DOWN_LIMIT))
		
		camera.rotation.x = camera_pitch
		camera.rotation.y = 0
		
		mouse_motion = Vector2.ZERO

func handle_movement(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		if direction:
			var target_vel = direction * WALK_SPEED
			velocity.x = lerp(velocity.x, target_vel.x, GROUND_ACCEL * delta)
			velocity.z = lerp(velocity.z, target_vel.z, GROUND_ACCEL * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, FRICTION * delta)
			velocity.z = lerp(velocity.z, 0.0, FRICTION * delta)
	else:
		if direction:
			var current_speed = Vector2(velocity.x, velocity.z).length()
			
			if current_speed < MAX_AIR_SPEED:
				var accel = AIR_STRAFE_ACCEL if input_dir.x != 0 else AIR_ACCEL
				velocity.x = lerp(velocity.x, direction.x * WALK_SPEED, accel * delta)
				velocity.z = lerp(velocity.z, direction.z * WALK_SPEED, accel * delta)
			else:
				var wish_vel = direction * current_speed
				velocity.x = lerp(velocity.x, wish_vel.x, 2.0 * delta)
				velocity.z = lerp(velocity.z, wish_vel.z, 2.0 * delta)

func start_slide():
	is_sliding = true
	slide_time = 0.0
	
	var current_speed = Vector2(velocity.x, velocity.z).length()
	var slide_dir = Vector3(velocity.x, 0, velocity.z).normalized()
	if slide_dir == Vector3.ZERO:
		slide_dir = -transform.basis.z
	
	var boosted_speed = max(current_speed, WALK_SPEED) * SLIDE_SPEED_BOOST
	velocity.x = slide_dir.x * boosted_speed
	velocity.z = slide_dir.z * boosted_speed
	
	if collision_shape and collision_shape.shape:
		collision_shape.shape.height = original_collision_height * 0.5
		collision_shape.position.y = original_collision_height * 0.25
	
	var tween = create_tween()
	tween.tween_property(camera, "position:y", original_camera_position.y - 0.5, 0.1)

func end_slide():
	is_sliding = false
	reset_collision()
	
	var tween = create_tween()
	tween.tween_property(camera, "position:y", original_camera_position.y, 0.15)

func reset_collision():
	if collision_shape and collision_shape.shape:
		collision_shape.shape.height = original_collision_height
		collision_shape.position.y = original_collision_height * 0.5

func update_slide(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir_temp = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if wish_dir_temp != Vector3.ZERO:
		var current_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		var new_dir = current_dir.lerp(wish_dir_temp, 3.0 * delta).normalized()
		var speed = Vector2(velocity.x, velocity.z).length()
		velocity.x = new_dir.x * speed
		velocity.z = new_dir.z * speed
	
	var friction = SLIDE_FRICTION * delta * 60
	velocity.x = move_toward(velocity.x, velocity.x * 0.95, friction)
	velocity.z = move_toward(velocity.z, velocity.z * 0.95, friction)

func start_dash():
	is_dashing = true
	dash_timer = DASH_TIME
	consecutive_dashes += 1
	dash_cooldown_timer = DASH_RESET_TIME
	
	dash_direction = wish_dir if wish_dir != Vector3.ZERO else -transform.basis.z
	dash_direction.y = 0
	dash_direction = dash_direction.normalized()
	
	velocity.x = dash_direction.x * DASH_SPEED
	velocity.z = dash_direction.z * DASH_SPEED
	velocity.y = 0
	
	add_camera_shake(0.2)

func end_dash():
	is_dashing = false

func handle_time_slow(delta):
	if time_slow_cooldown_timer > 0:
		time_slow_cooldown_timer -= delta
		if time_slow_cooldown_timer <= 0:
			can_use_time_slow = true
	
	if Input.is_action_just_pressed("time_slow") and can_use_time_slow and not time_slow_active:
		activate_time_slow()
	
	if time_slow_active:
		time_slow_timer -= delta
		
		if hud and hud.has_method("update_time_slow"):
			hud.update_time_slow(time_slow_timer, TIME_SLOW_DURATION)
		
		if time_slow_timer <= 0:
			deactivate_time_slow()

func activate_time_slow():
	time_slow_active = true
	time_slow_timer = TIME_SLOW_DURATION
	can_use_time_slow = false
	
	Engine.time_scale = TIME_SLOW_SCALE
	
	apply_time_slow_effect()
	add_camera_shake(0.15)
	
	print("TIME SLOW ACTIVATED!")

func deactivate_time_slow():
	time_slow_active = false
	time_slow_cooldown_timer = TIME_SLOW_COOLDOWN
	
	Engine.time_scale = 1.0
	
	if hud and hud.has_node("TimeSlowOverlay"):
		hud.get_node("TimeSlowOverlay").queue_free()
	
	add_camera_shake(0.1)
	
	print("Time slow ended. Cooldown: ", TIME_SLOW_COOLDOWN, "s")

func apply_time_slow_effect():
	if not hud:
		return
	
	var overlay = ColorRect.new()
	overlay.name = "TimeSlowOverlay"
	overlay.color = Color(0.3, 0.5, 1.0, 0.15)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	
	hud.add_child(overlay)

func apply_camera_effects(delta):
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
	
	var strafe_input = Input.get_axis("move_left", "move_right")
	var target_tilt = -strafe_input * MAX_TILT
	camera_tilt = lerp(camera_tilt, target_tilt, TILT_SPEED * delta)
	
	camera.rotation.x = camera_pitch
	camera.rotation.y = 0
	camera.rotation.z = deg_to_rad(camera_tilt)
	
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	target_fov = BASE_FOV + (horizontal_speed * SPEED_FOV_MULTIPLIER)
	target_fov = clamp(target_fov, BASE_FOV, BASE_FOV + 15)
	camera.fov = lerp(camera.fov, target_fov, 5.0 * delta)

func add_camera_shake(intensity: float):
	camera_shake_intensity += intensity

func apply_knockback(force: Vector3):
	# Knockback is NOT affected by time scale
	knockback_velocity = force
	velocity += knockback_velocity
	add_camera_shake(0.3)

func shake_from_position(explosion_pos: Vector3, max_distance: float = 20.0):
	var distance = global_position.distance_to(explosion_pos)
	if distance < max_distance:
		var intensity = 1.0 - (distance / max_distance)
		add_camera_shake(0.15 * intensity)

func _on_weapon_fired():
	add_camera_shake(0.05)

func _on_weapon_reloaded():
	add_camera_shake(0.08)
	if hud:
		hud.hide_reloading()

func _on_reload_started():
	if hud:
		hud.show_reloading()

func take_damage(amount):
	health -= amount
	
	if hud:
		if health <= 30:
			hud.flash_low_health()
	
	add_camera_shake(0.25)
	update_hud()
	
	if health <= 0:
		die()

func die():
	print("Player died!")
