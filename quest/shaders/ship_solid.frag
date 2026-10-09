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
    vec4 c = texture(tex, vec3(oUV, oLayer));
    vec3 t = (oOverlay > 0.5 && c.a > 0.95) ? vec3(1.0) : oTint;
    outColor = worldColor(vec4(mix(c.rgb * t * oShade, u.fogColor.rgb, shipFogF(oDist)), 1.0));
}
