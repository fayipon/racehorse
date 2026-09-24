shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

// Flags flap away from the pole: UV.x is 0 at the pole and 1 at the tip.
uniform float wind = 1.0;

void vertex() {
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float wave=sin(TIME*4.6-UV.x*5.5+world.x*.37+world.z*.23)+sin(TIME*2.1-UV.x*2.5+world.z*.5)*.4;
	VERTEX+=NORMAL*wave*.16*UV.x*wind;
}

void fragment() {
	ALBEDO=COLOR.rgb;
	ROUGHNESS=.92;
	BACKLIGHT=ALBEDO*.25;
}
