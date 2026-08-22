shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The pond surface: the same neon grid as the ground, but see-through so a sunk
// ball still reads from the bank, and two-sided so it still looks like a ceiling
// once you are under it. Only this one flat plane is transparent; the course
// itself stays opaque so nothing sorts through the hills.

uniform vec3 base_color : source_color = vec3(0.02, 0.03, 0.14);
uniform vec3 line_color : source_color = vec3(0.2, 0.5, 1.0);
uniform float cell_size = 2.4;
uniform float line_thickness = 1.6;
uniform float line_energy = 2.4;
uniform float fill_energy = 0.2;
uniform float scroll_speed = 0.35;
uniform float fade_start = 16.0;
uniform float fade_end = 85.0;
uniform float opacity = 0.5;
// A second grid drifting the other way, so the surface reads as moving water
// rather than a pane of glass laid over the hole.
uniform float ripple_scale = 1.6;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 uv, float thickness) {
	vec2 to_line = abs(fract(uv - 0.5) - 0.5) / max(fwidth(uv) * thickness, 0.00001);
	return 1.0 - min(min(to_line.x, to_line.y), 1.0);
}

void fragment() {
	vec2 base_uv = world_position.xz / cell_size;
	float line = grid_line(base_uv + vec2(0.0, TIME * scroll_speed), line_thickness);
	float drift = grid_line(
		base_uv * ripple_scale - vec2(TIME * scroll_speed * 0.6, 0.0), line_thickness
	);
	line = max(line, drift * 0.55);
	line *= 1.0 - smoothstep(fade_start, fade_end, length(VERTEX));
	ALBEDO = mix(base_color, line_color, line * 0.7);
	EMISSION = line_color * line * line_energy + base_color * fill_energy;
	ROUGHNESS = 0.12;
	METALLIC = 0.3;
	// Lines stay solid while the water between them is only a tint, so the pond
	// floor and anything on it read through the surface.
	ALPHA = clamp(opacity + line * (1.0 - opacity), 0.0, 1.0);
}
