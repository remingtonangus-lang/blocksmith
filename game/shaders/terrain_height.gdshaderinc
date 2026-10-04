// Ground height for any shader (terrain, grass, decals): the same manual bilinear filter as WorldGen.height_at.
// The textures are global shader parameters set by Terrain.gd.
global uniform sampler2D terrain_heightmap : filter_nearest, repeat_disable;
global uniform sampler2D terrain_mask : filter_nearest, repeat_disable;
global uniform sampler2D terrain_detail : filter_linear_mipmap, repeat_enable;
global uniform sampler2D terrain_normal : filter_linear_mipmap, repeat_disable;

const float T_HALF = 8192.0;
const float T_CELL = 8.0;
const int T_N = 2048;
const float T_DETAIL_PERIOD = 64.0;
const float T_DETAIL_AMP = 0.45;

float t_macro_h(vec2 p) {
	vec2 f = clamp((p + T_HALF) / T_CELL - 0.5, vec2(0.0), vec2(float(T_N) - 1.001));
	ivec2 i = ivec2(f);
	vec2 a = f - vec2(i);
	float h00 = texelFetch(terrain_heightmap, i, 0).r;
	float h10 = texelFetch(terrain_heightmap, i + ivec2(1, 0), 0).r;
	float h01 = texelFetch(terrain_heightmap, i + ivec2(0, 1), 0).r;
	float h11 = texelFetch(terrain_heightmap, i + ivec2(1, 1), 0).r;
	return mix(mix(h00, h10, a.x), mix(h01, h11, a.x), a.y);
}

vec4 t_mask_at(vec2 p) {
	ivec2 t = clamp(ivec2(floor((p + T_HALF) / T_CELL - 0.5)), ivec2(0), ivec2(T_N - 1));
	return texelFetch(terrain_mask, t, 0);
}

float t_detail_amp(vec2 p) {
	vec4 m = t_mask_at(p);
	return T_DETAIL_AMP * (1.0 - max(m.r, m.g));
}

float t_height(vec2 p) {
	float d = textureLod(terrain_detail, p / T_DETAIL_PERIOD, 0.0).r * 2.0 - 1.0;
	return t_macro_h(p) + d * t_detail_amp(p);
}

vec3 t_normal(vec2 p) {
	return normalize(textureLod(terrain_normal, (p + T_HALF) / (T_HALF * 2.0), 0.0).xyz * 2.0 - 1.0);
}
