// Muzzle flashes: a camera-facing star burst. INSTANCE_CUSTOM.x = remaining life (1..0), .y = random rotation.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

varying float v_life;
varying float v_rot;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = c + (right * VERTEX.x + up * VERTEX.y) * s;
	v_life = max(INSTANCE_CUSTOM.x, 0.0);
	v_rot = INSTANCE_CUSTOM.y * 6.28;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x) + v_rot;
	// Never negative: with additive blending a negative value subtracts, and the star's arms past the quad's
	// circle (1 - r < 0) or an expired flash drew a dark teal star in the air.
	float star = pow(abs(cos(a * 2.5)), 6.0) * max(1.0 - r, 0.0) + pow(max(1.0 - r * 1.6, 0.0), 2.0);
	ALBEDO = vec3(4.0, 2.6, 1.1) * star * v_life;
}
