// Comfort vignette for VR locomotion/riding: darkens the periphery in proportion to `amount`.
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled;
uniform float amount = 0.0;
void vertex() { POSITION = vec4(VERTEX.xy, 0.0, 1.0); }
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0 - amount * 0.55, 1.15 - amount * 0.45, r) * step(0.01, amount);
	ALBEDO = vec3(0.0);
	ALPHA = a;
}
