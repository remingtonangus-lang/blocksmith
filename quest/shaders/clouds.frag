#version 450
#include "common.glsl"
layout(location = 0) in vec2 oNdc;
layout(location = 0) out vec4 outColor;
// Two cloud decks over the overworld sky (L1 look upgrade, docs/status/look-upgrade.md): soft cumulus and high cirrus,
// both ray-cast onto flat planes above the eye (no geometry), driven by one wind (u.clouds.xy = the eye in cloud space,
// u.wind.xy = its direction; Sources/SkyLook.swift). Lit by the sun (gold at its rise and set, white at noon) or the
// moon, self-shadowed by one tap toward the sun, thicker and darker as the cover rises with rain, and lit from inside
// by storm flashes. Drawn after the dome, stars, sun and moon (blended, depth 1: only over open sky, so it hides them).
// Cost: 7 value-noise taps per sky pixel (5 cumulus, 2 cirrus); none below the horizon.
const float CUMULUS_Y = 340.0;   // internal world y (displayed y 276), above every peak
const float CIRRUS_Y = 900.0;
void main() {
    vec4 w = u.invViewProj[gl_ViewIndex] * vec4(oNdc, 1.0, 1.0);
    vec3 d = normalize(w.xyz / w.w);
    float hu = CUMULUS_Y - u.eye.y;
    if (d.y <= 0.004 || hu <= 0.0) { discard; }
    float cover = u.clouds.z;
    float storm = u.cloudFlash.w;
    vec3 sd = normalize(u.sunDir.xyz);
    float g = smoothstep(0.04, 0.4, sd.y);
    float sunUp = smoothstep(-0.1, 0.06, sd.y);
    vec3 sunC = mix(vec3(1.0, 0.5, 0.32), vec3(1.0, 0.97, 0.93), g);
    vec3 lightC = mix(vec3(0.13, 0.15, 0.21), sunC, sunUp) * (1.0 - 0.55 * storm);
    vec3 ambC = mix(u.horizon.rgb, u.zenith.rgb, 0.35);
    float fl = u.clouds.w * pow(clamp(dot(d, u.cloudFlash.xyz) * 0.5 + 0.5, 0.0, 1.0), 12.0);
    vec3 flashC = vec3(0.78, 0.82, 1.0) * fl;
    float sv = pow(clamp(dot(d, sd), 0.0, 1.0), 10.0) * sunUp;

    // Cumulus: four octaves of value noise (~150-block cells), cut at a threshold set by the cover; the fine octaves
    // only erode the edges, so a cloud keeps a soft body with a crisper, billowed rim.
    float t = hu / d.y;
    vec2 p = (u.clouds.xy + d.xz * t) * (1.0 / 150.0);
    float far = 1.0 - exp(-t / 5200.0);                        // aerial haze toward the horizon
    // Toward the horizon a pixel spans many blocks: the fine octaves fade to their mean and the rim softens there, so
    // the distant deck doesn't alias into stripes.
    float fine = 1.0 - smoothstep(0.2, 0.7, far);
    float n0 = vnoise(p);
    float n = n0 * 0.52 + vnoise(p * 2.13 + 3.7) * 0.28 + (vnoise(p * 4.71 + 9.2) * 0.13 + vnoise(p * 9.9 + 1.3) * 0.07) * fine
            + 0.1 * (1.0 - fine);
    float thr = mix(0.64, 0.2, cover);
    float dens = smoothstep(thr, thr + 0.1 + 0.2 * (1.0 - fine), n);
    float thick = smoothstep(thr + 0.05, thr + 0.42, n);
    // Self-shadow: denser toward the sun means the near side is in shade; sunlit edges and tops brighten.
    float ns = vnoise(p + normalize(sd.xz + vec2(1e-4)) * 0.3);
    float lit = clamp(0.58 + (n0 - ns) * 2.4 - thick * 0.35, 0.0, 1.0);
    vec3 cc = mix(ambC * 0.78, lightC * 1.08 + ambC * 0.18, lit);
    cc *= 1.0 - 0.4 * thick * (0.35 + storm);
    cc += sunC * sv * (1.0 - thick) * 0.8;                    // silver lining round clouds near the sun
    cc += flashC * (0.25 + 0.75 * thick);
    cc = mix(cc, u.horizon.rgb, far * 0.8);
    float ac = dens * (1.0 - smoothstep(0.62, 0.93, far)) * (0.82 + 0.18 * thick);

    // Cirrus: streaks stretched along the wind, moving at 0.6 of the cumulus drift; thinned under an overcast deck.
    float t2 = (CIRRUS_Y - u.eye.y) / d.y;
    vec2 q = u.clouds.xy * 0.6 + d.xz * t2;
    vec2 wd = u.wind.xy;
    vec2 r = vec2(dot(q, wd), dot(q, vec2(-wd.y, wd.x)));
    float m = vnoise(r * vec2(1.0 / 700.0, 1.0 / 260.0)) * 0.6 + vnoise(r * vec2(1.0 / 240.0, 1.0 / 70.0) + 5.3) * 0.4;
    float far2 = 1.0 - exp(-t2 / 16000.0);
    float ai = smoothstep(0.58, 0.9, m) * 0.32 * (1.0 - 0.8 * cover) * (1.0 - smoothstep(0.5, 0.85, far2));
    vec3 ci = mix(ambC, lightC * 1.15 + ambC * 0.15, 0.75) + sunC * sv * 0.5 + flashC * 0.3;
    ci = mix(ci, u.horizon.rgb, far2 * 0.7);

    // Cumulus over cirrus.
    float a = ac + ai * (1.0 - ac);
    if (a < 0.003) { discard; }
    vec3 col = (cc * ac + ci * ai * (1.0 - ac)) / a;
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    col += (ign - 0.5) / 255.0;
    outColor = worldColor(vec4(col, a));
}
