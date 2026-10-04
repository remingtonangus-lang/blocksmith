#version 450
#include "common.glsl"
layout(location = 0) in vec2 oNdc;
layout(location = 0) out vec4 outColor;
// The Mac's Fancy sky dome (zenith/horizon gradient, sun glow, anti-twilight arch, night band) as the Quest's sky.
void main() {
    // The viewport is flipped (negative height), so NDC y matches the Mac's.
    vec4 w = u.invViewProj[gl_ViewIndex] * vec4(oNdc, 1.0, 1.0);
    vec3 d = normalize(w.xyz / w.w);
    if (u.misc.x > 1.5) {
        // The Hollow: fog colour with faint drifting violet streaks.
        vec3 a = abs(d);
        vec2 q = a.y > max(a.x, a.z) ? d.xz / a.y : (a.x > a.z ? d.zy / a.x : d.xy / a.z);
        float t = u.params.z;
        float n = vnoise(q * 3.0 + vec2(t * 0.01, 0.0)) * 0.6 + vnoise(q * 9.0 - vec2(0.0, t * 0.015)) * 0.4;
        float streak = smoothstep(0.55, 0.85, vnoise(vec2(q.x * 1.5, q.y * 7.0) + 11.0));
        outColor = vec4(u.horizon.rgb * (0.85 + 0.3 * n) + vec3(0.035, 0.015, 0.05) * streak, 1.0);
        return;
    }
    if (u.misc.x < 0.5) { outColor = vec4(u.horizon.rgb, 1.0); return; }
    float h = clamp(d.y * 1.25, 0.0, 1.0);
    h = h * h * (3.0 - 2.0 * h);
    vec3 col = mix(u.horizon.rgb, u.zenith.rgb, h);
    if (d.y < 0.0) { col = u.horizon.rgb; }
    float sd = clamp(dot(d, u.sunDir.xyz), 0.0, 1.0);
    float band = 1.0 - clamp(abs(d.y) * 3.0, 0.0, 1.0);
    col += vec3(1.0, 0.55, 0.25) * pow(sd, 5.0) * u.horizon.w * (0.35 + 0.65 * band);
    col += vec3(1.0, 0.95, 0.85) * pow(sd, 24.0) * 0.18 * u.params.y;
    float anti = clamp(-dot(normalize(vec3(d.x, 0.0, d.z) + 1e-4), normalize(vec3(u.sunDir.x, 0.0, u.sunDir.z) + 1e-4)), 0.0, 1.0);
    float arch = exp(-pow((d.y - 0.1) / 0.09, 2.0));
    col += vec3(0.55, 0.32, 0.42) * arch * anti * anti * clamp(u.horizon.w - 0.15, 0.0, 1.0) * 0.55;
    float night = clamp((0.45 - u.params.y) / 0.35, 0.0, 1.0);
    if (night > 0.0 && d.y > -0.05) {
        float a = u.zenith.w;
        vec3 bn = normalize(vec3(0.3 * cos(a) - 0.2 * sin(a), 0.3 * sin(a) + 0.2 * cos(a), 0.93));
        float bnd = exp(-pow(dot(d, bn) * 4.5, 2.0));
        vec3 q = d * 6.0;
        float cl = vnoise(q.xy + q.z * 0.7) * 0.6 + vnoise(q.yz * 2.3 + 5.0) * 0.4;
        col += vec3(0.32, 0.3, 0.42) * bnd * smoothstep(0.3, 0.8, cl) * night * 0.22 * clamp(d.y * 4.0 + 0.2, 0.0, 1.0);
    }
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    col += (ign - 0.5) / 255.0;
    outColor = vec4(col, 1.0);
}
