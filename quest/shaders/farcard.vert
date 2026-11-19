#version 450
#include "common.glsl"
// Ledger 362: a far tree as a picture of the real tree (Sources/FarSprites.swift, FarForest.emitCards). One quad a
// tree, turned about the trunk to face the eye. Push constants as far.vert (m[0].xyz the ring origin relative to the
// head, m[1] the loaded disc); extra.x the pictures' size in pixels.
// Vertex: pos.xyz the tree's foot from the ring origin; pos.w packs the corner (0...3), the tree's own quarter turn
// (x4), the frame's side (x16) and its centre's height over the foot (x4096), both in quarter blocks; color = (the
// set's first layer, the tint: the column's foliage colour over the pictures', 1 for a kind with its own colour).
// The level pictures were taken from 20, 110, 200 and 290 degrees round the trunk; from more than 24 degrees above,
// the two pictures taken from 40 degrees up show (20 and 200), on a card tilted to face that way.
layout(push_constant) uniform Push { mat4 m; vec4 extra; } pc;
layout(location = 0) in vec4 pos;
layout(location = 1) in vec4 color;
layout(location = 0) out vec3 oUVL;
layout(location = 1) out vec4 oLit;      // rgb the light now over the light the pictures were taken in, a the fade
layout(location = 2) out vec4 oFog;      // rgb the fog's colour toward the tree, a its share
void main() {
    float wq = floor(pos.w + 0.5);
    int corner = int(mod(wq, 4.0));
    float turn = mod(floor(wq / 4.0), 4.0);
    float side = mod(floor(wq / 16.0), 256.0) * 0.25;
    float rise = floor(wq / 4096.0) * 0.25;
    vec3 foot = pos.xyz + pc.m[0].xyz;
    vec3 c = foot + vec3(0.0, rise, 0.0);
    float hd = max(0.001, length(c.xz));
    vec2 h = -c.xz / hd;                                   // from the tree toward the eye, level
    float elev = atan(-c.y, hd);
    float ang = degrees(atan(h.x, h.y)) - 20.0;
    vec2 q = vec2((corner == 1 || corner == 2) ? 1.0 : -1.0, corner >= 2 ? 1.0 : -1.0);
    vec3 right = vec3(h.y, 0.0, -h.x);
    vec3 up = vec3(0.0, 1.0, 0.0);
    float layer;
    if (elev > radians(24.0)) {
        float k = mod(floor(ang / 180.0 + 0.5) + floor(turn * 0.5), 2.0);
        layer = color.x + 4.0 + k;
        float t = radians(40.0);
        up = vec3(-h.x * sin(t), cos(t), -h.y * sin(t));
    } else {
        float k = mod(floor(ang / 90.0 + 0.5) + turn, 4.0);
        layer = color.x + k;
    }
    vec3 rel = c + right * (q.x * side * 0.5) + up * (q.y * side * 0.5);
    // Under the loaded chunks the real trees stand: no card there (the fragment stage fades the rim in).
    float d = length(foot.xz - pc.m[1].xy);
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(rel, 1.0);
    if (d < pc.m[1].z - 20.0) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); }
    float e = 0.5 / pc.extra.x;
    oUVL = vec3(mix(e, 1.0 - e, q.x * 0.5 + 0.5), mix(e, 1.0 - e, 0.5 - q.y * 0.5), layer);

    float day = u.params.y;
    vec3 skyTint = mix(vec3(0.6, 0.7, 1.0), vec3(1.0), smoothstep(0.30, 0.62, day));
    vec3 lit = max(day * skyTint, vec3(0.055));
    lit = mix(lit, vec3(1.0), u.sunDir.w);
    // (the pictures were taken at noon, light 1; a tinted kind takes its own column's foliage colour over the pictures')
    lit *= color.yzw;
    oLit = vec4(lit, smoothstep(pc.m[1].z - 20.0, pc.m[1].z + 4.0, d));
    float dist = length(c);
    oFog = vec4(filmic(fogColorAlong(c)), fogAmount(dist));
}
