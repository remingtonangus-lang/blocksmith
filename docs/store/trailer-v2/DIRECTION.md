# SUNDERFALL — Store Trailer v2: Director's Script & Visual Standards

**Runtime Target:** ~49.5 seconds (16 gameplay shots + 4.0s title card)  
**Format:** 1920×1080 @ 30 fps (rendered at 2560×1440 supersampled, downscaled Lanczos), AAC 48 kHz  
**Core Mandate:** Sell *VR presence, scale, and genre range* in the first 3 seconds. Every shot in the Nov 12 cut looked like a flat PC screensaver because the camera floated on smooth Catmull-Rom splines with zero hands, tools, weapons, or mount perspective. A Meta Quest 3 buyer scrolls past flat flythroughs in two seconds. We win them by putting them **inside the headset**—hands holding tools, reins, lanterns, and weapons—alternating with massive wide shots that prove the scale of the open world.

---

## Creative Pillars & Rules

1. **The 3-Second Hook (`hook_frigate_bow`):** No sleepy high-altitude drone pullbacks over brown roofs. Frame 1 puts the viewer at eye level in first-person on a ridge/terrace as a massive Meridian warship thunders directly overhead, bow-first, casting its shadow across a frontier town and tower. VR scale hits immediately.
2. **VR Presence (First-Person Rigging):** At least 7 of the 16 shots are framed at human eye height (1.6m–2.3m mounted) with **VR hands and held items visible in the lower foreground** (block/hammer while building, reins/horse neck while riding, lantern in the lush cave, rifle/pistol in Boreal corridor and outlaw fight). *See Engine Additions below for what `Cinema.swift` needs to render hands/mounts cleanly.*
3. **Strict Story & Lore Order:**
   - **Act I — Frontier Life & Creation (0:00–0:21):** Scale hook → Building → Farming → Player Horseback Riding → Frontier Train → Lush Caves. Shows warmth, daylight, color, and sandbox freedom so the game doesn't read as "just grey bases and war."
   - **Act II — Escalation on the Surface (0:21–0:35):** Boreal Station in the snow (infiltration) → Outlaw shootout → Commanding the sky frigate & firing the Tidebreaker main gun. (Strict rule: **No Ashguard on the surface**).
   - **Act III — The Deep & The Last War (0:35–0:49.5):** Descent into Hell (lava sea) → The Ash Vault battle (Ashguard troops & armor) → Sunset breath over the frontier → SUNDERFALL Title Card.
4. **Hard Bans (Do Not Show):**
   - **NO NPCs riding horses** (`ride` in the old cut showed two villagers standing stiffly upright on horses like surfboards, plus a black wireframe block-selection box at `00:05`!). Riding must be **first-person player riding** only.
   - **NO generated roads** (post-submission feature).
   - **NO crossfades between gameplay shots** (causes ghosted double-buildings; hard cuts only, except the final fade into the blurred sunset end-card).

---

## Cinema.swift Additions Needed for VR Presence

Right now `Cinema.swift` moves `g.player.pos` and sets `yaw`/`pitch`, rendering `WorldRenderer`, which leaves the screen completely bare of player hands, held items, or mount attachment—and in `ride` at `00:05` actually leaked the black block-target wireframe outline when the camera dipped near grass!

Before rendering the final v2 pass, add these 4 small hooks to `Cinema.swift` (`Shot` / `Ev`):
1. **Suppress Block Selection Wireframe in Cine Mode:** Force `wr.hideSelectionBox = true` (or set player gamemode/raycast off during `Cinema.shoot`) so a black wireframe cube *never* appears on terrain in low-angle shots (caught in `ride` at `00:05.000`).
2. **First-Person Held Item & Hand Pose (`"hold": "lantern"` / `"iron_pickaxe"` / `"spruce_planks"` / `"rifle"` on `Shot`):** Set `g.player.inventory` active slot to the named item and position the VR right/left hand transforms (`g.vrHands` / viewmodel pass in `WorldRenderer`) at natural waist-to-chest VR resting poses (`rightHandOffset = V3(0.24, -0.26, -0.38)` with subtle 1.2 Hz breathing/walk bob when moving) so Quest buyers immediately recognize VR hand presence.
3. **Player Horse Mount (`"playerMount": "horse"` on `Shot`):** Spawn a saddled `.horse` at `origin`, set `g.player.mount = horse` (or lock `eye = horse.pos + V3(0, horse.height + 0.55, 0)` with slight gallop vertical rhythm), steering `horse` toward a forward goal along `yaw`. The camera looks forward over the horse's animated head/ears—100% immersive VR riding, completely bypassing the missing NPC sitting animation.
4. **`fire` + Visible Muzzle Blast on `frigate_broadside`:** Ensure `playerMainGun` visually fires during the shot (not just cruising silently).

*(Fallback note in `trailer-shots.json`: Every shot below is written so its `cam` and `events` parse and render cleanly in **today's** `Cinema.swift` if you strip unrecognized keys, while comments/optional fields mark the exact hand/mount hooks once added.)*

---

## Music & Sound Design Map

- **0:00.0 – 0:21.3 (`main_title.m4a`):** Warm, adventurous frontier motif. Starts at full presence on frame 1 (0.2s quick fade-in, not sluggish).
- **0:21.3 – 0:49.5 (`ash_vault_battle.m4a`):** Hard-driving percussion kicks in right on the hard cut from the dark lush cave to the bright white snow of Boreal Station (`station_approach`).
- **Spot SFX Layer (`Resources/Sounds/real`):**
  - Wood/stone placement ticks rapid-fire during `fp_build` (`0:03.2 – 0:06.2`).
  - Hoofbeats / steam chug if available in `Resources/Sounds/real`, otherwise clean music carry.
  - Gunfire / sharp blast (`explodeLarge.wav` @ 0.7 gain) in `outlaw_fight`.
  - Heavy charge + twin layered `explodeLarge.wav` + `explodeLarge_1.wav` synced to the **instant** shell impact in `frigate_strike`.
  - Deep rumble blast on tank breakup in `ash_vault_war`.

---

## Beat-by-Beat Director's Shot List & Pass/Fail QC Checklists

| # | Time | Dur | Shot Name | Camera & Action | Caption | Pass / Fail Render QC Checklist |
|---|------|-----|-----------|-----------------|---------|---------------------------------|
| 1 | 0:00.0–0:03.2 | 3.2s | `hook_frigate_bow` | **THE HOOK.** Low eye-level perspective near the frontier village looking up-angle as a Meridian frigate cruises directly overhead bow-first toward the distant Capital spire. | `One massive world—built for VR` | - [ ] Frigate moves strictly bow-first at smooth 72 Hz step.<br>- [ ] Hull fills upper frame by 1.0s (instant hook).<br>- [ ] Zero sky seams in village roofs below. |
| 2 | 0:03.2–0:06.6 | 3.4s | `fp_build` | **First-person Eye Level (1.5x speed).** Standing right in front of a frontier cabin plot on green plains with ocean behind; walls, glass windows, and pitched dark-oak roof snap up rapidly in front of your hands. *(VR hand holds planks/hammer).* | `Build anything, block by block` | - [ ] Starts **after** bare grey slab stage (`ss: 2.2`) so walls/windows rise immediately.<br>- [ ] Footing sunk cleanly into slope—no dark slot underneath.<br>- [ ] No black selection wireframe on grass. |
| 3 | 0:06.6–0:09.4 | 2.8s | `fp_farm` | **First-person Walk-past (1.25x speed).** Low 1.7m walk alongside irrigated wheat and carrot rows bursting into golden maturity; farmer working at field edge, sunlit forest behind. | `Work the land` | - [ ] Wheat reaches full golden stage before cut out.<br>- [ ] Water trench clean, no Z-fighting.<br>- [ ] Farmer facing field, not clipping into trees. |
| 4 | 0:09.4–0:12.6 | 3.2s | `fp_ride` | **First-person Player Riding.** Mounted perspective (`y=2.25m` over galloping horse head/neck, or `playerMount: "horse"`) charging across open coastal plains toward a sunlit ridge. **Zero NPC riders.** | `Saddle up and ride out` | - [ ] **ZERO standing/T-posing NPC villagers on horses.**<br>- [ ] Horse head/mane cleanly visible at bottom center, moving forward.<br>- [ ] **ZERO black block-outline wireframe** on ground. |
| 5 | 0:12.6–0:15.8 | 3.2s | `train_pass` | **Trackside Eye-Level.** Tight 1.8m stance right beside the embankment as the green-and-red steam locomotive roars right past the lens. Framed away from defective birch roots. | `Ride the rails across the frontier` | - [ ] Train locomotive fills frame in <1.5s (no 3s empty waiting).<br>- [ ] **Check right edge:** No birch tree with raw cut-log texture on root flare.<br>- [ ] Rails sit flush on ballast. |
| 6 | 0:15.8–0:18.6 | 2.8s | `town_life` | **Eye-Level Village & Capital Reveal.** Brisk human-height walk past market crates and lanterns in the frontier village with the towering white landmark fortress rising behind. | *(none)* | - [ ] `QUEST_VOIDPROBE` shows 0 magenta sky pixels on savanna well or gables.<br>- [ ] Townsfolk walking naturally, none pushed abruptly by camera sphere. |
| 7 | 0:18.6–0:21.4 | 2.8s | `fp_cave_lush` | **First-person Cave Exploration.** Walking through a bioluminescent lush cave with hanging glow-vines, spore blossoms, and warm lantern light pools. *(VR hand holds lantern).* | `Explore the caves below` | - [ ] Warm lantern light illuminates foreground rock (not muddy dark).<br>- [ ] Camera doesn't clip ceiling vines.<br>- [ ] Smooth framerate, no unmeshed black void chunks at cave end. |
| 8 | 0:21.4–0:24.0 | 2.6s | `station_approach` | **[MUSIC DROP]** Crisp white snow contrast. Low-altitude tactical glide down toward Boreal Station's perimeter fence, radar dish, watchtower, and patrolling guards. | `Infiltrate a base in the snow` | - [ ] **NO oversized 42cm naval deck gun** on roof (light gun if landed, else cleared).<br>- [ ] **NO hovering/parked dropship** glitching over roof.<br>- [ ] Bright clean snow, dark grey smoke (not pitch black). |
| 9 | 0:24.0–0:26.2 | 2.2s | `station_breach` | **First-person Gate & Corridor Double-Beat** (`station_gate` 1.1s -> `station_corridor` 1.1s, or single tight corridor push). Pushing at 1.65m eye height down the hazard-striped bunker corridor toward armed guards. *(VR hand holds weapon).* | *(none)* | - [ ] Check deterministic fight seed: no ugly foreground snow-shard crater blocking gate.<br>- [ ] No striped texture off-by-one under snow ledge.<br>- [ ] Corridor ceiling lights crisp, guard doesn't moonwalk into wall. |
| 10 | 0:26.2–0:29.4 | 3.2s | `outlaw_fight` | **First-person Combat Stance.** Eye-level (`1.7m`) lateral strafe from cover as Marauder outlaws return fire and artillery/grenade blasts throw dirt and fire across the line. *(VR hand holds rifle).* | `Shoot it out with outlaws` | - [ ] **NO "eyed/holed" grey smoke sprite artifacts** (must use fixed particle sheet).<br>- [ ] Blasts do **not** leave floating black felled tree trunks/leaves.<br>- [ ] Action starts within 0.3s of cut. |
| 11 | 0:29.4–0:32.2 | 2.8s | `frigate_command` | **Dramatic Wing/Bridge Close Pass.** Camera paces just off the port bow of the Meridian warship high over the coast as its main battery pitches down and charges to fire. | `Command a warship in the sky` | - [ ] Frigate flies forward smoothly, zero judder.<br>- [ ] Main gun visibly pitches/charges (`fire` event active).<br>- [ ] Coastline and forest fully meshed (`rd: 18`, no chunk pop-in). |
| 12 | 0:32.2–0:35.0 | 2.8s | `frigate_strike` | **Tidebreaker Orbital Impact.** Closer, punchier angle overlooking the target ridge; the slug slams down, detonating a massive fireball and instant shockwave crater. | `and unleash its main gun` | - [ ] **NO jagged white/blue dashed tracer line flickering across frame.**<br>- [ ] **NO strobing/reshuffling explosion puffs** frame-to-frame.<br>- [ ] **Crater forms IMMEDIATELY on shell impact** (within 0.1–0.2s under the fireball, NOT popping in 1.5s late).<br>- [ ] **NO frozen grey debris blocks hanging in the sky** at `t+2s`. |
| 13 | 0:35.0–0:38.0 | 3.0s | `hell_descent` | **First-person Precipice Dive in Hell.** Swooping low over glowing magma rivers, basalt spires, and dark volcanic crags in the Deep. | `Descend into the Deep` | - [ ] Both Deep layers meshed (`deepLayerCut = false`), zero missing chunk holes.<br>- [ ] Lava emissive glow rich and vibrant; no pale unlit ground patches.<br>- [ ] Clean atmospheric fog horizon. |
| 14 | 0:38.0–0:42.2 | 4.2s | `ash_vault_war` | **Eye-Level Ash Vault Assault.** Pushing forward along the subterranean rail line toward the fortified red-lit Ash Vault gate as Ashguard troopers advance alongside an Ash Tank—which takes a direct hit and explodes at `t+2.4s`! | `and fight through the last war` | - [ ] Combines Vault scale + armored combat (replaces static marching clip).<br>- [ ] Ash Tank sits grounded on floor, then cleanly wrecks in fiery blast.<br>- [ ] Red Vault lights and flak towers read clearly through subterranean haze. |
| 15 | 0:42.2–0:45.5 | 3.3s | `sunset_finale` | **Golden Hour Pullback.** Warm dusk light sweeping across the frontier settlement and landmark tower as lanterns glow and sunset paints the clouds crimson-gold. | *(none)* | - [ ] Smooth `timeRate` sunset transition without shadow-map snapping.<br>- [ ] `peaceful: true`—zero zombies/skeletons spawning in town at dusk. |
| 16 | 0:45.5–0:49.5 | 4.0s | `TITLE CARD` | Blurred/darkened sunset plate: **S U N D E R F A L L** / horizontal rule / **EARLY ACCESS ON META QUEST** | `SUNDERFALL — Early Access on Meta Quest` | - [ ] Crisp typography, audio limiter holds peaks ≤ -1.0 dBFS, clean 3s music tail fade. |

---

## Visual Direction for Store Covers & Screenshots (All Store Visuals)

As visual director across the entire Meta Horizon Store page, here is what must change on Covers and Stills:

### 1. Cover Art (`covers/` — Hero 2560×1440, Square 1024×1024, Portrait 1440×2560, Mini 1280×720)
- **Critical Blocker Found Earlier:** Raw rendered screenshots were uploaded as cover candidates **with NO game title logo on them**. On the Meta Quest Store browse grid, a bare voxel screenshot with no logo looks like an unbranded asset test and kills click-through rate.
- **Cover Composition Spec:**
  - **Subject:** Low-angle golden-hour hero composition (`time: 0.41`): In the foreground right, an adventurer/player silhouette (or saddled horse on a grassy bluff overlooking a lantern-lit frontier cabin and village); in the upper-left sky, the **Meridian Frigate** banking through sunlit clouds with the white Capital/Tower on the horizon. This single frame communicates *Frontier + Building + Sky Warship* at a glance—unlike a flat midday side-profile of the ship.
  - **Typography Overlay (Mandatory on all 4 aspect ratios):** Render clean base plates at 5120×2880, then composite the **SUNDERFALL** wordmark (bold tracked serif matching the trailer title card, warm ivory `#FFFDF7` with subtle dark drop-shadow and chiseled warm-gold/ember bevel accent) inside Meta's Center Safe Zone (inner 70% width × 60% height so Square/Portrait crops and Meta's store badges never clip a letter). Keep `"EARLY ACCESS"` off the cover image itself (Meta Horizon Store Guidelines reject store-status/badge text baked into key art; Meta adds the Early Access pill automatically).

### 2. Store Screenshots (`screenshots/` — Pick the strongest 8, not 13 redundant angles)
Buyers swipe 5–8 screenshots max. Drop redundant village angles and ensure every screenshot represents one distinct gameplay pillar at 2560×1440 (downsampled from 5120×2880, zero HUD, zero sky cracks):
1. **Sky Frigate Over Frontier Village** (Scale & Vehicles)
2. **Cabin & Irrigated Homestead at Morning Light** (Building & Farming together in one rich frame, not an empty plain)
3. **Steam Train Crossing Forest Embankment** (Living World & Rails)
4. **Lush Lantern-Lit Cavern** (Underground Exploration)
5. **Boreal Station Snow Perimeter** (Tactical Infiltration — render *after* light-gun PR lands)
6. **Outlaw Firefight at Dusk** (Surface Combat — clean smoke particles)
7. **Lava Sea of Hell** (The Deep)
8. **Ash Vault Fortress & Armor** (Endgame War)