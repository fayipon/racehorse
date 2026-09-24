shader_type canvas_item;
render_mode unshaded;

// A manga impact frame: for a few frames the view drops to dark ink and every
// silhouette edge burns gold. It darkens rather than flashing the screen.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ink : source_color = vec4(0.05, 0.07, 0.07, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.84, 0.45, 1.0);

float luma(vec2 uv) { return dot(texture(screen_texture, uv).rgb, vec3(0.3, 0.59, 0.11)); }

void fragment() {
	vec2 step_size = SCREEN_PIXEL_SIZE * 1.5;
	float gx = luma(SCREEN_UV + vec2(step_size.x, 0.0)) - luma(SCREEN_UV - vec2(step_size.x, 0.0));
	float gy = luma(SCREEN_UV + vec2(0.0, step_size.y)) - luma(SCREEN_UV - vec2(0.0, step_size.y));
	float edge = smoothstep(0.05, 0.14, length(vec2(gx, gy)));
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 impact = mix(ink.rgb * (0.7 + 0.9 * luma(SCREEN_UV)), glow.rgb, edge);
	COLOR = vec4(mix(color, impact, strength), 1.0);
}
