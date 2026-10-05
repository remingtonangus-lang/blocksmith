// Human skin for generated characters (src/actors/character_materials.gd). MakeHuman CC0 albedo atlas + tint.
// - Pores: cellular pits (Worley) + fine value-noise grain + age creases as a micro-normal, faded by screen-space
//   frequency (no shimmer at distance); pits are slightly darker and rougher than the skin between them.
// - Regional roughness: vertex COLOR.g oily T-zone (forehead, nose, chin) shinier, cheeks matte, stubble rough.
// - Colour variation: low-frequency haemoglobin (red) / melanin (brown) / venous (blue-grey) mottling, sun weathering.
// - Custom light(): energy-normalised wrap diffuse with a red-shifted scatter term (cheap subsurface look that also
//   works on Mobile/Quest and wherever screen-space SSS is off), two-lobe GGX specular (skin's sharp oily lobe +
//   broad lobe) and a faint peach-fuzz sheen at grazing angles. `wrap` is set per renderer by CharacterMaterials:
//   small when Forward+ screen-space SSS runs, larger without it.
// vertex COLOR: r cavity occlusion (lids, nose wings, lips), g oily T-zone, b beard stubble mask.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float weathering : hint_range(0.0, 1.0) = 0.2;
uniform float stubble : hint_range(0.0, 1.0) = 0.0;
uniform vec3 stubble_color : source_color = vec3(0.12, 0.09, 0.07);
uniform float sss : hint_range(0.0, 1.0) = 0.5;
uniform float roughness = 0.66;         // matte cheek skin
uniform float oily_roughness = 0.5;     // T-zone
uniform float pore_strength = 0.45;
uniform float pore_scale = 1100.0;      // pore cells per UV unit (MakeHuman atlas: 1 UV ~ 0.8 m -> ~0.7 mm cells)
uniform float skin_age : hint_range(0.0, 1.0) = 0.2;
uniform float wrap : hint_range(0.0, 1.0) = 0.25;
uniform vec3 scatter_color : source_color = vec3(1.0, 0.42, 0.28);
uniform float sheen = 0.06;

global uniform float wetness;

varying float v_beard;
varying float v_cavity;
varying float v_oily;

void vertex() {
	v_beard = COLOR.b;
	v_cavity = COLOR.r;
	v_oily = COLOR.g;
}

// distance to the nearest jittered cell centre (0 at a pore centre, ~0.7 between pores)
float cell_dist(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = vec2(hash12(i + o), hash12(i + o + 17.3));
			d = min(d, length(o + h * 0.8 + 0.1 - f));
		}
	}
	return d;
}

// pore height field: pits at cell centres (sized per cell), fine grain on top
float pore_h(vec2 p) {
	float d = cell_dist(p);
	return smoothstep(0.0, 0.32, d) - 1.0;
}

vec2 grad_noise(vec2 p) {
	float e = 0.35;
	float c = vnoise(p);
	return vec2(vnoise(p + vec2(e, 0.0)) - c, vnoise(p + vec2(0.0, e)) - c) / e;
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb * tint;
	// colour variation: haemoglobin flush, melanin blotches, venous blue-grey (subtle, low frequency)
	float hb = fbm2(UV * 22.0 + 3.1) * 0.5 + 0.5;
	float mel = fbm2(UV * 48.0 + 9.7) * 0.5 + 0.5;
	float ven = fbm2(UV * 14.0 + 21.0) * 0.5 + 0.5;
	a *= mix(vec3(1.0), vec3(1.05, 0.95, 0.94), smoothstep(0.45, 0.85, hb) * 0.6);
	a *= mix(vec3(1.0), vec3(0.93, 0.9, 0.88), smoothstep(0.55, 0.9, mel) * 0.5);
	a *= mix(vec3(1.0), vec3(0.96, 0.98, 1.03), smoothstep(0.6, 0.95, ven) * 0.4);
	// weathering: warm tan + mottled redness on exposed skin, slightly drier (rougher)
	float mott = fbm2(UV * 60.0) * 0.5 + 0.5;
	a = mix(a, a * vec3(0.86, 0.74, 0.62), weathering * 0.55);
	a = mix(a, a * vec3(1.06, 0.9, 0.86), weathering * mott * 0.35);
	// stubble: dark short hair dots over the beard area
	float dots = smoothstep(0.35, 0.8, vnoise(UV * 2600.0) * 0.5 + 0.5);
	float st = stubble * v_beard;
	a = mix(a, stubble_color, st * (0.35 + 0.45 * dots));

	// micro relief: pores (cellular), grain, age creases; each faded by its screen-space frequency
	vec2 p1 = UV * pore_scale;
	float f1 = clamp(1.4 - length(fwidth(p1)) * 1.2, 0.0, 1.0);
	vec2 p2 = UV * pore_scale * 0.3;
	float f2 = clamp(1.4 - length(fwidth(p2)) * 1.2, 0.0, 1.0);
	vec2 p3 = UV * pore_scale * 0.05;
	float f3 = clamp(1.2 - length(fwidth(p3)) * 0.8, 0.0, 1.0);
	float pit = 0.0;
	vec2 g = vec2(0.0);
	if (f1 > 0.0) {
		float e = 0.12;
		float h0 = pore_h(p1);
		vec2 gp = vec2(pore_h(p1 + vec2(e, 0.0)) - h0, pore_h(p1 + vec2(0.0, e)) - h0) / e;
		g += gp * 0.16 * f1;
		pit = clamp(-h0, 0.0, 1.0) * f1;
	}
	g += grad_noise(p2 + 7.0) * f2 * 0.25;
	g += grad_noise(vec2(p3.x * 0.6, p3.y * 1.8) + 3.0) * f3 * 0.18 * skin_age;   // fine creases with age
	float oily = clamp(v_oily, 0.0, 1.0);
	g *= pore_strength * (1.0 + weathering * 0.6 + skin_age * 0.5) * (1.0 + oily * 0.3);   // pores larger on the nose
	NORMAL_MAP = normalize(vec3(-g * 0.5, 1.0)) * 0.5 + 0.5;
	ALBEDO = a * (1.0 - pit * 0.08);

	float r = mix(roughness, oily_roughness, oily);
	r += (mott - 0.5) * 0.1 * (0.5 + weathering) + st * 0.15 + pit * 0.12;
	r = mix(r, 0.18, clamp(wetness, 0.0, 1.0) * 0.7);
	ROUGHNESS = clamp(r, 0.15, 0.95);
	SPECULAR = 0.4;    // F0 ~0.026
	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.35;
	SSS_STRENGTH = sss;
}

float ggx(float ndh, float a) {
	float a2 = a * a;
	float d = ndh * ndh * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d + 1e-6);
}

float smith_vis(float ndl, float ndv, float a) {
	return 0.5 / (ndl * (ndv * (1.0 - a) + a) + ndv * (ndl * (1.0 - a) + a) + 1e-5);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// wrap diffuse: red wraps furthest past the terminator (light scattered under the skin), normalised so the lit
	// side keeps its brightness
	vec3 w = wrap * scatter_color;
	vec3 d = clamp((vec3(ndl) + w) / (1.0 + w), 0.0, 1.0) / (1.0 + w * 0.5);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	// peach fuzz: faint broad sheen toward grazing view on the lit side
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	DIFFUSE_LIGHT += sheen * pow(1.0 - ndv, 4.0) * clamp(ndl + 0.3, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	if (ndl > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
		float ldh = clamp(dot(LIGHT, h), 0.0, 1.0);
		float a1 = max(ROUGHNESS * ROUGHNESS * 0.85, 0.01);    // oily lobe
		float a2 = max(ROUGHNESS * ROUGHNESS * 1.9, 0.01);     // broad lobe (skin's dry surface)
		float spec = 0.45 * ggx(ndh, a1) * smith_vis(ndl, max(ndv, 1e-3), a1)
			+ 0.55 * ggx(ndh, a2) * smith_vis(ndl, max(ndv, 1e-3), a2);
		float f0 = 0.16 * SPECULAR_AMOUNT * SPECULAR_AMOUNT;
		float f = f0 + (1.0 - f0) * pow(1.0 - ldh, 5.0);
		SPECULAR_LIGHT += spec * f * ndl * ATTENUATION * LIGHT_COLOR;
	}
}
