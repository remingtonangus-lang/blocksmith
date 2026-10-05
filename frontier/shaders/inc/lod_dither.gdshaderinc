// Screen-space dither shared by the near tree meshes (shaders/foliage.gdshader) and their impostors
// (shaders/impostor_tree.gdshader). Both use the same threshold per pixel, so a mesh fading out with
// `lod_dither(FRAGCOORD.xy) < t` and an impostor fading in with `lod_dither(FRAGCOORD.xy) < t` are exact
// complements: during the hand-off every pixel shows one or the other, never both and never neither.
float lod_dither(vec2 frag) {
	// interleaved gradient noise (Jimenez 2014): stable per pixel, no visible grid at 1:1
	return fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
}

// Main-camera position, also inside shadow passes (where CAMERA_POSITION_WORLD is the light's camera).
// Use in vertex() only.
#define LOD_CAMERA_POS (MAIN_CAM_INV_VIEW_MATRIX[3].xyz)
