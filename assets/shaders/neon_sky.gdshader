shader_type sky;

// Synthwave night: magenta haze on the horizon fading up to near-black, with a
// scatter of stars hashed off the view direction so no texture is needed.

uniform vec3 horizon_color : source_color = vec3(0.42, 0.05, 0.45);
uniform vec3 zenith_color : source_color = vec3(0.02, 0.01, 0.1);
uniform vec3 ground_color : source_color = vec3(0.01, 0.01, 0.02);
uniform float star_threshold = 0.9987;
uniform float star_energy = 2.5;
// Higher values keep the magenta hugging the horizon instead of flooding the sky.
uniform float horizon_falloff = 4.0;

float star_hash(vec3 cell) {
	return fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	float height = EYEDIR.y;
	vec3 color;
	if (height >= 0.0) {
		color = mix(horizon_color, zenith_color, pow(clamp(height, 0.0, 1.0), 1.0 / horizon_falloff));
	} else {
		color = mix(horizon_color, ground_color, pow(clamp(-height, 0.0, 1.0), 0.3));
	}
	float star = step(star_threshold, star_hash(floor(EYEDIR * 320.0)));
	COLOR = color + vec3(star * star_energy * clamp(height * 4.0, 0.0, 1.0));
}
