shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// A planted sun emblem: gold disc, orange rays, a cream path ring and a clipped
// box-hedge edge on a dark foliage ground.
uniform vec4 foliage : source_color = vec4(0.19,0.33,0.16,1.0);
uniform vec4 gold : source_color = vec4(0.98,0.78,0.22,1.0);
uniform vec4 orange : source_color = vec4(0.93,0.46,0.18,1.0);
uniform vec4 cream : source_color = vec4(0.95,0.91,0.80,1.0);
uniform float rays = 12.0;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }

void fragment() {
	vec2 p=UV*2.0-1.0;
	float r=length(p);
	if (r>1.0) discard;
	float angle=atan(p.y,p.x);
	float ray=abs(fract(angle/6.2831853*rays)-.5)*2.0;
	float ray_mask=step(r,.9-ray*.38)*step(.5,r);
	float core=step(r,.4);
	float path=step(.42,r)*step(r,.47)+step(.93,r);
	// Tiny blossoms break up the flat colour into planted texture.
	float blossom=step(.5,hash(floor(UV*120.0)));
	vec3 color=foliage.rgb*(.85+blossom*.2);
	color=mix(color,orange.rgb*(.86+blossom*.2),ray_mask);
	color=mix(color,gold.rgb*(.88+blossom*.16),core);
	color=mix(color,cream.rgb,path);
	ALBEDO=color;
	ROUGHNESS=1.0;
}
