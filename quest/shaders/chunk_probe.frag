#version 450
#include "common.glsl"
// QUEST_LAYERPROBE=1 (trailer item 5, a debugging aid): solid world faces drawn as their texture layer instead of their
// colour, so a pixel names what was drawn there (headless --pick reads it back). R: layer & 255; G: layer >> 8, +8 for
// per-position ground (triplanar), + face << 4; B: +128 tinted (grass, foliage or water colour), +64 the detail stream
// (chunk_probe_detail.frag), and the first corner layer that differs (smooth blending) & 63, or 63 for none.
layout(location = 1) flat in float oLayer;
layout(location = 3) in vec3 oTint;
layout(location = 8) flat in float oFace;
layout(location = 10) in vec4 oLayers;
layout(location = 11) in vec4 oLW;
layout(location = 12) in vec3 oNrm;
layout(location = 0) out vec4 outColor;
void main() {
    uint l = uint(oLayer + 0.5);
    uint g = (l >> 8) | (dot(oNrm, oNrm) > 0.25 ? 8u : 0u) | (min(uint(oFace + 0.5), 15u) << 4);
    uint b = 63u;
    if (oLW.x + oLW.y + oLW.z + oLW.w > 0.5) {
        vec4 L = floor(oLayers / max(oLW, vec4(1e-4)) + 0.5);
        for (int k = 0; k < 4; k++) { if (b == 63u && oLW[k] > 0.002 && uint(L[k]) != l) { b = uint(L[k]) & 63u; } }
    }
    if (any(greaterThan(abs(oTint - vec3(1.0)), vec3(0.02)))) b |= 128u;
    outColor = vec4(float(l & 255u) / 255.0, float(g & 255u) / 255.0, float(b) / 255.0, 1.0);
}
