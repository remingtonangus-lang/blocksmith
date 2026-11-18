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
vec2 triCell, texSz;            // (texSz: the texture's size, asked once a fragment)
bool triOn;
vec4 texG(vec2 uv, vec2 gx, vec2 gy, float layer) {
    return texGradOrTop(vec3(sharpUVs(uv, (abs(gx) + abs(gy)) * texSz, texSz), layer), gx, gy, texSz);
}
vec4 triTex(float layer, bool turned) {
    vec4 c = vec4(0.0);
    if (fxOn(131072)) { turned = false; }
    if (fxOn(16384)) {                      // (ledger 235, headset trial: one projection a fragment, never a blend of two)
        if (triW.y >= triW.x && triW.y >= triW.z) { return turned ? texSharpTurnedGs(triUV[1], layer, triCell, triGX[1], triGY[1], texSz) : texG(triUV[1], triGX[1], triGY[1], layer); }
        if (triW.x >= triW.z) { return texG(triUV[0], triGX[0], triGY[0], layer); }
        return texG(triUV[2], triGX[2], triGY[2], layer);
    }
    if (triW.x > 0.0) c += triW.x * texG(triUV[0], triGX[0], triGY[0], layer);
    if (triW.y > 0.0) c += triW.y * (turned ? texSharpTurnedGs(triUV[1], layer, triCell, triGX[1], triGY[1], texSz) : texG(triUV[1], triGX[1], triGY[1], layer));
    if (triW.z > 0.0) c += triW.z * texG(triUV[2], triGX[2], triGY[2], layer);
    return c;
}

// Ledger 235: one read per material (see common.glsl). BS_FXADD=524288 = the shader as it was (mainOld).
void mainLean() {
    vec2 uv = oUV;
    bool lava = oAnim > 0.5 && oAnim < 1.5;
    if (lava) { uv += vec2(0.0, fract(u.params.z * 0.04)); }
    vec2 sz = vec2(textureSize(tex, 0).xy);
    vec3 wp = oRel + u.eye.xyz;
    vec3 dx = dFdx(wp), dy = dFdy(wp);
    vec2 U = uv, GX = dFdx(uv), GY = dFdy(uv);
    bool tri = dot(oNrm, oNrm) > 0.25;
    bool top = false;
    // Per-position ground: the projection its normal points most along (the others blended in only on a narrow band
    // of steep slopes before; the switch between two rough ground textures does not show).
    if (tri) {
        vec3 n = oNrm, an = abs(oNrm);
        // Ledger 266 (Nov 17 19:58:28 by Selenwick, a village path's ground step: "this shouldn't be happening, I've seen
        // it in other games"): texture stretching. A sharp ground step (a path terrace, a dug wall) shares its vertices
        // with the flat ground at its top and foot, so their normals point up and the riser between them took the top
        // projection: its texture smeared into long vertical streaks. Where the projection the normals pick lies along
        // the drawn face (under 0.45 of it facing that axis), the face's own normal picks it instead. Elsewhere the
        // per-position pick stands (P383: the quads round a vertex still agree). BS_OLDGROUNDPROJ=1: as before.
        vec3 fn = cross(dx, dy);
        float fl = length(fn);
        if (!fxOn(1048576) && fl > 1e-12) {
            fn /= fl;
            if (dot(fn, n) < 0.0) { fn = -fn; }
            vec3 af = abs(fn);
            float along = (an.y >= an.x && an.y >= an.z) ? af.y : (an.x >= an.z ? af.x : af.z);
            if (along < 0.45) { n = fn; an = af; }
        }
        if (an.y >= an.x && an.y >= an.z) {
            float sg = n.y > 0.0 ? 1.0 : -1.0;
            U = vec2(wp.x, sg * wp.z); GX = vec2(dx.x, sg * dx.z); GY = vec2(dy.x, sg * dy.z); top = true;
        } else if (an.x >= an.z) {
            float sg = n.x > 0.0 ? -1.0 : 1.0;
            U = vec2(sg * wp.z, -wp.y); GX = vec2(sg * dx.z, -dx.y); GY = vec2(sg * dy.z, -dy.y);
        } else {
            float sg = n.z > 0.0 ? 1.0 : -1.0;
            U = vec2(sg * wp.x, -wp.y); GX = vec2(sg * dx.x, -dx.y); GY = vec2(sg * dy.x, -dy.y);
        }
    }
    bool grassTop = oAnim > 1.5;
    bool turnMain = tri ? (top && (grassTop || turnedLayer(oLayer))) : (grassTop || (uint(oFace + 0.5) == 2u && turnedLayer(oLayer)));
    vec2 cell = tri ? floor(wp.xz) : floor(oRel.xz + u.eye.xz - fract(uv) + 0.5);
    int r = turnOf(cell);
    vec2 u1 = U, gx1 = GX, gy1 = GY;
    turnUV(turnMain ? r : 0, u1, gx1, gy1);
    vec4 c = texAt(u1, oLayer, gx1, gy1, sz);
    if (lava) { c.rgb = lavaGlow(c.rgb, oRel); }
    // Smooth terrain (P142): the other material at this quad's corners with the most weight, read once (a third
    // material at one quad is rare and gives way to the heavier of the two).
    if (oLW.x + oLW.y + oLW.z + oLW.w > 0.5) {
        vec4 L = floor(oLayers / max(oLW, vec4(1e-4)) + 0.5);
        vec4 diff = vec4(notEqual(L, vec4(oLayer))) * step(vec4(0.002), oLW);
        vec4 w = oLW * oLW;
        vec4 wd = w * diff;
        float m = max(max(wd.x, wd.y), max(wd.z, wd.w));
        if (m > 0.0) {
            float Lo = wd.x == m ? L.x : wd.y == m ? L.y : wd.z == m ? L.z : L.w;
            float wl = dot(wd, vec4(equal(L, vec4(Lo))));
            vec2 u2 = U, gx2 = GX, gy2 = GY;
            turnUV(tri && top && turnedLayer(Lo) ? r : 0, u2, gx2, gy2);
            vec4 ck = texAt(u2, Lo, gx2, gy2, sz);
            float wk = wl * (0.6 + 0.8 * dot(ck.rgb, vec3(0.333)));     // brighter grains of the other ground poke through first
            float w0 = dot(w, 1.0 - diff);
            c.rgb = (c.rgb * w0 + ck.rgb * wk) / max(w0 + wk, 1e-4);
        }
    }
    vec3 t = (oOverlay > 0.5 && c.a > 0.95) ? vec3(1.0) : oTint;
    vec3 lit = c.rgb * t * oShade;
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

void main() {
    if (!fxOn(524288) && !fxOn(4096) && !fxOn(2048)) { mainLean(); return; }
    vec2 uv = oUV;
    // Ledger 231 (headset trials, BS_FXADD): what the land's pixels cost. Not a look to ship.
    if (fxOn(4096)) { vec4 c0 = texture(tex, vec3(uv, oLayer)); outColor = vec4(applyFog(c0.rgb * oTint * oShade, oDist), 1.0); return; }
    if (fxOn(2048)) { vec4 c0 = texture(tex, vec3(uv, oLayer)); outColor = worldColor(vec4(applyFogDir(c0.rgb * oTint * oShade, oRel, oDist), 1.0)); return; }
    if (oAnim > 0.5 && oAnim < 1.5) { uv += vec2(0.0, fract(u.params.z * 0.04)); }
    texSz = vec2(textureSize(tex, 0).xy);
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
    bool turn = !fxOn(131072) && (oAnim > 1.5 || (uint(oFace + 0.5) == 2u && turnedLayer(oLayer)));
    vec4 c = triOn ? triTex(oLayer, oAnim > 1.5 || turnedLayer(oLayer))
        : turn ? texSharpTurned(uv, oLayer, floor(oRel.xz + u.eye.xz - fract(uv) + 0.5)) : texSharp(uv, oLayer);
    if (oAnim > 0.5 && oAnim < 1.5) { c.rgb = lavaGlow(c.rgb, oRel); }
    // Smooth terrain (P142): where the quad's corners are different materials (grass to dirt to stone to sand), blend
    // them by how near each corner is, sharpened and broken up by the texture's own brightness so the border wanders
    // like real ground instead of fading. One texture read where a quad is one material (most of them).
    if (!fxOn(8192) && oLW.x + oLW.y + oLW.z + oLW.w > 0.5) {
        vec4 L = floor(oLayers / max(oLW, vec4(1e-4)) + 0.5);
        vec4 diff = vec4(notEqual(L, vec4(oLayer))) * step(vec4(0.002), oLW);
        if (dot(diff, diff) > 0.0) {
            vec4 w = oLW * oLW;
            vec3 acc = c.rgb * dot(w, 1.0 - diff);
            float wsum = dot(w, 1.0 - diff);
            // P498: corners of the same other material are read once with their weights summed (a rock or a path in
            // grass is mostly quads with two or three corners of it: they read its texture two or three times).
            vec4 left = diff;
            for (int k = 0; k < 4; k++) {
                if (left[k] > 0.5) {
                    float wl = 0.0;
                    for (int j = k; j < 4; j++) { if (left[j] > 0.5 && L[j] == L[k]) { wl += w[j]; left[j] = 0.0; } }
                    vec4 ck = triOn ? triTex(L[k], turnedLayer(L[k])) : texSharp(uv, L[k]);
                    float wk = wl * (0.6 + 0.8 * dot(ck.rgb, vec3(0.333)));     // brighter grains of the other ground poke through first
                    acc += ck.rgb * wk; wsum += wk;
                }
            }
            c.rgb = acc / max(wsum, 1e-4);
        }
    }
    vec3 t = (oOverlay > 0.5 && c.a > 0.95) ? vec3(1.0) : oTint;
    vec3 lit = c.rgb * t * oShade;
    // SH1 surface sheen: metal and ice catch the sun, and so do tops left wet by rain, as much as the sky lights them.
    if (fxOn(262144)) { outColor = worldColor(vec4(applyFogDir(lit, oRel, oDist), 1.0)); return; }
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
