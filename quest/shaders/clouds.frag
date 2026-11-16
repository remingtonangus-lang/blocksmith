#version 450
#define BS_CLOUDS 1
#include "common.glsl"
layout(location = 0) in vec2 oNdc;
layout(location = 0) out vec4 outColor;
// Two cloud decks over the overworld sky (L1 look upgrade, docs/status/look-upgrade.md): soft cumulus and high cirrus,
// both ray-cast onto flat planes above the eye (no geometry), driven by one wind (u.clouds.xy = the eye in cloud space,
// u.wind.xy = its direction; Sources/SkyLook.swift). Lit by the sun (gold at its rise and set, white at noon) or the
// moon, self-shadowed by one tap toward the sun, thicker and darker as the cover rises with rain, and lit from inside
// by storm flashes. Drawn after the dome, stars, sun and moon (blended, depth 1: only over open sky, so it hides them).
// Cost: 7 value-noise taps per sky pixel (5 cumulus, 2 cirrus); none below the horizon. (Nov 11: each tap one fetch
// from the noise lattice table, common.glsl vnoise.)
void main() {
    vec4 w = u.invViewProj[gl_ViewIndex] * vec4(oNdc, 1.0, 1.0);
    vec4 c = cloudDecks(normalize(w.xyz / w.w));
    if (c.a < 0.003) { discard; }
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    outColor = worldColor(vec4(c.rgb + (ign - 0.5) / 255.0, c.a));
}
