#version 450
#include "common.glsl"
// Port of the Mac mobFS (Sources/Shaders.swift): pattern detail in model space, emissive parts unshaded, and a sun
// specular + rim on the glossy patterns (7 enamel, 8 metal, 10 leather, 11 smoked glass).
layout(location = 0) in vec3 oColor;
layout(location = 1) in float oShade;
layout(location = 2) in vec3 oLocal;
layout(location = 3) flat in float oPattern;
layout(location = 4) in float oDist;
layout(location = 5) in vec3 oRel;
layout(location = 0) out vec4 outColor;
float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
vec3 mobPattern() {
    vec3 p = oLocal;
    vec3 cell = floor(p + 0.001);
    float h = hash31(cell);
    float hf = hash31(floor(p * 4.0 + 0.001));
    vec3 c = oColor;
    if (oPattern > 0.5 && oPattern < 1.5) {
        float n = vnoise(p.xz * 0.28 + p.y * 0.21 + 3.0) * 0.7 + vnoise(p.zy * 0.33 + 7.0) * 0.3;
        c = mix(c, vec3(0.92, 0.9, 0.86), smoothstep(0.565, 0.595, n));
        c *= 0.94 + 0.06 * h + 0.06 * (hf - 0.5);
    } else if (oPattern > 1.5 && oPattern < 2.5) {
        c *= 0.84 + 0.1 * h + 0.12 * hf;
    } else if (oPattern > 2.5 && oPattern < 3.5) {
        float row = fract(p.y * 0.5 + 0.25 * hash31(vec3(cell.x, 0.0, cell.z)));
        c *= 0.86 + 0.1 * smoothstep(0.0, 0.6, row) + 0.05 * hf;
    } else if (oPattern > 3.5 && oPattern < 4.5) {
        float n = vnoise(p.xz * 0.5 + p.y * 0.37) * 0.6 + vnoise(p.zy * 1.3 + 5.0) * 0.4;
        c *= 0.74 + 0.3 * n + 0.06 * hf;
    } else if (oPattern > 4.5 && oPattern < 5.5) {
        c *= 0.9 + 0.06 * h + 0.05 * hf;
    } else if (oPattern > 5.5 && oPattern < 6.5) {
        float tw = sin((p.x + p.y + p.z) * 12.566);
        float fold = vnoise(p.xy * 0.33 + p.z * 0.21 + 11.0) * 0.6 + vnoise(p.zy * 0.4 + 3.0) * 0.4;
        c *= 0.955 + 0.025 * tw + 0.07 * (fold - 0.5) + 0.02 * (hf - 0.5);
    } else if (oPattern > 6.5 && oPattern < 7.5) {
        c *= 0.985 + 0.02 * (hf - 0.5);
    } else if (oPattern > 7.5 && oPattern < 8.5) {
        c *= 0.9 + 0.08 * hf + 0.04 * sin(p.y * 9.0 + p.x * 3.0);
    } else if (oPattern > 9.5 && oPattern < 10.5) {
        c *= 0.93 + 0.05 * hf;
    } else if (oPattern > 8.5) {
        // emissive (9) and smoked glass (11): flat
    } else {
        c *= 0.95 + 0.04 * h + 0.04 * (hf - 0.5);
    }
    return c;
}
vec3 mobSheen(vec3 n, vec3 rel, int pt, vec3 toLight, vec3 lightC) {
    vec3 v = normalize(rel);
    if (dot(n, v) > 0.0) n = -n;
    vec3 l = normalize(toLight);
    vec3 hv = normalize(l - v);
    float shin = pt == 8 ? 40.0 : (pt == 11 ? 90.0 : (pt == 10 ? 24.0 : 32.0));
    float k = pt == 8 ? 0.5 : (pt == 11 ? 0.55 : (pt == 10 ? 0.22 : 0.28));
    float s = pow(clamp(dot(n, hv), 0.0, 1.0), shin) * k * clamp(dot(n, l) * 4.0, 0.0, 1.0);
    float rim = pow(1.0 - clamp(dot(n, -v), 0.0, 1.0), 4.0) * (pt == 11 ? 0.12 : 0.06);
    return lightC * (s + rim);
}
void main() {
    vec3 c = mobPattern();
    int pt = int(oPattern + 0.5);
    if (pt == 9) { outColor = finalColor(vec4(applyFog(c, oDist), 1.0)); return; }
    vec3 col = c * oShade;
    if (pt == 7 || pt == 8 || pt == 10 || pt == 11) {
        vec3 n = normalize(cross(dFdx(oRel), dFdy(oRel)));
        col += mobSheen(n, oRel, pt, u.sunDir.xyz, vec3(u.params.y)) * clamp(oShade * 1.3, 0.0, 1.0);
    }
    outColor = finalColor(vec4(applyFog(col, oDist), 1.0));
}
