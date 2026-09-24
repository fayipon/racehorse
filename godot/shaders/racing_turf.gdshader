shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform vec4 grass_dark : source_color;
uniform vec4 grass_light : source_color;
uniform float lap_length = 280.0;
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }

void fragment() {
	// Whole mowing bands close seamlessly around the oval, including bends.
	float mowing=smoothstep(-.13,.13,sin(UV.x/lap_length*6.2831853*18.0));
	float patches=noise(world.xz*.7)*.65+noise(world.xz*2.8)*.35;
	// Fine cut grass fades before it can shimmer in the distant chase shots.
	float footprint=max(length(dFdx(world.xz)),length(dFdy(world.xz)));
	float detail=1.0-smoothstep(.04,.18,footprint);
	float blades=(noise(world.xz*vec2(32.0,10.0))-.5)*detail;
	// Hooves wear a darker band along the inside running line.
	float wear=1.0-smoothstep(.4,3.2,UV.y);
	float shade=clamp(.34+patches*.24+(mowing-.5)*.3+blades*.14-wear*.16,0.0,1.0);
	ALBEDO=mix(grass_dark.rgb,grass_light.rgb,shade);
	ROUGHNESS=1.0;
}
