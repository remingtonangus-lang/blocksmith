shader_type canvas_item;
// Colour-vision assist (settings > Accessibility): daltonisation. Simulates the chosen dichromacy in LMS space and
// moves the colour information that viewer cannot see into channels they can (Fidaner, Lin & Ozguven). Drawn as a
// full-screen rect on the top canvas layer, so the HUD, map and menus are corrected too.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;          // 0 off, 1 protan (red-weak), 2 deutan (green-weak), 3 tritan (blue-weak)
uniform float strength = 1.0;

vec3 to_lms(vec3 c) {
	return vec3(dot(c, vec3(17.8824, 43.5161, 4.11935)),
		dot(c, vec3(3.45565, 27.1554, 3.86714)),
		dot(c, vec3(0.0299566, 0.184309, 1.46709)));
}

vec3 to_rgb(vec3 l) {
	return vec3(dot(l, vec3(0.0809444479, -0.130504409, 0.116721066)),
		dot(l, vec3(-0.0102485335, 0.0540193266, -0.113614708)),
		dot(l, vec3(-0.000365296938, -0.00412161469, 0.693511405)));
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 lms = to_lms(c);
	vec3 sim = lms;
	if (mode == 1) {
		sim.x = 2.02344 * lms.y - 2.52581 * lms.z;
	} else if (mode == 2) {
		sim.y = 0.494207 * lms.x + 1.24827 * lms.z;
	} else if (mode == 3) {
		sim.z = -0.395913 * lms.x + 0.801109 * lms.y;
	}
	vec3 err = c - to_rgb(sim);
	vec3 shift = vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
	COLOR = vec4(clamp(c + shift * strength, 0.0, 1.0), 1.0);
}
