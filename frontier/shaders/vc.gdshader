// Untextured settlement parts merged into one surface per cell (iron, brass, glassware, cloth, water, mirror):
// albedo from vertex COLOR (sRGB), roughness and metallic from UV (written per source material by MeshKit.commit).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

global uniform float wetness;

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = clamp(UV.x - wetness * 0.2 * (1.0 - UV.y), 0.03, 1.0);
	METALLIC = UV.y;
	SPECULAR = 0.5;
}
