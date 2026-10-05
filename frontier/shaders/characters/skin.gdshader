// Human skin for generated characters (src/actors/character_materials.gd). MakeHuman CC0 albedo atlas + tint,
// subsurface scattering (Forward+ screen-space SSS), procedural pore / fine-wrinkle micro-normal that fades out with
// distance, sun-weathering (tan, redness, roughness break-up), vertex COLOR: r cavity occlusion (lids, nose wings,
// lips), g oily T-zone (shinier), b beard stubble mask; age deepens pores and adds fine crease noise; rain wetness.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float weathering : hint_range(0.0, 1.0) = 0.2;
uniform float stubble : hint_range(0.0, 1.0) = 0.0;
uniform vec3 stubble_color : source_color = vec3(0.12, 0.09, 0.07);
uniform float sss : hint_range(0.0, 1.0) = 0.5;
uniform float roughness = 0.56;
uniform float pore_strength = 0.35;
uniform float pore_scale = 900.0;   // per UV unit (MakeHuman atlas: 1 UV ~ 0.8 m)
uniform float skin_age : hint_range(0.0, 1.0) = 0.2;

global uniform float wetness;

varying float v_beard;
varying float v_cavity;
varying float v_oily;

void vertex() {
	v_beard = COLOR.b;
	v_cavity = COLOR.r;
	v_oily = COLOR.g;
}

vec2 grad_noise(vec2 p) {
	float e = 0.35;
	float c = vnoise(p);
	return vec2(vnoise(p + vec2(e, 0.0)) - c, vnoise(p + vec2(0.0, e)) - c) / e;
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb * tint;
	// weathering: warm tan + mottled redness on exposed skin, slightly drier (rougher)
	float mott = fbm2(UV * 60.0) * 0.5 + 0.5;
	vec3 tan_col = a * vec3(0.86, 0.74, 0.62);
	a = mix(a, tan_col, weathering * 0.55);
	a = mix(a, a * vec3(1.06, 0.9, 0.86), weathering * mott * 0.35);
	// stubble: dark short hair dots over the beard area
	float dots = smoothstep(0.35, 0.8, vnoise(UV * 2600.0) * 0.5 + 0.5);
	float st = stubble * v_beard;
	a = mix(a, stubble_color, st * (0.35 + 0.45 * dots));
	ALBEDO = a;
	// micro normal (pores + fine wrinkles), faded by screen-space frequency to avoid shimmer
	vec2 p1 = UV * pore_scale;
	vec2 p2 = UV * pore_scale * 0.18;
	float f1 = clamp(1.0 - length(fwidth(p1)) * 0.6, 0.0, 1.0);
	float f2 = clamp(1.0 - length(fwidth(p2)) * 0.6, 0.0, 1.0);
	vec2 p3 = UV * pore_scale * 0.05;
	float f3 = clamp(1.0 - length(fwidth(p3)) * 0.6, 0.0, 1.0);
	vec2 g = grad_noise(p1) * f1 * 0.6 + grad_noise(p2 + 7.0) * f2 * 0.4;
	g += grad_noise(vec2(p3.x * 0.4, p3.y * 2.5) + 3.0) * f3 * 0.35 * skin_age;   // fine creases with age
	g *= pore_strength * (1.0 + weathering * 0.6 + skin_age * 0.5);
	NORMAL_MAP = normalize(vec3(-g * 0.5, 1.0)) * 0.5 + 0.5;
	float r = roughness + (mott - 0.5) * 0.12 * (0.5 + weathering) + st * 0.15 - v_oily * 0.08;
	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.25;
	r = mix(r, 0.18, clamp(wetness, 0.0, 1.0) * 0.7);
	ROUGHNESS = clamp(r, 0.15, 0.95);
	SPECULAR = 0.45;
	SSS_STRENGTH = sss;
}
