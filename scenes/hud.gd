extends Control

@onready var health_label: Label = $HealthLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var wave_label: Label = $WaveLabel if has_node("WaveLabel") else null

func _ready():
	if reload_label:
		reload_label.visible = get_theme_default_base_scale()

func update_health(current_health: int, max_health: int = 100):
	if health_label:
		health_label.text = "HEALTH: " + str(current_health) + "/" + str(max_health)
		
		if current_health > 70: 
			health_label.add_theme_color_override("font_color", Color.WHITE)
		elif current_health > 30:
			health_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			health_label.add_theme_color_override("font_color", Color.RED)
			
func update_ammo(current: int, max_ammo: int, reserve: int = -1):
	if ammo_label:
		if reserve >= 0:
			ammo_label.text = "AMMO: " + str(current) + "/" + str(max_ammo) + " [" + str(reserve) + "]"
		else: 
			ammo_label.text = "AMMO: " + str(current) + "/" + str(max_ammo)
			
		if current == 0:
			ammo_label.add_theme_color_override("font_color", Color.RED)
		elif current <= max_ammo * 0.3:
			ammo_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			ammo_label.add_theme_color_override("font_color", Color.WHITE)
			
func show_reloading():
	if reload_label:
		reload_label.visible = true
		reload_label.text = "RELOADING... "
		reload_label.add_theme_color_override("font_color", Color.ORANGE)
		
func hide_reloading():
	if reload_label:
		reload_label.visible = false
		
func flash_low_health():
	if health_label:
		var tween = create_tween()
		tween.tween_property(health_label, "modulate:a", 0.3, 0.2)
		tween.tween_property(health_label, "modulate:a", 1.0, 0.2)
		
func update_wave(wave_number: int, enemies_remaining: int = -1):
	if wave_label: 
		if enemies_remaining >= 0:
			wave_label.text = "WAVE " + str(wave_number) + " - " + str(enemies_remaining)
		else:
			wave_label.text = "WAVE " + str(wave_number)
			
		
		if enemies_remaining == -1:
			pulse_wave_label()
			
func pulse_wave_label():
	if not wave_label:
		return
		
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(wave_label, "scale", Vector2(1.3, 1.3), 0.3)
	tween.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.3)
	
func show_wave_complete():
	if wave_label:
		wave_label.text = "WAVE COMPLETE"
		wave_label.add_theme_color_override("font_color", Color.GREEN)
		
		var tween = create_tween()
		tween.tween_property(wave_label, "scale", Vector2(1.5, 1.5), 0.3)
		tween.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.3)
		
		await get_tree().create_timer(2.0).timeout
		wave_label.add_theme_color_override("font_color", Color.WHITE)
		
