# Known test issues

Checks that fail for reasons other than a game bug, and what was done about them.

- **perf `mesh.chunk_ms_mean` gate (CI run 37990566272, 2026-10-09)**: 3.347 -> 5.579 ms on the runner. Not a mesher
  regression: a local A/B on the M1 (dad2af84 vs 05dd5699, `--bench --scenes mesh`, three runs each) gives
  3.48-3.54 vs 3.44-3.55 ms/chunk. The baseline dates from 3763 quads/chunk (now ~4950) and the previous run already
  read 4.38 ms (1.31x), so runner noise crossed the 1.6x gate. Baseline mesh / mesh_lod1 means and quads refreshed to
  run 37970910818 (4.38 / 4.10 ms, 4996 / 2535 quads).
- **ridecheck `ride crew`**: fails on the local M1 at dad2af84 and HEAD alike (crew "deck lost"), passes on CI.
  Pre-existing, not touched.
- **ridecheck `ride troops`** (troop inside the troop-bay engines' z 71 face for one tick): pre-existing flake; troops
  are mobs (Mob physics), the player-side fix for the same face is in Player.update's unstuck.
- **playthrough `blight`**: pre-existing (the bot's arrows can't finish the Blight in 600 s).

## questbugs `--only deep` flaky (seen 2026-10-09, task 25b1zzz)
- 1 of 4 local runs failed one check, a different one each time: "depth power ... an 8 hit does 4" (want 5) and
  "deep war: the Marshal marks a barrage and calls his guard". Best guess: random damage variance / Marshal AI timing
  in the test, not the pm9 changes (the same build passes 3 of 4 runs). Repro: `Blocksmith --snapshot /tmp/q.png
  --seed 12345 --find plains --time 0.3 --rd 4 --questbugs --only deep` a few times.
- 2026-10-11 (cloud gap pass, horses): "the Marshal marks a barrage" failed again in one full questcheck run on a
  branch that touches no Deep code; it passed two `--deep-only` reruns before. Still the same timing flake.

## questcheck full run, 2026-10-10 (honour thread, claude/project-thread-dkuflx)
- **"sheriff: a town without one gets a sheriff" / "only one is sent"**: failed on claude/quest-port 581dfc8 too, in the
  full run only (passes in `--towns-only`). The full run's earlier checks leave the player over water, where no
  sheriff spot is dry ground. Fixed in the test: the sheriff checks start at the spawn.
- **"every mob kind draws through the Quest renderer (invisible: tadpole (14 px))"**: fails on claude/quest-port
  581dfc8 as well; not touched (mob looks belong to the Mac worker).
- **"boreal 12345: corridor at noon hums ... wildlife: birdCall"**: fails on claude/quest-port 581dfc8 and on this
  branch alike (Boreal audio, not touched).
- **"VR swing mode holding a torch:
  the trigger attacks a husk"** / **"defence: an elder doesn't fight, keeps away"** (this branch, one run each, pass on
  the other runs): flaky, random AI/audio timing; not touched.
## questcheck fails on claude/quest-port @ 581dfc8 itself (seen 2026-10-10, horses thread)
Built and run unchanged in a worktree of 581dfc8, the same as with the horse changes on top; not touched there.
- "every mob kind draws through the Quest renderer (invisible: tadpole (14 px))" and "sheriff: a town without one gets
  a sheriff (none in Dry Springs)" / "sheriff: only one is sent": fail every run on the base.
- "boreal 12345: corridor at noon hums ..., wildlife: birdCall": flaky on the base (one pass, one fail in two
  `questcheck --boreal-only` runs); the ambience director's random bird call reaches the corridor.

## 2026-10-10 evening: `--towntests` sheriff/HUD after the Frontier towns merge (#19)
- Fails: "sheriff: shoots an outlaw player (health 20)" and "hud:  shown in town, on screen" (empty town name).
- Passed (121 ok, 0 fail on the sheriff checks) on the quest-port head before #19 "Frontier towns, honour, bounties
  and the Sheriff's Revolver"; the sheriff's warn/arrest flow and the HUD's standing line came in with it.
- Repro: `build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot /tmp/tt.png --seed 12345 --find plains --time 0.3 --rd 4 --towntests | grep FAIL`
- Owner: the cloud towns project (sheriff/honour are its scope). Not a Mac CI lane; questcheck runs TownTests too.

## 2026-10-10 late: `--mobtests` "path ladder climb" and "path swimmer crosses water"
- Fails after merging origin/claude/quest-port (The Deep expansion #22) into the 25b4zxx work: the ladder path ends at
  0,3,0 (8 nodes, 3 rungs) and `reaches(deck)` is false; the swimmer's 16-node path round the pool doesn't count as
  swimming. 145 other mob checks pass. 25b4zxx didn't touch Pathfinding.swift or MobTests.swift (its melee reach
  change only affects attack checks), so the likely cause is terrain/blocks at the test site after the merge.
- Repro: `build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot /tmp/m.png --seed 12345 --find plains --yaw 0 --pitch -30 --time 0.3 --up 3 --mobtests --posecheck | grep FAIL`
- FIXED (25b4zxxxx, 2026-10-11): not the Deep. The step-height rule from a092303d (Capital cities #16) in
  Pathfinding refused a 1-up step whose rise from the floor below exceeded 1.25 blocks; off a ladder rung or out of
  water the body rises from the cell itself, so the rule now skips those (`lifted`). `--mobtests`: 149 ok, 0 FAIL.

## maingun crater size under load (2026-10-11, cloud gap pass, frigate)
- "maingun: the slug lands N blocks out and blasts a ...-block crater" wants > 2000 blocks; where the slug lands (102-112
  blocks out over four runs) follows the frigate's drift while chunks stream in, so a busy machine (two builds and a
  check running at once) moved it onto shallow water: 1425 blocks twice with the same binary, 2435 / 3226 on quieter runs.
  "the helm shows where the shot will land ... predicted in 4.68 ms" (wants a fast prediction) failed in the same loaded run.
  The checks run before the gap-pass code (MainGunGapTests runs last), so they are load-sensitive, not a regression.

## questcheck on claude/quest-port @ 28eda0ac (+ 25b4zxxxx), 2026-10-11
- "deep hell: a 70-block drop into a hall floats down unhurt (3-8 damage)" and the boreal birdCall check fail on the
  upstream head (run 121) as well; the Deep's D1 hell band (#33) is the cloud lane's.
- "horse gap: the stablehand's counter has a Horses button (none)" failed once (run on 98e184b8), passed on run 121;
  "powderwight: strikes its fuse beside the player" failed on run 121, passed on 98e184b8. One-off fails on the same
  base, random town/mob state; horses and the Powderwight are cloud scope. Not touched.
- 2026-10-11 Quest CI run 38118811056 (f0248336): "deep war ... Marshal", "boreal ... birdCall" and "horse gap ...
  Horses button" failed together (all listed above as flaky; cloud-lane areas); polygon terrain checks passed. The APK was
  not published by that run; the last published quest-dist is 04d12966.
- FIXED in the gap pass's D3 (cloud, 2026-10-11), each a test leaking state or riding a random roll, not the game:
  "deep hell: a 70-block drop" (the keep garrison shot the falling test player: the drop now counts only the fall);
  "horse gap: Horses button" (the Deep balance duels ran ~20 minutes of game time and shut the stable for the night:
  the clock is put back); "powderwight: strikes its fuse" (the Powderwight's first look is a random 0-0.5 s off: the
  check zeroes it); "deep war ... Marshal" (a barrage shell downed the test player and calmed every mob: the war sim
  puts the Ashguard back on the player). The boreal birdCall check stays known red.
