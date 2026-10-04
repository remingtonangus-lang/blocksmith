#version 450
#include "common.glsl"
// Ship sections (same vertex format and light curve as chunk.vert), placed with the ship's transform
// (Sources/ShipRender.swift shipVS). Push constants: model (ship space -> camera-relative), origin (xyz section
// origin in ship space, w = sky light around the ship), fog (x start, y end; 0 = the frame's fog).
layout(push_constant) uniform Push { mat4 model; vec4 origin; vec4 fog; } pc;
layout(location = 0) in uvec2 v;
layout(location = 0) out vec2 oUV;
layout(location = 1) flat out float oLayer;
layout(location = 2) out vec3 oShade;
layout(location = 3) out vec3 oTint;
layout(location = 4) flat out float oOverlay;
layout(location = 5) out float oDist;
const float faceShade[8] = float[](0.80, 0.80, 1.00, 0.55, 0.68, 0.68, 0.88, 1.00);
const float aoCurve[4] = float[](0.42, 0.62, 0.81, 1.0);
const vec3 plains[3] = vec3[](vec3(0x91, 0xBD, 0x59) / 255.0, vec3(0x77, 0xAB, 0x2F) / 255.0, vec3(0x3F, 0x76, 0xE4) / 255.0);
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
    float skyRaw = float((w1 >> 22) & 15u) / 15.0;
    skyRaw = max(skyRaw, face == 3u ? 0.8 : 0.6);
    float skyL = skyRaw * pc.origin.w;
    float blkL = float((w1 >> 26) & 15u) / 15.0;
    vec3 rel = (pc.model * vec4(p + pc.origin.xyz, 1.0)).xyz;
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(rel, 1.0);
    oUV = uv;
    oLayer = float(layer);
    oTint = tintMode != 0u ? plains[tintMode - 1u] : vec3(1.0);
    oOverlay = float((w1 >> 30) & 1u);
    float sky = skyL * (0.35 + 0.65 * skyL) * u.params.y;
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    vec3 lit = max(vec3(sky), blk * vec3(1.0, 0.76, 0.46));
    lit = mix(max(lit, vec3(0.035)), vec3(1.0), u.sunDir.w);
    oShade = lit * (faceShade[face] * aoCurve[ao]);
    oDist = length(rel);
}
