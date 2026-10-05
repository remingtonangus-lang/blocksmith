shader_type spatial;
// Fur shells for the generated wildlife (wolf, coyote, fox, cougar, black bear, bison, raccoon, elk mane). The body
// LOD0 mesh is drawn again once per shell through the material's next_pass chain (no extra skinning): each pass
// pushes the skin out along the normal by shell_h x fur length (with a little droop) and keeps only the strands
// that reach that height, so tapered tufts build up from the coat. Fur length per region comes from fur_region()
// (bare nose and hooves, short face and lower legs, long tail, neck ruff, bison cape). Colour is the coat colour
// at the same rest point, darker at the roots. Strands thin out towards fade_end (the LOD0 range) so the switch to
// the bare LOD1 mesh does not pop. See src/actors/horse_visual.gd (_setup_fur) and AnimalCoats.FUR.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/inc/animal_coat.gdshaderinc"

uniform float shell_h = 0.5;            // 0 = root, 1 = tip
uniform float fur_len = 0.03;           // metres where fur_region() = 1
uniform float strand_density = 260.0;   // noise cells per metre
uniform float fade_start = 8.0;
uniform float fade_end = 12.0;

varying vec3 rest;
varying vec3 bake;
varying float flen;
varying vec3 v_col;
varying float v_rough;
varying float v_spec;
varying float v_rim;

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x);
	bake = COLOR.rgb;
	flen = fur_region(rest, smoothstep(0.3, 0.7, bake.b));
	float d = fur_len * flen * shell_h;
	VERTEX += NORMAL * d;
	VERTEX.y -= d * shell_h * 0.35;      // the tips droop under their weight
	// the coat colour is evaluated per vertex for the shells (the skin underneath carries the fine detail)
	float ao;
	vec3 back;
	vec3 c;
	float r;
	float sp;
	float rm;
	coat_shade(rest, bake, 0.0, c, ao, r, sp, rm, back);
	v_col = c;
	v_rough = r;
	v_spec = sp;
	v_rim = rm;
}

void fragment() {
	if (flen < 0.05) {
		discard;
	}
	vec3 sp = rest * strand_density + pattern_seed;
	// tufts: fine strands modulated by coarser clumps; a strand survives up to its own height
	float n = 0.62 * vnoise(sp) + 0.38 * vnoise(sp * 0.31 + 7.1);
	float fade = smoothstep(fade_start, fade_end, length(VERTEX));
	float keep = mix(0.16, 0.9, shell_h) + fade * (1.0 - shell_h * 0.3);
	if (n < keep) {
		discard;
	}
	vec3 col = v_col * mix(0.9, 1.06, vnoise(sp * 1.7 + 3.3));            // strand-to-strand variation
	float tip = smoothstep(0.55, 1.0, shell_h);
	col *= mix(0.74, 1.0, shell_h);                                      // self-shadowed roots
	col = mix(col, col * 1.1 + vec3(0.015), tip * grizzle * 0.5);          // pale banded tips on agouti coats
	ALBEDO = col;
	AO = mix(0.55, 1.0, shell_h);
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = clamp(v_rough + 0.08, 0.0, 1.0);
	SPECULAR = v_spec * 0.5;
	RIM = v_rim * 0.8;
	RIM_TINT = 0.7;
	BACKLIGHT = col * 0.12;
}
