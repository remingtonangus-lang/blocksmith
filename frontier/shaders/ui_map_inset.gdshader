// Map inset: a rotating window into the paper map around the player, soft-edged and slightly darkened at the rim.
shader_type canvas_item;
uniform vec2 center = vec2(0.5);
uniform float rotation = 0.0;
uniform float zoom = 0.05;
// live relief at inset scale (the paper map's own contours are too sparse up close): the world heightmap
uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float h_range = 1600.0;
uniform float map_size = 8192.0;
uniform bool has_heights = false;

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(rotation), s = sin(rotation);
	// camera yaw rotates the map so "up" is where the camera looks
	// screen offset -> world (x, z): right = (cos, -sin), forward = (-sin, -cos) for camera yaw
	vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
	vec2 uv = center + q * zoom * 2.0;
	vec4 col = texture(TEXTURE, uv);
	if (has_heights) {
		float px = zoom * 2.0 / 180.0;                       // map uv per inset pixel (~180 px panel)
		// 5-tap smoothed height: the 2 m heightmap otherwise draws jagged 10 m lines on near-flat ground
		float h = (texture(heightmap, uv).r * 2.0 + texture(heightmap, uv + vec2(px, 0.0) * 1.5).r
			+ texture(heightmap, uv - vec2(px, 0.0) * 1.5).r + texture(heightmap, uv + vec2(0.0, px) * 1.5).r
			+ texture(heightmap, uv - vec2(0.0, px) * 1.5).r) / 6.0 * h_range;
		float hx = texture(heightmap, uv + vec2(px, 0.0)).r * h_range - h;
		float hz = texture(heightmap, uv + vec2(0.0, px)).r * h_range - h;
		float slope = length(vec2(hx, hz)) / (px * map_size);
		// contours every 10 m, index line every 50 m, faded on steep ground so cliffs don't turn solid
		float f10 = abs(fract(h / 10.0 + 0.5) - 0.5) * 10.0 / max(fwidth(h), 1e-3);
		float f50 = abs(fract(h / 50.0 + 0.5) - 0.5) * 50.0 / max(fwidth(h), 1e-3);
		float line = (1.0 - smoothstep(0.3, 0.9, f10)) * 0.12 + (1.0 - smoothstep(0.5, 1.3, f50)) * 0.24;
		line *= 1.0 - smoothstep(0.6, 1.4, slope);
		// soft hillshade from the north-west, inked in sepia
		float shade = clamp((hx - hz) / (px * map_size) * 1.6, -0.6, 0.6);
		vec3 ink = vec3(0.36, 0.27, 0.17);
		col.rgb = mix(col.rgb, ink, line);
		col.rgb *= 1.0 - shade * 0.18;
	}
	float edge = smoothstep(0.5, 0.42, max(abs(p.x), abs(p.y)));
	col.rgb *= mix(0.75, 1.0, edge);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) col.rgb = vec3(0.86, 0.79, 0.64);
	COLOR = vec4(col.rgb, 0.96);
}
