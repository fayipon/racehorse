shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// A runner's tack, fitted to its body (asset_horse.gd): `part` 0 is the racing
// saddlecloth, 1 the leather saddle on it, 2 the elastic over-girth.
// Cloth and saddle share UV: (across, along) in metres, across signed from the
// spine, along from the cloth's front edge, so every detail keeps its size on
// any body. On the cloth, UV2 is the distance to the nearer hem and to the
// nearer end, and COLOR.r how freely that part hangs (1 at the hem).
// The girth's UV runs round the body (metres) and across the band (0 to 1).
uniform int part = 0;
uniform vec3 cloth : source_color = vec3(0.4,0.52,0.82);
uniform vec3 ink : source_color = vec3(1.0);
uniform int number = 1;
// The numeral's centre: its distance up from the hem and along from the front.
uniform vec2 number_at = vec2(0.25,0.6);
uniform sampler2D digits : source_color, filter_linear_mipmap, repeat_disable;
// Where the saddle sits, metres back from the cloth's front edge.
uniform float saddle_at = 0.4;
// How hard the horse is moving (0 standing, 1 at a gallop), and its own beat.
uniform float stride = 0.0;
uniform float phase = 0.0;
// The horse's tail-ward direction in the mesh's space.
uniform vec3 along_axis = vec3(0.0, 0.0, 1.0);

const float BINDING = 0.026;
const float CORNER = 0.085;
// Numeral cells are 0.8 as wide as high; two-digit numbers set condensed.
const float NUMERAL = 0.34;
const float CELL = 0.8;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Signed distance into the saddle's outline (metres, positive inside): an
// oval seat over the spine, and a rounded flap down each side of it.
float saddle_inside(vec2 uv) {
	float seat = (1.0 - length(vec2(uv.x / 0.17, (uv.y - saddle_at) / 0.24))) * 0.17;
	vec2 q = abs(vec2(abs(uv.x) - 0.28, uv.y - saddle_at - 0.02)) - vec2(0.22, 0.16) + 0.06;
	float flap = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.06);
	return max(seat, flap);
}

void vertex() {
	if (part == 0) {
		// The skirt lifts and swings with the gait; the back stays put.
		float swing = COLOR.r * COLOR.r;
		float beat = TIME * mix(2.0, 13.2, stride) + phase;
		VERTEX += NORMAL * swing * (0.003 + 0.02 * stride) * (0.55 + 0.45 * sin(beat));
		VERTEX += along_axis * swing * 0.016 * stride * sin(beat * 0.5 + 1.3);
	}
}

// Bump from a height field, by screen derivatives: no tangents on a fitted sheet.
vec3 bumped(vec3 normal, vec3 vertex, float height, float strength) {
	vec3 dpdx = dFdx(vertex);
	vec3 dpdy = dFdy(vertex);
	vec3 r1 = cross(dpdy, normal);
	vec3 r2 = cross(normal, dpdx);
	float determinant = dot(dpdx, r1);
	vec3 gradient = sign(determinant) * (dFdx(height) * r1 + dFdy(height) * r2);
	return normalize(abs(determinant) * normal - strength * gradient);
}

void fragment() {
	if (part == 1) {
		// Saddle: smooth black-brown leather, a padded seat, a stitched edge.
		float inside = saddle_inside(UV);
		if (inside < 0.0) discard;
		float px = max(fwidth(inside), 1e-4);
		float seat = smoothstep(0.0, 0.02, (1.0 - length(vec2(UV.x / 0.15, (UV.y - saddle_at) / 0.21))));
		vec3 leather = mix(vec3(0.085, 0.06, 0.045), vec3(0.06, 0.045, 0.035), seat);
		float grain = noise(UV * 140.0) * 0.6 + noise(UV * 37.0) * 0.4;
		leather *= 0.85 + 0.25 * grain;
		float stitch = (1.0 - smoothstep(0.0012, 0.0012 + px, abs(inside - 0.012))) * step(0.5, fract((UV.x + UV.y) / 0.012));
		leather = mix(leather, vec3(0.42, 0.36, 0.27), stitch * 0.8);
		// The cut edge rolls away darker.
		leather *= mix(0.55, 1.0, smoothstep(0.0, 0.01, inside));
		ALBEDO = leather;
		NORMAL = bumped(NORMAL, VERTEX, grain * 0.4 + smoothstep(0.0, 0.012, inside), 0.004);
		ROUGHNESS = mix(0.5, 0.36, seat);
		SPECULAR = 0.5;
		RIM = 0.2;
		RIM_TINT = 0.3;
	} else if (part == 2) {
		// Over-girth: white elastic webbing, ribbed across, edged in a bound seam.
		float rib = 0.5 + 0.5 * sin(UV.x * 520.0);
		float fine = 1.0 - smoothstep(0.0, 0.004, fwidth(UV.x * 520.0) * 0.01);
		float edge = smoothstep(0.0, 0.12, UV.y) * smoothstep(0.0, 0.12, 1.0 - UV.y);
		vec3 webbing = vec3(0.9, 0.89, 0.85) * (0.92 + 0.08 * rib * fine) * mix(0.75, 1.0, edge);
		ALBEDO = webbing;
		NORMAL = bumped(NORMAL, VERTEX, rib * fine * 0.5 + edge, 0.002);
		ROUGHNESS = 0.7;
		SPECULAR = 0.3;
	} else {
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
		// Cotton drill: a diagonal twill, and soft creases where the skirt hangs.
		float twill = 0.5 + 0.5 * sin((UV.x * 0.8 + UV.y) * 900.0);
		float hang = clamp(COLOR.r, 0.0, 1.0);
		float crease = noise(vec2(UV.x * 5.0, UV.y * 2.2) + phase) * 0.6 + noise(vec2(UV.x * 11.0, UV.y * 4.0) - phase) * 0.4;
		float drape = crease * (0.25 + 0.75 * hang);
		// The binding is a rolled edge in a deeper shade, stitched just inside.
		float rolled = sqrt(max(1.0 - pow((inside - BINDING * 0.5) / (BINDING * 0.5), 2.0), 0.0));
		float along_edge = edge.x < edge.y ? UV.y : UV.x;
		float stitch = step(0.45, fract(along_edge / 0.012)) * (1.0 - smoothstep(0.001, 0.001 + px, abs(inside - BINDING - 0.006))) * fine;
		vec3 piping = cloth * 0.6;
		vec3 color = mix(piping, cloth, body);
		color *= 0.94 + 0.06 * twill * fine;
		color *= 0.86 + 0.16 * drape;
		color = mix(color, cloth * 0.45, stitch * body);
		// Pressed down round the saddle, the cloth lies in its shadow.
		float near_saddle = saddle_inside(UV);
		color *= mix(0.62, 1.0, smoothstep(0.0, 0.05, -near_saddle));
		float height = mix(drape * 0.6 + twill * fine * 0.08, rolled * 1.2, 1.0 - body);
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
				color = mix(color, ink * (0.94 + 0.06 * twill * fine), printed * body);
				height *= 1.0 - printed * 0.5;
			}
		}
		ALBEDO = color;
		NORMAL = bumped(NORMAL, VERTEX, height, 0.0045);
		ROUGHNESS = mix(0.86, 0.7, 1.0 - body);
		SPECULAR = 0.25;
		// Cotton's soft sheen at grazing angles.
		RIM = 0.22;
		RIM_TINT = 0.65;
		BACKLIGHT = cloth * 0.12;
	}
}
