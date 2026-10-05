shader_type spatial;
// Wildlife coat (every generated species except the horse, which has horse_coat.gdshader). Painted in REST space
// like the horse: UV = rest (x, y), UV2.x = rest z (metres; Blender axes +x right, +y forward, +z up), COLOR = (AO,
// curvature, hoof mask, 1). Species-specific regions are placed with anchor points written by the generator
// (<species>_gaits.json "anchors") and colours/amounts from AnimalCoats (src/actors/animal_coats.gd):
// countershaded belly, darker dorsal saddle, agouti grizzle (wolves, coyotes), lower-leg points, white rump patch
// and black tail tip (deer, elk, pronghorn), throat/neck bands (pronghorn), face mask and ringed tail (raccoon),
// pale muzzle / dark nose pad, shaggy cape (bison), ear backs; plus blood, mud, wet and a skinned-carcass state.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.5, 0.38, 0.27);
uniform vec3 belly_color : source_color = vec3(0.85, 0.8, 0.72);
uniform vec3 dorsal_color : source_color = vec3(0.35, 0.27, 0.2);
uniform vec3 point_color : source_color = vec3(0.3, 0.24, 0.18);
uniform vec3 face_color : source_color = vec3(0.45, 0.36, 0.28);
uniform vec3 muzzle_color : source_color = vec3(0.8, 0.78, 0.74);
uniform vec3 nose_color : source_color = vec3(0.06, 0.05, 0.05);
uniform vec3 rump_color : source_color = vec3(0.92, 0.9, 0.86);
uniform vec3 tail_tip_color : source_color = vec3(0.06, 0.05, 0.05);
uniform vec3 hoof_color : source_color = vec3(0.12, 0.1, 0.09);
uniform vec3 band_color : source_color = vec3(0.92, 0.9, 0.86);
uniform float belly_amount : hint_range(0.0, 1.0) = 0.8;
uniform float dorsal_amount : hint_range(0.0, 1.0) = 0.4;
uniform float point_amount : hint_range(0.0, 1.0) = 0.3;
uniform float rump_amount : hint_range(0.0, 1.0) = 0.0;
uniform float tail_tip_amount : hint_range(0.0, 1.0) = 0.0;
uniform float band_amount : hint_range(0.0, 1.0) = 0.0;     // pronghorn throat bands / white chest
uniform float mask_amount : hint_range(0.0, 1.0) = 0.0;     // raccoon mask
uniform float ring_amount : hint_range(0.0, 1.0) = 0.0;     // ringed tail
uniform float grizzle : hint_range(0.0, 1.0) = 0.0;         // agouti banded guard hair
uniform float cape_amount : hint_range(0.0, 1.0) = 0.0;     // bison: darker shaggy forequarters
uniform vec3 cape_color : source_color = vec3(0.12, 0.08, 0.06);
uniform float fur_length : hint_range(0.0, 1.0) = 0.3;      // fur noise strength / roughness
uniform vec3 pattern_seed = vec3(0.0);
// anchors (rest metres)
uniform float y_rear = -0.58;
uniform float y_front = 0.58;
uniform float z_back = 1.0;
uniform float z_belly = 0.6;
uniform float z_knee = 0.35;
uniform float z_hock = 0.42;
uniform vec3 poll = vec3(0.0, 0.58, 1.38);
uniform vec3 nose = vec3(0.0, 0.75, 1.11);
uniform vec3 tail_base = vec3(0.0, -0.56, 0.93);
uniform vec3 tail_tip = vec3(0.0, -0.6, 0.75);
uniform vec3 eye = vec3(0.047, 0.607, 1.282);
uniform float body_scale = 1.0;
// state
uniform float blood : hint_range(0.0, 1.0) = 0.0;
uniform float mud : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float skinned : hint_range(0.0, 1.0) = 0.0;
global uniform float wetness;

varying vec3 rest;
varying vec3 bake;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return s;
}
// distance from point p to segment a-b
float seg(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - a - ab * t);
}

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x);
	bake = COLOR.rgb;
}

void fragment() {
	vec3 p = rest;
	float s = body_scale;
	float ao = bake.r;
	float curv = bake.g;
	float hoof = smoothstep(0.3, 0.7, bake.b);
	vec3 np = p / s;
	float n1 = fbm(np * 9.0 + pattern_seed);
	// ---- countershading: dark back, base flanks, pale belly / inner legs / throat
	float in_trunk = step(y_rear - 0.1 * s, p.y) * step(p.y, y_front + 0.1 * s);
	float h01 = clamp((p.z - z_belly) / max(z_back - z_belly, 0.01), 0.0, 1.0);
	vec3 col = base_color;
	float belly = (1.0 - smoothstep(0.0, 0.2, h01 + (n1 - 0.5) * 0.12)) * smoothstep(z_belly - 0.08 * s, z_belly - 0.02 * s, p.z) * in_trunk;
	float inner_leg = smoothstep(0.035 * s, 0.0, abs(p.x) - 0.06 * s) * step(p.z, z_belly) * step(z_knee, p.z) * 0.0;
	col = mix(col, belly_color, clamp(belly + inner_leg, 0.0, 1.0) * belly_amount);
	float dorsal = smoothstep(0.55, 1.0, h01 + (n1 - 0.5) * 0.2) * in_trunk * (1.0 - smoothstep(0.08 * s, 0.25 * s, abs(p.x)) * 0.3);
	col = mix(col, dorsal_color, dorsal * dorsal_amount);
	// ---- head: face colour, pale muzzle ring, dark nose pad, eye ring
	float head = 1.0 - smoothstep(0.0, 0.05 * s, seg(p, poll, nose) - 0.08 * s);
	col = mix(col, face_color, head * 0.6);
	float dn = distance(p, nose);
	col = mix(col, muzzle_color, (1.0 - smoothstep(0.025 * s, 0.06 * s, dn)) * 0.75 * (1.0 - mask_amount * 0.3));
	col = mix(col, nose_color, 1.0 - smoothstep(0.012 * s, 0.03 * s, distance(p, nose + (nose - poll) * 0.04 + vec3(0.0, 0.0, 0.01 * s))));
	vec3 e2 = vec3(sign(p.x) * eye.x, eye.y, eye.z);
	col = mix(col, muzzle_color, (1.0 - smoothstep(0.012 * s, 0.03 * s, distance(p, e2))) * 0.35);
	// raccoon mask: dark band through the eyes, white brows and muzzle
	if (mask_amount > 0.0) {
		vec3 fd = normalize(nose - poll);
		float u = dot(p - poll, fd) / max(length(nose - poll), 0.01);
		float mask = (1.0 - smoothstep(0.02 * s, 0.045 * s, abs(p.z - eye.z + (u - 0.3) * 0.02 * s))) * step(0.1, u) * step(u, 0.62) * head;
		col = mix(col, vec3(0.05, 0.045, 0.04), mask * mask_amount);
	}
	// ---- legs: points below knee/hock
	float leg_low = 1.0 - smoothstep(-0.03 * s, 0.06 * s, p.z - (p.y > 0.0 ? z_knee : z_hock));
	col = mix(col, point_color, clamp(leg_low + (n1 - 0.5) * 0.3, 0.0, 1.0) * point_amount);
	// ---- rump patch (white around the tail) and dark tail tip
	vec3 rc = tail_base + vec3(0.0, 0.01 * s, -0.12 * s);
	float rump = 1.0 - smoothstep(0.07 * s, 0.11 * s, length(vec2(p.x * 1.1, (p.z - rc.z) * 0.75)) + max(p.y - rc.y + 0.02 * s, 0.0) * 4.0 + (n1 - 0.5) * 0.04 * s);
	col = mix(col, rump_color, rump * rump_amount);
	float tseg = seg(p, tail_base, tail_tip);
	float along = clamp(dot(p - tail_base, tail_tip - tail_base) / max(dot(tail_tip - tail_base, tail_tip - tail_base), 1e-5), 0.0, 1.0);
	float on_tail = 1.0 - smoothstep(0.04 * s, 0.07 * s, tseg);
	col = mix(col, tail_tip_color, on_tail * smoothstep(0.7, 0.85, along) * tail_tip_amount);
	if (ring_amount > 0.0) {
		col = mix(col, vec3(0.08, 0.07, 0.06), on_tail * step(0.5, fract(along * 5.0)) * step(0.05, along) * ring_amount);
	}
	// ---- throat bands / white chest (pronghorn)
	if (band_amount > 0.0) {
		float neck = 1.0 - smoothstep(0.0, 0.05 * s, seg(p, vec3(0.0, y_front, z_back * 0.8), poll) - 0.07 * s);
		float under = smoothstep(0.0, 0.03 * s, -dot(p - mix(vec3(0.0, y_front, z_back * 0.8), poll, 0.5), vec3(0.0, -0.6, 0.8)));
		float bands = step(0.5, fract((p.z - z_back * 0.8) / (0.07 * s))) * neck * under;
		col = mix(col, band_color, max(bands, under * neck * 0.35) * band_amount);
	}
	// ---- agouti grizzle and the shaggy cape
	float gz = vnoise(vec3(np.x * 220.0, np.y * 60.0 - np.z * 30.0, np.z * 220.0));
	col = mix(col, mix(col * 0.55, vec3(0.85, 0.82, 0.76), step(0.55, gz)), grizzle * (0.3 + 0.7 * dorsal) * 0.6);
	if (cape_amount > 0.0) {
		float cape = smoothstep(0.1 * s, -0.25 * s, p.y - (y_front - 0.75 * s)) * smoothstep(z_belly - 0.25 * s, z_belly + 0.1 * s, p.z);
		cape = max(cape, head * 0.9);
		col = mix(col, cape_color, clamp(cape + (n1 - 0.5) * 0.3, 0.0, 1.0) * cape_amount);
	}
	// ---- fur detail: streaks along the hair flow, muscle definition from curvature/AO
	float streak = 0.86 + 0.28 * vnoise(vec3(np.x * 90.0, np.y * 14.0 - np.z * 8.0, np.z * 90.0 + np.y * 12.0));
	col *= mix(1.0, streak, 0.5 + 0.5 * fur_length);
	col *= mix(0.88, 1.06, curv);
	col = mix(col, hoof_color, hoof);
	// ---- state: mud on the legs, blood, wet, skinned carcass
	float low = smoothstep(z_belly + 0.1 * s, 0.0, p.z);
	col = mix(col, vec3(0.2, 0.15, 0.1), clamp(mud * low * smoothstep(0.4, 0.6, fbm(np * 14.0)), 0.0, 1.0));
	col = mix(col, vec3(0.28, 0.02, 0.02), blood * smoothstep(0.5, 0.65, fbm(np * 7.0 + 3.0)) * in_trunk);
	float w = clamp(max(wet, wetness), 0.0, 1.0);
	col *= mix(1.0, 0.65, w);
	float flesh_zone = in_trunk * step(z_knee * 1.1, p.z) * (1.0 - head);
	vec3 flesh = mix(vec3(0.45, 0.07, 0.06), vec3(0.85, 0.78, 0.7), smoothstep(0.55, 0.7, fbm(np * 20.0)));
	col = mix(col, flesh, skinned * flesh_zone);
	ALBEDO = col;
	AO = mix(0.65, 1.0, ao);
	AO_LIGHT_AFFECT = 0.35;
	float r = mix(0.62, 0.86, fur_length);
	r = mix(r, 0.35, hoof * 0.6);
	r = mix(r, 0.25, w);
	r = mix(r, 0.3, skinned * flesh_zone);
	ROUGHNESS = r;
	SPECULAR = mix(0.3, 0.55, max(w, skinned * flesh_zone));
	RIM = 0.25 * (1.0 - w) * fur_length;
	RIM_TINT = 0.7;
	BACKLIGHT = col * 0.08 * fur_length;
}
