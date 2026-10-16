#version 450
#include "common.glsl"
// F4 middle ring (Sources/FarRing.swift): low-poly ground past the loaded chunks at its true position, lit like a
// sky-lit top face (chunk.vert at full skylight) and fogged per vertex with the terrain's own fog, so the loaded
// edge has no seam in colour or haze. Drawn with simple.frag (gamma out).
// Push constants: m[0].xyz = ring origin relative to the head; m[1] = (loaded disc centre x, z relative to the head,
// loaded radius in blocks, sink depth). Vertex: pos.xyz from the ring origin, pos.w = normal x, z (10 bits each);
// color.rgb = ground / water colour, color.a = kind (0 ground, 1 water, 2 lava).
layout(push_constant) uniform Push { mat4 m; vec4 extra; } pc;
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 oColor;
void main() {
    vec3 rel = pos.xyz + pc.m[0].xyz;
    // Inside the loaded disc the real chunks draw the ground: sunk out of sight there, and just under the true height
    // in the band at the disc's edge (the overlap that keeps the seam closed).
    float d = length(rel.xz - pc.m[1].xy);
    float inside = 1.0 - smoothstep(pc.m[1].z - 24.0, pc.m[1].z, d);
    rel.y -= 2.0 + pc.m[1].w * inside;
    // P327 (b): well inside the disc it goes far under everything, so a pit or crater dug deeper than the sink never
    // shows the ring's green ground as a sheen across it.
    rel.y -= 4000.0 * (1.0 - smoothstep(pc.m[1].z - 72.0, pc.m[1].z - 40.0, d));
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(rel, 1.0);

    float q = pos.w;
    float qz = floor(q / 1024.0);
    float qx = q - qz * 1024.0;
    vec2 nxz = vec2(qx, qz) / 1023.0 * 2.0 - 1.0;
    vec3 n = vec3(nxz.x, sqrt(max(0.0, 1.0 - dot(nxz, nxz))), nxz.y);

    float day = u.params.y;
    vec3 skyTint = mix(vec3(0.6, 0.7, 1.0), vec3(1.0), smoothstep(0.30, 0.62, u.params.y));
    vec3 lit = max(day * skyTint, vec3(0.055));
    lit = mix(lit, vec3(1.0), u.sunDir.w);
    float dist = length(rel);
    vec3 c;
    if (color.a > 1.5) {
        c = color.rgb;                                           // crater lava glows
    } else if (color.a > 0.5) {
        // Far deep water as water.frag draws it past the bed (transmittance 0): the mirrored sky by Fresnel over the
        // water's own colour.
        float l = max(lit.x, max(lit.y, lit.z));
        vec3 deep = (color.rgb * 0.38 + vec3(0.03, 0.05, 0.04)) * (l + 0.04);
        vec3 v = rel / max(dist, 1e-3);
        float cosT = clamp(-v.y, 0.0, 1.0);
        float fres = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
        float h = clamp(-v.y * 1.25, 0.0, 1.0);
        h = h * h * (3.0 - 2.0 * h);
        vec3 refl = mix(fogColorAlong(rel), u.fogColor.rgb * vec3(0.45, 0.6, 0.92), h);
        c = refl * fres + deep * (1.0 - fres);
    } else {
        float sw = 0.85 * smoothstep(0.0, 0.45, day) * clamp(day * 4.0 + 0.5, 0.0, 1.0) * (1.0 - u.sunDir.w);
        c = color.rgb * lit * sunShadeN(n, smoothShade(n), sw, u.sunDir.xyz);
    }
    oColor = vec4(filmic(applyFogDir(c, rel, dist)), 1.0);
}
