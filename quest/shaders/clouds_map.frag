#version 450
#define BS_CLOUDS 1
#include "common.glsl"
// The clouds read from the cloud map (cloudbake.frag): the deck point this pixel's ray meets, as a direction from the
// map's origin. Same picture as clouds.frag within the map's resolution; one texture read.
layout(set = 2, binding = 0) uniform sampler2D cloudMap;
layout(push_constant) uniform Push { mat4 model; vec4 extra; } pc;
layout(location = 0) in vec2 oNdc;
layout(location = 0) out vec4 outColor;
void main() {
    vec4 w = u.invViewProj[gl_ViewIndex] * vec4(oNdc, 1.0, 1.0);
    vec3 d = normalize(w.xyz / w.w);
    float hu = CUMULUS_Y - u.eye.y;
    // (worked out for every pixel before any is discarded: the footprint below needs its neighbours' values)
    vec2 q = (u.clouds.xy - pc.extra.xy) + d.xz * (hu / max(d.y, 0.004));
    float ql = length(q);
    float t = atan(ql, pc.extra.z) / 1.5707963;                  // zenith angle of the deck point from the map's origin, 0...1
    vec2 m = q * ((1.0 - sqrt(max(1.0 - t, 0.0))) / max(ql, 1e-5));
    vec2 uv = m * 0.5 + 0.5;
    // The map's rows crowd toward the horizon (several texels to a screen pixel in the last degrees, more from high
    // up where the horizon is open, and many more in a small picture): one read there picked one texel of several and
    // the far clouds broke into speckles that crawl as the eye moves. Where a pixel covers more than one texel it
    // reads up to four across each way and takes their mean (the map holds colour times cover, so a mean is right).
    vec2 du = dFdx(uv), dv = dFdy(uv);
    float sz = float(textureSize(cloudMap, 0).x);
    if (d.y <= 0.004 || hu <= 0.0) { discard; }
    int nx = int(clamp(ceil(length(du) * sz * 0.75), 1.0, 4.0));
    int ny = int(clamp(ceil(length(dv) * sz * 0.75), 1.0, 4.0));
    vec4 c = vec4(0.0);
    if (nx * ny == 1) { c = textureLod(cloudMap, uv, 0.0); }
    else {
        for (int i = 0; i < nx; i++) {
            for (int j = 0; j < ny; j++) {
                vec2 o = du * ((float(i) + 0.5) / float(nx) - 0.5) + dv * ((float(j) + 0.5) / float(ny) - 0.5);
                c += textureLod(cloudMap, uv + o, 0.0);
            }
        }
        c /= float(nx * ny);
    }
    if (c.a < 0.003) { discard; }
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    outColor = finalColor(vec4(c.rgb / c.a + (ign - 0.5) / 255.0, c.a));
}
