shader_type spatial;
// Mane / forelock / tail hair cards: painted strand texture (alpha = strands), root-to-tip colour, anisotropic
// highlight along the strands, wind/motion flutter toward the tips, dirt and wet. UV: u across the card, v root (0)
// to tip (1). Alpha-to-coverage keeps edges soft with MSAA; alpha scissor otherwise.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

uniform sampler2D strands : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 hair_color : source_color = vec3(0.05, 0.035, 0.03);
uniform vec3 tip_color : source_color = vec3(0.12, 0.08, 0.05);
uniform float pinto = 0.0;
uniform vec3 pattern_seed = vec3(0.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float flutter = 1.0;
uniform float motion = 0.0;            // 0 standing .. 1 gallop: more flutter
global uniform float wind_strength;
global uniform vec2 wind_dir;
global uniform float wetness;

varying float tipness;

void vertex() {
	tipness = UV.y;
	float t = TIME * (2.0 + motion * 5.0);
	float k = UV.y * UV.y * flutter * (0.006 + 0.012 * wind_strength + 0.02 * motion);
	VERTEX += NORMAL * sin(t + VERTEX.x * 9.0 + VERTEX.z * 7.0 + UV.x * 3.0) * k;
}

void fragment() {
	vec4 s = texture(strands, UV);
	vec3 c = mix(hair_color, tip_color, smoothstep(0.2, 1.0, tipness));
	c *= s.rgb * 1.25;
	if (pinto > 0.6) {
		c = mix(c, vec3(0.88, 0.86, 0.82), step(0.55, fract(sin(dot(floor(UV * vec2(3.0, 1.0)) + pattern_seed.xy, vec2(12.9898, 78.233))) * 43758.5453)) * 0.7);
	}
	c = mix(c, vec3(0.45, 0.38, 0.30), dirt * 0.4 * tipness);
	float w = clamp(max(wet, wetness), 0.0, 1.0);
	c *= mix(1.0, 0.7, w);
	ALBEDO = c;
	ALPHA = s.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = mix(0.5, 0.3, w);
	SPECULAR = 0.45;
	ANISOTROPY = 0.75;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	BACKLIGHT = c * 0.35;
	AO = mix(0.55, 1.0, smoothstep(0.0, 0.45, tipness));
}
