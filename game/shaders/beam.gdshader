// Searchlight beam: a soft additive cone, brightest along its axis and near the lamp, fading with length.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 0.05;
uniform vec3 tint : source_color = vec3(0.9, 0.93, 1.0);
varying float v_along;

void vertex() {
	v_along = 1.0 - (VERTEX.y / 700.0 + 0.5);   // 0 at the lamp (top of the cylinder), 1 at the far end
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float fade = (1.0 - smoothstep(0.0, 1.0, v_along)) * smoothstep(0.0, 0.02, v_along);
	ALBEDO = tint * intensity * edge * fade;
}
