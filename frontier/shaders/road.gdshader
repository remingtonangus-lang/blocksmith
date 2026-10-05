// Wagon road ribbon (src/world/road_mesh.gd): UV.x across the road (0..1), UV.y metres along it. Two wheel ruts
// pressed into the road surface, a hoof-churned crown between them, grassy verges fading into the terrain, standing
// water in the ruts when it rains. Samples the terrain's own texture array so it sits in the ground.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"
#include "res://shaders/inc/cloud_shadow.gdshaderinc"

uniform sampler2DArray tex_ah : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fade_end = 380.0;

global uniform float wetness;
global uniform float snow_cover;

const float L_GRASS_DRY = 1.0;
const float L_DIRT = 3.0;
const float L_ROAD = 4.0;
const float L_MUD = 5.0;

varying vec3 v_world;
varying float v_water;
varying vec2 v_side;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_water = COLOR.r;
	v_side = COLOR.gb * 2.0 - 1.0;                    // world xz direction of +UV.x
	// pull towards the camera a little so the ribbon never z-fights the terrain under it
	vec3 to_cam = CAMERA_POSITION_WORLD - v_world;
	float d = length(to_cam);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * (to_cam / max(d, 0.001))) * (0.04 + d * 0.0015);
}

float rut_profile(float x, float c, float w) {
	float t = (abs(x) - c) / w;
	return exp(-t * t);
}

void fragment() {
	vec3 p = v_world;
	float dist = distance(CAMERA_POSITION_WORLD, p);
	float along = UV.y;
	float x = UV.x * 2.0 - 1.0;                       // -1 .. 1 across (4.6 m half width)
	// ruts wander a little; wagon gauge ~1.5 m -> ruts at +-0.75 m
	float wob = vnoise(vec2(along * 0.045, 3.7)) * 0.035 + vnoise(vec2(along * 0.31, 9.1)) * 0.008;
	float xr = x - wob;
	float rc = 0.163;                                  // 0.75 m / 4.6 m
	float rw = 0.033 + 0.009 * vnoise(vec2(along * 0.2, 1.3));
	float rut = rut_profile(xr, rc, rw);
	float rut_wide = rut_profile(xr, rc, rw * 2.6);
	float crown = smoothstep(0.125, 0.04, abs(xr));
	float verge = smoothstep(0.33, 0.7, abs(x));

	vec2 uvw = p.xz / 4.0;
	vec4 road_ah = texture(tex_ah, vec3(uvw, L_ROAD));
	vec4 road_nr = texture(tex_nr, vec3(uvw, L_ROAD));
	vec4 dirt_ah = texture(tex_ah, vec3(p.xz / 3.0, L_DIRT));
	vec4 grass_ah = texture(tex_ah, vec3(p.xz / 3.5, L_GRASS_DRY));
	vec4 mud_ah = texture(tex_ah, vec3(p.xz / 3.0, L_MUD));

	vec3 alb = road_ah.rgb;
	// crown: loose, hoof-churned, a little lighter with dry dung-dark flecks
	alb = mix(alb, dirt_ah.rgb * 1.05, crown * 0.6);
	alb *= 1.0 - crown * step(0.82, vnoise(p.xz * 3.1)) * 0.25;
	// ruts: compacted and darker, polished smooth by iron tyres
	alb = mix(alb, alb * 0.68, rut_wide * 0.8);
	// verges: dry grass creeping in, broken edge
	float edge_n = vnoise(p.xz * 0.9) * 0.15 + vnoise(p.xz * 3.7) * 0.07;
	alb = mix(alb, grass_ah.rgb, smoothstep(0.24, 0.62, abs(x) + edge_n));
	float rough = mix(road_nr.b, 0.8, rut);

	// groove normal: ruts ~6 cm deep, slope from the profile derivative along the world across-road direction
	float drut = (rut_profile(xr + 0.01, rc, rw) - rut_profile(xr - 0.01, rc, rw)) / 0.02;
	float tilt = 0.025 * drut / 4.6 * (1.0 - smoothstep(20.0, 80.0, dist));
	vec3 n = normalize(vec3(0.0, 1.0, 0.0) + vec3(road_nr.r * 2.0 - 1.0, 0.0, road_nr.g * 2.0 - 1.0) * 0.35
		+ vec3(v_side.x, 0.0, v_side.y) * tilt);

	// rain: standing water in the ruts, mud on the crown
	float wet = wetness;
	float puddle = wet * smoothstep(0.35, 0.8, rut + vnoise(p.xz * 0.6) * 0.3);
	alb = mix(alb, mix(alb, mud_ah.rgb, 0.6) * 0.7, wet * (1.0 - verge));
	alb *= mix(1.0, 0.5, puddle);
	rough = mix(rough, 0.25, wet * 0.6);
	rough = mix(rough, 0.03, puddle);

	alb = mix(alb, vec3(0.8, 0.82, 0.86), snow_cover * (1.0 - rut * 0.6));

	ALBEDO = alb * cloud_shade(p);
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	SPECULAR = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(n, vec3(0.0, 1.0, 0.0), puddle), 0.0)).xyz);
	float fade = 1.0 - smoothstep(fade_end * 0.75, fade_end, dist);
	float edge = 1.0 - smoothstep(0.7, 0.98, abs(x) + edge_n * 0.6);
	ALPHA = edge * fade * (1.0 - v_water);
}
