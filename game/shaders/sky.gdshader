// Physically based sky: single-scattering Rayleigh + Mie atmosphere (sun and moon), a raymarched cumulus slab
// shaped by the weather, stars and a moon disc. The expensive part runs in the half-resolution pass; the full
// resolution pass composites it and draws the crisp sun / moon discs.
shader_type sky;
render_mode use_half_res_pass;

#include "res://shaders/common.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_intensity = 20.0;
uniform float moon_intensity = 0.02;
uniform float exposure = 1.6;
uniform float cloud_cover = 0.45;     // 0 clear .. 1 overcast
uniform float cloud_dark = 0.0;       // storms
uniform float cloud_steps = 28.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float star_rot = 0.0;
uniform float haze = 1.0;             // Mie multiplier (fog, rain)
uniform vec3 ground_color = vec3(0.24, 0.25, 0.22);
uniform sampler3D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;

const float R_E = 6371e3;
const float R_A = 6471e3;
const vec3 BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const float BETA_M = 21e-6;
const float H_R = 8000.0;
const float H_M = 1200.0;
const float CLOUD_LO = 1700.0;
const float CLOUD_HI = 3600.0;

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float d = b * b - c;
	if (d < 0.0) return vec2(1e9, -1e9);
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

vec3 scatter(vec3 rd, vec3 ld, float intensity, float h0) {
	vec3 ro = vec3(0.0, R_E + max(h0, 1.0), 0.0);
	vec2 t = ray_sphere(ro, rd, R_A);
	float t1 = t.y;
	vec2 g = ray_sphere(ro, rd, R_E);
	if (g.x > 0.0) t1 = g.x;
	const int STEPS = 12;
	const int LSTEPS = 4;
	float ds = t1 / float(STEPS);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float od_r = 0.0;
	float od_m = 0.0;
	float mu = dot(rd, ld);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float gg = 0.76;
	float pm = 3.0 / (8.0 * PI) * ((1.0 - gg * gg) * (1.0 + mu * mu)) / ((2.0 + gg * gg) * pow(1.0 + gg * gg - 2.0 * gg * mu, 1.5));
	for (int i = 0; i < STEPS; i++) {
		vec3 p = ro + rd * (float(i) + 0.5) * ds;
		float h = length(p) - R_E;
		float hr = exp(-h / H_R) * ds;
		float hm = exp(-h / H_M) * ds;
		od_r += hr;
		od_m += hm;
		vec2 lt = ray_sphere(p, ld, R_A);
		float lds = lt.y / float(LSTEPS);
		float lr = 0.0;
		float lm = 0.0;
		bool lit = true;
		for (int j = 0; j < LSTEPS; j++) {
			vec3 q = p + ld * (float(j) + 0.5) * lds;
			float lh = length(q) - R_E;
			if (lh < 0.0) { lit = false; break; }
			lr += exp(-lh / H_R) * lds;
			lm += exp(-lh / H_M) * lds;
		}
		if (lit) {
			vec3 tau = BETA_R * (od_r + lr) + BETA_M * haze * 1.1 * (od_m + lm);
			vec3 att = exp(-tau);
			sum_r += att * hr;
			sum_m += att * hm;
		}
	}
	return intensity * (sum_r * BETA_R * pr + sum_m * BETA_M * haze * pm);
}

vec3 sun_transmittance(vec3 ld) {
	vec3 ro = vec3(0.0, R_E + 500.0, 0.0);
	vec2 lt = ray_sphere(ro, ld, R_A);
	float lds = lt.y / 6.0;
	float lr = 0.0;
	float lm = 0.0;
	for (int j = 0; j < 6; j++) {
		vec3 q = ro + ld * (float(j) + 0.5) * lds;
		float lh = max(length(q) - R_E, 0.0);
		lr += exp(-lh / H_R) * lds;
		lm += exp(-lh / H_M) * lds;
	}
	return exp(-(BETA_R * lr + BETA_M * haze * 1.1 * lm));
}

float cloud_density(vec3 p, float lod) {
	float hfrac = clamp((p.y - CLOUD_LO) / (CLOUD_HI - CLOUD_LO), 0.0, 1.0);
	float shape = smoothstep(0.0, 0.12, hfrac) * (1.0 - smoothstep(0.35, 1.0, hfrac));
	vec3 q = vec3(p.x + cloud_offset.x, p.y, p.z + cloud_offset.y);
	float base = textureLod(cloud_noise, q / 9000.0, lod).r;
	float cov = mix(0.62, 0.18, cloud_cover);
	float d = smoothstep(cov, cov + 0.3, base * shape + base * 0.25);
	if (d <= 0.0) return 0.0;
	float det = textureLod(cloud_noise, q / 2100.0 + vec3(0.37), lod).r;
	d = clamp(d - (1.0 - det) * 0.32 * (1.0 - hfrac * 0.5), 0.0, 1.0);
	return d * mix(0.012, 0.03, cloud_cover);
}

// Returns rgb = in-scattered cloud light, a = transmittance.
vec4 clouds(vec3 ro, vec3 rd, vec3 sun_col, vec3 amb, vec3 ld, int steps) {
	if (abs(rd.y) < 0.0005) return vec4(0.0, 0.0, 0.0, 1.0);
	float t0 = (CLOUD_LO - ro.y) / rd.y;
	float t1 = (CLOUD_HI - ro.y) / rd.y;
	if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }
	t0 = max(t0, 0.0);
	if (t1 <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);
	float far = 60000.0;
	if (t0 > far) return vec4(0.0, 0.0, 0.0, 1.0);
	t1 = min(t1, t0 + 9000.0);
	float ds = (t1 - t0) / float(steps);
	float trans = 1.0;
	vec3 light = vec3(0.0);
	float jitter = hash12(rd.xz * 1000.0 + TIME);
	float mu = dot(rd, ld);
	float phase = mix(0.8 / (4.0 * PI), 3.0 * pow(max(mu, 0.0), 8.0), 0.4) + 0.06;
	for (int i = 0; i < 64; i++) {
		if (i >= steps || trans < 0.03) break;
		float t = t0 + (float(i) + jitter) * ds;
		vec3 p = ro + rd * t;
		float lod = clamp(t / 12000.0, 0.0, 3.0);
		float d = cloud_density(p, lod);
		if (d > 0.0) {
			float ls = 0.0;
			ls += cloud_density(p + ld * 180.0, lod + 0.5);
			ls += cloud_density(p + ld * 520.0, lod + 1.0);
			float shadow = exp(-ls * 420.0 * (1.0 + cloud_dark * 2.0));
			float powder = 1.0 - exp(-d * 2.0 * ds);
			float hfrac = clamp((p.y - CLOUD_LO) / (CLOUD_HI - CLOUD_LO), 0.0, 1.0);
			vec3 s = sun_col * shadow * phase * 6.0 * (0.4 + powder * 0.6) + amb * (0.45 + hfrac * 0.55);
			s *= (1.0 - cloud_dark * 0.75);
			float a = exp(-d * ds);
			light += trans * (1.0 - a) * s;
			trans *= a;
		}
	}
	float fade = 1.0 - smoothstep(25000.0, far, t0);
	return vec4(light * fade, mix(1.0, trans, fade));
}

vec3 stars(vec3 rd) {
	float c = cos(star_rot);
	float s = sin(star_rot);
	vec3 r = vec3(rd.x * c - rd.z * s, rd.y, rd.x * s + rd.z * c);
	vec3 p = r * 260.0;
	vec3 cell = floor(p);
	float h = hash13(cell);
	vec3 f = fract(p) - 0.5;
	float star = smoothstep(0.08, 0.0, length(f + (vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3)) - 0.5) * 0.7));
	star *= step(0.985, h) * (0.4 + 2.5 * pow(hash13(cell + 9.1), 6.0));
	float band = exp(-pow(dot(r, normalize(vec3(0.3, 0.2, 0.93))) * 3.2, 2.0)) * 0.03 * fbm2(r.xz * 18.0);
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), hash13(cell + 2.2));
	return tint * star + vec3(0.55, 0.6, 0.8) * band;
}

void sky() {
	vec3 rd = normalize(EYEDIR);
	float h0 = max(POSITION.y, 1.0);
	if (AT_HALF_RES_PASS || AT_CUBEMAP_PASS) {
		vec3 dir = rd;
		dir.y = max(dir.y, -0.02);
		vec3 col = scatter(normalize(dir), sun_dir, sun_intensity, h0);
		col += scatter(normalize(dir), moon_dir, sun_intensity * moon_intensity, h0) * vec3(0.8, 0.9, 1.15);
		float night = 1.0 - smoothstep(-0.18, 0.02, sun_dir.y);
		col += vec3(0.0006, 0.0009, 0.0018) * night;
		if (rd.y > 0.0) {
			col += stars(rd) * night * (1.0 - cloud_cover * 0.9) * 0.02 * smoothstep(0.0, 0.15, rd.y);
		}
		// Below the horizon: a dim ground colour lit by the sky (seen only over the ocean edge / from altitude).
		if (rd.y < 0.0) {
			float k = smoothstep(0.0, -0.06, rd.y);
			vec3 amb = scatter(vec3(0.0, 1.0, 0.0), sun_dir, sun_intensity, h0) * 0.5;
			col = mix(col, ground_color * (amb + vec3(0.002)), k);
		}
		if (rd.y > -0.01) {
			vec3 st = sun_transmittance(sun_dir) * smoothstep(-0.12, 0.05, sun_dir.y);
			vec3 sun_col = st * sun_intensity * 0.06 + sun_transmittance(moon_dir) * smoothstep(-0.1, 0.05, moon_dir.y) * sun_intensity * moon_intensity * 0.06;
			vec3 amb = scatter(vec3(0.0, 1.0, 0.0), sun_dir, sun_intensity, h0) * 1.6 + vec3(0.002, 0.003, 0.005);
			int steps = AT_CUBEMAP_PASS ? max(int(cloud_steps * 0.4), 6) : int(cloud_steps);
			if (steps > 0) {
				vec4 cl = clouds(vec3(POSITION.x, h0, POSITION.z), rd, sun_col, amb * (1.0 - cloud_dark * 0.6), sun_dir.y > -0.05 ? sun_dir : moon_dir, steps);
				// Aerial perspective over the cloud: blend toward the sky colour with distance.
				col = col * cl.a + cl.rgb;
			}
			if (cloud_cover > 0.75 && steps == 0) {
				col = mix(col, amb * 0.6, (cloud_cover - 0.75) * 3.0);
			}
		}
		COLOR = col * exposure;
	} else {
		vec3 col = HALF_RES_COLOR.rgb;
		// Sun and moon discs (behind clouds: dimmed by the cloud transmittance encoded in brightness).
		float sd = dot(rd, sun_dir);
		float vis = 1.0 - cloud_cover * 0.85;
		if (sd > 0.99995) {
			vec3 st = sun_transmittance(sun_dir);
			col += st * sun_intensity * 30.0 * exposure * vis * smoothstep(0.99995, 0.99999, sd);
		}
		float md = dot(rd, moon_dir);
		if (md > 0.99985 && moon_dir.y > -0.02) {
			vec3 mp = rd - moon_dir;
			float crater = 0.85 + 0.15 * vnoise(mp.xy * 4000.0);
			col += vec3(0.9, 0.92, 1.0) * 0.6 * crater * smoothstep(0.99985, 0.99992, md) * vis;
		}
		COLOR = col;
	}
}
