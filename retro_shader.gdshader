shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color;
uniform float vertex_snap = 0.05;
uniform bool use_vertex_snap = true;

void vertex() {
	if (use_vertex_snap) {
		vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
		world_pos.xyz = floor(world_pos.xyz / vertex_snap) * vertex_snap;
		VERTEX = (inverse(MODEL_MATRIX) * world_pos).xyz;
	}
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	ALBEDO = albedo_color.rgb * tex.rgb;
}


