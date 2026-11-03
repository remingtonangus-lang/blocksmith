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
// rain rings, tumbling side faces, and the surface seen from below (refracted sky, total
// internal reflection). Alpha blending carries it: out = premultiplied colour / A, A = 1 - (1 - fresnel) x transmittance.

// The sky along a direction, as the Mac's Fancy water mirrors it (VibrantShaders skyAlong): the hazy fog colour at the
// horizon (so far water fades pale into the haze, not a dark band) up to a deeper blue overhead, plus the sun's disc.
// (It used the sky dome's horizon/zenith colours: the reflection read darker and more saturated than the Mac's.)
vec3 skyAlong(vec3 d) {
    if (u.misc.x > 1.5) { return u.horizon.rgb; }
    float h = clamp(d.y * 1.25, 0.0, 1.0);
    h = h * h * (3.0 - 2.0 * h);
    vec3 col = mix(fogColorAlong(d), u.fogColor.rgb * vec3(0.45, 0.6, 0.92), h);
    float sd = clamp(dot(d, u.sunDir.xyz), 0.0, 1.0);
    col += vec3(1.0, 0.95, 0.85) * pow(sd, 600.0) * 6.0 * u.params.y;
    return col;
}

void main() {
    float t = u.params.z;
    vec2 uv = oUV + vec2(t * 0.03, t * 0.017);
    vec4 c = texSharp(uv, oLayer);
    vec3 rgb = c.rgb * oTint * max(oShade, vec3(0.05));
    float f = smoothstep(u.fogColor.w, u.params.x, oDist);
    if (oWDepth < 0.0) {
        if (oOverlay > 0.5 && oFace > 1.5 && oFace < 2.5) {
            // P239 (Oct 13 21:52, "ice should be like a mirror"): the top of ice (Mesher marks it with the overlay bit)
            // mirrors the sky like polished glass: a strong Fresnel reflection over the ice's own colour, a faint
            // frosted wobble so it isn't a perfect plane, and a sharp sun glint.
            vec3 v = normalize(oRel);
            vec3 wp = oRel + u.eye.xyz;
            vec2 fr = (vec2(vnoise(wp.xz * 1.7), vnoise(wp.xz * 1.7 + 5.1)) - 0.5) * 0.035 * (1.0 - smoothstep(16.0, 64.0, oDist));
            vec3 n = normalize(vec3(fr.x, 1.0, fr.y));
            float lit = max(oShade.x, max(oShade.y, oShade.z));
            float skyVis = clamp(lit / max(0.3, u.params.y), 0.0, 1.0);
            float cosT = clamp(dot(-v, n), 0.0, 1.0);
            float fres = 0.06 + 0.94 * pow(1.0 - cosT, 5.0);
            vec3 r = reflect(v, n); r.y = abs(r.y);
            vec3 refl = skyAlong(r) * mix(0.2, 1.0, skyVis);
            // P275 (a): a glassy mirror, not a white sheet: the reflection is strong only at grazing angles, so looking
            // down you see through the blue-tinted ice to the water and blocks below.
            float k = clamp(0.08 + 0.72 * fres, 0.0, 1.0) * mix(0.35, 1.0, skyVis);
            vec3 col = mix(rgb, refl, k);
            float sunVis = smoothstep(-0.04, 0.12, u.sunDir.y) * skyVis;
            vec3 hv = normalize(u.sunDir.xyz - v);
            float nh = clamp(dot(n, hv), 0.0, 1.0);
            col += vec3(1.0, 0.95, 0.85) * (pow(nh, 900.0) * 6.0 + pow(nh, 90.0) * 0.12) * sunVis;
            float a = max(c.a, k * 0.85);
            outColor = worldColor(vec4(mix(col, fogColorAlong(oRel), f), mix(a, 1.0, f * 0.8)));
            return;
        }
        // Glass and other translucent blocks: as before.
        outColor = worldColor(vec4(mix(rgb, fogColorAlong(oRel), f), mix(c.a, 1.0, f * 0.8)));
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
        vec2 g = vec2(cos(w1.x + w1.y * 0.6), sin(w1.y - w1.x * 0.45)) * 0.045;
        // P184 (Oct 13: "render distance struggles over water"): the fine noise ripples only where they still show.
        if (oDist < 128.0) { g += (vec2(vnoise(w2), vnoise(w2 + 7.3)) - 0.5) * 0.11; }
        g *= 0.85 + 0.1 * u.waves.x;                                       // choppier as the sea gets up
        // Ripples a pixel can't resolve alias into contour bands on far water: fade them.
        g *= 1.0 - 0.8 * smoothstep(32.0, 128.0, oDist);
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
        // P451 (Oct 25 09:00, a beach: the water "really sticky... like goo. It just doesn't totally flatten out against
        // the surface"): the swell's tilt dies out over the shallows with its height (chunk.vert waveK). A sheet of water
        // a few centimetres deep over the sand rolled with the open sea's reflections, a thick gel sliding on the beach.
        if (wp.y > 124.5 && wp.y < 127.5) { g -= oceanWave(wp.xz, t).yz * (1.5 * smoothstep(0.25, 1.4, oWDepth)); }
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
            outColor = worldColor(vec4(mix(col, u.fogColor.rgb, f), 0.94));
        } else {
            outColor = worldColor(vec4(mix(rgb, u.fogColor.rgb, f), mix(c.a, 1.0, f * 0.8)));
        }
        return;
    }

    float cosT = clamp(dot(-v, n), 0.0, 1.0);
    float fres = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
    vec3 r = reflect(v, n);
    r.y = abs(r.y);                                                        // ripples can tip it under the horizon
    vec3 refl = skyAlong(r) * mix(0.25, 1.0, skyVis);
    // The water's own colour (tint, lit like the surface): what fills the view where the bed can't be seen.
    // Tuned to the Mac's Fancy ocean seen ~40 degrees down at noon (seed 12345 --find ocean: about 35, 61, 93).
    vec3 deep = (oTint * 0.38 + vec3(0.03, 0.05, 0.04)) * (lit + 0.04) * (0.85 + 0.3 * texL);
    vec3 pm;        // premultiplied colour
    float A;        // coverage: how much of the bed behind is replaced
    if (top) {
        // Light crossing `path` metres of water reaches the eye with `absorb` left (red goes first).
        float path = oWDepth / max(0.12, abs(v.y));
        // P352: swamp water (a tint greener than it is blue) is murky: it swallows light fast, so the shallow bed
        // fades into a dark green-brown body instead of showing through, and it carries no shoreline foam (shallow
        // all over, the foam read as white bubbles across the whole swamp).
        float murk = 1.0 - smoothstep(0.8, 1.0, oTint.b / max(oTint.g, 0.01));
        vec3 absorb = exp(-path * mix(vec3(0.42, 0.15, 0.09), vec3(1.1, 0.9, 1.2), murk));
        float T = dot(absorb, vec3(0.3, 0.5, 0.2));
        // F5 (open ocean the cheapest view): deep water (the mesher's 5+ band) past the near ring shows none of its bed,
        // so the far sections under 16+ blocks of water are not drawn at all (SceneRenderer.cull); from high up the
        // bed's last tenth or so of transmittance would otherwise show the sky through.
        if (oWDepth > 10.0) { T *= 1.0 - smoothstep(60.0, 76.0, oDist); }
        fres = min(1.0, fres * 1.1);
        A = 1.0 - (1.0 - fres) * T;
        pm = refl * fres + deep * (1.0 - fres) * (1.0 - T);
        // P403 step 3 / P412 (c) (Remington, Oct 22: the white sheen and foam 'add little and don't look good'): the
        // shoreline foam band and the soft sun sheen are gone; the sun keeps its tight glint.
        if (sunVis > 0.0) {
            vec3 hv = normalize(u.sunDir.xyz - v);
            float nh = clamp(dot(n, hv), 0.0, 1.0);
            // P412 (c) again (the jungle shore at noon: the glint blew out to a white patch a block wide): tighter and dimmer.
            vec3 sp = sunC * (pow(nh, 1400.0) * 2.5) * sunVis;
            pm += sp;
            A = max(A, min(1.0, max(sp.r, max(sp.g, sp.b))));
        }
        // P507 (Nov 1 12:30:09-12:30:24 on a beach: "still a little bit of a ridge here where the water... the water doesn't
        // quite settle with the ground perfectly... Or anywhere for that matter"): the last few centimetres of water at
        // the shoreline thin out to nothing (the sky's sheen and the tint fade with the depth), so the water's edge
        // isn't a line drawn across the sand where the sheet meets it.
        float shore = smoothstep(0.02, 0.4, oWDepth);
        A *= shore; pm *= shore;
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
    outColor = worldColor(vec4(pm / max(A, 1e-3), A));
}
