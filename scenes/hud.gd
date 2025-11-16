extends Control

@onready var health_label = $HealthLabel
@onready var ammo_label = $AmmoLabel

func _ready():
	print("HUD ready!")
	print("Health label: ", health_label)
	print("Ammo label: ", ammo_label)

func update_health(value):
	print("Updating health to: ", value)
	if health_label:
		health_label.text = "Health: " + str(value)
	else:
		print("ERROR: health_label is null!")

func update_ammo(current, max_ammo):
	print("Updating ammo to: ", current, "/", max_ammo)
	if ammo_label:
		ammo_label.text = "Ammo: " + str(current) + "/" + str(max_ammo)
	else:
		print("ERROR: ammo_label is null!")
