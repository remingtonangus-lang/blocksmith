shader_type spatial;
// Feather cards for the bird wings and tails (tools/animals/bird.py). UV.x runs along the span (0 shoulder,
// 1 tip) or tail length; UV.y across the chord (0 leading edge, 1 trailing edge) or tail width. The shader cuts
// the outline (scalloped feather tips, separated "finger" primaries for soaring birds, spiky grouse tail) with
// alpha scissor and paints coverts, flight feathers, barring, dark tips, the pale underside (back faces) and
// tail bands. Two-sided.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform bool is_tail = false;
uniform vec3 covert_color : source_color = vec3(0.35, 0.27, 0.2);
uniform vec3 flight_color : source_color = vec3(0.25, 0.2, 0.15);
uniform vec3 under_color : source_color = vec3(0.7, 0.65, 0.58);
uniform vec3 tip_color : source_color = vec3(0.12, 0.1, 0.08);
uniform vec3 bar_color : source_color = vec3(0.6, 0.55, 0.45);
uniform float bars = 0.0;            // number of pale bars across the flight / tail feathers
uniform float tip_amount = 0.4;
uniform int fingers = 0;             // separated primaries at the wing tip
uniform float feathers = 18.0;       // feathers along the trailing edge
uniform float spiky = 0.0;           // grouse: pointed tail feathers
uniform vec3 tail_band : source_color = vec3(0.1, 0.08, 0.06);
uniform float tail_band_amount = 0.0;
uniform vec3 tail_tip_color : source_color = vec3(0.75, 0.68, 0.55);
uniform float tail_tip_amount = 0.0;
uniform float sheen = 0.0;
uniform vec3 sheen_tint : source_color = vec3(0.4, 0.5, 0.9);

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec3 col;
	float alpha = 1.0;
	if (!is_tail) {
		// trailing edge: scalloped feather tips
		float fu = fract(u * feathers);
		float scallop = 0.93 + 0.07 * cos((fu - 0.5) * 6.2832 * 0.5);
		if (v > scallop) {
			alpha = 0.0;
		}
		// splayed primaries ("fingers"): slots between the outer feathers, deepest at the tip
		if (fingers > 0 && u > 0.74) {
			float fx = (u - 0.74) / 0.26 * float(fingers);
			float slot = smoothstep(0.0, 0.25, abs(fract(fx) - 0.5) * 2.0 - 0.6);
			float depth = mix(0.35, 0.05, (u - 0.74) / 0.26);
			if (v > depth && fract(fx) > 0.8) {
				alpha = 0.0;
			}
			if (v > 0.85 - 0.5 * (u - 0.74) && slot > 0.5) {
				alpha = 0.0;
			}
		}
		// tip of the wing: rounded
		if (u > 0.97 && v > (1.0 - u) * 25.0) {
			alpha = 0.0;
		}
		float coverts = 1.0 - smoothstep(0.32, 0.42, v + 0.05 * sin(u * 40.0));
		col = mix(flight_color, covert_color, coverts);
		float bar = step(0.6, fract(v * bars + u * 2.0)) * step(0.35, v) * step(0.5, bars);
		col = mix(col, bar_color, bar * 0.6);
		col = mix(col, tip_color, smoothstep(0.75, 0.95, max(v, (u - 0.7) / 0.3)) * tip_amount);
		col *= 0.9 + 0.1 * step(0.5, fract(u * feathers));     // feather to feather variation
		if (!FRONT_FACING) {
			col = mix(col, under_color, 0.75 * (1.0 - smoothstep(0.85, 1.0, u)) * (1.0 - tip_amount * smoothstep(0.8, 1.0, v)));
		}
	} else {
		// tail fan: u along the tail, v across (0..1); rounded or spiky tip
		float across = abs(v - 0.5) * 2.0;
		float tipline = 0.92 - 0.12 * across * across;
		float fv = fract(v * 12.0);
		tipline += spiky * (0.1 * (1.0 - abs(fv - 0.5) * 2.0) - 0.08);
		if (u > tipline) {
			alpha = 0.0;
		}
		col = flight_color;
		float bar = step(0.6, fract(u * bars)) * step(0.5, bars) * step(0.2, u);
		col = mix(col, bar_color, bar * 0.6);
		col = mix(col, tail_band, (1.0 - smoothstep(0.03, 0.06, abs(u - (tipline - 0.13)))) * tail_band_amount);
		col = mix(col, tail_tip_color, smoothstep(tipline - 0.07, tipline - 0.03, u) * tail_tip_amount);
		col *= 0.9 + 0.1 * step(0.5, fv);
		if (!FRONT_FACING) {
			col = mix(col, under_color, 0.5);
		}
	}
	if (alpha < 0.5) {
		discard;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.4, sheen);
	SPECULAR = mix(0.3, 0.6, sheen);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	EMISSION = sheen_tint * fres * sheen * 0.06;
	BACKLIGHT = col * 0.25;
}
