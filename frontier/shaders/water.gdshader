// Frontier water (lake + rivers): refraction through the screen texture, depth-based absorption and scattering,
// flowing normals (rivers scroll along UV.y), shoreline foam, rain ripples, Fresnel sky reflection.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

// WATER_OPAQUE (defined by water.gd on the quest preset): no screen/depth texture reads, so the Mobile renderer
// skips the per-eye back-buffer copy; the water body is shaded as a fixed depth of tinted water instead.
#ifndef WATER_OPAQUE
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif
uniform float opaque_depth = 2.5;      // WATER_OPAQUE: assumed water depth under the surface (m)
uniform vec3 deep_color : source_color = vec3(0.05, 0.12, 0.13);
uniform vec3 shallow_color : source_color = vec3(0.32, 0.36, 0.26);
uniform float absorption = 0.32;
uniform float flow_speed = 0.0;        // m/s along UV.y (rivers); 0 = still lake
uniform float wave_scale = 1.0;
uniform float murk = 0.6;              // silt: rivers are browner/opaquer

global uniform float rain_amount;
global uniform vec2 wind_dir;
global uniform float wind_strength;

varying vec3 v_world;
varying vec2 v_flow_uv;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_flow_uv = UV;
	// gentle swell on the lake
	if (flow_speed == 0.0) {
		float t = TIME * 0.6;
		VERTEX.y += (sin(v_world.x * 0.07 + t) * 0.5 + sin(v_world.z * 0.05 - t * 0.8) * 0.5) * 0.06 * wave_scale * (0.5 + wind_strength);
	}
}

vec2 grad_noise(vec2 p) {
	float e = 0.05;
	float c = fbm2(p);
	return vec2(fbm2(p + vec2(e, 0.0)) - c, fbm2(p + vec2(0.0, e)) - c) / e;
}

void fragment() {
	vec3 p = v_world;
	vec2 uvw;
	vec2 g;
	if (flow_speed > 0.0) {
		// flow along the ribbon: stretch noise along the stream, two phases to hide the reset
		float t = TIME * flow_speed;
		vec2 a = vec2(v_flow_uv.x * 3.0, v_flow_uv.y - t) * vec2(1.0, 0.35);
		vec2 b = vec2(v_flow_uv.x * 3.0 + 7.3, v_flow_uv.y * 1.3 - t * 1.25) * vec2(1.0, 0.45);
		g = grad_noise(a * 0.6) * 0.6 + grad_noise(b * 1.4) * 0.35;
	} else {
		float t = TIME;
		vec2 wd = normalize(wind_dir + 1e-4);
		g = grad_noise(p.xz * 0.06 + wd * t * 0.05) * 0.5 + grad_noise(p.xz * 0.21 - wd.yx * t * 0.09) * 0.35
			+ grad_noise(p.xz * 0.9 + wd * t * 0.3) * 0.12;
		g *= 0.6 + wind_strength;
	}
	// rain ripples: expanding rings in cells
	if (rain_amount > 0.01) {
		vec2 cellp = p.xz * 1.6;
		vec2 id = floor(cellp);
		vec2 f = fract(cellp) - 0.5;
		float h = hash12(id);
		float ph = fract(TIME * 1.3 + h);
		float r = length(f + (vec2(hash12(id + 3.1), hash12(id + 7.7)) - 0.5) * 0.4);
		float ring = sin((r - ph * 0.45) * 60.0) * smoothstep(0.45, 0.0, abs(r - ph * 0.45)) * (1.0 - ph);
		g += normalize(f + 1e-4) * ring * rain_amount * 0.8;
	}
	// far away the ripples are sub-pixel: calm the normals so the surface reads as a sheet reflecting the sky
	// instead of aliasing into blotches; rivers are smoother than wind-driven lake chop
	float dist = length(VERTEX);
	g *= mix(1.0, 0.25, smoothstep(25.0, 350.0, dist)) * (flow_speed > 0.0 ? 0.55 : 1.0);
	vec3 n = normalize(vec3(-g.x * 0.18 * wave_scale, 1.0, -g.y * 0.18 * wave_scale));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

#ifdef WATER_OPAQUE
	float thick = opaque_depth;
	vec3 refr = mix(shallow_color, deep_color, 0.5) * 0.5;
#else
	// depth below the surface along the view ray
	float d_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d_raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float scene_depth = -vpos.z;
	float surf_depth = -VERTEX.z;
	float thick = max(scene_depth - surf_depth, 0.0);
	// refraction offset scaled by thickness (none at the shore to avoid edge artefacts)
	vec2 off = n.xz * 0.025 * clamp(thick * 0.5, 0.0, 1.0);
	vec2 ruv = SCREEN_UV + off;
	float d2 = texture(depth_tex, ruv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, d2, 1.0);
	v2.xyz /= v2.w;
	if (-v2.z < surf_depth) ruv = SCREEN_UV;          // don't refract things in front of the water
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
#endif
	float absorb = 1.0 - exp(-thick * absorption * (1.0 + murk * 2.5));
	absorb = max(absorb, murk * 0.35 * smoothstep(0.0, 0.4, thick));     // suspended silt even in the shallows
	vec3 water_col = mix(shallow_color, deep_color, clamp(thick / 6.0, 0.0, 1.0));
	// light that crossed the water from the bed (already lit scene colour) vs light scattered back by the water
	// body itself, which must be lit by the sun/sky like any surface (unlit emission glowed at night)
	vec3 transmitted = refr * vec3(0.85, 0.92, 0.9) * (1.0 - absorb);
	vec3 scatter_alb = water_col * absorb;
	// shoreline foam / froth in fast water
	float foam = smoothstep(0.6, 0.0, thick) * (0.5 + 0.5 * vnoise(p.xz * 3.0 + TIME * 0.4));
	if (flow_speed > 0.0) {
		foam += smoothstep(0.55, 0.85, fbm2(vec2(v_flow_uv.x * 6.0, v_flow_uv.y * 2.0 - TIME * flow_speed * 1.1))) * 0.25;
	}
	foam = clamp(foam, 0.0, 1.0) * 0.7;
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(scatter_alb * (1.0 - fres), vec3(0.9), foam);
	EMISSION = transmitted * (1.0 - foam) * (1.0 - fres);
	ROUGHNESS = mix(0.03, 0.5, foam) + rain_amount * 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = 1.0;
}
