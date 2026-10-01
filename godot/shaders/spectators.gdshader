shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform bool reduce_motion = false;
varying float height;

// A racecourse crowd dresses mostly in white, navy, black, grey and stone, with
// a smaller share of colour.
vec3 shirt(float n) {
	if (n < .16) return vec3(.86,.86,.83);
	if (n < .25) return vec3(.74,.72,.66);
	if (n < .34) return vec3(.16,.2,.31);
	if (n < .42) return vec3(.11,.11,.12);
	if (n < .49) return vec3(.44,.46,.48);
	if (n < .57) return vec3(.55,.67,.8);
	if (n < .64) return vec3(.72,.63,.5);
	if (n < .7) return vec3(.62,.17,.19);
	if (n < .76) return vec3(.84,.6,.64);
	if (n < .82) return vec3(.27,.42,.33);
	if (n < .88) return vec3(.83,.74,.42);
	if (n < .94) return vec3(.33,.45,.62);
	return vec3(.55,.42,.62);
}

vec3 trousers(float n) {
	if (n < .3) return vec3(.12,.14,.2);
	if (n < .5) return vec3(.1,.1,.11);
	if (n < .68) return vec3(.62,.56,.45);
	if (n < .82) return vec3(.27,.33,.44);
	if (n < .92) return vec3(.36,.36,.37);
	return vec3(.82,.8,.76);
}

void vertex() {
	height = VERTEX.y;
	// Category UVs let one draw call retain distinct clothes, skin and hair.
	if (UV.x < .1) COLOR.rgb = mix(vec3(.39,.24,.16),vec3(.84,.65,.5),INSTANCE_CUSTOM.y);
	else if (UV.x < .3) COLOR.rgb = shirt(INSTANCE_CUSTOM.x);
	else if (UV.x < .5) COLOR.rgb = trousers(fract(INSTANCE_CUSTOM.x * 7.31 + INSTANCE_CUSTOM.z));
	else if (UV.x < .7) COLOR.rgb = vec3(.12,.11,.10);
	else COLOR.rgb = mix(vec3(.08,.06,.045),vec3(.42,.3,.15),INSTANCE_CUSTOM.x*INSTANCE_CUSTOM.y);
	if (!reduce_motion) {
		// Feet stay planted; only a small subset gently shift their upper body.
		float upper = smoothstep(1.3,3.0,VERTEX.y);
		VERTEX.x += sin(TIME * (1.0 + INSTANCE_CUSTOM.x*.35) + INSTANCE_CUSTOM.z*6.283) * INSTANCE_CUSTOM.w * .035 * upper;
	}
}
void fragment() {
	// Laps and legs sit in the shade of the people around them.
	ALBEDO = COLOR.rgb * mix(.55, 1.0, smoothstep(.6, 2.6, height));
	ROUGHNESS = .9;
	SPECULAR = .15;
	RIM = .15;
	RIM_TINT = .7;
}
