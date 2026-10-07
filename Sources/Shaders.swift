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
    // Fancy (HDR) pipeline only; zero in Fast.
    float4x4 invViewProj; // inverse of viewProj (camera-relative), for depth reconstruction
    float4x4 shadowMat;   // camera-relative position -> shadow map clip space
    float4 sunColor;      // rgb = direct light (sun or moon) colour x intensity, w = shadow strength
    float4 ambColor;      // rgb = sky ambient colour, w = rain wetness
    float4 lightDir;      // xyz = direction toward the light, w = time of day fraction
    float4 screen;        // xy = render size in pixels, zw = 1 / size
    float4 dimTint;       // rgb = colour of the dimension ambient lift (Fancy; white in the overworld)
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

constexpr sampler texSampler(mag_filter::nearest, min_filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));

constant float faceShade[8] = { 0.80, 0.80, 1.00, 0.55, 0.68, 0.68, 0.88, 1.00 };
constant float aoCurve[4] = { 0.42, 0.62, 0.81, 1.0 };

// See Mesher.swift for the vertex layout. tints: 256 grass, 256 foliage, 256 water colours (RGBA8).
// Per-section record (buffer 2, indexed by instance id = draw index): section origin relative to the
// camera and the chunk's tint table offset (in words) inside the tint buffer (buffer 3).
struct SectionRec { packed_float3 origin; uint tint; };

// Cave fill (playtest 2026-10-05: caves were black without torches): a cool minimum light so walls, ores and mobs
// read a few blocks away in the dark, fading with distance so a cave stays dark and moody; torches stay far brighter.
// u.dimTint.w is Options > Video > Brightness (0 moody, 0.5 default, 1 bright), which also lifts the light curve a little.
// `sky` (vertex skylight 0...1; Fast passes it): the fill fades out by skylight 5, so seabeds under deep water and
// the night surface keep their dark depth gradient (Fancy has eye adaptation and passes 0).
static float3 caveFill(float3 lit, float dist, constant Uniforms& u, float ao = 1.0, float sky = 0.0) {
    float b = u.dimTint.w;
    float g = (b - 0.5) * 0.8;
    lit = saturate(lit + lit * (1.0 - lit) * g);
    float near = mix(1.0, 0.45, smoothstep(5.0, 30.0, dist));
    // Fast has no eye adaptation or tone curve to open up the dark: twice the fill (cave_dark_fast read at half of Fancy).
    float fl = max(0.04, (0.06 + 0.3 * b) * near) * (u.eye.w < 0.5 ? 2.0 : 1.0) * (1.0 - smoothstep(0.0, 0.34, sky));
    return max(lit, float3(0.84, 0.92, 1.08) * fl * mix(0.5, 1.0, ao));   // corners stay darker (Fancy passes its AO)
}

vertex ChunkOut chunkVS(uint vid [[vertex_id]],
                        uint iid [[instance_id]],
                        const device uint2* verts [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]],
                        const device SectionRec* sections [[buffer(2)]],
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

    float3 rel = p + sectionOffset;
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
        o.tint = unpack_unorm4x8_to_float(tints[tintBase + cx + cz * 16u + (tintMode - 1u) * 256u]).rgb;
    }
    o.overlay = float((w1 >> 30) & 1u);
    o.anim = face == 7u ? 1.0 : 0.0;
    // Skylight scales with daylight; block light (torches) is warm and constant (a light warm cast: the old
    // (1, 0.76, 0.46) turned grey stone tan in torch-lit interiors).
    float sky = skyL * (0.35 + 0.65 * skyL) * u.params.y;
    // Moonlight: what little skylight is left at night is cool blue rather than grey.
    float3 skyTint = mix(float3(0.6, 0.7, 1.0), float3(1.0), smoothstep(0.26, 0.6, u.params.y));
    // Reference light curve (l / (4 - 3l)) with the default-brightness gamma lift, so a torch (14, -1 per
    // block) clearly lights ~6-7 blocks around it. Block light is never scaled by daylight.
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    // Warm at the edge of a light's reach, near white right next to it (Fancy does the same).
    float3 lit = max(sky * skyTint, blk * mix(float3(1.0, 0.87, 0.68), float3(1.0, 0.95, 0.86), blk * blk));
    // Dimension ambient lifts the whole light curve (the Emberdeep/End are never pitch black).
    lit = mix(caveFill(lit, length(rel), u, 1.0, skyL), float3(1.0), u.sunDir.w);   // cave fill: unlit walls stay readable nearby
    o.shade = lit * (faceShade[face] * aoCurve[ao]);
    o.dist = length(rel);
    o.rel = rel;
    o.face = float(face);
    return o;
}

// Seen from under water, geometry never goes fully black: it keeps a water-coloured ambient
// (albedo x fog colour), like light scattered through the water column.
static float3 waterAmbient(float3 lit, float3 albedo, constant Uniforms& u) {
    return u.params.w > 0.5 ? max(lit, albedo * u.fogColor.rgb * 2.2) : lit;
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
    return float4(applyFogDir(waterAmbient(c.rgb * t * in.shade, c.rgb * t, u), in.rel, in.dist, u), 1.0);
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
    float3 rgb = waterAmbient(c.rgb * t * in.shade, c.rgb * t, u);
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
    // Dusk/dawn: a soft pink band above the horizon opposite the sun (the anti-twilight arch).
    float anti = saturate(-dot(normalize(float3(d.x, 0.0, d.z) + 1e-4), normalize(float3(s.sun.x, 0.0, s.sun.z) + 1e-4)));
    float arch = exp(-pow((d.y - 0.1) / 0.09, 2.0));
    col += float3(0.55, 0.32, 0.42) * arch * anti * anti * saturate(s.horizon.w - 0.15) * 0.55;
    float night = saturate((0.45 - s.sun.w) / 0.35);
    if (night > 0.0 && d.y > -0.05) {
        // A faint galactic band across the night sky, turning with the stars (zenith.w = sky angle).
        float a = s.zenith.w;
        float3 bn = normalize(float3(0.3 * cos(a) - 0.2 * sin(a), 0.3 * sin(a) + 0.2 * cos(a), 0.93));
        float band = exp(-pow(dot(d, bn) * 4.5, 2.0));
        float3 q = d * 6.0;
        float cl = vnoise(q.xy + q.z * 0.7) * 0.6 + vnoise(q.yz * 2.3 + 5.0) * 0.4;
        col += float3(0.32, 0.3, 0.42) * band * smoothstep(0.3, 0.8, cl) * night * 0.22 * saturate(d.y * 4.0 + 0.2);
    }
    // Interleaved-gradient dither of one 8-bit step: the smooth gradient showed bands (critic, sky shots).
    float ign = fract(52.9829189 * fract(dot(in.pos.xy, float2(0.06711056, 0.00583715))));
    col += (ign - 0.5) / 255.0;
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

struct StarOut { float4 pos [[position]]; float4 color; float2 uv; };

vertex StarOut starVS(uint vid [[vertex_id]],
                      const device SimpleVert* verts [[buffer(0)]],
                      constant Uniforms& u [[buffer(1)]],
                      constant StarParams& sp [[buffer(2)]]) {
    StarOut o;
    o.pos = u.viewProj * (sp.rot * float4(verts[vid].pos.xyz, 1.0));
    o.color = verts[vid].color * sp.tint;
    // Gentle twinkle: each star (6 vertices) gets its own phase and speed.
    float star = float(vid / 6u);
    float ph = fract(sin(star * 12.9898) * 43758.5453);
    o.color.rgb *= 0.78 + 0.22 * sin(u.params.z * (1.5 + 2.5 * ph) + ph * 40.0);
    // Quad corner (vertices 0 1 2 0 2 3 of corners (0,0) (1,0) (1,1) (0,1)) for a round falloff.
    const uint corner[6] = {0u, 1u, 2u, 0u, 2u, 3u};
    uint c = corner[vid % 6u];
    o.uv = float2(c == 1u || c == 2u ? 1.0 : 0.0, c >= 2u ? 1.0 : 0.0);
    return o;
}

// Round, soft-edged stars (solid quads aliased into 1-3 px blobs: blind critic, night).
fragment float4 starFS(StarOut in [[stage_in]]) {
    float r = length(in.uv * 2.0 - 1.0);
    float a = 1.0 - smoothstep(0.35, 1.0, r);
    return float4(in.color.rgb * 1.5, in.color.a * a);
}

// Clouds: one big camera-relative quad; the fragment shader decides per 12x12-block cell
// whether it is cloud, giving flat blocky clouds that drift with the wind.
struct CloudOut { float4 pos [[position]]; float3 rel; float2 cell; };

vertex CloudOut cloudVS(uint vid [[vertex_id]],
                        const device SimpleVert* verts [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]]) {
    CloudOut o;
    float3 p = verts[vid].pos.xyz;
    o.pos = u.viewProj * float4(p, 1.0);
    o.rel = p;
    o.cell = p.xz;
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
    float3 col = base * (0.85 + 0.3 * n) + float3(0.035, 0.015, 0.05) * streak;
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
    o.cell = verts[vid].pos.xz;                       // cloud space: the drift moves with the clouds, not the camera
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
    if (u.sunColor.r + u.sunColor.g + u.ambColor.r > 0.0) {
        // HDR (Fancy): sky ambient plus direct sun/moon light on the lit faces (pink-gold at sunset).
        float lit = smoothstep(0.75, 1.0, in.rel.y);
        col = u.ambColor.rgb * (0.9 + 0.5 * in.rel.y) + u.sunColor.rgb * (0.35 + 1.1 * lit);
        // At night clouds are dim grey shapes against the stars, not lit blue blobs.
        col *= mix(0.22, 1.0, smoothstep(0.12, 0.7, day));
        // Shape: sides and undersides deeper, and a soft brightness drift per 4-block cell, so a cloud reads as a
        // mass rather than a flat white slab (blind critic, run 417: luma spread 1.2 over a whole cloud).
        float cell = fract(sin(dot(floor(in.cell * 0.25), float2(12.9898, 78.233))) * 43758.5453);
        col *= mix(0.72, 1.0, in.rel.y) * (0.9 + 0.12 * cell);
        col = mix(col, u.fogColor.rgb, 0.15);
    }
    return float4(col, 0.82 * fade);
}

// Mobs: flat-coloured cuboids; the pattern id adds pixel detail in model space (1/16-block cells).
struct MobVert { float4 pos; float4 color; float4 local; };
struct MobOut { float4 pos [[position]]; float3 color; float shade; float3 local; float pattern [[flat]]; float dist; float3 rel; };

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
    o.rel = m.pos.xyz;
    return o;
}

static float hash31(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

static float3 mobPattern(MobOut in) {
    // Detail at the blocks' 128 px scale (1/64 block) on top of the 1/16 cells, and smooth (not stair-stepped) patch
    // edges, so mobs don't read as 16 px pixel art next to the HD blocks.
    float3 p = in.local;
    float3 cell = floor(p + 0.001);
    float h = hash31(cell);
    float hf = hash31(floor(p * 4.0 + 0.001));
    float3 c = in.color;
    if (in.pattern > 0.5 && in.pattern < 1.5) {
        // cow: big white patches with soft edges
        float n = vnoise(p.xz * 0.28 + p.y * 0.21 + 3.0) * 0.7 + vnoise(p.zy * 0.33 + 7.0) * 0.3;
        c = mix(c, float3(0.92, 0.9, 0.86), smoothstep(0.565, 0.595, n));
        c *= 0.94 + 0.06 * h + 0.06 * (hf - 0.5);
    } else if (in.pattern > 1.5 && in.pattern < 2.5) {
        c *= 0.84 + 0.1 * h + 0.12 * hf;                         // wool: fuzz
    } else if (in.pattern > 2.5 && in.pattern < 3.5) {
        float row = fract(p.y * 0.5 + 0.25 * hash31(float3(cell.x, 0.0, cell.z)));
        c *= 0.86 + 0.1 * smoothstep(0.0, 0.6, row) + 0.05 * hf;  // feathers: overlapping rows
    } else if (in.pattern > 3.5 && in.pattern < 4.5) {
        float n = vnoise(p.xz * 0.5 + p.y * 0.37) * 0.6 + vnoise(p.zy * 1.3 + 5.0) * 0.4;
        c *= 0.74 + 0.3 * n + 0.06 * hf;                          // mottled skin
    } else if (in.pattern > 4.5 && in.pattern < 5.5) {
        c *= 0.9 + 0.06 * h + 0.05 * hf;                          // bone
    } else if (in.pattern > 5.5 && in.pattern < 6.5) {
        // dress cloth: a fine diagonal twill at 1/64 block and soft folds (white uniforms stay bright)
        float tw = sin((p.x + p.y + p.z) * 12.566);
        float fold = vnoise(p.xy * 0.33 + p.z * 0.21 + 11.0) * 0.6 + vnoise(p.zy * 0.4 + 3.0) * 0.4;
        c *= 0.955 + 0.025 * tw + 0.07 * (fold - 0.5) + 0.02 * (hf - 0.5);
    } else if (in.pattern > 6.5 && in.pattern < 7.5) {
        c *= 0.985 + 0.02 * (hf - 0.5);                           // enamel: clean, glossy (mobSheen)
    } else if (in.pattern > 7.5 && in.pattern < 8.5) {
        c *= 0.9 + 0.08 * hf + 0.04 * sin(p.y * 9.0 + p.x * 3.0); // polished metal: fine brushing
    } else if (in.pattern > 9.5 && in.pattern < 10.5) {
        c *= 0.93 + 0.05 * hf;                                    // polished leather
    } else if (in.pattern > 8.5) {
        // emissive (9) and smoked glass (11): flat
    } else {
        c *= 0.95 + 0.04 * h + 0.04 * (hf - 0.5);
    }
    return c;
}

// Highlights on polished mob surfaces (Capital uniforms: 7 enamel, 8 metal, 10 leather, 11 smoked glass): a sun
// specular and a faint rim, from the face normal `n` (screen derivatives of the camera-relative position).
static float3 mobSheen(float3 n, float3 rel, int pt, float3 toLight, float3 lightC) {
    float3 v = normalize(rel);
    if (dot(n, v) > 0.0) n = -n;
    float3 l = normalize(toLight);
    float3 h = normalize(l - v);
    float shin = pt == 8 ? 40.0 : (pt == 11 ? 90.0 : (pt == 10 ? 24.0 : 32.0));
    float k = pt == 8 ? 0.5 : (pt == 11 ? 0.55 : (pt == 10 ? 0.22 : 0.28));
    float s = pow(saturate(dot(n, h)), shin) * k * saturate(dot(n, l) * 4.0);
    float rim = pow(1.0 - saturate(dot(n, -v)), 4.0) * (pt == 11 ? 0.12 : 0.06);
    return lightC * (s + rim);
}
static bool mobGlossy(int pt) { return pt == 7 || pt == 8 || pt == 10 || pt == 11; }

fragment float4 mobFS(MobOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
    float3 c = mobPattern(in);
    int pt = int(in.pattern + 0.5);
    if (pt == 9) return float4(applyFog(c, in.dist, u), 1.0);        // emissive: visors, cells, lenses
    float3 col = c * in.shade;
    if (mobGlossy(pt)) {
        float3 n = normalize(cross(dfdx(in.rel), dfdy(in.rel)));
        col += mobSheen(n, in.rel, pt, u.sunDir.xyz, float3(u.params.y)) * saturate(in.shade * 1.3);
    }
    return float4(applyFog(col, in.dist, u), 1.0);
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
    // Glyphs and sprites sample the full-size level (crisp pixel art); block-face icons (layer + 4096) use the mip
    // chain, so a 128 px face shrunk to a ~35 px icon doesn't alias.
    float L = in.layer;
    float4 c;
    if (L >= 4096.0) { c = tex.sample(texSampler, in.uv, uint(L - 4096.0)); }
    else { c = tex.sample(texSampler, in.uv, uint(L), level(0.0)); }
    if (c.a < 0.1) { discard_fragment(); }
    return float4(c.rgb * in.color.rgb, c.a * in.color.a);
}
"""
