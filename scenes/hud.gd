extends Control

@onready var health_label = $HealthLabel
@onready var ammo_label = $AmmoLabel

func _ready():
	pass

func update_health(value):
	if health_label:
		health_label.text = "Health: " + str(value)

func update_ammo(current, max_ammo, reserve = -1):
	if ammo_label:
		if reserve >= 0:
			ammo_label.text = "Ammo: " + str(current) + "/" + str(max_ammo) + " [" + str(reserve) + "]"
		else:
			ammo_label.text = "Ammo: " + str(current) + "/" + str(max_ammo)

func show_reload_message():
	if ammo_label:
		ammo_label.text = "RELOADING..."
