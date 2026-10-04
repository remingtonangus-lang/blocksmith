// Frontier terrain: CDLOD patches displaced from the world heightmap, per-pixel normals, 13 PBR layers blended
// by biome/moisture/roads/slope/altitude with height-aware transitions. Layer order = tools/pack_textures.py.
shader_type spatial;
render_mode world_vertex_coords, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D controlmap : filter_linear, repeat_disable;
uniform sampler2DArray tex_ah : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float map_size = 8192.0;
uniform float h_range = 1600.0;
uniform float hm_res = 4096.0;
uniform float lake_level = 120.0;
uniform vec3 cam_pos;
uniform float detail_dist = 140.0;     // beyond this, materials sample at a coarser scale (anti-tiling)

global uniform float wetness;
global uniform float snow_cover;

const int L_GRASS_LUSH = 0;
const int L_GRASS_DRY = 1;
const int L_GRASS_SPARSE = 2;
const int L_DIRT = 3;
const int L_ROAD = 4;
const int L_MUD = 5;
const int L_FOREST = 6;
const int L_DESERT = 7;
const int L_RED_SAND = 8;
const int L_ROCK = 9;
const int L_RED_ROCK = 10;
const int L_SNOW = 11;
const int L_PEBBLES = 12;

// metres per texture repeat for each layer
const float TILE[13] = float[](3.0, 3.5, 3.0, 3.0, 4.0, 3.0, 3.0, 4.0, 4.0, 9.0, 10.0, 6.0, 2.5);

varying vec3 v_world;
varying float v_skirt;

float height_at(vec2 xz) {
	vec2 uv = (xz + map_size * 0.5) / map_size;
	return textureLod(heightmap, uv, 0.0).r * h_range;
}

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xz;
	float cell = INSTANCE_CUSTOM.z;
	vec2 wxz = VERTEX.xz;
	float h0 = height_at(wxz);
	float d = distance(cam_pos, vec3(wxz.x, h0, wxz.y));
	float morph = clamp((d - INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.y - INSTANCE_CUSTOM.x, 1.0), 0.0, 1.0);
	vec2 g = round((wxz - origin) / cell);
	vec2 odd = mod(g, 2.0);
	wxz -= odd * cell * morph;
	float h = height_at(wxz);
	v_skirt = UV2.x;
	VERTEX = vec3(wxz.x, h - UV2.x * cell * 3.0, wxz.y);
	v_world = VERTEX;
}

struct Mat { vec3 albedo; float height; vec2 nxy; float rough; float ao; };

Mat sample_layer(int L, vec2 xz, float dist) {
	float s = 1.0 / TILE[L];
	vec2 uv = xz * s;
	vec4 ah = texture(tex_ah, vec3(uv, float(L)));
	vec4 nr = texture(tex_nr, vec3(uv, float(L)));
	if (dist > detail_dist * 0.6) {
		// blend in a rotated, 4x larger sample to break up visible repetition at range
		float t = smoothstep(detail_dist * 0.6, detail_dist * 1.6, dist);
		vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * xz * s * 0.23;
		vec4 ah2 = texture(tex_ah, vec3(uv2, float(L)));
		vec4 nr2 = texture(tex_nr, vec3(uv2, float(L)));
		ah = mix(ah, mix(ah, ah2, 0.5), t);
		nr = mix(nr, mix(nr, nr2, 0.5), t);
	}
	Mat m;
	m.albedo = ah.rgb; m.height = ah.a; m.nxy = nr.rg * 2.0 - 1.0; m.rough = nr.b; m.ao = nr.a;
	return m;
}

// Steep faces: project the layer on the two vertical planes (biplanar) to avoid stretching.
Mat sample_cliff(int L, vec3 p, vec3 n, float dist) {
	float s = 1.0 / TILE[L];
	vec2 uvx = p.zy * s;
	vec2 uvz = p.xy * s;
	vec2 uvy = p.xz * s;
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec4 ah = texture(tex_ah, vec3(uvx, float(L))) * w.x + texture(tex_ah, vec3(uvz, float(L))) * w.z + texture(tex_ah, vec3(uvy, float(L))) * w.y;
	vec4 nr = texture(tex_nr, vec3(uvx, float(L))) * w.x + texture(tex_nr, vec3(uvz, float(L))) * w.z + texture(tex_nr, vec3(uvy, float(L))) * w.y;
	Mat m;
	m.albedo = ah.rgb; m.height = ah.a; m.nxy = nr.rg * 2.0 - 1.0; m.rough = nr.b; m.ao = nr.a;
	return m;
}

float hblend(float w, float h_layer, float h_base) {
	float mid = 1.0 - abs(w * 2.0 - 1.0);
	return smoothstep(0.0, 1.0, clamp((w - 0.5) * 3.0 + 0.5 + (h_layer - h_base) * 1.6 * mid, 0.0, 1.0));
}

void mix_in(inout Mat base, Mat layer, float w) {
	if (w <= 0.002) return;
	float t = hblend(w, layer.height, base.height);
	base.albedo = mix(base.albedo, layer.albedo, t);
	base.height = mix(base.height, layer.height, t);
	base.nxy = mix(base.nxy, layer.nxy, t);
	base.rough = mix(base.rough, layer.rough, t);
	base.ao = mix(base.ao, layer.ao, t);
}

void fragment() {
	vec3 p = v_world;
	vec2 uv = (p.xz + map_size * 0.5) / map_size;
	float texel = 1.0 / hm_res;
	float cell = map_size / hm_res;
	float dist = distance(CAMERA_POSITION_WORLD, p);
	// per-pixel normal from the heightmap (2 m), wider footprint at range to avoid shimmer
	float e = texel * (1.0 + floor(dist / 600.0));
	float hl = texture(heightmap, uv - vec2(e, 0.0)).r;
	float hr = texture(heightmap, uv + vec2(e, 0.0)).r;
	float hd = texture(heightmap, uv - vec2(0.0, e)).r;
	float hu = texture(heightmap, uv + vec2(0.0, e)).r;
	vec3 n = normalize(vec3((hl - hr) * h_range, 2.0 * cell * (e / texel), (hd - hu) * h_range));
	float slope = 1.0 - n.y;                        // 0 flat .. 1 vertical

	vec4 c = texture(controlmap, uv);               // r road, g moisture, b biome, a sediment
	float road = c.r;
	float moist = c.g;
	float biome = c.b;                              // 0 desert .. 0.5 grass .. 1 forest
	float sed = c.a;
	float alt = p.y;

	// macro variation noise (shared by several decisions)
	float n1 = fbm2(p.xz * 0.004);
	float n2 = fbm2(p.xz * 0.019 + 17.0);
	float n3 = vnoise(p.xz * 0.11);

	// --- base soil by biome
	Mat m;
	float desert_w = smoothstep(0.32, 0.12, biome + n1 * 0.08);
	float forest_w = smoothstep(0.70, 0.86, biome + n1 * 0.06);
	float lush_w = smoothstep(0.45, 0.85, moist + n2 * 0.15) * (1.0 - desert_w);
	if (desert_w > 0.98) {
		m = sample_layer(L_DESERT, p.xz, dist);
	} else {
		m = sample_layer(L_GRASS_DRY, p.xz, dist);
		mix_in(m, sample_layer(L_GRASS_SPARSE, p.xz, dist), smoothstep(0.1, 0.6, n2 + 0.2) * (1.0 - lush_w) * 0.8);
		mix_in(m, sample_layer(L_GRASS_LUSH, p.xz, dist), lush_w);
		mix_in(m, sample_layer(L_DESERT, p.xz, dist), desert_w);
	}
	mix_in(m, sample_layer(L_RED_SAND, p.xz, dist), desert_w * smoothstep(0.0, 0.5, n1 + 0.2));
	mix_in(m, sample_layer(L_FOREST, p.xz, dist), forest_w * smoothstep(0.05, 0.45, n2 + n3 * 0.25) * 0.85);
	// --- erosion sediment and dirt patches
	float dirt_w = clamp(smoothstep(0.35, 1.0, sed) * 0.7 + smoothstep(0.35, 0.7, n3 * 0.6 + n2 * 0.5) * 0.3, 0.0, 1.0) * (1.0 - desert_w * 0.7);
	mix_in(m, sample_layer(L_DIRT, p.xz, dist), dirt_w);
	// --- wet banks near rivers and the lake
	float near_water = smoothstep(lake_level + 3.0, lake_level + 0.5, alt) + smoothstep(0.92, 1.0, moist) * 0.8;
	mix_in(m, sample_layer(L_MUD, p.xz, dist), clamp(near_water, 0.0, 1.0));
	mix_in(m, sample_layer(L_PEBBLES, p.xz, dist), smoothstep(lake_level + 0.8, lake_level - 1.0, alt));
	// --- roads and trails
	mix_in(m, sample_layer(L_ROAD, p.xz, dist), smoothstep(0.15, 0.75, road + n3 * 0.15));
	// --- rock on steep ground (biplanar)
	float rock_w = smoothstep(0.24, 0.42, slope + n2 * 0.08);
	if (rock_w > 0.002) {
		Mat r = sample_cliff(desert_w > 0.5 ? L_RED_ROCK : L_ROCK, p, n, dist);
		mix_in(m, r, rock_w);
	}
	// --- snow above the snow line (patchy), less on steep faces; weather adds cover
	float snow_line = 1150.0 + n1 * 90.0 - snow_cover * 900.0;
	float snow_w = smoothstep(snow_line, snow_line + 120.0, alt) * smoothstep(0.55, 0.3, slope);
	snow_w = max(snow_w, snow_cover * smoothstep(0.5, 0.2, slope) * smoothstep(0.3, 0.8, n3 + snow_cover));
	if (snow_w > 0.002) mix_in(m, sample_layer(L_SNOW, p.xz, dist), snow_w);

	// macro colour variation (sun-bleached / darker patches) so the land never reads as one tile
	m.albedo *= 0.88 + 0.24 * (n1 * 0.5 + 0.5);
	m.albedo = mix(m.albedo, m.albedo * vec3(1.06, 1.0, 0.9), smoothstep(-0.2, 0.6, n2) * 0.5);

	// wetness (rain): darker, glossier, puddles in low flat spots
	float wet = wetness * (0.6 + 0.4 * n3);
	float puddle = wetness * smoothstep(0.55, 0.75, n3) * smoothstep(0.08, 0.0, slope) * (1.0 - m.height);
	m.albedo *= mix(1.0, 0.62, wet);
	m.rough = mix(m.rough, 0.25, wet * 0.8);
	m.rough = mix(m.rough, 0.04, puddle);
	m.nxy = mix(m.nxy, vec2(0.0), puddle);

	// detail normal in the tangent frame of the terrain normal
	vec3 t = normalize(cross(n, vec3(0.0, 0.0, 1.0)));
	vec3 b = normalize(cross(t, n));
	float detail_fade = 1.0 - smoothstep(60.0, 400.0, dist) * 0.7;
	vec3 nd = normalize(n + (t * m.nxy.x - b * m.nxy.y) * detail_fade);
	nd = mix(nd, n, v_skirt);

	ALBEDO = m.albedo;
	ROUGHNESS = clamp(m.rough, 0.04, 1.0);
	AO = mix(1.0, m.ao, 0.8);
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nd, 0.0)).xyz);
}
