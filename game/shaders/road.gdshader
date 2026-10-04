// Road ribbons: UV.x = metres along the road, UV.y = 0..1 across. Capital roads: asphalt with white edge lines
// and a dashed centre line; Cinder tracks: rutted gravel. Wet roads turn glossy.
shader_type spatial;

#include "res://shaders/common.gdshaderinc"

uniform bool paved = true;
global uniform float weather_wetness;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float dist = length(VERTEX);
	float aa = clamp(dist / 400.0, 0.0, 1.0);
	vec3 col;
	float rough;
	if (paved) {
		float n = vnoise(vec2(u, v * 9.0) * 1.3);
		col = vec3(0.075, 0.078, 0.083) * mix(0.82, 1.18, n);
		float edge = step(abs(v - 0.06), 0.012) + step(abs(v - 0.94), 0.012);
		float centre = step(abs(v - 0.5), 0.012) * step(0.45, fract(u / 9.0));
		col = mix(col, vec3(0.78), clamp(edge + centre, 0.0, 1.0) * (1.0 - aa * 0.7));
		rough = 0.82;
	} else {
		float rut = smoothstep(0.08, 0.0, abs(v - 0.3)) + smoothstep(0.08, 0.0, abs(v - 0.7));
		float n = fbm2(vec2(u * 0.6, v * 4.0));
		col = mix(vec3(0.33, 0.29, 0.23), vec3(0.24, 0.2, 0.15), rut * 0.7) * mix(0.8, 1.15, n);
		rough = 0.95;
	}
	float wet = weather_wetness;
	ALBEDO = col * mix(1.0, 0.65, wet);
	ROUGHNESS = mix(rough, 0.1, wet * 0.9);
	SPECULAR = 0.5;
}
