// Shared by every Quest shader (prepended by quest/tools/shaders.py). Ports of the Mac's Fast-path Metal shaders
// (Sources/Shaders.swift); both eyes render in one pass (multiview: gl_ViewIndex picks the eye's matrices).
#extension GL_EXT_multiview : require

layout(set = 0, binding = 0, std140) uniform Frame {
    mat4 viewProj[2];      // per eye, camera-relative (the head centre is the origin)
    mat4 invViewProj[2];
    vec4 fogColor;         // rgb, w = fog start
    vec4 params;           // x = fog end, y = daylight, z = time (s), w = underwater
    vec4 sunDir;           // xyz, w = dimension ambient
    vec4 eye;              // xyz = head centre (world), w = fog glow toward the sun (0 = none)
    vec4 zenith;           // sky: rgb zenith, w = sky angle
    vec4 horizon;          // sky: rgb horizon (= fog), w = sun glow
    mat4 starRot;
    vec4 starTint;
    vec4 misc;             // x = sky kind (0 none, 1 overworld dome, 2 hollow), y = panel alpha, z = output gamma (2.2 sRGB target)
} u;

layout(set = 0, binding = 1) uniform sampler2DArray tex;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + vec2(1, 0)), c = hash21(i + vec2(0, 1)), d = hash21(i + vec2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 applyFog(vec3 c, float dist) {
    float f = smoothstep(u.fogColor.w, u.params.x, dist);
    return mix(c, u.fogColor.rgb, f);
}

vec3 fogColorAlong(vec3 rel) {
    float glow = u.eye.w;
    if (glow <= 0.0) { return u.fogColor.rgb; }
    float sd = clamp(dot(normalize(rel), normalize(u.sunDir.xyz)), 0.0, 1.0);
    return u.fogColor.rgb + vec3(1.0, 0.55, 0.25) * pow(sd, 5.0) * glow;
}

vec3 applyFogDir(vec3 c, vec3 rel, float dist) {
    float f = smoothstep(u.fogColor.w, u.params.x, dist);
    return mix(c, fogColorAlong(rel), f);
}

vec3 waterAmbient(vec3 lit, vec3 albedo) {
    return u.params.w > 0.5 ? max(lit, albedo * u.fogColor.rgb * 2.2) : lit;
}

vec3 lavaGlow(vec3 c, vec3 rel) {
    vec2 w = (rel + u.eye.xyz).xz;
    float t = u.params.z;
    float n = vnoise(w * 0.45 + vec2(t * 0.11, t * 0.07)) * 0.65 + vnoise(w * 1.3 - vec2(t * 0.05, t * 0.13)) * 0.35;
    return c * (0.78 + 0.5 * n) + vec3(0.12, 0.05, 0.0) * smoothstep(0.62, 0.9, n);
}

// Every world shader computes display (gamma-space) colours like the Mac; an sRGB swapchain stores linear values.
vec4 finalColor(vec4 c) { return vec4(pow(max(c.rgb, vec3(0.0)), vec3(u.misc.z)), c.a); }
