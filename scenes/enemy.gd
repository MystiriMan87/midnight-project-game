extends CharacterBody3D

@export var max_health = 100
@export var move_speed = 3.0
@export var detection_range = 20.0

var health = max_health
var player = null
var gravity = 20.0

@onready var nav_agent = $NavigationAgent3D

func _ready():
	# Find player
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Chase player if in range
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
				
				# Look at player
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	
	move_and_slide()

func take_damage(amount):
	health -= amount
	print("Enemy took ", amount, " damage. Health: ", health)
	
	if health <= 0:
		die()

func die():
	queue_free()
