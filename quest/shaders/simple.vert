#version 450
#include "common.glsl"
// Coloured triangles, camera-relative (outlines, rays, the comfort vignette, the test scene).
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 oColor;
void main() {
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(pos.xyz, 1.0);
    if (pos.w > 1.5) { gl_Position = vec4(pos.xy, 0.0, 1.0); }   // w = 2: already in clip space (screen overlays)
    oColor = color;
}
