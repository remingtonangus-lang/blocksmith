# P394: an object hit under 1 ms on the frame thread

Host numbers from `questcheck` built with `QUEST_OPT=-Ounchecked`, seed 13480747113613945685, `--view OUT --at 6094,190,688
--rd 4 --field --questlod --w 480 --h 400 --fov 90 --scene objects` (Sources/ObjectBreakTests.swift: P389's ten objects,
each struck until it breaks, 55 blows). Taken on a quiet machine (no build running). "Before" is the P389 build
(f6330321), "after" this one; two after runs.

A blow and its swap-in land on different frames (the blow queues the cut on the object worker; the cut is swapped in on
the frame it finishes), so each column is one frame's cost.

| object | before: blow worst | before: swap-in worst | after: blow worst | after: swap-in worst |
|---|---|---|---|---|
| lamp post (P389's 1.2-1.8 ms) | 1.140 | 1.713 | 0.195 / 0.138 | 0.607 / 0.415 |
| parasol (largest: 12 cells) | 0.081 | 0.777 | 0.092 / 0.077 | 0.671 / 0.628 |
| café table | 0.111 | 1.017 | 0.153 / 0.087 | 1.057 / 0.532 |
| barrel | 0.104 | 2.127 | 0.126 / 0.113 | 0.855 / 1.010 |
| all 55 blows | 1.140 | 2.127 | 0.195 / 0.670 | 1.057 / 1.010 |

New in after: the frames following a swap-in each take one queued cell removal or drop: mean 0.03, worst 0.65-0.73 ms
(30 items).

What moved off the hit's frame:
- A cut's cell removals (a block edit each) and drops (a pack insert each) go to `Registry.later`, one a frame
  (WorldObjectsGame.objectsTick). The cell no longer draws or collides once its pieces are gone, so the frames between
  show nothing different; a save drains the queue first.
- Two tables built on the session's first block break are built at load (Mob.warmTables): TownLaw.property (84 ms on
  the first break) and PlantSupport's rules (part of a 22 ms break under a parasol).
- A quiet break (an object's cells) re-meshes what stood on it in the background too.

Left over 1 ms: one swap-in each on a café table (1.057) and a barrel (1.010), within run-to-run noise of 1 ms; the lamp
post and the largest object are under it in every run.
