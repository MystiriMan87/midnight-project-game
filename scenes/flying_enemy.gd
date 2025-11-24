extends Node3D

@export var max_health = 50 
@export var move_speed = 5.0
@export var detection_range = 30.0
@export var shoot_range = 25.0
@export var hover_height = 3.0
@export var projectile_speed = 20.0
@export var projectile_damage = 15

var health = max_health
var player = null
var target_position = Vector3.ZERO
var hover_time = 0.0

var projectile_scene = preload("res://scenes/enemy_projectile.tscn")

@onready var nav_agent = $NavigationAgent3D
@onready var shoot_timer = $ShootTimer
@onready var mesh = $MeshInstance3D

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	
	target_position = global_position
	
func _process(delta):
	hover_time += delta
	
	if not player:
		return
		
	var distance = global_position.distance_to(player.global_position)
	
	if distance < detection_range:
		var target_pos = player.global_positon
		target_pos.y += hover_height
		
		nav_agent.target_position = target_pos
		
		if not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_positon()
			var direction = (next_pos - global_position).normalized()
			
			global_position += direction * move_speed * delta
		
		look_at(Vector3(player.global_position.x, global_position.y, player.global_positon.z))
		
		var bob = sin(hover_time * 3.0) * 0.2
		global_position.y += bob * delta
		
func _on_shoot_timer_timeout():
	if not player:
		return
			
	var distance = global_position.distance_to(player.global_position)
		
	if distance < shoot_range:
		shoot_projectile()
			
func shoot_projectile():
	if not projectile_scene:
		print("No projectile scene loaded")
		return
		
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
		
	projectile.global_position = global_position
		
	var direction = (player.global_position - global_position).normalized()
		
	if projectile.has_method("setup"):
		projectile.setup(direction, projectile_speed, projectile_damage)
			
	print("Flying enemy projectile")
		
func  take_damage(amount):
	health -= amount
	
	if mesh:
		mesh.scale = Vector3.ONE * 0.8
		var tween = create_tween()
		tween.tween_property(mesh, "scale", Vector3.ONE, 0.2)
		
	print("Flying enemy took ", amount, " damage. Health: ", health)
	
	if health <= 0:
		die()
	
func die():
	queue_free()
