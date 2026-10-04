// Ocean and rivers: Gerstner swell near the camera, two scrolling normal maps, refraction through the screen
// texture with depth-based absorption, shore foam, sky reflections with Fresnel (from the engine's radiance).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.012, 0.055, 0.075);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.24, 0.22);
uniform float sea_state = 0.5;        // 0 calm .. 1 storm
uniform bool is_river = false;
uniform vec3 cam_pos;
uniform float wave_fade = 1600.0;

global uniform vec4 wind;
global uniform float night;
global uniform float weather_wetness;

varying vec3 v_world;
varying vec3 v_normal;
varying float v_crest;

vec3 gerstner(vec2 p, vec2 dir, float wl, float steep, float t, inout vec3 tang, inout vec3 bin) {
	float k = TAU / wl;
	float c = sqrt(9.81 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	tang += vec3(-d.x * d.x * steep * sin(f), d.x * steep * cos(f), -d.x * d.y * steep * sin(f));
	bin += vec3(-d.x * d.y * steep * sin(f), d.y * steep * cos(f), -d.y * d.y * steep * sin(f));
	return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	if (!is_river) {
		float fade = 1.0 - smoothstep(wave_fade * 0.4, wave_fade, distance(w.xz, cam_pos.xz));
		float s = mix(0.06, 0.2, sea_state) * fade;
		vec2 wd = wind.xz;
		float t = TIME;
		disp += gerstner(w.xz, wd, 62.0 + sea_state * 50.0, s, t, tang, bin);
		disp += gerstner(w.xz, vec2(wd.x * 0.8 + 0.4, wd.y - 0.5), 31.0, s * 0.8, t, tang, bin);
		disp += gerstner(w.xz, vec2(-wd.y + 0.3, wd.x), 18.0, s * 0.6, t, tang, bin);
		disp += gerstner(w.xz, vec2(wd.x - 0.6, wd.y + 0.7), 9.0, s * 0.45, t, tang, bin);
		v_crest = clamp(disp.y / (0.9 + sea_state * 2.2), 0.0, 1.0);
	} else {
		v_crest = 0.0;
	}
	w += disp;
	v_world = w;
	v_normal = normalize(cross(bin, tang));
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(v_normal, 0.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float t = TIME;
	vec2 flow = is_river ? vec2(UV.x * 0.0 - t * 0.6, 0.0) : wind.xz * t * 0.6;
	vec2 uv1 = (is_river ? vec2(UV.x * 0.12 - t * 0.35, UV.y * 0.6) : p / 23.0 + flow * 0.02);
	vec2 uv2 = (is_river ? vec2(UV.x * 0.05 - t * 0.2, UV.y * 0.3 + 0.37) : p / 71.0 - flow.yx * 0.011);
	vec3 n1 = texture(normal_a, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normal_b, uv2).xyz * 2.0 - 1.0;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail = mix(0.55, 0.12, smoothstep(50.0, 1500.0, dist)) * (0.6 + sea_state * 0.8);
	vec3 nd = normalize(vec3(n1.x + n2.x, 0.0, n1.y + n2.y));
	vec3 nw = normalize(v_normal + nd * detail + vec3(0.0, 0.0, 0.0));
	if (!FRONT_FACING) nw = -nw;
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// Scene depth behind the water surface.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float scene_depth = -vpos.z;
	float water_depth = max(scene_depth - (-VERTEX.z), 0.0);
	// Refraction: offset by the normal, fall back to the unshifted sample when the offset hits something in front.
	vec2 off = nv.xz * 0.035 * clamp(water_depth / 3.0, 0.0, 1.0);
	vec2 ruv = SCREEN_UV + off;
	float raw2 = texture(depth_tex, ruv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, raw2, 1.0);
	v2.xyz /= v2.w;
	if (-v2.z < -VERTEX.z) ruv = SCREEN_UV;
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
	float murk = is_river ? 0.55 : 0.16;
	vec3 absorb = exp(-water_depth * murk * vec3(0.45, 0.12, 0.09));
	vec3 water_col = mix(deep_color, shallow_color, exp(-water_depth * 0.09)) * (1.0 - night * 0.85);
	vec3 body = refr * absorb + water_col * (1.0 - absorb.g);
	// Foam: shorelines and wave crests.
	float foam_n = fbm2(p * 0.35 + vec2(t * 0.15, 0.0));
	float shore = (1.0 - smoothstep(0.0, 1.6 + sea_state * 2.0, water_depth)) * step(0.001, water_depth);
	float foam = clamp(shore * smoothstep(0.35, 0.75, foam_n + shore * 0.4) + smoothstep(0.55, 0.95, v_crest) * smoothstep(0.45, 0.7, foam_n) * sea_state, 0.0, 1.0);
	if (is_river) foam = shore * smoothstep(0.5, 0.8, foam_n) * 0.6;
	ALBEDO = mix(vec3(0.0), vec3(0.85, 0.88, 0.9) * (1.0 - night * 0.8), foam);
	EMISSION = body * (1.0 - foam);
	ROUGHNESS = mix(0.03 + sea_state * 0.05 + weather_wetness * 0.06, 0.8, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL = nv;
	ALPHA = 1.0;
}
