shader_type spatial;
// Wildlife coat (every generated species except the horse, which has horse_coat.gdshader). Painted in REST space
// like the horse: UV = rest (x, y), UV2.x = rest z (metres; Blender axes +x right, +y forward, +z up), COLOR = (AO,
// curvature, hoof mask, 1). Species-specific regions are placed with anchor points written by the generator
// (<species>_gaits.json "anchors") and colours/amounts from AnimalCoats (src/actors/animal_coats.gd):
// countershaded belly, darker dorsal saddle, agouti grizzle (wolves, coyotes), lower-leg points, white rump patch
// and black tail tip (deer, elk, pronghorn), throat/neck bands (pronghorn), face mask and ringed tail (raccoon),
// pale muzzle / dark nose pad, shaggy cape (bison), ear backs; plus blood, mud, wet and a skinned-carcass state.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/animal_coat.gdshaderinc"

varying vec3 rest;
varying vec3 bake;

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x);
	bake = COLOR.rgb;
}

void fragment() {
	vec3 back;
	float gfade = 1.0 - smoothstep(0.35, 1.2, length(fwidth(grizzle_coord(rest / body_scale))));
	coat_shade(rest, bake, gfade, ALBEDO, AO, ROUGHNESS, SPECULAR, RIM, back);
	AO_LIGHT_AFFECT = 0.35;
	RIM_TINT = 0.7;
	BACKLIGHT = back;
}
