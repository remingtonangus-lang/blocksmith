#version 450
#include "common.glsl"
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 oColor;
layout(location = 1) out vec2 oUV;
void main() {
    vec4 p = u.viewProj[gl_ViewIndex] * (u.starRot * vec4(pos.xyz, 1.0));
    gl_Position = p.xyww;                   // at the far plane: only over open sky
    oColor = color * u.starTint;
    float star = float(gl_VertexIndex / 6);
    float ph = fract(sin(star * 12.9898) * 43758.5453);
    oColor.rgb *= 0.78 + 0.22 * sin(u.params.z * (1.5 + 2.5 * ph) + ph * 40.0);
    const uint corner[6] = uint[](0u, 1u, 2u, 0u, 2u, 3u);
    uint c = corner[gl_VertexIndex % 6];
    oUV = vec2(c == 1u || c == 2u ? 1.0 : 0.0, c >= 2u ? 1.0 : 0.0);
}
