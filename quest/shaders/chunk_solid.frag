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
layout(location = 10) in vec4 oLayers;      // smooth terrain: each corner's layer x its weight (chunk.vert)
layout(location = 11) in vec4 oLW;
layout(location = 12) in vec3 oNrm;         // P383: per-position ground's normal (zero for everything else)
layout(location = 0) out vec4 outColor;

// P383: per-position ground is textured triplanar from the world position: each axis's projection (the same uv the
// cube faces and the old per-quad facing used) weighted by how much the normal points along it, sharpened so most of
// the ground reads one projection (one texture read) and only steep slopes blend two. Uvs and their screen derivatives
// are taken up front (uniform control flow), so the reads can be skipped per fragment.
vec3 triW;
vec2 triUV[3], triGX[3], triGY[3];
vec2 triCell;
bool triOn;
vec4 texG(vec2 uv, vec2 gx, vec2 gy, float layer) {
    vec2 sz = vec2(textureSize(tex, 0).xy);
    return textureGrad(tex, vec3(sharpUVd(uv, (abs(gx) + abs(gy)) * sz), layer), gx, gy);
}
vec4 triTex(float layer, bool turned) {
    vec4 c = vec4(0.0);
    if (triW.x > 0.0) c += triW.x * texG(triUV[0], triGX[0], triGY[0], layer);
    if (triW.y > 0.0) c += triW.y * (turned ? texSharpTurnedG(triUV[1], layer, triCell, triGX[1], triGY[1]) : texG(triUV[1], triGX[1], triGY[1], layer));
    if (triW.z > 0.0) c += triW.z * texG(triUV[2], triGX[2], triGY[2], layer);
    return c;
}

void main() {
    vec2 uv = oUV;
    if (oAnim > 0.5 && oAnim < 1.5) { uv += vec2(0.0, fract(u.params.z * 0.04)); }
    triOn = dot(oNrm, oNrm) > 0.25;
    // (constant over a primitive, so the derivatives inside are taken over whole 2 x 2 fragment quads)
    if (triOn) {
        vec3 n = normalize(oNrm + vec3(0.0, 1e-5, 0.0));
        vec3 wp = oRel + u.eye.xyz;
        vec3 w = max(abs(n) - 0.55, vec3(0.0));
        w = w * w;
        triW = w / max(w.x + w.y + w.z, 1e-6);
        triUV[0] = n.x > 0.0 ? vec2(-wp.z, -wp.y) : vec2(wp.z, -wp.y);
        triUV[1] = n.y > 0.0 ? wp.xz : vec2(wp.x, -wp.z);
        triUV[2] = n.z > 0.0 ? vec2(wp.x, -wp.y) : vec2(-wp.x, -wp.y);
        for (int k = 0; k < 3; k++) { triGX[k] = dFdx(triUV[k]); triGY[k] = dFdy(triUV[k]); }
        triCell = floor(wp.xz);
    }
    // Grass tops: turned per block (texSharpTurned); the cell is the world block under this fragment. P496: so are
    // the tops of the layers ShaderFX.turnBits lists (snow, soil, rock).
    bool turn = oAnim > 1.5 || (uint(oFace + 0.5) == 2u && turnedLayer(oLayer));
    vec4 c = triOn ? triTex(oLayer, oAnim > 1.5 || turnedLayer(oLayer))
        : turn ? texSharpTurned(uv, oLayer, floor(oRel.xz + u.eye.xz - fract(uv) + 0.5)) : texSharp(uv, oLayer);
    if (oAnim > 0.5 && oAnim < 1.5) { c.rgb = lavaGlow(c.rgb, oRel); }
    // Smooth terrain (P142): where the quad's corners are different materials (grass to dirt to stone to sand), blend
    // them by how near each corner is, sharpened and broken up by the texture's own brightness so the border wanders
    // like real ground instead of fading. One texture read where a quad is one material (most of them).
    if (oLW.x + oLW.y + oLW.z + oLW.w > 0.5) {
        vec4 L = floor(oLayers / max(oLW, vec4(1e-4)) + 0.5);
        vec4 diff = vec4(notEqual(L, vec4(oLayer))) * step(vec4(0.002), oLW);
        if (dot(diff, diff) > 0.0) {
            vec4 w = oLW * oLW;
            vec3 acc = c.rgb * dot(w, 1.0 - diff);
            float wsum = dot(w, 1.0 - diff);
            for (int k = 0; k < 4; k++) {
                if (diff[k] > 0.5) {
                    vec4 ck = triOn ? triTex(L[k], turnedLayer(L[k])) : texSharp(uv, L[k]);
                    float wk = w[k] * (0.6 + 0.8 * dot(ck.rgb, vec3(0.333)));     // brighter grains of the other ground poke through first
                    acc += ck.rgb * wk; wsum += wk;
                }
            }
            c.rgb = acc / max(wsum, 1e-4);
        }
    }
    vec3 t = (oOverlay > 0.5 && c.a > 0.95) ? vec3(1.0) : oTint;
    vec3 lit = c.rgb * t * oShade;
    // SH1 surface sheen: metal and ice catch the sun, and so do tops left wet by rain, as much as the sky lights them.
    if (fxOn(16) && u.params.y > 0.05) {
        uint li = uint(oLayer + 0.5), f = uint(oFace + 0.5);
        bool metal = (u.sheen[(li >> 7u) & 15u][(li >> 5u) & 3u] & (1u << (li & 31u))) != 0u;
        bool wet = u.waves.y > 0.05 && f == 2u;
        if ((metal || wet) && f < 6u) {
            vec3 v = normalize(-oRel), h = normalize(v + normalize(u.sunDir.xyz));
            float sky = clamp(dot(oShade, vec3(0.333)) * 1.4, 0.0, 1.0);
            float sp = metal ? pow(max(dot(faceNormal(f), h), 0.0), 48.0) * 0.55 : pow(max(dot(faceNormal(f), h), 0.0), 90.0) * 0.4 * u.waves.y;
            lit += vec3(1.0, 0.95, 0.85) * sp * u.params.y * sky;
        }
    }
    outColor = worldColor(vec4(applyFogDir(waterAmbient(lit, c.rgb * t), oRel, oDist), 1.0));
}
