# Reference-quality spec (blind critic target)

The bar: a polished commercial voxel game on a 1080p TV, better looking than the classic genre reference at the
same view. Critics score each axis 0-10 (10 = indistinguishable from a shipped commercial game at that view;
8 = a player would accept it as shipped; 5 = good indie; 2 = prototype) against these lines. Ranges, not points.
Each line names how to measure it on a CI snapshot (1280x800 unless noted). Critics may add gaps they observe but
may not contradict a line unless they measure the opposite on the image.

| # | Axis | Target | Measure |
|---|---|---|---|
| 1 | Texture detail | blocks within 8 m show detail finer than 1/16 block (target 128 px per block face); no visible 16-px stair-stepping on edges of features | crop a block face 1-3 m away; count distinct features across it |
| 2 | Texture coherence | one art style: shared palette families per material (stone greys, wood browns), no single block 2x more saturated than its neighbours | sample mean HSV of 10 block types in a scene |
| 3 | Distance stability | no moire / shimmer: textures beyond 32 m average to their material colour | two frames 1 tick apart: per-pixel difference in distant terrain < 4/255 on average |
| 4 | Lighting | noon scene: shadowed areas 25-45 % of sunlit luminance; caves readable with torches within 8 m (no pure black where a torch is in view) | luminance histogram of sun vs shade regions |
| 5 | Atmosphere | horizon fog colour matches the sky band within 10 % luminance; no visible chunk edge or LOD seam | inspect the horizon row band; seam search |
| 6 | Water | surface reads as water at every distance (no see-through holes to the sky, no z-fighting) | tour_* aerial and seabed shots |
| 7 | Structures | doors at the floor level, interiors lit, nothing floating or buried; villages read as places | interior shots + structcheck counts (0 door_step, 0 floating) |
| 8 | Mobs | grounded (no hovering > 0.1 block, no sinking into blocks), facing their movement | mobs / village shots |
| 9 | UI / HUD | HUD text >= 14 px at 1080p (gstack-game visual thresholds), icons crisp (no blurred upscale), hotbar icons readable at TV distance | measure glyph heights; icon edge sharpness |
| 10 | Night | moonlit terrain readable (mean luminance 6-14 % of noon), stars not aliased | night tour shots |

## Resolved contradictions
- Detail (1) vs stability (3): both hold through mipmaps + anisotropic filtering: detail up close, averaged far away.

## Unmeasurable on stills
- Motion feel, animation quality, input latency: judged from bot replays and frame sequences, not single PNGs.
