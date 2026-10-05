// Frontier buildings (src/world/mesh_kit.gd geometry): packed CC0 PBR sets (ah = RGB albedo + A height,
// nr = RG normal + B roughness + A AO) on UVs in metres, so every board/brick has real-world size.
// Per building: paint tint (COLOR.rgb, mixed by tint_amount), weathering (COLOR.a: sun-bleach, grime, rougher),
// per-board tone variation, splash dirt rising from the ground (UV2.x = height above ground, worse in the
// texture's low spots), streaky grime, rain wetness. UV2.y = per-building seed (texture offset and variation).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D tex_ah : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile = vec2(2.0, 2.0);          // metres per texture repeat (u, v)
uniform float boards = 0.0;                  // boards per repeat for tone variation (0 = off)
uniform float board_axis = 1.0;              // 1: boards stacked along v (horizontal boards), 0: along u
uniform float tint_amount = 0.4;             // how strongly the vertex paint tint applies
uniform float board_var = 0.10;
uniform float macro_var = 0.10;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float normal_depth = 1.0;
uniform float dirt_height = 0.75;
uniform float dirt_amount = 0.65;
uniform vec3 dirt_color : source_color = vec3(0.36, 0.29, 0.22);
uniform float grime = 0.35;                  // vertical streak grime strength
uniform float spec = 0.4;
uniform float metallic = 0.0;
uniform float desaturate = 0.0;              // material-level desaturation (e.g. tone down saturated scans)
uniform vec3 albedo_mul : source_color = vec3(1.0);

global uniform float wetness;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float seed = UV2.y;
	vec2 uv = UV / tile + vec2(seed * 7.31, seed * 3.17);
	vec4 ah = texture(tex_ah, uv);
	vec4 nr = texture(tex_nr, uv);
	vec3 alb = ah.rgb * albedo_mul;
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	alb = mix(alb, vec3(lum), desaturate);
	// per-board tone (boards were cut, painted and replaced at different times)
	if (boards > 0.0) {
		float coord = board_axis > 0.5 ? uv.y : uv.x;
		float bi = floor(coord * boards);
		float along = floor((board_axis > 0.5 ? uv.x : uv.y) * 0.7 + hash12(vec2(bi, 3.7)) * 4.0);
		float r = hash12(vec2(bi + seed * 131.0, along));
		alb *= 1.0 + (r - 0.5) * 2.0 * board_var;
	}
	// macro tone and stains in metre space
	float n1 = fbm2(UV * 0.45 + seed * 37.0);
	float n2 = vnoise(UV * vec2(3.0, 0.35) + seed * 11.0);       // vertical streaks (v runs down walls)
	alb *= 1.0 + n1 * macro_var;
	// paint tint
	// tints are authored in sRGB (like a paint chart): convert to linear before multiplying
	vec3 tint = mix(vec3(1.0), pow(COLOR.rgb, vec3(2.2)), tint_amount);
	alb *= tint;
	// weathering: sun-bleached, greyer, a little lighter on exposed wood; plus grime streaks
	float w = clamp(COLOR.a * (0.7 + 0.5 * n1), 0.0, 1.0);
	float l2 = dot(alb, vec3(0.299, 0.587, 0.114));
	alb = mix(alb, vec3(l2) * vec3(1.03, 1.0, 0.94) * 1.05, w * 0.45);
	float vertical = 1.0 - abs(v_wnrm.y);
	alb *= 1.0 - grime * w * vertical * smoothstep(0.1, 0.9, n2 * 0.5 + 0.5) * 0.35;
	// splash dirt near the ground, deeper in grooves/low spots of the height map
	float hgt = UV2.x;
	float dn = vnoise(UV * 1.7 + seed * 5.0) * 0.5 + 0.5;
	float dirt = 1.0 - smoothstep(0.0, dirt_height * (0.55 + 0.9 * dn), hgt);
	dirt *= mix(0.55, 1.0, 1.0 - ah.a) * dirt_amount * step(-0.05, hgt);
	alb = mix(alb, dirt_color * (0.85 + 0.3 * dn), clamp(dirt, 0.0, 1.0));
	float rough = clamp(nr.b * rough_mul + rough_add + w * 0.08 + dirt * 0.15, 0.05, 1.0);
	// rain: darker and glossier, mostly on outward-facing upper surfaces
	float wet = wetness * (0.5 + 0.5 * max(v_wnrm.y, 0.0)) * (0.7 + 0.3 * n1);
	alb *= mix(1.0, 0.7, wet);
	rough = mix(rough, 0.3, wet * 0.7);
	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = spec;
	AO = nr.a;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = vec3(nr.r, nr.g, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
}
