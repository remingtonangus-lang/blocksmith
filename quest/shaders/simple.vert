#version 450
#include "common.glsl"
// Coloured triangles, camera-relative (outlines, rays, the comfort vignette, the test scene, the far landmarks).
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 oColor;
void main() {
    vec3 p = pos.xyz;
    // The far landmarks and the horizon ground (LandmarkRender.swift, Renderer.shellOnGPU), in world terms so a build
    // holds while the eye moves: w = 3 + the shell's radius, each point put on the impostor shell along its own direction
    // from the eye, the radius growing a little with the true distance (2600: Renderer.landmarkRange); w = -1, a point at
    // its true place (the near citadels and town boxes).
    if (pos.w > 2.5) {
        vec3 d = p - u.eye.xyz;
        float len = max(0.001, length(d));
        float r = (pos.w - 3.0) * (0.95 + 0.05 * min(1.0, len / 2600.0));
        p = d * (r / len);
    } else if (pos.w < -0.5) {
        p -= u.eye.xyz;
    }
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(p, 1.0);
    if (pos.w > 1.5 && pos.w < 2.5) { gl_Position = vec4(pos.xy, 0.0, 1.0); }   // w = 2: already in clip space (screen overlays)
    oColor = color;
}
