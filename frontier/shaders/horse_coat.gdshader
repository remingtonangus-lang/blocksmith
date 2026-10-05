shader_type spatial;
// Horse coat: base colour + lighter underside, dark points, dapples / flecks (grey), dorsal stripe (dun/grulla),
// tobiano pinto patches, appaloosa blanket or leopard spots, white socks/stockings and face markings, short-hair
// sheen and hair-flow streaks, baked AO/curvature for muscle definition, dirt / mud / wet / sweat layers.
// Everything is painted in REST space so patterns stay glued to the body while it animates:
//   UV = rest (x, y)  UV2.x = rest z   (metres; Blender axes: +x horse's right, +y forward, +z up, ground at 0)
//   COLOR = (ambient occlusion, curvature, hoof mask, 1)   — all written by tools/animals/horse_gen.py
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.40, 0.20, 0.09);
uniform vec3 belly_color : source_color = vec3(0.50, 0.30, 0.16);
uniform vec3 point_color : source_color = vec3(0.05, 0.035, 0.03);
uniform float point_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec3 mane_color : source_color = vec3(0.05, 0.035, 0.03);
uniform vec3 hoof_color : source_color = vec3(0.13, 0.11, 0.10);
uniform float dapple : hint_range(0.0, 1.0) = 0.0;
uniform float flecks : hint_range(0.0, 1.0) = 0.0;
uniform float dorsal_stripe : hint_range(0.0, 1.0) = 0.0;
uniform float pinto : hint_range(0.0, 1.5) = 0.0;
uniform float appaloosa : hint_range(0.0, 1.0) = 0.0;
uniform float leopard : hint_range(0.0, 1.0) = 0.0;
uniform vec3 pattern_seed = vec3(0.0);
uniform vec4 socks = vec4(0.0);          // white height (m) on LF, RF, LH, RH
uniform float face_white = 0.0;          // 0 none, 1 star, 2 star + strip, 3 blaze, 4 bald face
uniform float snip = 0.0;
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform float mud : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float sweat : hint_range(0.0, 1.0) = 0.0;
uniform float sheen : hint_range(0.0, 1.0) = 0.6;
uniform float lod_detail : hint_range(0.0, 1.0) = 1.0;
uniform float global_wetness_scale = 1.0;
global uniform float wetness;

varying vec3 rest;
varying vec3 bake;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i), n100 = hash13(i + vec3(1, 0, 0)), n010 = hash13(i + vec3(0, 1, 0)), n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1)), n101 = hash13(i + vec3(1, 0, 1)), n011 = hash13(i + vec3(0, 1, 1)), n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return s;
}
// distance to nearest and second-nearest feature point (cellular)
vec2 voronoi(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0, d2 = 8.0;
	for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = hash33(i + g);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return vec2(d1, d2);
}

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x);
	bake = COLOR.rgb;
}

// soft mask helpers in rest space
float leg_low(vec3 p) {
	// below knee (front, y > 0) / hock (hind, y < 0)
	float kh = p.y > 0.0 ? 0.50 : 0.56;
	return 1.0 - smoothstep(kh - 0.05, kh + 0.10, p.z);
}

void fragment() {
	vec3 p = rest;
	float ao = bake.r;
	float curv = bake.g;
	float hoof = smoothstep(0.3, 0.7, bake.b);
	vec3 sp = p + pattern_seed;
	float side_n = fbm(p * vec3(9.0, 9.0, 9.0) + 3.1);

	// ---- base: lighter underside and inner legs, slightly darker topline
	float belly = smoothstep(1.05, 0.80, p.z) * smoothstep(0.92, 0.70, abs(p.y + 0.05)) * (1.0 - leg_low(p));
	float inner = smoothstep(0.09, 0.03, abs(abs(p.x) - 0.05)) * step(p.z, 1.0) * 0.0;
	vec3 col = mix(base_color, belly_color, clamp(belly * 0.85 + inner, 0.0, 1.0));
	col *= mix(1.0, 0.86, smoothstep(1.35, 1.55, p.z) * (1.0 - smoothstep(1.0, 1.15, p.y)));
	// head: muzzle darker/greyer, around the eyes darker, flatter hair on the face
	float head = smoothstep(1.02, 1.12, p.y) * smoothstep(1.35, 1.55, p.z + p.y * 0.0);
	float muzzle = smoothstep(1.40, 1.50, p.y) * smoothstep(1.62, 1.50, p.z);
	col = mix(col, col * vec3(0.55, 0.5, 0.5), muzzle * 0.8);
	vec3 eye_l = vec3(-0.095, 1.217, 1.795), eye_r = vec3(0.095, 1.217, 1.795);
	float eye_ring = 1.0 - smoothstep(0.02, 0.055, min(distance(p, eye_l), distance(p, eye_r)));
	col *= 1.0 - 0.45 * eye_ring;

	// ---- dark points: lower legs, ear tips/rims, muzzle (bay, buckskin, dun...)
	float ears = smoothstep(2.02, 2.10, p.z);
	float pts = max(leg_low(p) + side_n * 0.15 - 0.05, 0.0);
	pts = clamp(pts, 0.0, 1.0);
	float pmask = clamp(max(max(pts, ears), muzzle * 0.6) * point_amount, 0.0, 1.0);
	col = mix(col, point_color, pmask);
	// dorsal stripe and leg barring (primitive marks of duns / grullas)
	float dorsal = dorsal_stripe * (1.0 - smoothstep(0.012, 0.03, abs(p.x))) * step(1.40, p.z) * step(-0.95, p.y) * step(p.y, 0.55);
	col = mix(col, point_color, dorsal * 0.85);

	// ---- grey: dapples (light centres, darker rims) or flea-bitten flecks; darker head and legs
	if (dapple > 0.0) {
		vec2 v = voronoi(sp * 11.0);
		float rim = smoothstep(0.0, 0.35, v.y - v.x);
		float body_zone = smoothstep(0.6, 0.95, p.z) * (1.0 - head * 0.7);
		vec3 dcol = mix(col * 0.72, col * 1.28 + 0.05, rim);
		col = mix(col, dcol, dapple * body_zone);
		col = mix(col, point_color, dapple * 0.35 * head);
	}
	if (flecks > 0.0) {
		float f = step(0.86, vnoise(sp * 70.0)) * step(0.4, vnoise(sp * 9.0));
		col = mix(col, point_color * 0.8 + vec3(0.12, 0.06, 0.03), f * flecks * 0.8);
	}

	// ---- white: pinto (tobiano: white crossing the back, legs and belly), appaloosa blanket / leopard spots
	float white = 0.0;
	if (pinto > 0.0) {
		float n = fbm(sp * 2.2) + fbm(sp * 6.0) * 0.25;
		float bias = -0.25 + 0.35 * smoothstep(0.9, 0.3, p.z) + 0.25 * smoothstep(0.6, 1.0, abs(p.y + 0.25) < 0.45 ? 1.0 : 0.0);
		bias -= 0.5 * head * (1.0 - step(1.6, p.z));
		white = max(white, smoothstep(0.58, 0.60, n + bias * pinto * 0.6) * step(0.01, pinto));
	}
	if (appaloosa > 0.0 || leopard > 0.0) {
		float blanket = leopard > 0.0 ? 1.0 : smoothstep(0.02, 0.06, -p.y + 0.12 + (fbm(sp * 4.0) - 0.5) * 0.35) * smoothstep(0.95, 1.15, p.z);
		blanket *= max(appaloosa, leopard);
		vec2 v = voronoi(sp * 12.0);
		float spot = 1.0 - smoothstep(0.18, 0.26, v.x + fbm(sp * 30.0) * 0.12);
		vec3 spot_col = leopard > 0.0 ? point_color : base_color * 0.9;
		col = mix(col, mix(vec3(0.90, 0.88, 0.84), spot_col, spot), blanket);
		// mottled skin around muzzle/eyes
		col = mix(col, vec3(0.45, 0.38, 0.36), muzzle * 0.5 * appaloosa);
	}
	// socks / stockings: ragged edge, per leg
	float leg_h = p.y > 0.0 ? (p.x < 0.0 ? socks.x : socks.y) : (p.x < 0.0 ? socks.z : socks.w);
	if (leg_h > 0.0 && abs(p.y) > 0.40) {
		float edge = leg_h + (fbm(p * 30.0) - 0.5) * 0.05;
		white = max(white, 1.0 - smoothstep(edge - 0.008, edge + 0.008, p.z));
	}
	// face: star / strip / blaze / bald (distance to the face midline, along the face)
	if (face_white > 0.0) {
		vec3 fd = normalize(vec3(0.0, 0.385, -0.485));
		vec3 poll = vec3(0.0, 1.115, 1.985);
		float u = dot(p - poll, fd) / 0.62;                     // 0 poll .. 1 nose
		vec3 perp = p - poll - fd * dot(p - poll, fd);
		float front = step(0.0, dot(perp, vec3(0.0, 0.78, 0.62)));  // dorsal (front) side of the face
		float star = 1.0 - smoothstep(0.028, 0.04, length(vec2(p.x, (u - 0.33) * 0.62 * 0.8)));
		float wid = face_white >= 4.0 ? 0.075 : (face_white >= 3.0 ? 0.04 : 0.016);
		float strip = (1.0 - smoothstep(wid, wid + 0.01, abs(p.x + (fbm(p * 20.0) - 0.5) * 0.02))) * step(0.36, u) * step(u, 1.02);
		float fw = star + (face_white >= 2.0 ? strip : 0.0);
		white = max(white, clamp(fw, 0.0, 1.0) * front * smoothstep(1.0, 1.1, p.y));
		white = max(white, snip * (1.0 - smoothstep(0.02, 0.03, length(vec2(p.x, (u - 0.9) * 0.4)))) * front * smoothstep(1.35, 1.42, p.y));
	}
	col = mix(col, vec3(0.92, 0.9, 0.86), clamp(white, 0.0, 1.0));

	// ---- hooves: horn colour, striped on white legs
	vec3 hc = hoof_color;
	float lw = leg_h > 0.06 ? 1.0 : 0.0;
	hc = mix(hc, vec3(0.62, 0.55, 0.44), lw * (0.6 + 0.4 * step(0.5, vnoise(vec3(atan(p.x, p.y) * 40.0, 0.0, 0.0)))));
	col = mix(col, hc * (0.85 + 0.15 * vnoise(vec3(p.x * 300.0, p.z * 30.0, p.y * 300.0))), hoof);

	// ---- hair: fine streaks along the hair flow (backwards and down), muscle definition from curvature/AO
	vec3 flow_p = vec3(p.x * 70.0, p.y * 9.0 - p.z * 5.0, p.z * 70.0 + p.y * 10.0);
	float streak = mix(1.0, 0.92 + 0.16 * vnoise(flow_p), lod_detail * (1.0 - hoof));
	col *= streak;
	col *= mix(0.9, 1.05, curv);
	float occl = mix(0.65, 1.0, ao);

	// ---- dirt (dust everywhere, more on legs/belly), mud splashes (legs and belly), wet, sweat
	float low = smoothstep(1.25, 0.15, p.z);
	float dn = fbm(p * 6.0 + 7.0);
	float dust = clamp(dirt * (0.35 + 0.65 * low) * (0.6 + 0.8 * dn), 0.0, 1.0);
	col = mix(col, vec3(0.52, 0.44, 0.34), dust * 0.6);
	float splash = smoothstep(0.45, 0.65, fbm(p * 14.0 + 3.0) + low * 0.55 - 0.25) * smoothstep(1.0, 0.0, p.z);
	float m = clamp(mud * splash * 1.4, 0.0, 1.0);
	col = mix(col, vec3(0.20, 0.15, 0.10), m);
	float w = clamp(max(wet, wetness * global_wetness_scale) + m * 0.5, 0.0, 1.0);
	float sw = sweat * smoothstep(1.15, 1.5, p.z) * (1.0 - smoothstep(0.1, 0.9, abs(p.y - 0.2))) * fbm(p * 12.0);
	col *= mix(1.0, 0.62, w * (1.0 - m * 0.5));
	col = mix(col, col * 0.8 + vec3(0.04), clamp(sw, 0.0, 1.0) * 0.6);

	ALBEDO = col;
	AO = occl;
	AO_LIGHT_AFFECT = 0.35;
	float r = mix(0.66, 0.5, sheen);
	r = mix(r, 0.82, dust * 0.8);
	r = mix(r, 0.9, m);
	r = mix(r, 0.18, w * (1.0 - m));
	r = mix(r, 0.3, hoof * 0.5);
	ROUGHNESS = r;
	SPECULAR = mix(0.32, 0.6, w);
	RIM = sheen * 0.22 * (1.0 - dust);
	RIM_TINT = 0.6;
}
