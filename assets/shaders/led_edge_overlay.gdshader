shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

// Same widening as led_edge, but the creator ghost sits on the fairway lips.
// Those walls would swallow a depth-tested bar, so this one always draws.

uniform vec3 tint : source_color = vec3(0.15, 0.95, 1.0);
uniform float energy = 3.0;
uniform float min_width = 2.2;

const float DIAGONAL = 0.70711;


void vertex() {
	vec3 offset = CUSTOM0.xyz;
	vec3 spine = VERTEX - offset;
	float have = length((MODELVIEW_MATRIX * vec4(offset, 0.0)).xyz);
	if (have > 0.00001) {
		float depth = max(-(MODELVIEW_MATRIX * vec4(spine, 1.0)).z, 0.001);
		float per_pixel = 2.0 * depth / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);
		float want = max(have, min_width * DIAGONAL * per_pixel);
		VERTEX = spine + offset * (want / have);
	}
}


void fragment() {
	ALBEDO = tint;
	EMISSION = tint * energy;
}
