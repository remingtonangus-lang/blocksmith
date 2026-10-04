#version 450
#include "common.glsl"
layout(location = 0) out vec2 oNdc;
void main() {
    vec2 p = vec2(gl_VertexIndex == 1 ? 3.0 : -1.0, gl_VertexIndex == 2 ? 3.0 : -1.0);
    gl_Position = vec4(p, 1.0, 1.0);    // depth 1: drawn after the terrain, only where nothing else is
    oNdc = p;
}
