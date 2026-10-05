// Receiving side of the cloud shadows: the ground point is projected along the sun to the cloud deck and looks up
// the density map rendered by src/world/cloud_shadows.gd. Returns the factor to multiply direct-lit albedo by.
global uniform sampler2D cloud_shadow_map;
global uniform vec4 cloud_shadow_rect;   // xy deck-space min corner (m), z size (m), w strength (0 = off)
global uniform vec4 cloud_sun;           // xyz towards the sun, w deck altitude (m)

float cloud_shade(vec3 wp) {
	if (cloud_shadow_rect.w <= 0.0) {
		return 1.0;
	}
	vec3 sd = cloud_sun.xyz;
	vec2 deck = wp.xz + sd.xz / max(sd.y, 0.12) * (cloud_sun.w - wp.y);
	vec2 uv = (deck - cloud_shadow_rect.xy) / cloud_shadow_rect.z;
	vec2 e = min(uv, 1.0 - uv);
	float edge = smoothstep(0.0, 0.08, min(e.x, e.y));
	float d = texture(cloud_shadow_map, uv).r * edge;
	return 1.0 - d * cloud_shadow_rect.w;
}
