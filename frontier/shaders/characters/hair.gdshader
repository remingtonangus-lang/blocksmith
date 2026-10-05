// Hair cards for generated characters: MakeHuman CC0 hair texture re-coloured to a per-character hair colour
// (luminance-preserving), alpha scissor with alpha-to-coverage, anisotropic highlight along the strands, wetness.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool use_normal = false;
uniform vec3 hair_color : source_color = vec3(0.25, 0.17, 0.11);
uniform float alpha_cut = 0.38;
uniform float grey = 0.0;   // 0..1 greying for elders
uniform bool use_vertex_color = false;   // beards: COLOR.rgb = shell occlusion, COLOR.a = shell density

global uniform float wetness;

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	float avg = dot(textureLod(albedo_tex, vec2(0.5), 10.0).rgb, vec3(0.299, 0.587, 0.114));
	float rel = clamp(lum / max(avg, 0.02), 0.2, 2.5);
	vec3 c = mix(hair_color, vec3(0.62, 0.6, 0.57), grey) * rel;
	c *= mix(1.0, 0.65, clamp(wetness, 0.0, 1.0));
	float a = t.a;
	if (use_vertex_color) {
		c *= COLOR.rgb;
		a *= COLOR.a;
	}
	ALBEDO = clamp(c, 0.0, 1.0);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = mix(0.5, 0.25, clamp(wetness, 0.0, 1.0));
	SPECULAR = 0.35;
	ANISOTROPY = 0.7;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	BACKLIGHT = c * 0.25;
}
