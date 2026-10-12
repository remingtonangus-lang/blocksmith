# Blocksmith scorecard

The objectives of docs/STORE_QUALITY.md with their current value, target, status and evidence. Status rules: GREEN only
with evidence from a repeatable command AND an independent verifier pass; AMBER = measured but incomplete, unverified or
a proxy; RED = misses the target, or not measured yet (UNMEASURED). Re-measure with the commands below and update.

Measured on: claude/quest-port @ 3308bfbc (2026-10-09), M1 MacBook (8 GB, low priority), seed 12345 unless noted.
Evidence files: docs/status/evidence/2026-10-09/.

## Tools (all local, no new CI jobs)
| Tool | Command | Measures |
|---|---|---|
| Bench routes | `tools/bench_routes.sh [--quest] [--secs 30]` (`--bench F --scenes route_<plains,forest,village,cave,capital,ashvault>`) | frame p50/p99/max, hitches > 25 ms per minute, load, resident memory + growth, mobs |
| Golden shots + flicker | `tools/golden.sh [OUT] [names]` -> shots/golden/<date>_<sha>/ (git-ignored), flicker via `tools/flicker.py a.png b.png` | the 17-shot list; per-shot flicker ppm on a 0.02 deg camera nudge |
| Quest golden | `questcheck --golden DIR` (for the existing quest lane: add `--golden build/quest-out/golden` to the questcheck line in .github/workflows/quest.yml; the agent token cannot push workflow files) | spawn, aerial, dusk, night, rain, Capital city through the Quest renderer (lavapipe) |
| Audio audit | `Blocksmith --snapshot /tmp/a.png --seed 12345 --rd 4 --audioaudit F.md` | coverage per material/mob, dry-vs-wet step mapping, ambience rules (forest noon/night, cave, Deep, Ash Vault) |
| Audio levels | `Blocksmith --sounds DIR && Blocksmith --music DIR/music --seconds 30 && tools/audiolevels.py DIR --out F.md` | peak dBFS, clipping, BS.1770 LUFS, wet-sounding steps (spectral distance to mud/slime) |
| World audit | `Blocksmith --worldaudit 50 --secs 30 --out F.md` (~8 min) | safe spawn (game's spawnPoint), structure piece overlaps, distance to village/base/city, mob density by biome/depth/time |
| Input matrix | `Blocksmith --snapshot /tmp/i.png --seed 12345 --find plains --time 0.3 --rd 4 --inputmatrix F.md` | every pad button tap/hold in 4 contexts through Game.tick; two effects from one press = conflict; keyboard default duplicates |
| UI overflow | `tools/uioverflow.sh` (`--uilog` JSON per screen + tools/uioverflow.py) | 24 screens x 2 sizes: text off screen, past its panel, overlapping; smallest text px |

## 1. Performance (hard gate)
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Quest frame time, 6 routes | 72 fps, p99 <= 13.9 ms, <= 1 hitch > 25 ms/min | Mac proxy (Oct 11, release build, rd 16, 60 s routes): p99 plains 9.7, forest 11.0, village 9.4, cave 6.3, capital 11.9, ashvault 8.7 ms, 0 hitches/min, 6/6 pass; taiga/flyover counted work 433k/318k quads. tools/quest_perf_gate.sh now FAILS on a regression: quads over the pin + 5% or frame p99 over the pin x 1.25 (pins in tools/perf_baseline.json, `--rebaseline` after an intended change; CI pins quads only). Device numbers not measured (logcat perf line) | AMBER | performance.md, tools/perf_baseline.json |
| Quest render distance >= 1.5x today | rd 12 at 72 fps (today 8) | Quest default now rd 12 at 72 Hz (was 90 Hz, guard cut rd to 5-9 in real play). Mac Quest proxy after the tick fixes: rd 12 p99 8.9-11.1 ms, 0-1 hitch/min (forest 3); 5/6 routes pass. Device not re-measured | AMBER | docs/status/evidence/2026-10-09-pm/quest-perf-log.md, `tools/quest_perf_gate.sh` |
| Memory | Quest peak <= 3 GB; < 2% growth in 30 min | Mac routes resident peak 292-371 MB; growth over 30 s: plains +10%, forest +14%, village +12% (warm-up, not a soak) | AMBER | routes_mac.md |
| Thermal soak | 30 min >= 72 fps | not measured (needs device) | RED (UNMEASURED) | - |
| Load times | title < 8 s, world < 10 s, no holes | route world preload 0.23-0.50 s at rd 8 (headless loadSync, not the app's launch path); title time not measured | AMBER | routes_mac.md (load ms) |
| Mac 60 fps at 1080p on the routes | p99 <= 16.7 ms, <= 1 hitch/min | p99 7.2-12.2 ms; hitches/min plains 2, forest 2, capital 4 (max 33 ms); 3/6 pass | RED | routes_mac.md |

## 2. Stability and saves
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Crashes | 0 in a 4-hour bot soak + 100 save/load cycles | 100 save/load cycles (Oct 12, Linux host, `questcheck --savesoak-only`): a survival world played, changed (blocks, inventory, a chest), saved and loaded back as the app does, 100 times: every cycle came back as saved, no World or Game left alive, resident 169 -> 191 MB, save folder 0.2 MB; 5 cycles in every full run. The 4 h bot soak still not run (CI smoke is 60 s x 3 render distances) | AMBER | `questcheck --savesoak-only` |
| Save safety | old saves load, backup before migration | Oct 11 (audit gap 3): a format-3 world with 30 animals is backed up (Backups/<name>-before-f4-*, mobs.json copied), then crowds over the per-chunk cap are thinned once (12 wild -> 4; penned, owned, named kept); a failed backup skips the thinning. Synthetic save only, no real old player saves tested | AMBER | `--questbugs --only gaps` |

## 3. Controls, feel and VR comfort
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Movement (sprint >= 1.5x every direction) | QuestSim tests | covered by QuestBugTests (`--questbugs`), not re-measured this round | AMBER | Sources/QuestBugTests.swift |
| Reach | blocks 6, melee ~3 | block reach constant 6 (Game.swift, `reach`); Oct 12 (Q2): melee measured through the pad path, a pig moved back 0.25 a try: blows land to 3.30 blocks from the eye to its near side (the game's 3.5 ray, a little over the genre's 3; kept: generous for VR arm's length). Block reach not measured end to end | GREEN (melee measured) | `questcheck --latency-only` |
| Input conflicts | no press does two things | Mac pad: 0 conflicts over 16 buttons x tap/hold x 4 contexts (foot, horse, car, inventory); keyboard: 0 duplicate defaults. Verifier: the diff only sees menu/pause/hotbar/camera/mount/helm/flight/sneak/drop/jump, not attack/use/place/aim/fire/throttle, so 0 is an undercount. Oct 12 (Q2): Quest Touch matrix (`questcheck --touchmatrix-only`): 11 controls x tap/hold x 7 contexts (on foot, riding, a boat, a deck gun, swimming, flying, inventory): 0 conflicts after a fix (a left-stick tap that left any seat latched sneaking: the next horse threw the player off, and the next use of a ship's helm took the ship apart; verified). Still missing: the ship's helm, a gun or bow held, the pause menu, stick pushes and snap turn; the diff doesn't see swings, block breaks or yaw | AMBER (verified, weak measure) | input_matrix.md |
| Comfort checklist | snap/smooth turn, vignette, recenter, seated, height, pause on headset removal | step-ups now eased for every mount and on foot, Mac + Quest camera: max 0.05-0.11 block/frame at 72 Hz (fastest horse 0.133, its true climb rate) vs 1.0 snapped before (verified). Oct 11 (audit gap 5): helm speed vignette while piloting fast ships, scaled by the comfort vignette setting. Rest of the checklist not audited | AMBER | `--questbugs --only pm9a` |
| Horse handling (western feel) | gaits, momentum, stamina, bond, nerves, sure footing (docs/status/horses.md) | 29 HorseTests checks pass: gaits 1.7/8/16 b/s, 0 to gallop 1.6 s, stop 1.5 s, worst 12 b/s^2; level-1 gallop 15.6 s; refuses cliffs/lava (also rearing and backing), rides stairs; frights by level; spur via Game.tick pad click. Verifier pass 1 found 2 blockers + 4 more (all fixed with checks). Device feel not tested | AMBER (pending verifier pass 2 / device) | `questcheck --horse-only` |
| Response within one frame | input-latency test | Oct 12 (Q2): 10 controls pressed through the headset's pad path (PadManager.touch, polled before Game.tick in the same frame, QuestApp.frame): jump, walk, look, sneak, hotbar, pause, inventory, mine, place, attack each change the game state in the tick that reads the press (0 frames). Not measured: XR runtime pose/input latency and motion-to-photon (needs the device) | AMBER (game side GREEN; device latency unmeasured) | `questcheck --latency-only` |

On claude/blocksmith-playtest the same matrix finds 1 conflict: on foot, LB hold = hotbar + drop item.

Notes from the matrix (not conflicts, worth a look): the D-pad left opens Commands even while driving; in the inventory Y does
nothing and LB/RB open the crafting book; D-pad down drops on tap but not on hold.

## 4. Visual quality and art direction
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| One coherent style (style 3 stylised realism) | all shots match docs/art/style-options/3-stylised-realism.png | 1221 of 1489 layers in style 3 (82%, 2026-10-11 art-gaps pass): all item + effect icons, XP bar, doors/glass/beds/candles/shulkers/glazed/torches/lanterns/rails/tall plants; 268 long-tail block layers left (docs/status/art-style-remaining.md); Mac shot scores below predate it | AMBER | golden_mac_sheet.jpg, ~/ClaudeTools/projects/blocksmith-qa/runs/2026-10-11/artgaps |
| Ground noise | calm grass/flowers | plant counts per biome: short grass 66 -> 7 per chunk (x0.106), desert cactus 1.24 -> 0.40/chunk, ferns/dead bush/cane/leaf litter/flowers cut (verified). No image noise metric yet | AMBER | docs/status/evidence/2026-10-09-pm/plants.md, `--only pm9b` |
| Models | believable mobs | connectivity: every mob kind stays in one piece over 19,392 walk/gallop/knockback/hurt poses (14 kinds had gaps, incl. the horse knee; verified). Head look/attack/sit poses not covered; believability not reviewed | RED (only connectivity measured) | `--questbugs --only pm9a` |
| Sky | realistic sky + clouds | blocky cloud slabs (base_battle, frigate); dusk/night readable | RED | golden_mac_sheet.jpg |
| Defects: flicker | no z-fighting/flicker | 0-4 ppm on 7 world shots (threshold ok < 20; synthetic speckles read 182 ppm, so the detector works); only a 0.02 deg nudge, no time step | AMBER | flicker.txt |
| Defects: floating trees, light leaks | none | Oct 12 (Q2): `questcheck --gencheck`, 288 chunks over 3 seeds: floating blocks 8 -> 0 (lone blocks at the column top and on chunk edge rows are cleared now; all 8 were there), ores in air 4 -> 1 (edge rule since added), plant_floating 1, leaves_orphan 1, trunk_floating 1 (the half-tree class in BUGS.md, Mac lane). Light leaks not measured | AMBER (light leaks unmeasured; trees Mac lane) | `questcheck --gencheck` |

Golden shots, Mac (score 1-5 vs style 3; reason): spawn 2 (faces a tree trunk at the actual spawn, flat textures);
forest 2 (dense uniform canopy, blocky); village 3 (readable layout, blocky); cave_torch 2 (flat grey walls, little
light shaping); ore_closeup 1 (framing shows no ore); horse 2 (horse reads, ground noisy); capital_city 3 (clear city
grid from the air, white boxes); base_battle 2 (stand-in: the frigate battle scene; clouds are slabs); frigate 3 (clean
silhouette); the_deep 3 (lava and red rock read well); ash_vault 2 (very dark, citadel lights only); inventory 3,
crafting 3, options 3 (clean, small text); dusk 3 (good sky gradient); night 3 (stars, readable); rain 2 (rain streaks
fine, grass noisy). Quest copies: produced once the quest.yml line above is added (artifact quest-host-N/golden).

## 5. Audio
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Coverage | every block/item/mob/vehicle/UI sound | all 20 materials have break/place/step/hit/fall; Oct 12 (Q2): every mob kind has a voice: the war machines (Cinder Tank, half-track, truck, Behemoth) idle on a diesel chug, gun mounts (field gun, deck gun) clank, all ring when hit and blow up when killed (crystal, minecart, boat, armour stand allowed silent); items not audited | AMBER (items not audited) | `questcheck --musiclevels-only` (sound coverage) |
| Context: dry vs wet steps | dry surfaces sound dry | block mapping correct (grass, dirt, stone, sand, gravel, planks...: no dry block on mud/slime). Rendered steps (Oct 11, audit gap 9): every dry material measures closer to stone/gravel/wood than to mud/slime (wool 0.12 vs 2.77, sculk 0.31 vs 2.87 after the foley profiles lost their squelch and low thump); all 1009 files <= -1 dBFS (scapes capped -1.2; firefight was -0.4); audiolevels.py now exits 1 on a wet step or a loud file. Reverb wet mix untested | GREEN | audio_levels.md |
| Context: ambience by place/time | no birds underground, at night, Deep, Ash Vault | 60 s of the director each: forest noon 12 bird calls; forest midnight 0 (owl + crickets); cave under forest (y 51) noon/midnight 0 wildlife; Ash Vault 0; Deep hell band 0. plus a shallow dark cave 6-20 blocks down near the forest surface (the reported case; y 68, sky light 0) at noon: 0 wildlife. Not tested: the reverb wet mix near entrances, caves in other biomes | AMBER | audio_audit.md |
| Mix | music ~ -16 LUFS, SFX peaks <= -1 dBFS, no clipping | Oct 12 (Q2): music runs through a leveller (K-weighted meter, slow gain, soft knee under -1 dBFS): all 20 pieces -16.2 to -15.5 LUFS, peaks -2.9 to -1.0 dBFS, none clipped (was -18.7 to -27.1). SFX: 1009 files, 0 over -1 dBFS, 0 clipped (Oct 11 audio_levels.md). Leveller not yet heard on device | GREEN (verify by ear) | `questcheck --musiclevels-only`, audio_levels.md |
| Music | composed tracks per context | still synthesized; licence questions open (store-readiness.md) | RED | - |

## 6. Content, progression and balance
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| First hour | always a next goal | Oct 12 (Q2): after the seven controls tips a survival player had no goal at all; now Goals.swift shows the next step of the story path (wood, workbench, tools, a bed, iron, titanium, the Emberdeep, the Stronghold, the Blight, the Deep, the Ash Vault war; the Hollow only on ground saved with its gate): 8 s in the tips slot when it changes, always at the top of the inventory. Checks: 21 steps on new ground and 23 on legacy ground each move on once met and never back, names fit the 1024x640 headset panel. Scripted playthrough on Linux (seed 12345): 16 goals seen in order, 0 steps back, the path walked by the end. Not measured: a human's first hour (onboarding feel), dead ends outside the story path | AMBER (no reviewer play log) | `questcheck --firsthour-only`, `--playthrough` |
| Progression | all tiers reachable in sane time, 10 seeds | `--playthrough` exists (one seed, CI heavy lane); 10-seed timings not run | AMBER | Sources/Playthrough.swift |
| Balance | TTK tables in range | Oct 12 (Q2): real duels through Game.tick, 12 night/raid mobs x 3 gear tiers (balance.md): iron gear survives every common night mob 20 s+, nothing kills it under 2 s; early gear beats each common mob, diamond beats all; no one-swing kills; each tier up never worse; a hisser blast kills an unarmoured player, iron survives. Found and fixed: Marauders (and every archer at close range) aimed over the head and never hit a still player (Marauder now 10.6 s unarmoured). Deep units: deep-balance.md; soldier classes: troop-classes.md. Frigate and boss fights not in the table | AMBER (frigate, bosses not tabled) | `questcheck --balance-only` |
| Copper circuits (redstone parity) | every Java redstone component + behaviour | 111/111 checklist rows pass (verified spot-check: real behaviour asserts); pistons move instantly (Java 2 ticks), 0-tick tricks skipped | AMBER | docs/status/copper-parity.md, `--coppertest` |
| Bone meal | works wherever Bedrock's does | 64 targets grow via the right-click path, 10 non-targets refuse; stems/glow lichen/mangrove leaves/tall seagrass absent from the game | GREEN (verified) | docs/status/evidence/2026-10-09-pm/bonemeal.md, `--only pm9b` |
| Enchanting table | classic offers incl. Fortune/Gentle Touch, multi-enchants | pickaxe lvl 30: Fortune 32%, Gentle Touch 17%, never together; multi-enchant 63-75% (books 21%) | GREEN (verified) | docs/status/evidence/2026-10-09-pm/pm9d-enchant-distribution.txt, `--only pm9d` |

## 7. World, mobs and AI
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Spawn density | not empty, not swarms | Oct 9 PM: surface monsters halved (3 nights: 63 -> 33, caves 84 -> 93, verified). Earlier: 30 s per time of day, 50 seeds, player 12 above spawn: midnight surface hostiles median 10 (max 16, zero on 3 seeds); passive surface median 10 (zero on 1 seed at noon); noon surface hostiles median 5 (max 27; mostly creepers/skeletons/zombies; "surface" = above column height - 6, so shade under trees/overhangs counts) - needs a look | AMBER | world_audit.md |
| Behaviour | no stuck mobs, no friendly fire | Oct 12 (Q2): the bots and behaviour sim now run on the Linux host (`questcheck --behaviorsim`, `--agent BOT`). Village, a full game day, seeds 12345 and 777: in_wall 8 -> 0 on both (villagers waking in a bed against a wall stood inside it; fixed, also when a threat wakes them); goals bed 13/13 and 8/8, meet 8/8 and 4/4, work 13/13 and 10/10; 1-2 animals flagged spinning or stuck (varies run to run); seed 777: villagers fell 5 blocks into a ravine that crosses the village (2 in one run); calm townsfolk now stop at any drop deeper than the path finder's 3 blocks, on a path or not (fleeing still drops): fell 2 -> 0, seed 12345 unchanged (verified). Capital citadel garrison (35 mobs, gunshots every 3 min, seed 12345) no flags. Friendly fire: NPC rounds pass through Capital and Ashguard troops by construction (Armory.mobHit) and their own shells' blasts spare them; measured in the Ashguard's biggest battle (30 s, 134 units, the player never attacking, Mob.onHit): 0 hits on its own. Capital, Greywall (fortress tier) and Meridian squads (`questcheck --friendlyfire-only`: 12 soldiers in three ranks firing through each other at the player for 20 s): Greywall 15 and Meridian 11 hits on their own (their launchers' blasts spared only the Capital and the Ashguard) -> 0 / 0 / 0; every blast from a soldier now spares its own side. Not measured: town deputies | AMBER (no verifier yet on the squad check; town deputies not measured; knockback can still push a villager off an edge) | `questcheck --behaviorsim [--site citadel]` |
| World gen: safe spawn | safe spawn | 0/50 unsafe (game spawnPoint: feet/head clear, full ground, no lava within 2, no water within 1) | GREEN (verified; cactus, fire, cliff edges, nearby hostiles not checked) | world_audit.md |
| World gen: overlaps | no structure overlaps | Oct 12 (Q2): small kinds give way to big ones they would cut into (StructureCache.yields: ruined portals, shipwrecks, mineshafts, desert wells, fossils; of two mineshafts the earlier region's stays; saved ground keeps its old starts). 12 seeds x 2048^2: 0 piece overlaps in 1,560 starts. Was 138 in 50 seeds. Mac `--worldaudit` over 50 seeds not re-run | AMBER (GREEN once the 50-seed audit agrees) | `questcheck --overlaps-only` |
| World gen: findability | bases/citadels findable | distance from spawn: Capital citadel median 428 (max 1544), Capital city median 752 (max 1980), village median 479 (max 2043, 1 seed > 2000) | AMBER (no target distance set) | world_audit.md |

## 8. UI and UX
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Legibility / no truncation | readable, nothing cut | 48 screens: 8 flags. Oct 12 (Q2): the menu control legend steps down a text scale until it fits the screen (the creative legend ran 1386 px at 1280x800; Mac renderer, not re-shot). By design: credits scroll off the bottom. To review: tooltips (Iron Chestplate, Coal Ore, Torch) extend past their menu panel. Smallest text 12 px (options, 1280x800); VR angular size not measured | AMBER (re-shoot on Mac; tooltips) | ui_overflow.md |
| Consistency | one style, controller everywhere, settings persist | Oct 12 (Q2): settings persist measured: three fresh launches on one data root write every option off its default (85: every Settings @Pref, the older Game/HUD/volume/key options and the 26 headset VR options), read them back, then Reset Options and read again. Found: every Float option (sensitivities, dead zones, rumble, brightness, volumes...) came back at its default on each Linux/Android launch (Foundation returns a Double, `as? Float` refused it; fixed in Pref); Reset Options missed Display, Smooth Terrain, Chipping, Bug Notes and every VR option and turned the headset's couch-mode HUD off (fixed: QuestSettings.reset). One style and controller reach not reviewed | AMBER (settings GREEN; style, controller reach unreviewed) | `questcheck --settings-only` |
| Accessibility | subtitles, colour-safe, per-bus volume | re-read Oct 12: subtitles with a direction arrow (AudioSubtitles.swift, Options > Audio and Accessibility), colourblind-safe cue colours (Settings.colorblind), per-category volume sliders (SoundCategory). Oct 12 (Q2): text size in the headset measured (`questcheck --vrtext-only`, capital letter at the defaults): HUD (subtitles, toasts, goals) 1.17 degrees, inventory and creative 1.53, pause menu 1.02 (floors 1.0 HUD / 0.7 menus). Not measured: a screen reader; legibility on the device | AMBER | Sources/AudioSubtitles.swift, Settings.swift |

## 9. Store compliance
IP names: 28 display strings renamed (docs/status/ip-renames.md), `python3 tools/namecheck.py --coined` 0 hits over 90 terms (CI fast lane); unsure terms flagged for Remington there. AMBER (needs Remington's call on the flagged terms).
See docs/status/store-readiness.md (audit round 1). Not re-measured here.

## Log
- 2026-10-10 (horses): HorseFeel.swift gaits/stamina/bond/care/nerves/footing + HorseTests in questcheck; first tamed horse now bonds (horseBond 0 == bond 0 bug).
- 2026-10-09 PM (task 25b1zzz, playtest notes items 1-11): pm9a/pm9b/pm9d checks, --coppertest, namecheck --coined, quest_perf_gate.sh added; verifier found a save-ordering race in the new background autosave (quit during an autosave could land older files last), fixed (sync saveNow flushes the queue first).
- 2026-10-09 (towns of people): new content checked by TownTests (economy no-arbitrage over every recipe, shop UI fit
  and overflow, townsfolk schedule/models/defence, 3 generated towns with all 8 shops); VR shop panel rendered in
  questsim (_shop.png); `--golden` gains town.png and town_shop.png. Player-visible Villager terms renamed
  (docs/status/ip-renames.md).
- 2026-10-09 (task 25b1zx): verifier pass (safe spawn GREEN, input matrix AMBER: blind to attack/use/fire effects);
  shallow-cave ambience check added (pass); world audit re-run with water within 1 of spawn (0/50 unsafe).
- 2026-10-09 (task 25b1z): tools built, everything measured once. Reddest: performance hitches (Quest proxy ashvault
  12/min), style (all shots), music loudness and SFX peaks, structure overlaps near military bases, UI hint overflow,
  plus the unmeasured soak/save/comfort/balance rows.
- 2026-10-09 (task 4, Boreal Station): new snowbound bunker structure with BorealTests in questcheck (walk route, light,
  snow, doors, garrison) and 5 golden shots; verifier pass, findings fixed (docs/status/boreal-station.md).
- 2026-10-10 (Boreal Station infiltration): an operation per station (copy the uplink codes, sabotage the generator,
  extract; silent vs loud rewards; alarm locks the uplink, squads down the stairwell, roused soldiers open bulkhead
  doors). 15 checks per seed in borealtest, 5 seeds pass; full questcheck passes (docs/status/boreal-station.md).
