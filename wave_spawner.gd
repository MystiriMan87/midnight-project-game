extends Node3D

@export var enemy_scene: PackedScene
@export var flying_enemy_scene: PackedScene
@export var ground_enemies_per_wave = 3
@export var flying_enemies_per_wave = 2
@export var time_between_waves = 20.0
@export var spawn_radius = 10.0
@export var increase_difficulty = true

var current_wave = 0
var enemies_alive = 0
var wave_active = false
var hud = null

func _ready():
	await get_tree().process_frame
	
	# Find HUD - try multiple methods
	var player = get_tree().get_first_node_in_group("player")
	if player:
		hud = player.get_node_or_null("CanvasLayer/HUD")
		if hud:
			print("✓ HUD found via player")
		else:
			print("✗ HUD not found at player/CanvasLayer/HUD")
	
	# Fallback: search entire tree
	if not hud:
		for node in get_tree().get_nodes_in_group("hud"):
			hud = node
			print("✓ HUD found via group")
			break
	
	if not hud:
		print("✗ WARNING: HUD not found! Wave display won't work")
	
	start_wave()

func start_wave():
	current_wave += 1
	wave_active = true
	enemies_alive = 0
	
	var ground_count = ground_enemies_per_wave
	var flying_count = flying_enemies_per_wave
	
	if increase_difficulty:
		ground_count += (current_wave - 1)
		flying_count += (current_wave - 1) / 2
	
	print("=== WAVE ", current_wave, " ===")
	print("Ground enemies: ", ground_count)
	print("Flying enemies: ", flying_count)
	
	# Update HUD
	if hud:
		if hud.has_method("update_wave"):
			hud.update_wave(current_wave)
			print("✓ Updated HUD to wave ", current_wave)
		else:
			print("✗ HUD doesn't have update_wave method!")
	else:
		print("✗ No HUD reference!")
	
	# Spawn ground enemies
	for i in ground_count:
		if enemy_scene:
			spawn_enemy(enemy_scene, false)
			await get_tree().create_timer(0.5).timeout
	
	# Spawn flying enemies
	for i in flying_count:
		if flying_enemy_scene:
			spawn_enemy(flying_enemy_scene, true)
			await get_tree().create_timer(0.5).timeout
	
	# Update HUD with enemy count
	update_hud_enemy_count()

func spawn_enemy(scene: PackedScene, is_flying: bool):
	if not scene:
		return
	
	var enemy = scene.instantiate()
	get_tree().root.add_child(enemy)
	
	var random_offset = Vector3(
		randf_range(-spawn_radius, spawn_radius),
		0,
		randf_range(-spawn_radius, spawn_radius)
	)
	
	var spawn_pos = global_position + random_offset
	
	if is_flying:
		spawn_pos.y += 5.0
	
	enemy.global_position = spawn_pos
	
	enemies_alive += 1
	
	spawn_effect(spawn_pos)
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
		print("✓ Connected to enemy died signal")
	else:
		print("⚠ Enemy has no died signal, using fallback")
		check_enemy_alive(enemy)

func check_enemy_alive(enemy):
	while enemy and is_instance_valid(enemy):
		await get_tree().create_timer(0.5).timeout
	
	if not is_instance_valid(enemy):
		_on_enemy_died()

func _on_enemy_died():
	enemies_alive -= 1
	
	print("Enemies remaining: ", enemies_alive)
	
	# Update HUD
	update_hud_enemy_count()
	
	if enemies_alive <= 0 and wave_active:
		wave_active = false
		print("WAVE COMPLETE!")
		
		# Show wave complete message
		if hud and hud.has_method("show_wave_complete"):
			hud.show_wave_complete()
		
		await get_tree().create_timer(time_between_waves).timeout
		start_wave()

func update_hud_enemy_count():
	if hud and hud.has_method("update_wave"):
		hud.update_wave(current_wave, enemies_alive)
		print("Updated enemy count: ", enemies_alive)

func spawn_effect(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 30
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 1.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 45
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -5, 0)
	material.scale_min = 0.1
	material.scale_max = 0.2
	material.color = Color.CYAN
	
	particles.process_material = material
	
	var mesh = QuadMesh.new()
	particles.draw_pass_1 = mesh
	
	get_tree().root.add_child(particles)
	particles.global_position = pos
	
	await get_tree().create_timer(0.6).timeout
	particles.queue_free()
