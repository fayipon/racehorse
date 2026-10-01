shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

// A far tree as one upright card turned to the view, painted from a picture of
// the grown 3D tree (tools/bake_impostors.gd) with its crown normals, so the
// card lights like the tree it stands in for. In the shadow pass the card
// turns to the sun and casts the tree's silhouette.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
// The same wind as the grown trees (foliage.gdshader): the card's upper part
// leans with the gusts, seen side-on as a shift across the card.
uniform float sway = 0.0;
uniform float sway_height = 10.0;
const vec2 WIND = vec2(0.92, 0.39);

void vertex() {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 facing = normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	if (sway > 0.0) {
		vec2 foot = MODEL_MATRIX[3].xz;
		float gust = 0.55 + 0.45 * sin(TIME * 0.55 - dot(foot, WIND) * 0.045) + 0.22 * sin(TIME * 1.7 - dot(foot, WIND) * 0.12 + foot.y * 0.05);
		float lift = max(VERTEX.y, 0.0) / sway_height;
		VERTEX.x += dot(vec3(WIND.x, 0.0, WIND.y), right) * lift * lift * sway * gust;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(facing, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 picture = texture(albedo_texture, UV);
	ALBEDO = picture.rgb * COLOR.rgb;
	ALPHA = picture.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	ROUGHNESS = 1.0;
	BACKLIGHT = ALBEDO * 0.25;
}
