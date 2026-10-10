#version 450
#include "common.glsl"
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec4 oColor;
layout(location = 3) in float oDist;
layout(location = 4) flat in float oOverlay;
layout(location = 0) out vec4 outColor;
void main() {
    vec4 c = texSharp(oUV, oLayer);
    if (c.a < 0.1) { discard; }
    outColor = finalColor(vec4(c.rgb * oColor.rgb, c.a * oColor.a));
}
