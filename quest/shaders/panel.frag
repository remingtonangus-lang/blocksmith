#version 450
layout(set = 2, binding = 0) uniform sampler2D panel;
layout(push_constant) uniform Push { mat4 model; vec4 extra; } pc;
layout(location = 0) in vec2 oUV;
layout(location = 0) out vec4 outColor;
void main() {
    vec4 c = texture(panel, oUV);
    outColor = vec4(c.rgb, c.a * pc.extra.x);
}
