#version 450
#include "common.glsl"
// P381 step 9 (Application SpaceWarp): the eye's scene depth copied down to the runtime's motion-vector size, and the
// motion vectors (the world stands still; the player's own movement goes to the runtime as the app space's delta pose).
layout(set = 2, binding = 0) uniform sampler2DArray sceneDepth;
layout(push_constant) uniform Push { mat4 m; vec4 extra; } pc;     // extra.xy: the drawn share (dynamic resolution)
layout(location = 0) in vec2 oUV;
layout(location = 0) out vec4 outMotion;
void main() {
    gl_FragDepth = texture(sceneDepth, vec3(oUV * pc.extra.xy, float(gl_ViewIndex))).r;
    outMotion = vec4(0.0);
}
