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
| Quest frame time, 6 routes | 72 fps, p99 <= 13.9 ms, <= 1 hitch > 25 ms/min | Mac proxy (2 eyes 1440x1584, rd 8): p99 10.0-11.4 ms on all six; hitches/min plains 2, capital 2 (max 112 ms), ashvault 12 (max 46 ms); 3/6 pass. Device numbers not measured (logcat perf line) | RED | routes_quest_proxy.md |
| Quest render distance >= 1.5x today | rd 12 at 72 fps (today 8) | Quest default now rd 12 at 72 Hz (was 90 Hz, guard cut rd to 5-9 in real play). Mac Quest proxy after the tick fixes: rd 12 p99 8.9-11.1 ms, 0-1 hitch/min (forest 3); 5/6 routes pass. Device not re-measured | AMBER | docs/status/evidence/2026-10-09-pm/quest-perf-log.md, `tools/quest_perf_gate.sh` |
| Memory | Quest peak <= 3 GB; < 2% growth in 30 min | Mac routes resident peak 292-371 MB; growth over 30 s: plains +10%, forest +14%, village +12% (warm-up, not a soak) | AMBER | routes_mac.md |
| Thermal soak | 30 min >= 72 fps | not measured (needs device) | RED (UNMEASURED) | - |
| Load times | title < 8 s, world < 10 s, no holes | route world preload 0.23-0.50 s at rd 8 (headless loadSync, not the app's launch path); title time not measured | AMBER | routes_mac.md (load ms) |
| Mac 60 fps at 1080p on the routes | p99 <= 16.7 ms, <= 1 hitch/min | p99 7.2-12.2 ms; hitches/min plains 2, forest 2, capital 4 (max 33 ms); 3/6 pass | RED | routes_mac.md |

## 2. Stability and saves
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Crashes | 0 in a 4-hour bot soak + 100 save/load cycles | CI smoke is 60 s x 3 render distances; no 4 h soak or 100-cycle save test exists | RED (UNMEASURED) | .github/workflows/mac.yml smoke |
| Save safety | old saves load, backup before migration | no migration test on real old saves | RED (UNMEASURED) | - |

## 3. Controls, feel and VR comfort
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Movement (sprint >= 1.5x every direction) | QuestSim tests | covered by QuestBugTests (`--questbugs`), not re-measured this round | AMBER | Sources/QuestBugTests.swift |
| Reach | blocks 6, melee ~3 | block reach constant 6 (Game.swift:902); melee not measured | AMBER | code only |
| Input conflicts | no press does two things | Mac pad: 0 conflicts over 16 buttons x tap/hold x 4 contexts (foot, horse, car, inventory); keyboard: 0 duplicate defaults. Verifier: the diff only sees menu/pause/hotbar/camera/mount/helm/flight/sneak/drop/jump, not attack/use/place/aim/fire/throttle, so 0 is an undercount. Quest Touch bindings not covered; contexts missing: swimming, flying, ship deck, gun held, deck gun | AMBER (verified, weak measure) | input_matrix.md |
| Comfort checklist | snap/smooth turn, vignette, recenter, seated, height, pause on headset removal | step-ups now eased for every mount and on foot, Mac + Quest camera: max 0.05-0.11 block/frame at 72 Hz (fastest horse 0.133, its true climb rate) vs 1.0 snapped before (verified). Rest of the checklist not audited | AMBER | `--questbugs --only pm9a` |
| Horse handling (western feel) | gaits, momentum, stamina, bond, nerves, sure footing (docs/status/horses.md) | 29 HorseTests checks pass: gaits 1.7/8/16 b/s, 0 to gallop 1.6 s, stop 1.5 s, worst 12 b/s^2; level-1 gallop 15.6 s; refuses cliffs/lava (also rearing and backing), rides stairs; frights by level; spur via Game.tick pad click. Verifier pass 1 found 2 blockers + 4 more (all fixed with checks). Device feel not tested | AMBER (pending verifier pass 2 / device) | `questcheck --horse-only` |
| Response within one frame | input-latency test | not measured | RED (UNMEASURED) | - |

On claude/blocksmith-playtest the same matrix finds 1 conflict: on foot, LB hold = hotbar + drop item.

Notes from the matrix (not conflicts, worth a look): the D-pad left opens Commands even while driving; in the inventory Y does
nothing and LB/RB open the crafting book; D-pad down drops on tap but not on hold.

## 4. Visual quality and art direction
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| One coherent style (style 3 stylised realism) | all shots match docs/art/style-options/3-stylised-realism.png | every shot is still the blocky 16 px look; scores below | RED | golden_mac_sheet.jpg |
| Ground noise | calm grass/flowers | plant counts per biome: short grass 66 -> 7 per chunk (x0.106), desert cactus 1.24 -> 0.40/chunk, ferns/dead bush/cane/leaf litter/flowers cut (verified). No image noise metric yet | AMBER | docs/status/evidence/2026-10-09-pm/plants.md, `--only pm9b` |
| Models | believable mobs | connectivity: every mob kind stays in one piece over 19,392 walk/gallop/knockback/hurt poses (14 kinds had gaps, incl. the horse knee; verified). Head look/attack/sit poses not covered; believability not reviewed | RED (only connectivity measured) | `--questbugs --only pm9a` |
| Sky | realistic sky + clouds | blocky cloud slabs (base_battle, frigate); dusk/night readable | RED | golden_mac_sheet.jpg |
| Defects: flicker | no z-fighting/flicker | 0-4 ppm on 7 world shots (threshold ok < 20; synthetic speckles read 182 ppm, so the detector works); only a 0.02 deg nudge, no time step | AMBER | flicker.txt |
| Defects: floating trees, light leaks | none | not measured | RED (UNMEASURED) | - |

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
| Coverage | every block/item/mob/vehicle/UI sound | all 20 materials have break/place/step/hit/fall; mob kinds without a voice: deckGun, ashTank, ashHalftrack, ashArtillery, ashTruck (crystal, minecart, boat, armour stand allowed); items not audited | RED | audio_audit.md |
| Context: dry vs wet steps | dry surfaces sound dry | block mapping correct (grass, dirt, stone, sand, gravel, planks...: no dry block on mud/slime). Rendered steps: wool and sculk measure closer to mud/slime than to stone/gravel/wood; wood is borderline (1.52 vs 1.43); grass/dirt measure dry. The "wet" Remington hears may be the reverb wet mix (AudioAmbience: wet = max(enclosure^2, cave*0.6)) rather than the step renders: untested | AMBER | audio_audit.md, audio_levels_summary.md |
| Context: ambience by place/time | no birds underground, at night, Deep, Ash Vault | 60 s of the director each: forest noon 12 bird calls; forest midnight 0 (owl + crickets); cave under forest (y 51) noon/midnight 0 wildlife; Ash Vault 0; Deep hell band 0. plus a shallow dark cave 6-20 blocks down near the forest surface (the reported case; y 68, sky light 0) at noon: 0 wildlife. Not tested: the reverb wet mix near entrances, caves in other biomes | AMBER | audio_audit.md |
| Mix | music ~ -16 LUFS, SFX peaks <= -1 dBFS, no clipping | music -18.7 to -27.1 LUFS (all 19 pieces below target); 191 SFX peak above -1 dBFS; 0 clipped files | RED | audio_levels_summary.md |
| Music | composed tracks per context | still synthesized; licence questions open (store-readiness.md) | RED | - |

## 6. Content, progression and balance
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| First hour | always a next goal | not measured this round | RED (UNMEASURED) | - |
| Progression | all tiers reachable in sane time, 10 seeds | `--playthrough` exists (one seed, CI heavy lane); 10-seed timings not run | AMBER | Sources/Playthrough.swift |
| Balance | TTK tables in range | not measured | RED (UNMEASURED) | - |
| Copper circuits (redstone parity) | every Java redstone component + behaviour | 111/111 checklist rows pass (verified spot-check: real behaviour asserts); pistons move instantly (Java 2 ticks), 0-tick tricks skipped | AMBER | docs/status/copper-parity.md, `--coppertest` |
| Bone meal | works wherever Bedrock's does | 64 targets grow via the right-click path, 10 non-targets refuse; stems/glow lichen/mangrove leaves/tall seagrass absent from the game | GREEN (verified) | docs/status/evidence/2026-10-09-pm/bonemeal.md, `--only pm9b` |
| Enchanting table | classic offers incl. Fortune/Gentle Touch, multi-enchants | pickaxe lvl 30: Fortune 32%, Gentle Touch 17%, never together; multi-enchant 63-75% (books 21%) | GREEN (verified) | docs/status/evidence/2026-10-09-pm/pm9d-enchant-distribution.txt, `--only pm9d` |

## 7. World, mobs and AI
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Spawn density | not empty, not swarms | Oct 9 PM: surface monsters halved (3 nights: 63 -> 33, caves 84 -> 93, verified). Earlier: 30 s per time of day, 50 seeds, player 12 above spawn: midnight surface hostiles median 10 (max 16, zero on 3 seeds); passive surface median 10 (zero on 1 seed at noon); noon surface hostiles median 5 (max 27; mostly creepers/skeletons/zombies; "surface" = above column height - 6, so shade under trees/overhangs counts) - needs a look | AMBER | world_audit.md |
| Behaviour | no stuck mobs, no friendly fire | not measured this round (agents exist: `--agent`) | RED (UNMEASURED) | - |
| World gen: safe spawn | safe spawn | 0/50 unsafe (game spawnPoint: feet/head clear, full ground, no lava within 2, no water within 1) | GREEN (verified; cactus, fire, cliff edges, nearby hostiles not checked) | world_audit.md |
| World gen: overlaps | no structure overlaps | 138 piece-level overlaps in 50 seeds x 2048^2: military_base + ruined_portal 26, military_base + village 8, capital_city + ruined_portal 5, ocean_ruin + shipwreck 14, mineshaft + trial_chambers 32 (underground) | RED | world_audit.md |
| World gen: findability | bases/citadels findable | distance from spawn: Capital citadel median 428 (max 1544), Capital city median 752 (max 1980), village median 479 (max 2043, 1 seed > 2000) | AMBER (no target distance set) | world_audit.md |

## 8. UI and UX
| Metric | Target | Current | Status | Evidence |
|---|---|---|---|---|
| Legibility / no truncation | readable, nothing cut | 48 screens: 8 flags. Real: creative menu hint line runs off both screen edges at 1280x800 (1386 px wide). By design: credits scroll off the bottom. To review: tooltips (Iron Chestplate, Coal Ore, Torch) extend past their menu panel. Smallest text 12 px (options, 1280x800); VR angular size not measured | RED | ui_overflow.md |
| Consistency | one style, controller everywhere, settings persist | not reviewed | RED (UNMEASURED) | - |
| Accessibility | subtitles, colour-safe, per-bus volume | per-category volume sliders exist (SoundCategory); subtitles not found | RED | Sources/Sound.swift |

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
