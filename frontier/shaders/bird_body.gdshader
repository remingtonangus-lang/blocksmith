shader_type spatial;
// Bird body plumage (tools/animals/bird.py bodies), painted in rest space like the mammal coats: UV = rest (x, y),
// UV2.x = rest z (metres, Blender axes), COLOR = (AO, curvature, -, 1). Regions from anchors written by the
// generator: back/belly countershading, a breast band, the head (or the turkey's bare red-blue head with wattle
// and snood), beak, legs; mottling, barring and an iridescent sheen as amounts. Colours come from BirdLooks.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 back_color : source_color = vec3(0.3, 0.24, 0.18);
uniform vec3 belly_color : source_color = vec3(0.7, 0.62, 0.5);
uniform vec3 band_color : source_color = vec3(0.25, 0.18, 0.12);   // breast / belly band
uniform float band_amount = 0.0;
uniform vec3 head_color : source_color = vec3(0.3, 0.24, 0.18);
uniform float bare_head = 0.0;                                     // turkey: skin head (red / blue)
uniform vec3 leg_color : source_color = vec3(0.7, 0.55, 0.3);
uniform vec3 beak_color : source_color = vec3(0.2, 0.18, 0.15);
uniform float mottle = 0.3;
uniform float barring = 0.0;
uniform float sheen = 0.0;                                         // iridescent gloss (crow, turkey)
uniform vec3 sheen_tint : source_color = vec3(0.4, 0.5, 0.9);
uniform vec3 head_c = vec3(0.0, 0.3, 0.9);
uniform vec3 body_c = vec3(0.0, 0.0, 0.5);
uniform vec3 body_r = vec3(0.17, 0.3, 0.2);
uniform float hip_z = 0.4;
uniform float body_scale = 1.0;
uniform vec3 pattern_seed = vec3(0.0);

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

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x);
	bake = COLOR.rgb;
}

void fragment() {
	vec3 p = rest;
	float s = body_scale;
	vec3 np = p / max(s, 0.05);
	// countershading: darker back, paler belly
	float h = clamp((p.z - (body_c.z - body_r.z)) / max(2.0 * body_r.z, 0.01), 0.0, 1.0);
	vec3 col = mix(belly_color, back_color, smoothstep(0.3, 0.75, h + (vnoise(np * 30.0 + pattern_seed) - 0.5) * 0.2));
	// breast / belly band
	float band = (1.0 - smoothstep(0.03, 0.08, abs(p.z - (body_c.z - body_r.z * 0.25)))) * step(body_c.y - body_r.y * 0.2, p.y);
	col = mix(col, band_color, band * band_amount);
	// mottling and barring
	float m = vnoise(np * 55.0 + pattern_seed);
	col *= mix(1.0, 0.65 + 0.55 * m, mottle);
	col = mix(col, col * 0.55, barring * step(0.55, fract((p.y * 3.0 + p.z) / max(0.03 * s * 3.0, 0.004))));
	// head
	float dh = distance(p, head_c);
	float head = 1.0 - smoothstep(0.035 * s * 1.6, 0.06 * s * 1.6, dh);
	col = mix(col, head_color, head);
	if (bare_head > 0.0) {
		// turkey: blue face, red wattle / snood / throat
		float throat = 1.0 - smoothstep(0.0, 0.07, distance(p, head_c + vec3(0.0, 0.0, -0.06)));
		col = mix(col, vec3(0.45, 0.62, 0.85), head * bare_head);
		col = mix(col, vec3(0.62, 0.06, 0.05), max(throat, (1.0 - smoothstep(0.0, 0.035, distance(p, head_c + vec3(0.0, 0.05, -0.03))))) * bare_head);
	}
	// beak: in front of the head
	float beak = step(head_c.y + 0.035 * s * 1.2, p.y) * (1.0 - smoothstep(0.0, 0.04 * s, abs(p.z - head_c.z)));
	col = mix(col, beak_color, beak);
	// legs and feet below the belly
	float leg = 1.0 - smoothstep(hip_z * 0.55, hip_z * 0.7, p.z);
	col = mix(col, leg_color, leg);
	float ao = bake.r;
	ALBEDO = col * mix(0.75, 1.0, ao);
	ROUGHNESS = mix(0.75, 0.45, max(sheen, leg * 0.3));
	SPECULAR = mix(0.35, 0.6, sheen);
	// iridescence: a view-dependent tint on the glossy plumage
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = sheen_tint * fres * sheen * 0.08 * (1.0 - leg);
	RIM = 0.3 * (1.0 - leg);
	RIM_TINT = 0.6;
}
