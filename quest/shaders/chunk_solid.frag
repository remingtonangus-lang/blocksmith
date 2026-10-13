#version 450
#include "common.glsl"
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec3 oShade;
layout(location = 3) in vec3 oTint;
layout(location = 4) flat in float oOverlay;
layout(location = 5) flat in float oAnim;
layout(location = 6) in float oDist;
layout(location = 7) in vec3 oRel;
layout(location = 8) flat in float oFace;
layout(location = 10) in vec4 oLayers;      // smooth terrain: each corner's layer x its weight (chunk.vert)
layout(location = 11) in vec4 oLW;
layout(location = 0) out vec4 outColor;
void main() {
    vec2 uv = oUV;
    if (oAnim > 0.5 && oAnim < 1.5) { uv += vec2(0.0, fract(u.params.z * 0.04)); }
    // Grass tops: turned per block (texSharpTurned); the cell is the world block under this fragment.
    vec4 c = oAnim > 1.5 ? texSharpTurned(uv, oLayer, floor(oRel.xz + u.eye.xz - fract(uv) + 0.5)) : texSharp(uv, oLayer);
    if (oAnim > 0.5 && oAnim < 1.5) { c.rgb = lavaGlow(c.rgb, oRel); }
    // Smooth terrain (P142): where the quad's corners are different materials (grass to dirt to stone to sand), blend
    // them by how near each corner is, sharpened and broken up by the texture's own brightness so the border wanders
    // like real ground instead of fading. One texture read where a quad is one material (most of them).
    if (oLW.x + oLW.y + oLW.z + oLW.w > 0.5) {
        vec4 L = floor(oLayers / max(oLW, vec4(1e-4)) + 0.5);
        vec4 diff = vec4(notEqual(L, vec4(oLayer))) * step(vec4(0.002), oLW);
        if (dot(diff, diff) > 0.0) {
            vec4 w = oLW * oLW;
            vec3 acc = c.rgb * dot(w, 1.0 - diff);
            float wsum = dot(w, 1.0 - diff);
            for (int k = 0; k < 4; k++) {
                if (diff[k] > 0.5) {
                    vec4 ck = texSharp(uv, L[k]);
                    float wk = w[k] * (0.6 + 0.8 * dot(ck.rgb, vec3(0.333)));     // brighter grains of the other ground poke through first
                    acc += ck.rgb * wk; wsum += wk;
                }
            }
            c.rgb = acc / max(wsum, 1e-4);
        }
    }
    vec3 t = (oOverlay > 0.5 && c.a > 0.95) ? vec3(1.0) : oTint;
    outColor = worldColor(vec4(applyFogDir(waterAmbient(c.rgb * t * oShade, c.rgb * t), oRel, oDist), 1.0));
}
