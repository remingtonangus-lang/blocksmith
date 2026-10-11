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
const float CUMULUS_Y = 340.0;   // internal world y (displayed y 276), above every peak; nothing draws from above it
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
    // u.wind.w: the cave dimming the dome already has (WorldRenderer.caveScale): from a dark cave the clouds up a shaft
    // dim with the sky instead of staying full white.
    float cave = u.wind.w;
    vec3 sunC = mix(vec3(1.0, 0.5, 0.32), vec3(1.0, 0.97, 0.93), g) * cave;
    vec3 lightC = mix(vec3(0.13, 0.15, 0.21) * cave, sunC, sunUp) * (1.0 - 0.55 * storm);
    vec3 ambC = mix(mix(u.horizon.rgb, u.zenith.rgb, 0.35), u.horizon.rgb, u.wind.z * 0.4);   // desert haze yellows them
    float fl = u.clouds.w * pow(clamp(dot(d, u.cloudFlash.xyz) * 0.5 + 0.5, 0.0, 1.0), 12.0);
    vec3 flashC = vec3(0.78, 0.82, 1.0) * fl * cave;
    float sv = pow(clamp(dot(d, sd), 0.0, 1.0), 10.0) * sunUp;

    // Cumulus: four octaves of value noise (~150-block cells), cut at a threshold set by the cover; the fine octaves
    // only erode the edges, so a cloud keeps a soft body with a crisper, billowed rim.
    float t = hu / d.y;
    vec2 p = (u.clouds.xy + d.xz * t) * (1.0 / 150.0);
    float far = 1.0 - exp(-t / 5200.0);                        // aerial haze toward the horizon
    // Footprint filtering: toward the horizon one pixel spans many cloud cells, so each octave fades to its mean (0.5)
    // once its cells shrink below ~2 pixels, the base octave included, and the rim widens by the footprint: no
    // zebra stripes or shimmer in the distant deck. Octaves are rotated against each other (no grid-aligned smears).
    float fp = length(fwidth(p));
    const mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    vec2 p1 = rot * p * 2.13 + 3.7, p2 = rot * p1 * 2.21 + 5.1, p3 = rot * p2 * 2.1 + 1.3;
    float w0 = 1.0 - smoothstep(0.3, 0.6, fp), w1 = 1.0 - smoothstep(0.3, 0.6, fp * 2.13);
    float w2 = 1.0 - smoothstep(0.3, 0.6, fp * 4.71), w3 = 1.0 - smoothstep(0.3, 0.6, fp * 9.9);
    float n0 = mix(0.5, vnoise(p), w0);
    float n = n0 * 0.52 + mix(0.5, vnoise(p1), w1) * 0.28 + mix(0.5, vnoise(p2), w2) * 0.13 + mix(0.5, vnoise(p3), w3) * 0.07;
    float thr = mix(0.64, 0.2, cover);
    float dens = smoothstep(thr, thr + 0.1 + min(0.3, fp * 0.5), n);
    float thick = smoothstep(thr + 0.05, thr + 0.42, n);
    // Self-shadow: denser toward the sun means the near side is in shade; sunlit edges and tops brighten.
    float ns = mix(0.5, vnoise(p + normalize(sd.xz + vec2(1e-4)) * 0.3), w0);
    float lit = clamp(0.58 + (n0 - ns) * 2.4 - thick * 0.35, 0.0, 1.0);
    vec3 cc = mix(ambC * 0.78, lightC * 1.08 + ambC * 0.18, lit);
    cc *= 1.0 - 0.4 * thick * (0.35 + storm);
    cc += sunC * sv * (1.0 - thick) * (0.8 + 0.8 * (1.0 - g));    // silver lining round clouds near the sun
    cc += flashC * (0.25 + 0.75 * thick);
    cc = mix(cc, u.horizon.rgb, smoothstep(0.0, 0.85, far));       // reaches the horizon colour before it fades out
    float ac = dens * (1.0 - smoothstep(0.5, 0.95, far)) * smoothstep(0.015, 0.1, d.y) * (0.9 + 0.1 * thick);

    // Cirrus: streaks stretched along the wind, moving at 0.6 of the cumulus drift; thinned under an overcast deck.
    float t2 = (CIRRUS_Y - u.eye.y) / d.y;
    vec2 q = u.clouds.xy * 0.6 + d.xz * t2;
    vec2 wd = u.wind.xy;
    vec2 r = vec2(dot(q, wd), dot(q, vec2(-wd.y, wd.x)));
    vec2 r0 = r * vec2(1.0 / 700.0, 1.0 / 260.0), r1 = r * vec2(1.0 / 240.0, 1.0 / 70.0) + 5.3;
    float fq = length(fwidth(r1));
    float m = vnoise(r0) * 0.6 + mix(0.5, vnoise(r1), 1.0 - smoothstep(0.3, 0.6, fq)) * 0.4;
    float far2 = 1.0 - exp(-t2 / 16000.0);
    float ai = smoothstep(0.58, 0.9, m) * 0.32 * (1.0 - 0.8 * cover) * (1.0 - smoothstep(0.5, 0.85, far2)) * smoothstep(0.015, 0.1, d.y);
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
