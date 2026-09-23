shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float wind_strength = 0.045;
uniform bool cutout = true;
uniform float soft_normals = 0.35;
uniform bool green_palette = false;
uniform vec4 leaf_dark : source_color = vec4(0.20,0.34,0.13,1.0);
uniform vec4 leaf_light : source_color = vec4(0.48,0.63,0.28,1.0);

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 0.85 + world.x * 0.27 + world.z * 0.19);
	float flutter = sin(TIME * 1.8 + world.z * 1.3 + world.x * 0.7);
	float weight = smoothstep(0.0, 0.8, VERTEX.y);
	VERTEX.x += (gust + flutter * 0.23) * wind_strength * weight;
	VERTEX.z += cos(TIME * 0.7 + world.x * 0.2) * wind_strength * weight * 0.4;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), soft_normals));
}

void fragment() {
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
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	BACKLIGHT = ALBEDO * 0.12;
}
