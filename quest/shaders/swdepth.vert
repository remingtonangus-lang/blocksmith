#version 450
#include "common.glsl"
// P381 step 9 (Application SpaceWarp): one triangle over the motion-vector image; uv 0,0 at its top-left, as the
// scene's depth image is stored.
layout(location = 0) out vec2 oUV;
void main() {
    vec2 p = vec2(gl_VertexIndex == 1 ? 3.0 : -1.0, gl_VertexIndex == 2 ? 3.0 : -1.0);
    gl_Position = vec4(p, 0.0, 1.0);
    oUV = p * 0.5 + 0.5;
}
