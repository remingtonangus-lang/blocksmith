# Integration stream (claude/blocksmith-playtest)

Owner: the integration session. Owns tasks 4 (Capital frigate), 5 (twin 42 cm turrets) and 6 (Capital citadels) of
Remington's 2026-10-04 list, plus merging the other streams. Other streams: (B) claude/bs-vehicle-riding (riding moving
vehicles, crews aboard), (D) claude/bs-capital-soldiers (soldier models, dress uniforms, arms bug, ranks/gear), and a
local Claude Code on Remington's Mac (USB GIP controller driver, hardware tests).

## Done in this stretch (2026-10-04)
- (0) Fast flight: sprint while flying ~8x (87 b/s), V toggles it (Key Bindings > Toggle Fast Flight).
- (1) Halo Infinite-style controller defaults: R3 melee, B crouch, sensitivity 1-10 per axis (default 3), power curve,
  look acceleration 0-5 (default 3), centre dead zone + max input threshold per stick; all in Options > Controller.
- (1b) usb-gip driver (USBGamepad.swift) - now owned by the Mac session. The integration session only fixed its
  IOUSBHost Swift names so the branch compiles (refined-for-Swift methods are imported as __configure,
  __sendIORequest, __enqueueIORequest). NEEDS A HARDWARE CHECK on Remington's Mac.
- (2) Capital vehicles are machines with components (helm, engines, per-wheel tracking) and crews (driver, gunners,
  troops); disabled not despawned. (3) first pass: Mob.deck riders walk in the ship frame; --ridetest added
  (reported, not gating). Stream B continues both.
- (4) Capital frigate: CapitalFrigate.swift (role "capfrigate", 142 blocks, kinematic). Replaces the Skyward Frigate
  in "frigate" encounters, /vessel frigate and the ship_frigate shots (bow/side/top/deck views added).
- (5) HeavyTurret (Soldiers.swift): the deck_gun mob is a true-scale twin 42 cm turret; shells burst like TNT
  (power 2.4, breaks blocks: Slug.breaks).
- (6) CapitalBase.swift: citadels replace the Steelhold fortresses (key military_base, mob keys and steelhold_* loot
  tables kept). A Capital frigate is stationed over each citadel (ShipManager.stationFrigates, key citadel:x,z).

## CI (heavy run 456 on cf2b180)
- Green: build, smoke, perf, checks (structcheck: 9 citadels, 99 POIs, 333 mobs, no issues), shots (mobtests clean once
  the stationed frigate was leashed to its citadel), tours (physicstest passes with the Capital frigate encounter).
- play: one playthrough FAIL (back through the Emberdeep arrival portal: the idle player was pushed out of it); fixed in
  15bc483 by holding the player in the portal. Verify on the next heavy run.
- --ridetest (not gating) now measures the real bug for stream B: on a crawler driving S-turns at 6 b/s the bot drifts
  154 blocks relative to the deck while standing still and falls off (5064 of 10800 frames off the deck); the sheep
  (Mob.deck in the ship frame) stays aboard except 197 frames. Riding the player is task 3 (stream B).

## Controller (usb-gip)
Compiles on CI since 627d256 (IOUSBHost refined names: __configure(withValue:matchInterfaces:),
__sendIORequest(with:bytesTransferred:completionTimeout:), plain enqueueIORequest(with:completionTimeout:)). Needs the
hardware check on Remington's Mac: run the built app from Terminal with the PowerA pad plugged in and read the
"usb-gip:" lines (found / step ... / opened / first input report). Owned by the Mac session.

## Standing order (Remington, 2026-10-04): never stop
Streams: B destruction physics + wrecks (plus riding), D reactive bases then pilotable aircraft/helicopters (plus
soldiers), H claude/bs-world-fx material damage + weather, Mac session usb-gip. This stream after the Capital rebuild,
in order: Future ideas #9 Big landmarks (volcanoes with bounded flowing lava, deep canyons, huge rare ruins seen from
far away via a landmark LOD / impostors past the render distance), #5 photo / cinematic camera (spline paths, depth of
field from the depth copy, hidden HUD), #10 split-screen couch co-op (after a perf pass: 60 fps at rd 8 per view).
Then bug hunting and measured improvements. Stays integration owner: branch green, PR #9 what's-new current.
.claude/ALLOW_STOP removed (the Stop hook keeps sessions working).

## Crafting book, landmarks, photo mode, split screen (2026-10-04)
- Crafting book (23cff05): the crafting table opens CraftingBookMenu (40 tiles a page, ten categories, craftable-now
  first, craft 1 / stack / max straight into the inventory, controller-first). --padtest drives it; shots craftbook,
  tv_craftbook, tv_craftbook_all. Compiled on CI; padtest + TV shots wait for heavy run 482.
- Big landmarks (#9): volcanoes (ab69472; run 470 shots: the cone and its lava channel look right, the crater shot's
  camera was above the world - moved down), impostors past the render distance (d690160), canyons (094ed04), the
  Ancient Spire (a9d7344, key great_ruin). All compile (run 482 fast lane).
- Photo / cinematic camera (#5, b315b78): F6 / Pause > Photo Mode; keyframe paths, depth of field. --cinetest, shots
  photo_dof / photo_dof_far.
- Split-screen co-op (#10, Coop.swift): a second pad joins with Menu; seats swap per-player state through Game; chunks
  stream round both players; mobs / pickups / arrows updated by the nearest seat; top / bottom views copied into the
  frame. --cooptest (not gating until it passes once), shots coop and tv_coop (their frame time is the rd 8 two-view
  perf number; the per-view budget is 8.3 ms GPU for 60 fps with both views).

## Batch after run 482 (2026-10-04 evening)
- Run 482 on 983ea14: smoke, perf, tours (padtest incl. the crafting book), checks, play all green.
- Split screen (Coop.swift) + smoke variant 8c (reported, not gating) + --cooptest (reported, not gating).
- Profile-driven CPU savings from profile_flight16: minimap terrain rows cached per seat (11% of encode), bee-nest
  population on the chunk's own arrays (largest Game.tick share), mobs out of view and over 64 blocks culled before
  their vertices are written (27% of encode), HUD vertex storage reused and no per-quad arrays, World.update re-checks
  only dirty chunks after edits (update_ms_p50 had grown 15x).
- Blind critic round on the Capital and volcano shots (gemini, run 470 images): hall doorways get transoms (pier stubs
  hung over the door), the frigate gets a drive glow from its nozzles, citadel_turret reframed (camera was in a
  birch), the bridge-deck ladder head fixed (stream B's ridecheck). A sky-coloured streak across the volcano: either
  the LOD 0 / LOD 1 seam or the cloud layer cutting the cone; volcano_far_nolod decides.

## Run 482 (983ea14): all green; read-out
- padtest crafting-book checks pass; tv_craftbook / tv_craftbook_all look right (ingredient names were cut short: fixed).
- cinetest PASS. photo_dof showed the inside of the player's head (photo mode drew the model at the eye): fixed.
- structcheck: great_ruin top chest unreachable 9/9 (the landing re-filled the stair's headroom) and floating 4/9: fixed.
- Impostors work (volcano with plume, spires); foot rings / shaft bases floated over the haze, the night plume stayed
  grey: fixed. Spire interior near black: ghost lanterns per floor.

## Run 509 (639eb75): all green
- Split screen: cooptest 17/18 (the blast check stood player 2 inside a hill: fixed), two-view frame 5.8 ms at
  1920x1080 rd 8 (one view ~3 ms), 7.6 ms at 1280x800 with chunks streaming round both. Smoke 8c: player 2 moved
  only 12 blocks (diagnostics added; not gating).
- Village / life bots no longer die (0 violations; was 2 deaths): citadel turrets and the stationed frigate no
  longer shell passers-by.
- great_ruin structcheck clean. Photo mode verified (photo_dof). The volcano streak was the impostor drawn through
  the loaded cone (identical with --nolod): impostors now sit on a shell beyond all loaded terrain.

## Playtest report (Remington, 2026-10-05): in order, each with a regression check
1. P0 mobs invisible in game. Harness shots draw mobs in Fancy; ruled out by reading: the landmark pass (simple
   pipe has an HDR variant; impostor depth sits on a shell past the loaded terrain), the 64-block cull, the scratch
   ring budget (landmarks ~100 KB), co-op despawn (single player unchanged), pixel formats (bgra8 fixed).
   --mobcheck (98d01b3 + live phase 95b7d4f): every kind alone, Fancy and Fast; then a 45 s survival night through
   Game.tick, every spawned kind viewed alone and again after a JSON save/load, NaN/zero-scale state. Not gating
   until the cause is found. Mobs now get night vision's lift (they did not).
2. Mobs calm on death and respawn (Game.calmMobs, e2cc215); --mobtests checks every kind both times.
3. Crafting book opens on its first tile; the inventory's crafting is the same book, 2x2 (08e2970); --padtest.
4. Cave fill + Options > Video > Brightness (0d6ebee); shots cave_dark(_moody/_bright/_fast/_mobs).
- CI: macOS runners backed up (runs 525/528/532/534 queued); cancelled 532 and 534 (both superseded by 95b7d4f,
  which carries the same mobcheck and every fix).
- P0 likely cause (2a00dd3): the mob vertex buffer (4 MB, ~2400 model parts) filled with far mobs first at render
  distance 16-24 (hundreds loaded; jointed soldiers are many parts each), so fresh spawns beside the player (last in the
  list) were never written. Now nearest first, none past the fog; mobcheck crowd test; F3 / bug notes count drops.
  Also: 98d01b3 / 95b7d4f could not build (MobRenderCheck called Mob.swift's private parts()); cancelled 95b7d4f's
  run and pushed the fix; precheck now catches cross-file private calls and duplicate top-level functions.
- 01:13 UTC: cancelled queued run 528 (8ac3d54 heavy; 525 had already finished) on this branch: superseded by 542 (2ab6bf7,
  which contains it), and it held a macOS runner slot ahead of it.

- Run 549 (0f6c0ea) fast lane: build green; mobcheck PASS (15 kinds after a survival night, crowd: the cow beside the
  player drawn with 246 far mobs dropped), plantcheck PASS, musiccheck PASS (no audio device on CI: director part
  skipped). Cave fill retuned from its shots (6f38b43: Default p50 20, Fast 19, Bright 39, Moody 1). All three gate now.
- Remington's Mac notes (2026-10-05): "works like a dream"; sugar cane floating (PlantSupport.swift) and a custom music
  folder (CustomMusic.swift) done.

## Run 563 (7005780, [full]): green
- Heavy lane all green (padtest 156/0, mobtests 0 failed, cooptest, mobcheck, plantcheck, musiccheck, smoke rd 8/16/24/24f:
  0 mobs dropped for a full buffer with 600 loaded). Smoke 8c (not gating): player 2's scripted turn sat inside the look
  dead zone, so they walked into one obstacle for 50 s (fixed in the script). Soldier spin traces named the 10-block
  home edge (stream D landed the same fix first: SoldierBrain.homing, stroll area 7; mine dropped in the rebase).

## Landmarks verified (run 563 shots)
- volcano_far: no streak (the impostor shell fix holds). volcano_horizon_night: two volcanoes, the near plume lit orange.
- Known limit: seen from a high hill the impostors (volcano foot, spire skirt) sit over empty sky past the loaded
  terrain (nothing is drawn there), so their haze-coloured feet read as a pale disc. A fix needs far terrain (a coarse
  horizon ring), not impostor tweaks; parked.

## Fast-lane shots and leaves
- Fast-lane shots render at 32 px textures (BLOCKSMITH_TEXRES=32): leaves vanish at mid range there (citadel_far on
  e7124b3 looked like a forest of bare trunks, horizon_ring showed leafless sticks), while the 128 px game and the heavy
  lane draw them. Judge trees on heavy-lane shots only. (Players can't pick 32 px: textureRes is not in Options.)

## Frigates (session B request, 2026-10-05 ~02:50 UTC)
- Session B: go ahead with BOTH frigate hulls on claude/bs-frigates (CapitalFrigate.swift and the Stormwarden
  warfrigate); the integration session is not editing CapitalFrigate.swift and will not touch it meanwhile. Please keep:
  the stationed frigate's guard rule (CapitalShips: regions prefixed "citadel" engage only within 96 blocks of home until
  provoked), the drive exhaust particles (`exhausts` in CapitalFrigate), save keys / roles / turret mounts / crew posts /
  helm APIs. Mob vertex buffers now grow to 16 MB and draw nearest first (2ab6bf7), so bigger crews are fine; the
  Capital soldier rig is 190 parts close up, so keep crews modest per deck in view. Original names only (public repo).

## Run 634 (4d315cd, heavy) read-out
- Red: perf (flight24 resident peak 722 MB vs baseline 512, gate 1.4x; run 605 had 675), ridecheck crew (trooper 1.88
  off post 0; also red on run 605, so from the soldier merge, not the horizon ring), basetest "citadel update stays
  cheap" (2.6 / 1.3 ms, both rebuild scenes), smoke 8c (player 2 circled: 7 blocks net, not gating). Green: checks,
  play, smoke rd 8/16/24/24f.
- Memory: flight8 125 -> 242 MB since the 2026-10-02 baseline at the same chunk counts: the 128 px textures and Fancy.
  The emissive mask was a full 128 px slice per layer (37 MB GPU + 37 MB CPU at start-up), now one per glowing layer.
  Baseline left as is; if the gate still trips after this, re-baseline only the resident_peak_mb rows with the reason.
- Crew: calm crawler troopers strolled round their world-space spawn point (stream D's stroll circle / homing) while the
  hull drove off; crew with a post aboard now keep watch. Citadel rebuild: setBlockAsync (stream D: both in your files,
  small; shout in STATUS if you'd rather have it another way).
- Verified at 128 px: citadel_far trees whole (no bare trunks or leaf plates round the site); horizon_ring_evening reads
  as faint far ground in the haze. base_patrol frames the camera on a leaf canopy (patrol not in view): stream D's shot.

- Session log 08:10-08:40 UTC: run 651 (7264bb4) superseded by 076df09 while still queued (no runner had started it);
  run 652 (076df09) superseded by aada510 after its fast lane (emissive glow shots checked) and before its heavy build
  started. Also pushed: horizon ring per world seed, villagers/golems don't stroll into caves, village cave sealing
  counts a floor at the fill depth.

- 08:55 UTC: cancelled runs 651 (7264bb4) and 657 (aada510): superseded by later pushes but still queued for macOS
  runners ahead of run 658 (pushing over a queued run does not cancel it; cancel it explicitly).

- 09:10 UTC: cancelled run 658 (fcaeb04) after its fast lane passed (no warnings) and before its heavy build got a
  runner: one heavy run on the next push covers it and ~25 later commits instead of two queue cycles.

- 09:07-09:25 UTC: runs 661 (4608bd6) and 662 (6994f63) cancelled while still queued, superseded by c801470 (a likely
  NaN crash for idle frigate gunners, then the wooden-shelf empty container: crash fixes take the next run).

- 09:31-10:05 UTC: runs 663 (c801470), 667 (8aa3717) and 670 (32bd4ba) cancelled while still queued (no macOS runner
  free), each superseded by the next batch (container-screen item loss, save / load audit, split-screen audit);
  144ba6e carries all three batches.

- 10:20 UTC: run 672 (144ba6e) fast lane green (no warnings; optimized smoke rd 8 60 s PASS, p50 7.2 ms, resident 252 ->
  287 MB with chunks alive == loaded throughout: the ~20 MB/s growth is gone, the rest is map cells and stashed mobs).
  Its heavy lane was still queued: cancelled, 01f1b95 carries it plus the rest of the split-screen audit, the collision
  sweep and World.update quiet-frame costs from the 076df09 bench (per mob 7.8 us, update p50 0.89 ms at rd 24).

- 10:35 UTC: run 676 (01f1b95) fast lane: build clean, smoke rd 8 PASS (p50 7.95 ms, resident peak 281 MB); cooptest
  1 FAILED ("an enemy round fired at player 2": a round fired across from the side, likely stopped by terrain; now fired
  straight down over player 2's head). Heavy lane still queued: cancelled; 1a6f386 carries it plus 21 commits (a code
  review's six findings, NaN quarantines, pathfinder cursor, O(1) needsMesh, mineshafts / ravines vs aquifers,
  structcheck / village / life / collisiontest gating).

- 10:45 UTC: macOS runners busy with claude/bs-capital-soldiers (runs 680/681, Kestrel air patrols, basetest air) and the
  capital / frontier workflows; run 679 (e9a42c8) queued behind them. A trial merge of claude/bs-capital-soldiers
  (17 commits from c801470: Aircraft, BaseTests, CapitalAir, FlightModel, FlightTests, ShipPlay, Soldiers) into this
  branch's head is clean (git merge-tree, no conflicts).
- Heads-up for merges: claude/quest-port (run 675) also reworked World.collides / sweep to reuse one box list; this branch
  changed sweep too (per-column chunk lookups + a swapped-out scratch list, 01f1b95): expect a conflict there, keep the
  per-column lookup.

## Next
- Per-frame allocations left after the 2026-10-05 audit (refactors; measure with the profiles first): mob model parts
  rebuilt per mob per frame (Mob.swift parts / equipmentParts: append into one reused buffer); the HUD line chain
  (WorldMap Minimap.lines + CombatHUD + HudExtras concatenations, ContextPrompts strings: one inout buffer, cached
  prompt text); hotbar block icons rebuild their boxes and uv arrays per slot per frame (cache per BlockID); block
  outline / crack / sky / arm arrays in Renderer.encode (static lets); flashes sorted twice per Fancy frame.
- For stream D (soldier rig): a Capital soldier is 190 parts within 14 blocks (90 to 34 blocks, 34 beyond), about 330 KB
  of vertices rebuilt every frame; a courtyard of 30 is ~10 MB/frame of writes plus 30 pose builds. Mob buffers now grow
  to 16 MB and draw nearest first (2ab6bf7), but a cheaper LOD 0 (merge trim/buttons/badges into fewer boxes, or LOD 1
  from ~8 blocks) would save CPU and memory. The behaviour-sim trace now prints why idle citadel soldiers spin.
- Checked on run 509 (639eb75): citadel_turret (twin 42 cm gunhouse on its barbette, soldiers drawn on the plaza)
  and ship_frigate_deck (deck markings, superstructure, crew bar) look right.
- (Done) structcheck covers the citadel: 9 checked, 99 POIs, 333 mobs, no issues (run 634).
- (Done) --ridecheck gates the tours lane (its crew failure turned run 634 red).
- 2026-10-05 11:15: run 682 heavy build failed (WorldMap.swift:243, type checker timeout on the MapCache.batch
  trailing closure; the fast -Onone lane does not catch it). Fixed with a named nested function; also fixed five
  races from the thread-safety audit (map epoch, music generation token, sound evict, World.alive lock, bench
  timing) and the first fidelity-audit items (shears/sword/hoe speeds, full-draw bow crits). Pushed with [full].
- 11:40 UTC: run 685 (d31579b) still queued (no macOS runner): cancelled, superseded by this push (fidelity drops /
  mob speeds, precheck Type.member() resolution, per-half subtitles).
- 11:55 UTC: run 686 (313ecce) still queued: cancelled, superseded by the fidelity audit round 2 (three read-only
  audits: items/blocks, combat/survival, spawning/AI; ~45 fixes) plus --fidelitycheck (gating). A compile review of
  313ecce..2d0b90f by a subagent found nothing.
- 11:40-12:40 UTC: run 692 (1b8f474): fast lane clean (no warnings, cooptest PASS incl. the enemy round and per-half
  subtitles, fidelitycheck 30/30), release build and benchmarks done; smoke / tours / shots / checks / play queued
  behind bs-capital-soldiers (which now rebases on 1b8f474) and frontier runs. Held locally meanwhile (~45 commits,
  compile-reviewed by a subagent): fidelity audit rounds 2-3 (world mechanics, sparkstone/brewing, loot pending),
  a UB audit (map loop range, dragon respawn index, clamps), XP orbs, fluid spread toward drops, fire odds,
  --rulescheck (not gating yet) and a mobtests cluster-cap check. Pushing once 692's heavy lane publishes.
