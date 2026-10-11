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
layout(location = 0) out vec4 outColor;
void main() {
    vec2 uv = oUV;
    if (oAnim > 0.5 && oAnim < 1.5) { uv += vec2(0.0, fract(u.params.z * 0.04)); }
    // Grass tops: turned per block (texSharpTurned); the cell is the world block under this fragment.
    vec4 c = oAnim > 1.5 ? texSharpTurned(uv, oLayer, floor(oRel.xz + u.eye.xz - fract(uv) + 0.5)) : texSharp(uv, oLayer);
    if (oAnim > 0.5 && oAnim < 1.5) { c.rgb = lavaGlow(c.rgb, oRel); }
    vec3 t = (oOverlay > 0.5 && c.a > 0.95) ? vec3(1.0) : oTint;
    outColor = worldColor(vec4(applyFogDir(waterAmbient(c.rgb * t * oShade, c.rgb * t), oRel, oDist), 1.0));
}
