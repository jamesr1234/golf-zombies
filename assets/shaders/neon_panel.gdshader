shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// Local UV grid for a vertical hex-fort pane. Lit only while a face is taking
// hits, so the partner can see which side to cover.

uniform vec3 line_color : source_color = vec3(0.15, 0.95, 1.0);
uniform float energy = 2.4;
uniform float cells = 5.0;
uniform float alpha = 0.75;

void fragment() {
	vec2 grid = abs(fract(UV * cells) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.07, min(grid.x, grid.y));
	ALBEDO = line_color;
	EMISSION = line_color * energy * line;
	ALPHA = mix(0.04, alpha, line);
}
