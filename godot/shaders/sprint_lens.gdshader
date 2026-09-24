shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float rush : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 uv = SCREEN_UV;
    // Keep the runners sharp and soften only peripheral ground and stands.
    float side = smoothstep(0.28, 0.50, abs(uv.x - 0.5));
    float ground = smoothstep(0.18, 0.48, abs(uv.y - 0.43));
    float edge = max(side, ground);
    vec2 offset = vec2((5.0 + 5.0 * rush) * SCREEN_PIXEL_SIZE.x * strength * edge, 0.0);
    vec3 color = texture(screen_texture, uv).rgb * 0.40;
    color += texture(screen_texture, uv + offset * 0.5).rgb * 0.20;
    color += texture(screen_texture, uv - offset * 0.5).rgb * 0.20;
    color += texture(screen_texture, uv + offset).rgb * 0.10;
    color += texture(screen_texture, uv - offset).rgb * 0.10;
    color *= mix(vec3(1.0), vec3(1.025, 1.008, 0.985), strength);
    COLOR = vec4(color, 1.0);
}
