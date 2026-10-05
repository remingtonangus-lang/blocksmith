# World fx checks (material damage and weather)


## cracks
- PASS: stone at level 3 is whole (cracks only)
- PASS: stone at level 6 is chipped
- PASS: iron never chips (dents)
- PASS: steel plating never chips (dents)
- PASS: oak planks chip as before
- PASS: damage decals are drawn (130 decal quads)
- PASS: crack, dent and scorch decals all present (cracks 52, dents 63, scorch 15)
- frame with 130 decal quads: 4.52 ms
- PASS: glass shatters at the third crack
- PASS: glass leaves shard particles
- PASS: a blast leaves soot round its crater (75 blocks)
- scene cracks took 1.1 s

## fire
- 125 fire ticks: peak 158 burning, charred 94, burned away 163, spreads downwind 238 / upwind 56, tick mean 0.030 ms, worst 2.785 ms
- frame while the house burns: 4.87 ms
- PASS: the house catches fire (peak 158)
- PASS: wood scorches before it burns (78 scorched)
- PASS: wood chars to charcoal (6 charcoal blocks, 94 charred)
- PASS: fire spreads with the wind (downwind 238, upwind 56)
- PASS: fire tick stays cheap (worst 2.785 ms)
- PASS: lightning sets the struck tree alight (1 fires)
- plank field: 1500 burning (cap 1500), capped spreads 12792, tick mean 1.690 ms, worst 2.108 ms
- PASS: burning cells stay under the cap (1500)
- PASS: fire tick at the cap stays bounded (worst 2.108 ms)
- scene fire took 1.9 s

## flood
- 1119 of the flood blocks are shoreline (half height)
- after 10 min of heavy rain: 10231 flood blocks (749 at 5 min), 784 cells flooded, deepest 10.59, model step worst 1.10 ms, frame 5.37 ms
- PASS: heavy rain floods the low ground (10231 blocks)
- PASS: the flood rises while it rains (749 -> 10231)
- PASS: no flood water hangs in the air (0)
- PASS: the fluid sim leaves flood water alone (0 of 400 changed)
- PASS: flood shorelines are sloped, not walls (110 full sources beside air (1.1%))
- PASS: a sealed hut stays dry inside (0 flood blocks inside, 95 round it)
- PASS: no shoreline grooves inside the flood (0 half-height blocks with nothing open beside them)
- PASS: flood model step stays cheap (worst 1.10 ms)
- PASS: a reloaded flood is recognised (9552 of 10231 blocks adopted)
- receding: 10231 -> 597 after 15 min -> 172 after 30 min
- PASS: the flood recedes after the rain (10231 -> 172)
- scene flood took 2.2 s

## snow
- PASS: snow drifts are smooth enough to walk (0 of 1277 neighbour pairs differ by more than 3 layers)
- PASS: snow doesn't bury a standing cow's feet (2 layers under it)
- PASS: no rain under a glass roof (under: false, on top: true)
- PASS: snow settles on a glass roof, not under it (25 of 25 roof blocks snowed on, 0 floor columns under it grew)
- PASS: deep snow drops snowballs (2 from 5 layers)
- snow depth (layers, mean over 625 columns): 0.98 -> 4.16 after 4 min of snow -> 0.99 after 10 min of sun; 274935 block writes; 5678 chunk passes: mean 0.049 ms, p95 0.091 ms, worst 1.07 ms
- PASS: snow piles up in layers while it snows (0.98 -> 4.16)
- PASS: snow melts back after the storm (4.16 -> 0.99)
- PASS: snow chunk pass stays cheap (p95 0.091 ms, worst 1.07 ms)
- scene snow took 1.5 s

## storm
- PASS: the ship rolls back and forth (not just listing) (tilt 2.1-11.4 deg)
- gunboat: max tilt 1.2 deg calm, 11.4 deg in the storm (swell 1.30), lowest 126.49 vs start 127.04, upright 1.00, ship step worst 0.15 ms
- PASS: a storm rolls and pitches the ship (11.4 vs 1.2 deg)
- PASS: the ship rides it out (afloat, not capsized) (up 1.00)
- lightning on the gunboat: 129 -> 126 hull blocks
- PASS: lightning bursts on a ship's hull (129 -> 126)
- storm frame: 8.55 ms
- scene storm took 0.7 s

## wildfire
- dry storm, 4 min: 21 strikes, 106 burning (peak 1146, cap 1500), 6664 burned away, 456 charred; 10 min later 143 burning; fire tick p95 0.656 ms, worst 4.131 ms; frame 5.16 ms
- PASS: dry lightning strikes in dry country (21)
- PASS: dry lightning starts fires (peak 1146)
- PASS: a wildfire stays under the burning-cell cap (peak 1146)
- PASS: fire tick stays cheap under a wildfire (p95 0.656 ms)
- scene wildfire took 1.2 s

## shallows
- PASS: the water surface runs over plants in shallow water (0 of 41 plant cells without a surface)
- scene shallows took 0.3 s