shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 grass_dark : source_color;
uniform vec4 grass_light : source_color;
uniform float band = 6.0;
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }

void fragment() {
	// Two diagonal mowing passes make the classic infield diamond pattern.
	float footprint=max(length(dFdx(world.xz)),length(dFdy(world.xz)));
	float soft=clamp(footprint*1.5,.08,1.0);
	float a=sin((world.x+world.z)*3.14159/band);
	float b=sin((world.x-world.z)*3.14159/band);
	float diamonds=smoothstep(-soft,soft,a*b);
	float patches=noise(world.xz*.35)*.6+noise(world.xz*2.4)*.4;
	ALBEDO=mix(grass_dark.rgb,grass_light.rgb,clamp(.28+diamonds*.34+patches*.3,0.0,1.0));
	ROUGHNESS=1.0;
}
