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
    float4 sunDir;
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
    float2 uv = float2(float(w1 & 31u), float((w1 >> 5) & 31u)) / 16.0;
    uint layer = ((w1 >> 10) & 1023u) | ((w1 >> 31) << 10);
    uint ao = (w1 >> 20) & 3u;
    float skyL = float((w1 >> 22) & 15u) / 15.0;
    float blkL = float((w1 >> 26) & 15u) / 15.0;

    float3 rel = p + sectionOffset.xyz;
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
    float blk = blkL / (4.0 - 3.0 * blkL) * 1.1;   // steep falloff: bright pool, dark edges
    float3 lit = max(float3(sky), blk * float3(1.0, 0.76, 0.46));
    // Dimension ambient lifts the whole light curve (the Emberdeep/End are never pitch black).
    lit = mix(max(lit, float3(0.035)), float3(1.0), u.sunDir.w);
    o.shade = lit * (faceShade[face] * aoCurve[ao]);
    o.dist = length(rel);
    return o;
}

static float3 applyFog(float3 c, float dist, constant Uniforms& u) {
    float f = smoothstep(u.fogColor.w, u.params.x, dist);
    return mix(c, u.fogColor.rgb, f);
}

fragment float4 chunkFS(ChunkOut in [[stage_in]],
                        texture2d_array<float> tex [[texture(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    float2 uv = in.uv;
    if (in.anim > 0.5) { uv += float2(0.0, fract(u.params.z * 0.04)); }   // slow lava flow
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    if (c.a < 0.5) { discard_fragment(); }
    // Overlay faces (grass sides): only the marked texels (alpha ~0.9) take the biome tint.
    float3 t = (in.overlay > 0.5 && c.a > 0.95) ? float3(1.0) : in.tint;
    float3 rgb = c.rgb * t * in.shade;
    return float4(applyFog(rgb, in.dist, u), 1.0);
}

fragment float4 waterFS(ChunkOut in [[stage_in]],
                        texture2d_array<float> tex [[texture(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    float t = u.params.z;
    float2 uv = in.uv + float2(t * 0.03, t * 0.017);
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    float3 rgb = c.rgb * in.tint * max(in.shade, float3(0.05));
    float f = smoothstep(u.fogColor.w, u.params.x, in.dist);
    return float4(mix(rgb, u.fogColor.rgb, f), mix(c.a, 1.0, f * 0.8));
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

fragment float4 crackFS(EntOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]]) {
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer), level(0.0));
    if (c.a < 0.1) { discard_fragment(); }
    return float4(c.rgb, c.a * in.color.a);
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
