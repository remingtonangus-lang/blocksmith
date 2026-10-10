# Boreal Station (task 4: Siberia-style military base)

A new snowbound bunker structure, separate from the Capital Citadel (kept as is). The feel is borrowed from the
cold-war bunker levels of 90s shooters: grey concrete corridors, small blue lamps in the corners, steel bulkhead doors,
cold and clean, buried under snow. The layout is original.

## What it is
- Spawns in snowy biomes only (snowy plains, snowy taiga, ice spikes, grove, snowy slopes), spacing 28 chunks,
  never within the yard of a village, temple, outpost, manor, portal ruin, trail ruin, citadel, Capital city or spire.
  Existing worlds: chunks generated before this change are guarded (structure-guard-stations.txt), so no station is
  cut in half by old terrain.
- Surface: a fenced, snow-covered yard with a gatehouse, blockhouse over the stairwell, radar mast, watchtower, fuel
  tanks, shed, plowed road, drifts; a deck gun on the blockhouse roof.
- Bunker (16 below the yard): a two-storey hall with a catwalk and console ring, a ring corridor, and control, archive,
  cells, armory, generator, mess and barracks rooms behind 12 bulkhead doors. Garrison: the existing Capital soldiers,
  loot from the steelhold tables.
- New blocks: Station Concrete (+ stairs/slab, dark band, floor), Steel Railing, Corner Lamp (light 12, blue),
  Data Cabinet, Bulkhead Door. Procedural painters in TextureGen.borealPainters; cool blue-grey so the amber block
  light reads cold.
- Reachable with /locate boreal_station, the pause-menu Shortcuts list, and the world map ("N" marker).

## Checks
- `questcheck` runs `BorealTests` (skip with `--no-boreal`, only it with `--boreal-only`; seeds `--boreal-seeds`).
  Mac: `Blocksmith --borealtest`. Per seed: station near spawn, structcheck clean, walk route from the gate reaches the
  hall and all 8 rooms, no dim floor cells (block light >= 8) in the bunker, stairwell and blockhouse, stair landings
  clear, >= 80% concrete faces, >= 250 lamps, 12 + 3 doors, no snow inside, snow layer on roofs and yard, garrison
  not inside blocks, generation cost close to plain terrain.
- Golden shots: boreal_station, boreal_gate, boreal_corridor, boreal_hall, boreal_stairs, boreal_radar (`questcheck --golden DIR`).

## Evidence (2026-10-09, cloud thread, lavapipe)
- Full `questcheck --render --questsim --golden`: all checks passed, 3 m 05 s.
- borealtest seeds 12345, 777, 424242, 1, 2026 all pass; a verifier ran 8 more seeds, all pass.
  Seed 12345: station 1062 blocks from spawn, 145 hall cells + 8/8 rooms reached, darkest light 8, 90% concrete,
  278 lamps, 22 mobs, station chunk gen 95 ms vs 95 ms elsewhere.
- Quest APK built in the thread (tools/cloud-setup.sh apk, 544 s), storecheck 0 failures.

## Independent verifier (Opus) findings
Fixed: a light panel at head height on a stair landing, rusty-looking rails (new Steel Railing block), dim untested
stairwell (panels + test), world-audit overlap box too tall, catwalk stair without a rail, 1-high blockhouse rails,
weak checks (snow layer, lamp count, head cell, landings).
Polish after review (2026-10-10): the radar dish is now one sampled shell with a steel rim and feed arm (was lumpy),
the catwalk uses station floor plate (the ship grating read purple from below).
Left as is: drifts skip walls that sit in a neighbouring chunk (the writer cannot read across chunks); the catwalk
sides still read lavender under the hall's light (shading, not texture; renderer is the local lane's area); stations
are 360-2281 blocks from spawn.
