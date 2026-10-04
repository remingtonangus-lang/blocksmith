#version 450
#include "common.glsl"
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 uv;
layout(location = 2) in vec4 color;
layout(location = 0) out vec2 oUV;
layout(location = 1) flat out float oLayer;
layout(location = 2) out vec4 oColor;
layout(location = 3) out float oDist;
layout(location = 4) flat out float oOverlay;
void main() {
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(pos.xyz, 1.0);
    oUV = uv.xy;
    oLayer = pos.w;
    oColor = color;
    oDist = length(pos.xyz);
    oOverlay = uv.z;
}
