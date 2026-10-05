// Distant trees: one camera-facing (Y-axis) card per tree, albedo + view-space normal baked from the real mesh
// (atlas column = species). Hidden near the camera where the full mesh is drawn (cross-faded with a dither).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform float species_count = 4.0;
uniform float near_start = 300.0;
uniform float far_end = 6000.0;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(0.85, 0.95, 0.75);

varying float v_fade;
varying vec3 v_right;
varying float v_tint;

// Far thinning: beyond thin_start a stable hashed subset of the cards is kept (down to thin_min at far_end) and
// each kept card grows by 1/sqrt(keep), so the forest covers the same area with fewer, larger cards. Far cards are
// a pixel or less wide; the impostors were the largest tree cost of the GPU ablation (1.6-1.9 ms of a 17 ms
// battle frame on the CI Mac).
uniform float thin_start = 1200.0;
uniform float thin_min = 0.3;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[1].xyz);
	float sx = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float d = length(to_cam);
	float keep = mix(1.0, thin_min, smoothstep(thin_start, far_end, d));
	float grow = inversesqrt(keep);
	vec3 fwd = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(0.0001));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 world = origin + right * VERTEX.x * sx * 2.0 * grow + vec3(0.0, VERTEX.y * sc * grow, 0.0);
	v_fade = smoothstep(near_start, near_start + 30.0, d) * (1.0 - smoothstep(far_end * 0.85, far_end, d));
	if (hash12(origin.xz * 0.37) > keep) v_fade = 0.0;
	v_right = right;
	v_tint = INSTANCE_CUSTOM.y;
	float sp = INSTANCE_CUSTOM.x;
	UV = vec2((UV.x + sp) / species_count, UV.y);
	// Back to model space without inverse(MODEL_MATRIX) (two 4x4 inverses per vertex): the instance basis is a
	// scaled rotation, so its inverse is the transpose over the squared column lengths.
	mat3 m = mat3(MODEL_MATRIX);
	vec3 inv2 = 1.0 / vec3(dot(m[0], m[0]), dot(m[1], m[1]), dot(m[2], m[2]));
	vec3 w = v_fade <= 0.0 ? -origin : world - origin;
	VERTEX = (transpose(m) * w) * inv2;
	NORMAL = (transpose(m) * fwd) * inv2;
}

void fragment() {
	vec4 c = texture(albedo_atlas, UV);
	float dither = hash12(floor(FRAGCOORD.xy) + 0.5);
	if (c.a < 0.5 || dither > v_fade) discard;
	vec3 nb = texture(normal_atlas, UV).xyz * 2.0 - 1.0;
	// Baked normal (x right, y up, z toward the viewer) to world, then to view space.
	vec3 fwd = normalize(cross(v_right, vec3(0.0, 1.0, 0.0)));
	vec3 nw = normalize(v_right * nb.x + vec3(0.0, 1.0, 0.0) * nb.y - fwd * nb.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 col = c.rgb * mix(tint_a, tint_b, v_tint);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.4;
}
