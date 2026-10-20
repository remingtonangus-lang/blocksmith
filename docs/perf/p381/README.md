# P381 step 7: full vs adaptive ground, Stone Gulch

Headset-resolution shots (one eye, 2064 x 2208, 104 degree field of view) of the Polygons world over Stone Gulch
(seed 13480747113613945685, eye at 6080, 190, 700 in raw height, about 48 blocks over the town, facing 123 degrees,
15 degrees down: open savanna, the river and the town's roofs), rendered by `questcheck --view` on lavapipe with Quest
settings (`--field --questlod`), the same binary with `BS_ADAPTIVE=0` for the full ground.

- `gulch-view{8,16,24}-full.jpg`: the field ground as the surface nets draw it, a quad per sample cell (and P375's
  far merge past 180 blocks).
- `gulch-view{8,16,24}-adaptive.jpg`: the adaptive ground (Sources/AdaptiveGround.swift): within 0.05 block of the full
  ground both ways near, and a copy within 1/8 block (under one Quest 3 pixel there) for sections 180 blocks or more
  away.

Pixels that differ (both eyes, 9,114,624 pixels):

| view | any difference | by more than 8 of 255 | by more than 32 of 255 |
|---|---|---|---|
| 8 | 1,828,280 (20%) | 80,981 (0.89%) | 7,445 (0.08%) |
| 16 | 2,143,012 (24%) | 98,368 (1.08%) | 8,234 (0.09%) |
| 24 | 2,217,992 (24%) | 109,463 (1.20%) | 10,104 (0.11%) |

The differences are shading, not shape: a big triangle interpolates its corners' light and normals across ground the
full mesh shaded vertex by vertex, so slopes come out a level or two of 255 brighter or darker in patches (most
differing pixels differ by 1-8). The larger ones are along the river's bank, where the water's drawn surface follows
the ground. At 1:1 zoom the pairs can't be told apart by eye. JPEG encoding adds its own tiny differences.

Quads and lavapipe frame time for these shots (both eyes):

| view | full | adaptive | lavapipe frame |
|---|---|---|---|
| 8 | 146,141 | 115,823 (-21%) | 539 -> 373 ms |
| 16 | 598,441 | 469,823 (-21%) | 713 -> 556 ms |
| 24 | 1,576,541 | 1,269,637 (-19%) | 1,343 -> 1,043 ms |
