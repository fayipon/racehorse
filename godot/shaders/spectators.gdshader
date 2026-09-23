shader_type spatial;
render_mode cull_back;

uniform bool reduce_motion = false;

vec3 shirt(float n) {
	if (n < .125) return vec3(.77,.39,.27);
	if (n < .25) return vec3(.28,.49,.61);
	if (n < .375) return vec3(.74,.64,.32);
	if (n < .5) return vec3(.43,.57,.40);
	if (n < .625) return vec3(.65,.49,.59);
	if (n < .75) return vec3(.76,.75,.66);
	if (n < .875) return vec3(.30,.36,.43);
	return vec3(.53,.45,.63);
}

void vertex() {
	// Category UVs let one draw call retain distinct clothes, skin and hair.
	if (UV.x < .1) COLOR.rgb = mix(vec3(.39,.24,.16),vec3(.82,.62,.44),INSTANCE_CUSTOM.y);
	else if (UV.x < .3) COLOR.rgb = shirt(INSTANCE_CUSTOM.x);
	else if (UV.x < .5) COLOR.rgb = mix(vec3(.14,.18,.22),vec3(.39,.37,.29),INSTANCE_CUSTOM.y);
	else if (UV.x < .7) COLOR.rgb = vec3(.12,.11,.10);
	else COLOR.rgb = mix(vec3(.11,.075,.045),vec3(.40,.28,.12),INSTANCE_CUSTOM.x);
	if (!reduce_motion) {
		// Feet stay planted; only a small subset gently shift their upper body.
		float upper = smoothstep(1.3,3.0,VERTEX.y);
		VERTEX.x += sin(TIME * (1.0 + INSTANCE_CUSTOM.x*.35) + INSTANCE_CUSTOM.z*6.283) * INSTANCE_CUSTOM.w * .035 * upper;
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = .08;
}
