// The Capital's facades. Vertex COLOR: r = style, g = building seed, b = floor height / 8, a = lights allowed.
// UV = (metres along the perimeter, metres of height). Styles: glass curtain wall, banded white with ribbon
// windows, white stone, grey trim, dark metal, garden soil/hedge, landing pad, smoked glass, concrete, and the
// Cinder Pact's olive drab and rust. Windows light up at night (per-window random, warm or cool).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/common.gdshaderinc"

global uniform float night;
global uniform float weather_wetness;

varying float v_style;
varying float v_seed;
varying float v_floor;
varying float v_lights;
varying vec3 v_wpos;
varying vec3 v_wnorm;

void vertex() {
	v_style = COLOR.r;
	v_seed = COLOR.g;
	v_floor = max(COLOR.b * 8.0, 2.5);
	v_lights = COLOR.a;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float line(float x, float w) {
	float d = abs(fract(x) - 0.5) * 2.0;
	return 1.0 - smoothstep(1.0 - w * 2.0, 1.0 - w * 2.0 + 0.02, d);
}

void fragment() {
	int style = int(v_style * 11.0 + 0.001);
	vec2 uv = UV;
	float fl = v_floor;
	float row = floor(uv.y / fl);
	float fy = fract(uv.y / fl);
	vec3 alb = vec3(0.9);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float aa = clamp(dist / 900.0, 0.0, 1.0);
	bool up = v_wnorm.y > 0.7;
	vec3 white = vec3(0.86, 0.87, 0.86);
	if (style == 0 || style == 7) {
		// Curtain wall: mullions every 1.6 m, slim floor spandrels, glass tinted per building.
		float col_w = 1.6;
		float cx = floor(uv.x / col_w);
		float mull = line(uv.x / col_w + 0.5, mix(0.03, 0.08, aa));
		float span = smoothstep(0.86, 0.88, fy) * (1.0 - smoothstep(0.98, 1.0, fy));
		float frame = max(mull, span);
		float win_r = hash12(vec2(cx, row) + v_seed * 91.0);
		vec3 glass = style == 0 ? mix(vec3(0.06, 0.09, 0.11), vec3(0.11, 0.15, 0.17), v_seed) : vec3(0.025, 0.03, 0.035);
		// Some panes show interiors (blinds, ceilings) in daylight.
		glass *= mix(0.8, 1.35, step(0.7, win_r) * (1.0 - night));
		alb = mix(glass, white * 0.92, frame);
		rough = mix(0.035, 0.45, frame);
		spec = mix(0.95, 0.5, frame);
		metal = mix(0.35, 0.0, frame);
		if (v_lights > 0.5 && frame < 0.5) {
			float lit = step(win_r, mix(0.04, 0.42, night)) * night;
			vec3 lc = mix(vec3(1.0, 0.82, 0.6), vec3(0.85, 0.92, 1.0), step(0.5, hash12(vec2(row, v_seed * 13.0))));
			emit = lc * lit * mix(1.6, 3.2, hash12(vec2(cx * 3.1, row)));
		}
	} else if (style == 1) {
		// Banded: white spandrel bands with ribbon windows and slender mullions every 2.2 m.
		float win = step(0.36, fy) * (1.0 - step(0.9, fy));
		float cx = floor(uv.x / 2.2);
		float mull = line(uv.x / 2.2 + 0.5, mix(0.03, 0.07, aa));
		float win_r = hash12(vec2(cx, row) + v_seed * 57.0);
		vec3 glass = vec3(0.07, 0.09, 0.1) * mix(0.85, 1.25, step(0.75, win_r) * (1.0 - night));
		float w = win * (1.0 - mull);
		float joint = line(uv.x / 6.6 + 0.5, 0.01) * (1.0 - win);
		alb = mix(white * (1.0 - joint * 0.12) * mix(0.97, 1.02, hash12(vec2(row, floor(uv.x / 6.6)))), glass, w);
		rough = mix(0.4, 0.04, w);
		spec = mix(0.5, 0.9, w);
		metal = mix(0.0, 0.3, w);
		if (v_lights > 0.5 && w > 0.5) {
			float lit = step(win_r, mix(0.05, 0.45, night)) * night;
			emit = mix(vec3(1.0, 0.85, 0.65), vec3(0.9, 0.95, 1.0), step(0.6, v_seed)) * lit * 2.4;
		}
	} else if (style == 2 || style == 3) {
		// White stone or grey trim: large panels with fine joints.
		float jx = line(uv.x / 3.0 + 0.5, 0.012);
		float jy = line(uv.y / 1.5 + 0.5, 0.015);
		float j = max(jx, jy) * (1.0 - aa);
		alb = (style == 2 ? white : vec3(0.62, 0.64, 0.66)) * (1.0 - j * 0.18) * mix(0.96, 1.03, hash12(floor(uv / vec2(3.0, 1.5)) + v_seed));
		rough = style == 2 ? 0.5 : 0.42;
		if (up) alb *= 0.93;
	} else if (style == 4) {
		alb = vec3(0.16, 0.17, 0.19);
		rough = 0.35;
		metal = 0.75;
	} else if (style == 5) {
		// Garden: hedge and lawn tops, planted soil sides in white planters.
		float n = fbm2(v_wpos.xz * 1.7 + v_wpos.y);
		alb = up ? mix(vec3(0.12, 0.24, 0.07), vec3(0.24, 0.36, 0.11), n) : mix(vec3(0.1, 0.2, 0.06), vec3(0.2, 0.3, 0.1), n);
		rough = 0.85;
		spec = 0.25;
	} else if (style == 6) {
		// Landing pad: grey deck, white ring and chevrons, lit edge at night.
		vec2 p = UV;
		float r = length(p);
		alb = vec3(0.3, 0.31, 0.33);
		float ring = smoothstep(0.4, 0.2, abs(r - 9.0));
		float inner = smoothstep(0.3, 0.1, abs(r - 4.5));
		float bar = step(abs(p.x), 0.6) * step(abs(p.y), 3.0) + step(abs(p.y), 0.6) * step(abs(p.x), 3.0);
		alb = mix(alb, white, clamp(ring + inner + bar * 0.0, 0.0, 1.0));
		rough = 0.7;
		if (up && v_lights > 0.5) {
			float edge = smoothstep(0.35, 0.0, abs(r - 12.5)) * step(0.5, fract(atan(p.y, p.x) * 6.0));
			emit = vec3(1.0, 0.9, 0.6) * edge * (0.3 + night * 3.0);
		}
	} else if (style == 8) {
		float n = vnoise(uv * 0.7);
		alb = vec3(0.55, 0.55, 0.53) * mix(0.85, 1.05, n);
		rough = 0.85;
	} else if (style == 9) {
		float n = fbm2(uv * 0.3);
		alb = vec3(0.24, 0.26, 0.17) * mix(0.75, 1.1, n);
		rough = 0.8;
	} else {
		float n = fbm2(uv * 0.5);
		alb = mix(vec3(0.33, 0.17, 0.09), vec3(0.45, 0.3, 0.2), n);
		rough = 0.75;
		metal = 0.4;
	}
	// Roofs and terraces read slightly darker; dirt collects low on the walls.
	if (!up) {
		alb *= mix(0.88, 1.0, smoothstep(0.0, 6.0, uv.y - floor(uv.y / 400.0) * 400.0));
	}
	float wet = weather_wetness;
	alb *= mix(1.0, 0.82, wet * (1.0 - metal));
	rough = mix(rough, rough * 0.4, wet);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
