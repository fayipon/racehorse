shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// Every mown or raked surface shares this one shader, so the web build compiles
// a single program for all of them; `pattern` picks the surface.
// 0: infield diamonds, 1: outer meadow, 2: racing turf, 3: sand track.
uniform int pattern = 0;
uniform vec4 color_dark : source_color = vec4(0.31,0.40,0.22,1.0);
uniform vec4 color_light : source_color = vec4(0.43,0.51,0.29,1.0);
uniform float band = 6.0;
uniform float lap_length = 280.0;
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
	float footprint=max(length(dFdx(world.xz)),length(dFdy(world.xz)));
	vec3 albedo;
	if (pattern==0) {
		// Two diagonal mowing passes make the classic infield diamond pattern.
		float soft=clamp(footprint*1.5,.08,1.0);
		float a=sin((world.x+world.z)*3.14159/band);
		float b=sin((world.x-world.z)*3.14159/band);
		float diamonds=smoothstep(-soft,soft,a*b);
		float patches=noise(world.xz*.35)*.6+noise(world.xz*2.4)*.4;
		albedo=mix(color_dark.rgb,color_light.rgb,clamp(.28+diamonds*.34+patches*.3,0.0,1.0));
	} else if (pattern==1) {
		float patches=noise(world.xz*.17)*.65+noise(world.xz*.62)*.25+noise(world.xz*3.0)*.1;
		float infield=1.0-smoothstep(14.0,19.0,length(vec2(max(abs(world.x)-28.0,0.0),world.z)));
		float mowing=sin(world.x*.6+world.z*.12)*.025*infield;
		albedo=mix(color_dark.rgb,color_light.rgb,clamp(patches+mowing,0.0,1.0));
	} else if (pattern==2) {
		// Whole mowing bands close seamlessly around the oval, including bends.
		float mowing=smoothstep(-.13,.13,sin(UV.x/lap_length*6.2831853*18.0));
		float patches=noise(world.xz*.7)*.65+noise(world.xz*2.8)*.35;
		// Fine cut grass fades before it can shimmer in the distant chase shots.
		float detail=1.0-smoothstep(.04,.18,footprint);
		float blades=(noise(world.xz*vec2(32.0,10.0))-.5)*detail;
		// Hooves wear a darker band along the inside running line.
		float wear=1.0-smoothstep(.4,3.2,UV.y);
		float shade=clamp(.34+patches*.24+(mowing-.5)*.3+blades*.14-wear*.16,0.0,1.0);
		albedo=mix(color_dark.rgb,color_light.rgb,shade);
	} else {
		// Harrow lines run with the direction of travel; UV.y spans the width.
		float detail=1.0-smoothstep(.03,.16,footprint);
		float harrow=(sin(UV.y*40.0+noise(world.xz*.8)*3.0)*.5+.5)*detail;
		float grain=noise(world.xz*9.0)*.3+noise(world.xz*2.2)*.35+noise(world.xz*.45)*.35;
		float edge=smoothstep(0.0,.35,UV.y)*smoothstep(0.0,.35,width-UV.y);
		albedo=mix(color_dark.rgb,color_light.rgb,clamp(.3+grain*.5-harrow*.05,0.0,1.0))*mix(.88,1.0,edge);
	}
	ALBEDO=albedo;
	ROUGHNESS=1.0;
}
