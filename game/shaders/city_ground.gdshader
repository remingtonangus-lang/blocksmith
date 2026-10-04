// The Capital's podium surface, drawn analytically from the plan (CapitalCity.is_open uses the same rules):
// grid avenues with lane markings and curbs, sidewalks, radial boulevards, ring roads, the central plaza in
// white stone, park blocks as lawns with paths, and warm lamp light on the pavement at night.
shader_type spatial;

#include "res://shaders/common.gdshaderinc"

uniform vec2 center;
uniform float block = 150.0;
uniform float avenue = 26.0;
uniform float boulevard = 44.0;
uniform float radius = 1500.0;
uniform sampler2D parks : filter_nearest;
uniform float parks_n = 12.0;
uniform float lamp_glow = 0.0;
global uniform float weather_wetness;
global uniform float night;

varying vec3 v_w;

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_w.xz - center;
	float d = length(p);
	vec3 white = vec3(0.72, 0.73, 0.72);
	vec3 asphalt = vec3(0.07, 0.072, 0.078);
	vec3 col = white;
	float rough = 0.55;
	float road = 0.0;
	float mark = 0.0;
	float dist = length(v_w - CAMERA_POSITION_WORLD);
	float aa = clamp(dist / 600.0, 0.0, 1.0);
	// Grid avenues.
	vec2 g = mod(p + block * 0.5, block);
	vec2 gc = min(g, block - g);                 // distance to the nearest avenue centre line, per axis
	float half_w = avenue * 0.5;
	float carriage = half_w - 4.0;
	float on_x = step(gc.y, carriage);           // street running along x (centre z = k * block)
	float on_z = step(gc.x, carriage);
	road = max(on_x, on_z);
	// Lane markings: centre line dashes and lane edges.
	float dash_x = step(abs(gc.y), 0.12) * step(0.5, fract(p.x / 8.0));
	float dash_z = step(abs(gc.x), 0.12) * step(0.5, fract(p.y / 8.0));
	float lane_x = step(abs(gc.y - 4.5), 0.08) * step(0.6, fract(p.x / 5.0));
	float lane_z = step(abs(gc.x - 4.5), 0.08) * step(0.6, fract(p.y / 5.0));
	float edge_x = step(abs(gc.y - (carriage - 0.6)), 0.1);
	float edge_z = step(abs(gc.x - (carriage - 0.6)), 0.1);
	mark = on_x * max(max(dash_x, lane_x), edge_x) * (1.0 - on_z) + on_z * max(max(dash_z, lane_z), edge_z) * (1.0 - on_x);
	// Crossings: zebra stripes where avenues meet.
	float cross = on_x * on_z;
	// Curbs and sidewalks.
	float side = max(step(gc.y, half_w), step(gc.x, half_w)) * (1.0 - road);
	float curb = max(step(abs(gc.y - carriage), 0.25), step(abs(gc.x - carriage), 0.25)) * max(step(gc.y, half_w), step(gc.x, half_w));
	// Radial boulevards and rings.
	for (int k = 0; k < 8; k++) {
		float a = 6.2831853 * float(k) / 8.0;
		vec2 dir = vec2(cos(a), sin(a));
		float along = dot(p, dir);
		float across = abs(dot(p, vec2(-dir.y, dir.x)));
		if (along > 300.0 && across < boulevard * 0.5) {
			float lane = across < boulevard * 0.5 - 5.0 ? 1.0 : 0.0;
			road = max(road, lane);
			side = max(side, 1.0 - lane);
			float median = step(across, 1.6);
			mark = mix(mark, 0.0, lane);
			mark = max(mark, lane * step(abs(across - 8.0), 0.1) * step(0.5, fract(along / 9.0)));
			if (median > 0.5) { road = 0.0; side = 0.0; }
		}
	}
	float ring1 = step(abs(d - 330.0), 12.0);
	float ring2 = step(abs(d - 900.0), 14.0);
	road = max(road, max(ring1, ring2));
	// Central plaza: white stone in rings and radial joints.
	float plaza = step(d, 300.0);
	// Park blocks.
	vec2 bi = floor((p + block * 0.5) / block);
	vec2 tuv = (bi + parks_n + 0.5) / (parks_n * 2.0 + 1.0);
	float park = texture(parks, tuv).r * (1.0 - road) * (1.0 - side) * (1.0 - plaza);
	if (plaza > 0.5) {
		float rj = step(abs(fract(d / 6.0) - 0.5), 0.02);
		float aj = step(abs(fract(atan(p.y, p.x) / 6.2831853 * 96.0) - 0.5), 0.03);
		col = white * (1.0 - max(rj, aj) * 0.15 * (1.0 - aa)) * mix(0.97, 1.02, hash12(floor(vec2(d / 6.0, atan(p.y, p.x) * 15.0))));
		rough = 0.42;
	} else if (road > 0.5) {
		float n = vnoise(v_w.xz * 0.9);
		col = asphalt * mix(0.85, 1.15, n);
		col = mix(col, vec3(0.85), mark * (1.0 - aa * 0.6));
		if (cross > 0.5) {
			float zebra = step(0.5, fract((gc.x + gc.y) / 1.2)) * step(min(gc.x, gc.y), carriage) * step(carriage - 6.0, max(gc.x, gc.y));
			col = mix(col, vec3(0.85), zebra * (1.0 - aa));
		}
		rough = 0.8;
	} else if (park > 0.5) {
		vec2 lp = mod(p + block * 0.5, block) - block * 0.5;
		float path = step(abs(abs(lp.x) - abs(lp.y)), 2.0) + step(abs(length(lp) - 30.0), 1.5);
		float n = fbm2(v_w.xz * 0.4);
		col = mix(vec3(0.14, 0.26, 0.07), vec3(0.22, 0.34, 0.1), n);
		col = mix(col, white * 0.92, clamp(path, 0.0, 1.0));
		rough = 0.85;
	} else {
		// Sidewalks and building lots: light paving slabs.
		vec2 sl = floor(v_w.xz / vec2(2.0, 1.0));
		float joint = max(step(fract(v_w.x / 2.0), 0.03), step(fract(v_w.z / 1.0), 0.05)) * (1.0 - aa);
		col = white * mix(0.93, 1.0, hash12(sl)) * (1.0 - joint * 0.15);
		rough = 0.55;
	}
	col = mix(col, vec3(0.55, 0.56, 0.57), curb * (1.0 - road) * 0.6);
	// Night: pools of lamp light along the sidewalks (every 15 m, offset like the lamp posts).
	vec3 emit = vec3(0.0);
	if (lamp_glow > 0.01) {
		float lx = step(abs(gc.y - (half_w - 2.5)), 9.0) * smoothstep(9.0, 0.0, length(vec2(mod(p.x, 15.0) - 7.5 - 1.3, gc.y - (half_w - 3.8))));
		float lz = step(abs(gc.x - (half_w - 2.5)), 9.0) * smoothstep(9.0, 0.0, length(vec2(gc.x - (half_w - 3.8), mod(p.y, 15.0) - 7.5)));
		emit = vec3(1.0, 0.8, 0.55) * max(lx, lz) * lamp_glow * 0.5 * col;
	}
	float wet = weather_wetness;
	ALBEDO = col * mix(1.0, 0.7, wet);
	ROUGHNESS = mix(rough, 0.12, wet * 0.85);
	SPECULAR = 0.5;
	EMISSION = emit;
}
