#version 450
#include "common.glsl"
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 color;
layout(location = 2) in vec4 local;
layout(location = 0) out vec3 oColor;
layout(location = 1) out float oShade;
layout(location = 2) out vec3 oLocal;
layout(location = 3) flat out float oPattern;
layout(location = 4) out float oDist;
layout(location = 5) out vec3 oRel;
void main() {
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(pos.xyz, 1.0);
    oColor = color.rgb;
    oShade = color.a;
    oLocal = local.xyz;
    oPattern = pos.w;
    oDist = length(pos.xyz);
    oRel = pos.xyz;
}
