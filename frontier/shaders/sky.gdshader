// Frontier sky: single-scattering atmosphere (Rayleigh + Mie, few-step raymarch), sun and moon discs with limb
// darkening, procedural stars that twinkle, and a two-layer cloud deck (cumulus + cirrus) lit by the sun with a
// cheap self-shadow march. Weather drives coverage/darkness through uniforms set by src/world/sky.gd.
shader_type sky;
render_mode use_half_res_pass;

#include "res://shaders/inc/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);      // towards the sun
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_phase = 0.5;                  // 0 new .. 0.5 full .. 1 new
uniform float cloud_cover = 0.35;                // 0 clear .. 1 overcast
uniform float cloud_dark = 0.0;                  // storm darkening
uniform float cloud_time = 0.0;                  // seconds, drives drift
uniform vec2 wind_dir = vec2(1.0, 0.3);
uniform float haze = 0.0;                        // dust/fog in the air (raises Mie)
uniform float exposure = 1.0;
uniform float star_rot = 0.0;                    // sidereal rotation
uniform float lightning = 0.0;                   // flash intensity
uniform vec3 zenith_col = vec3(0.1, 0.2, 0.5);    // CPU-evaluated sky colours (src/world/sky.gd)
uniform vec3 horizon_col = vec3(0.4, 0.5, 0.6);
uniform vec3 sun_trans = vec3(1.0);              // atmospheric transmittance towards the sun

const float PLANET_R = 6371e3;
const float ATMOS_R = 6471e3;
const vec3 BETA_R = vec3(5.5e-6, 13.0e-6, 22.4e-6);
const float BETA_M = 21e-6;
const float H_R = 8000.0;
const float H_M = 1200.0;
const float G_M = 0.76;

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float d = b * b - c;
	if (d < 0.0) return vec2(1e9, -1e9);
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

vec3 atmosphere(vec3 rd, vec3 sd, float sun_i) {
	vec3 ro = vec3(0.0, PLANET_R + 400.0, 0.0);
	vec2 hit = ray_sphere(ro, rd, ATMOS_R);
	float tmax = hit.y;
	vec2 ground = ray_sphere(ro, rd, PLANET_R);
	if (ground.x > 0.0) tmax = min(tmax, ground.x);
	const int STEPS = 12;
	const int LSTEPS = 4;
	float ds = tmax / float(STEPS);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float od_r = 0.0;
	float od_m = 0.0;
	float mu = dot(rd, sd);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = G_M;
	float pm = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	float beta_m = BETA_M * (1.0 + haze * 6.0);
	for (int i = 0; i < STEPS; i++) {
		vec3 p = ro + rd * (float(i) + 0.5) * ds;
		float h = length(p) - PLANET_R;
		float hr = exp(-h / H_R) * ds;
		float hm = exp(-h / H_M) * ds;
		od_r += hr;
		od_m += hm;
		vec2 lh = ray_sphere(p, sd, ATMOS_R);
		float lds = lh.y / float(LSTEPS);
		float lod_r = 0.0;
		float lod_m = 0.0;
		bool lit = true;
		for (int j = 0; j < LSTEPS; j++) {
			vec3 lp = p + sd * (float(j) + 0.5) * lds;
			float lh2 = length(lp) - PLANET_R;
			if (lh2 < 0.0) { lit = false; break; }
			lod_r += exp(-lh2 / H_R) * lds;
			lod_m += exp(-lh2 / H_M) * lds;
		}
		if (lit) {
			vec3 tau = BETA_R * (od_r + lod_r) + beta_m * 1.1 * (od_m + lod_m);
			vec3 att = exp(-tau);
			sum_r += att * hr;
			sum_m += att * hm;
		}
	}
	return sun_i * (sum_r * BETA_R * pr + sum_m * beta_m * pm);
}

vec3 sun_transmittance(vec3 sd) {
	// optical depth along the sun ray from the viewer (for sun disc / cloud colour)
	vec3 ro = vec3(0.0, PLANET_R + 400.0, 0.0);
	vec2 lh = ray_sphere(ro, sd, ATMOS_R);
	float lds = lh.y / 8.0;
	float od_r = 0.0;
	float od_m = 0.0;
	for (int j = 0; j < 8; j++) {
		vec3 lp = ro + sd * (float(j) + 0.5) * lds;
		float h = max(length(lp) - PLANET_R, 0.0);
		od_r += exp(-h / H_R) * lds;
		od_m += exp(-h / H_M) * lds;
	}
	return exp(-(BETA_R * od_r + BETA_M * (1.0 + haze * 6.0) * 1.1 * od_m));
}

float stars(vec3 rd) {
	float c = cos(star_rot);
	float s = sin(star_rot);
	vec3 d = vec3(rd.x * c - rd.z * s, rd.y, rd.x * s + rd.z * c);
	vec3 p = d * 220.0;
	vec3 i = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = fract(sin(dot(i, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float star = step(0.9965, h) * smoothstep(0.32, 0.0, length(f));
	float tw = 0.7 + 0.3 * sin(TIME * (2.0 + h * 9.0) + h * 40.0);
	// faint milky band
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.55, 0.78))) * 3.2, 2.0)) * (0.5 + 0.5 * fbm2(d.xz * 9.0 + d.y * 4.0));
	return star * tw * (0.4 + h * 3.0) + band * 0.035;
}

float cloud_density(vec2 p, float cover) {
	vec2 w = vec2(fbm2(p * 0.6 + 3.1), fbm2(p * 0.6 + 7.7)) * 0.6;
	float base = fbm2(p + w) * 0.5 + 0.5;
	float detail = fbm2(p * 4.3 - w * 2.0) * 0.5 + 0.5;
	float d = base * 0.75 + detail * 0.25;
	float thr = mix(0.78, 0.25, cover);
	return smoothstep(thr, thr + 0.22, d);
}

void sky() {
	vec3 rd = EYEDIR;
	vec3 sd = normalize(sun_dir);
	float sun_up = sd.y;
	float sun_i = 22.0;
	vec3 col;
	if (AT_HALF_RES_PASS || AT_CUBEMAP_PASS) {
		col = atmosphere(vec3(rd.x, max(rd.y, 0.0) + 0.0001, rd.z), sd, sun_i);
		if (rd.y < 0.0) {
			vec3 hz = atmosphere(vec3(rd.x, 0.001, rd.z), sd, sun_i);
			col = mix(hz, hz * vec3(0.55, 0.5, 0.45), smoothstep(0.0, -0.3, rd.y));
		}
	} else {
		col = HALF_RES_COLOR.rgb;
	}
	if (AT_HALF_RES_PASS) {
		COLOR = col;
	} else {
		// night sky floor: faint blue airglow so night is dark but readable
		float night = smoothstep(0.05, -0.2, sun_up);
		col += vec3(0.008, 0.011, 0.02) * night * (1.0 - rd.y * 0.5);
		// moonlight scattering
		vec3 md = normalize(moon_dir);
		float moon_lum = (1.0 - abs(moon_phase * 2.0 - 1.0)) * smoothstep(-0.05, 0.1, md.y);
		col += vec3(0.012, 0.016, 0.026) * moon_lum * night * (0.4 + 0.6 * pow(max(dot(rd, md), 0.0), 8.0));
		vec3 trans = sun_trans;
		// sun disc with limb darkening
		float cos_sun = dot(rd, sd);
		float disc = smoothstep(0.99986, 0.99993, cos_sun);
		float limb = sqrt(max(0.0, 1.0 - pow((1.0 - cos_sun) / (1.0 - 0.99986), 2.0)));
		vec3 sun_col = trans * sun_i * 120.0 * (0.6 + 0.4 * limb);
		// stars and moon (behind clouds, faded by the bright sky)
		float sky_lum = dot(col, vec3(0.3, 0.5, 0.2));
		float star_vis = clamp(1.0 - sky_lum * 30.0, 0.0, 1.0) * step(0.0, rd.y);
		vec3 behind = vec3(stars(rd)) * star_vis * vec3(0.9, 0.95, 1.0);
		float cos_moon = dot(rd, md);
		float moon_disc = smoothstep(0.99975, 0.99982, cos_moon);
		if (moon_disc > 0.0) {
			// phase terminator: light side faces the sun direction projected on the disc
			vec3 tang = normalize(rd - md * cos_moon + 1e-5);
			vec3 sun_proj = normalize(sd - md * dot(sd, md) + 1e-5);
			float side = dot(tang, sun_proj);
			float ph = cos(moon_phase * 2.0 * PI);   // 1 new, -1 full
			float lit = smoothstep(ph - 0.15, ph + 0.15, side * 1.0 - (ph < 0.0 ? 0.0 : 0.0));
			float mare = 0.8 + 0.2 * fbm2(tang.xy * 40.0);
			behind += vec3(0.9, 0.92, 1.0) * moon_disc * (0.08 + 1.4 * lit * mare) * smoothstep(-0.02, 0.05, md.y);
		}
		behind += sun_col * disc * step(-0.02, sd.y);

		// clouds on a curved deck at ~2.2 km
		float cover = cloud_cover;
		vec3 cloud_add = vec3(0.0);
		float cloud_a = 0.0;
		if (rd.y > 0.0) {
			float t = 2200.0 / (rd.y + 0.06);
			vec2 cp = rd.xz * t * 0.00028 + wind_dir * cloud_time * 0.0009;
			float dens = cloud_density(cp, cover);
			if (dens > 0.001) {
				// self shadow: two samples towards the sun
				vec2 to_sun = normalize(sd.xz + 1e-4) * 0.06;
				float sh = cloud_density(cp + to_sun, cover) * 0.6 + cloud_density(cp + to_sun * 2.5, cover) * 0.4;
				float beer = exp(-sh * 2.2);
				float powder = 1.0 - exp(-dens * 3.0);
				vec3 amb = zenith_col * 1.6 + vec3(0.02, 0.025, 0.03) * night;
				float silver = pow(max(cos_sun, 0.0), 12.0) * 2.5;
				vec3 sun_light = trans * sun_i * 0.075 * (beer * powder * (1.0 + silver)) * smoothstep(-0.12, 0.05, sun_up);
				vec3 moon_light = vec3(0.02, 0.025, 0.04) * moon_lum * beer * night;
				cloud_add = (sun_light + amb * (0.55 + 0.45 * (1.0 - dens)) + moon_light) * (1.0 - cloud_dark * 0.75);
				cloud_add += vec3(0.8, 0.85, 1.0) * lightning * 3.0 * dens;
				cloud_a = dens * smoothstep(0.0, 0.12, rd.y) * (0.85 + cover * 0.15);
			}
			// cirrus streaks high above
			vec2 cc = rd.xz * (9000.0 / (rd.y + 0.04)) * 0.00004 + wind_dir * cloud_time * 0.00025;
			float cir = smoothstep(0.55, 1.0, fbm2(vec2(cc.x * 3.0, cc.y * 0.6) + fbm2(cc * 2.0)) * 0.5 + 0.6) * 0.35 * (1.0 - cover * 0.5);
			vec3 cir_col = trans * sun_i * 0.04 + zenith_col;
			col = mix(col, cir_col, cir * smoothstep(0.0, 0.2, rd.y) * (1.0 - cloud_a));
		}
		// overcast: flatten the sky towards a grey deck
		vec3 grey = mix(zenith_col, horizon_col, 0.5) * vec3(1.15, 1.1, 1.05) * 1.1 * (1.0 - cloud_dark * 0.7);
		col = mix(col, grey, smoothstep(0.6, 1.0, cover) * 0.85);
		col = col + behind * (1.0 - cloud_a) * (1.0 - smoothstep(0.7, 1.0, cover));
		col = mix(col, cloud_add, cloud_a);
		col += vec3(0.6, 0.65, 0.8) * lightning * 0.4;
		COLOR = col * exposure;
	}
}
