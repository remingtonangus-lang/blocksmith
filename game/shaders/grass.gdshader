// GPU grass: a fixed lattice of clumps that travels with the camera (the MultiMesh node is snapped to the lattice
// step); each clump finds its own ground height, density, colour and size from the terrain textures, so nothing
// is generated on the CPU. INSTANCE_CUSTOM.x = random seed. Blades bend with the wind and thin out with distance.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/common.gdshaderinc"
#include "res://shaders/terrain_height.gdshaderinc"

uniform float radius = 60.0;
uniform float density = 1.0;
global uniform vec4 wind;
global uniform float weather_snow;
global uniform float snow_line;

varying vec3 v_col;
varying float v_h;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float seed = INSTANCE_CUSTOM.x;
	vec2 jitter = vec2(hash12(origin.xz * 0.731 + seed), hash12(origin.xz * 1.37 - seed)) - 0.5;
	vec2 base = origin.xz + jitter * 1.4;
	float d = distance(base, CAMERA_POSITION_WORLD.xz);
	vec4 m = t_mask_at(base);
	vec3 n = t_normal(base);
	float h = t_height(base);
	float slope = 1.0 - n.y;
	float meadow = fbm2(base * 0.02);
	float dens = (1.0 - smoothstep(0.18, 0.3, slope)) * (1.0 - max(m.r, m.g) * 1.0) * (1.0 - m.b);
	dens *= smoothstep(3.0, 6.0, h) * (1.0 - smoothstep(snow_line - 300.0, snow_line - 50.0, h));
	dens *= mix(1.0, 0.35, m.a);           // forest floor: sparse
	dens *= (1.0 - weather_snow);
	dens *= density;
	float keep = hash12(base * 3.1);
	float far = smoothstep(radius * 0.55, radius, d);
	float visible = step(keep, dens * (1.0 - far * 0.7)) * (1.0 - step(radius, d));
	float scale = mix(0.55, 1.15, hash12(base * 7.7)) * mix(0.8, 1.25, meadow) * visible;
	scale *= 1.0 - smoothstep(radius * 0.8, radius, d) * 0.6;
	// Wind: bend the blade tips.
	float tip = clamp(VERTEX.y / 0.7, 0.0, 1.0);
	vec2 wd = normalize(wind.xz + 0.0001);
	float gust = sin(TIME * 1.7 + base.x * 0.13 + base.y * 0.09) * 0.5 + 0.6;
	vec3 local = VERTEX * scale;
	local.xz += wd * tip * tip * (0.12 + wind.y * 0.45) * gust * scale;
	// Random yaw per clump.
	float yaw = hash12(base * 5.3) * 6.2832;
	float cy = cos(yaw);
	float sy = sin(yaw);
	local.xz = vec2(local.x * cy - local.z * sy, local.x * sy + local.z * cy);
	vec3 world = vec3(base.x, h, base.y) + local;
	v_h = tip;
	vec3 green = mix(vec3(0.16, 0.26, 0.07), vec3(0.36, 0.38, 0.15), meadow);
	green = mix(green, vec3(0.42, 0.40, 0.2), hash12(base * 2.9) * 0.35);
	v_col = green;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(normalize(n + vec3(0.0, 0.6, 0.0)), 0.0)).xyz;
}

void fragment() {
	ALBEDO = v_col * mix(0.45, 1.05, v_h);
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = v_col * 0.5;
	AO = mix(0.5, 1.0, v_h);
}
