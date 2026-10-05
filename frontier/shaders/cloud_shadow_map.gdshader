// Renders the cumulus deck's density over a square of deck space around the camera into a small viewport texture
// (src/world/cloud_shadows.gd). Same density function and drift as the sky shader.
shader_type canvas_item;

#include "res://shaders/inc/noise.gdshaderinc"
#include "res://shaders/inc/clouds.gdshaderinc"

uniform vec4 rect;          // xy min corner (m), z size (m)
uniform float cover = 0.35;
uniform float cloud_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.3);

void fragment() {
	vec2 deck = rect.xy + UV * rect.z;
	vec2 cp = deck * 0.00028 + wind_dir * cloud_time * 0.0009;
	float d = cloud_density(cp, cover);
	// thin cloud edges cast soft, partial shadow; dense cores block most of the sun
	COLOR = vec4(vec3(smoothstep(0.05, 0.85, d)), 1.0);
}
