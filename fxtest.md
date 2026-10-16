# World fx checks (material damage and weather)


## cracks
- PASS: stone at level 3 is whole (cracks only)
- PASS: stone at level 6 is chipped
- PASS: iron never chips (dents)
- PASS: steel plating never chips (dents)
- PASS: oak planks chip as before
- PASS: damage decals are drawn (130 decal quads)
- PASS: crack, dent and scorch decals all present (cracks 52, dents 63, scorch 15)
- frame with 130 decal quads: 13.12 ms
- PASS: glass shatters at the third crack
- PASS: glass leaves shard particles
- PASS: a blast leaves soot round its crater (82 blocks)
- scene cracks took 1.8 s

## fire
- 125 fire ticks: peak 16 burning, charred 24, burned away 30, spreads downwind 12 / upwind 2, tick mean 0.094 ms, worst 1.476 ms
- frame while the house burns: 4.95 ms
- PASS: the house catches fire (peak 16)
- PASS: wood scorches before it burns (92 scorched)
- PASS: wood chars to charcoal (9 charcoal blocks, 24 charred)
- PASS: fire spreads with the wind (downwind 12, upwind 2)
- PASS: fire tick stays cheap (worst 1.476 ms)
- PASS: lightning sets the struck tree alight (1 fires)
- plank field: 1340 burning (cap 1500), capped spreads 0, tick mean 2.396 ms, worst 4.011 ms
- PASS: burning cells stay under the cap (1340)
- PASS: fire tick at the cap stays bounded (worst 4.011 ms)
- scene fire took 2.5 s

## flood
- 1142 of the flood blocks are shoreline (half height)
- after 10 min of heavy rain: 10266 flood blocks (717 at 5 min), 789 cells flooded, deepest 10.59, model step worst 1.69 ms, frame 6.72 ms
- PASS: heavy rain floods the low ground (10266 blocks)
- PASS: the flood rises while it rains (717 -> 10266)
- PASS: no flood water hangs in the air (0)
- PASS: the fluid sim leaves flood water alone (0 of 400 changed)
- PASS: flood shorelines are sloped, not walls (105 full sources beside air (1.0%))
- the hut site stayed dry (0 flood blocks round it): sealed-room oracle not exercised
- PASS: no shoreline grooves inside the flood (3 half-height blocks with nothing open beside them)
- PASS: flood model step stays cheap (worst 1.69 ms)
- PASS: a reloaded flood is recognised (9544 of 10266 blocks adopted)
- receding: 10266 -> 592 after 15 min -> 172 after 30 min
- PASS: the flood recedes after the rain (10266 -> 172)
- scene flood took 2.8 s

## snow
- PASS: snow drifts are smooth enough to walk (0 of 1271 neighbour pairs differ by more than 3 layers)
- PASS: snow doesn't bury a standing cow's feet (2 layers under it)
- PASS: no rain under a glass roof (under: false, on top: true)
- PASS: snow settles on a glass roof, not under it (25 of 25 roof blocks snowed on, 0 floor columns under it grew)
- PASS: deep snow drops snowballs (2 from 5 layers)
- snow depth (layers, mean over 625 columns): 0.98 -> 4.11 after 4 min of snow -> 0.99 after 10 min of sun; 274708 block writes; 5678 chunk passes: mean 0.046 ms, p95 0.083 ms, worst 1.21 ms
- PASS: snow piles up in layers while it snows (0.98 -> 4.11)
- PASS: snow melts back after the storm (4.11 -> 0.99)
- PASS: snow chunk pass stays cheap (p95 0.083 ms, worst 1.21 ms)
- scene snow took 1.5 s

## storm
- PASS: the ship rolls back and forth (not just listing) (tilt 2.1-11.4 deg)
- gunboat: max tilt 1.2 deg calm, 11.4 deg in the storm (swell 1.30), lowest 126.49 vs start 127.04, upright 1.00, ship step worst 0.42 ms
- PASS: a storm rolls and pitches the ship (11.4 vs 1.2 deg)
- PASS: the ship rides it out (afloat, not capsized) (up 1.00)
- lightning on the gunboat: 129 -> 126 hull blocks
- PASS: lightning bursts on a ship's hull (129 -> 126)
- storm frame: 8.33 ms
- scene storm took 0.6 s

## wildfire
- dry storm, 4 min: 22 strikes, 29 burning (peak 942, cap 1500), 529 burned away, 158 charred; 10 min later 7 burning; fire tick p95 0.151 ms, worst 3.806 ms; frame 6.37 ms
- PASS: dry lightning strikes in dry country (22)
- PASS: dry lightning starts fires (peak 942)
- PASS: a wildfire stays under the burning-cell cap (peak 942)
- PASS: fire tick stays cheap under a wildfire (p95 0.151 ms)
- scene wildfire took 1.3 s

## shallows
- PASS: the water surface runs over plants in shallow water (0 of 41 plant cells without a surface)
- scene shallows took 0.3 s