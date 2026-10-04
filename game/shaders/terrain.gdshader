// CDLOD terrain. Patch instances come from Terrain.gd (MultiMesh): MODEL_MATRIX scales a unit 32x32 grid to the
// node, INSTANCE_CUSTOM = (morph start, morph end, level, vertex step). Heights are fetched with a manual bilinear
// filter that matches WorldGen.height_at exactly (collision and placement agree with what is drawn).
shader_type spatial;
render_mode skip_vertex_transform, depth_draw_opaque, cull_back;

#include "res://shaders/common.gdshaderinc"

#include "res://shaders/terrain_height.gdshaderinc"

uniform sampler2D maskmap_lin : filter_linear_mipmap, repeat_disable;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 cam_pos;
const float world_half = T_HALF;
const float detail_period = T_DETAIL_PERIOD;

global uniform float weather_wetness;
global uniform float weather_snow;
global uniform float snow_line;

varying vec3 v_world;
varying float v_morph;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float vstep = INSTANCE_CUSTOM.w;
	vec2 g = VERTEX.xz * 32.0;
	vec2 wp = origin.xz + g * vstep;
	float h = t_height(wp);
	float d = distance(cam_pos, vec3(wp.x, h, wp.y));
	float k = clamp((d - INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.y - INSTANCE_CUSTOM.x, 0.001), 0.0, 1.0);
	vec2 fr = fract(g * 0.5) * 2.0;
	g -= fr * k;
	wp = origin.xz + g * vstep;
	h = t_height(wp);
	v_morph = k;
	v_world = vec3(wp.x, h, wp.y);
	vec2 uv = (wp + world_half) / (world_half * 2.0);
	vec3 n = t_normal(wp);
	VERTEX = (VIEW_MATRIX * vec4(v_world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

vec4 tri_sample(int layer, vec3 p, vec3 w, float scale) {
	vec4 a = texture(albedo_array, vec3(p.zy * scale, float(layer)));
	vec4 b = texture(albedo_array, vec3(p.xz * scale, float(layer)));
	vec4 c = texture(albedo_array, vec3(p.xy * scale, float(layer)));
	return a * w.x + b * w.y + c * w.z;
}

vec3 tri_normal(int layer, vec3 p, vec3 w, float scale) {
	vec3 a = texture(normal_array, vec3(p.zy * scale, float(layer))).xyz * 2.0 - 1.0;
	vec3 b = texture(normal_array, vec3(p.xz * scale, float(layer))).xyz * 2.0 - 1.0;
	vec3 c = texture(normal_array, vec3(p.xy * scale, float(layer))).xyz * 2.0 - 1.0;
	// Whiteout-style: rotate each planar normal into world space.
	vec3 na = vec3(0.0, a.y, a.x);
	vec3 nb = vec3(b.x, 0.0, b.y);
	vec3 nc = vec3(c.x, c.y, 0.0);
	return na * w.x + nb * w.y + nc * w.z;
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 uv = (p + world_half) / (world_half * 2.0);
	vec3 n = normalize(texture(terrain_normal, uv).xyz * 2.0 - 1.0);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	// Fine detail slope from the detail layer (fades out with distance).
	vec4 det = texture(terrain_detail, p / detail_period);
	float amp = t_detail_amp(p);
	float dfade = 1.0 - smoothstep(150.0, 600.0, dist);
	vec2 dslope = (det.gb - 0.5) * 0.5 * amp / (2.0 * detail_period / 256.0);
	n = normalize(n + vec3(-dslope.x, 0.0, -dslope.y) * dfade);
	vec4 m = texture(maskmap_lin, uv);
	float slope = 1.0 - n.y;
	float h = v_world.y;
	float var1 = texture(terrain_detail, p / 731.0).r;
	float var2 = texture(terrain_detail, p / 213.0).a * 0.0 + texture(terrain_detail, p / 157.0 + 0.37).r;

	// Material weights: 0 grass, 1 meadow, 2 forest floor, 3 rock, 4 sand, 5 snow, 6 paving, 7 road.
	float w_rock = smoothstep(0.13, 0.3, slope + (var1 - 0.5) * 0.1);
	w_rock = max(w_rock, smoothstep(1900.0, 2150.0, h + var1 * 200.0));
	float w_sand = (1.0 - smoothstep(2.5, 5.0 + var2 * 3.0, h)) * (1.0 - w_rock);
	w_sand = max(w_sand, m.b * 0.85 * (1.0 - w_rock));
	float sl = snow_line - weather_snow * 900.0;
	float w_snow = smoothstep(sl - 60.0, sl + 80.0, h + (var1 - 0.5) * 260.0) * (1.0 - smoothstep(0.55, 0.75, slope));
	float w_urban = smoothstep(0.35, 0.8, m.g);
	float w_road = smoothstep(0.3, 0.7, m.r);
	float w_forest = smoothstep(0.25, 0.8, m.a);
	float w_meadow = smoothstep(0.35, 0.75, var2) * (1.0 - w_forest);
	float rest = 1.0;
	vec4 wa = vec4(0.0); // grass, meadow, forest, rock
	vec4 wb = vec4(0.0); // sand, snow, paving, road
	wb.w = w_road; rest -= wb.w;
	wb.z = w_urban * rest; rest -= wb.z;
	wb.y = w_snow * rest; rest -= wb.y;
	wa.w = w_rock * rest; rest -= wa.w;
	wb.x = w_sand * rest; rest -= wb.x;
	wa.z = w_forest * rest; rest -= wa.z;
	wa.y = w_meadow * rest; rest -= wa.y;
	wa.x = max(rest, 0.0);

	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	float sc = 1.0 / 4.0;
	vec4 alb = vec4(0.0);
	vec3 nn = vec3(0.0);
	float far_mix = smoothstep(80.0, 400.0, dist);
	// Flat layers sampled at two scales to hide tiling.
	if (wa.x > 0.01) {
		vec4 s = mix(texture(albedo_array, vec3(p * sc, 0.0)), texture(albedo_array, vec3(p * sc * 0.23, 0.0)), 0.35 + far_mix * 0.4);
		alb += s * wa.x; nn += (texture(normal_array, vec3(p * sc, 0.0)).xyz * 2.0 - 1.0) * wa.x;
	}
	if (wa.y > 0.01) {
		vec4 s = mix(texture(albedo_array, vec3(p * sc, 1.0)), texture(albedo_array, vec3(p * sc * 0.27, 1.0)), 0.35 + far_mix * 0.4);
		alb += s * wa.y; nn += (texture(normal_array, vec3(p * sc, 1.0)).xyz * 2.0 - 1.0) * wa.y;
	}
	if (wa.z > 0.01) {
		alb += texture(albedo_array, vec3(p * sc * 0.8, 2.0)) * wa.z;
		nn += (texture(normal_array, vec3(p * sc * 0.8, 2.0)).xyz * 2.0 - 1.0) * wa.z;
	}
	vec3 rock_n = vec3(0.0);
	if (wa.w > 0.01) {
		vec4 r1 = tri_sample(3, v_world, tw, sc * 0.5);
		vec4 r2 = tri_sample(3, v_world, tw, sc * 0.09);
		alb += mix(r1, r2, 0.45) * wa.w;
		rock_n = tri_normal(3, v_world, tw, sc * 0.5) * wa.w;
	}
	if (wb.x > 0.01) {
		alb += texture(albedo_array, vec3(p * sc, 4.0)) * wb.x;
		nn += (texture(normal_array, vec3(p * sc, 4.0)).xyz * 2.0 - 1.0) * wb.x;
	}
	if (wb.y > 0.01) {
		alb += texture(albedo_array, vec3(p * sc * 0.5, 5.0)) * wb.y;
		nn += (texture(normal_array, vec3(p * sc * 0.5, 5.0)).xyz * 2.0 - 1.0) * wb.y;
	}
	if (wb.z > 0.01) {
		alb += texture(albedo_array, vec3(p * sc * 0.5, 6.0)) * wb.z;
		nn += (texture(normal_array, vec3(p * sc * 0.5, 6.0)).xyz * 2.0 - 1.0) * wb.z;
	}
	if (wb.w > 0.01) {
		alb += texture(albedo_array, vec3(p * sc * 0.5, 7.0)) * wb.w;
		nn += (texture(normal_array, vec3(p * sc * 0.5, 7.0)).xyz * 2.0 - 1.0) * wb.w;
	}
	// Large-scale tint variation so far fields are not one flat colour.
	alb.rgb *= mix(0.86, 1.12, var1) * mix(0.94, 1.04, var2);
	// Tangent-space normals on the flat layers (x -> world x, y -> world z).
	vec3 T = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 B = normalize(vec3(0.0, 0.0, 1.0) - n * n.z);
	float nfade = 1.0 - smoothstep(60.0, 260.0, dist);
	vec3 nw = normalize(n + (T * nn.x + B * nn.y) * 0.9 * nfade + rock_n * 0.9 * nfade);
	// Weather: wet ground darkens and turns glossy; fresh snow settles on flat ground.
	float wet = weather_wetness * (1.0 - wb.y);
	vec3 col = alb.rgb * mix(1.0, 0.62, wet);
	float rough = mix(alb.a, 0.25, wet * 0.8);
	float fresh = weather_snow * smoothstep(0.75, 0.92, nw.y) * (1.0 - wb.w);
	col = mix(col, vec3(0.92, 0.94, 0.97), fresh);
	rough = mix(rough, 0.55, fresh);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
