#version 450
#include "common.glsl"
// P381 step 9 (Application SpaceWarp): the eye's scene depth copied down to the runtime's motion-vector size, and the
// motion vectors (the world stands still; the player's own movement goes to the runtime as the app space's delta pose).
layout(set = 2, binding = 0) uniform sampler2DArray sceneDepth;
layout(push_constant) uniform Push { mat4 m; vec4 extra; } pc;     // extra.xy: the drawn share (dynamic resolution)
layout(location = 0) in vec2 oUV;
layout(location = 0) out vec4 outMotion;
void main() {
    float d = texture(sceneDepth, vec3(oUV * pc.extra.xy, float(gl_ViewIndex))).r;
    gl_FragDepth = d;
    outMotion = vec4(0.0);
    // Ledger 232: where this pixel's point was in the last drawn frame (the head's turn and the player's walk are
    // motion on the screen like any other): its point from the depth, through that frame's view-projection.
    if (pc.extra.z > 0.5) {
        vec3 ndc = vec3(oUV * 2.0 - 1.0, d);
        vec4 rel = u.invViewProj[gl_ViewIndex] * vec4(ndc, 1.0);
        vec4 was = u.prevClip[gl_ViewIndex] * vec4(rel.xyz / rel.w, 1.0);
        if (was.w > 1e-4) { outMotion = vec4(ndc - was.xyz / was.w, 0.0); }
    }
}
