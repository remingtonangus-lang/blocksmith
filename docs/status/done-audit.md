# Done audit (task 25b6, 2026-10-11)

Every queue task marked done between 20-blocksmith-r3-features and 25b4xxxxxx-blocksmith-apply-art-style (plus
25b4z and its gap rounds), graded against the CURRENT repo (claude/quest-port @ fa79ef5e and later). Continuations
are graded with their parent. The four biggest tasks (22, 23, 21, 25b4) and 25b4z were graded by a fresh Opus
reviewer each (high effort, one at a time) that first expanded the brief into studio-level objectives (rows E1..).
The smaller tasks were graded by the audit session itself from the code, tests and reports (lighter evidence).

Grades: MET / PARTIAL / MISSING. "Device" means the Quest 3 headset: no session since Oct 8 has had the Quest on adb,
so nothing is verified on the headset; that is one shared gap (docs/status/device-checklist.md), not repeated per row.

## Cross-cutting findings
- **Nothing verified on the headset** (feel, comfort, water look, perf, voice notes, polygon walk). Needs Remington to
  plug in the Quest; device-checklist.md is the script.
- **Scorecard is stale**: docs/status/scorecard.md was measured at 3308bfbc (Oct 9) and still says e.g. "every shot is
  still the blocky 16 px look" after the art-style work. Re-measuring is the 25c quality loop's first job (folded in).
- **Audio peaks**: 196 of 986 rendered sounds peaked at -0.9 dBFS (target <= -1). Fixed here: the synth's peak cap
  moved from 0.9 to 0.88 (-1.1 dBFS), Sources/SoundSynth.swift `finish`.

## Smaller tasks (audit-session grading)

### 20-blocksmith-quest-bugs
| Requirement | Grade | Evidence |
|---|---|---|
| Water looks pretty again (real cause found) | PARTIAL | not fixed in task 20; task 21 made Quest water mirror the sky like Mac Fancy. Never judged on device. |
| Ocean vertex waves at 72 fps | MET (code) | Quest water swell; perf gate routes pass on the Mac proxy |
| Movement ignores right-hand pointing | MET | REPORT 20/21; walking follows head + left stick, tested |
| Climb out of water onto a 1-block ledge | MET | QuestBugTests |
| Held tools natural size | MET (code) | bigger held tools; device unverified |
| Sword damage = reference (stone sword 4 hits on zombie) | MET | --swingtest 56/56 |
| Lapis 4-9 / copper(redstone) 4-5 drops | MET | already correct, now tested |
| Skeletons hold and shoot a bow | MET | REPORT 20 |
| Idle/hurt/death sounds per mob, 3D on Quest | PARTIAL | scorecard: Ash tank/halftrack/artillery/truck and deck gun have no voice (vehicles: engine loops cover some) |
| Better mob models | MET | detailed mobs; 25b1zzz fixed detached limbs in 14 kinds |

### 20-blocksmith-r3-features (+20b)
| Requirement | Grade | Evidence |
|---|---|---|
| Titanium replaces diamond, harder to spot | MET | keys kept, rarer veins |
| Steel armour via iron + carbon in a blast furnace | MET | Steel Blend -> blast furnace only |
| Copper replaces sparkstone/redstone | MET | coppertest 111/111 rows |
| Jetpack | MET | chest slot, A to fly, refuel recipe |
| Gun enchantments | MET | 5 enchantments |
| Game-wide shader/lighting pass, Quest-friendly | PARTIAL | done in code; device look never judged |
| Saved world keeps loading (backup + migration test) | MET | auto-backup + migration test |

### 24-blocksmith-audio-visual (+24b)
| Requirement | Grade | Evidence |
|---|---|---|
| Every SFX overhauled, deliberate not placeholder | PARTIAL | 949 synthesized sounds, 0 clipped; no ElevenLabs SFX (no direct key); wool/sculk steps still measure wet-ish |
| Levels clean | MET (after this audit) | peak cap -1.1 dBFS (was 196 files at -0.9) |
| Visual pass (sky, fog, lighting, materials, less cartoonish) | PARTIAL | sky dome/haze/greens done; scorecard Sky row RED (slab clouds) |
| Higher-res textures where it shows | MET (later) | skipped in 24, then 128 px Quest textures in 25b4z |
| No Quest frame-rate cost | PARTIAL | Mac proxy only |

### 25-blocksmith-store-audit (+25b)
| Requirement | Grade | Evidence |
|---|---|---|
| Verify every promised item by running it | PARTIAL | round 1 in docs/status/store-readiness.md; item 10 lists paths never exercised |
| Play the first hour (Quest + Mac) | PARTIAL | bots/harness only; never on device |
| Fix worst first, open list kept | MET | store-readiness.md open list (10 items) |
| Repeat while issues remain | PARTIAL | 25c-store-audit was skipped; the repeat lives on as 25c quality loop |

### 25b1-blocksmith-playtest-fixes (+25b1b)
| Requirement | Grade | Evidence |
|---|---|---|
| Sprint >= 1.5x walk on Quest, with cue, test | MET | QuestBugTests.swift:150-156, QuestSim.swift:97 |
| Place/break reach 6, melee ~3 | MET | Game.swift:979 reach 6 |
| Horse: B inventory no longer dismounts; pickup when mounted | MET | REPORT 25b1 |
| Mobs spawn on ground and in caves again | MET | halved surface monsters later (25b1zzz), caves unchanged |
| Creeper fuse/health fair for melee | MET | REPORT 25b1 |
| Grass/flowers sparser | MET | grass ~1/8 (25b1zzz) |

### 25b1z-blocksmith-quality-infrastructure (+25b1zx)
| Requirement | Grade | Evidence |
|---|---|---|
| Bench runner, 6 routes, Mac + Quest path | MET | --bench, tools/quest_perf_gate.sh |
| Golden shots Mac + QuestSim, flicker diff | PARTIAL | Quest golden shots need a workflow edit only Remington can push |
| Audio tools (coverage, context, loudness) | MET | --audioaudit, tools/audiolevels.py (run in this audit) |
| 50-seed world-gen audit | MET | scorecard World gen rows |
| Input binding matrix, UI overflow detector | MET | scorecard |
| Scorecard measured with evidence | PARTIAL | exists, but stale since Oct 9 (see cross-cutting) |

### 25b1zz-blocksmith-voice-bug-notes (+25b1zzx)
| Requirement | Grade | Evidence |
|---|---|---|
| Always-on recording, VAD, AAC chunks, 2 GB cap, sidecar + screenshot, HUD dot | MET (code) | REPORT 25b1zzx |
| Compiled out of store builds, proven | MET | storecheck on both APKs |
| Pull + transcribe script | MET | ~/ClaudeTools/quest/bugnotes (synthetic recordings only) |
| Voice heard over game sound | PARTIAL | never tested with a real headset mic |

### 25b1zzz-blocksmith-playtest-oct9pm
| Requirement | Grade | Evidence |
|---|---|---|
| All 11 notes, horse comfort first, class-level fixes | MET | REPORT; pm9a/b/d checks |
| Copper parity checklist + build | MET | coppertest 111/111 |
| Pistons 2-tick motion | PARTIAL | pistons still move instantly (REPORT) |
| Automated check per item + verifier | MET | REPORT |

### 25b1zzzz-blocksmith-local-quest-build
| Requirement | Grade | Evidence |
|---|---|---|
| Toolchain installed lean, tools/quest-local.sh build/sign/install/launch/log | MET | script used by every later session |
| --check mode | MET | explains why questcheck needs Linux |
| Clean / incremental / edit-to-headset times | PARTIAL | 261 s / 210 s / 19 s fast; edit-to-headset not measured (no headset) |

### 25b2-blocksmith-performance (+25b2x)
| Requirement | Grade | Evidence |
|---|---|---|
| Profile CPU/GPU/draws/meshing/AI/memory | MET | docs/status/performance.md |
| Steady 72 fps on Quest | PARTIAL | Mac proxy p99 8.4-12.8 ms; no device numbers; thermal soak unmeasured |
| Noticeably larger render distance | PARTIAL | Quest default rd 16 + auto rd; unproven on device |
| Plain-English cost guide | MET | performance.md |

### 25b3-blocksmith-smooth-terrain-prototype (+25b3x) and 25b5a polygon test (+x, xx)
| Requirement | Grade | Evidence |
|---|---|---|
| Toggle, default OFF, Mac + Quest; per-world option | MET | Create World > Terrain; --smoothtest 14 checks; questcheck create path |
| Side-by-side shots, bench, mesh time, breakage list, recommendation | MET | docs/proposals/smooth-terrain.md, docs/status/polygon-test.md |
| Walk it on the Quest, device fps | PARTIAL | device-checklist.md section 2 (no headset) |
| Smooth collision | PARTIAL | collision is still boxes (feet float/sink on slopes), documented |

## 22-blocksmith-depth-final-battle (+22b) — Opus reviewer
Graded at fa79ef5e (includes cloud D1 #33 and D3 #41). `--questbugs --only deep`: 74 ok, 0 failures. Shots:
snaps/audit-22-vault.png, audit-22-tanks.png, audit-22-citadel.png. Verdict: the brief is mostly met in code and
tests; store quality is not (the D2 vault pass never merged; nothing measured on a Quest).

| # | Requirement (reading) | Grade | Evidence |
|---|---|---|---|
| R1 | No bedrock floor | MET | DeepTests: 0 bedrock in 36 new chunks; old chunks lose the floor on load |
| R2 | More vertical chunks | MET | Dim.deep stacked under the surface (768 blocks total); a dimension seam, not taller chunks (CH 384) |
| R3 | Hotter deeper: more lava | MET | emberslate below y -24, magma, sealed lava pockets (2286 lava, 0 open faces) |
| R4 | Red terrain deeper | MET | emberslate texture, red hell band |
| R5 | Tougher enemies deeper | MET | Mob.power 1 at y 10, > 1.5 at y -60 (test) |
| R6 | Open hell layer | MET | band 176 tall (DeepGen.swift:17), halls median 90 high, 5 biomes |
| R7 | Fortresses in hell | MET | 49 fortresses, 49 bastions, 49 Brimstone Keeps per 7x7 sample, no overlaps |
| R8 | Dig through hell, drop into a cavern far below | MET | seal y 192-199, ~160-block drop with an updraft; needs Sunderite since D3 |
| R9 | Huge cavern (130+ tall, wide open) | MET (feel PARTIAL) | 133-145 tall, open everywhere sampled; fog ends at 130 blocks (AshSky.swift:18) so the size doesn't read |
| R10 | Original fictional WW2-style army | MET | the Ashguard, ranks, the Ash Marshal |
| R11 | All black with red signage | MET | shots; ash_* textures (AshSites.swift:38-100) |
| R12 | Tanks, half-tracks, artillery, other WW2 vehicles | PARTIAL | tank, half-track, field gun, truck, fuel truck; no mortars, AA, armoured cars, motorcycles, aircraft |
| R13 | No Nazi symbols / real insignia | MET | grep clean; the ember mark is original |
| R14 | Main base at 0,0 | MET | test: 5288 ashcrete, 46 units |
| R15 | Smaller sites like a real army | MET | staging, 2 motor pools, 2 fuel depots, 2 supply hubs, 3 batteries, 8 outposts, 111 camps |
| R16 | Lots of tanks (20+) | MET | 24 placed plus camps |
| R17 | Real fight: AI | MET | tank tell + coax MG, half-track circles, soldiers use Steelhold AI, Marshal calls guards |
| R18 | Vehicles that shoot | MET | tank/half-track/field-gun fire tests |
| R19 | Victory state | MET (isolated) | victory, stand-down, lift home pass; no bot fights its way there |
| R20 | Performant on Quest | PARTIAL | Quest proxy ashvault route: 12 hitches/min, max 45.6 ms; no unit cap; no device numbers |
| R21 | Saves: backup, migration, test | MET | backup + DeepTests load every saved world |
| R22 | Ship + install | PARTIAL | v75 on quest-dist; never installed |
| R23 | Store quality, nothing half-done | PARTIAL | D2 pass (towns, rail, airfield, mortars, patrols, alarm, reinforcements) never merged |
| E1 | Reachable end to end (surface to Marshal and home) | PARTIAL | each step tested alone; Playthrough.swift has no Deep stage |
| E2 | Fair warning for incoming fire | PARTIAL | battery shells have no warning (DE10) |
| E3 | Death and the way back | MET | surface respawn, Ember Gates, Gate Shard, Deep Lift |
| E4 | Quest perf in the biggest battle | MISSING | none (DE14) |
| E5 | VR comfort (falls, explosions, haze) | PARTIAL | slow-fall updraft; sky switches abruptly at y 128 |
| E6 | Variety/depth of the war | MISSING | patrols, alarm, reinforcements, crews, story (DE8, DE9, DE11) |
| E7 | War state saved | MET | faction, victory, gates, lifts saved (tests) |
| E8 | Balance, first contact | PARTIAL | unarmoured player killed by a Sharpshooter 92 blocks out within 4 s of arriving |

Gaps (the Deep is the cloud lane's area since Oct 10; handed over in docs/roadmap/backlog.md "FROM THE DONE AUDIT"):
BIG: D2 vault pass; vault perf on Quest (unit cap, soldier AI LOD, full-alarm questcheck number); a Deep stage in
Playthrough.swift. SMALL: battery shell warning (AshUnits.swift ashArtillery -> g.ashStrikes), crew bail-out
(AshWar.swift ashUnitDied), marksman first-shot tell, blended vault sky y 120-136, fog end 130 -> ~220.

## 23-blocksmith-factions — Opus reviewer
`--questbugs --only factions` 20/20 ok; `--questbugs --only maingun` 6 failures (twice). Shots: snaps/audit-23-*.png
(frigate bow/side-dusk/top, city far/street). Verdict: mostly built, not store quality; the live helm shot is broken.

| # | Requirement | Grade | Evidence |
|---|---|---|---|
| R1 | Frigate its own faction | MET | Faction.meridian (CapitalShips.swift:17-19, :622) |
| R2 | Long dark grey hull | MET | 160x27x40, 17,359 blocks, 0x383D42 |
| R3 | Twin lower bow booms | MET | CapitalFrigate.swift:140 |
| R4 | Lit porthole rows | MET | frigate_porthole light 11; dusk shot |
| R5 | Raised bridge + sensor dome | MET | CapitalFrigate.swift:170, :265 |
| R6 | Bulky engine block, glowing thrusters | PARTIAL | at night the stern glow reads as two small points |
| R7 | Drivable | PARTIAL | helm works; no designed way to board an armed ship 45 blocks up outside `/vessel frigate` |
| R8 | Very fast | MET | 42 b/s (~7.5x sprint) |
| R9 | MAC gun craters a military base | PARTIAL | design right (r 13, citadel lockdown); live helm shot never fires: "charges for 5.56 s", 0-block crater, 0 thumps; the crater test calls Explosion.crater directly |
| R10 | Capital cities generated | MET | CapitalCity.swift, a city within 2,008 blocks on 6 seeds |
| R11 | Low flat white architecture | MET | street level reads cream brick more than white |
| R12 | No towers | MET | 1-2 storeys |
| R13 | Trees | MET | planters, gardens |
| R14 | Grey flooring | MET | capital_paving |
| R15 | Outdoor seating | MET (code) | seating(); not seen in shots |
| R16 | Covered walkways following the terrain | PARTIAL | canopies on some strips only; terraces, not slopes |
| R17 | Military bases still generate | MET | citadel within 1,178 blocks on 6 seeds |
| R18 | Bases can be found | PARTIAL | /locate works; in play the radar and orders are base loot, so the first base means wandering ~1,200 blocks |
| R19 | Factions post-game only | MET | ShipVessels.swift postGame gate |
| R20 | Very rare | MET | ~one warship per 63M sq blocks |
| R21 | Found by radar | MET | FactionGear.swift:20-57 |
| R22 | Coordinates captured from bases | MET | intercepted orders: bearing + map mark |
| R23 | Guns/items from base components only | MET | Guns.swift:100-104, test |
| R24 | Capital, Steelhold, Crawlers, Frigate all hostile to each other | PARTIAL | any two factions are foes; Steelhold has been the Capital's internal name since Oct 4, so only 3 of 4 exist; only Capital vs frigate tested |
| R25 | Saved world intact | MET | structure guard on 4 saved worlds; backups |
| R26 | Commit per item, checks | MET | 3e38b30a, e3722d19 |
| R27 | Ship + install | PARTIAL | v77 published; never installed |
| R28 | Store quality | PARTIAL | R6, R7, R9, R16, R18, R24 |
| E1 | Gun feel (telegraph, shake, haptics, sound) | PARTIAL | written in MainGun.swift; live check measures 0 thumps, 0 shake |
| E2 | Quest perf | PARTIAL | Mac host worst 14.4 ms after an impact (> 13.9); no device |
| E3 | VR comfort at 42 b/s and in blasts | PARTIAL | Blast Shake toggle; no flight vignette for capital ships |
| E4 | Findability/onboarding | PARTIAL | see R18 |
| E5 | Failure states | MET | crippled frigate crash-lands; broken citadel stays broken through a save |
| E6 | Variety | PARTIAL | one frigate design |
| E7 | Regression coverage | PARTIAL | no capital_city snapshot in snap.sh; maingun red |
| E8 | Naming clarity | MISSING | a Capital city is called "Meridian" (CapitalTown.swift:17), same as the Meridian Navy |

Gaps: maingun live shot (cloud lane: frigate gun, top priority), first-base findability (cloud: base/village),
boarding route + capital-ship flight vignette (BIG, queued 25b4zzz-blocksmith-audit-gaps), "Meridian" city rename +
city snapshot in snap.sh + thruster glow (cloud: towns/frigate), real-shot crater test (cloud: frigate gun).
Steelhold as a 4th faction: Remington decides (it was folded into the Capital on Oct 4).

## 21-blocksmith-store-quality — Opus reviewer
`--questbugs` 285 ok / 1 fail (frigate maingun crater, not this task); `--mobtests` 0 failed (8 animals in 275 chunks);
`--padtest` 156 ok / 6 fail (Worlds list order/copy/rename: Mac UI, frozen). Shots: snaps/audit-21-*.png.
Verdict: every item has code, but none is fully MET by the store bar: nothing seen on a headset, and the Quest water
screenshot check is silently skipped.

| # | Requirement | Grade | Evidence |
|---|---|---|---|
| 1 | Lily pads blend into the water | PARTIAL | Mesher.swift:566-580; chunk.vert:55-58 bobs pads at 0.7 of the swell while water uses waveK by shore distance, so they part in storms; no lily-pad shot anywhere |
| 2a | Horse: proper model | PARTIAL | Animals.swift:517 horseParts (jointed legs, neck, mane, tail; donkey/mule differ); flat untextured colours; no Quest render |
| 2b | Horse animation | PARTIAL | walk/gallop/graze poses render; motion never judged in play |
| 3a | Quest water: fresnel, sky reflection, waves | PARTIAL | water.frag:24-121 |
| 3b | Matches the Mac look, checked on screenshots | MISSING (now) | questcheck: "no shore within 1600 blocks (water view skipped)" (quest/src/headless/main.swift:252); no committed side-by-side |
| 4a | Walking follows head + left stick only | MET (sim) | questbugs hand-waving delta 0.0000; questcheck reclined walk dot 1.00 |
| 4b | Verified on device | PARTIAL | no headset |
| 5 | Far fewer animals | PARTIAL | cap 5, 1.75% chunk packs; old chunks keep their crowds and animals never despawn |
| 6 | Guns/tools much bigger on Quest | PARTIAL | QuestControls.swift:881, :1068 (sword ~1.55 m); no size setting, clipping unchecked |
| 7a | Mac Xbox Halo Infinite layout | MET | padtest |
| 7b | Halo-like sensitivity | PARTIAL | 170 deg/s at 3, 1.9x accel after 0.15 s; no curve test, no real pad |
| 8a | Lying-down recenter levels world/horizon/HUD incl. pitch | PARTIAL | QuestRig.swift:63-77, questcheck reclined checks; no headset |
| 8b | On a button and a menu option | MET (sim) | Menu hold 0.7 s + toast/haptic; QuestOptions "Recenter View" |
| 8c | Remembered | MET (code) | QuestSettings.swift:80 |
| 9 | Hunt and fix first-30-minute issues | PARTIAL | 3 fixes only; Worlds-list padtest fails, swamps nearly without open water, store-readiness open 2-6 |
| R1 | Backup + migration test | MET | Backups/all-worlds-before-task21-store-20261008; World377 loads 5435 chunks |
| R2 | Commit per item, checks pass | MET | 7 commits |
| R3 | Ship | MET | v74 then; never installed |
| R4 | Store quality | PARTIAL | device + dead water shot |
| E1 | Quest perf after the changes | PARTIAL | perf gate exists, no device numbers |
| E2 | Regression shot per item | PARTIAL | held items yes; water skipped; no lily/horse Quest shot |
| E3 | Failure states (storms, menus, riding) | PARTIAL | pads part in storms; recenter while riding/menu untested |
| E4 | Feedback | MET | recenter toast + haptic |
| E5 | Settings/comfort | PARTIAL | no held-item size option |
| E6 | Variety | MET | 5 coats + donkey + mule |

Gaps: device session (Remington: plug in the Quest); Quest water shot revived + pair committed; lily pads follow the
water's shore factor; one-time animal thinning on old saves (with migration test); held-item size option + clip check;
Halo sensitivity table test; swamp open water; textured horse coat (cloud lane: horses). Queued in
25b4zzz-blocksmith-audit-gaps.

## 25b4-blocksmith-apply-art-style (+x .. xxxxxx) — Opus reviewer
Counts from `--texnames` vs Resources/Textures; 9 shots snaps/audit-25b4-*.png; Quest CI run 38117715539.
Verdict: roughly half done. Terrain, ores, woods, plants and most icons match style 3 well; 865 of 1429 layers that
should be styled are (61%); nothing proven on the Quest renderer (CI Quest renders didn't even load texpack.bin).

| # | Requirement | Grade | Evidence |
|---|---|---|---|
| R1 | Re-texture every block | PARTIAL | 433/933; doors, trapdoors, glass, stained glass, beds, candles, glazed terracotta, shulkers, rails, torches, lanterns, tall grass, vines, lily pad procedural |
| R2 | Ores distinct but natural | PARTIAL | all ore layers styled; gold specks faint at 7 m, close to copper; ancient_debris_top, gilded_blackstone procedural |
| R3 | Every item | PARTIAL | 432/496 (64 missing; report said 12) |
| R4 | UI icons | PARTIAL | hearts/air styled; 39 effect icons, XP bar, font, panels not |
| R5 | Real materials, muted colours, subtle detail | MET | restyled set matches 3-stylised-realism.png; dirt path a bit orange |
| R6 | Cohesive with lighting/sky | PARTIAL | painted next to flat pixel blocks in one shot; blocky clouds |
| R7 | 32-64 px per face | PARTIAL | 128 px on purpose for the sharpness complaint; spec change never signed off |
| R8 | ASTC/ETC compression | MISSING | Quest uploads RGBA8 (~155 MB); only the Mac uses BC3 |
| R9 | Mipmaps | MET | Lanczos-2 mips, aniso 8 |
| R10 | No frame-time growth | MISSING | not measured on the headset after 128 px |
| R11 | Memory within limits | MET (computed) | ~155 MB vs 3 GB peak |
| R12 | Gemini sheets sliced into tiles | MET | 44 sheets, slice/derive tools |
| R13 | Every texture checked in golden shots | PARTIAL | galleries cover a subset; seams clean except nether_quartz_ore, deepslate_diamond_ore |
| R14 | Independent comparison to the reference | PARTIAL | mentioned in CREDITS, no written score |
| R15 | Don't copy the reference mob look | MET | |
| R16 | Sources in assets/CREDITS | PARTIAL | prompts recorded; no licence line (added as an open item in this audit) |
| R17 | Also on claude/blocksmith-playtest | PARTIAL | not merged (branches far apart); playtest branch is frozen Mac work now |
| R18 | Save keeps loading | MET | no save keys changed; questcheck 667 ok |
| R19 | Commit per batch | MET | 16 art commits |
| R20 | Ship a Quest build | MET (no install) | APK quest-129 carries texpack.bin |
| R21 | List what remains | PARTIAL | art-style-remaining.md was stale (recount added in this audit) |
| E1 | One style in a single shot | PARTIAL | pixel UI chrome, untextured mobs, blocky clouds; scorecard style row never re-scored |
| E2 | Readable at Quest resolution/distance | PARTIAL | numpy model only; CI Quest renders used procedural 32 px (fixed in this audit: headless loads texpack.bin) |
| E3 | Mips/aliasing/shimmer | PARTIAL | modelled, not measured on device |
| E4 | Memory efficiency | PARTIAL | ~4x an ASTC 4x4 pack |
| E5 | Variety within families | PARTIAL | 16-colour families (~100 layers) all procedural |
| E6 | Legal/originality | PARTIAL | original, prompts kept; licence unconfirmed |
| E7 | Regression shots | MET | galleries + hdatlas in the heavy lane |
| E8 | Tiling seams | MET | 2 marginal tiles |

Gaps: queued 25b4zzz-blocksmith-art-gaps (CHROME=1): ~300 layers of high-visibility families, 64 icons, gold ore
specks, 2 seams, UI/effect icons, one texpack commit. ASTC vs lossless and the 128 px spec change are Remington's
call (listed in the report). Fixed here: CI Quest renders load the art; remaining-list recount; licence open item.

## 25b4z-blocksmith-playtest-oct10am (+ gap rounds zx .. zxxxxx) — Opus reviewer
25b4zy (flesh-out) never ran, so graded against its own text. `--swingtest` 56 ok; `--rdgovernortest` PASS;
`--worldgencheck 24` pass; `--questbugs` 285 ok / 1 fail (maingun, not this task); `--towntests` 281 ok / **5 FAIL**
(cloud lane). All 38 voice notes have a status; 5 spot-checked "fixed" notes match the code. Shots:
snaps/audit-25b4z-{camp,camp2,volcano-far,town,texclose}.png.

| Requirement | Grade | Evidence |
|---|---|---|
| 1a Blur cause found, crisp at headset distance | PARTIAL | 64 px pack was the cause; now 128 px, sharp-bilinear, aniso 8; never seen on a headset |
| 1b Keep frame rate | PARTIAL | +146 MB GPU memory, est. < 0.2 ms; no device log |
| 1c Grass detail | MET | 80cd6bb4 |
| 1d Flower bush detail | MET | firefly bush painter |
| 1e Keep praised art | MET | untouched |
| 2a Auto render distance recovers | MET | rdgovernortest 16 -> 12 -> 16 |
| 2b Cause of the drops | PARTIAL | Mac proxy: taiga GPU-bound, 512k quads, 2/3 leaves; device unconfirmed |
| 2c Proof gains are permanent | PARTIAL | CI gate checks quad counts only (budget raised 360k -> 380k); frame times info-only |
| 3 Capital spacing across seeds | MET | 25 seeds, nearest city min 1248 |
| 4 Volcano far view blends in | PARTIAL | dark, sun-lit, but a hard cut-out on a pale haze band, no visible foothills at 650 blocks |
| 5 Ruined portals removed/rare | MET | 0 in worldgencheck |
| 6a All villagers become townsfolk incl. old saves | MET | towntest old-save conversion ok |
| 6b Wallet on HUD | PARTIAL (cloud) | HUD/inventory wallet checks fail with empty text (HonourTests.swift:218, HonourGapTests.swift:263) |
| 6c Emerald vs dollar documented | MET | economy.md |
| 6d Theft anger | MET | law test ok |
| 6e Sheriff replaces the golem | PARTIAL (cloud) | new towns ok; "sheriff shoots an outlaw player" FAILS; old towns keep golems by design |
| 6f English voice lines | MET | 14 voices, ~10 contexts, 4.97 MB ADPCM; not heard on headset |
| 7 Wild camps | MET | 5 kinds, ~5 per 2048^2, structcheck 0 |
| 8 Note 1 identified | MET | swing-mode melee |
| 9a No block breaking near creatures | MET | Game.swift:1139 |
| 9b Blocks only with trigger held | MET | blade never mines |
| 9c Real blade contact, min speed | MET | VRMelee swept capsule |
| 9d Enemy melee physically reaches | PARTIAL (cloud) | monsters MET; hostile townsfolk still centre distance (Townsfolk.swift:260, backlog T1) |
| 9e Haptics + hit flash | MET | |
| 9f Generous but physical reach | PARTIAL | reach 3.0, blade x1.3; feel untried |
| 9g Reclined mode replaces the alternative | MET | |
| 9h One-line descriptions in the menu | MET | |
| 10a Bow the right way round | PARTIAL | geometry tests pass; no rendered drawn-bow image |
| 10b-e String/arrow follow hand, haptics, release, both hands | MET | swingtest |
| Status copy of 38 notes | MET | |
| Ship a quest-dist build | PARTIAL | head APK failed to compile (getpid, CircuitWorkshopTests.swift:146): **fixed in this audit** |
| E1 VR comfort | PARTIAL | no headset |
| E2 Failure states | MET | |
| E3 Left-handed parity | MET | |
| E4 Saves/migration | MET | |
| E5 Quest perf proven on device | MISSING | no device log since 128 px + governor |
| E6 Variety | MET | |
| E7 Regression gates | PARTIAL | --towntests not in a CI lane, 5 FAIL |
| E8 Feedback | MET | |

Gaps: device perf proof (Remington: plug in the Quest; device-checklist.md section 1); towntests 5 FAIL + add to the
checks shard (cloud: towns, backlog A10); townsfolk melee (cloud, T1); volcano base blend, drawn-bow render,
perf-gate p99 gating -> queued 25b4zzza-blocksmith-audit-gaps.

## Audit gaps follow-up (task 25b4zzza..., 2026-10-11)

The gap rows above (task 21 rows 1, 3b, 5, E2, E3, E5; ships E3; volcano 4; bow 10a; swamps in 9) were worked in
commits bf7b9a2a, 092703b4, 66d617c4 and the "verifier fixes" / "volcano ground mist" commits. Checks:
`--questbugs --only gaps` (0 failures) and questcheck. Evidence (not in git):
~/ClaudeTools/projects/blocksmith-qa/runs/2026-10-11/audit-gaps (Mac/Quest water pair mac_water.jpg + stereo_water.jpg,
lily pond, volcano before/after, both drawn bows, Quest CI artifacts in ci/ and ci144/).

| Gap | Now | Proof |
|---|---|---|
| Pads part from the water in storms | MET | pad corners take the water's shore factor (648/648 match); lily_pond shots in snap.sh + questcheck |
| Quest water view skipped | MET | pinned seed-12345 beach, a skip is a FAIL; Quest CI 38147389994 wrote stereo_water*.png |
| Old saves keep animal crowds | MET | backup, then one-time thinning (format 4); questbugs migration test |
| Held item size option | MET | VR "Held Item Size" 0.8-1.5x, saved, sword + guns; QuestSim hip clearance 0.27 m eyes / 0.34 m floor at 1.5x |
| Capital-ship flight vignette | MET | QuestControls: ShipComfort.vignette while piloting, scaled by the comfort setting (pure-function check only) |
| Volcano far blend | MET (Mac), Quest render in CI | apron + sunk ring cells; ground mist thickens the haze down the flanks so the foot melts into the band |
| Drawn-bow render | MET | questcheck draws both bows at draw 1.00, the head turned to the bow |
| Perf gate p99 | MET | local: p99 > pin x 1.25 fails; CI: p99 > local pin x 2 fails; quads pinned at + 5% |
| Wool/sculk steps, firefight peak | MET | audiolevels.py gate in the checks shard |
| Swamps without open water | MET | 35% / 26% open water on 12345 / 777, pads on 14-15% of it |
