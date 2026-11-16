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
    if (d.y <= 0.004 || hu <= 0.0) { discard; }
    vec2 q = (u.clouds.xy - pc.extra.xy) + d.xz * (hu / d.y);
    float ql = length(q);
    float t = atan(ql, pc.extra.z) / 1.5707963;                  // zenith angle of the deck point from the map's origin, 0...1
    vec2 m = q * ((1.0 - sqrt(max(1.0 - t, 0.0))) / max(ql, 1e-5));
    vec4 c = textureLod(cloudMap, m * 0.5 + 0.5, 0.0);
    if (c.a < 0.003) { discard; }
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    outColor = finalColor(vec4(c.rgb / c.a + (ign - 0.5) / 255.0, c.a));
}
