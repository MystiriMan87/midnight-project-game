extends Node

# Add this as an autoload singleton or attach to your player/camera

@onready var camera: Camera3D = get_viewport().get_camera_3d()

var speed_lines_material: ShaderMaterial
var speed_lines_mesh: MeshInstance3D

func _ready():
	await get_tree().process_frame
	_setup_speed_lines()

func _setup_speed_lines():
	# Create a quad mesh in front of camera for speed lines
	speed_lines_mesh = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(2, 2)
	speed_lines_mesh.mesh = quad
	
	# Create shader material
	speed_lines_material = ShaderMaterial.new()
	speed_lines_material.shader = _create_speed_lines_shader()
	speed_lines_material.set_shader_parameter("intensity", 0.0)
	speed_lines_material.set_shader_parameter("speed", 1.0)
	
	speed_lines_mesh.material_override = speed_lines_material
	speed_lines_mesh.layers = 2  # Render on layer 2
	
	# Position in front of camera
	if camera:
		camera.add_child(speed_lines_mesh)
		speed_lines_mesh.position = Vector3(0, 0, -0.5)
	
	speed_lines_mesh.visible = false

func _create_speed_lines_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 5.0) = 1.0;

// Random function for variation
float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	
	// Center coordinates
	vec2 center = uv - 0.5;
	float dist = length(center);
	float angle = atan(center.y, center.x);
	
	// Normalize angle to 0-1 range
	float norm_angle = (angle + 3.14159) / (2.0 * 3.14159);
	
	// Create multiple layers of lines with different speeds
	float line_count = 24.0;
	float line_id = floor(norm_angle * line_count);
	
	// Add randomness to line thickness and position
	float rand_offset = random(vec2(line_id, 0.0));
	float line_thickness = 0.015 + rand_offset * 0.01;
	
	// Calculate if we're on a line
	float line_pos = fract(norm_angle * line_count);
	float line = smoothstep(0.5 - line_thickness, 0.5 - line_thickness + 0.01, line_pos) * 
	             smoothstep(0.5 + line_thickness, 0.5 + line_thickness - 0.01, line_pos);
	
	// Animate lines moving outward
	float line_length = dist - (TIME * speed * 0.3) + rand_offset;
	line_length = fract(line_length * 2.0);
	
	// Create tapered lines (wider at edges, thinner towards center)
	float taper = smoothstep(0.0, 0.2, line_length) * smoothstep(1.0, 0.7, line_length);
	
	// Only show lines in outer region
	float radial_mask = smoothstep(0.2, 0.4, dist) * smoothstep(1.0, 0.8, dist);
	
	// Combine everything
	float alpha = line * taper * radial_mask * intensity * 2.0;
	
	// Vary brightness based on line
	float brightness = 0.7 + rand_offset * 0.3;
	
	ALBEDO = vec3(brightness);
	ALPHA = alpha;
}
"""
	return shader

# Call this when dashing
func show_dash_effect(duration: float = 0.3):
	if not speed_lines_mesh:
		return
	
	speed_lines_mesh.visible = true
	
	# Set speed for outward motion
	speed_lines_material.set_shader_parameter("speed", 3.0)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Instant full intensity
	speed_lines_material.set_shader_parameter("intensity", 1.0)
	
	# Hold briefly then fade
	tween.tween_interval(0.05)
	tween.tween_method(func(val): speed_lines_material.set_shader_parameter("intensity", val), 1.0, 0.0, duration)
	tween.tween_callback(func(): speed_lines_mesh.visible = false)

# Call this for time slow effect
func show_time_slow_effect(is_active: bool):
	if not camera:
		return
	
	var env = camera.get_viewport().world_3d.environment
	if not env:
		return
	
	# Make sure adjustment is enabled
	env.adjustment_enabled = true
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	if is_active:
		# Only desaturate and add blue tint, no brightness change
		tween.tween_property(env, "adjustment_saturation", 0.3, 0.3)
		tween.parallel().tween_property(env, "adjustment_color_correction", Vector3(0.7, 0.8, 1.3), 0.3)
		# Explicitly ensure brightness stays at 1.0
		env.adjustment_brightness = 1.0
	else:
		# Return to normal
		tween.tween_property(env, "adjustment_saturation", 1.0, 0.3)
		tween.parallel().tween_property(env, "adjustment_color_correction", Vector3.ONE, 0.3)
		# Explicitly ensure brightness stays at 1.0
		env.adjustment_brightness = 1.0

# Alternative: Vignette effect for damage/low health
func show_vignette(intensity: float):
	# Create or update red damage vignette overlay
	if not camera:
		return
	
	var hud = _get_hud()
	if not hud:
		return
	
	# Remove old vignette if it exists
	var old_vignette = hud.get_node_or_null("DamageVignette")
	if old_vignette:
		old_vignette.queue_free()
	
	# Create new vignette overlay
	var vignette = ColorRect.new()
	vignette.name = "DamageVignette"
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = _create_vignette_material()
	
	vignette.anchor_left = 0
	vignette.anchor_top = 0
	vignette.anchor_right = 1
	vignette.anchor_bottom = 1
	
	hud.add_child(vignette)
	
	# Animate the vignette intensity
	var shader_mat = vignette.material as ShaderMaterial
	shader_mat.set_shader_parameter("intensity", intensity)
	
	# Fade out after a moment
	var tween = create_tween()
	tween.tween_interval(0.1)
	tween.tween_method(func(val): 
		if is_instance_valid(shader_mat):
			shader_mat.set_shader_parameter("intensity", val)
	, intensity, 0.0, 0.5)
	tween.tween_callback(func(): 
		if is_instance_valid(vignette):
			vignette.queue_free()
	)

func _create_vignette_material() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 uv = UV;
	vec2 center = uv - 0.5;
	float dist = length(center);
	
	// Create vignette falloff from edges
	float vignette = smoothstep(0.7, 0.2, dist);
	vignette = 1.0 - vignette;
	
	// Red color with alpha based on distance from center
	vec3 red = vec3(1.0, 0.0, 0.0);
	float alpha = vignette * intensity;
	
	COLOR = vec4(red, alpha);
}
"""
	
	var material = ShaderMaterial.new()
	material.shader = shader
	return material

func _get_hud() -> Control:
	# Try to find HUD in the scene
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var hud = player.get_node_or_null("CanvasLayer/HUD")
		if hud:
			return hud
		var canvas = player.get_node_or_null("CanvasLayer")
		if canvas:
			for child in canvas.get_children():
				if child is Control:
					return child
	return null

# Motion blur effect (requires WorldEnvironment with Glow enabled)
func show_motion_blur(active: bool):
	if not camera:
		return
		
	var env = camera.get_viewport().world_3d.environment
	if not env:
		return
	
	var tween = create_tween()
	if active:
		env.glow_enabled = true
		tween.tween_property(env, "glow_strength", 1.5, 0.2)
		tween.parallel().tween_property(env, "glow_blend_mode", Environment.GLOW_BLEND_MODE_ADDITIVE, 0.2)
	else:
		tween.tween_property(env, "glow_strength", 0.8, 0.2)
		tween.tween_callback(func(): env.glow_enabled = false)
