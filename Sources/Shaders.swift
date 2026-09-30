// Metal shaders as a source string, compiled at launch with device.makeLibrary(source:).
// This avoids needing the full Xcode `metal` toolchain.
// Struct layouts must match Swift: Uniforms, SimpleVert, HudVert (see Renderer.swift).

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 viewProj;   // projection * rotation-only view (camera-relative rendering)
    float4 fogColor;     // rgb, w = fog start
    float4 params;       // x = fog end, y = daylight, z = time (s), w = underwater
    float4 sunDir;       // xyz, w = dimension ambient
    float4 eye;          // xyz = camera position (world), w = 0 Fast, 1 + sun glow (0...0.99) for Fancy
};

struct ChunkOut {
    float4 pos [[position]];
    float2 uv;
    float layer [[flat]];
    float3 shade;
    float3 tint;
    float overlay [[flat]];
    float anim [[flat]];
    float dist;
    float3 rel;
    float face [[flat]];
};

constexpr sampler texSampler(filter::nearest, mip_filter::linear, address::repeat);

constant float faceShade[8] = { 0.80, 0.80, 1.00, 0.55, 0.68, 0.68, 0.88, 1.00 };
constant float aoCurve[4] = { 0.42, 0.62, 0.81, 1.0 };

// See Mesher.swift for the vertex layout. tints: 256 grass, 256 foliage, 256 water colours (RGBA8).
vertex ChunkOut chunkVS(uint vid [[vertex_id]],
                        const device uint2* verts [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]],
                        constant float4& sectionOffset [[buffer(2)]],
                        const device uint* tints [[buffer(3)]]) {
    uint2 v = verts[vid];
    uint w0 = v.x, w1 = v.y;
    uint xi = w0 & 511u, zi = (w0 >> 18) & 511u;
    float3 p = float3(float(xi), float((w0 >> 9) & 511u), float(zi)) / 16.0;
    uint face = (w0 >> 27) & 7u;
    uint tintMode = w0 >> 30;
    uint uu = w1 & 31u, vv = (w1 >> 5) & 31u;
    float2 uv = float2(float(uu), float(vv)) / 16.0;
    if (uu == 31u && vv == 31u) {
        // Greedy-merged quad: UVs from the position so the texture repeats once per block.
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
    float skyL = float((w1 >> 22) & 15u) / 15.0;
    float blkL = float((w1 >> 26) & 15u) / 15.0;

    float3 rel = p + sectionOffset.xyz;
    if (face == 6u && vv == 0u && u.eye.w > 0.5) {
        // Fancy: grass and flowers sway; only the top corners move so the base stays planted.
        float3 wp = rel + u.eye.xyz;
        float t = u.params.z;
        float sway = sin(wp.x * 0.9 + wp.z * 0.6 + t * 1.7) * 0.6 + sin(wp.z * 1.3 - wp.x * 0.4 + t * 2.3) * 0.4;
        rel.x += sway * 0.045;
        rel.z += cos(wp.x * 0.7 - wp.z * 0.8 + t * 1.9) * 0.03;
    }
    ChunkOut o;
    o.pos = u.viewProj * float4(rel, 1.0);
    o.uv = uv;
    o.layer = float(layer);
    o.tint = float3(1.0);
    if (tintMode != 0u) {
        uint cx = min(15u, xi >> 4), cz = min(15u, zi >> 4);
        o.tint = unpack_unorm4x8_to_float(tints[cx + cz * 16u + (tintMode - 1u) * 256u]).rgb;
    }
    o.overlay = float((w1 >> 30) & 1u);
    o.anim = face == 7u ? 1.0 : 0.0;
    // Skylight scales with daylight; block light (torches) is warm and constant.
    float sky = skyL * (0.35 + 0.65 * skyL) * u.params.y;
    // Moonlight: what little skylight is left at night is cool blue rather than grey.
    float3 skyTint = mix(float3(0.6, 0.7, 1.0), float3(1.0), smoothstep(0.1, 0.55, u.params.y));
    // Reference light curve (l / (4 - 3l)) with the default-brightness gamma lift, so a torch (14, -1 per
    // block) clearly lights ~6-7 blocks around it. Block light is never scaled by daylight.
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    float3 lit = max(sky * skyTint, blk * float3(1.0, 0.76, 0.46));
    // Dimension ambient lifts the whole light curve (the Emberdeep/End are never pitch black).
    lit = mix(max(lit, float3(0.035)), float3(1.0), u.sunDir.w);
    o.shade = lit * (faceShade[face] * aoCurve[ao]);
    o.dist = length(rel);
    o.rel = rel;
    o.face = float(face);
    return o;
}

static float3 applyFog(float3 c, float dist, constant Uniforms& u) {
    float f = smoothstep(u.fogColor.w, u.params.x, dist);
    return mix(c, u.fogColor.rgb, f);
}

// Fog colour seen along a view ray: Fancy adds the same warm dawn/dusk glow toward the sun as the sky
// dome, so fogged terrain on that horizon melts into the glow instead of cutting a dark silhouette.
static float3 fogColorAlong(float3 rel, constant Uniforms& u) {
    float glow = u.eye.w - 1.0;
    if (glow <= 0.0) { return u.fogColor.rgb; }
    float sd = saturate(dot(normalize(rel), normalize(u.sunDir.xyz)));
    return u.fogColor.rgb + float3(1.0, 0.55, 0.25) * pow(sd, 5.0) * glow;
}

static float3 applyFogDir(float3 c, float3 rel, float dist, constant Uniforms& u) {
    float f = smoothstep(u.fogColor.w, u.params.x, dist);
    return mix(c, fogColorAlong(rel, u), f);
}

static float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Lava: slow drifting hot spots over the flowing texture (both graphics modes; a few ALU ops).
static float3 lavaGlow(float3 c, float3 rel, constant Uniforms& u) {
    float2 w = (rel + u.eye.xyz).xz;
    float t = u.params.z;
    float n = vnoise(w * 0.45 + float2(t * 0.11, t * 0.07)) * 0.65 + vnoise(w * 1.3 - float2(t * 0.05, t * 0.13)) * 0.35;
    return c * (0.78 + 0.5 * n) + float3(0.12, 0.05, 0.0) * smoothstep(0.62, 0.9, n);
}

fragment float4 chunkSolidFS(ChunkOut in [[stage_in]],
                             texture2d_array<float> tex [[texture(0)]],
                             constant Uniforms& u [[buffer(1)]]) {
    float2 uv = in.uv;
    if (in.anim > 0.5) { uv += float2(0.0, fract(u.params.z * 0.04)); }
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    if (in.anim > 0.5) { c.rgb = lavaGlow(c.rgb, in.rel, u); }
    float3 t = (in.overlay > 0.5 && c.a > 0.95) ? float3(1.0) : in.tint;
    return float4(applyFogDir(c.rgb * t * in.shade, in.rel, in.dist, u), 1.0);
}

fragment float4 chunkFS(ChunkOut in [[stage_in]],
                        texture2d_array<float> tex [[texture(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    float2 uv = in.uv;
    if (in.anim > 0.5) { uv += float2(0.0, fract(u.params.z * 0.04)); }   // slow lava flow
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    if (c.a < 0.5) { discard_fragment(); }
    if (in.anim > 0.5) { c.rgb = lavaGlow(c.rgb, in.rel, u); }
    // Overlay faces (grass sides): only the marked texels (alpha ~0.9) take the biome tint.
    float3 t = (in.overlay > 0.5 && c.a > 0.95) ? float3(1.0) : in.tint;
    float3 rgb = c.rgb * t * in.shade;
    return float4(applyFogDir(rgb, in.rel, in.dist, u), 1.0);
}

fragment float4 waterFS(ChunkOut in [[stage_in]],
                        texture2d_array<float> tex [[texture(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    float t = u.params.z;
    float2 uv = in.uv + float2(t * 0.03, t * 0.017);
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    float3 rgb = c.rgb * in.tint * max(in.shade, float3(0.05));
    float a = c.a;
    if (u.eye.w > 0.5 && in.face < 2.5 && in.face > 1.5 && u.params.w < 0.5) {
        // Fancy water surface: grazing views reflect more sky (Fresnel), and small ripples catch a sun glint.
        float3 v = normalize(in.rel);
        float3 wp = in.rel + u.eye.xyz;
        float2 rip = float2(sin(wp.x * 1.7 + wp.z * 0.9 + t * 1.6), sin(wp.z * 2.1 - wp.x * 0.7 + t * 1.3)) * 0.06;
        float3 n = normalize(float3(rip.x, 1.0, rip.y));
        float fres = pow(1.0 - saturate(-v.y), 3.0);
        float lit = max(in.shade.x, max(in.shade.y, in.shade.z));
        rgb = mix(rgb, u.fogColor.rgb * (0.6 + 0.4 * lit), fres * 0.45);
        float3 r = reflect(v, n);
        float spec = pow(saturate(dot(r, normalize(u.sunDir.xyz))), 180.0) * u.params.y * lit;
        rgb += float3(1.0, 0.95, 0.8) * spec * 0.9;
        a = mix(a, 1.0, fres * 0.55);
    }
    float f = smoothstep(u.fogColor.w, u.params.x, in.dist);
    return float4(mix(rgb, fogColorAlong(in.rel, u), f), mix(a, 1.0, f * 0.8));
}

// Fancy sky: one full-screen triangle; the fragment shader shades the view direction with a
// zenith/horizon gradient, a warm glow around the sun at dawn/dusk and a faint haze around the sun.
struct SkyParams {
    float4x4 invViewProj;
    float4 zenith;      // rgb
    float4 horizon;     // rgb (= terrain fog colour), w = sun glow strength
    float4 sun;         // xyz = sun direction, w = daylight
};
struct SkyOut { float4 pos [[position]]; float2 ndc; };

vertex SkyOut skyVS(uint vid [[vertex_id]]) {
    float2 p = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);
    SkyOut o;
    o.pos = float4(p, 1.0, 1.0);
    o.ndc = p;
    return o;
}

fragment float4 skyFS(SkyOut in [[stage_in]], constant SkyParams& s [[buffer(1)]]) {
    float4 w = s.invViewProj * float4(in.ndc, 1.0, 1.0);
    float3 d = normalize(w.xyz / w.w);
    // Slow start: the first few degrees above the horizon stay close to the fog colour, so fogged
    // terrain and trees that poke above the horizon line don't show as pale silhouettes.
    float h = saturate(d.y * 1.25);
    h = h * h * (3.0 - 2.0 * h);
    float3 col = mix(s.horizon.rgb, s.zenith.rgb, h);
    if (d.y < 0.0) { col = s.horizon.rgb; }   // below the horizon: exactly the fog colour, so far terrain blends in
    float sd = saturate(dot(d, s.sun.xyz));
    float band = 1.0 - saturate(abs(d.y) * 3.0);                 // the glow hugs the horizon
    float3 warm = float3(1.0, 0.55, 0.25);
    col += warm * pow(sd, 5.0) * s.horizon.w * (0.35 + 0.65 * band);
    col += float3(1.0, 0.95, 0.85) * pow(sd, 24.0) * 0.18 * s.sun.w;
    return float4(col, 1.0);
}

struct SimpleVert { float4 pos; float4 color; };
struct SimpleOut { float4 pos [[position]]; float4 color; };

vertex SimpleOut simpleVS(uint vid [[vertex_id]],
                          const device SimpleVert* verts [[buffer(0)]],
                          constant Uniforms& u [[buffer(1)]]) {
    SimpleOut o;
    o.pos = u.viewProj * float4(verts[vid].pos.xyz, 1.0);
    o.color = verts[vid].color;
    return o;
}

fragment float4 simpleFS(SimpleOut in [[stage_in]]) { return in.color; }

// Stars: static unit-sphere quads rotated with the sun (buffer 2), faded in at night via tint.
struct StarParams { float4x4 rot; float4 tint; };

vertex SimpleOut starVS(uint vid [[vertex_id]],
                        const device SimpleVert* verts [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]],
                        constant StarParams& sp [[buffer(2)]]) {
    SimpleOut o;
    o.pos = u.viewProj * (sp.rot * float4(verts[vid].pos.xyz, 1.0));
    o.color = verts[vid].color * sp.tint;
    // Gentle twinkle: each star (6 vertices) gets its own phase and speed.
    float star = float(vid / 6u);
    float ph = fract(sin(star * 12.9898) * 43758.5453);
    o.color.rgb *= 0.78 + 0.22 * sin(u.params.z * (1.5 + 2.5 * ph) + ph * 40.0);
    return o;
}

// Clouds: one big camera-relative quad; the fragment shader decides per 12x12-block cell
// whether it is cloud, giving flat blocky clouds that drift with the wind.
struct CloudOut { float4 pos [[position]]; float3 rel; };

vertex CloudOut cloudVS(uint vid [[vertex_id]],
                        const device SimpleVert* verts [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    CloudOut o;
    float3 p = verts[vid].pos.xyz;
    o.pos = u.viewProj * float4(p, 1.0);
    o.rel = p;
    return o;
}

// cp: xy = world xz offset (eye + wind), z = fade distance, w = unused
fragment float4 cloudFS(CloudOut in [[stage_in]],
                        constant Uniforms& u [[buffer(1)]],
                        constant float4& cp [[buffer(2)]]) {
    float2 w = in.rel.xz + cp.xy;
    float2 cell = floor(w / 12.0);
    float n = vnoise(cell * 0.23) * 0.62 + vnoise(cell * 0.06 + 17.0) * 0.38 + (hash21(cell) - 0.5) * 0.08;
    if (n < 0.6) { discard_fragment(); }
    float fade = 1.0 - smoothstep(cp.z * 0.5, cp.z, length(in.rel.xz));
    float day = u.params.y;
    float3 col = float3(1.0, 1.0, 1.0) * mix(0.05, 1.0, smoothstep(0.12, 1.0, day));
    col = mix(col, u.fogColor.rgb, 0.2);
    return float4(col, 0.82 * fade);
}

// Fancy Hollow sky: the fog colour with faint drifting violet streaks and darker voids (no sun, no stars).
fragment float4 hollowSkyFS(SkyOut in [[stage_in]], constant SkyParams& s [[buffer(1)]]) {
    float4 w = s.invViewProj * float4(in.ndc, 1.0, 1.0);
    float3 d = normalize(w.xyz / w.w);
    float t = s.sun.w;
    // Project onto a box around the viewer so the pattern has no pole pinch.
    float3 a = abs(d);
    float2 q = a.y > max(a.x, a.z) ? d.xz / a.y : (a.x > a.z ? d.zy / a.x : d.xy / a.z);
    float n = vnoise(q * 3.0 + float2(t * 0.01, 0.0)) * 0.6 + vnoise(q * 9.0 - float2(0.0, t * 0.015)) * 0.4;
    float streak = smoothstep(0.55, 0.85, vnoise(float2(q.x * 1.5, q.y * 7.0) + 11.0));
    float3 base = s.horizon.rgb;
    float3 col = base * (0.7 + 0.5 * n) + float3(0.09, 0.04, 0.12) * streak;
    return float4(col, 1.0);
}

// Fancy clouds: boxes in cloud space (buffer 0, colour = face shade), one offset to the camera.
vertex CloudOut cloudBoxVS(uint vid [[vertex_id]],
                           const device SimpleVert* verts [[buffer(0)]],
                           constant Uniforms& u [[buffer(1)]],
                           constant float4& off [[buffer(2)]]) {
    CloudOut o;
    float3 p = verts[vid].pos.xyz + off.xyz;
    o.pos = u.viewProj * float4(p, 1.0);
    o.rel = float3(p.x, verts[vid].color.x, p.z);   // y carries the face shade
    return o;
}

// cp: z = fade distance
fragment float4 cloudBoxFS(CloudOut in [[stage_in]],
                           constant Uniforms& u [[buffer(1)]],
                           constant float4& cp [[buffer(2)]]) {
    float fade = 1.0 - smoothstep(cp.z * 0.5, cp.z, length(in.rel.xz));
    float day = u.params.y;
    float3 col = float3(1.0) * mix(0.05, 1.0, smoothstep(0.12, 1.0, day)) * in.rel.y;
    col = mix(col, u.fogColor.rgb, 0.2);
    return float4(col, 0.82 * fade);
}

// Mobs: flat-coloured cuboids; the pattern id adds pixel detail in model space (1/16-block cells).
struct MobVert { float4 pos; float4 color; float4 local; };
struct MobOut { float4 pos [[position]]; float3 color; float shade; float3 local; float pattern [[flat]]; float dist; };

vertex MobOut mobVS(uint vid [[vertex_id]],
                    const device MobVert* verts [[buffer(0)]],
                    constant Uniforms& u [[buffer(1)]]) {
    MobVert m = verts[vid];
    MobOut o;
    o.pos = u.viewProj * float4(m.pos.xyz, 1.0);
    o.color = m.color.rgb;
    o.shade = m.color.a;
    o.local = m.local.xyz;
    o.pattern = m.pos.w;
    o.dist = length(m.pos.xyz);
    return o;
}

static float hash31(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

fragment float4 mobFS(MobOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
    float3 cell = floor(in.local + 0.001);
    float h = hash31(cell);
    float3 c = in.color;
    if (in.pattern > 0.5 && in.pattern < 1.5) {
        // cow: big white patches
        float n = vnoise(cell.xz * 0.28 + cell.y * 0.21 + 3.0) * 0.7 + vnoise(cell.zy * 0.33 + 7.0) * 0.3;
        if (n > 0.58) { c = float3(0.92, 0.9, 0.86); }
        c *= 0.9 + 0.1 * h;
    } else if (in.pattern > 1.5 && in.pattern < 2.5) {
        c *= 0.8 + 0.2 * h;           // wool
    } else if (in.pattern > 2.5 && in.pattern < 3.5) {
        c *= 0.88 + 0.12 * step(0.5, h); // feathers
    } else if (in.pattern > 3.5 && in.pattern < 4.5) {
        float h2 = hash31(floor(in.local * 0.5 + 0.001));
        c *= 0.72 + 0.28 * h2 + 0.12 * h;  // mottled skin
    } else if (in.pattern > 4.5) {
        c *= 0.9 + 0.1 * h;              // bone
    } else {
        c *= 0.93 + 0.07 * h;
    }
    return float4(applyFog(c * in.shade, in.dist, u), 1.0);
}

// Textured entities: dropped items (cutout) and the block-breaking crack overlay (blended).
struct EntityVert { float4 pos; float4 uv; float4 color; };
struct EntOut { float4 pos [[position]]; float2 uv; float layer [[flat]]; float4 color; float dist; float overlay [[flat]]; };

vertex EntOut entityVS(uint vid [[vertex_id]],
                       const device EntityVert* verts [[buffer(0)]],
                       constant Uniforms& u [[buffer(1)]]) {
    EntityVert e = verts[vid];
    EntOut o;
    o.pos = u.viewProj * float4(e.pos.xyz, 1.0);
    o.uv = e.uv.xy;
    o.layer = e.pos.w;
    o.color = e.color;
    o.dist = length(e.pos.xyz);
    o.overlay = e.uv.z;
    return o;
}

fragment float4 entityFS(EntOut in [[stage_in]],
                         texture2d_array<float> tex [[texture(0)]],
                         constant Uniforms& u [[buffer(1)]]) {
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer));
    if (c.a < 0.5) { discard_fragment(); }
    float3 rgb = c.rgb;
    if (in.overlay > 0.5 && c.a < 0.95) { rgb *= float3(0.57, 0.74, 0.35); }   // grass-side overlay (default grass colour)
    return float4(applyFog(rgb * in.color.rgb, in.dist, u), 1.0);
}

// Blended textured quads: the block-breaking crack overlay, rain and snow, lightning.
fragment float4 crackFS(EntOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]]) {
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer), level(0.0));
    if (c.a < 0.1) { discard_fragment(); }
    return float4(c.rgb * in.color.rgb, c.a * in.color.a);
}

struct HudVert { float2 pos; float2 uv; float4 color; float4 extra; };
struct HudOut { float4 pos [[position]]; float2 uv; float4 color; float layer [[flat]]; };

vertex HudOut hudVS(uint vid [[vertex_id]],
                    const device HudVert* verts [[buffer(0)]],
                    constant float2& screen [[buffer(1)]]) {
    HudVert v = verts[vid];
    HudOut o;
    o.pos = float4(v.pos.x / screen.x * 2.0 - 1.0, 1.0 - v.pos.y / screen.y * 2.0, 0.0, 1.0);
    o.uv = v.uv;
    o.color = v.color;
    o.layer = v.extra.x;
    return o;
}

fragment float4 hudFS(HudOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]]) {
    if (in.layer < 0.0) { return in.color; }
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer), level(0.0));
    if (c.a < 0.1) { discard_fragment(); }
    return float4(c.rgb * in.color.rgb, c.a * in.color.a);
}
"""
