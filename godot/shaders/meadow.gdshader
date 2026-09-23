shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 grass_dark : source_color = vec4(0.31,0.40,0.22,1.0);
uniform vec4 grass_light : source_color = vec4(0.43,0.51,0.29,1.0);
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float patches=noise(world.xz*.17)*.65+noise(world.xz*.62)*.25+noise(world.xz*3.0)*.1;
	float infield=1.0-smoothstep(14.0,19.0,length(vec2(max(abs(world.x)-28.0,0.0),world.z)));
	float mowing=sin(world.x*.6+world.z*.12)*.025*infield;
	ALBEDO=mix(grass_dark.rgb,grass_light.rgb,clamp(patches+mowing,0.0,1.0));
	ROUGHNESS=1.0;
}
