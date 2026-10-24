#version 450
#include "common.glsl"
// P403 7b: a moving thing's motion vector, this frame's NDC position minus the last drawn frame's (XR_FB_space_warp).
layout(location = 0) in vec4 oCur;
layout(location = 1) in vec4 oPrev;
layout(location = 0) out vec4 outMotion;
void main() {
    outMotion = vec4(oCur.xyz / oCur.w - oPrev.xyz / oPrev.w, 0.0);
}
