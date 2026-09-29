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
    float shade;
    float dist;
};

constexpr sampler texSampler(filter::nearest, mip_filter::linear, address::repeat);

constant float faceShade[8] = { 0.80, 0.80, 1.00, 0.55, 0.68, 0.68, 0.88, 0.88 };
constant float aoCurve[4] = { 0.42, 0.62, 0.81, 1.0 };
constant float2 cornerUV[4] = { float2(0, 1), float2(1, 1), float2(1, 0), float2(0, 0) };

vertex ChunkOut chunkVS(uint vid [[vertex_id]],
                        const device uint2* verts [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]],
                        constant float4& chunkOffset [[buffer(2)]]) {
    uint2 v = verts[vid];
    uint w0 = v.x, w1 = v.y;
    float3 p = float3(float(w0 & 31u), float((w0 >> 5) & 511u), float((w0 >> 14) & 31u));
    uint face = (w0 >> 19) & 7u;
    uint corner = (w0 >> 22) & 3u;
    uint ao = (w0 >> 24) & 3u;
    if (((w0 >> 26) & 1u) != 0u) { p.y -= 0.125; }
    uint layer = w1 & 255u;
    float light = float((w1 >> 8) & 15u) / 15.0;

    float3 rel = p + chunkOffset.xyz;
    ChunkOut o;
    o.pos = u.viewProj * float4(rel, 1.0);
    o.uv = cornerUV[corner];
    o.layer = float(layer);
    float sky = light * (0.35 + 0.65 * light);
    float lit = max(sky * u.params.y, 0.035);
    o.shade = lit * faceShade[face] * aoCurve[ao];
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
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer));
    if (c.a < 0.5) { discard_fragment(); }
    float3 rgb = c.rgb * in.shade;
    return float4(applyFog(rgb, in.dist, u), 1.0);
}

fragment float4 waterFS(ChunkOut in [[stage_in]],
                        texture2d_array<float> tex [[texture(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    float t = u.params.z;
    float2 uv = in.uv + float2(t * 0.03, t * 0.017);
    float4 c = tex.sample(texSampler, uv, uint(in.layer));
    float3 rgb = c.rgb * max(in.shade, 0.05);
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
    p = fract(p * float2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
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
    float n = vnoise(cell * 0.19) * 0.7 + vnoise(cell * 0.045 + 17.0) * 0.5 + hash21(cell) * 0.1;
    if (n < 0.8) { discard_fragment(); }
    float fade = 1.0 - smoothstep(cp.z * 0.5, cp.z, length(in.rel.xz));
    float day = u.params.y;
    float3 col = float3(1.0, 1.0, 1.0) * (0.12 + 0.88 * day);
    col = mix(col, u.fogColor.rgb, 0.2);
    return float4(col, 0.82 * fade);
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
