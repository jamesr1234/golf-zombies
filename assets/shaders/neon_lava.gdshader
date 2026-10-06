shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Hot crust with drifting glow veins and popping bubbles. Vertex swell is the
// boil; the rest is colour so a whole pool can share one material.

uniform vec3 crust_color : source_color = vec3(0.18, 0.03, 0.01);
uniform vec3 glow_color : source_color = vec3(1.0, 0.28, 0.04);
uniform vec3 bubble_color : source_color = vec3(1.0, 0.72, 0.18);
uniform float cell_size = 1.35;
uniform float boil = 0.055;
uniform float energy = 3.8;

varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float swell = noise(world_position.xz * 1.7 + vec2(TIME * 0.55, TIME * 0.38));
	float pop = noise(world_position.xz * 3.4 - vec2(TIME * 0.9, TIME * 0.6));
	VERTEX.y += (swell * 0.7 + pop * 0.3) * boil;
}

void fragment() {
	vec2 uv = world_position.xz / cell_size;
	float flow = noise(uv * 2.2 + vec2(TIME * 0.22, -TIME * 0.18));
	float vein = noise(uv * 5.4 - vec2(TIME * 0.4, TIME * 0.28));
	float heat = smoothstep(0.35, 0.82, flow * 0.65 + vein * 0.45);
	float bubble = smoothstep(0.78, 0.93, noise(uv * 6.2 + vec2(TIME * 0.7, TIME * 0.55)));
	vec3 color = mix(crust_color, glow_color, heat);
	color = mix(color, bubble_color, bubble);
	ALBEDO = color;
	EMISSION = glow_color * (0.45 + heat * energy) + bubble_color * bubble * 6.0;
	ROUGHNESS = mix(0.55, 0.18, heat + bubble);
	METALLIC = 0.15;
}
