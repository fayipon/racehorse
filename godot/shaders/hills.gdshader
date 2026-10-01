shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// The far hills round the course (landscape.gd): a forest canopy of rounded
// crowns with open meadows on the gentler ground, fading into blue haze with
// distance as real far country does.
uniform vec4 canopy_dark : source_color = vec4(0.18, 0.29, 0.14, 1.0);
uniform vec4 canopy_light : source_color = vec4(0.33, 0.46, 0.22, 1.0);
uniform vec4 meadow : source_color = vec4(0.52, 0.6, 0.3, 1.0);
uniform vec4 haze_color : source_color = vec4(0.62, 0.74, 0.84, 1.0);
// How much of the colour the haze replaces at this ring's distance.
uniform float haze = 0.35;
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 up_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (up_normal.y < 0.0) { up_normal = -up_normal; NORMAL = -NORMAL; }
	// Tree crowns a few metres across, in clumps; seen far off they blur to a
	// mottled green that still reads as woodland.
	float crowns = noise(world.xz * 0.22) * 0.55 + noise(world.xz * 0.06) * 0.3 + noise(world.xz * 0.9) * 0.15;
	// Stands of darker and lighter woodland tens of metres across.
	float stands = noise(world.xz * 0.025) * 0.65 + noise(world.xz * 0.008 + vec2(9.0, 1.0)) * 0.35;
	vec3 forest = mix(canopy_dark.rgb, canopy_light.rgb, clamp(crowns * 0.45 + stands * 0.75 - 0.15, 0.0, 1.0));
	// Meadows open on gentle slopes in irregular patches.
	float open = smoothstep(0.58, 0.72, noise(world.xz * 0.012 + vec2(3.0, 7.0))) * smoothstep(0.82, 0.95, up_normal.y);
	vec3 ground = mix(forest, meadow.rgb, open);
	// Height lifts the haze a little less on the summits, which stand out.
	float lift = clamp(world.y / 90.0, 0.0, 1.0);
	float mist = clamp(haze * (1.0 - lift * 0.25), 0.0, 1.0);
	ALBEDO = ground * (1.0 - mist);
	EMISSION = haze_color.rgb * mist * 0.85;
	ROUGHNESS = 1.0;
}
