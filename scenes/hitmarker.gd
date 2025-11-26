extends Control

@onready var top_left = $TopLeft
@onready var top_right = $TopRight
@onready var bottom_left = $BottomLeft
@onready var bottom_right = $BottomRight

func _ready():
	hide()

func show_hit(kill: bool = false):
	show()
	
	# Reset positions and colors
	var offset = 8.0
	var center = size / 2.0
	
	top_left.position = center + Vector2(-offset, -offset)
	top_right.position = center + Vector2(offset, -offset)
	bottom_left.position = center + Vector2(-offset, offset)
	bottom_right.position = center + Vector2(offset, offset)
	
	# Set color based on kill or hit
	var hit_color = Color.RED if kill else Color.WHITE
	top_left.modulate = hit_color
	top_right.modulate = hit_color
	bottom_left.modulate = hit_color
	bottom_right.modulate = hit_color
	
	# Animate
	var tween = create_tween()
	tween.set_parallel(true)
	
	var expand = 15.0 if kill else 12.0
	var duration = 0.15 if kill else 0.1
	
	# Expand outward
	tween.tween_property(top_left, "position", center + Vector2(-expand, -expand), duration)
	tween.tween_property(top_right, "position", center + Vector2(expand, -expand), duration)
	tween.tween_property(bottom_left, "position", center + Vector2(-expand, expand), duration)
	tween.tween_property(bottom_right, "position", center + Vector2(expand, expand), duration)
	
	# Fade out
	tween.tween_property(top_left, "modulate:a", 0.0, duration)
	tween.tween_property(top_right, "modulate:a", 0.0, duration)
	tween.tween_property(bottom_left, "modulate:a", 0.0, duration)
	tween.tween_property(bottom_right, "modulate:a", 0.0, duration)
	
	await tween.finished
	hide()
