shader_type spatial;
render_mode unshaded, cull_disabled;

// tools/bake_impostors.gd draws each grown tree twice with this: once for its
// colour (with the baked ambient occlusion) and once for its normals, written
// so that the saved 8-bit picture holds n * 0.5 + 0.5 exactly.
uniform sampler2D picture : source_color, filter_linear_mipmap;
uniform bool normals = false;
varying vec3 view_normal;

void vertex() {
	view_normal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float to_linear(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

void fragment() {
	vec4 texel = texture(picture, UV);
	if (normals) {
		vec3 n = normalize(view_normal) * 0.5 + 0.5;
		ALBEDO = vec3(to_linear(n.x), to_linear(n.y), to_linear(n.z));
	} else {
		ALBEDO = texel.rgb * COLOR.rgb;
	}
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
