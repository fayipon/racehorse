shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// Every mown or raked surface shares this one shader, so the web build compiles
// a single program for all of them; `pattern` picks the surface.
// 0: infield diamonds, 1: outer meadow, 2: racing turf, 3: sand track.
// The blades and grains come from baked textures (scripts/bake_turf.py); the
// colours here set each surface's tone around them.
uniform int pattern = 0;
uniform vec4 color_dark : source_color = vec4(0.31,0.40,0.22,1.0);
uniform vec4 color_light : source_color = vec4(0.43,0.51,0.29,1.0);
uniform float band = 6.0;
uniform float width = 4.8;
uniform float half_straight = 28.0;
// Across the racing turf the mower runs this many lengthwise passes.
uniform float passes = 6.0;
uniform sampler2D turf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D turf_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Racing turf only: the near grass is drawn again as stacked shells, each
// keeping the blades tall enough to reach it, so low cameras see real blades.
// A shell mesh carries its height fraction in UV2.x; the turf itself is 0.
uniform float blade_height = 0.0;
uniform float blade_density = 90.0;
uniform float blade_lean = .5;
// Breeze on the shells: waves of bent blades rolling downwind, the same wind
// as the trees (foliage.gdshader). Zero keeps the blades still.
uniform float breeze = 0.0;
const vec2 WIND = vec2(0.92, 0.39);
// One turf tile is a metre of grass; one sand tile three metres of track.
const float TURF_TILE = 1.0;
const float SAND_TILE = 3.0;
varying vec3 world;
varying float layer;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() {
	layer=UV2.x;
	// Uncut grass stands longer along both rails.
	float rough=1.0+(1.0-smoothstep(0.0,.7,UV.y))+(1.0-smoothstep(0.0,.7,width-UV.y));
	VERTEX.y+=layer*blade_height*rough;
	world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

// Which way a lengthwise mowing pass laid its blades, across the turf's width.
float pass_lay(float across_track) {
	return smoothstep(-.35,.35,sin(across_track/(width/passes)*3.14159))*2.0-1.0;
}

// Mown stripes are blades laid one way or the other: a band laid away from the
// viewer shows the sunlit sides of its blades and looks pale, one laid toward
// the viewer shows their shaded tips and looks dark, and seen from above the
// difference fades. `lay` is the direction the band's blades point.
float laid(vec2 lay, vec3 to_camera) {
	return -dot(lay,to_camera.xz);
}

void fragment() {
	float footprint=max(length(dFdx(world.xz)),length(dFdy(world.xz)));
	float sideways=min(length(dFdx(world.xz)),length(dFdy(world.xz)));
	vec3 to_camera=normalize(CAMERA_POSITION_WORLD-world);
	// Stadium geometry: the outward direction from the nearest point of the centre line.
	vec2 outward=world.xz-vec2(clamp(world.x,-half_straight,half_straight),0.0);
	outward=length(outward)>.001?normalize(outward):vec2(0.0,1.0);
	vec2 along=vec2(outward.y,-outward.x);
	float blade_shade=1.0;
	float glint=0.0;
	if (blade_height>0.0) {
		// Once a blade spans less than a pixel the shells would only sparkle, so
		// every blade shortens with distance until it sinks into the turf texture.
		float cell=1.0/blade_density;
		float reach=1.0-smoothstep(cell*.22,cell*.7,sideways);
		if (layer>reach) discard;
		// Each layer looks back along the pass's lay to the blade's root, so
		// blades lean with the mowing stripes and curve over near their tips.
		float wave=sin(TIME*1.6-dot(world.xz,WIND)*.35)*.5+.5;
		vec2 bend=along*pass_lay(UV.y)*blade_lean+WIND*breeze*(.3+.7*wave*wave);
		vec2 q=(world.xz-bend*blade_height*layer*layer)*blade_density;
		vec2 id=floor(q);
		float tall=.3+.7*hash(id);
		if (layer>tall*reach) discard;
		vec2 root=vec2(hash(id+vec2(3.1,1.7)),hash(id+vec2(7.3,4.9)))*.44+.28;
		if (distance(fract(q),root)>.36*(1.0-.8*layer/tall)) discard;
		// Light reaches the tips; the base of the sward stays in shade.
		blade_shade=mix(.55,1.05,layer/tall)*mix(.88,1.12,hash(id+vec2(11.0,2.0)));
		// Some upper blades catch the sun on their waxy sides and turn silvery.
		glint=step(.82,hash(id+vec2(5.0,13.0)))*smoothstep(.55,.9,layer/tall);
	}
	vec3 albedo;
	vec3 surface_normal=vec3(0.0,1.0,0.0);
	if (pattern==3) {
		// Harrow lines run with the direction of travel; UV.y spans the width.
		vec2 uv=UV/SAND_TILE;
		vec3 grains=texture(sand_albedo,uv).rgb;
		vec3 mean=textureLod(sand_albedo,vec2(.5),12.0).rgb;
		float mottle=noise(world.xz*.45)*.6+noise(world.xz*1.7)*.4;
		vec3 base=mix(color_dark.rgb,color_light.rgb,clamp(.25+mottle*.6,0.0,1.0));
		// Kicked-back sand darkens toward both rails, where the harrow misses.
		float edge=smoothstep(0.0,.45,UV.y)*smoothstep(0.0,.45,width-UV.y);
		albedo=base*grains/mean*mix(.84,1.0,edge);
		vec3 n=texture(sand_normal,uv).xyz*2.0-1.0;
		n.xy*=1.0-smoothstep(.02,.12,footprint);
		surface_normal=normalize(n.x*vec3(along.x,0.0,along.y)+n.z*vec3(0.0,1.0,0.0)-n.y*vec3(outward.x,0.0,outward.y));
	} else {
		vec2 uv=world.xz/TURF_TILE;
		vec3 blades=texture(turf_albedo,uv).rgb;
		vec3 mean=textureLod(turf_albedo,vec2(.5),12.0).rgb;
		// Larger, turned copies of the same turf break up the tile's repeat and
		// keep a clumpy grain in the middle distance, where the blades blur away.
		vec3 luma=vec3(.3,.59,.11);
		float mean_luma=dot(mean,luma);
		float clumps=dot(texture(turf_albedo,mat2(vec2(.8,.6),vec2(-.6,.8))*world.xz/(TURF_TILE*3.7)).rgb,luma)/mean_luma;
		float tufts=dot(texture(turf_albedo,mat2(vec2(.28,-.96),vec2(.96,.28))*world.xz/(TURF_TILE*13.0)).rgb,luma)/mean_luma;
		// Sunlit blade sides against the dark of the sward: a little more contrast
		// than the texture's own average carries.
		vec3 detail=pow(blades/mean,vec3(1.3))*mix(1.0,clumps,.5)*mix(1.0,tufts,.35);
		// Lush and thinner patches several metres across.
		float patches=noise(world.xz*.16)*.55+noise(world.xz*.55)*.3+noise(world.xz*2.1)*.15;
		float yellow=smoothstep(.45,.85,noise(world.xz*.09+vec2(17.0,3.0)));
		float shade;
		float sheen=0.0;
		float divots=0.0;
		if (pattern==0) {
			// Two diagonal mowing passes make the classic infield diamond pattern.
			float soft=clamp(footprint*1.5,.08,1.0);
			float a=smoothstep(-soft,soft,sin((world.x+world.z)*3.14159/band))*2.0-1.0;
			float b=smoothstep(-soft,soft,sin((world.x-world.z)*3.14159/band))*2.0-1.0;
			sheen=laid(vec2(.7071,.7071)*a,to_camera)*.5+laid(vec2(.7071,-.7071)*b,to_camera)*.5;
			shade=.42+patches*.3;
		} else if (pattern==1) {
			shade=patches;
		} else {
			// Lengthwise passes follow the bends.
			sheen=laid(along*pass_lay(UV.y),to_camera)*.6;
			// Hooves wear a browner band along the inside running line.
			float wear=(1.0-smoothstep(.4,3.2,UV.y))*(.6+noise(world.xz*1.3)*.4);
			shade=clamp(.34+patches*.34-wear*.12,0.0,1.0);
			yellow=max(yellow,wear*.55);
			// Scattered divots where shoes have torn the turf.
			divots=smoothstep(.83,.93,noise(world.xz*4.3))*smoothstep(.55,.85,noise(world.xz*.7+vec2(5.0,9.0)));
			divots*=(1.0-smoothstep(.04,.15,footprint))*(1.0-smoothstep(1.5,7.0,UV.y)*.7);
			// No blades stand in a torn-out divot.
			if (layer>0.0 && divots>.25) discard;
		}
		vec3 tone=mix(color_dark.rgb,color_light.rgb,clamp(shade,0.0,1.0));
		// Sunburnt patches are warmer and paler.
		tone=mix(tone,tone*vec3(1.16,1.05,.72),yellow*.45);
		// Laid-away bands are paler and a little yellower, laid-toward richer.
		tone*=1.0+sheen*vec3(.2,.17,.1);
		// Shell blades carry their own light and only a hint of the texture below.
		if (layer>0.0) detail=mix(detail,vec3(1.0),.6);
		albedo=mix(tone*detail,vec3(.3,.22,.13)*(.8+blades.g),divots*.8)*blade_shade;
		albedo=mix(albedo,albedo*1.25+vec3(.06,.08,.05),glint);
		vec3 n=texture(turf_normal,uv).xyz*2.0-1.0;
		n.xy*=1.0-smoothstep(.03,.2,footprint);
		surface_normal=normalize(vec3(n.x,n.z,-n.y));
	}
	ALBEDO=albedo;
	NORMAL=normalize((VIEW_MATRIX*vec4(surface_normal,0.0)).xyz);
	ROUGHNESS=1.0;
}
