shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Built surfaces of the course: stands, the starting gate, the podium. One
// shader draws them all so a whole structure is one draw call and the web build
// compiles one program. The vertex colour is the surface's tint; its alpha
// picks what it is made of (mesh_kit.gd names the codes):
//   1.0 paint     .9 concrete   .8 glazing    .7 metal      .6 seat plastic
//   .5 paving     .4 canvas     .3 rubber     .2 gold       .125 damask
//   .1 marble     .05 padding
// Detail is drawn in world space, so pieces join without seams and keep their
// scale on any size of part.
uniform bool ground_shade = true;
// Glazing looks into rooms: one room is this wide, tall and deep (metres), and
// rooms stack from y = room_floor.
uniform vec3 room = vec3(3.25, 3.3, 4.5);
uniform float room_floor = 0.0;
varying vec3 world;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p = p * 2.03 + vec2(17.1, 9.4); a *= 0.5; }
	return v;
}

// The face's own plane: across, up the face (or along z on a floor) and out.
void face_frame(vec3 n, out vec3 across, out vec3 up) {
	if (abs(n.y) > 0.7) {
		across = vec3(1.0, 0.0, 0.0);
		up = vec3(0.0, 0.0, 1.0);
	} else {
		across = normalize(cross(vec3(0.0, 1.0, 0.0), n));
		up = vec3(0.0, 1.0, 0.0);
	}
}

// Detail on whichever plane the face mostly lies in.
float planar(vec3 p, vec3 n, float scale) {
	vec3 a = abs(n);
	vec2 uv = a.y > a.x && a.y > a.z ? p.xz : a.x > a.z ? p.zy : p.xy;
	return fbm(uv * scale);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// A room behind a pane: the view ray is followed into a box of `room` and the
// first wall it meets is shaded. Rooms differ by their hash; some keep their
// blinds half down, all have a ceiling of downlights.
vec3 interior(vec3 p, vec3 n, vec3 view_dir, out float frame) {
	vec3 across, up;
	face_frame(n, across, up);
	vec2 at = vec2(dot(p, across), p.y - room_floor);
	vec2 cell = floor(at / room.xy);
	vec2 local = fract(at / room.xy);
	float seed = hash(cell + vec2(3.1, 7.7));
	// Mullions: the room's own frame, and a light bar between two panes.
	vec2 edge = min(local, 1.0 - local) * room.xy;
	float mid = abs(local.x - 0.5) * room.x;
	frame = 1.0 - smoothstep(0.035, 0.06, min(min(edge.x, edge.y), mid + 0.012));
	// Into the room: x across, y up, z deeper.
	vec3 d = vec3(dot(view_dir, across), dot(view_dir, up), -dot(view_dir, n));
	vec3 o = vec3(local, 0.0);
	vec3 scale = vec3(1.0 / room.x, 1.0 / room.y, 1.0 / room.z);
	vec3 r = d * scale;
	vec3 t_wall = vec3(
		r.x > 0.0 ? (1.0 - o.x) / r.x : -o.x / min(r.x, -1e-5),
		r.y > 0.0 ? (1.0 - o.y) / r.y : -o.y / min(r.y, -1e-5),
		(1.0) / max(r.z, 1e-5));
	float t = min(min(t_wall.x, t_wall.y), t_wall.z);
	vec3 hit = o + r * t;
	vec3 warm = mix(vec3(0.95, 0.83, 0.66), vec3(0.82, 0.86, 0.9), step(0.7, seed));
	vec3 color;
	if (t == t_wall.z) {
		// Back wall: panelled, with a counter and the odd silhouette before it.
		color = warm * mix(0.42, 0.55, step(0.5, fract(hit.x * 3.0)));
		float counter = step(hit.y, 0.32) * step(0.1, hit.x) * step(hit.x, 0.9);
		color = mix(color, vec3(0.16, 0.12, 0.1), counter);
		float figure = step(0.55, seed) * step(abs(hit.x - fract(seed * 7.3) * 0.7 - 0.15), 0.05 + 0.03 * step(hit.y, 0.4)) * step(hit.y, 0.55);
		color = mix(color, vec3(0.1, 0.1, 0.12), figure);
	} else if (t == t_wall.y) {
		if (r.y > 0.0) {
			// Ceiling with a row of downlights.
			vec2 lamp = vec2(fract(hit.x * 2.0) - 0.5, (hit.z - 0.45) * 2.2);
			color = warm * 0.45 + vec3(1.0, 0.92, 0.78) * smoothstep(0.2, 0.0, length(lamp)) * 1.6;
		} else {
			color = mix(vec3(0.28, 0.2, 0.16), vec3(0.36, 0.3, 0.26), step(0.5, seed)) * (0.7 + 0.3 * hit.z);
		}
	} else {
		color = warm * 0.5 * (0.75 + 0.25 * hit.z);
	}
	// Light falls off toward the back of the room.
	color *= mix(1.0, 0.6, hit.z);
	// Some rooms keep the blind half down.
	float blind = step(0.72, seed) * step(1.0 - (0.25 + fract(seed * 13.0) * 0.35), local.y);
	color = mix(color, vec3(0.78, 0.76, 0.7) * (0.85 + 0.15 * step(0.5, fract(local.y * 40.0))), blind);
	return color;
}

void fragment() {
	vec3 tint = COLOR.rgb;
	float tag = COLOR.a;
	vec3 n = normalize(world_normal);
	float grain = planar(world, n, 6.0);
	float broad = planar(world, n, 0.35);
	vec3 albedo = tint;
	float rough = 0.55;
	float spec = 0.4;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float bump = 0.0;
	if (tag > 0.95) {
		// Paint: a satin finish over a faintly uneven surface.
		albedo *= 0.96 + 0.06 * broad + 0.03 * grain;
		rough = 0.42;
		spec = 0.45;
	} else if (tag > 0.85) {
		// Concrete: fine aggregate, cloudy pours and rain streaks down walls.
		float streak = abs(n.y) < 0.5 ? noise(vec2(dot(world, vec3(n.z, 0.0, -n.x)) * 3.0, world.y * 0.15)) : 0.5;
		albedo *= 0.84 + 0.14 * broad + 0.1 * grain - 0.06 * smoothstep(0.55, 0.9, streak);
		rough = 0.9;
		spec = 0.25;
		bump = grain * 0.4;
	} else if (tag > 0.75) {
		float frame;
		vec3 view_dir = normalize(world - CAMERA_POSITION_WORLD);
		vec3 room_light = interior(world, n, view_dir, frame);
		float fresnel = pow(1.0 - clamp(dot(-view_dir, n), 0.0, 1.0), 3.0);
		albedo = mix(vec3(0.02, 0.025, 0.03), tint * 0.8, frame);
		emit = room_light * (1.0 - frame) * (1.0 - fresnel * 0.85) * 0.55;
		rough = mix(0.04, 0.4, frame);
		spec = mix(0.75, 0.4, frame);
		metal = frame * 0.6;
	} else if (tag > 0.65) {
		// Brushed metal.
		albedo *= 0.9 + 0.1 * noise(vec2(dot(world.xz, vec2(1.0)) * 0.6, world.y * 40.0));
		rough = 0.32;
		metal = 0.85;
		spec = 0.5;
	} else if (tag > 0.55) {
		// Moulded seat plastic.
		albedo *= 0.94 + 0.08 * grain;
		rough = 0.38;
		spec = 0.5;
	} else if (tag > 0.45) {
		// Paving: 0.6 m slabs with sanded joints.
		vec2 slab = world.xz / vec2(0.6, 0.6);
		vec2 joint = min(fract(slab), 1.0 - fract(slab));
		float line = 1.0 - smoothstep(0.012, 0.03, min(joint.x, joint.y));
		albedo *= (0.9 + 0.1 * hash(floor(slab)) + 0.06 * grain) * (1.0 - 0.28 * line);
		rough = 0.85;
		spec = 0.3;
	} else if (tag > 0.35) {
		// Canvas: a tight weave that glows where the sun comes through.
		albedo *= 0.93 + 0.05 * grain + 0.04 * step(0.5, fract(dot(world, vec3(9.0))));
		rough = 0.95;
		spec = 0.2;
		BACKLIGHT = albedo * 0.35;
	} else if (tag > 0.25) {
		albedo *= 0.9 + 0.12 * grain;
		rough = 0.75;
		spec = 0.3;
	} else if (tag > 0.15) {
		// Gold leaf.
		albedo = tint * (0.92 + 0.12 * broad);
		rough = 0.24 + 0.1 * grain;
		metal = 1.0;
		spec = 0.5;
	} else if (tag > 0.1125) {
		// Damask wall covering: a tone-on-tone lattice of leaves with a satin sheen.
		vec3 across, up;
		face_frame(n, across, up);
		vec2 q = vec2(dot(world, across), world.y) / vec2(0.7, 0.9);
		vec2 cell = fract(q + vec2(0.5 * mod(floor(q.y), 2.0), 0.0)) - 0.5;
		vec2 d = abs(cell);
		float leaf = 1.0 - smoothstep(0.0, 0.04, abs(length(d * vec2(1.0, 0.7) - vec2(0.12, 0.08)) - 0.16));
		float lattice = 1.0 - smoothstep(0.0, 0.025, abs(d.x + d.y - 0.42));
		float motif = max(leaf, lattice * 0.7);
		albedo *= 0.9 + 0.16 * motif + 0.04 * grain;
		rough = mix(0.75, 0.45, motif);
		spec = 0.35;
	} else if (tag > 0.075) {
		// Polished marble: soft clouds and fine veins wandering through a pale stone.
		vec3 a = abs(n);
		vec2 uv = a.y > a.x && a.y > a.z ? world.xz : a.x > a.z ? world.zy : world.xy;
		float warp = fbm(uv * 0.6);
		float vein = 1.0 - abs(sin((uv.x * 0.9 + uv.y * 0.5 + warp * 3.2) * 2.0));
		float fine_vein = 1.0 - abs(sin((uv.y * 1.6 - uv.x * 0.7 + fbm(uv * 1.3 + 4.0) * 4.0) * 2.7));
		float veins = pow(vein, 26.0) * 0.8 + pow(fine_vein, 40.0) * 0.5;
		float cloud = fbm(uv * 0.9 + 7.0);
		albedo = tint * (0.93 + 0.08 * cloud) * (1.0 - 0.12 * clamp(veins, 0.0, 1.0));
		rough = 0.14;
		spec = 0.55;
	} else {
		// Padding: vinyl in upright stitched channels, a seam every 0.9 m.
		vec3 across, up;
		face_frame(n, across, up);
		float x = dot(world, across) / 0.2;
		float f = fract(x) - 0.5;
		float channel = 1.0 - 4.0 * f * f;
		float seam = smoothstep(0.47, 0.492, abs(fract(world.y / 0.9) - 0.5));
		albedo *= (0.9 + 0.1 * pow(max(channel, 0.0), 0.5)) * (1.0 - 0.18 * seam) * (0.97 + 0.04 * grain);
		rough = 0.42;
		spec = 0.5;
		bump = channel * 0.5 - seam * 0.3;
	}
	// Surfaces near the ground sit in the soft shade of what stands round them.
	if (ground_shade) albedo *= mix(0.72, 1.0, smoothstep(0.0, 0.9, world.y));
	if (bump != 0.0) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 g = sign(det) * (dFdx(bump) * r1 + dFdy(bump) * r2);
		NORMAL = normalize(abs(det) * NORMAL - 0.02 * g);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = emit;
}
