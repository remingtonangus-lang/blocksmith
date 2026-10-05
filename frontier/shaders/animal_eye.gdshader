shader_type spatial;
// Wildlife eye: a glossy sphere whose outward-facing cap carries the iris and pupil. The generator writes the
// position projected onto the eye's tangent plane (unit radius): UV.x = horizontal (forward) offset and
// UV.y = 1 - vertical offset (glTF flips v). The projection is linear in position, so it interpolates exactly
// across the sphere's flat triangles and the pupil stays round. Pupil shapes: 0 round (canids, bears, felids),
// 1 horizontal bar (deer, elk, pronghorn, bison, rabbit), 2 vertical slit (fox).

uniform vec3 iris_color : source_color = vec3(0.30, 0.18, 0.08);
uniform vec3 iris_rim : source_color = vec3(0.10, 0.06, 0.03);
uniform vec3 sclera_color : source_color = vec3(0.06, 0.045, 0.035);
uniform float iris_size : hint_range(0.2, 1.0) = 0.75;     // sine of the iris half-angle
uniform float pupil_size : hint_range(0.05, 0.9) = 0.35;   // fraction of the iris radius
uniform int pupil_shape = 0;

void fragment() {
	vec2 q = vec2(UV.x, 1.0 - UV.y);
	float r = length(q) / iris_size;                         // 0 at the centre, 1 at the iris edge
	vec2 qp = q / (iris_size * pupil_size);
	float pd = length(qp);
	if (pupil_shape == 1) {
		pd = length(qp / vec2(1.6, 0.55));
	} else if (pupil_shape == 2) {
		pd = length(qp / vec2(0.35, 1.3));
	}
	vec3 iris = mix(iris_color * 1.15, iris_rim, smoothstep(0.45, 1.0, r));
	vec3 col = mix(iris, sclera_color, smoothstep(0.93, 1.03, r));
	col = mix(vec3(0.005), col, smoothstep(0.85, 1.08, pd));
	ALBEDO = col;
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
}
