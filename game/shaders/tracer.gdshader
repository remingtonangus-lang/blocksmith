// Tracer streaks: a quad stretched 9 m back along the flight direction (INSTANCE_CUSTOM.xyz), turned to face
// the camera around that axis. INSTANCE_CUSTOM.w = faction (0 Capital: white-blue, 1 Cinder: orange-red).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

varying float v_u;
varying float v_fac;

void vertex() {
	vec3 head = MODEL_MATRIX[3].xyz;
	vec3 dir = normalize(INSTANCE_CUSTOM.xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - head);
	vec3 side = normalize(cross(dir, to_cam));
	float len = 9.0;
	float dist = length(CAMERA_POSITION_WORLD - head);
	float w = 0.035 + dist * 0.0012;          // stays visible far away
	vec3 world = head - dir * (VERTEX.y + 0.5) * len + side * VERTEX.x * w * 2.0;
	v_u = VERTEX.y + 0.5;
	v_fac = INSTANCE_CUSTOM.w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float core = pow(across, 3.0);
	float tail = 1.0 - v_u;
	vec3 col = v_fac < 0.5 ? vec3(0.75, 0.88, 1.6) : vec3(1.8, 0.75, 0.25);
	ALBEDO = col * core * tail * 4.0;
}
