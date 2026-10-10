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
- Sound: a low mains hum (Snd.stationHumLoop, "Machinery hums") from corner lamps and data cabinets, through the
  ambience director's emitters; no birds or wind in the bunker.
- Alarm (BorealAlarm.swift, from basesTick): a hostile gunshot or blast inside the fence or bunker, or a soldier
  seeing the player inside, sets off a klaxon every 4 s from the speaker nearest the player (hall, blockhouse, yard)
  and rouses the whole garrison toward the source; it stops 45 s after the last noise or fight. Not saved.
- Reachable with /locate boreal_station, the pause-menu Shortcuts list, and the world map ("N" marker).

## Checks
- `questcheck` runs `BorealTests` (skip with `--no-boreal`, only it with `--boreal-only`; seeds `--boreal-seeds`).
  Mac: `Blocksmith --borealtest`. Per seed: station near spawn, structcheck clean, walk route from the gate reaches the
  hall and all 8 rooms, no dim floor cells (block light >= 8) in the bunker, stairwell and blockhouse, stair landings
  clear, >= 80% concrete faces, >= 250 lamps, 12 + 3 doors, no snow inside, snow layer on roofs and yard, garrison
  not inside blocks, generation cost close to plain terrain, every planned snow drift present, the hall and a
  corridor hum at noon with no wildlife, the hum renders clean (seamless loop, quieter than a beacon), and a shot
  in the hall sets off the alarm (klaxon, every garrison soldier roused) which stands down after the quiet period.
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
Snow drifts now come from the plan (BorealStation.surfaceWall), so a wall in the next chunk still gets its drift;
borealtest checks every planned drift is there (the old code missed the cross-chunk ones).
Left as is: the catwalk
sides still read lavender under the hall's light (shading, not texture; renderer is the local lane's area); stations
are 360-2281 blocks from spawn.

## Infiltration operation (2026-10-10, BorealOps.swift)
Cold-war bunker infiltration feel (borrowed feel only: no names, characters or layouts). One operation per station,
saved in world.json ("stationOps"); a finished station stays finished and pays once.
- Start: stepping inside the fence. A toast lists the jobs; a bar under the boss bars (shared HUD, so on Quest too)
  shows the next one: "Copy the uplink codes", "Sabotage the generator", "Extract past the fence", the copy %, the fuse.
- Copy the uplink codes: use any command console in the control room (north wing; the screen wall or the desks).
  8 s while you stay within 4 blocks; walking off pauses it (progress kept); while the alarm sounds the uplink is locked.
- Sabotage the generator: use the machine in the generator hall (south-east). A 45 s charge; when it blows it wrecks
  the machine (blast + most of its body torn out) and the station hears it. A generator already wrecked some other way
  counts as sabotaged.
- Extract: with both done, get past the fence (3 blocks outside the yard, on the surface).
- Silent (no alarm before extraction): Farsight Rifle, 24 heavy rounds, 2 golden apples, $250, "Cold Run" and the
  "Nobody Was Here" challenge. Loud: 90 rifle rounds, a golden apple, $100, "Cold Run".
- Alarm consequences: the uplink locks; roused station soldiers open bulkhead doors (Mob.stationDoors: before this they
  walked straight at the noise and stood against the room's wall); squads of three come down the stairwell every 25 s
  while a player is inside, three squads at most.
- Use works with a gun in hand (it runs before the gun's aim), and only on these objective blocks.

### Checks (borealtest, every seed)
Outside the fence nothing starts; inside starts it; the console copies (25% after 2 s), pauses when you walk off,
finishes on return; the hall's screen wall is not an objective; charge + out past the fence = complete and silent with
the rifle, $250 and both advancements; the charge wrecks the generator (112 -> 50 machine blocks); saved and loaded it
stays done and pays once; the alarm locks the copy (bar shows ALARM); a squad of 3 spawns at the stairwell foot at
25 s, waves stop at 3; a roused soldier shut in the archive gets out through its bulkhead door under the real game AI
(3.6 s; with Mob.stationDoors disabled it is still inside after 40 s); a wrecked generator counts as sabotage; a loud
extraction pays $100 and no silent challenge.
Fixed on the way: BaseWatch.of keyed by ObjectIdentifier gave a new Game allocated at a freed game's address the old
game's watch (alarms and operations leaked between harness games); it now holds a weak owner.

### Evidence (2026-10-10, cloud thread, lavapipe)
- `questcheck --boreal-only --boreal-seeds 12345,777,424242,1,2026`: all checks passed (75 operation checks), 54 s.
- Full `tools/cloud-setup.sh check` (linux-check + questcheck --render --questsim --golden): all checks passed, 6 min.

### Pre-mortem
1. Holding a gun, LT aims instead of using the console: the objective use runs before the gun (checked by reading
   Game.interact; the test calls stationUse directly).
2. The generator destroyed before the charge (rockets): counts as sabotaged, no softlock (checked).
3. Garrison shut in rooms makes the alarm toothless: roused soldiers now use the doors (checked under the game AI).
4. Dying mid-run or reloading: state is saved; a running fuse keeps its seconds (fuse saved).
5. Creative mode pays the reward too (alarm sightings need survival, so creative is always silent): left as is.
Open: every console in the control room destroyed would block the copy (40 consoles; not handled).
