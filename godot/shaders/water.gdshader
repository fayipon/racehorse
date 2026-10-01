shader_type spatial;
render_mode specular_schlick_ggx, diffuse_burley, cull_disabled;

// Still water in the infield lake. It mirrors the sky (the engine's sky
// reflection, strongest at grazing views) over a dark, peaty body that clears
// to green-brown over the shallows by the coping; COLOR.r is 1 at the shore and
// 0 in open water. Fine ripples drift downwind on the same wind as the trees.
uniform vec4 deep : source_color = vec4(0.02, 0.05, 0.055, 1.0);
uniform vec4 shallow : source_color = vec4(0.17, 0.21, 0.15, 1.0);
uniform float ripple = 1.0;
const vec2 WIND = vec2(0.92, 0.39);
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float surface(vec2 p, float t) {
	return noise(p * 0.9 - WIND * t * 0.35) * 0.55
		+ noise(p * 2.6 + vec2(WIND.y, -WIND.x) * t * 0.5) * 0.3
		+ noise(p * 7.0 - WIND * t * 1.1) * 0.15;
}

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float t = TIME * ripple;
	vec2 p = world.xz;
	float e = 0.04;
	float h = surface(p, t);
	vec2 slope = vec2(surface(p + vec2(e, 0.0), t) - h, surface(p + vec2(0.0, e), t) - h) / e;
	// Ripples fade where they would only shimmer at a pixel's size.
	float footprint = length(fwidth(p));
	slope *= 0.045 * (1.0 - smoothstep(0.08, 0.6, footprint) * 0.7);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float shore = clamp(COLOR.r, 0.0, 1.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, shore * shore);
	ROUGHNESS = 0.02;
	SPECULAR = 0.55;
}
