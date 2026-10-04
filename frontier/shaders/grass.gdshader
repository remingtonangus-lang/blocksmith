// Grass clumps (src/world/vegetation.gd): GPU placement on the heightmap, density and colour from the control
// map (dry prairie gold, river-bottom green, sparse desert tufts), wind waves, bending away from the player,
// distance fade by shrinking blades into the ground.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D controlmap : filter_linear, repeat_disable;
uniform float map_size = 8192.0;
uniform float h_range = 1600.0;
uniform float lake_level = 120.0;
uniform float fade_dist = 80.0;

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform vec3 player_pos;
global uniform float wetness;
global uniform float snow_cover;

varying vec3 v_col;
varying float v_t;

float h_at(vec2 xz) { return textureLod(heightmap, (xz + map_size * 0.5) / map_size, 0.0).r * h_range; }

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // instance origin (tile + offset)
	vec2 uv = (root.xz + map_size * 0.5) / map_size;
	vec4 c = textureLod(controlmap, uv, 0.0);
	float h = h_at(root.xz);
	float e = map_size / 4096.0;
	float slope = abs(h_at(root.xz + vec2(e, 0.0)) - h) + abs(h_at(root.xz + vec2(0.0, e)) - h);
	float rnd = INSTANCE_CUSTOM.x;
	float biome = c.b;
	float moist = c.g;
	float n = vnoise(root.xz * 0.05) * 0.5 + 0.5;
	// density: lush near water, dense in grassland, patchy in desert, none on roads, cliffs, water, snow
	float dens = mix(0.12, 1.0, smoothstep(0.15, 0.45, biome)) * (0.55 + 0.45 * n);
	dens *= mix(1.0, 0.35, smoothstep(0.75, 0.95, biome) * (1.0 - moist));   // forest floor thinner
	dens *= 1.0 - smoothstep(0.08, 0.35, c.r);
	dens *= 1.0 - smoothstep(1.2, 2.4, slope);
	dens *= step(lake_level + 0.4, h);
	dens *= 1.0 - smoothstep(1100.0, 1200.0, h);
	dens *= 1.0 - snow_cover;
	float d = distance(vec3(root.x, h, root.z), CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_dist * 0.65, fade_dist, d);
	float present = step(rnd, dens) * fade;
	float hscale = mix(0.55, 1.25, moist) * (0.75 + 0.5 * n) * mix(0.6, 1.0, smoothstep(0.1, 0.4, biome));
	vec3 v = VERTEX * vec3(1.0, hscale, 1.0) * present;
	float t = COLOR.r;                      // 0 root .. 1 tip
	v_t = t;
	// wind: travelling gust waves plus per-blade flutter
	vec2 wd = normalize(wind_dir + 1e-4);
	float wave = sin(dot(root.xz, wd) * 0.18 - TIME * 2.2) * 0.5 + 0.5;
	float gust = (0.35 + wave * 0.65) * wind_strength;
	vec3 wv = vec3(wd.x, 0.0, wd.y) * gust * 0.35 + vec3(sin(TIME * 3.1 + rnd * 40.0), 0.0, cos(TIME * 2.7 + rnd * 30.0)) * 0.04;
	// push away from the player / horse
	vec3 wp = vec3(root.x, h, root.z) + v;
	vec3 away = wp - player_pos;
	float push = smoothstep(1.4, 0.2, length(away.xz)) * step(abs(away.y), 2.5);
	wv += normalize(vec3(away.x, 0.0, away.z) + 1e-4) * push * 0.55;
	v += (inverse(mat3(MODEL_MATRIX)) * wv) * t * t * present;
	v.y -= push * t * t * 0.25 * present;
	VERTEX = v;
	VERTEX.y += (h - root.y) / max(length(MODEL_MATRIX[1].xyz), 0.01);
	// colour: dry gold -> green with moisture; sun-bleached tips; desert tufts grey-green
	vec3 dry = vec3(0.72, 0.60, 0.36);
	vec3 green = vec3(0.30, 0.38, 0.14);
	vec3 desert = vec3(0.62, 0.58, 0.44);
	vec3 col = mix(dry, green, smoothstep(0.45, 0.9, moist + (n - 0.5) * 0.3));
	col = mix(desert, col, smoothstep(0.15, 0.4, biome));
	col *= 0.85 + 0.3 * INSTANCE_CUSTOM.y;
	col = mix(col * 0.55, col * 1.12 + vec3(0.06, 0.05, 0.0), t);
	v_col = col * (1.0 - wetness * 0.25);
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.85 - wetness * 0.4;
	AO = mix(0.45, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.4;
	BACKLIGHT = v_col * 0.45;
}
