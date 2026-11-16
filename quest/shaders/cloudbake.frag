#version 450
#define BS_CLOUDS 1
#include "common.glsl"
// The cloud map (Nov 16, ledger 171; quest/src/vk/CloudMap.swift): the cloud decks painted into a square image of the
// whole sky dome, a strip of rows a frame, and clouds_map.frag reads it back with one texture read a pixel in place of
// the decks' seven noise taps. A texel stands for a fixed point of the cumulus deck: the point straight up the map's
// direction from the map's origin (pc.extra.xy, in cloud space) at the height the deck was over the eye then
// (pc.extra.z). The zenith is the image's centre and the horizon its inscribed circle (zenith angle = radius x 90
// degrees). What is painted is what today's eye sees through that point, so a strip painted later fits the others.
// Stored: the colour after the film curve and the grade, times its cover (premultiplied), and the cover.
layout(push_constant) uniform Push { mat4 model; vec4 extra; } pc;
layout(location = 0) in vec2 oNdc;
layout(location = 0) out vec4 outColor;
void main() {
    float r = min(length(oNdc), 0.9985);
    vec2 az = oNdc / max(length(oNdc), 1e-5);
    float th = r * 1.5707963;
    vec2 q = az * (pc.extra.z * sin(th) / cos(th));          // the deck point, from the map's origin
    vec2 e = u.clouds.xy - pc.extra.xy;                       // the eye, from the map's origin
    vec4 c = cloudDecks(normalize(vec3(q.x - e.x, CUMULUS_Y - u.eye.y, q.y - e.y)));
    if (length(oNdc) >= 1.0) { c = vec4(0.0); }
    outColor = vec4(grade(filmic(c.rgb)) * c.a, c.a);
}
