shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

// Every soft, wrap-lit surface shares this one shader, so the web build
// compiles a single program for all of them; `style` picks the surface.
// 0: textured leaves and grass, 1: clipped box hedge, 2: pennant flags.
uniform int style = 0;
uniform sampler2D leaf_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float wind_strength = 0.045;
uniform bool cutout = true;
uniform float soft_normals = 0.35;
uniform bool green_palette = false;
uniform vec4 leaf_dark : source_color = vec4(0.20,0.34,0.13,1.0);
uniform vec4 leaf_light : source_color = vec4(0.48,0.63,0.28,1.0);
// Flags flap away from the pole: UV.x is 0 at the pole and 1 at the tip.
uniform float wind = 1.0;
varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (style == 0) {
		float gust = sin(TIME * 0.85 + world.x * 0.27 + world.z * 0.19);
		float flutter = sin(TIME * 1.8 + world.z * 1.3 + world.x * 0.7);
		float weight = smoothstep(0.0, 0.8, VERTEX.y);
		VERTEX.x += (gust + flutter * 0.23) * wind_strength * weight;
		VERTEX.z += cos(TIME * 0.7 + world.x * 0.2) * wind_strength * weight * 0.4;
		NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), soft_normals));
	} else if (style == 2) {
		float wave=sin(TIME*4.6-UV.x*5.5+world.x*.37+world.z*.23)+sin(TIME*2.1-UV.x*2.5+world.z*.5)*.4;
		VERTEX+=NORMAL*wave*.16*UV.x*wind;
	}
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	if (style == 0) {
		vec4 tex = texture(leaf_texture, UV);
		vec3 color = tex.rgb;
		if (green_palette) {
			float value = clamp(max(tex.r,max(tex.g,tex.b))*1.8,0.0,1.0);
			color = mix(leaf_dark.rgb,leaf_light.rgb,value);
		}
		ALBEDO = color * tint.rgb * COLOR.rgb;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		ALPHA = cutout ? tex.a : 1.0;
		BACKLIGHT = ALBEDO * 0.12;
	} else if (style == 1) {
		// Planar noise on all three axes keeps clipped leaves on every face.
		float leaves=(noise(world.xy*4.0)+noise(world.zy*4.0)+noise(world.xz*4.0))/3.0;
		float clumps=(noise(world.xy*.9)+noise(world.zy*.9))*.5;
		float top=smoothstep(.4,.95,NORMAL.y*.5+.5);
		ALBEDO=mix(leaf_dark.rgb,leaf_light.rgb,clamp(leaves*.7+clumps*.3+top*.12,0.0,1.0));
		ROUGHNESS=1.0;
		ALPHA=1.0;
	} else {
		ALBEDO=COLOR.rgb;
		ROUGHNESS=.92;
		ALPHA=1.0;
		BACKLIGHT=ALBEDO*.25;
	}
}
