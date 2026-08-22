shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Vertex sway so a crown reads as leaves in wind instead of a rigid bulb.

uniform vec4 albedo : source_color = vec4(0.28, 0.82, 0.32, 1.0);
uniform float emission_energy = 0.7;
uniform float sway_phase = 0.0;
uniform float sway_amp = 0.16;
uniform float sway_speed = 1.35;

void vertex() {
	float lift = max(VERTEX.y + 0.35, 0.0);
	float t = TIME * sway_speed + sway_phase;
	VERTEX.x += sin(t + VERTEX.z * 1.1) * sway_amp * lift;
	VERTEX.z += cos(t * 0.73 + VERTEX.x * 0.9) * sway_amp * 0.55 * lift;
	VERTEX.x += sin(t * 2.4 + VERTEX.x * 4.0) * sway_amp * 0.22 * lift;
}

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * emission_energy;
	ROUGHNESS = 0.72;
	METALLIC = 0.04;
}
