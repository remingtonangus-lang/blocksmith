#version 450
#include "common.glsl"
// Section vertices (Sources/Mesher.swift layout) + a per-instance section record (origin relative to the head,
// tint table offset). Tint tables: 256 grass, 256 foliage, 256 water colours per chunk.
layout(location = 0) in uvec2 v;
layout(location = 1) in vec3 origin;
layout(location = 2) in uint tintBase;
layout(set = 1, binding = 0, std430) readonly buffer Tints { uint tints[]; };

layout(location = 0) out vec2 oUV;
layout(location = 1) flat out float oLayer;
layout(location = 2) out vec3 oShade;
layout(location = 3) out vec3 oTint;
layout(location = 4) flat out float oOverlay;
layout(location = 5) flat out float oAnim;
layout(location = 6) out float oDist;
layout(location = 7) out vec3 oRel;
layout(location = 8) flat out float oFace;

const float faceShade[8] = float[](0.80, 0.80, 1.00, 0.55, 0.68, 0.68, 0.88, 1.00);
const float aoCurve[4] = float[](0.42, 0.62, 0.81, 1.0);

void main() {
    uint w0 = v.x, w1 = v.y;
    uint xi = w0 & 511u, zi = (w0 >> 18) & 511u;
    vec3 p = vec3(float(xi), float((w0 >> 9) & 511u), float(zi)) / 16.0;
    uint face = (w0 >> 27) & 7u;
    uint tintMode = w0 >> 30;
    uint uu = w1 & 31u, vv = (w1 >> 5) & 31u;
    vec2 uv = vec2(float(uu), float(vv)) / 16.0;
    if (uu == 31u && vv == 31u) {
        if (face == 0u) uv = vec2(-p.z, -p.y);
        else if (face == 1u) uv = vec2(p.z, -p.y);
        else if (face == 2u) uv = vec2(p.x, p.z);
        else if (face == 3u) uv = vec2(p.x, -p.z);
        else if (face == 4u) uv = vec2(p.x, -p.y);
        else uv = vec2(-p.x, -p.y);
    }
    uint layer = ((w1 >> 10) & 1023u) | ((w1 >> 31) << 10);
    uint ao = (w1 >> 20) & 3u;
    float skyL = float((w1 >> 22) & 15u) / 15.0;
    float blkL = float((w1 >> 26) & 15u) / 15.0;
    vec3 rel = p + origin;
    // Ocean waves: water surface corners (14/16 up a source cell) at sea level under open sky bob with the swell.
    // Every corner at that height moves (tops and the upper edge of sides alike), so faces stay joined.
    if (tintMode == 3u && ((w0 >> 9) & 15u) == 14u && skyL > 0.9) {
        vec3 wp = rel + u.eye.xyz;
        if (wp.y > 124.5 && wp.y < 127.5) rel.y += oceanWave(wp.xz, u.params.z).x;
    }
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(rel, 1.0);
    oUV = uv;
    oLayer = float(layer);
    oTint = vec3(1.0);
    if (tintMode != 0u) {
        uint cx = min(15u, xi >> 4), cz = min(15u, zi >> 4);
        oTint = unpackUnorm4x8(tints[tintBase + cx + cz * 16u + (tintMode - 1u) * 256u]).rgb;
    }
    oOverlay = float((w1 >> 30) & 1u);
    oAnim = face == 7u ? 1.0 : 0.0;
    float sky = skyL * (0.35 + 0.65 * skyL) * u.params.y;
    vec3 skyTint = mix(vec3(0.6, 0.7, 1.0), vec3(1.0), smoothstep(0.26, 0.6, u.params.y));
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    vec3 lit = max(sky * skyTint, blk * mix(vec3(1.0, 0.87, 0.68), vec3(1.0, 0.95, 0.86), blk * blk));
    // Cave fill (port of Shaders.caveFill, Fast path): a cool minimum light that fades with distance; misc.w = brightness.
    // misc.y = how dark it is at the eye (stand-in for eye adaptation): standing in daylight, Brightness and the fill are
    // off, so seabeds under deep water (skylight 0, like caves) stay near black and the ocean reads deep (v51 regression).
    float dk = u.misc.y;
    float b = mix(0.5, u.misc.w, dk);
    float g = (b - 0.5) * 0.8;
    lit = clamp(max(lit, vec3(0.055)) + lit * (1.0 - lit) * g, 0.0, 1.0);
    float nearK = mix(1.0, 0.45, smoothstep(5.0, 30.0, length(rel)));
    // Only where the sky can't reach (caves, deep interiors): at skylight 5+ (the surface at night) the fill would
    // wash out the dark depth gradient.
    float fl = max(0.04, (0.06 + 0.3 * b) * nearK) * 2.0 * (1.0 - smoothstep(0.0, 0.34, skyL)) * dk;
    lit = max(lit, vec3(0.84, 0.92, 1.08) * fl * mix(0.5, 1.0, float(ao) / 3.0));
    lit = mix(lit, vec3(1.0), u.sunDir.w);
    oShade = lit * (faceShade[face] * aoCurve[ao]);
    oDist = length(rel);
    oRel = rel;
    oFace = float(face);
}
