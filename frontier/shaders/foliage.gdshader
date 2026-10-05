// Trees and shrubs (meshes from src/world/tree_gen.gd). One shader for bark and leaf cards:
// layered wind (trunk sway, branch bob, leaf flutter) from vertex COLOR, alpha-scissored leaf atlas tinted per
// species and per instance, translucency for back-lit leaves. Each LOD draws in [lod_start, lod_end] with dithered
// cross-fades at both ends that exactly complement the neighbouring LOD (or the impostor past the last one).
// src/world/impostor_baker.gd compiles this same source with IMPOSTOR_BAKE defined to render the impostor atlases:
// unshaded, no wind, no fade, neutral per-instance tint; INSTANCE_CUSTOM.x picks albedo (0) or normal (1) output.
shader_type spatial;
#ifdef IMPOSTOR_BAKE
render_mode cull_disabled, unshaded;
#else
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#endif

#include "res://shaders/inc/noise.gdshaderinc"
#include "res://shaders/inc/cloud_shadow.gdshaderinc"
#include "res://shaders/inc/lod_dither.gdshaderinc"

uniform bool is_leaf = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;   // packed nr for bark
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_var = 0.12;
uniform float alpha_cut = 0.45;
uniform float sway = 1.0;           // species stiffness multiplier
uniform float tree_height = 12.0;
uniform float translucency = 0.6;
uniform float lod_start = -1.0;     // fades in over [lod_start - lod_band, lod_start] (per instance; < 0: no fade-in)
uniform float lod_end = 200.0;      // fades out over [lod_end - lod_band, lod_end]: the next LOD / impostor takes over
uniform float lod_band = 15.0;

global uniform vec2 wind_dir;
global uniform float wind_strength;

varying float v_inst_rand;
varying float v_ao;
varying float v_cloud;
varying float v_fade;
varying float v_fade_in;
varying flat float v_bake_normal;
varying float v_bake_depth;

void vertex() {
	vec3 wpos0 = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
#ifdef IMPOSTOR_BAKE
	v_inst_rand = 0.5;              // neutral tint; the impostor applies the per-tree variation itself
	v_bake_normal = INSTANCE_CUSTOM.x;
	// depth towards the bake camera relative to the trunk axis, in crown radii (custom y): -1 back .. +1 front.
	// The impostor rebuilds each texel's 3D position from it for its crown self-shadowing.
	float bake_scale = length(MODEL_MATRIX[0].xyz);
	float vz = ((MODEL_MATRIX * vec4(VERTEX, 1.0)).z - MODEL_MATRIX[3].z) / bake_scale;
	v_bake_depth = vz / max(INSTANCE_CUSTOM.y, 0.05);
	v_cloud = 1.0;
	v_fade = 0.0;
	v_fade_in = 1.0;
#else
	v_inst_rand = fract(sin(dot(wpos0.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float w = COLOR.r * sway;
	float ph = COLOR.g * 6.2831 + v_inst_rand * 6.2831;
	float t = TIME;
	vec2 wd = normalize(wind_dir + 1e-4);
	float gust = 0.6 + 0.4 * sin(t * 0.37 + wpos0.x * 0.02) * sin(t * 0.23 + wpos0.z * 0.017);
	float strength = wind_strength * gust;
	// trunk: slow bend proportional to height^2
	float hb = pow(clamp(VERTEX.y / tree_height, 0.0, 1.5), 2.0);
	vec3 bend = vec3(wd.x, 0.0, wd.y) * (sin(t * 0.9 + v_inst_rand * 6.0) * 0.35 + 0.65) * strength * hb * 0.35;
	// branches: bob at their own phase
	bend += vec3(sin(t * 2.1 + ph), cos(t * 1.7 + ph) * 0.4, cos(t * 2.3 + ph * 1.3)) * w * strength * 0.06;
	// leaf flutter at card tips
	if (is_leaf) {
		float flutter = UV2.y * strength * 0.05;
		bend += NORMAL * sin(t * 9.0 + ph * 3.0 + VERTEX.x * 3.0) * flutter;
	}
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * bend);
	// hand over to the impostor: dither out over the band (fragment), collapse once it is fully gone
	float dcam = distance(wpos0, LOD_CAMERA_POS);
	v_fade = smoothstep(lod_end - lod_band, lod_end, dcam);
	v_fade_in = lod_start < 0.0 ? 1.0 : smoothstep(lod_start - lod_band, lod_start, dcam);
	VERTEX *= step(dcam, lod_end) * step(lod_start - lod_band, dcam);
	v_cloud = cloud_shade((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
#endif
	v_ao = mix(0.55, 1.0, clamp(COLOR.r * 1.2, 0.0, 1.0));
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
#ifndef IMPOSTOR_BAKE
	float dth = lod_dither(FRAGCOORD.xy);
	if (dth < v_fade || dth >= v_fade_in) discard;
#endif
	vec3 alb;
	float ao;
	if (is_leaf) {
		// the leaf atlas mips keep their alpha-tested coverage (TreeGen.preserve_alpha_coverage), so crowns stay as
		// full at 200 m as up close, and match their impostors
		vec4 a = texture(albedo_tex, UV);
		if (a.a < alpha_cut) discard;
		vec3 var_tint = tint * (1.0 + (v_inst_rand - 0.5) * tint_var * 2.0);
		var_tint = mix(var_tint, var_tint * vec3(1.08, 0.95, 0.75), smoothstep(0.6, 1.0, v_inst_rand) * 0.6);
		alb = a.rgb * var_tint * 1.6;
		ao = v_ao;
		ROUGHNESS = 0.75;
		SPECULAR = 0.3;
		BACKLIGHT = alb * translucency * v_cloud;
	} else {
		vec4 a = texture(albedo_tex, UV);
		vec4 n = texture(normal_tex, UV);
		alb = a.rgb * tint;
		ao = n.a * v_ao;
		NORMAL_MAP = vec3(n.r, n.g, 1.0);
		ROUGHNESS = n.b;
		SPECULAR = 0.3;
	}
#ifdef IMPOSTOR_BAKE
	if (v_bake_normal < 0.5) {
		// stored at half scale (leaf albedo reaches ~1.5 linear) so 8-bit sRGB storage does not clip the hue
		ALBEDO = alb * 0.5;
	} else {
		// view-space normal xy (the bake camera is orthographic, +z towards it); blue = depth in the low half for
		// bark, the high half for leaves. The output is sRGB-encoded on store, so pre-decode to keep the raw values.
		vec3 vn = normalize(NORMAL);
		float dz = clamp(v_bake_depth * 0.5 + 0.5, 0.0, 0.998);
		ALBEDO = srgb_to_linear(vec3(vn.x * 0.5 + 0.5, vn.y * 0.5 + 0.5, (is_leaf ? 0.5 : 0.0) + dz * 0.5));
	}
#else
	ALBEDO = alb * v_cloud;
	AO = ao;
#endif
}
