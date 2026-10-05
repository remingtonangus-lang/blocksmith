#version 450
#include "common.glsl"
layout(location = 0) in vec2 oUV;
layout(location = 1) flat in float oLayer;
layout(location = 2) in vec3 oShade;
layout(location = 3) in vec3 oTint;
layout(location = 4) flat in float oOverlay;
layout(location = 5) flat in float oAnim;
layout(location = 6) in float oDist;
layout(location = 7) in vec3 oRel;
layout(location = 8) flat in float oFace;
layout(location = 0) out vec4 outColor;
void main() {
    float t = u.params.z;
    vec2 uv = oUV + vec2(t * 0.03, t * 0.017);
    vec4 c = texture(tex, vec3(uv, oLayer));
    vec3 rgb = c.rgb * oTint * max(oShade, vec3(0.05));
    float a = c.a;
    if (oFace < 2.5 && oFace > 1.5 && u.params.w < 0.5) {
        // Water surface: grazing views reflect more sky (Fresnel) and ripples catch a sun glint.
        vec3 vdir = normalize(oRel);
        vec3 wp = oRel + u.eye.xyz;
        vec2 rip = vec2(sin(wp.x * 1.7 + wp.z * 0.9 + t * 1.6), sin(wp.z * 2.1 - wp.x * 0.7 + t * 1.3)) * 0.06;
        vec3 n = normalize(vec3(rip.x, 1.0, rip.y));
        float fres = pow(1.0 - clamp(-vdir.y, 0.0, 1.0), 3.0);
        float lit = max(oShade.x, max(oShade.y, oShade.z));
        rgb = mix(rgb, u.fogColor.rgb * (0.6 + 0.4 * lit), fres * 0.45);
        vec3 r = reflect(vdir, n);
        float spec = pow(clamp(dot(r, normalize(u.sunDir.xyz)), 0.0, 1.0), 180.0) * u.params.y * lit;
        rgb += vec3(1.0, 0.95, 0.8) * spec * 0.9;
        a = mix(a, 1.0, fres * 0.55);
    }
    float f = smoothstep(u.fogColor.w, u.params.x, oDist);
    // The sRGB swapchain blends in linear light, which makes gamma-authored translucent water read darker and more
    // opaque than the Mac's gamma-space blend: keep its alpha lower and its colour lifted to match the earlier look.
    float lin = u.misc.z > 1.5 ? 1.0 : 0.0;
    vec3 col = mix(rgb, fogColorAlong(oRel), f);
    col = pow(max(col, vec3(0.0)), vec3(mix(1.0, 0.85, lin)));
    float alpha = mix(a, 1.0, f * 0.8);
    alpha *= mix(1.0, 0.8, lin * (1.0 - f));
    outColor = finalColor(vec4(col, alpha));
}
