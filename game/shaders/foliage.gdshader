// Tree leaves and bark: wind sway from vertex-colour flex, leaf flutter, alpha-tested cards with coverage kept
// at distance, backlit translucency, per-instance tint (INSTANCE_CUSTOM: species, tint, phase, -) and a per-tree
// fade-out (dissolve) between near_end and near_end + 30 m where the impostor takes over.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool is_leaf = true;
uniform float near_end = 300.0;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(0.85, 0.95, 0.75);
global uniform vec4 wind;

varying float v_fade;
varying float v_ao;
varying float v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = INSTANCE_CUSTOM.z * 6.28 + COLOR.g;
	float flex = COLOR.r;
	float strength = wind.y;
	float t = TIME;
	vec3 wdir = normalize(vec3(wind.x, 0.0, wind.z) + 0.0001);
	float sway = (sin(t * 0.9 + phase * 0.3 + origin.x * 0.02) * 0.6 + sin(t * 2.1 + origin.z * 0.03) * 0.25 + 0.5) * strength;
	vec3 off = wdir * sway * flex * flex * 0.45;
	if (is_leaf) {
		off += vec3(sin(t * 7.0 + phase * 5.0), cos(t * 6.1 + phase * 3.0), sin(t * 5.3 + phase)) * 0.04 * flex * (0.4 + strength);
	}
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * off);
	float d = distance(origin, CAMERA_POSITION_WORLD);
	v_fade = 1.0 - smoothstep(near_end, near_end + 30.0, d);
	v_ao = COLOR.b;
	v_tint = INSTANCE_CUSTOM.y;
	if (d > near_end + 32.0) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	float a = c.a;
	if (is_leaf) {
		// Keep coverage in the smaller mips so far canopies do not thin out.
		vec2 px = UV * 1024.0;
		float lod = log2(max(length(dFdx(px)), length(dFdy(px))) + 1e-5);
		a *= 1.0 + max(lod, 0.0) * 0.35;
	}
	// Dissolve into the impostor with a stable screen-space dither.
	float dither = hash12(floor(FRAGCOORD.xy));
	if (a < 0.5 || dither > v_fade) discard;
	vec3 col = c.rgb * mix(tint_a, tint_b, v_tint);
	ALBEDO = col * mix(0.55, 1.0, v_ao);
	ROUGHNESS = is_leaf ? 0.72 : 0.92;
	SPECULAR = is_leaf ? 0.32 : 0.2;
	if (is_leaf) {
		BACKLIGHT = col * 0.55;
		AO = v_ao;
		AO_LIGHT_AFFECT = 0.4;
	}
}
