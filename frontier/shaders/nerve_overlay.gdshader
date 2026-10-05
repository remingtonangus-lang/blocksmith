// Nerve slow-time look: the world drains to a warm, high-contrast sepia like an old albumen print, with paper grain,
// a faint radial blur toward the centre, and a vignette that tightens on each heartbeat (lub-dub, ~78 bpm, real
// time: TIME is not scaled by Engine.time_scale). Cheap single pass; safe on the Mobile renderer.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(1.25, 1.0));
	vec3 col = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		col += textureLod(screen_tex, 0.5 + c * (1.0 - float(i) * 0.007 * r), 0.0).rgb;
	}
	col /= 6.0;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	// tone curve: lift the toe, roll the shoulder (print look)
	l = smoothstep(0.02, 0.95, l);
	vec3 sepia = mix(vec3(0.16, 0.10, 0.06), vec3(1.0, 0.90, 0.72), l);
	vec3 outc = mix(col, sepia, 0.88 * strength);
	// keep a hint of red (blood, ink) so marks still read
	float red = clamp((col.r - max(col.g, col.b)) * 2.5, 0.0, 1.0);
	outc = mix(outc, col * vec3(1.05, 0.7, 0.6), red * 0.5 * strength);
	// heartbeat: two pulses per beat
	float t = fract(TIME * 1.3);
	float beat = exp(-pow((t - 0.05) * 18.0, 2.0)) + 0.6 * exp(-pow((t - 0.22) * 18.0, 2.0));
	float vig = smoothstep(0.95, 0.28 - beat * 0.05, r);
	outc *= mix(1.0, vig, 0.9 * strength);
	// paper grain
	float g = hash(floor(uv * vec2(640.0, 360.0)) + floor(TIME * 24.0)) - 0.5;
	outc += g * 0.05 * strength;
	outc = (outc - 0.5) * 1.15 + 0.5;
	COLOR = vec4(outc, 1.0);
}
