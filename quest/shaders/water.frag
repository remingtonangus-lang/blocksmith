#version 450
#include "common.glsl"
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec3 oShade;
layout(location = 3) in vec3 oTint;
layout(location = 4) flat in float oOverlay;
layout(location = 5) flat in float oAnim;
layout(location = 6) in float oDist;
layout(location = 7) in vec3 oRel;
layout(location = 8) flat in float oFace;
layout(location = 9) in float oWDepth;     // water: metres of water under the surface (Mesher.waterDepthAO); -1 other blocks
layout(location = 0) out vec4 outColor;

// Port of the Mac's Fancy water (Sources/VibrantShaders.swift waterVibFS) without its scene and depth copies: Schlick
// Fresnel between the mirrored sky and the water body, ripple + ocean swell normals, an HDR-ish sun glint, depth
// absorption from the mesher's per-corner water depth (the bed shows through the shallows, deep water goes dark navy),
// broken shoreline foam, rain rings, tumbling side faces, and the surface seen from below (refracted sky, total
// internal reflection). Alpha blending carries it: out = premultiplied colour / A, A = 1 - (1 - fresnel) x transmittance.

// The sky along a direction (sky.frag's dome without the night band): what the surface mirrors.
vec3 skyAlong(vec3 d) {
    if (u.misc.x > 1.5) { return u.horizon.rgb; }
    float h = clamp(d.y * 1.25, 0.0, 1.0);
    h = h * h * (3.0 - 2.0 * h);
    vec3 col = mix(u.horizon.rgb, u.zenith.rgb, h);
    float sd = clamp(dot(d, u.sunDir.xyz), 0.0, 1.0);
    float band = 1.0 - clamp(abs(d.y) * 3.0, 0.0, 1.0);
    col += vec3(1.0, 0.55, 0.25) * pow(sd, 5.0) * u.horizon.w * (0.35 + 0.65 * band);
    col += vec3(1.0, 0.95, 0.85) * pow(sd, 24.0) * 0.18 * u.params.y;
    return col;
}

void main() {
    float t = u.params.z;
    vec2 uv = oUV + vec2(t * 0.03, t * 0.017);
    vec4 c = texture(tex, vec3(uv, oLayer));
    vec3 rgb = c.rgb * oTint * max(oShade, vec3(0.05));
    float f = smoothstep(u.fogColor.w, u.params.x, oDist);
    if (oWDepth < 0.0) {
        // Glass, ice and other translucent blocks: as before.
        outColor = finalColor(vec4(mix(rgb, fogColorAlong(oRel), f), mix(c.a, 1.0, f * 0.8)));
        return;
    }
    vec3 v = normalize(oRel);
    vec3 wp = oRel + u.eye.xyz;
    bool top = oFace > 1.5 && oFace < 2.5;
    float lit = max(oShade.x, max(oShade.y, oShade.z));
    float skyVis = clamp(lit / max(0.3, u.params.y), 0.0, 1.0);          // under a roof or in a cave: little sky to mirror
    float sunVis = smoothstep(-0.04, 0.12, u.sunDir.y) * skyVis;
    vec3 sunC = mix(vec3(1.0, 0.62, 0.32), vec3(1.0, 0.95, 0.85), smoothstep(0.05, 0.35, u.sunDir.y));
    float texL = dot(c.rgb, vec3(0.33));

    vec3 n = normalize(vec3(-v.x, 0.0, -v.z) + vec3(0.0, 1e-3, 0.0));
    if (top) {
        vec2 w1 = wp.xz * 0.8 + vec2(t * 0.55, t * 0.3);
        vec2 w2 = wp.xz * 2.1 - vec2(t * 0.35, -t * 0.6);
        vec2 g = vec2(cos(w1.x + w1.y * 0.6), sin(w1.y - w1.x * 0.45)) * 0.045
               + (vec2(vnoise(w2), vnoise(w2 + 7.3)) - 0.5) * 0.11;
        g *= 0.85 + 0.1 * u.waves.x;                                       // choppier as the sea gets up
        // Ripples a pixel can't resolve alias into contour bands on far water: fade them.
        g *= 1.0 - 0.8 * smoothstep(24.0, 96.0, oDist);
        if (u.waves.y > 0.05 && oDist < 32.0) {
            // Rain: expanding drop rings, one per half-block cell at random times.
            vec2 cell = floor(wp.xz * 2.0);
            float hh = fract(sin(dot(cell, vec2(41.3, 289.1))) * 43758.5);
            float ph = fract(t * 1.4 + hh * 7.0);
            vec2 ctr = (cell + 0.25 + 0.5 * vec2(hh, fract(hh * 13.7))) * 0.5;
            vec2 dv = wp.xz - ctr;
            float dd = length(dv);
            float ring = sin((dd - ph * 0.22) * 90.0) * (1.0 - ph) * (1.0 - smoothstep(0.0, 0.25, abs(dd - ph * 0.22) * 6.0));
            g += dv / max(dd, 1e-3) * ring * 0.12 * u.waves.y;
        }
        if (wp.y > 124.5 && wp.y < 127.5) { g -= oceanWave(wp.xz, t).yz * 1.5; }
        n = normalize(vec3(g.x, 1.0, g.y));
    }

    if (u.params.w > 0.5) {
        // Under water. Looking up at the surface: the bright world above, refracted; beyond the critical angle the
        // surface mirrors the lit water below (total internal reflection).
        if (top) {
            vec3 rd = refract(v, -n, 1.33);
            vec3 tir = u.fogColor.rgb * 1.15;
            vec3 col = dot(rd, rd) < 1e-4 ? tir : mix(skyAlong(rd) * 0.85 * mix(0.3, 1.0, skyVis), tir, 0.3);
            col += sunC * pow(clamp(dot(rd, u.sunDir.xyz), 0.0, 1.0), 220.0) * 2.0 * sunVis;
            outColor = finalColor(vec4(mix(col, u.fogColor.rgb, f), 0.94));
        } else {
            outColor = finalColor(vec4(mix(rgb, u.fogColor.rgb, f), mix(c.a, 1.0, f * 0.8)));
        }
        return;
    }

    float cosT = clamp(dot(-v, n), 0.0, 1.0);
    float fres = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
    vec3 r = reflect(v, n);
    r.y = abs(r.y);                                                        // ripples can tip it under the horizon
    vec3 refl = skyAlong(r) * mix(0.25, 1.0, skyVis);
    // The water's own colour (tint, lit like the surface): what fills the view where the bed can't be seen.
    vec3 deep = oTint * (lit * 0.34 + 0.015) * (0.85 + 0.3 * texL);
    vec3 pm;        // premultiplied colour
    float A;        // coverage: how much of the bed behind is replaced
    if (top) {
        // Light crossing `path` metres of water reaches the eye with `absorb` left (red goes first).
        float path = oWDepth / max(0.12, abs(v.y));
        vec3 absorb = exp(-path * vec3(0.42, 0.15, 0.09));
        float T = dot(absorb, vec3(0.3, 0.5, 0.2));
        fres = min(1.0, fres * 1.1);
        A = 1.0 - (1.0 - fres) * T;
        pm = refl * fres + deep * (1.0 - fres) * (1.0 - T);
        // Shoreline foam: where the water thins out over the bed, a broken white band drifting with the waves.
        float shore = 1.0 - smoothstep(0.0, 0.8, oWDepth);
        float fn = vnoise(wp.xz * 2.6 + vec2(t * 0.4, -t * 0.3)) * 0.6 + vnoise(wp.xz * 6.0 - t * 0.5) * 0.4;
        float foam = shore * shore * smoothstep(0.5, 0.85, fn + shore * 0.15) * 0.5;
        vec3 foamC = vec3(0.92, 0.95, 0.97) * (lit * 0.85 + 0.05);
        pm = mix(pm, foamC, foam);
        A = mix(A, 1.0, foam);
        // Sun glint: a tight HDR core and a soft sheen.
        vec3 hv = normalize(u.sunDir.xyz - v);
        float nh = clamp(dot(n, hv), 0.0, 1.0);
        vec3 sp = sunC * (pow(nh, 500.0) * 4.0 + pow(nh, 70.0) * 0.18) * sunVis * (1.0 - foam);
        pm += sp;
        A = max(A, min(1.0, max(sp.r, max(sp.g, sp.b))));
    } else {
        // Side faces (water spilling down a step, falls): tumbling water with white streaks, a weak reflection.
        float across = abs(v.x) > abs(v.z) ? wp.z : wp.x;
        float fall = vnoise(vec2(across * 5.0, wp.y * 1.6 + t * 3.2)) * 0.65 + vnoise(vec2(across * 11.0, wp.y * 3.0 + t * 4.5)) * 0.35;
        vec3 body = oTint * (lit * 0.6 + 0.02);
        vec3 col = mix(body, refl, fres * 0.3);
        col = mix(col, vec3(0.9) * (lit * 0.9 + 0.05), smoothstep(0.55, 0.9, fall) * 0.45);
        A = 0.82;
        pm = col * A;
    }
    A = mix(A, 1.0, f);
    pm = mix(pm, fogColorAlong(oRel), f);
    outColor = finalColor(vec4(pm / max(A, 1e-3), A));
}
