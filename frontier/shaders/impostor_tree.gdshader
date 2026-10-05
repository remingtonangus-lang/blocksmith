// Distant trees and shrubs: baked impostors of the real tree meshes (src/world/impostor_baker.gd), one MultiMesh per
// region for every species. Per instance (INSTANCE_CUSTOM): x atlas entry (species * variants + variant), y scale,
// z rotation about Y (the same as the near mesh), w random. Y-axis billboard planted at the trunk base; picks the
// two baked azimuths nearest the view direction (relative to the instance rotation) and cross-fades them; lit by the
// baked view-space normals (sun, sky ambient, translucency, cloud shadows), with crown self-shadowing rebuilt from
// the baked depth, and swayed like the near trunk. Edges and
// the hand-off use the same screen dither as shaders/foliage.gdshader, so the swap at lod_end is a pixel-exact
// complement of the mesh fading out. In shadow passes the quad turns to the sun and casts the tree's silhouette.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://shaders/inc/cloud_shadow.gdshaderinc"
#include "res://shaders/inc/lod_dither.gdshaderinc"

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_px = vec2(1920.0, 1120.0);
uniform vec4 entry_rect[32];     // uv of view 0's cell (xy), cell size in uv (zw)
uniform vec4 entry_frame[32];    // x frame height (m), y fraction of it below the base, z cell aspect w/h, w views
uniform vec4 entry_crown[32];    // x crown radius, y crown centre height, z crown half height, w tree height (m)
uniform vec4 entry_info[32];     // x lod_end (impostor fully in), y tree height (wind), z 1 = has leaves, w far end (0: far_end)
uniform float lod_band = 15.0;
uniform float far_end = 2500.0;
uniform float shadow_end = 330.0;    // impostors stop casting beyond this (the shadow distance)
uniform float max_lod = 4.0;         // atlas cells are 16-px aligned: mips up to 4 never mix neighbouring cells
uniform float translucency = 0.6;
uniform float self_shadow_min = 0.12;     // darkest a leaf deep in shadow inside its own crown gets (direct light)
uniform float self_shadow_density = 2.2;  // per crown radius of leaves the light passes through
uniform float interior_occlusion = 1.2;   // per crown radius a leaf sits behind the crown's front surface
uniform vec3 light_dir = vec3(0.3, 0.8, 0.5);   // towards the shadow-casting light (src/world/vegetation.gd)

global uniform vec2 wind_dir;
global uniform float wind_strength;

varying flat int v_e;
varying flat vec3 v_view;        // x view k0, y view k1, z blend k0 -> k1
varying flat vec2 v_ang;         // world rotation of the bake frames of k0 and k1
varying flat float v_rand;
varying float v_cloud;
varying float v_fade;
varying flat float v_half_w;
varying flat float v_scale;
varying flat float v_leafy;
varying flat vec3 v_frame;       // frame height S (m, scaled), fraction below the base, cell aspect
varying float v_self_shadow;
varying vec3 v_backlight;

const float TAU_F = 6.28318531;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_e = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 31);
	float sc = INSTANCE_CUSTOM.y;
	float rot = INSTANCE_CUSTOM.z;
	vec4 fr = entry_frame[v_e];
	vec4 info = entry_info[v_e];
	// the near mesh's per-instance random, from the same expression on the same origin: identical tint per tree
	v_rand = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float d = distance(origin, LOD_CAMERA_POS);
	float far = info.w > 0.0 ? min(far_end, info.w) : far_end;
	float vis = smoothstep(info.x - lod_band, info.x, d) * (1.0 - smoothstep(far * 0.9, far, d));
	bool shadow_pass = PROJECTION_MATRIX[3][3] != 0.0;   // orthographic: the directional shadow camera
	vec3 tv;
	if (shadow_pass) {
		tv = INV_VIEW_MATRIX[2].xyz;                       // towards the light
		vis *= step(d, shadow_end);
	} else {
		tv = CAMERA_POSITION_WORLD - origin;
	}
	tv.y = 0.0;
	tv = length(tv) > 1e-4 ? normalize(tv) : vec3(0.0, 0.0, 1.0);
	// view direction in the tree's own frame -> nearest two baked azimuths
	float cr = cos(rot);
	float sr = sin(rot);
	vec2 cl = vec2(tv.x * cr - tv.z * sr, tv.x * sr + tv.z * cr);
	float n = fr.w;
	float fk = fract(atan(cl.x, cl.y) / TAU_F) * n;
	float k0 = floor(fk);
	v_view = vec3(k0, mod(k0 + 1.0, n), fk - k0);
	v_ang = vec2(rot + v_view.x * TAU_F / n, rot + v_view.y * TAU_F / n);
	// Y-axis billboard, trunk base at the instance origin (planted on the terrain like the mesh)
	float S = fr.x * sc;
	float hy = (VERTEX.y - fr.y) * S;
	vec3 right = vec3(tv.z, 0.0, -tv.x);
	vec3 off = right * VERTEX.x * S * fr.z + vec3(0.0, hy, 0.0);
	// trunk sway, same expression as the near mesh (shaders/foliage.gdshader)
	vec2 wd = normalize(wind_dir + 1e-4);
	float t = TIME;
	float gust = 0.6 + 0.4 * sin(t * 0.37 + origin.x * 0.02) * sin(t * 0.23 + origin.z * 0.017);
	float hb = pow(clamp(hy / max(info.y, 0.5), 0.0, 1.5), 2.0);
	off += vec3(wd.x, 0.0, wd.y) * (sin(t * 0.9 + v_rand * 6.0) * 0.35 + 0.65) * wind_strength * gust * hb * 0.35;
	v_leafy = info.z;
	VERTEX = off * step(1e-4, vis);         // basis is identity in the region buffer; collapse when hidden
	NORMAL = tv;
	v_fade = vis;
	v_half_w = S * fr.z * 0.5 + 0.3;
	v_scale = sc;
	v_frame = vec3(S, fr.y, fr.z);
	v_cloud = cloud_shade(origin + vec3(0.0, S * (1.0 - fr.y) * 0.5, 0.0));
}

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

void fragment() {
	vec4 r = entry_rect[v_e];
	vec2 cell = r.zw;
	// mip from the screen footprint, clamped so cells never mix; keep samples half a texel inside the cell
	vec2 px = UV * cell * atlas_px;
	float lod = clamp(0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))), 0.0, max_lod);
	vec2 ht = exp2(lod) * 0.5 / atlas_px;
	vec2 cuv = clamp(UV * cell, ht, cell - ht);
	vec2 uv0 = r.xy + vec2(v_view.x * cell.x, 0.0) + cuv;
	vec2 uv1 = r.xy + vec2(v_view.y * cell.x, 0.0) + cuv;
	vec4 a0 = textureLod(albedo_atlas, uv0, lod);
	vec4 a1 = textureLod(albedo_atlas, uv1, lod);
	float f = v_view.z;
	vec4 a = mix(a0, a1, f);                     // premultiplied: a plain mix is the right blend
	// coverage -> ~1 px dithered edge; coarse mips average leaves with sky, so lower the cut to keep the canopy dense
	float cut = 0.5 - 0.05 * lod;
	float edge = clamp((a.a - cut) / max(fwidth(a.a), 0.04) + 0.5, 0.0, 1.0);
	if (lod_dither(FRAGCOORD.xy) >= edge * v_fade) discard;
	vec4 q0 = textureLod(normal_atlas, uv0, lod);
	vec4 q1 = textureLod(normal_atlas, uv1, lod);
	vec3 n0 = q0.rgb / max(q0.a, 1e-3);
	vec3 n1 = q1.rgb / max(q1.a, 1e-3);
	vec2 e0 = n0.xy * 2.0 - 1.0;
	vec2 e1 = n1.xy * 2.0 - 1.0;
	vec3 w0 = rot_y(vec3(e0, sqrt(max(1.0 - dot(e0, e0), 0.0))), v_ang.x);
	vec3 w1 = rot_y(vec3(e1, sqrt(max(1.0 - dot(e1, e1), 0.0))), v_ang.y);
	float wa0 = q0.a * (1.0 - f);
	float wa1 = q1.a * f;
	float wsum = max(wa0 + wa1, 1e-4);
	vec3 nw = normalize(w0 * wa0 + w1 * wa1 + vec3(0.0, 1e-4, 0.0));
	float leaf0 = step(0.5, n0.b);
	float leaf1 = step(0.5, n1.b);
	float leaf = (leaf0 * wa0 + leaf1 * wa1) / wsum;
	// each texel's 3D position (tree-local, metres) from its baked depth, in the frame of the view it came from
	vec4 cr = entry_crown[v_e] * v_scale;
	vec2 qp = vec2((UV.x - 0.5) * v_frame.x * v_frame.z, (1.0 - UV.y - v_frame.y) * v_frame.x);
	float z0 = ((n0.b - 0.5 * leaf0) * 4.0 - 1.0) * cr.x;
	float z1 = ((n1.b - 0.5 * leaf1) * 4.0 - 1.0) * cr.x;
	vec3 p = (rot_y(vec3(qp, z0), v_ang.x) * wa0 + rot_y(vec3(qp, z1), v_ang.y) * wa1) / wsum;
	// how far behind the crown's front surface the texel sits (seen through a gap): inner leaves are darker
	vec2 qe = vec2(qp.x / cr.x, (qp.y - cr.y) / cr.z);
	float zs = cr.x * sqrt(max(1.0 - dot(qe, qe), 0.0));
	float inner = clamp((zs - (z0 * wa0 + z1 * wa1) / wsum) / cr.x, 0.0, 2.0);
	float occ = mix(1.0, exp(-inner * interior_occlusion), leaf);
	// crown self-shadowing (the mesh gets it from the shadow map): light path through the crown ellipsoid
	vec3 sc3 = vec3(cr.x, cr.z, cr.x);
	vec3 q = (p - vec3(0.0, cr.y, 0.0)) / sc3;
	vec3 lc = normalize(light_dir) / sc3;
	float qa = dot(lc, lc);
	float qb = dot(q, lc);
	float qc = dot(q, q) - 1.0;
	float disc = qb * qb - qa * qc;
	float path = 0.0;
	if (disc > 0.0) {
		float sq = sqrt(disc);
		float t_out = (-qb + sq) / qa;
		float t_in = max((-qb - sq) / qa, 0.0);
		path = max(t_out - t_in, 0.0);
	}
	// (bark too: the crown shades its own trunk; leafless snags have no crown to speak of)
	v_self_shadow = mix(1.0, mix(self_shadow_min, 1.0, exp(-path * self_shadow_density / max(cr.x, 0.3))), v_leafy) * occ;
	// height AO as on the mesh (shaders/foliage.gdshader v_ao)
	float ao = mix(0.55, 1.0, clamp(1.2 * clamp(p.y / max(cr.w, 0.3), 0.2, 1.0), 0.0, 1.0));
	vec3 alb = a.rgb / max(a.a, 1e-3) * 2.0;     // baked at half scale
	vec3 var_tint = vec3(1.0 + (v_rand - 0.5) * 0.24);
	var_tint = mix(var_tint, var_tint * vec3(1.08, 0.95, 0.75), smoothstep(0.6, 1.0, v_rand) * 0.6);
	alb *= mix(vec3(1.0), var_tint, leaf);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// light and shadow from a point moved to the sun side of this tree's own shadow caster (the same quad turned to
	// the light): no hard self-shadow split down the middle, shadows from neighbours and terrain still land
	vec3 lh = vec3(light_dir.x, 0.0, light_dir.z);
	lh = length(lh) > 1e-4 ? normalize(lh) : vec3(0.0, 0.0, 1.0);
	LIGHT_VERTEX = VERTEX + (VIEW_MATRIX * vec4(lh, 0.0)).xyz * v_half_w;
	ALBEDO = alb * v_cloud;
	v_backlight = alb * translucency * leaf * v_cloud;
	ROUGHNESS = mix(0.9, 0.75, leaf);
	AO = ao * mix(0.55, 1.0, occ);
}

// Burley diffuse + translucency as the built-in model does for the mesh, with the crown self-shadowing applied to
// direct light only (ambient stays, as on a shadowed leaf).
void light() {
	float cndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float cndv = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float cldh = clamp(dot(LIGHT, h), 0.0, 1.0);
	float fd90m1 = 2.0 * cldh * cldh * ROUGHNESS - 0.5;
	float fdv = 1.0 + fd90m1 * pow(1.0 - cndv, 5.0);
	float fdl = 1.0 + fd90m1 * pow(1.0 - cndl, 5.0);
	float brdf = (1.0 / PI) * fdv * fdl * cndl;
	vec3 lit = LIGHT_COLOR * ATTENUATION * v_self_shadow;
	DIFFUSE_LIGHT += lit * brdf + lit * (vec3(1.0 / PI) - brdf) * v_backlight;
}
