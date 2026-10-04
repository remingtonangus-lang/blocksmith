#version 450
#include "common.glsl"
layout(location = 0) in vec3 oColor;
layout(location = 1) in float oShade;
layout(location = 2) in vec3 oLocal;
layout(location = 3) flat in float oPattern;
layout(location = 4) in float oDist;
layout(location = 0) out vec4 outColor;
float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
void main() {
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
    } else if (oPattern > 4.5) {
        c *= 0.9 + 0.06 * h + 0.05 * hf;
    } else {
        c *= 0.95 + 0.04 * h + 0.04 * (hf - 0.5);
    }
    outColor = finalColor(vec4(applyFog(c * oShade, oDist), 1.0));
}
