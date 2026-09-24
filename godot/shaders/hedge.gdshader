shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform vec4 leaf_dark : source_color;
uniform vec4 leaf_light : source_color;
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }

void fragment() {
	// Planar noise on all three axes keeps clipped leaves on every face.
	float leaves=(noise(world.xy*4.0)+noise(world.zy*4.0)+noise(world.xz*4.0))/3.0;
	float clumps=(noise(world.xy*.9)+noise(world.zy*.9))*.5;
	float top=smoothstep(.4,.95,NORMAL.y*.5+.5);
	ALBEDO=mix(leaf_dark.rgb,leaf_light.rgb,clamp(leaves*.7+clumps*.3+top*.12,0.0,1.0));
	ROUGHNESS=1.0;
}
