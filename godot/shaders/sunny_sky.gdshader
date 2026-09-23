shader_type sky;
render_mode use_debanding;

// Broad, soft cloud silhouettes keep the sky readable in low race cameras.
uniform float drift_speed = 0.001;

float puff(vec2 p, vec2 center, vec2 size) {
	return 1.0 - smoothstep(0.78, 1.0, length((p - center) / size));
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float height = max(direction.y, 0.0);
	vec3 sky = mix(vec3(0.73, 0.88, 0.98), vec3(0.20, 0.57, 0.87), pow(height, 0.48));
	if (direction.y < 0.0) {
		sky = mix(vec3(0.73, 0.88, 0.98), vec3(0.43, 0.58, 0.37), smoothstep(0.0, 0.18, -direction.y));
	}
	vec3 sun_direction = normalize(vec3(-0.38, 0.22, -1.0));
	float sun_distance = length(direction - sun_direction);
	float halo = exp(-sun_distance * sun_distance * 100.0);
	sky = mix(sky, vec3(1.0, 0.91, 0.65), halo * 0.45);
	float disc = 1.0 - smoothstep(0.033, 0.037, sun_distance);
	sky = mix(sky, vec3(1.0, 0.96, 0.78), disc);
	float angle = atan(direction.x, direction.z);
	float cloud = 0.0;
	for (int i = 0; i < 12; i++) {
		float index = float(i);
		float center = index * 0.523599 + TIME * drift_speed;
		float offset = atan(sin(angle - center), cos(angle - center));
		float elevation = 0.12 + 0.055 * sin(index * 2.4) + 0.06 * mod(index, 2.0);
		vec2 p = vec2(offset, direction.y - elevation);
		float size = 0.8 + 0.2 * sin(index * 5.7);
		float shape = puff(p, vec2(0.0, 0.0), vec2(0.15, 0.025) * size);
		shape = max(shape, puff(p, vec2(-0.04, 0.02), vec2(0.058, 0.04) * size));
		shape = max(shape, puff(p, vec2(0.025, 0.035), vec2(0.065, 0.055) * size));
		shape = max(shape, puff(p, vec2(0.085, 0.009), vec2(0.055, 0.029) * size));
		cloud = max(cloud, shape);
	}
	vec3 cloud_color = mix(vec3(0.85, 0.90, 0.93), vec3(1.0, 0.99, 0.94), smoothstep(0.06, 0.23, direction.y));
	sky = mix(sky, cloud_color, cloud * smoothstep(0.0, 0.06, direction.y) * 0.93);
	COLOR = sky;
}
