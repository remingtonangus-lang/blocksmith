Here is the complete visual direction, replacement shot specifications, `cine.py` cut table, required engine/game fixes, and cover/still notes.

---

### 1. `docs/store/trailer-v2/DIRECTION.md`

```markdown
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
```

---

### 2. Replacement Shot Specs & Cut Table

#### `docs/store/trailer-shots.json`
*(All fields decode directly in the existing `Cinema.swift` `JSONDecoder`—Swift's `Decodable` safely ignores extra JSON keys if not declared on `Shot`, so I have included `"_vr_todo"` notes right on the first-person shots so today's binary parses 100% cleanly while flagging the exact hand/mount pose for the `Cinema.swift` VR-presence upgrade.)*

```json
[
 {
  "name": "hook_frigate_bow",
  "anchor": {
   "near": "village",
   "from": [
    3000,
    0
   ],
   "frigate": [
    -45,
    95,
    155
   ]
  },
  "time": 0.36,
  "seconds": 4.5,
  "warm": 3,
  "peaceful": true,
  "rd": 18,
  "fov": 74,
  "cruise": 26,
  "follow": false,
  "cam": [
   {
    "t": 0,
    "pos": [
     12,
     -42,
     -55
    ],
    "look": [
     -10,
     -6,
     15
    ]
   },
   {
    "t": 4.5,
    "pos": [
     16,
     -41,
     -62
    ],
    "look": [
     18,
     -2,
     -65
    ]
   }
  ]
 },
 {
  "name": "fp_build",
  "_vr_todo": "hold: spruce_planks + hammer swing or VR right hand visible; hideSelectionBox: true",
  "anchor": {
   "find": "plains",
   "from": [
    400,
    400
   ]
  },
  "time": 0.3,
  "seconds": 7.5,
  "warm": 3,
  "peaceful": true,
  "fov": 76,
  "events": [
   {
    "t": 0.1,
    "do": "build",
    "at": [
     0,
     0,
     0
    ],
    "size": [
     9,
     5,
     8
    ],
    "dur": 6.2
   },
   {
    "t": 5.8,
    "do": "place",
    "block": "lantern",
    "at": [
     3,
     1,
     -1
    ],
    "n": 2,
    "spread": 3
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     -3.5,
     1.75,
     11.5
    ],
    "look": [
     4.5,
     2.6,
     3.5
    ],
    "ground": true
   },
   {
    "t": 4,
    "pos": [
     1.5,
     1.8,
     12.5
    ],
    "look": [
     4.5,
     3.4,
     4.0
    ],
    "ground": true
   },
   {
    "t": 7.5,
    "pos": [
     7.5,
     2.1,
     11.5
    ],
    "look": [
     4.5,
     3.8,
     4.0
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "fp_farm",
  "_vr_todo": "hold: iron_hoe or wheat in VR right hand; hideSelectionBox: true",
  "anchor": {
   "find": "plains",
   "from": [
    2000,
    2000
   ]
  },
  "time": 0.29,
  "seconds": 5.5,
  "warm": 3,
  "peaceful": true,
  "fov": 75,
  "events": [
   {
    "t": 0,
    "do": "farm",
    "at": [
     0,
     0,
     0
    ],
    "size": [
     11,
     9
    ],
    "block": "wheat",
    "dur": 4.2
   },
   {
    "t": 0,
    "do": "farm",
    "at": [
     0,
     0,
     10
    ],
    "size": [
     11,
     5
    ],
    "block": "carrots",
    "dur": 4.2
   },
   {
    "t": 0,
    "do": "spawn",
    "mob": "villager:farmer",
    "at": [
     12,
     0,
     6
    ],
    "n": 1,
    "yaw": 260
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     -3.2,
     1.72,
     -2.0
    ],
    "look": [
     6.5,
     1.1,
     6.5
    ],
    "ground": true
   },
   {
    "t": 5.5,
    "pos": [
     -2.5,
     1.75,
     7.5
    ],
    "look": [
     7.5,
     1.2,
     9.0
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "fp_ride",
  "_vr_todo": "CRITICAL ENGINE HOOK: mount g.player onto a saddled horse trotting along yaw 90 (playerMount: 'horse') with reins/hands in lower frame and NO NPC villager riders. Until playerMount is added, DO NOT spawn 'rider' villagers (they stand upright); this camera flies at mounted saddle height (2.25m) across coastal plains.",
  "anchor": {
   "find": "plains",
   "from": [
    400,
    400
   ]
  },
  "time": 0.32,
  "seconds": 4.5,
  "warm": 3,
  "peaceful": true,
  "rd": 16,
  "fov": 78,
  "events": [],
  "cam": [
   {
    "t": 0,
    "pos": [
     -12,
     2.25,
     6
    ],
    "look": [
     25,
     2.1,
     2
    ],
    "ground": true
   },
   {
    "t": 4.5,
    "pos": [
     18,
     2.25,
     3
    ],
    "look": [
     55,
     2.2,
     -1
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "train_pass",
  "anchor": {
   "rail": 50,
   "from": [
    -1500,
    1500
   ],
   "train": "passenger"
  },
  "time": 0.44,
  "seconds": 6,
  "warm": 4,
  "fov": 74,
  "cam": [
   {
    "t": 0,
    "pos": [
     -3.8,
     1.85,
     -3.5
    ],
    "look": [
     -24,
     2.3,
     0.5
    ],
    "ground": true
   },
   {
    "t": 6,
    "pos": [
     -3.4,
     1.85,
     -4.2
    ],
    "look": [
     -12,
     2.3,
     0.8
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "town_life",
  "anchor": {
   "near": "village",
   "from": [
    3000,
    0
   ]
  },
  "time": 0.38,
  "seconds": 5,
  "warm": 10,
  "peaceful": true,
  "rd": 18,
  "fov": 72,
  "cam": [
   {
    "t": 0,
    "pos": [
     -27,
     1.75,
     -5
    ],
    "look": [
     8,
     3.2,
     -8
    ],
    "ground": true
   },
   {
    "t": 5,
    "pos": [
     -16,
     1.8,
     -5.5
    ],
    "look": [
     24,
     4.0,
     -9
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "fp_cave_lush",
  "_vr_todo": "hold: lantern in VR right hand casting warm foreground light",
  "anchor": {
   "find": "plains",
   "from": [
    3000,
    1500
   ],
   "cave": true
  },
  "time": 0.3,
  "seconds": 5,
  "warm": 2,
  "peaceful": true,
  "rd": 8,
  "fov": 78,
  "events": [
   {
    "t": 0,
    "do": "place",
    "block": "lantern",
    "at": [
     5,
     0,
     0
    ],
    "n": 11,
    "spread": 7.5
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     -4.5,
     1.75,
     1.8
    ],
    "look": [
     10,
     1.3,
     -1
    ]
   },
   {
    "t": 5,
    "pos": [
     2.0,
     1.7,
     0.3
    ],
    "look": [
     14,
     1.5,
     -2.5
    ]
   }
  ]
 },
 {
  "name": "station_approach",
  "_vr_todo": "Remove skip:['ships'] and clear:deck_gun once Boreal light-gun PR lands on quest-port",
  "anchor": {
   "near": "boreal_station",
   "from": [
    1500,
    -1500
   ],
   "station": "boreal_station"
  },
  "time": 0.28,
  "seconds": 5,
  "warm": 6,
  "skip": [
   "ships"
  ],
  "events": [
   {
    "t": 0,
    "do": "clear",
    "mob": "deck_gun",
    "at": [
     0,
     0,
     0
    ],
    "spread": 120
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     1,
     1,
     12
    ],
    "look": [
     4,
     -25,
     -52
    ]
   },
   {
    "t": 5,
    "pos": [
     2,
     -10,
     -8
    ],
    "look": [
     4,
     -24,
     -52
    ]
   }
  ]
 },
 {
  "name": "station_breach",
  "_vr_todo": "hold: pistol/rifle in VR right hand; cuts hard mid-shot from gate approach into bunker corridor using Key.cut = true!",
  "anchor": {
   "near": "boreal_station",
   "from": [
    1500,
    -1500
   ],
   "station": "boreal_corridor"
  },
  "time": 0.3,
  "seconds": 4,
  "warm": 6,
  "fov": 76,
  "events": [
   {
    "t": 0,
    "do": "clear",
    "mob": "deck_gun",
    "at": [
     0,
     0,
     0
    ],
    "spread": 120
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     0,
     1.65,
     3.5
    ],
    "look": [
     0,
     1.62,
     -20
    ]
   },
   {
    "t": 4,
    "pos": [
     0,
     1.65,
     -4.5
    ],
    "look": [
     0,
     1.62,
     -22
    ]
   }
  ]
 },
 {
  "name": "outlaw_fight",
  "_vr_todo": "hold: rifle in VR hands; requires fixed non-eyed smoke particles",
  "anchor": {
   "at": [
    3090,
    0,
    65
   ]
  },
  "time": 0.42,
  "seconds": 5,
  "warm": 2,
  "rain": false,
  "survival": false,
  "rd": 18,
  "fov": 75,
  "events": [
   {
    "t": 0,
    "do": "spawn",
    "mob": "soldier_trooper@marauder^90",
    "at": [
     -23,
     0,
     -2
    ],
    "n": 12,
    "spread": 8
   },
   {
    "t": 0,
    "do": "spawn",
    "mob": "soldier_marksman@marauder^90",
    "at": [
     -29,
     0,
     7
    ],
    "n": 6,
    "spread": 6
   },
   {
    "t": 0.35,
    "do": "explode",
    "at": [
     -18,
     0,
     8
    ],
    "power": 4.5,
    "fire": true
   },
   {
    "t": 1.4,
    "do": "explode",
    "at": [
     -24,
     0,
     -5
    ],
    "power": 5,
    "fire": true
   },
   {
    "t": 2.6,
    "do": "explode",
    "at": [
     -27,
     0,
     9
    ],
    "power": 5.5,
    "fire": true
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     -8.5,
     1.7,
     6.0
    ],
    "look": [
     -25,
     1.55,
     0
    ],
    "ground": true
   },
   {
    "t": 5,
    "pos": [
     -10.5,
     1.72,
     1.5
    ],
    "look": [
     -27,
     1.55,
     -1.5
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "frigate_command",
  "_vr_todo": "Note: 'fire' event marks fr.captured = true and charges mainGun; verify cruise pose doesn't cancel gun charge VFX",
  "anchor": {
   "near": "village",
   "from": [
    3000,
    0
   ],
   "frigate": [
    -200,
    160,
    0
   ]
  },
  "time": 0.34,
  "seconds": 4.5,
  "warm": 2,
  "rd": 18,
  "fov": 72,
  "cruise": 20,
  "follow": true,
  "events": [
   {
    "t": 0.4,
    "do": "fire",
    "pitch": -12
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     -38,
     -5,
     -48
    ],
    "look": [
     0,
     -1,
     -12
    ]
   },
   {
    "t": 4.5,
    "pos": [
     -32,
     -3,
     -28
    ],
    "look": [
     0,
     -2,
     -4
    ]
   }
  ]
 },
 {
  "name": "frigate_strike",
  "_vr_todo": "DEPENDS ON GAME FIXES: instant crater mesh update, no jagged white/blue tracer line, no strobing puffs, no floating grey debris blocks",
  "anchor": {
   "near": "village",
   "from": [
    3000,
    0
   ],
   "frigate": [
    -200,
    160,
    45
   ]
  },
  "time": 0.35,
  "seconds": 4.5,
  "warm": 2,
  "rd": 18,
  "fov": 70,
  "events": [
   {
    "t": 0.55,
    "do": "impact",
    "at": [
     216,
     0,
     -190
    ],
    "ground": true
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     252,
     20,
     -154
    ],
    "look": [
     215,
     1,
     -190
    ],
    "ground": true
   },
   {
    "t": 4.5,
    "pos": [
     244,
     17,
     -160
    ],
    "look": [
     215,
     -2,
     -190
    ],
    "ground": true
   }
  ]
 },
 {
  "name": "hell_descent",
  "dim": "deep",
  "anchor": {
   "at": [
    60,
    0,
    60
   ],
   "deep": "hell"
  },
  "seconds": 4.5,
  "warm": 2,
  "rd": 12,
  "fov": 78,
  "cam": [
   {
    "t": 0,
    "pos": [
     0,
     36,
     4
    ],
    "look": [
     -34,
     18,
     -60
    ]
   },
   {
    "t": 4.5,
    "pos": [
     -8,
     24,
     -18
    ],
    "look": [
     -32,
     15,
     -78
    ]
   }
  ]
 },
 {
  "name": "ash_vault_war",
  "dim": "deep",
  "anchor": {
   "at": [
    -80,
    0,
    0
   ],
   "deep": "vault"
  },
  "seconds": 5.5,
  "warm": 2,
  "rd": 10,
  "fov": 72,
  "survival": false,
  "events": [
   {
    "t": 0,
    "do": "spawn",
    "mob": "soldier_trooper@ash^0",
    "at": [
     2,
     0,
     -8
    ],
    "n": 10,
    "spread": 7
   },
   {
    "t": 0,
    "do": "vehicle",
    "mob": "ash_tank",
    "at": [
     5,
     0,
     -15
    ],
    "yaw": 15
   },
   {
    "t": 2.4,
    "do": "wreck",
    "at": [
     5,
     0,
     -15
    ],
    "spread": 7,
    "power": 5
   }
  ],
  "cam": [
   {
    "t": 0,
    "pos": [
     -7,
     2.1,
     -13
    ],
    "look": [
     12,
     2.4,
     -9
    ]
   },
   {
    "t": 5.5,
    "pos": [
     -2,
     2.0,
     -7
    ],
    "look": [
     13,
     2.5,
     -13
    ]
   }
  ]
 },
 {
  "name": "sunset_finale",
  "anchor": {
   "near": "village",
   "from": [
    3000,
    0
   ]
  },
  "time": 0.435,
  "timeRate": 0.009,
  "seconds": 5.5,
  "warm": 6,
  "peaceful": true,
  "rd": 18,
  "cam": [
   {
    "t": 0,
    "pos": [
     40,
     12,
     40
    ],
    "look": [
     0,
     5,
     0
    ],
    "ground": true
   },
   {
    "t": 5.5,
    "pos": [
     64,
     26,
     64
    ],
    "look": [
     -8,
     2,
     -8
    ],
    "ground": true
   }
  ]
 }
]
```

#### Replacement `CUT` list (and music-switch update) for `tools/cine.py`
*(Note for `tools/cine.py`: also update `fin = os.path.join(d, "sunset_finale.mp4")` on line 76 and `switch = starts[names.index("station_approach")] if "station_approach" in names else total / 2` on line 98 so the endcard plate and music drop lock onto the new shot names.)*

```python
CUT = [
    # ACT I: THE HOOK & FRONTIER SANDBOX (main_title.m4a)
    ("hook_frigate_bow", 3.2, "One massive world — built for VR", [], {"xf": 0, "ss": 0.2}),
    ("fp_build",         3.4, "Build anything, block by block", [], {"xf": 0, "ss": 2.0, "speed": 1.5}),
    ("fp_farm",          2.8, "Work the land", [], {"xf": 0, "ss": 1.6, "speed": 1.25}),
    ("fp_ride",          3.2, "Saddle up and ride out", [], {"xf": 0, "ss": 0.4}),
    ("train_pass",       3.2, "Ride the rails across the frontier", [], {"xf": 0, "ss": 2.4}),
    ("town_life",        2.8, None, [], {"xf": 0, "ss": 0.5}),
    ("fp_cave_lush",     2.8, "Explore the caves below", [], {"xf": 0, "ss": 1.2}),

    # ACT II: SURFACE ESCALATION & SKY WARSHIP (ash_vault_battle.m4a drops at station_approach)
    ("station_approach", 2.6, "Infiltrate a base in the snow", [], {"xf": 0, "ss": 0.8}),
    ("station_breach",   2.2, None, [], {"xf": 0, "ss": 0.4}),
    ("outlaw_fight",     3.2, "Shoot it out with outlaws", [(0.25, "explodeLarge.wav", 0.9), (1.3, "explodeLarge_1.wav", 0.85), (2.5, "explodeLarge.wav", 0.95)], {"xf": 0, "ss": 0.1}),
    ("frigate_command",  2.8, "Command a warship in the sky", [], {"xf": 0, "ss": 0.4}),
    ("frigate_strike",   2.8, "and unleash its main gun", [(0.45, "explodeLarge.wav", 1.0), (0.50, "explodeLarge_1.wav", 1.0)], {"xf": 0, "ss": 0.1}),

    # ACT III: THE DEEP & THE LAST WAR
    ("hell_descent",     3.0, "Descend into the Deep", [], {"xf": 0, "ss": 0.3, "speed": 1.25}),
    ("ash_vault_war",    4.2, "and fight through the last war", [(2.1, "explodeLarge.wav", 1.0), (2.18, "explodeLarge_1.wav", 0.9)], {"xf": 0, "ss": 0.3}),
    ("sunset_finale",    3.3, None, [], {"xf": 0, "ss": 0.8}),
]
TITLE = 4.0       # ~49.5 s total runtime with end card
```

#### Engine Uncertainties Explicitly Flagged
1. **`frigate_command` (`cruise` + `fire` interaction):** In `Cinema.swift`, setting `"do": "fire"` sets `fr.captured = true` and calls `w.ships.playerMainGun(fr, game: g)` while `fr.vel = .zero`, and then later in the frame loop `if let cr = s.cruise` overwrites `fr.pos` and `fr.rot = cruiseRot!`. **Verify during render:** If locking `fr.rot = cruiseRot!` overrides `w.ships.pointHull(fr, pitch:)` or cancels the main-gun charge glow, let `cruiseRot` capture `fr.rot` *after* the `fire` event pitches the hull (or drop `"pitch": -12` and keep the level charge VFX).
2. **`fp_ride` (Player Mount):** Today's `Cinema.swift` only has `"do": "rider"` (which spawns an NPC villager standing upright on a horse) and has no `"playerMount"` key yet. Until a ~15-line `playerMount` hook is added to `Cinema.swift` to lock `g.player` onto a saddled `.horse` looking over its neck/ears, `fp_ride` flies at saddle height without a horse head in frame. **Do not ship `fp_ride` without adding the `playerMount` hook**—Remington specifically asked for the *player* riding a horse.

---

### 3. Game-Side & Harness Fixes the Shots Depend On

Route these directly to the game/engine lanes so we fix them for real instead of trimming around bugs:

1. **Main-Gun Strike — Delayed Crater Formation (`ShipManager.mainGunImpact` / Chunk Remeshing) [CRITICAL - Remington flagged]:**
   - *Symptom:* Looking at `frigate_strike` (`00:46` -> `00:48`), the shell detonates at `00:46`, huge orange spheres expand over intact green grass at `00:47`, and the crater hole only snaps into the terrain mesh 1.5–2.0 seconds later (`00:48`) as the smoke clears.
   - *Root Cause & Fix:* Either `mainGunImpact` schedules block carving on a delayed fuse after the visual burst, OR asynchronous smooth-terrain chunk remeshing lags behind by tens of frames under headless lavapipe ticks. `mainGunImpact` must carve the crater blocks **at the exact tick of shell contact** (while the opaque core fireball hides the swap), and in `Cinema` / synchronous impact paths force an immediate synchronous chunk remesh of dirty chunks within blast radius before drawing that frame.
2. **Main-Gun Strike — Jagged White/Blue Tracer Line, Strobing Puffs & Floating Sky Debris (`frigate_strike`):**
   - *Symptom:* Visible in `frigate_strike` `00:47–00:49`: (a) a jagged white/blue line slices down the lower-right frame (`00:47–00:49`) and flickers; (b) explosion smoke spheres reshuffle depth/sort order every frame causing harsh luminance strobing; (c) dark grey square block fragments hang frozen mid-air in the upper sky at `00:48`.
   - *Fix:* Replace/fade the main-gun tracer ribbon within 3–4 ticks of impact (and fix its billboard/segment winding so it doesn't kink into a jagged white seam); sort explosion billboards deterministically by `(cameraDistance, particleID)` instead of unstable frame list order; apply full gravity to blasted debris entities/particles so nothing hangs weightless in the sky.
3. **Black Block-Selection Wireframe Leaking into Cine Shots (`WorldRenderer` / `Cinema.swift`):**
   - *Symptom:* Look closely at `CLIP ride 00:05.000` (bottom center): a stark black 1×1×1 block-selection wireframe cube appears on the grass because `g.player` came within survival/creative reach distance of the ground! Since v2 moves to eye-level first-person cameras (`1.65m–1.8m`), this wireframe will ruin *every* ground shot unless suppressed.
   - *Fix:* Suppress the block target outline whenever headless `Cinema` is running (or when HUD is hidden).
4. **VR Hands + Held Items + Player Horse Mount in `Cinema.swift`:**
   - Add `playerMount` (attaching `g.player` to a saddled `.horse` trotting forward so the horse's head/mane and player reins appear naturally in first-person) and `hold` (rendering the Quest VR hand models holding a lantern, planks/tool, or rifle in the lower foreground of first-person shots).
5. **Merge In-Flight Playtest Fixes to `claude/quest-port` Before Final Render:**
   - **"Eyed/Holed" Smoke Puffs (`war_advance` `00:01–00:04`):** Very prominent skull-like holes in the grey smoke sprites in the attached frames—must merge the particle-sheet fix PR before rendering `outlaw_fight` and `ash_vault_war`.
   - **Boreal Station Light Roof Gun & Parked Dropship:** Merge the Boreal roof gun replacement PR so we can drop `skip: ["ships"]` and `clear: "deck_gun"` from `station_approach` / `station_breach`.
   - **Birch Root-Flare Cut-Log Texture (`train` `00:00–00:05`, right foreground):** Visible right at the bottom of the birch trunk on the right side of `train`—merge the stump/flare UV fix before rendering `train_pass`.

---

### 4. Summary of Limitations & Next Actions for Opus / Cloud Render Thread

- **What I could not do directly in this turn:** Because this switched to a single-turn response without shell execution, I could not run `ffmpeg` locally to output the optional rough animatic MP4 or push the git commit directly.
- **Exact handoff steps for Opus & Cloud Render Thread:**
  1. Write Section 1 to `docs/store/trailer-v2/DIRECTION.md`, Section 2's JSON to `docs/store/trailer-shots.json`, and update `CUT` + `sunset_finale.mp4` + `station_approach` switch in `tools/cine.py` on branch `carbon/trailer-new`.
  2. Add the block-outline suppression + `playerMount` + VR hand `hold` hooks to `quest/src/headless/Cinema.swift`, and pull in the strike-crater/tracer/smoke fixes from the playtest lane.
  3. Render all 15 gameplay shots in the cloud at `2560x1440` (`QUEST_SKIP=landmarks`), run `QUEST_VOIDPROBE=1` crack checks on `hook_frigate_bow` and `town_life`, cut both `--captions` and clean versions, and send the contact sheets/frames back to me for strict Pass/Fail QC against the checklists in `DIRECTION.md`.