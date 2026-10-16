# Blocksmith store-quality standard (Meta Horizon Store + Mac)

Owner: Remington. Written Oct 9 2026. Every Blocksmith session reads this first. Work is judged against these
objectives and their measurements, not against "the bug list". Remington's reports are inputs, not the plan.

## How work is directed
1. `docs/status/scorecard.md` lists every objective below with its metric, current value, target and status
   (RED / AMBER / GREEN), the build it was measured on and the evidence (test name, log, screenshot path).
2. Each session picks the reddest, highest-impact objectives, improves them, re-measures, updates the scorecard.
3. Nothing is GREEN without evidence produced by a repeatable command. "Should work" or "looks fine" is AMBER at best.

## Standards against AI blind spots (mandatory)
- **Evidence or it didn't happen.** Every claimed fix cites a test, a measured number or a judged screenshot.
- **Independent verifier.** A builder never grades its own work. Before an objective goes GREEN, a fresh subagent
  (Opus, no access to the builder's reasoning) gets only this spec, the claim and the build, and must try to break it.
- **Every reported bug becomes a regression test** (like the sprint test), so it can never silently return.
- **Fix the class, not the instance.** A report like "footsteps sound wet" means audit every sound's context rules;
  "birds in caves" means audit every ambience rule; "sprint not faster" means verify every movement modifier.
- **Proactive hunting quota.** Each round spends at least a third of its time on objectives with no open reports,
  and logs what it looked for and found (finding nothing is suspicious: look harder or change method).
- **Pre-mortem.** Before closing a feature, list 5 ways a player could break or dislike it and test each.
- **Golden shots.** A fixed list of camera shots (below) is rendered every build on Mac and in QuestSim; a reviewer
  compares against the previous build and the art direction, scoring each 1-5 with a written reason.
- **Measure on Quest-equivalent settings**, never only on the Mac path.
- **No regressions:** a change that drops any GREEN metric is reverted or fixed before ship.

## Objectives and how each is measured

### 1. Performance (hard gate)
| Metric | Target | How measured |
|---|---|---|
| Quest frame time, 6 benchmark routes | 72 fps; p99 <= 13.9 ms; no hitch > 25 ms more than once per minute | `--bench` runner flies/walks fixed routes (plains spawn, forest, village, cave, Capital city/base battle, Ash Vault battle), logs frame times |
| Quest render distance at that frame rate | >= 1.5x today's | bench at increasing distances |
| Memory | Quest app peak <= 3 GB; < 2% growth over a 30-min soak | allocator stats + soak run |
| Thermal soak | 30 min with no drop below 72 fps | soak run on device/QuestSim |
| Load times | title < 8 s, world < 10 s; no visible chunk holes inside view distance | timed launch, pop-in detector |
| Mac (M1 Air) | 60 fps at 1080p on the same routes | same bench |
`docs/status/performance.md` explains in plain English what costs compute vs memory and what changed.

### 2. Stability and saves
| Metric | Target | How measured |
|---|---|---|
| Crashes | 0 in a 4-hour bot soak and 100 save/load cycles | soak + crash counter |
| Save safety | old saves load, auto-backup before migrations, no data loss | migration tests on real old saves |

### 3. Controls, feel and VR comfort
| Metric | Target | How measured |
|---|---|---|
| Movement | sprint >= 1.5x walk in every direction; head-relative; ship decks correct | QuestSim input tests |
| Reach | blocks 6, melee about 3 | tests |
| Input conflicts | no button does two things at once (e.g. B inventory vs dismount) | auto-generated binding matrix per context, checked for overlaps |
| Comfort | snap/smooth turn, vignette option, recenter incl. reclined, seated mode, height calibration, pause on headset removal | checklist + tests |
| Response | actions register within one frame | input-latency test |

### 4. Visual quality and art direction
| Metric | Target | How measured |
|---|---|---|
| One coherent style | all blocks, items and mobs match style 3 STYLISED REALISM (Remington picked it Oct 9; docs/art/style-options/3-stylised-realism.png) | golden-shot review against the style sheet |
| Ground noise | grass/flowers calm, readable terrain | noise metric on golden shots + review |
| Models | mobs/animals have believable proportions, silhouettes and animation; no "cheap/fake" look | turntable renders reviewed with a written rubric |
| Sky | realistic sky with clouds, cheap on Quest | golden shots at dawn/noon/dusk/night/rain |
| Defects | no z-fighting, seams, flicker, T-poses, floating trees, light leaks | automated frame-diff flicker check + world-gen audit |

Golden shot list: spawn view, forest, village, cave with torch, ore close-up, horse riding, Capital city, base battle,
frigate, the Deep, Ash Vault citadel, inventory, crafting, options menu, dusk, night, rain.

### 5. Audio
| Metric | Target | How measured |
|---|---|---|
| Coverage | every block, item, mob, vehicle and UI action has a fitting sound | auto-generated coverage table (no gaps) |
| Context rules | surface-correct footsteps and hits (dry = dry; wet only in rain/water/mud); ambience follows place and time (no birds underground, at night, in the Deep or Ash Vault) | rule tests + rendered WAV analysis |
| Mix | music about -16 LUFS, SFX peaks <= -1 dBFS, no clipping, spatialised, ducking | loudness analysis |
| Music | real composed tracks per context, played sparingly | see Music below; licence verified before release |
Music source: Google Lyria 3 via OpenRouter (key in ~/.config/openrouter/api-key) for drafts. Sound effects:
ElevenLabs sound effects need a direct ElevenLabs key (not set up yet); otherwise careful synthesis. Every
generated asset is logged in assets/CREDITS with service, prompt and date; commercial licence status goes in
store-readiness.md (no free tool found allows commercial use of its output; Remington decides on paid plans).

### 6. Content, progression and balance
| Metric | Target | How measured |
|---|---|---|
| First hour | a new player always knows a next goal; no dead ends; light onboarding hints | bot playthrough + reviewer play log |
| Progression | wood -> stone -> iron -> steel -> titanium -> endgame -> Ash Vault final battle all reachable in sane time | bot milestone timings across 10 seeds |
| Balance | time-to-kill and damage tables within designed ranges; no unwinnable or trivial fights (hisser, Ashguard, frigate) | combat sims |

### 7. World, mobs and AI
| Metric | Target | How measured |
|---|---|---|
| Spawn density | within target per biome/depth/time (not empty, not swarms) | density histograms over 50 seeds |
| Behaviour | no stuck mobs, no friendly fire, factions behave, pathing works | stuck/idle detectors in soak |
| World gen | no structure overlaps, safe spawn, findable bases/citadels | world-gen audit over 50 seeds |

### 8. UI and UX
| Metric | Target | How measured |
|---|---|---|
| Legibility | all text readable in VR (minimum angular size), no truncation | screenshot overflow detector on every screen |
| Consistency | one visual style, controller-navigable everywhere, settings persist | UI screenshot review |
| Accessibility | subtitles for voice lines, colour-safe indicators, volume sliders per bus | checklist |

### 9. Store compliance
Meta VRC checklist (performance, comfort, pause on headset removal, boundary handling, permissions with clear
disclosure, e.g. the microphone for voice bug notes), store assets (icon, screenshots, trailer), privacy policy,
age rating, credits, every third-party/generated asset's licence, and no real extremist symbols (the Ashguard stays fictional).
Each item: status + evidence in store-readiness.md.

## Inputs from Remington (Oct 9) folded into the objectives above
Footsteps/hits sound wet like mud (audio context rules); birds heard in caves (ambience rules); wants real music
(audio: music); wants ElevenLabs-quality SFX (audio: needs a direct key); textures restyle after he picks a style
(visual); mobs look fake, replace the creeper (visual: models); realistic sky with clouds (visual: sky); grass and
flowers too noisy (visual: ground noise); frame rate and render distance (performance).
