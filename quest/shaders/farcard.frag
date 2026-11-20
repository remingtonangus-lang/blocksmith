#version 450
#include "common.glsl"
// Ledger 362: the far trees' cards. The picture is the game's own render of the tree at noon (gamma out), so it is
// taken back to light, scaled by the light now, fogged like the land and sent out the same way.
layout(set = 0, binding = 3) uniform sampler2DArray farTex;
layout(push_constant) uniform Push { mat4 m; vec4 extra; } pc;
layout(location = 0) in vec3 oUVL;
layout(location = 1) in vec4 oLit;
layout(location = 2) in vec4 oFog;
layout(location = 3) in vec3 oTint;
layout(location = 0) out vec4 outColor;
void main() {
    vec4 t = texture(farTex, oUVL);
    // The rim of the loaded disc: cards come in through a screen-door pattern, so there is no line where they start.
    float dither = fract(dot(floor(gl_FragCoord.xy), vec2(0.5, 0.25)) + 0.125);
    if (t.a < 0.5 || oLit.a <= dither) { discard; }
    // (the picture already went through the film curve once: only the fog's colour goes through it here)
    // Ledger 362 (his v5 verdict, "just need some more white on those far trees"): the column's foliage tint and the
    // wood's shade went over the whole picture, snow included, so snow in thick woods went grey by up to a fifth. Now
    // they take only the leaf pixels, and the snow is lifted a little (a touch whiter than a strict match, as asked).
    // (extra.z where snow starts in the picture's darkest channel, extra.w how far it is lifted toward white)
    float lo = pc.extra.z;
    float snow = smoothstep(lo, lo + 0.2, min(t.r, min(t.g, t.b)));
    vec3 base = mix(t.rgb, vec3(max(t.r, max(t.g, t.b))), snow * pc.extra.w * 2.0);
    vec3 c = pow(clamp(base * (1.0 + pc.extra.w * snow), 0.0, 1.0), vec3(1.0 / u.misc.z)) * oLit.rgb * mix(oTint, vec3(1.0), snow);
    c = mix(c, oFog.rgb, oFog.a);
    outColor = finalColor(vec4(c, 1.0));
}
