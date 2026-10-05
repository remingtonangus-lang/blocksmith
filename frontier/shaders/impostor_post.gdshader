// Impostor bake resolve (src/world/impostor_baker.gd): 2x2 box downsample of the supersampled bake into the atlas,
// written with premultiplied alpha so mipmaps and bilinear filtering never bleed the transparent background into
// the canopy edges (no dilation pass needed). The top half (albedo) holds sRGB-encoded colour: averaged in linear
// light and re-encoded; the bottom half (normals) is raw data.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_nearest;

vec3 to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	ivec2 dst = textureSize(src, 0) / 2;
	ivec2 o = ivec2(floor(UV * vec2(dst))) * 2;
	bool srgb = UV.y < 0.5;
	vec3 rgb = vec3(0.0);
	float a = 0.0;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec4 c = texelFetch(src, o + ivec2(i, j), 0);
			vec3 v = srgb ? to_lin(c.rgb) : c.rgb;
			rgb += v * c.a;
			a += c.a;
		}
	}
	rgb *= 0.25;
	a *= 0.25;
	COLOR = vec4(srgb ? to_srgb(rgb) : rgb, a);
}
