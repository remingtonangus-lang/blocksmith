#version 450
layout(set = 0, binding = 1) uniform sampler2DArray tex;
layout(location = 0) in vec2 oUV;
layout(location = 1) in vec4 oColor;
layout(location = 2) flat in float oLayer;
layout(location = 0) out vec4 outColor;
void main() {
    if (oLayer < 0.0) { outColor = oColor; return; }
    float L = oLayer;
    vec4 c;
    if (L >= 4096.0) { c = texture(tex, vec3(oUV, L - 4096.0)); }
    else { c = textureLod(tex, vec3(oUV, L), 0.0); }
    if (c.a < 0.1) { discard; }
    outColor = vec4(c.rgb * oColor.rgb, c.a * oColor.a);
}
