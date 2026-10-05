// Painted sign letters from a multichannel signed-distance atlas (src/world/sign_text.gd): crisp edges at any
// distance, paint colour from vertex COLOR, chipped/faded paint from the building weathering (COLOR.a).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/noise.gdshaderinc"

uniform sampler2D atlas : filter_linear, repeat_disable;
uniform float px_range = 6.0;

global uniform float wetness;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float median3(vec3 c) { return max(min(c.r, c.g), min(max(c.r, c.g), c.b)); }

void fragment() {
	vec3 s = texture(atlas, UV).rgb;
	float sd = median3(s) - 0.5;
	vec2 unit = vec2(px_range) / vec2(textureSize(atlas, 0));
	vec2 screen_tex = vec2(1.0) / max(fwidth(UV), vec2(1e-6));
	float spx = max(0.5 * dot(unit, screen_tex), 1.0);
	float a = clamp(sd * spx + 0.5, 0.0, 1.0);
	// chipped paint: small flakes missing where weathered
	float flake = vnoise(v_wpos.xz * 37.0 + v_wpos.y * 41.0) * 0.5 + 0.5;
	float wear = COLOR.a;
	a *= step(wear * 0.55, flake);
	float fade = 1.0 - wear * 0.25 * (vnoise(v_wpos.xy * 3.0 + v_wpos.zy * 2.0) * 0.5 + 0.5);
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * fade;
	ROUGHNESS = mix(0.55, 0.3, wetness);
	SPECULAR = 0.4;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
