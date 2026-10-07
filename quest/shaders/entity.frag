#version 450
#include "common.glsl"
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec4 oColor;
layout(location = 3) in float oDist;
layout(location = 4) flat in float oOverlay;
layout(location = 0) out vec4 outColor;
void main() {
    // Near the eye (the held tool, items in hand reach) the pixel art is sampled texel-exact from the top mip: the
    // linear min filter + mip blend smeared a 16x16 sprite seen at arm's length (Quest round 3: blurry tools).
    vec4 c;
    if (oDist < 4.0) {
        vec2 sz = vec2(textureSize(tex, 0).xy);
        c = textureLod(tex, vec3((floor(oUV * sz) + 0.5) / sz, oLayer), 0.0);
    } else {
        c = texture(tex, vec3(oUV, oLayer));
    }
    if (c.a < 0.5) { discard; }
    vec3 rgb = c.rgb;
    if (oOverlay > 0.5 && c.a < 0.95) { rgb *= vec3(0.57, 0.74, 0.35); }
    outColor = finalColor(vec4(applyFog(rgb * oColor.rgb, oDist), 1.0));
}
