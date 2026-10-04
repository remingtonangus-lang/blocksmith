// Garments of generated characters (src/actors/character_materials.gd). A Poly Haven CC0 fabric (albedo/normal/
// roughness, assets/ext/cloth/<fabric>) is tiled in metres on UV2 and re-coloured to `tint` (the garment's mean
// colour), modulated by the garment's own detail from UV (MakeHuman CC0 diffuse luminance, normal map, AO), plus
// vertex COLOR (r = baked occlusion, g = wear mask from the generator), height-based dust on legs/boots, fold sheen.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.5);
uniform bool use_fabric = false;
uniform sampler2D fabric_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_roughness : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 2.5;          // fabric repeats per metre
uniform float fabric_mix = 0.85;   // how much of the fabric's own pattern survives the re-tint
uniform bool use_base = false;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_base_normal = false;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool use_ao = false;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap;
uniform float dirt : hint_range(0.0, 1.0) = 0.3;
uniform float sheen = 0.0;
uniform float metallic = 0.0;
uniform float base_roughness = 0.85;

global uniform float wetness;

varying float v_height;
varying float v_occl;
varying float v_wear;

void vertex() {
	v_height = VERTEX.y;
	v_occl = COLOR.r;
	v_wear = COLOR.g;
}

void fragment() {
	vec2 fuv = UV2 * tile;
	vec3 col = tint;
	if (use_fabric) {
		vec3 f = texture(fabric_albedo, fuv).rgb;
		vec3 favg = textureLod(fabric_albedo, vec2(0.5), 12.0).rgb;
		float fl = dot(f, vec3(0.299, 0.587, 0.114)) / max(dot(favg, vec3(0.299, 0.587, 0.114)), 0.02);
		col *= mix(1.0, clamp(fl, 0.3, 2.0), fabric_mix);
	}
	if (use_base) {
		vec3 b = texture(base_albedo, UV).rgb;
		vec3 bavg = textureLod(base_albedo, vec2(0.5), 12.0).rgb;
		float bl = dot(b, vec3(0.299, 0.587, 0.114)) / max(dot(bavg, vec3(0.299, 0.587, 0.114)), 0.02);
		col *= mix(1.0, clamp(bl, 0.25, 1.8), 0.6);
	}
	float occl = v_occl;
	if (use_ao) {
		occl *= mix(1.0, texture(ao_tex, UV).r, 0.8);
	}
	// wear: lighter, desaturated fibres where the generator marked rubbing (elbows, knees, hems, edges)
	float n = fbm2(UV2 * 9.0) * 0.5 + 0.5;
	float wear = clamp(v_wear * (0.6 + 0.8 * n), 0.0, 1.0) * (1.0 - metallic);
	col = mix(col, mix(vec3(dot(col, vec3(0.333))), col, 0.6) * 1.25, wear * 0.45);
	// dust: rises from the ground up the trousers / skirts / boots
	float dust = smoothstep(0.55, 0.0, v_height + n * 0.18) * dirt;
	col = mix(col, vec3(0.42, 0.36, 0.29), dust * 0.7);
	col *= mix(1.0, 0.6, clamp(wetness, 0.0, 1.0) * (1.0 - metallic));
	ALBEDO = col;
	AO = occl;
	AO_LIGHT_AFFECT = 0.4;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (use_fabric) {
		nm = texture(fabric_normal, fuv).rgb;
	}
	if (use_base_normal) {
		vec3 bn = texture(base_normal, UV).rgb * 2.0 - 1.0;
		vec3 fn = nm * 2.0 - 1.0;
		nm = normalize(vec3(fn.xy + bn.xy, fn.z * bn.z)) * 0.5 + 0.5;   // whiteout blend
	}
	NORMAL_MAP = nm;
	float r = base_roughness;
	if (use_fabric) {
		r *= mix(0.8, 1.15, texture(fabric_roughness, fuv).r);
	}
	r = mix(r, r * 0.55, clamp(wetness, 0.0, 1.0));
	ROUGHNESS = clamp(r + dust * 0.1, 0.05, 1.0);
	METALLIC = metallic;
	RIM = sheen;
	RIM_TINT = 0.6;
}
