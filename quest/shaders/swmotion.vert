#version 450
#include "common.glsl"
// P403 7b (Application SpaceWarp on by default): the motion vectors of things that move on their own (the hands and
// what they hold, mobs, ships), drawn again into the motion-vector image after the depth copy. pos is the vertex as the
// scene drew it (camera-relative, mob / entity / simple vertices all start with it); pc.m maps it to where that point
// was at the last drawn frame, in the same camera-relative world terms. Both go through this frame's view, so the
// head's own motion stays out (the runtime takes it from the poses and the app space's delta).
layout(push_constant) uniform Push { mat4 m; vec4 extra; } pc;
layout(location = 0) in vec4 pos;
layout(location = 0) out vec4 oCur;
layout(location = 1) out vec4 oPrev;
void main() {
    // Pulled 2 % toward the head so the depth test against the copied scene depth (drawn at full size, read at the
    // runtime's smaller size) keeps the object's own pixels and nothing behind a nearer surface.
    vec4 cur = u.viewProj[gl_ViewIndex] * vec4(pos.xyz, 1.0);
    oCur = cur;
    oPrev = u.viewProj[gl_ViewIndex] * vec4((pc.m * vec4(pos.xyz, 1.0)).xyz, 1.0);
    gl_Position = u.viewProj[gl_ViewIndex] * vec4(pos.xyz * 0.98, 1.0);
}
