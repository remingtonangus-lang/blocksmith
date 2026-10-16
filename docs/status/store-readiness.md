# Store readiness (Meta Horizon Store bar)

Independent QA audit, repeated per session (task 25, 25b, ...). The game is NOT marked store-ready; only Remington
decides that after headset play. Each round: verify promised items with the harness, play the first hour headless
(Mac + QuestSim on CI), fix worst first, list what stays open.

## Round 1 (2026-10-09, task 25)
Measured (Mac, local M1, release build 66db7fa0+):
- `--questbugs`: 121 checks, 0 failures (incl. every saved Mac world loading: World377 4800 chunks, 0 unreadable).
- Smoke rd 8, 60 s: p50 9.9 ms, p99 19.9 ms, worst 175 ms (first frame), 3218 blocks travelled, menus closed.
- Monkey agent 2 seeds x 2 runs: 0 crashes / NaN / stuck; deaths to Sunken only. Life agent: trade + sleep met on 777.
- Screens looked at (downscaled): title, pause, options, commands, crafting book, crafting, furnace, enchanting,
  trading, inventory search, create world, death; spawn day/dusk/night, lush + dripstone caves, underwater, animals.

Fixed this round (each with the oracle that caught it):
1. Spawn on a mushroom island (seed 12345): no tree within 100 blocks, so no wood at all. findSpawn skips mushroom
   fields (playthrough "gather: logs mined by hand" 0 -> pass).
2. Beds: the remodelled bed's stacked boxes let a walker sink into the head end; beds collide as one 9/16 slab
   (collisiontest walk_through 3 -> 0).
3. Option tips cut mid-sentence ("Torches stay..."): tips now wrap to two smaller lines before cutting.
4. Enchanting table: the clue text ran under the level-cost badge; it now stops 2 px short (full name beats "+?").
5. Igloo basements hung over caves: a stone-brick footing goes down to solid ground.
6. Saved Safe Area 5% (off the 0-10 step list) could never be stepped back to; snapped to the next step on load.
7. Test rot that hid real signal (CI heavy lane red on every run): padtest (Worlds row index; 15 -> 0 failures),
   physicstest (capital ships sail post-game since task 23), structcheck (tree canopies, a pyramid's treasure room
   inside a citadel box; 17 -> 2), playthrough (Deep fall after bottom-layer mining, stronghold ring origin;
   8 -> 2), smoke at short durations, life bot's sleep window, a precheck error in QuestBugTests.

## Open (worst first)
1. NOT VERIFIED ON A HEADSET (no Quest on adb this session, nor in any earlier round): comfort (turning, vignette,
   reclined mode), the water look, lighting, held tools (the "vanishing held tool" report was never reproduced),
   system keyboard for commands, 90 Hz frame pacing, controller haptics. Store reviewers will run this on device.
2. Blight fight (playthrough): 388 arrows for ~35 damage, 0 sword hits, boss never dies in 600 s. Under
   investigation in round 1 (see below for the result).
3. Citadels can be built over a desert pyramid (seed 424242, 408 296): the pyramid above ground is flattened and its
   treasure room sits buried under the plaza. Fix needs a save-safe placement rule (structure-guard), not a blind
   `clear` check (would move citadels in explored ground).
4. Capital city at seed 424242 (-768, y 40, 1054): capital_stone_trim columns over a 5+ block void (structcheck
   floating 1). Jungle temple 424242 (249 65 1178): 4 cobblestone columns over a terrain overhang.
5. Water flow: water spreads both ways instead of only toward the nearest drop (rulescheck "water heads for the drop
   3 east"; channels and farms behave differently from the genre reference).
6. Hitches: first rendered frame 66-175 ms; 20-35 ms sound tick and ~50 ms first block placement (earlier notes).
7. CI perf gate: ships.edit_ms_mean 0.5 -> 2.0 ms on CI only; local M1 0.17 ms in the CI scene order (not a game
   regression; the gate keeps the heavy perf job red).
8. Monkey agent leaves the death screen open for 20 s (the agent never presses Respawn: harness gap).
9. Visual judgement calls for the next round: stone/dripstone look soft (filtered) up close in Fancy; the igloo
   exterior reads as a small snow lump from above; higher-res textures were skipped on purpose (task 24).
10. Not exercised this round: horse riding + bonding in play, base building, split screen, saving/loading through the
    GUI title flow, the Hollow and the Deep war by hand, every Quest-only path (QuestSim runs on the Linux CI lane).
