#version 450
layout(set = 0, binding = 1) uniform sampler2DArray tex;
layout(location = 0) in vec2 oUV;
layout(location = 1) in vec4 oColor;
layout(location = 2) flat in float oLayer;
layout(location = 0) out vec4 outColor;
// common.glsl sharpUV (this shader doesn't include common.glsl): the texture array magnifies LINEAR, so glyphs and
// icons keep crisp texel edges, anti-aliased over about one panel pixel.
vec2 sharpUV(vec2 uv) {
    vec2 sz = vec2(textureSize(tex, 0).xy);
    vec2 t = uv * sz;
    vec2 seam = floor(t + 0.5);
    vec2 d = clamp(fwidth(t), vec2(1e-4), vec2(1.0));
    return (seam + clamp((t - seam) / d, -0.5, 0.5)) / sz;
}
void main() {
    if (oLayer < 0.0) { outColor = oColor; return; }
    float L = oLayer;
    vec4 c;
    if (L >= 4096.0) { c = texture(tex, vec3(sharpUV(oUV), L - 4096.0)); }
    else { c = textureLod(tex, vec3(sharpUV(oUV), L), 0.0); }
    if (c.a < 0.1) { discard; }
    outColor = vec4(c.rgb * oColor.rgb, c.a * oColor.a);
}
