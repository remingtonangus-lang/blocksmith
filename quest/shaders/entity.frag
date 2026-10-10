#version 450
#include "common.glsl"
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec4 oColor;
layout(location = 3) in float oDist;
layout(location = 4) flat in float oOverlay;
layout(location = 0) out vec4 outColor;
void main() {
    // Held tools and dropped items: sharp-bilinear like the blocks (crisp texels up close, Quest round 3's blurry
    // tools; no stair-step crawl), trilinear once a texel is smaller than a pixel.
    vec4 c = texSharp(oUV, oLayer);
    if (c.a < 0.5) { discard; }
    vec3 rgb = c.rgb;
    if (oOverlay > 0.5 && c.a < 0.95) { rgb *= vec3(0.57, 0.74, 0.35); }
    outColor = worldColor(vec4(applyFog(rgb * oColor.rgb, oDist), 1.0));
}
