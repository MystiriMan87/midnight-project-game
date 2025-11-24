extends Node3D

@export var max_health = 50
@export var move_speed = 8.0
@export var detection_range = 30.0
@export var shoot_range = 30.0
@export var hover_height = 4.0
@export var projectile_speed = 30.0
@export var projectile_damage = 15
@export var keep_distance = 15.0

var health = max_health
var player = null
var hover_time = 0.0

var projectile_scene = preload("res://scenes/enemy_projectile.tscn")

@onready var shoot_timer = $ShootTimer
@onready var mesh = $MeshInstance3D

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	if shoot_timer:
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)

func _process(delta):
	hover_time += delta
	
	if not player:
		return
	
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player < detection_range:
		var target_pos = player.global_position
		target_pos.y += hover_height
		
		var direction = (target_pos - global_position).normalized()
		
		if distance_to_player > keep_distance:
			global_position += direction * move_speed * delta
		elif distance_to_player < keep_distance - 2.0:
			global_position -= direction * move_speed * delta
		
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
		
		var bob = sin(hover_time * 3.0) * 0.15
		global_position.y += bob * delta

func _on_shoot_timer_timeout():
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance < shoot_range:
		shoot_projectile()

func shoot_projectile():
	if not projectile_scene:
		print("No projectile scene loaded!")
		return
	
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
	
	projectile.global_position = global_position
	
	var direction = (player.global_position - global_position).normalized()
	
	if projectile.has_method("setup"):
		projectile.setup(direction, projectile_speed, projectile_damage)

func take_damage(amount):
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
