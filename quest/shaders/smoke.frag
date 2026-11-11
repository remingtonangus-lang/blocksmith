#version 450
#include "common.glsl"
// Smoke (Particles.isSmoke): the entity pass's look (sharp texels, the light in the vertex colour, fog) but see-through,
// the vertex alpha its thickness (trailer, Nov 11: opaque dark puffs read as black blobs at night).
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec4 oColor;
layout(location = 3) in float oDist;
layout(location = 4) flat in float oOverlay;
layout(location = 0) out vec4 outColor;
void main() {
    vec4 c = texSharp(oUV, oLayer);
    if (c.a < 0.5) { discard; }
    float a = oColor.a * (1.0 - fogAmount(oDist));
    outColor = worldColor(vec4(applyFog(c.rgb * oColor.rgb, oDist), a));
}
