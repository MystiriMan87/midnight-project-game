extends Control

@onready var health_label: Label = $HealthLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel

func _ready():
	if reload_label:
		reload_label.visible = false

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
		reload_label.text = "RELOADING..."
		reload_label.add_theme_color_override("font_color", Color.ORANGE)

func hide_reloading():
	if reload_label:
		reload_label.visible = false

func flash_low_health():
	if health_label:
		var tween = create_tween()
		tween.tween_property(health_label, "modulate:a", 0.3, 0.2)
		tween.tween_property(health_label, "modulate:a", 1.0, 0.2)
