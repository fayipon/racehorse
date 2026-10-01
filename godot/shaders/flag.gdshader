shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Cloth flags flying downwind from their poles. A flag is a grid: UV.x runs
// 0 at the hoist to 1 at the fly, UV.y 0 at the top to 1 at the foot, and UV2
// holds its length and depth in metres. Waves run from the hoist to the fly,
// growing as they go, on the same gusts that bend the trees
// (foliage.gdshader); the normal follows the cloth's slope, so every fold is
// lit and shaded. In a lull the fly sags toward the pole.
uniform float wind = 1.0;
const vec2 WIND = vec2(0.92, 0.39);
varying float fold;
varying vec2 cloth;

float gust_at(vec2 place) {
	float swell = 0.55 + 0.45 * sin(TIME * 0.55 - dot(place, WIND) * 0.045);
	float ripple = sin(TIME * 1.7 - dot(place, WIND) * 0.12 + place.y * 0.05);
	return swell + ripple * 0.22;
}

void vertex() {
	vec3 fly = vec3(WIND.x, 0.0, WIND.y);
	vec3 side = vec3(-WIND.y, 0.0, WIND.x);
	float len = UV2.x;
	float depth = UV2.y;
	float u = UV.x;
	float v = UV.y;
	float x = u * len;
	float y = v * depth;
	vec3 hoist = VERTEX - fly * x + vec3(0.0, y, 0.0);
	float gust = clamp(gust_at(hoist.xz), 0.0, 1.4);
	float phase = COLOR.a * 6.2832;
	float strength = wind * (0.35 + 0.65 * gust);
	// Travelling waves, quicker and tighter in a strong wind.
	float k = 6.2832 / (len * mix(0.75, 0.5, gust));
	float w = mix(5.0, 9.0, gust);
	float grow = pow(u, 1.25);
	float a1 = len * 0.095 * strength * grow;
	float a2 = len * 0.04 * strength * grow;
	float s1 = k * x - TIME * w + v * depth * 1.4 + phase;
	float s2 = 1.9 * k * x - TIME * w * 1.6 - v * depth * 2.3 + phase * 1.7;
	float z = a1 * sin(s1) + a2 * sin(s2);
	// Slopes of the cloth along the fly and down the flag, for its normal.
	float dz_dx = a1 * k * cos(s1) + a2 * 1.9 * k * cos(s2) + (len * 0.095 * strength * 1.25 * pow(max(u, 1e-3), 0.25) / len) * sin(s1);
	float dz_dy = a1 * 1.4 * cos(s1) - a2 * 2.3 * cos(s2);
	// The fly gathers up a little as the cloth ripples, and sags in a lull.
	float sag = (1.0 - clamp(strength, 0.0, 1.0)) * 0.35;
	float drop = sag * len * u * u;
	vec3 offset = side * z - fly * (abs(z) * 0.35 + sag * x * u * 0.45) - vec3(0.0, drop, 0.0);
	VERTEX += offset;
	// The sag swings the cloth within its own plane, so only the waves tilt it.
	NORMAL = normalize(side - fly * dz_dx + vec3(0.0, 1.0, 0.0) * dz_dy);
	fold = z / max(len * 0.1, 1e-3);
	cloth = vec2(x, y);
}

void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;
	vec3 color = COLOR.rgb;
	// A white sleeve round the pole, a stitched hem along the fly.
	float sleeve = step(UV.x, 0.045);
	color = mix(color, vec3(0.93, 0.92, 0.88), sleeve);
	float hem = smoothstep(0.975, 0.985, UV.x) * (1.0 - smoothstep(0.995, 1.0, UV.x));
	color *= 1.0 - 0.18 * hem;
	// The weave, and the deeper hollows of each fold.
	float weave = 0.5 + 0.5 * sin(cloth.x * 520.0) * sin(cloth.y * 520.0);
	color *= 0.95 + 0.05 * weave;
	color *= 0.9 + 0.1 * clamp(fold * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = color;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
	// Sunlight glows through the thin cloth from behind.
	BACKLIGHT = color * 0.55;
	RIM = 0.1;
	RIM_TINT = 0.5;
}
