# Frontier — Quality Bar

The target is the open-world Western genre's top tier (the 2018 reference game everyone means). This file turns
"that level" into things a machine or a blind critic can check. Every system below has:

- **Bar**: what top-tier means, in measurable or checkable terms.
- **Checks**: how we verify it (automated oracle `[auto]`, numbers from `--benchmark`/bots `[num]`, or blind critic
  rubric on screenshots/clips/logs `[critic]`).
- **Score**: the latest blind-critic score, 0–10 (10 = indistinguishable from the reference tier on that axis).

Scoring rules for critics: grade only from the evidence pack (screenshots, clips, bot logs, numbers). Never read
builder notes. 10 = reference tier, 7 = a strong AA open-world game, 5 = competent indie, 3 = prototype,
1 = placeholder. Gap = weight × (10 − score); the work queue in `docs/status/frontier.md` is sorted by gap.

| # | System | Weight | Score |
|---|--------|--------|-------|
| 1 | Terrain and vegetation | 3 | – |
| 2 | Lighting and atmosphere | 3 | – |
| 3 | Characters and faces | 3 | – |
| 4 | Animation and locomotion | 3 | – |
| 5 | Horses | 3 | – |
| 6 | AI and towns | 3 | – |
| 7 | Wildlife | 2 | – |
| 8 | Combat and gunplay | 3 | – |
| 9 | Audio | 2 | – |
| 10 | Writing and missions | 3 | – |
| 11 | UI | 2 | – |
| 12 | Performance and stability | 3 | – |
| 13 | VR (Quest 3) | 2 | – |
| 14 | Open-world systems (honour, law, economy, camp, encounters) | 3 | – |

---

## 1. Terrain and vegetation
**Bar**
- World ≥ 60 km² of continuous, streamed land with ≥ 5 distinct biomes (high desert, red-rock canyon, grassland
  plains, river valley/wetland, pine mountains with snow line) and believable transitions (no hard seams).
- Landforms read as geology: erosion channels, alluvial fans, cliffs with strata, river valleys that drain downhill
  to a sea/lake. Rivers flow continuously downhill (`[auto]` monotone river profile check).
- Ground materials: ≥ 8 PBR materials blended by slope/height/moisture/roads with height-based blending, no visible
  tiling at 5–200 m (macro variation + detail normal), triplanar on cliffs (no stretching on slopes > 45°).
- Vegetation: dense grass/shrub coverage near the camera (≥ 50k visible grass blades/clumps on High), ≥ 8 tree/shrub
  species with distinct silhouettes, wind animation layered (trunk sway + branch + leaf flutter), interacts with the
  player/horse (bends), LOD/impostors with no popping visible within 150 m.
- Roads and trails worn into terrain (ruts, compacted dirt), connecting every settlement.
- Draw distance ≥ 4 km on High with distant mountains silhouetted through aerial perspective.
**Checks**
- `[auto]` worldgen oracle: no NaNs, slopes sane, rivers monotone, every settlement reachable by road, no spawn in water.
- `[auto]` tour shots: no holes/sky below terrain, no magenta/missing textures, no fully black frames.
- `[critic]` vista, mid-ground and foot-level shots of each biome at 3 times of day.

## 2. Lighting and atmosphere
**Bar**
- Physically-based sun/moon/sky with continuous 24 h cycle (default 48 real minutes per day), correct sun path,
  golden hour, blue hour, starfield and moon phases.
- Volumetric fog / aerial perspective with height falloff; god rays through trees and doorways; morning valley mist.
- Weather: clear, overcast, rain, thunderstorm (lightning lights the scene), fog, dust storm, snow in the mountains;
  transitions over minutes; wet surfaces darken and gain specular; puddles; clouds that move and cast shadows.
- Global illumination: bounce light in interiors (SDFGI/VoxelGI on High, baked probes/fallback lower), SSAO,
  screen-space reflections, contact shadows; no light leaks in interiors.
- Exposure adapts when walking from a bright street into a dark saloon (eye adaptation 1–3 s).
- Lamps, lanterns, campfires flicker and cast shadows at night.
**Checks**
- `[auto]` luminance histogram per time-of-day shot: no clipped-black / blown-white frames beyond 2 % of pixels
  outside night sky; night is dark but readable (mean luminance in band).
- `[critic]` same vantage at dawn/noon/dusk/night/rain/fog.

## 3. Characters and faces
**Bar**
- Realistic human proportions; ≥ 30 visually distinct NPC appearances in a town (body, face shape, skin tone, age,
  hair, facial hair, clothing combos) — no two adjacent NPCs identical.
- Period-correct 1899 clothing (hats, vests, dusters, dresses, work clothes) with PBR cloth, wear and dirt.
- Faces: skin shading with subsurface, eyes with wet highlights, blinking, gaze tracking (look at the player),
  lip-sync on all voiced lines, ≥ 6 expressions.
- Player customisation: clothing/hat swap at a store; hair/beard growth.
**Checks**
- `[auto]` distinctness: in a town crowd shot, appearance hash collisions among visible NPCs < 5 %.
- `[critic]` portrait close-ups in dialogue, crowd shots, period accuracy.

## 4. Animation and locomotion
**Bar**
- Motion-captured or mocap-quality base locomotion: idle variations, walk/jog/run/sprint with starts, stops, turns
  (plant-and-turn), slope adaptation; foot IK on uneven ground (foot sliding < 3 cm per step `[num]`).
- Weight and momentum: speed changes take 0.2–0.6 s, no instant turns at speed.
- Context animations: sit, lean, smoke, drink, work tasks, open doors, mount/dismount (both sides), climb ladders,
  vault, swim, crouch, carry.
- Combat animations: draw/holster per weapon, aim offsets, recoil, reload, hit reactions by body zone, ragdoll blend
  on death (active ragdoll / partial physics), stumbling.
- Procedural layers: head/eye look-at, breathing, cloth/hair secondary motion.
**Checks**
- `[num]` foot-slide metric, turn-rate limits, animation pop count (pose delta spikes) from bots.
- `[critic]` clips of locomotion over rough terrain, mounting, combat.

## 5. Horses
**Bar**
- Anatomically convincing horse (proportions, musculature, mane/tail motion, ≥ 6 coat colours/patterns, breeds with
  different stats).
- Gaits with correct footfall patterns: walk (4-beat), trot (2-beat diagonal), canter (3-beat), gallop (4-beat);
  smooth transitions, turning lean, slope handling, stops with weight, rear/buck when spooked.
- Bonding (levels unlock moves), care (brushing, feeding, dirt/mud accumulation), stamina/health cores, calling with
  a whistle, horse fear of predators/gunfire, saddle bags inventory, hitching posts.
- Riding feel: pace control by tapping, auto-follow road, collision with obstacles with stumble/fall, jumping.
**Checks**
- `[auto]` gait oracle: foot contact pattern per gait matches the reference phase table within tolerance.
- `[num]` bots ride town-to-town: arrival rate 100 %, stuck events 0, falls only on cliffs.
- `[critic]` riding clips at each gait, close-ups.

## 6. AI and towns
**Bar**
- Every named settlement has ≥ 25 NPCs with daily schedules (home, work, eat, socialise, sleep) visible as a
  changing town over the day; shops open/close; lamps lit at dusk.
- NPCs react to the player: greet/antagonise, notice weapons drawn, flee/cower/fight, report crimes to law,
  remember recent interactions; conversations among NPCs (ambient dialogue).
- Pathfinding on navmesh: no walking through walls/props, no stuck NPCs, doors used, crowds avoid each other.
- Interiors: enterable saloon, general store, gunsmith, sheriff's office, hotel, bank, doctor, barber, stable,
  homes; furniture used by NPCs.
**Checks**
- `[auto]` behaviour sim: stuck (< 0.1 m in 10 s while having a goal) < 1 % of NPC-minutes, schedule completion
  > 95 %, interpenetration events 0, falling events 0.
- `[critic]` town time-lapse screenshots, reaction clips.

## 7. Wildlife
**Bar**
- ≥ 15 species across biomes (deer, elk, pronghorn, bison, wolf, coyote, cougar, bear, rabbit, fox, raccoon,
  turkey, eagle/hawk, crow, fish species), ecology: herds, predators hunt prey, flee from player/horse by scent and
  noise, day/night activity patterns.
- Hunting: tracking (prints, blood), pelt quality (perfect/good/poor based on weapon and shot), skinning animation,
  carcass carry on horse, selling to butcher/trapper, crafting.
- Fishing: cast, lure choice, fight with line tension.
**Checks**
- `[auto]` ecology sim counts (population stable over 2 in-game days, predation events occur).
- `[critic]` wildlife shots and hunting clip.

## 8. Combat and gunplay
**Bar**
- ≥ 10 period firearms (revolvers, repeater rifles, shotgun, bolt rifle, varmint rifle) with distinct handling,
  recoil, sound, reload, ammo types; weapon wear/cleaning.
- Gunfights: cover system, blind fire, lock-on soft aim + free aim, hit reactions by location, disarms, dismount
  shots, enemy flanking/suppression/retreat, ≥ 3 enemy archetypes.
- **Nerve** (slow-time ability): time dilates, mark multiple targets, auto-fire sequence; meter with cores;
  upgrades with level.
- Melee: fistfights with blocks/grapples, knives, lasso/hogtie.
- Lethality and readability: headshots kill, damage falloff, blood/impact decals, dust kicks on miss.
**Checks**
- `[auto]` combat bot: enemies engage, take cover, flank; no AI firing through walls; time-to-kill in band.
- `[critic]` gunfight clips including Nerve.

## 9. Audio
**Bar**
- Layered ambience per biome and time (wind, insects, birds, frogs at night, distant coyotes), weather audio.
- Gunshots with distance tails/echo, slapback off cliffs/buildings, interior/exterior reverb zones.
- Horse: hooves per surface and gait, breathing, vocalisations; footsteps per surface.
- Fully voiced main dialogue with distinct voices per character; ambient NPC barks.
- Original dynamic score: exploration, tension, combat, mission themes, adapting to state.
**Checks**
- `[auto]` no clipping (peak < −0.3 dBFS) in rendered sounds; every dialogue line has audio; loudness targets.
- `[critic]` audio clips per scenario.

## 10. Writing and missions
**Bar**
- Original story with a central arc (≥ 6 chapters planned), memorable cast (≥ 10 major characters with arcs).
- Cinematic missions: scripted sequences with camera direction, dialogue during rides, set pieces (train robbery,
  bank job, cattle drive, shootout in town), checkpoints, gold-medal objectives.
- Side content: strangers' stories, bounties, random encounters (≥ 20 types), letters/newspaper, journal.
- Dialogue quality: period voice, subtext, character consistency; no exposition dumps.
**Checks**
- `[auto]` mission bots finish every mission start-to-end; no softlocks.
- `[critic]` read scripts; grade mission clips.

## 11. UI
**Bar**
- Minimal diegetic-leaning HUD (radar with roads, cores for health/stamina/Nerve), weapon wheel, item wheel,
  satchel inventory, map with paper-map styling and waypoint routing, journal, catalogue shops.
- Original typographic identity (1899 print style), controller/keyboard/VR parity, all text legible at 1080p and
  in VR.
- Menus: settings with graphics presets, keybinding, subtitles, accessibility (aim assist, colour-blind modes).
**Checks**
- `[auto]` UI dead-end oracle: every menu reachable and exitable with controller only.
- `[critic]` screenshots of HUD, map, menus.

## 12. Performance and stability
**Bar** (8 GB Apple M1 MacBook, native resolution)
- High preset: average ≥ 60 fps, 1 % low ≥ 50 fps, p99 frame time ≤ 22 ms in the benchmark route (town, riding,
  gunfight, forest); memory ≤ 4.5 GB resident; no hitch > 100 ms after load.
- Load to gameplay ≤ 30 s; streaming without hitches while galloping.
- 0 crashes in CI bot hours; 0 script errors in logs.
**Checks**
- `[num]` `--benchmark` writes fps/frame-time percentiles + memory to `~/Library/Logs/Frontier/benchmark.json`.
- `[auto]` bots: crash/stuck/fall/frame-spike oracles; error-log scan.

## 13. VR (Quest 3)
**Bar**
- Same world and missions; 72/90 Hz stable on Quest 3 with scaled assets (Mobile renderer, foveation).
- Comfort: snap/smooth turn, vignette on locomotion and riding, seated/standing modes, height calibration.
- Physical interactions: draw revolver from holster, fan the hammer, reload by hand, reins, lasso throw.
**Checks**
- `[auto]` APK builds; headless XR smoke test.
- `[num]` frame time from on-device benchmark when available.

## 14. Open-world systems
**Bar**
- Honour/standing (−/+) affecting dialogue, prices, endings; wanted system with witnesses, bounty per state,
  lawmen response, bounty hunters; robberies of stores/trains/stagecoaches; bounties board missions.
- Economy: money, shops (catalogue), selling pelts/loot, fences.
- Camp: companions with routines, chores, contributions, camp upgrades, campfire songs/stories.
- Random encounters seeded across the map; points of interest (cabins, caves, ruins) with stories.
- Save/load anywhere outside combat; autosave.
**Checks**
- `[auto]` systems bot: commit crime → witnessed → wanted → pay bounty; buy/sell round trip; save/load equality.
- `[critic]` systems coherence review from logs and screenshots.
