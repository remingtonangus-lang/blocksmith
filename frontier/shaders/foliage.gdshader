// Trees and shrubs (meshes from src/world/tree_gen.gd). One shader for bark and leaf cards:
// layered wind (trunk sway, branch bob, leaf flutter) from vertex COLOR, alpha-scissored leaf atlas tinted per
// species and per instance, translucency for back-lit leaves, distance fade-in to avoid LOD popping.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"
#include "res://shaders/inc/cloud_shadow.gdshaderinc"

uniform bool is_leaf = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;   // packed nr for bark
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_var = 0.12;
uniform float alpha_cut = 0.45;
uniform float sway = 1.0;           // species stiffness multiplier
uniform float tree_height = 12.0;
uniform float translucency = 0.6;
uniform float lod_end = 200.0;      // beyond this the billboard takes over (per instance)

global uniform vec2 wind_dir;
global uniform float wind_strength;

varying float v_inst_rand;
varying float v_ao;
varying float v_cloud;

void vertex() {
	vec3 wpos0 = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
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
	// hand over to the billboard: shrink into the trunk base over the last 15 m
	float dcam = distance(wpos0, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(lod_end - 15.0, lod_end, dcam);
	v_cloud = cloud_shade((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_ao = mix(0.55, 1.0, clamp(COLOR.r * 1.2, 0.0, 1.0));
}

void fragment() {
	if (is_leaf) {
		vec4 a = texture(albedo_tex, UV);
		if (a.a < alpha_cut) discard;
		vec3 var_tint = tint * (1.0 + (v_inst_rand - 0.5) * tint_var * 2.0);
		var_tint = mix(var_tint, var_tint * vec3(1.08, 0.95, 0.75), smoothstep(0.6, 1.0, v_inst_rand) * 0.6);
		ALBEDO = a.rgb * var_tint * 1.6;
		ROUGHNESS = 0.75;
		SPECULAR = 0.3;
		AO = v_ao;
		BACKLIGHT = ALBEDO * translucency;
		ALBEDO *= v_cloud;
		BACKLIGHT *= v_cloud;
	} else {
		vec4 a = texture(albedo_tex, UV);
		vec4 n = texture(normal_tex, UV);
		ALBEDO = a.rgb * tint * v_cloud;
		NORMAL_MAP = vec3(n.r, n.g, 1.0);
		ROUGHNESS = n.b;
		AO = n.a * v_ao;
		SPECULAR = 0.3;
	}
}
