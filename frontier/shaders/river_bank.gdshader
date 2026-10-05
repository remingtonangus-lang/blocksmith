// River margins (src/world/water.gd _build_banks): UV.x 0 just under the water line .. 1 up the bank, UV.y metres
// along the river, UV2.x height above the water surface. Wet gravel and mud at the water's edge, a dark damp band,
// drying out up the bank and fading into the terrain.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"
#include "res://shaders/inc/cloud_shadow.gdshaderinc"

uniform sampler2DArray tex_ah : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_nr : filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float wetness;

const float L_DIRT = 3.0;
const float L_MUD = 5.0;
const float L_PEBBLES = 12.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - v_world;
	float d = length(to_cam);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * (to_cam / max(d, 0.001))) * (0.03 + d * 0.0012);
}

void fragment() {
	vec3 p = v_world;
	float dist = distance(CAMERA_POSITION_WORLD, p);
	float u = UV.x;
	float above = UV2.x;                                   // metres above the water surface
	float n1 = vnoise(p.xz * 0.35) * 0.5 + 0.5;
	float n2 = vnoise(p.xz * 1.7) * 0.5 + 0.5;
	vec4 peb = texture(tex_ah, vec3(p.xz / 2.5, L_PEBBLES));
	vec4 mud = texture(tex_ah, vec3(p.xz / 3.0, L_MUD));
	vec4 dirt = texture(tex_ah, vec3(p.xz / 3.0, L_DIRT));
	vec4 nr = texture(tex_nr, vec3(p.xz / 2.5, L_PEBBLES));
	// gravel bars on the inside, mud where it's flatter and higher
	float gravel = smoothstep(0.35, 0.65, n1 + (0.5 - u) * 0.6);
	vec3 alb = mix(mud.rgb, peb.rgb, gravel);
	alb = mix(alb, dirt.rgb, smoothstep(0.55, 0.95, u) * 0.5);
	// wet band just above the water line (capillary rise + splash), with a dark tide mark
	float wet = 1.0 - smoothstep(0.05, 0.6 + n2 * 0.3, above);
	wet = max(wet, wetness);
	alb *= mix(1.0, 0.55, wet);
	alb *= 1.0 - smoothstep(0.08, 0.0, abs(above - 0.12)) * 0.25;
	ALBEDO = alb * cloud_shade(p);
	ROUGHNESS = mix(nr.b, 0.22, wet * 0.85);
	SPECULAR = 0.4;
	vec3 n = normalize(vec3(nr.r * 2.0 - 1.0, 2.0, nr.g * 2.0 - 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(n, vec3(0.0, 1.0, 0.0), wet * 0.4), 0.0)).xyz);
	float outer = 1.0 - smoothstep(0.6, 1.0, u + (n1 - 0.5) * 0.35);
	ALPHA = outer * (1.0 - smoothstep(250.0, 400.0, dist));
}
