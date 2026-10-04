#version 450
// The Mac HUD's pixel-space quads (Renderer.buildHUD) drawn into the panel image (no multiview).
layout(push_constant) uniform Push { vec4 screen; } pc;
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;
layout(location = 3) in vec4 extra;
layout(location = 0) out vec2 oUV;
layout(location = 1) out vec4 oColor;
layout(location = 2) flat out float oLayer;
void main() {
    gl_Position = vec4(pos.x / pc.screen.x * 2.0 - 1.0, pos.y / pc.screen.y * 2.0 - 1.0, 0.0, 1.0);
    oUV = uv;
    oColor = color;
    oLayer = extra.x;
}
