shader_type canvas_item;
render_mode unshaded;

// Anime focus lines: thin wedges converge on the framed subject at the centre
// of the lens. The seed changes a dozen times a second for a hand-drawn flicker.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.98, 0.9, 1.0);

float hash(float n) { return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453); }

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float radius = length(p);
	float around = atan(p.y, p.x) / 6.2831853 + 0.5;
	float count = 150.0;
	float id = floor(around * count);
	float cell = fract(around * count);
	float width = 0.12 + 0.3 * hash(id + 0.37);
	float soft = fwidth(around * count) * 1.5;
	float line = smoothstep(width + soft, width, abs(cell - 0.5) * 2.0) * step(0.42, hash(id));
	// Each line starts at its own distance, keeping the subject clear.
	float start = mix(0.62, 0.3, strength) + 0.28 * hash(id + 1.71);
	float reach = smoothstep(start, start + 0.22, radius);
	COLOR = vec4(tint.rgb, line * reach * strength * 0.8);
}
