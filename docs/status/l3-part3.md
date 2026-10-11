# L3 part 3 (Lane C): perf overlay, world-gen checks, volcano eruptions

The third part of backlog item L3 (docs/status/ground-l3.md has parts 1 and 2). It covers the RENDER DISTANCE / PERF
and WORLD GEN items and the camp rarity. The 20-minute soak and the device fps belong to lane M (the Mac worker).
Ruined portals were removed from the game at Remington's request, so they are not rebuilt; the check makes sure they
stay gone.

## Objectives
Listed: an optional perf overlay (fps, frame ms, render distance, chunk jobs) in settings. Capitals a minimum distance
from spawn and from each other, checked over 50 seeds with the numbers in this doc. Spawn always gets a natural start
area. Rare small volcano eruptions with particles and rumble. Camps found about every 10-15 minutes of travel, with
the respawn rules documented.

Expanded (mine):
1. The overlay is one switch (Options > Interface > Performance Overlay, off by default; Reset Options turns it off)
   on both the Mac and the Quest. It draws two short lines in the HUD's top-right corner and shows the worst frame of
   the last second, not just the average, because a hitch is what a player feels. It says when Auto Render Distance
   is holding the distance below the chosen one. No allocation per frame: a fixed 128-frame ring.
2. Capitals are kept apart by a rule, not by luck. Each capital region gets a priority hash. A capital whose
   neighbouring region has a higher-priority capital within 1200 blocks is dropped. A save keeps every city and
   camp whose ground it had generated before this update: the first load takes a snapshot of the chunk folder into
   structure-guard-l3.txt (StructureCache.legacyL3), the same way earlier placement changes were guarded.
3. A natural start means no surface structure within 24 blocks of the spawn (mineshaft tunnels below don't count)
   and the spawn on dry land. Camps are kept 64 blocks from the spawn by rule. Villages, capitals (1200+ by rule)
   and the other structures are not placed by a spawn rule; the 51-seed check measures them and fails under 24
   blocks (closest seen: 31).
4. Camp rarity is measured as minutes of walking: a camp seen within 96 blocks either side, at walking speed
   (4.3 blocks/s). The check fails outside 10-15 minutes.
5. Eruptions are rare and cheap: about one per 20 minutes spent within 1100 blocks of a volcano, 18-30 s each. A
   burst every 2-5 s throws glowing lava bombs and ash. Its boom arrives at the speed of sound (the shake waits for
   it too) and is heard all over the reach. The view shakes within 600 blocks, through the existing shake, so VR's
   Blast Shake and Screen Effects options cover it. A ridden horse within 150 blocks rears when the boom reaches it. Past the loaded terrain
   the far impostor swells its plume, lights the plume's foot and throws sparks, so an eruption reads from the
   horizon. An eruption never edits the world or a save. The roll is a hash of the time slot and the volcano, so a
   replay erupts at the same moments.

## Checks (questcheck)
- `perf overlay:` (Sources/PerfOverlayTests.swift; runs before `--workshop-only` exits): the one-second window drops a
  hitch 3 s old; the two lines read "72 fps  14.1 ms (worst 30.0)  GPU 9.2 ms" / "Render distance 6 of 10 (auto)
  Chunks 218, 0 jobs"; the Interface row toggles Off -> On and the HUD grows 1710 -> 2016 vertices.
- `eruption:` (Sources/EruptionTests.swift): rarity over 5 volcanoes x 60 h of rolls; the strength curve; a burst at
  120 blocks (bombs, ash, the boom 0.35 s later, the shake and a horse's startle waiting for it); the boom plays the rumble and shakes the
  view; bursts 2-5 s apart; at 900 blocks no particles, a quieter boom and no shake; over after its length; the
  rumble is in the bank and passes the sound check. On the Quest renderer, the 700-block volcano view is rendered
  again while erupting, and the impostor must draw its bombs. The calm view is also rendered with and without the
  smoke, and the plume's pixels must differ.
- `l3 guard:` (Sources/L3GuardTests.swift): a made-up city 300 blocks from a real, stronger one is dropped, but kept
  when one chunk of its ground is in the L3 guard. Camps read the same guard.
- `--worldgencheck 50` (Sources/WorldGenCheck.swift): 50 seeds plus Remington's Quest world.

## World-gen numbers (50 seeds + 1, 2026-10-11)
| Measure | min | median | max |
|---|---|---|---|
| Spawn to the nearest Capital city (blocks; rule 1200+) | 1267 | 1656 | 2483 |
| Closest pair of Capital cities in 4096^2 (31 seeds with 2+; rule 1200+) | 1268 | 2125 | 4199 |
| Spawn to the nearest Capital citadel | 348 | 604 | 1544 |
| Spawn to the nearest surface structure piece (rule 24+) | 31 | 144 | none in range |

- Capital cities: 1.76 per 4096^2. Before the apart rule, the closest pair was 376 blocks.
- Camps: 8.1 per 2048^2 (hunters 143, traders 98, abandoned 72, prospectors 56, outlaws 45), about one every 10.4
  minutes of walking. Before the alternate site, it was 16.9 minutes; with two alternates, it was 8.6 minutes.
- Volcanoes: 74 in 2766 cells of 1280^2 (2.7 %). Each foot is checked at 12 points: no sea, no snow, and at most one
  wet point (a stream crossing the foothills).
- Ruined gates: 0.

## Camp respawn rules
A camp is built once, when its chunks first generate: its chest is filled once from its loot table, and its trader,
donkey or outlaws spawn once. Nothing respawns. A looted chest stays empty, and killed outlaws stay dead. A camp
that hasn't been found yet is still there on a later visit, because camps generate with the world.

## Found on the way: far plumes were hidden on the Quest
The Quest drew the landmark smoke before the sky. The smoke writes no depth, so the sky painted over it, and no far
volcano ever showed its plume on the Quest. The smoke now draws after the sky (quest/src/vk/WorldRenderer.swift,
drawLandmarkSmoke). Evidence: docs/status/evidence/l3-part3/volcano_calm_erupting.png shows the Quest renderer from
700 blocks at noon, calm on the left and erupting on the right.

## Verifier
(filled in after the verifier pass)
