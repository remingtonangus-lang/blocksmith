#version 450
#include "common.glsl"
layout(location = 0) in vec4 oColor;
layout(location = 1) in vec2 oUV;
layout(location = 0) out vec4 outColor;
void main() {
    float r = length(oUV * 2.0 - 1.0);
    float a = 1.0 - smoothstep(0.35, 1.0, r);
    outColor = finalColor(vec4(oColor.rgb * 1.5, oColor.a * a));
}
