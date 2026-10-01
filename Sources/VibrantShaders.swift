// Fancy ("vibrant") rendering: HDR terrain shading with sun/moon shadows, emissive glow and material
// specular; water with refraction, screen-space reflections, caustics and depth absorption; shadow map
// passes; and the post chain (bloom, god rays + sun haze, tone mapping, colour grading).
// Appended to shaderSource (Shaders.swift) and compiled with it, so it can use Uniforms, texSampler,
// faceShade, aoCurve, vnoise, lavaGlow, waterAmbient and the fog helpers.

let vibrantShaderSource = """

struct VibOut {
    float4 pos [[position]];
    float2 uv;
    float layer [[flat]];
    float3 tint;
    float overlay [[flat]];
    float anim [[flat]];
    float face [[flat]];
    float water [[flat]];
    float ao;
    float2 light;      // x = sky light, y = block light (0...1)
    float3 rel;
};

// Per-section record at buffer 2, indexed by instance id: camera-relative origin + tint table offset (words).
// Same 16-byte layout as a float4 offset with w = 0, so single-section draws can pass (x, y, z, 0) bytes.
struct VibSection { packed_float3 origin; uint tint; };

vertex VibOut chunkVibVS(uint vid [[vertex_id]],
                         uint iid [[instance_id]],
                         const device uint2* verts [[buffer(0)]],
                         constant Uniforms& u [[buffer(1)]],
                         const device VibSection* sections [[buffer(2)]],
                         const device uint* tints [[buffer(3)]]) {
    float3 sectionOffset = float3(sections[iid].origin);
    uint tintBase = sections[iid].tint;
    uint2 v = verts[vid];
    uint w0 = v.x, w1 = v.y;
    uint xi = w0 & 511u, zi = (w0 >> 18) & 511u;
    float3 p = float3(float(xi), float((w0 >> 9) & 511u), float(zi)) / 16.0;
    uint face = (w0 >> 27) & 7u;
    uint tintMode = w0 >> 30;
    uint uu = w1 & 31u, vv = (w1 >> 5) & 31u;
    float2 uv = float2(float(uu), float(vv)) / 16.0;
    if (uu == 31u && vv == 31u) {
        switch (face) {
            case 0u: uv = float2(-p.z, -p.y); break;
            case 1u: uv = float2(p.z, -p.y); break;
            case 2u: uv = float2(p.x, p.z); break;
            case 3u: uv = float2(p.x, -p.z); break;
            case 4u: uv = float2(p.x, -p.y); break;
            default: uv = float2(-p.x, -p.y); break;
        }
    }
    uint layer = ((w1 >> 10) & 1023u) | ((w1 >> 31) << 10);
    uint ao = (w1 >> 20) & 3u;
    float3 rel = p + sectionOffset;
    if (face == 6u && vv == 0u) {
        float3 wp = rel + u.eye.xyz;
        float t = u.params.z;
        float sway = sin(wp.x * 0.9 + wp.z * 0.6 + t * 1.7) * 0.6 + sin(wp.z * 1.3 - wp.x * 0.4 + t * 2.3) * 0.4;
        rel.x += sway * 0.045;
        rel.z += cos(wp.x * 0.7 - wp.z * 0.8 + t * 1.9) * 0.03;
    }
    VibOut o;
    o.pos = u.viewProj * float4(rel, 1.0);
    o.uv = uv;
    o.layer = float(layer);
    o.tint = float3(1.0);
    if (tintMode != 0u) {
        uint cx = min(15u, xi >> 4), cz = min(15u, zi >> 4);
        o.tint = unpack_unorm4x8_to_float(tints[tintBase + cx + cz * 16u + (tintMode - 1u) * 256u]).rgb;
    }
    o.overlay = float((w1 >> 30) & 1u);
    o.anim = face == 7u ? 1.0 : 0.0;
    o.face = float(face);
    o.water = tintMode == 3u ? 1.0 : 0.0;
    o.ao = aoCurve[ao];
    o.light = float2(float((w1 >> 22) & 15u), float((w1 >> 26) & 15u)) / 15.0;
    o.rel = rel;
    return o;
}

static float3 vibNormal(float face) {
    switch (uint(face)) {
        case 0u: return float3(1, 0, 0);
        case 1u: return float3(-1, 0, 0);
        case 3u: return float3(0, -1, 0);
        case 4u: return float3(0, 0, 1);
        case 5u: return float3(0, 0, -1);
        default: return float3(0, 1, 0);
    }
}

// Sun/moon shadow: 5-tap hardware PCF around the projected point, faded out at the map's edge.
static float vibShadow(depth2d<float> sm, float3 rel, float3 n, constant Uniforms& u) {
    if (u.sunColor.w <= 0.001) { return 1.0; }
    float4 sc = u.shadowMat * float4(rel + n * 0.07, 1.0);
    float2 uv = float2(sc.x * 0.5 + 0.5, 0.5 - sc.y * 0.5);
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0 || sc.z >= 1.0) { return 1.0; }
    constexpr sampler cmp(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);
    float z = sc.z - 0.0006;
    float ts = 1.0 / 2048.0;
    float s = sm.sample_compare(cmp, uv, z) * 2.0;
    s += sm.sample_compare(cmp, uv + float2(ts, ts) * 1.2, z);
    s += sm.sample_compare(cmp, uv + float2(-ts, ts) * 1.2, z);
    s += sm.sample_compare(cmp, uv + float2(ts, -ts) * 1.2, z);
    s += sm.sample_compare(cmp, uv + float2(-ts, -ts) * 1.2, z);
    s /= 6.0;
    float edge = smoothstep(0.82, 0.97, max(abs(sc.x), abs(sc.y)));
    return mix(1.0, mix(s, 1.0, edge), u.sunColor.w);
}

// Animated caustic pattern (two drifting cell layers multiplied), 0...~1.
static float caustic(float2 p, float t) {
    float2 q = p * 0.9;
    float a = abs(sin(q.x + sin(q.y * 1.3 + t * 0.9) * 1.6 + t * 0.6));
    float b = abs(sin(q.y * 1.1 + sin(q.x * 0.8 - t * 0.7) * 1.7 - t * 0.5));
    float c = vnoise(p * 1.7 + float2(t * 0.25, -t * 0.2));
    return pow(saturate(1.0 - a * b * 1.6), 3.0) * (0.6 + 0.8 * c);
}

// Shared terrain shading: ambient sky light (face shade, AO) + directional sun/moon light with shadows,
// warm block light, rain wetness, material specular, emissive texels, fog.
static float3 flashLight(float3 rel, float3 n, constant float4* fl) {
    float3 acc = float3(0.0);
    for (int i = 0; i < 8; i++) {
        float4 pr = fl[i * 2];
        if (pr.w <= 0.0) { break; }
        float3 d = pr.xyz - rel;
        float dist = length(d);
        float att = saturate(1.0 - dist / pr.w);
        float ndl = saturate(dot(n, d / max(dist, 0.001)) * 0.75 + 0.25);
        acc += fl[i * 2 + 1].rgb * att * att * ndl;
    }
    return acc;
}

static float4 vibShade(VibOut in, float4 c, depth2d<float> sm, texture2d_array<float> emis,
                       const device uchar4* mats, constant Uniforms& u, constant float4* fl) {
    float3 t = (in.overlay > 0.5 && c.a > 0.95) ? float3(1.0) : in.tint;
    float3 albedo = c.rgb * t;
    uint layer = uint(in.layer);
    float4 m = float4(mats[layer]) / 255.0;          // x spec, y shininess/255, z metal, w can get wet
    float3 n = vibNormal(in.face);
    float3 v = normalize(in.rel);
    float skyL = in.light.x, blkL = in.light.y;
    float skyC = skyL * (0.35 + 0.65 * skyL);
    float sunVis = smoothstep(0.55, 0.95, skyL);
    float shadow = sunVis > 0.0 ? vibShadow(sm, in.rel, n, u) : 1.0;
    float spec = m.x, shin = max(4.0, m.y * 255.0);
    // Rain: skylit upward faces get darker and glossy.
    float wet = u.ambColor.w * m.w * sunVis * (in.face == 2.0 ? 1.0 : 0.35);
    albedo *= 1.0 - 0.18 * wet;
    spec = max(spec, 0.45 * wet); shin = max(shin, 48.0 * step(0.01, wet));
    float fs = faceShade[uint(in.face)];
    float3 amb = u.ambColor.rgb * skyC * fs * in.ao;
    float ndl = in.face > 5.5 ? 0.55 + 0.45 * saturate(u.lightDir.y) : saturate(dot(n, u.lightDir.xyz));
    float3 direct = u.sunColor.rgb * ndl * shadow * sunVis * mix(0.7, 1.0, in.ao);
    float3 skyPart = amb + direct;
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    float3 blkPart = blk * float3(1.0, 0.7, 0.4) * 1.1 * mix(0.75, 1.0, in.ao);
    float3 lit = max(skyPart, blkPart) + min(skyPart, blkPart) * 0.3;
    lit = mix(max(lit, float3(0.03)), float3(1.0), u.sunDir.w);
    lit += flashLight(in.rel, n, fl);
    float3 col = albedo * lit;
    if (spec > 0.004 && sunVis > 0.0) {
        float3 h = normalize(u.lightDir.xyz - v);
        float sp = pow(saturate(dot(n, h)), shin) * spec * shadow * sunVis * ndl;
        float3 sc = mix(float3(1.0), albedo * 1.8, m.z);
        col += u.sunColor.rgb * sc * sp * 2.5;
    }
    if (u.params.w > 0.5 && n.y > 0.5) {
        // Seen from under water: caustics dance on sunlit surfaces.
        col += albedo * caustic((in.rel + u.eye.xyz).xz, u.params.z) * u.sunColor.rgb * skyC * 0.5;
    }
    float e = emis.sample(texSampler, in.uv, layer).r;
    col += albedo * e * 2.4;
    col = waterAmbient(col, albedo, u);
    return float4(applyFogDir(col, in.rel, length(in.rel), u), 1.0);
}

fragment float4 chunkVibSolidFS(VibOut in [[stage_in]],
                                texture2d_array<float> tex [[texture(0)]],
                                depth2d<float> sm [[texture(1)]],
                                texture2d_array<float> emis [[texture(2)]],
                                constant Uniforms& u [[buffer(1)]],
                                const device uchar4* mats [[buffer(4)]],
                                constant float4* fl [[buffer(5)]]) {
    float2 uv = in.uv;
    if (in.anim > 0.5) { uv += float2(0.0, fract(u.params.z * 0.04)); }
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    if (in.anim > 0.5) { c.rgb = lavaGlow(c.rgb, in.rel, u); }
    VibOut o = in; o.uv = uv;
    return vibShade(o, c, sm, emis, mats, u, fl);
}

fragment float4 chunkVibFS(VibOut in [[stage_in]],
                           texture2d_array<float> tex [[texture(0)]],
                           depth2d<float> sm [[texture(1)]],
                           texture2d_array<float> emis [[texture(2)]],
                           constant Uniforms& u [[buffer(1)]],
                           const device uchar4* mats [[buffer(4)]],
                           constant float4* fl [[buffer(5)]]) {
    float2 uv = in.uv;
    if (in.anim > 0.5) { uv += float2(0.0, fract(u.params.z * 0.04)); }
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    if (c.a < 0.5) { discard_fragment(); }
    if (in.anim > 0.5) { c.rgb = lavaGlow(c.rgb, in.rel, u); }
    VibOut o = in; o.uv = uv;
    return vibShade(o, c, sm, emis, mats, u, fl);
}

static float3 relAt(float2 suv, float d, constant Uniforms& u) {
    float4 ndc = float4(suv.x * 2.0 - 1.0, 1.0 - suv.y * 2.0, d, 1.0);
    float4 w = u.invViewProj * ndc;
    return w.xyz / w.w;
}

// Sky colour along a direction (for reflections that miss the scene): horizon fog colour to a deeper
// zenith, plus the sun disc.
static float3 skyAlong(float3 d, constant Uniforms& u) {
    float h = saturate(d.y * 1.25);
    h = h * h * (3.0 - 2.0 * h);
    float3 hor = fogColorAlong(d, u);
    float3 col = mix(hor, u.fogColor.rgb * float3(0.45, 0.6, 0.92), h);
    return col + u.sunColor.rgb * pow(saturate(dot(d, u.lightDir.xyz)), 600.0) * 6.0;
}

// Water and other translucent faces. Water tops: refraction of the opaque scene (copied before this
// pass), depth absorption, caustics on the bed, screen-space reflections with a sky fallback, Fresnel,
// an HDR sun glint. Glass/ice and other translucent blocks blend as before, lit like terrain.
fragment float4 waterVibFS(VibOut in [[stage_in]],
                           texture2d_array<float> tex [[texture(0)]],
                           depth2d<float> sm [[texture(1)]],
                           texture2d<float> scene [[texture(3)]],
                           depth2d<float> sdepth [[texture(4)]],
                           constant Uniforms& u [[buffer(1)]]) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float t = u.params.z;
    float skyL = in.light.x, blkL = in.light.y;
    float skyC = skyL * (0.35 + 0.65 * skyL);
    float sunVis = smoothstep(0.55, 0.95, skyL);
    float3 v = normalize(in.rel);
    float dist = length(in.rel);
    if (in.water < 0.5) {
        float4 c = tex.sample(texSampler, in.uv, uint(in.layer));
        float3 lit = u.ambColor.rgb * skyC * faceShade[uint(in.face)] + u.sunColor.rgb * sunVis * 0.6 + blkL * float3(1.0, 0.7, 0.4);
        lit = mix(max(lit, float3(0.04)), float3(1.0), u.sunDir.w);
        float3 rgb = c.rgb * in.tint * lit;
        float3 n = vibNormal(in.face);
        float3 h = normalize(u.lightDir.xyz - v);
        rgb += u.sunColor.rgb * pow(saturate(dot(n, h)), 90.0) * sunVis * 1.5;
        float f = smoothstep(u.fogColor.w, u.params.x, dist);
        return float4(mix(rgb, fogColorAlong(in.rel, u), f), mix(c.a, 1.0, f * 0.8));
    }
    float2 suv = in.pos.xy * u.screen.zw;
    float3 wp = in.rel + u.eye.xyz;
    float3 n = vibNormal(in.face);
    if (in.face == 2.0) {
        float2 w1 = wp.xz * 0.8 + float2(t * 0.55, t * 0.3);
        float2 w2 = wp.xz * 2.1 - float2(t * 0.35, -t * 0.6);
        float2 g = float2(cos(w1.x + w1.y * 0.6), sin(w1.y - w1.x * 0.45)) * 0.045
                 + (float2(vnoise(w2), vnoise(w2 + 7.3)) - 0.5) * 0.11;
        n = normalize(float3(g.x, 1.0, g.y));
    }
    float3 deep = in.tint * (u.ambColor.rgb * 0.30 + u.sunColor.rgb * 0.10 + float3(0.01, 0.015, 0.02)) * mix(1.0, 0.4, u.params.w);
    // Opaque scene behind the surface.
    float d0 = sdepth.sample(ls, suv);
    float behind0 = d0 >= 1.0 ? dist + 64.0 : length(relAt(suv, d0, u));
    float thick0 = max(0.0, behind0 - dist);
    float2 ruv = suv + n.xz * 0.06 * saturate(thick0 * 0.3) * (1.0 / max(1.0, dist * 0.05));
    float d1 = sdepth.sample(ls, ruv);
    float behind1 = d1 >= 1.0 ? dist + 64.0 : length(relAt(ruv, d1, u));
    if (behind1 < dist) { ruv = suv; d1 = d0; behind1 = behind0; }
    float thick = max(0.0, behind1 - dist);
    float3 refr = scene.sample(ls, ruv).rgb;
    if (d1 < 1.0 && u.params.w < 0.5) {
        float3 bed = relAt(ruv, d1, u) + u.eye.xyz;
        refr += refr * caustic(bed.xz, t) * u.sunColor.rgb * sunVis * exp(-thick * 0.3) * 1.3;
    }
    float3 absorb = exp(-thick * float3(0.42, 0.15, 0.09));
    float3 under = refr * absorb + deep * (1.0 - absorb);
    if (u.params.w > 0.5) {
        // Looking up at the surface from below: the bright world above, tinted.
        // Beyond the critical angle the surface mirrors the water below (total internal reflection).
        float3 rd = refract(v, -n, 1.33);
        float3 col = length(rd) < 0.01 ? deep * 1.4 : mix(skyAlong(rd, u) * 0.85, deep, 0.3);
        col += u.sunColor.rgb * pow(saturate(dot(rd, u.lightDir.xyz)), 40.0) * 3.0 * sunVis;
        return float4(applyFog(col, dist, u), 1.0);
    }
    // Reflection: march the reflected ray through the opaque depth; fall back to the sky.
    float3 r = reflect(v, n);
    float3 refl = skyAlong(r, u) * mix(0.25, 1.0, sunVis);
    if (r.y > -0.05) {
        float3 pr = in.rel;
        float stepL = 0.4 + dist * 0.02;
        for (int i = 0; i < 20; i++) {
            pr += r * stepL;
            stepL *= 1.18;
            float4 cp = u.viewProj * float4(pr, 1.0);
            if (cp.w <= 0.0) { break; }
            float2 q = float2(cp.x / cp.w * 0.5 + 0.5, 0.5 - cp.y / cp.w * 0.5);
            if (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) { break; }
            float dq = sdepth.sample(ls, q);
            if (dq >= 1.0) { continue; }
            float sd = length(relAt(q, dq, u));
            float pd = length(pr);
            if (pd > sd && pd - sd < stepL * 2.5) {
                float edge = smoothstep(0.0, 0.08, min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)));
                refl = mix(refl, scene.sample(ls, q).rgb, edge);
                break;
            }
        }
    }
    float cosT = saturate(dot(-v, n));
    float fres = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
    float3 col = mix(under, refl, saturate(fres * 1.1));
    if (in.face == 2.0) {
        // Shoreline foam: where the water is shallow over the bed (or meets a wall), a broken white
        // band that drifts with the waves.
        float shore = 1.0 - smoothstep(0.0, 1.1, thick0);
        float fn = vnoise(wp.xz * 2.6 + float2(t * 0.4, -t * 0.3)) * 0.6 + vnoise(wp.xz * 6.0 - t * 0.5) * 0.4;
        float foam = shore * smoothstep(0.35, 0.75, fn + shore * 0.35);
        float3 foamLit = u.ambColor.rgb * skyC + u.sunColor.rgb * sunVis * 0.9 + blkL * float3(1.0, 0.7, 0.4) * 0.6;
        col = mix(col, foamLit * 0.95, foam * 0.85);
    }
    float3 h = normalize(u.lightDir.xyz - v);
    float sp = pow(saturate(dot(n, h)), 500.0) * 7.0 + pow(saturate(dot(n, h)), 70.0) * 0.18;
    col += u.sunColor.rgb * sp * sunVis;
    float f = smoothstep(u.fogColor.w, u.params.x, dist);
    return float4(mix(col, fogColorAlong(in.rel, u), f), 1.0);
}

// Shadow map passes: depth only (solid faces), alpha-tested cutout faces (leaves cast dappled shadows).
struct ShadowOut { float4 pos [[position]]; float2 uv; float layer [[flat]]; };

vertex ShadowOut shadowVS(uint vid [[vertex_id]],
                          const device uint2* verts [[buffer(0)]],
                          constant float4x4& lightVP [[buffer(1)]],
                          constant float4& off [[buffer(2)]]) {
    uint2 v = verts[vid];
    uint w0 = v.x, w1 = v.y;
    float3 p = float3(float(w0 & 511u), float((w0 >> 9) & 511u), float((w0 >> 18) & 511u)) / 16.0;
    uint uu = w1 & 31u, vv = (w1 >> 5) & 31u;
    ShadowOut o;
    o.pos = lightVP * float4(p + off.xyz, 1.0);
    o.uv = (uu == 31u && vv == 31u) ? float2(0.5) : float2(float(uu), float(vv)) / 16.0;
    o.layer = float(((w1 >> 10) & 1023u) | ((w1 >> 31) << 10));
    return o;
}

fragment void shadowCutFS(ShadowOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]]) {
    if (tex.sample(texSampler, in.uv, uint(in.layer)).a < 0.5) { discard_fragment(); }
}

// Post: full-screen triangle.
struct FsOut { float4 pos [[position]]; float2 uv; };

vertex FsOut fsVS(uint vid [[vertex_id]]) {
    float2 p = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);
    FsOut o;
    o.pos = float4(p, 0.0, 1.0);
    o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return o;
}

// prm: xy = source texel size, z = threshold (0 = none), w = unused
fragment float4 bloomDownFS(FsOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float4& prm [[buffer(0)]]) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float2 o = prm.xy;
    float3 c = (src.sample(ls, in.uv + float2(-o.x, -o.y)).rgb + src.sample(ls, in.uv + float2(o.x, -o.y)).rgb
              + src.sample(ls, in.uv + float2(-o.x, o.y)).rgb + src.sample(ls, in.uv + float2(o.x, o.y)).rgb) * 0.25;
    if (prm.z > 0.0) {
        float l = max(c.r, max(c.g, c.b));
        float soft = clamp(l - prm.z + 0.25, 0.0, 0.5);
        soft = soft * soft / 0.5;
        float w = max(soft, l - prm.z) / max(l, 1e-4);
        c *= w;
        c = min(c, float3(24.0));
    }
    return float4(c, 1.0);
}

// Tent upsample of the smaller level, added onto the bigger one (additive blend). prm.xy = src texel size, z = weight.
fragment float4 bloomUpFS(FsOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float4& prm [[buffer(0)]]) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float2 o = prm.xy;
    float3 c = src.sample(ls, in.uv).rgb * 4.0;
    c += (src.sample(ls, in.uv + float2(o.x, 0)).rgb + src.sample(ls, in.uv - float2(o.x, 0)).rgb
        + src.sample(ls, in.uv + float2(0, o.y)).rgb + src.sample(ls, in.uv - float2(0, o.y)).rgb) * 2.0;
    c += src.sample(ls, in.uv + o).rgb + src.sample(ls, in.uv - o).rgb
       + src.sample(ls, in.uv + float2(o.x, -o.y)).rgb + src.sample(ls, in.uv + float2(-o.x, o.y)).rgb;
    return float4(c / 16.0 * prm.z, 1.0);
}

struct PostParams {
    float4 sun;      // xy = sun position (uv), z = god ray strength, w = bloom strength
    float4 sunCol;   // rgb = sun colour, w = haze strength
    float4 grade;    // x = exposure, y = saturation, z = contrast, w = vignette
    float4 mist;     // rgb = mist colour, w = density
    float4 mistH;    // x = base height relative to the eye, y = falloff height
};

// God rays: march from each pixel toward the sun through the depth buffer; sky texels (depth 1) shine.
fragment float4 raysFS(FsOut in [[stage_in]], depth2d<float> dep [[texture(0)]], constant PostParams& p [[buffer(0)]]) {
    constexpr sampler ls(filter::nearest, address::clamp_to_edge);
    const int N = 28;
    float2 uv = in.uv;
    float2 delta = (p.sun.xy - uv) / float(N) * 0.9;
    float illum = 0.0, decay = 1.0, wsum = 0.0;
    for (int i = 0; i < N; i++) {
        uv += delta;
        float d = dep.sample(ls, uv);
        illum += (d >= 0.99999 ? 1.0 : 0.0) * decay;
        wsum += decay;
        decay *= 0.955;
    }
    float r = illum / wsum;
    float fall = 1.0 - smoothstep(0.0, 0.75, length((in.uv - p.sun.xy) * float2(1.6, 1.0)));
    return float4(r * fall, 0, 0, 1);
}

static float3 toneShoulder(float3 x) {
    const float k = 0.76;
    float3 over = max(x - k, 0.0);
    return min(x, float3(k)) + (1.0 - k) * (1.0 - exp(-over / (1.0 - k)));
}

fragment float4 compositeFS(FsOut in [[stage_in]],
                            texture2d<float> hdr [[texture(0)]],
                            texture2d<float> bloom [[texture(1)]],
                            texture2d<float> rays [[texture(2)]],
                            depth2d<float> dep [[texture(3)]],
                            constant PostParams& p [[buffer(0)]],
                            constant Uniforms& u [[buffer(1)]]) {
    constexpr sampler ls(filter::linear, address::clamp_to_edge);
    float3 c = hdr.sample(ls, in.uv).rgb;
    c += bloom.sample(ls, in.uv).rgb * p.sun.w;
    c += rays.sample(ls, in.uv).r * p.sunCol.rgb * p.sun.z;
    if (p.sunCol.w > 0.0) {
        // Sun haze: distant geometry toward the sun picks up warm in-scattered light.
        float d = dep.sample(ls, in.uv);
        float3 rel = relAt(in.uv, d, u);
        float dist = d >= 1.0 ? 400.0 : length(rel);
        float3 dir = normalize(rel);
        float phase = pow(saturate(dot(dir, u.lightDir.xyz)), 5.0) * 0.8 + 0.08;
        float haze = (1.0 - exp(-dist * 0.0035)) * phase * p.sunCol.w;
        if (d < 1.0) { c += p.sunCol.rgb * haze; }
    }
    if (p.mist.w > 0.0) {
        // Height mist: exponential density with height, integrated analytically along the view ray.
        float d = dep.sample(ls, in.uv);
        float3 rel = relAt(in.uv, d, u);
        float dist = d >= 1.0 ? u.params.x : min(length(rel), u.params.x);
        float3 dir = normalize(rel);
        float h0 = -p.mistH.x;                       // eye height above the mist base
        float k = 1.0 / p.mistH.y;
        float dy = dir.y * dist * k;
        float base = p.mist.w * exp(-max(h0, -8.0) * k);
        float od = abs(dy) > 1e-3 ? base * dist * (1.0 - exp(-dy)) / dy : base * dist;
        float m = 1.0 - exp(-od);
        float phase = 1.0 + pow(saturate(dot(dir, u.lightDir.xyz)), 6.0) * 1.5;
        c = mix(c, p.mist.rgb * phase, saturate(m));
    }
    if (u.params.w > 0.5 && u.sunColor.r + u.sunColor.g > 0.05) {
        // Under water: slanted light shafts that sway, brightest near the surface and toward the sun.
        float d = dep.sample(ls, in.uv);
        float3 rel = relAt(in.uv, d, u);
        float3 dir = normalize(rel);
        float dist = d >= 1.0 ? 40.0 : min(length(rel), 40.0);
        float t = u.params.z;
        float3 pm = u.eye.xyz + dir * dist * 0.5;
        float2 q = pm.xz - u.lightDir.xz * pm.y * 0.6;
        float shaft = pow(vnoise(q * 0.35 + float2(t * 0.15, t * 0.1)), 3.0) * 1.6;
        float up = saturate(dir.y * 0.8 + 0.4);
        c += u.fogColor.rgb * u.sunColor.rgb * shaft * up * (1.0 - exp(-dist * 0.06)) * 3.0;
    }
    c *= p.grade.x;
    c = toneShoulder(c);
    float l = dot(c, float3(0.299, 0.587, 0.114));
    c = mix(float3(l), c, p.grade.y);
    c = (c - 0.45) * p.grade.z + 0.45;
    c += float3(0.012, 0.005, -0.008) * smoothstep(0.5, 1.0, l) + float3(-0.006, 0.0, 0.012) * (1.0 - smoothstep(0.0, 0.35, l));
    float2 vq = (in.uv - 0.5) * float2(1.1, 1.0);
    c *= 1.0 - p.grade.w * pow(saturate(length(vq) * 1.3), 2.4);
    return float4(saturate(c), 1.0);
}
"""
