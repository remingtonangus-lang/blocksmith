#version 450
#include "common.glsl"
layout(push_constant) uniform Push { mat4 model; vec4 origin; vec4 fog; } pc;
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec3 oShade;
layout(location = 3) in vec3 oTint;
layout(location = 4) flat in float oOverlay;
layout(location = 5) in float oDist;
layout(location = 0) out vec4 outColor;
float shipFogF(float d) {
    float s = pc.fog.y > 0.0 ? pc.fog.x : u.fogColor.w, e = pc.fog.y > 0.0 ? pc.fog.y : u.params.x;
    return smoothstep(s, e, d);
}
void main() {
    vec4 c = texSharp(oUV, oLayer);
    vec3 rgb = c.rgb * oTint * max(oShade, vec3(0.05));
    float f = shipFogF(oDist);
    outColor = worldColor(vec4(mix(rgb, u.fogColor.rgb, f), mix(c.a, 1.0, f * 0.8)));
}
