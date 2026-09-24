shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.13,0.34,0.38,1.0);
uniform vec4 sky : source_color = vec4(0.80,0.89,0.95,1.0);
uniform float ripple = 1.0;
varying vec3 world;

void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }

void fragment() {
	vec2 p=world.xz;
	float t=TIME*.7*ripple;
	vec3 n=normalize(vec3(
		sin(p.x*1.9+t)*.05+sin(p.y*3.1-t*1.2)*.035,
		1.0,
		cos(p.y*2.3+t*.8)*.05+cos(p.x*3.7-t)*.03));
	NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	// Grazing views mirror the pale sky; steep views look into the water.
	float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),4.0);
	ALBEDO=mix(deep.rgb,sky.rgb,clamp(fresnel*1.1,0.0,.9));
	ROUGHNESS=.06;
	SPECULAR=.7;
}
