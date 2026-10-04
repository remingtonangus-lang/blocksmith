// Distant trees for every species in one MultiMesh per region: Y-axis billboard, per-instance custom data
// (x species, y width, z height, w random). Paints a soft canopy silhouette shaped per species (cone, round,
// bush) with the leaf atlas, lit as a rough volume. Collapses inside near_end where full meshes draw.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
uniform vec4 species_tint[16];     // rgb leaf tint, a has leaves
uniform vec4 species_bark[16];     // rgb bark, a crown shape (0 cone, 1 cone-round, 2 round, 3 bush)
uniform float near_end = 200.0;
uniform float shrub_end = 110.0;
uniform float far_end = 2500.0;

varying flat int v_sp;
varying float v_rand;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_sp = int(INSTANCE_CUSTOM.x + 0.5);
	v_rand = INSTANCE_CUSTOM.w;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float d = length(to_cam);
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + 1e-4);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float w = INSTANCE_CUSTOM.y;
	float h = INSTANCE_CUSTOM.z;
	float shape = species_bark[v_sp].a;
	float start = shape > 2.5 ? shrub_end : near_end;
	float vis = smoothstep(start - 15.0, start, d) * (1.0 - smoothstep(far_end * 0.9, far_end, d));
	vec3 wp = origin + (right * VERTEX.x * w + vec3(0.0, VERTEX.y * h, 0.0)) * vis;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(to_cam, 0.0)).xyz;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float y = 1.0 - UV.y;             // 0 ground .. 1 top
	vec4 lt = species_tint[v_sp];
	vec4 bk = species_bark[v_sp];
	float shape = bk.a;
	float trunk = step(abs(p.x), 0.045 + 0.02 * (1.0 - y)) * step(y, shape > 2.5 ? 0.3 : 0.55);
	float crown_w;
	float base_y = 0.18;
	if (shape < 0.5) {               // cone (fir)
		base_y = 0.06; crown_w = (1.0 - y) * 1.05;
	} else if (shape < 1.5) {        // cone-round (ponderosa)
		base_y = 0.35; crown_w = 0.85 * sin(clamp((y - 0.3) / 0.72, 0.0, 1.0) * 3.14159) * mix(1.0, 0.55, y);
	} else if (shape < 2.5) {        // round (cottonwood, aspen, oak)
		base_y = 0.25; crown_w = sin(clamp((y - 0.2) / 0.82, 0.0, 1.0) * 3.14159);
	} else {                         // bush
		base_y = 0.0; crown_w = sin(clamp(y / 1.0, 0.0, 1.0) * 3.14159) * 1.1;
	}
	float lumps = vnoise(vec2(p.x * 3.0, y * 5.0) + v_rand * 13.0) * 0.18 + vnoise(UV * 22.0 + v_rand * 7.0) * 0.1;
	float edge = crown_w - abs(p.x) + lumps;
	float leaves = step(0.0, edge) * step(base_y, y) * step(0.5, lt.a);
	if (leaves < 0.5 && trunk < 0.5) discard;
	vec3 leaf = texture(leaf_tex, fract(UV * vec2(3.0, 4.0)) * 0.25 + vec2(0.0, 0.25)).rgb;
	vec3 col = leaves > 0.5 ? lt.rgb * (0.55 + 0.7 * leaf.g) * 1.25 : bk.rgb;
	// rough volume normal: canopy rounds away at the edges; darker inside / at the bottom
	float nx = clamp(p.x / max(crown_w, 0.15), -1.0, 1.0);
	vec3 n_view = normalize(vec3(nx * 0.8, (y - 0.45) * 0.9, 0.7));
	NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(INV_VIEW_MATRIX) * n_view));
	float self_shadow = mix(0.6, 1.0, smoothstep(base_y, 1.0, y)) * (0.8 + 0.2 * clamp(edge * 4.0, 0.0, 1.0));
	ALBEDO = col * (0.9 + 0.2 * v_rand) * (leaves > 0.5 ? self_shadow : 1.0);
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.25;
}
