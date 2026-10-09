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
    vec4 misc;             // x = sky kind (0 none, 1 overworld dome, 2 hollow), y = eye darkness (cave fill weight),
                           // z = output gamma (2.2 sRGB target), w = Brightness
    vec4 waves;            // x = ocean swell scale (calm 0.6, thunderstorm 5: Weather.swell), y = rain (drop rings)
} u;

layout(set = 0, binding = 1) uniform sampler2DArray tex;

// Ocean swell (chunk.vert moves sea-level water surfaces by it, water.frag tilts the surface normal by its slope):
// three sines (~11, 7 and 4.5 m long, 14 cm at the crest), times the weather's swell scale (u.waves.x; Sources/Weather.swift OceanSwell
// mirrors it for boats). xyz = height, d/dx, d/dz at world xz.
vec3 oceanWave1(vec2 w, float t) {
    float a1 = w.x * 0.50 + w.y * 0.27 + t * 1.8;
    float a2 = w.y * 0.82 - w.x * 0.36 + t * 2.3;
    float a3 = w.x * 1.08 - w.y * 0.88 + t * 2.9;
    float h = sin(a1) * 0.07 + sin(a2) * 0.045 + sin(a3) * 0.025;
    float dx = cos(a1) * 0.07 * 0.50 - cos(a2) * 0.045 * 0.36 + cos(a3) * 0.025 * 1.08;
    float dz = cos(a1) * 0.07 * 0.27 + cos(a2) * 0.045 * 0.82 - cos(a3) * 0.025 * 0.88;
    return vec3(h, dx, dz);
}
vec3 oceanWave(vec2 w, float t) { return oceanWave1(w, t) * u.waves.x; }

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

// Round 3 lighting (same maths as Sources/Shaders.swift sunShade/filmic): sky-lit faces in daylight blend the fixed
// face shade toward a cool sky ambient + warm sun diffuse (golden near the horizon), weight w (0...0.85). Per vertex.
vec3 sunShadeN(vec3 n, float base, float w, vec3 sd) {
    if (w <= 0.0) { return vec3(base); }
    vec3 l = normalize(sd);
    float g = clamp(l.y * 2.2, 0.0, 1.0);
    vec3 sunC = mix(vec3(1.22, 0.80, 0.48), vec3(1.04, 1.0, 0.93), g);
    vec3 d = vec3(0.86, 0.93, 1.06) * 0.66 + sunC * (0.46 * clamp(dot(n, l), 0.0, 1.0));
    return mix(vec3(base), d, w);
}
vec3 faceNormal(uint f) {
    return f == 0u ? vec3(1, 0, 0) : f == 1u ? vec3(-1, 0, 0) : f == 2u ? vec3(0, 1, 0) : f == 3u ? vec3(0, -1, 0) : f == 4u ? vec3(0, 0, 1) : vec3(0, 0, -1);
}
// Cheap filmic curve for world surfaces (not HUD/panels): soft shoulder above 0.9, highlight lift above mid-grey
// (shadows and 0.5 untouched), saturation 1.08. ~14 ALU per fragment.
vec3 filmic(vec3 c) {
    c = max(c, vec3(0.0));
    vec3 hi = 0.9 + 0.1 * (1.0 - exp((0.9 - c) * 10.0));
    c = mix(c, hi, step(vec3(0.9), c));
    c = c + 0.25 * c * (1.0 - c) * max(2.0 * c - 1.0, 0.0);
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return max(l + (c - l) * 1.08, vec3(0.0));
}
vec4 worldColor(vec4 c) { return finalColor(vec4(filmic(c.rgb), c.a)); }
