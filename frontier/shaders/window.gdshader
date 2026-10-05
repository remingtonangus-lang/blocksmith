// Frontier window glass: thin, slightly wavy period glass (cylinder-blown panes), a little grime at the edges,
// mostly transparent so furnished interiors read through it, sky/sun reflections from the low roughness.
// At night a subset of windows glows warm (lamp-lit curtains): COLOR.r = this window's rank (0..1) — the window is
// lit when rank < lights_on * lit_share; COLOR.g = curtain pattern variant; COLOR.b = 1 for interiors that are
// furnished and visible (less curtain so the room itself shows).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

uniform vec3 glass_tint : source_color = vec3(0.52, 0.58, 0.55);
uniform float base_alpha = 0.22;
uniform float lights_on = 0.0;             // 0 day .. 1 night (set by settlements.gd)
uniform float lit_share = 0.7;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.28);
uniform float lamp_energy = 2.2;

global uniform float wetness;

void fragment() {
	vec2 p = UV;                                  // metres in the wall plane
	float wav = vnoise(p * vec2(9.0, 3.0) + COLOR.g * 17.0);
	float grime = smoothstep(0.25, 1.0, fbm2(p * 2.5 + COLOR.g * 9.0) * 0.5 + 0.5);
	float lit = step(COLOR.r, lights_on * lit_share);
	// curtain: soft vertical folds, lighter in the middle
	float folds = 0.75 + 0.25 * sin(p.x * 38.0 + COLOR.g * 20.0);
	float curtain = mix(folds, 1.0, COLOR.b * 0.5);
	ALBEDO = glass_tint * 0.3 * (1.0 - grime * 0.4);
	ROUGHNESS = 0.03 + grime * 0.25 + wetness * 0.02;
	METALLIC = 0.0;
	SPECULAR = 0.85;
	NORMAL_MAP = vec3(0.5 + wav * 0.035, 0.5 + vnoise(p * vec2(3.0, 8.0)) * 0.035, 1.0);
	EMISSION = lamp_color * lamp_energy * lit * curtain * (0.85 + 0.15 * COLOR.g);
	ALPHA = clamp(base_alpha + grime * 0.2 + lit * mix(0.62, 0.35, COLOR.b), 0.0, 0.96);
}
