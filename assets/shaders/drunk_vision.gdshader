shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blur_px = 0.0;
uniform float split = 0.0;
uniform float tint = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = SCREEN_PIXEL_SIZE;
	float wobble = sin(TIME * 1.6 + uv.y * 10.0) * split * 0.35;
	vec2 off = vec2(split + wobble, split * 0.28 * sin(TIME * 1.15));
	vec4 left = vec4(0.0);
	vec4 right = vec4(0.0);
	float weight = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 jitter = vec2(float(x), float(y)) * texel * blur_px;
			float w = 1.0 / (1.0 + abs(float(x)) + abs(float(y)));
			left += texture(screen_texture, uv + off + jitter) * w;
			right += texture(screen_texture, uv - off + jitter) * w;
			weight += w;
		}
	}
	left /= weight;
	right /= weight;
	vec4 mixed = mix(left, right, 0.5);
	mixed.rgb = mix(mixed.rgb, mixed.rgb * vec3(1.12, 0.92, 0.62), tint);
	COLOR = mixed;
}
