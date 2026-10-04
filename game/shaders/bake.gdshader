// Impostor bake: unshaded albedo (mode 0) or view-space normal (mode 1) of a tree mesh.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform bool is_leaf = true;

varying float v_ao;

void vertex() {
	v_ao = COLOR.b;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (is_leaf && c.a < 0.5) discard;
	if (mode == 0) {
		ALBEDO = c.rgb * mix(0.55, 1.0, v_ao);
	} else {
		vec3 n = normalize(NORMAL);
		if (!FRONT_FACING) n = -n;
		ALBEDO = pow(n * 0.5 + 0.5, vec3(2.2)); // cancels the viewport's sRGB encode
	}
}
