shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

// Every soft, wrap-lit surface shares this one shader, so the web build
// compiles a single program for all of them; `style` picks the surface.
// 0: textured leaves and grass, 1: clipped box hedge, 2: pennant flags,
// 3: bark of the grown trees.
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
// Grown trees and bushes (scripts/bake_trees.py) bake normals pointing out of
// each crown lump; both sides of a card keep that normal so the crown lights as
// one soft mass, and sunlight shines through the leaves from behind.
uniform bool crown_normals = false;
uniform float backlight = 0.12;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic;
// Clipped hedges (style 1) can be clothed in the bush leaves of the leaf
// atlas (its lower-left cell), projected on all three axes.
uniform bool leafy = false;
// Wind on grown plants: a plant bends from its foot, its top leaning `sway`
// metres at `sway_height` in a full gust, and the lean grows with the square
// of the height so the trunk stays planted. Gusts roll across the whole
// course, so neighbours move together; `flutter` shimmers single leaves.
// Bark and leaves of one tree share the numbers and bend as one.
uniform float sway = 0.0;
uniform float sway_height = 10.0;
uniform float flutter = 0.0;
const vec2 WIND = vec2(0.92, 0.39);
varying vec3 world;
varying vec3 crown_normal;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

float gust_at(vec2 place) {
	// A slow swell that travels downwind, with a quicker ripple on top.
	float swell = 0.55 + 0.45 * sin(TIME * 0.55 - dot(place, WIND) * 0.045);
	float ripple = sin(TIME * 1.7 - dot(place, WIND) * 0.12 + place.y * 0.05);
	return swell + ripple * 0.22;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway > 0.0) {
		vec3 foot = MODEL_MATRIX[3].xyz;
		float gust = gust_at(foot.xz);
		float lift = max(VERTEX.y, 0.0) / sway_height;
		float lean = lift * lift * sway;
		vec3 push = vec3(WIND.x, 0.0, WIND.y) * lean * gust;
		// Crowns also rock a little across the wind.
		push += vec3(-WIND.y, 0.0, WIND.x) * lean * 0.3 * sin(TIME * 1.15 + foot.x * 0.21 + foot.z * 0.17);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
		if (flutter > 0.0) {
			float leaf = fract(sin(dot(VERTEX.xz + VERTEX.y, vec2(12.9898, 78.233))) * 43758.5453);
			VERTEX += NORMAL * flutter * (0.35 + 0.65 * gust) * sin(TIME * (4.5 + leaf * 3.5) + leaf * 6.2832) * min(lift * 3.0, 1.0);
		}
	}
	if (style == 0 && sway > 0.0) {
		crown_normal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	} else if (style == 0) {
		float gust = sin(TIME * 0.85 + world.x * 0.27 + world.z * 0.19);
		float quiver = sin(TIME * 1.8 + world.z * 1.3 + world.x * 0.7);
		float weight = smoothstep(0.0, 0.8, VERTEX.y);
		VERTEX.x += (gust + quiver * 0.23) * wind_strength * weight;
		VERTEX.z += cos(TIME * 0.7 + world.x * 0.2) * wind_strength * weight * 0.4;
		NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), soft_normals));
		crown_normal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
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
		BACKLIGHT = ALBEDO * backlight;
		if (crown_normals) NORMAL = normalize(crown_normal);
	} else if (style == 3) {
		ALBEDO = texture(leaf_texture, UV).rgb * COLOR.rgb;
		NORMAL_MAP = texture(bark_normal, UV).rgb;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		ALPHA = 1.0;
	} else if (style == 1) {
		// Planar noise on all three axes keeps clipped leaves on every face.
		float leaves=(noise(world.xy*4.0)+noise(world.zy*4.0)+noise(world.xz*4.0))/3.0;
		float clumps=(noise(world.xy*.9)+noise(world.zy*.9))*.5;
		float top=smoothstep(.4,.95,NORMAL.y*.5+.5);
		ALBEDO=mix(leaf_dark.rgb,leaf_light.rgb,clamp(leaves*.7+clumps*.3+top*.12,0.0,1.0));
		if (leafy) {
			vec3 axis = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			axis = pow(axis, vec3(4.0));
			axis /= axis.x + axis.y + axis.z;
			vec3 sprigs = vec3(0.0);
			float cover = 0.0;
			vec2 planes[3] = vec2[3](world.zy, world.xz, world.xy);
			for (int k = 0; k < 3; k++) {
				// The dense middle of the bush cluster, so tiles join leaf to leaf;
				// a second, offset layer covers the joins of the first.
				vec2 p = planes[k] * 1.6;
				vec2 q = p + vec2(0.5, 0.37);
				vec4 leaf = textureGrad(leaf_texture, (fract(p) * 0.4 + 0.3) * 0.5 + vec2(0.0, 0.5), dFdx(p) * 0.2, dFdy(p) * 0.2);
				vec4 over = textureGrad(leaf_texture, (fract(q) * 0.4 + 0.3) * 0.5 + vec2(0.0, 0.5), dFdx(q) * 0.2, dFdy(q) * 0.2);
				float seam = max(abs(fract(p.x) - 0.5), abs(fract(p.y) - 0.5)) * 2.0;
				leaf = mix(leaf, over, smoothstep(0.6, 0.95, seam));
				float w = k == 0 ? axis.x : k == 1 ? axis.y : axis.z;
				sprigs += leaf.rgb * leaf.a * w;
				cover += leaf.a * w;
			}
			// Gaps between sprigs look into the hedge's dark inside.
			ALBEDO = mix(leaf_dark.rgb * 0.45, sprigs / max(cover, 0.001) * mix(0.85, 1.15, clumps), clamp(cover * 1.4, 0.0, 1.0));
		}
		ROUGHNESS=1.0;
		ALPHA=1.0;
	} else {
		ALBEDO=COLOR.rgb;
		ROUGHNESS=.92;
		ALPHA=1.0;
		BACKLIGHT=ALBEDO*.25;
	}
}
