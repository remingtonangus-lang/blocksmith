#version 450
#include "common.glsl"
// Realistic world: the section's round shapes (trunks, limbs, organic objects) in 16-byte vertices (Sources/DetailMesh.swift):
//   x: x Int16 (1/256 block) | y Int16 << 16      y: z Int16 | nx snorm8 << 16 | ny snorm8 << 24
//   z: nz snorm8 | tint(2) << 8 | ao(2) << 10 | sky(4) << 12 | block(4) << 16 | layer(11) << 20 | cut << 31
//   w: u half | v half << 16
// Lit like chunk.vert's smooth terrain (a vertex normal), drawn by chunk_solid.frag / chunk_cut.frag.
layout(location = 0) in uvec4 v;
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
layout(location = 9) out float oWDepth;
layout(location = 10) out vec4 oLayers;
layout(location = 11) out vec4 oLW;

const float aoCurve[4] = float[](0.42, 0.62, 0.81, 1.0);

void main() {
    vec3 p = vec3(float(int(v.x << 16u) >> 16), float(int(v.x) >> 16), float(int(v.y << 16u) >> 16)) / 256.0;
    vec3 nrm = vec3(float(int(v.y << 8u) >> 24), float(int(v.y) >> 24), float(int(v.z << 24u) >> 24)) / 127.0;
    nrm = normalize(nrm + vec3(0.0, 1e-4, 0.0));
    uint tintMode = (v.z >> 8u) & 3u;
    uint ao = (v.z >> 10u) & 3u;
    float skyL = float((v.z >> 12u) & 15u) / 15.0;
    float blkL = float((v.z >> 16u) & 15u) / 15.0;
    uint layer = (v.z >> 20u) & 2047u;
    vec3 rel = p + origin;
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(rel, 1.0);
    oUV = unpackHalf2x16(v.w);
    oLayer = float(layer);
    oTint = vec3(1.0);
    if (tintMode != 0u) {
        uint cx = uint(clamp(p.x, 0.0, 15.0)), cz = uint(clamp(p.z, 0.0, 15.0));
        oTint = unpackUnorm4x8(tints[tintBase + cx + cz * 16u + (tintMode - 1u) * 256u]).rgb;
    }
    oOverlay = 0.0;
    oAnim = 0.0;
    float sky = skyL * (0.35 + 0.65 * skyL) * u.params.y;
    vec3 skyTint = mix(vec3(0.6, 0.7, 1.0), vec3(1.0), smoothstep(0.30, 0.62, u.params.y));
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    vec3 lit = max(sky * skyTint, blk * mix(vec3(1.06, 0.82, 0.56), vec3(1.0, 0.95, 0.86), blk * blk));
    float dk = u.misc.y;
    float b = mix(0.5, u.misc.w, dk);
    float g = (b - 0.5) * 0.8;
    lit = clamp(max(lit, vec3(0.055)) + lit * (1.0 - lit) * g, 0.0, 1.0);
    float nearK = mix(1.0, 0.45, smoothstep(5.0, 30.0, length(rel)));
    float fl = max(0.04, (0.06 + 0.3 * b) * nearK) * 2.0 * (1.0 - smoothstep(0.15, 0.68, skyL)) * dk;
    lit = max(lit, vec3(0.84, 0.92, 1.08) * fl * mix(0.5, 1.0, float(ao) / 3.0));
    lit = mix(lit, vec3(1.0), u.sunDir.w);
    oWDepth = -1.0;
    float sw = 0.85 * smoothstep(0.0, 0.45, u.params.y) * skyL * skyL * clamp((sky - blk) * 4.0 + 0.5, 0.0, 1.0) * (1.0 - u.sunDir.w);
    oShade = lit * sunShadeN(nrm, smoothShade(nrm), sw, u.sunDir.xyz) * aoCurve[ao];
    oLW = vec4(0.0);
    oLayers = vec4(0.0);
    oDist = length(rel);
    oRel = rel;
    oFace = 2.0;
}
