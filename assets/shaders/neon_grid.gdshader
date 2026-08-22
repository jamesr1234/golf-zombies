shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// World-space neon grid used for the ground and every surface patch. Lines are
// measured in screen derivatives so they stay one crisp width at any distance
// instead of turning into moire in the fog.

uniform vec3 base_color : source_color = vec3(0.02, 0.06, 0.08);
uniform vec3 line_color : source_color = vec3(0.15, 1.0, 0.75);
uniform float cell_size = 4.0;
uniform float line_thickness = 1.6;
uniform float line_energy = 2.0;
uniform float fill_energy = 0.2;
uniform float scroll_speed = 0.0;
// Without this the lines merge into one solid glowing wall at grazing angles,
// which hides the flag and everything else on the horizon.
uniform float fade_start = 16.0;
uniform float fade_end = 85.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid_uv = world_position.xz / cell_size + vec2(0.0, TIME * scroll_speed);
	vec2 to_line = abs(fract(grid_uv - 0.5) - 0.5) / max(fwidth(grid_uv) * line_thickness, 0.00001);
	float line = 1.0 - min(min(to_line.x, to_line.y), 1.0);
	line *= 1.0 - smoothstep(fade_start, fade_end, length(VERTEX));
	ALBEDO = mix(base_color, line_color, line * 0.7);
	EMISSION = line_color * line * line_energy + base_color * fill_energy;
	ROUGHNESS = 0.65;
	METALLIC = 0.2;
}
