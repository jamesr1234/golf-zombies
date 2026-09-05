shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// Hidden until a strike. The bounce lights the pane at the hit
// and falls off along the ribbon so the bounce reads from the tee.

uniform vec3 line_color : source_color = vec3(0.15, 0.95, 1.0);
uniform float cells = 0.4;
uniform vec3 hit_pos = vec3(0.0);
uniform float hit_energy = 0.0;
uniform float hit_radius = 12.0;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 grid_uv = vec2(world_pos.y, world_pos.x + world_pos.z) * cells;
	vec2 grid = abs(fract(grid_uv) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.07, min(grid.x, grid.y));
	float dist = length(world_pos - hit_pos);
	float glow = hit_energy * (1.0 - smoothstep(0.0, hit_radius, dist));
	float hot = hit_energy * (1.0 - smoothstep(0.0, hit_radius * 0.35, dist));
	ALBEDO = line_color;
	EMISSION = line_color * (glow * (0.35 + line) + hot);
	ALPHA = glow * 0.45 + hot * 0.35;
	if (ALPHA < 0.01) {
		discard;
	}
}
