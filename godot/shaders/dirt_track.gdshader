shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 sand_dark : source_color;
uniform vec4 sand_light : source_color;
uniform float width = 4.8;
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }

void fragment() {
	// Harrow lines run with the direction of travel; UV.y spans the width.
	float footprint=max(length(dFdx(world.xz)),length(dFdy(world.xz)));
	float detail=1.0-smoothstep(.03,.16,footprint);
	float harrow=(sin(UV.y*40.0+noise(world.xz*.8)*3.0)*.5+.5)*detail;
	float grain=noise(world.xz*9.0)*.3+noise(world.xz*2.2)*.35+noise(world.xz*.45)*.35;
	float edge=smoothstep(0.0,.35,UV.y)*smoothstep(0.0,.35,width-UV.y);
	ALBEDO=mix(sand_dark.rgb,sand_light.rgb,clamp(.3+grain*.5-harrow*.05,0.0,1.0))*mix(.88,1.0,edge);
	ROUGHNESS=1.0;
}
