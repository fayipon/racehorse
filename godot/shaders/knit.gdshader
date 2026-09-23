shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 color : source_color = vec4(0.65,0.27,0.23,1.0);
uniform float stitch_scale = 20.0;
varying vec3 local_position;
varying vec3 local_normal;

float stitch(vec2 p) {
	vec2 cell = fract(p) - 0.5;
	// Two diagonal strands form a repeating V-shaped knit stitch.
	float diagonal = abs(abs(cell.x) - (0.12 + (cell.y + 0.5) * 0.45));
	float strand = exp(-diagonal * diagonal * 115.0);
	float fiber = 0.88 + 0.12 * sin((cell.y + abs(cell.x)) * 105.0);
	return strand * fiber;
}

float fabric(vec3 p, vec3 weights) {
	return stitch(p.zy) * weights.x + stitch(p.xz) * weights.y + stitch(p.xy) * weights.z;
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(normalize(local_normal)), vec3(5.0));
	w /= max(w.x+w.y+w.z, 0.001);
	vec3 p = local_position * stitch_scale;
	float height = fabric(p,w);
	float detail = 1.0 - smoothstep(0.10,0.7,length(fwidth(p)));
	ALBEDO = color.rgb * mix(0.9,0.66 + height * 0.34,detail);
	// Derivative-based bump avoids tangent seams on the sculpted mesh.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy,NORMAL);
	vec3 r2 = cross(NORMAL,dpdx);
	float determinant = dot(dpdx,r1);
	vec3 gradient = sign(determinant) * (dFdx(height)*r1+dFdy(height)*r2);
	NORMAL = normalize(abs(determinant)*NORMAL - 0.003*detail*gradient);
	ROUGHNESS = 0.96;
	SPECULAR = 0.16;
	RIM = 0.07;
	RIM_TINT = 0.8;
}
