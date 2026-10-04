// Nerve slow-time look: drain colour toward a warm sepia, crush the edges with a vignette, a faint radial blur
// and a pulse in time with the heartbeat.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c);
	vec3 col = vec3(0.0);
	// cheap radial blur toward the centre
	for (int i = 0; i < 6; i++) {
		col += textureLod(screen_tex, 0.5 + c * (1.0 - float(i) * 0.006 * r), 0.0).rgb;
	}
	col /= 6.0;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 sepia = vec3(l * 1.08, l * 0.92, l * 0.72);
	vec3 outc = mix(col, sepia, 0.72 * strength);
	float pulse = 0.5 + 0.5 * sin(TIME * 7.5 * 0.28);
	float vig = smoothstep(0.85, 0.25, r + pulse * 0.02);
	outc *= mix(1.0, vig, 0.85 * strength);
	outc = (outc - 0.5) * 1.12 + 0.5;
	COLOR = vec4(outc, 1.0);
}
