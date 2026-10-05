// Distant country beyond the map (src/world/backdrop.gd): coarse, fogged by the environment; colour by altitude and
// slope (golden grass low, dark timber on the slopes, grey rock, snow caps) with large-scale variation.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

#include "res://shaders/inc/noise.gdshaderinc"

uniform float map_half = 4096.0;
global uniform float snow_cover;

varying vec3 v_world;

void vertex() {
	v_world = VERTEX;
}

void fragment() {
	vec3 p = v_world;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - n.y;
	float m1 = fbm2(p.xz * 0.0004) * 0.5 + 0.5;
	float m2 = vnoise(p.xz * 0.003) * 0.5 + 0.5;
	vec3 grass = mix(vec3(0.26, 0.20, 0.09), vec3(0.17, 0.16, 0.07), m1);
	vec3 timber = mix(vec3(0.05, 0.07, 0.035), vec3(0.08, 0.085, 0.045), m2);
	vec3 rock = mix(vec3(0.22, 0.20, 0.18), vec3(0.30, 0.22, 0.16), m1);
	vec3 col = grass;
	float forest = smoothstep(0.08, 0.2, slope) * smoothstep(1700.0, 900.0, p.y) * smoothstep(0.35, 0.6, m1 + m2 * 0.3);
	col = mix(col, timber, forest);
	col = mix(col, rock, smoothstep(0.35, 0.6, slope + (m2 - 0.5) * 0.2));
	float snow = smoothstep(1500.0, 1800.0, p.y + m2 * 150.0 + snow_cover * 900.0) * smoothstep(0.7, 0.4, slope);
	col = mix(col, vec3(0.85, 0.87, 0.9), snow);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
