#version 450
#include "common.glsl"
layout(location = 0) in vec4 oColor;
layout(location = 0) out vec4 outColor;
void main() { outColor = finalColor(oColor); }
