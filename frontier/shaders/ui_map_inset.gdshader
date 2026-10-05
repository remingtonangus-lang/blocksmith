// Map inset: a rotating window into the paper map around the player, soft-edged and slightly darkened at the rim.
shader_type canvas_item;
uniform vec2 center = vec2(0.5);
uniform float rotation = 0.0;
uniform float zoom = 0.05;

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(rotation), s = sin(rotation);
	// camera yaw rotates the map so "up" is where the camera looks
	// screen offset -> world (x, z): right = (cos, -sin), forward = (-sin, -cos) for camera yaw
	vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
	vec2 uv = center + q * zoom * 2.0;
	vec4 col = texture(TEXTURE, uv);
	float edge = smoothstep(0.5, 0.42, max(abs(p.x), abs(p.y)));
	col.rgb *= mix(0.75, 1.0, edge);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) col.rgb = vec3(0.86, 0.79, 0.64);
	COLOR = vec4(col.rgb, 0.96);
}
