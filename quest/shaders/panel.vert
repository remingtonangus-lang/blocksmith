#version 450
#include "common.glsl"
// World-space panels (HUD, menus): a textured quad from the panel image; the model matrix comes as a push constant.
layout(push_constant) uniform Push { mat4 model; vec4 extra; } pc;
layout(location = 0) out vec2 oUV;
void main() {
    const vec2 c[6] = vec2[](vec2(0, 0), vec2(1, 0), vec2(1, 1), vec2(0, 0), vec2(1, 1), vec2(0, 1));
    vec2 q = c[gl_VertexIndex];
    gl_Position = u.viewProj[gl_ViewIndex] * (pc.model * vec4(q.x - 0.5, 0.5 - q.y, 0.0, 1.0));
    oUV = q;
}
