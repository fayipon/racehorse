shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// A racing saddlecloth: quilted cotton with a rolled binding, rounded lower
// corners and the runner's number printed on each flank. UV is (across, along)
// in metres, across signed from the spine; UV2 is the distance to the nearer
// hem and to the nearer end. Every detail keeps its size on any body.
uniform vec3 cloth : source_color = vec3(0.4,0.52,0.82);
uniform vec3 binding : source_color = vec3(0.94,0.91,0.84);
uniform vec3 ink : source_color = vec3(1.0);
uniform int number = 1;
// The numeral's centre: its distance up from the hem and along from the front.
uniform vec2 number_at = vec2(0.2,0.3);
uniform sampler2D digits : source_color, filter_linear_mipmap, repeat_disable;

const float BINDING = 0.038;
const float CORNER = 0.085;
const float QUILT = 0.09;
// Numeral cells are 0.8 as wide as high; two-digit numbers set condensed.
const float NUMERAL = 0.32;
const float CELL = 0.8;

void fragment() {
	vec2 edge = UV2;
	// Distance inside the cloth's outline, with the lower corners rounded.
	float inside = min(edge.x, edge.y);
	vec2 corner = max(vec2(CORNER) - edge, vec2(0.0));
	if (corner.x > 0.0 && corner.y > 0.0) {
		inside = CORNER - length(corner);
	}
	if (inside < 0.0) {
		discard;
	}
	float px = max(fwidth(inside), 1e-4);
	float fine = 1.0 - smoothstep(0.0015, 0.006, px);
	float body = smoothstep(BINDING - px, BINDING + px, inside);

	// Diamond quilting: each pillow rises from its stitched seams.
	vec2 q = vec2(UV.x + UV.y, UV.x - UV.y) / QUILT;
	vec2 f = fract(q) - 0.5;
	float pillow = pow(max((1.0 - 4.0 * f.x * f.x) * (1.0 - 4.0 * f.y * f.y), 0.0), 0.3);
	float quilted = body * (1.0 - smoothstep(0.12, 0.45, length(fwidth(q))));
	// The binding is a rolled edge, with a running stitch just inside it.
	float roll = 1.0 - body;
	float rolled = sqrt(max(1.0 - pow((inside - BINDING * 0.5) / (BINDING * 0.5), 2.0), 0.0));
	float along_edge = edge.x < edge.y ? UV.y : UV.x;
	float stitch = step(0.45, fract(along_edge / 0.014)) * (1.0 - smoothstep(0.0012, 0.0012 + px, abs(inside - BINDING - 0.007))) * fine;
	float height = mix(pillow, rolled * 1.3, roll) * mix(1.0, quilted, body);

	vec3 color = mix(binding, cloth, body);
	color *= mix(1.0, 0.86 + 0.14 * pillow, quilted);
	color = mix(color, cloth * 0.55, stitch * body);

	// The number, printed flat on each flank, read from that side.
	if (FRONT_FACING) {
		vec2 t = vec2((UV.y - number_at.y) * (UV.x < 0.0 ? 1.0 : -1.0), edge.x - number_at.x) / NUMERAL;
		int count = number >= 10 ? 2 : 1;
		float squeeze = count == 2 ? 0.8 : 1.0;
		float slot = CELL * 0.82 * squeeze;
		float x = t.x + slot * float(count) * 0.5;
		float k = floor(x / slot);
		if (k >= 0.0 && k < float(count) && abs(t.y) < 0.5) {
			int digit = count == 1 ? number : (k < 0.5 ? number / 10 : number % 10);
			float cx = (x - (k + 0.5) * slot) / (CELL * squeeze) + 0.5;
			vec2 uv = vec2((float(digit) + clamp(cx, 0.0, 1.0)) / 10.0, 0.5 - t.y);
			vec2 scale = vec2(1.0 / (CELL * squeeze * 10.0), -1.0);
			float printed = textureGrad(digits, uv, dFdx(t) * scale, dFdy(t) * scale).a;
			color = mix(color, ink, printed * body);
			height *= 1.0 - printed * 0.6;
		}
	}
	ALBEDO = color;
	// Derivative-based bump, as the knit uses: no tangents on a fitted sheet.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float determinant = dot(dpdx, r1);
	vec3 gradient = sign(determinant) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(determinant) * NORMAL - 0.004 * mix(1.0, fine, body) * gradient);
	ROUGHNESS = mix(0.9, 0.72, roll);
	SPECULAR = 0.3;
	// Cotton's soft sheen at grazing angles.
	RIM = 0.12;
	RIM_TINT = 0.6;
}
