# P375 / P376 step 7: full vs merged far ground, Stone Gulch

Headset-resolution shots (one eye, 2064 x 2208, 104 degree field of view) of the Polygons world at Stone Gulch
(seed 13480747113613945685, eye 28 blocks over 6094.4, 688.6, facing 123 degrees, 8 degrees down), rendered by
`questcheck --view` on lavapipe with Quest settings (`--field --questlod --pixelpair`).

- `gulch-view{8,16,24}-full.jpg`: every far section draws its full mesh.
- `gulch-view{8,16,24}-merged.jpg`: sections at least 180 blocks away draw the merged ground copy (GroundMerge,
  1/8 block of error, under one Quest 3 pixel there).

Pixels that differ between full and merged: 0 at view 8, 475 at view 16, 788 at view 24 (of 9.1M; single pixels on
the far horizon). JPEG encoding adds its own tiny differences, so the files themselves are not byte-identical.
