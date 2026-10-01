# Status

Goal (from Remington, 2026-09-30): make Blocksmith play like the reference game as closely as practical —
every block, sparkstone, Emberdeep, End, terrain/caves/structures/villages with the same rarities, raids, the
Blight, and a completable game. Assets stay original/procedural (no copied textures, sounds or decompiled
code); mechanics, names and numbers follow the reference game.

## Playtest branch (claude/blocksmith-playtest, PR #9; integration + core session)
Every PR branch (#1-#8 and new ones) plus the integration branch merged with real merges and re-merged as they move;
PR #9's description keeps the player-facing what's-new list, the tested commit and known issues.
- CI order: build, smoke test (`./smoke.sh`: 60 s of real play through Game.tick and the full renderFrame path at
  render distances 8, 16 and 24, lldb backtrace on failure), benchmarks (a crashed scene is rerun under lldb ->
  benchdebug.log), profile, scripted playthrough, then snap.sh (every shot and harness test; a failing line no longer
  stops the rest, the step fails at the end with the failing lines listed).
- Integration fixes that live only here so far: one subtitles system (HudExtras + Settings.subtitles, audio captions as
  fallback); Options > Audio holds the per-category sliders; Resolution caps the dynamic resolution; World Scale
  (Fancy) is its own option and key (fancyWorldScale); ShipRenderer has an HDR pipeline set for Fancy; a held gun fires
  before ship interaction unless piloting; Reload Gun is a rebindable key (R, shared with Swap Off Hand: with a gun
  held R reloads); gun and helm button prompts + Controls Reference rows; renderer scratch ring 4 MB with a tail
  reserve so the first-person arm/gun can't be written past the end (render distance 24 segfault); duplicate items warn.
- Known issues: scripted playthrough Blight fight; rd 24 Fancy smoke run aborts inside the CI paravirtual GPU driver;
  the debug build fails to link on CI.

### Work queue (2026-10-01: this is the only session now; the six workstream PRs are handed off and merged here)
Priority: crashes/CI first, then gameplay, then content, then polish. [x] done here, [ ] open.
- CI / crashes
  - [x] Settings.subtitles <-> AudioSettings.subtitles infinite recursion (every frame hung); padtest toggles both menus.
  - [x] Vibrant mip average split into typed lets (Swift 6.3 type-check timeout); CI type-check time gate (>= 400 ms fails).
  - [ ] rd 24 Fancy smoke abort (AppleParavirtCommandBuffer endCurrentChunk) and the debug-build link error.
  - [ ] Combined-build CI shots: confirm the Paravirtual base-vertex guard cleared the black/scrambled terrain.
  - [ ] Audio (#4): confirm Synth.wash clamp un-silences mountainWindLoop/snowWindLoop; first CI run of --audiotest.
  - [ ] UI (#5): padtest "taking damage rumbles" (lastHurtSound reset); look at tv_combat / vehicle_hud / tv_map.
  - [ ] Visuals (#6): verify the half-res volumetric shafts (~4.7 ms tour avg), cave_torches shot, glowstone not clipping.
  - [ ] Terrain (#7): CI on the WIP commit (lake/delta tours, climate maps, --onland aerial tours); terrain check 0 problems.
  - [x] Physics (#8): frigate patrol altitude (hoverY floor is the spawn altitude); calib.cpu_ms in perf/baseline.json.
  - [ ] Physics (#8): round-6 commits compile and pass physicstest; ship snapshots (props/wheels/barrels in place);
        flight24 cull_ms under 1.20 ms p50; refresh the perf baseline with the ships metrics.
  - [ ] Gameplay (#2/#3): mobtests 0 failed incl. new checks; playthrough green (Blight summon T, return rift, Blight fight).
- Gameplay
  - [x] Fancy ships use Vibrant's ship pipelines (shadows, emissive, flashes; dark under cover).
  - [x] Muzzle flashes light the terrain (player guns, soldiers, deck guns).
  - [ ] Soldiers' cover/flank inside a real fortress; gun damage balance vs soldiers and players.
  - [ ] Pad-control gameplay tests for the airship and aircraft (padtest drives only the car).
- Content
  - [ ] Copper golem (needs copper chests); the spear.
  - [ ] Biome balance (snowy northern seeds, rare badlands/pale garden); lakes, deltas, fjords in game.
  - [x] Steelhold soldiers crew the vessels (marksmen + rifle troopers on the frigate, trooper + arc ironclad on the
        carriage) and hold their stations aboard (aim and fire, no cover runs overboard); physicstest check.
- Polish
  - [ ] Map waypoint/pin; free pad cursor for menus; per-voice pitch jitter; waterfall/river audiotest.
  - [ ] Mob shadow-map shadows, eye adaptation, gun icons via ItemTextures.autoPainter; terrain gen perf (ore veins, tints).
  - [ ] Real-M1 checks: base-vertex path, Fancy GPU time (F3), the seed 777 night ocean seam grid.

## Naming (repo is public)
All player-facing names are Blocksmith's own: the Emberdeep (fiery dimension), the Hollow (void dimension), Hisser,
Voidwalker, Wailer, Cinderwisp, Boarling/Tusker, Shellsentry, the Blight (summoned boss), Deep Stalker + Murk blocks,
Hollow Wyrm, Marauder/Brigand/Conjurer/Hexling/Siegebeast raiders, Sparkstone circuits, Lumenstone, Deeprock, Onyxstone,
Duskium, Violite, Tidestone, Proving Halls, Forest Manor, Sea Temple, Buried Citadel, Boarling Keep, Hollow Spires...
Internal keys (block/item names, MobKind.keys, Dim raw values) are unchanged save IDs, so old worlds load as before.
No third-party text, textures, sounds or logos: everything is procedural or written for Blocksmith.

## Roadmap / progress
| Phase | Scope | State |
|---|---|---|
| A1 Engine | 16-bit block states (flattened), world y −64…319 (internal 0…383), 16³ section meshing with 48³ local light region, stored per-section light, box models, biome tints, box collision + step-up, name-paletted chunk saves | done, CI-verified |
| A2 Font | original 5×7 pixel font in the texture array; HUD text, toasts, F3 overlay | done |
| A3 Items | item registry (materials, food, tools ×6 tiers, armor ×6), ItemStack/inventory (36 + armor + offhand), survival mining time (hardness/tool/tier formula), drops table, dropped item entities (physics, merge, pickup), durability, attack cooldown, eating, buckets, Q/B drop, death drops | done |
| A4 Containers | MC-style menus (click/right-click/shift-click/number keys, controller cursor), 2×2 + 3×3 crafting with recipe engine (tags, mirroring), furnace (fuel/smelt ticks, lit state), chests, creative palette | done (recipe list keeps growing) |
| B Survival content | zombie/skeleton/hisser/spider/voidwalker/slime with light-based spawning, combat (cooldown, crits, knockback), armor, bow, beds + sleeping, farming (wheat/carrots/potatoes/beetroot, farmland moisture, bone meal), breeding, TNT + explosions, XP, fire | done |
| C Emberdeep | portals, lava, 5 emberdeep biomes, fortresses (bridges, castle, cinderwisp spawners, wart rooms), bastions (housing, treasure, stables, bridge), onyxstone set, spawners, undead boarling (group anger), boarling (bartering, gold armor), brute, tusker, magmastrider, wailer (deflectable fireballs), cinderwisp, lava blob, blight skeleton (blight effect), emberdeep wart | done |
| D End | 128 strongholds in rings (portal room, libraries, prisons, fountains), eyes of ender, hollow gate (12 frames, 10% pre-filled), the Hollow (central island, 10 spikes with crystals/cages, bedrock fountain, 1000-block void, outer islands, spiral), hollow wyrm (circle/strafe/charge/perch, breath clouds, crystal healing, 12000 XP, egg, gateways), hollow spires + ships (glider wings), shellsentrys (levitation), glider wings flight + rockets, credits | done — scripted start-to-credits playthrough on CI (`--playthrough`, PR #3); see "Completability" below |
| E Terrain parity | new surface generator: 5 climate noises → all 53 surface biomes (multi-noise tables), continentalness/erosion/weirdness height with rivers, plateaus, windswept hills and 250-block peaks, 3D density overhangs; cheese/spaghetti/noodle caves, aquifers, lava below y −55; 1.18 ore distributions + granite/diorite/andesite/tuff/dirt/gravel blobs; geodes, dungeons, lush/driprock/deep-dark cave decoration; per-biome surfaces (badlands bands, hoodoos, podzol, snow) and a final freeze pass; 20 tree shapes (fancy oak, mega spruce/jungle, acacia, dark oak, mangrove, cherry, huge mushrooms, ice spikes); vegetation incl. two-tall plants, sugar cane, cacti, bamboo, kelp, corals, lily pads, icebergs. Structures: villages (5 styles), desert pyramids, jungle temples, swamp huts, igloos, marauder watchtowers, ruined portals, shipwrecks, buried treasure, mineshafts, desert wells, strongholds  Big structures: sea temples (spikefishs, elder spikefishs, sponge rooms, gold core), forest manors (3 floors, brigands/conjurers, loot), buried citadels (murk, shriekers, deeprock, loot), proving halls (tuff/copper halls, proving spawners, vaults), ocean ruins, trail ruins (suspicious gravel), fossils | done — structures are hand-built approximations of the reference layouts |
| F Sparkstone | power levels 0–15 with strong/weak conduction; dust networks (cross/line shapes, slopes), torches (1-tick inverters, burnout), levers, buttons (stone/wood timings), pressure plates (incl. weighted), repeaters (delay, locking), comparators (compare/subtract, container fill), observers, pistons + sticky pistons (12-block limit, slime/honey groups, quasi-connectivity, entity pushing), sparkstone lamps/blocks, dispensers (arrows, fire charges, buckets, TNT, bone meal, armor), droppers, hoppers (5 slots, 8-tick transfers, locking, furnaces), note blocks (13 instruments × 25 pitches), daylight detectors, targets; doors/trapdoors/gates/TNT/bells react to power; rails (10 shapes incl. slopes/curves, auto-shaping), powered/detector/activator rails, rideable minecarts | done — not yet: tripwire, trapped chest, murk sensor, lectern output, crafter |
| G Long tail | **Effects**: all 39 status effects with reference numbers (regen/poison/blight timing, absorption + health boost hearts, speed/slowness/jump/slow falling/levitation, haste/fatigue mining, resistance, fire resistance, water breathing, night vision, blindness/darkness fog, hunger, ill omen/siege omen/hero), HUD icons + inventory list. **Brewing**: brewing stand (cinderwisp fuel, 20 s brews, 3 bottles), every potion (normal/long/strong) × drink/splash/lingering/tipped arrows, full recipe table incl. fermented spider eye corruption, witches using the reference potion logic. **Enchanting**: 42 enchantments (weights, level windows, exclusivity), table with bookshelves + lapis + XP and the reference selection algorithm, books, anvil (combine/repair/rename, prior-work penalty, too expensive, wear), grindstone, all effects (sharpness/smite/bane, knockback, fire aspect, looting, sweeping, efficiency, silk touch, fortune, unbreaking, mending, protection family, feather falling, thorns, respiration, aqua affinity, deep stride, swift sneak, ghost stride, power/punch/flame/infinity, multishot/piercing/quick charge, loyalty/riptide/channeling/impaling, luck/lure, curses). **Villagers**: 13 professions from job sites, 5 levels, reference trade tables, demand pricing, restocking, trading screen, nitwits, biome robes, zombie villagers + curing discount, wandering trader. **Raids**: omen bottles → Ill Omen → Siege Omen → 5(+1) waves of marauders/brigands/conjurers (fangs, vexes)/witches/siegebeasts (riders), raid bar, Village Hero; marauder patrols with captains. **Blight**: ghost sand + skulls summoning, 11 s charge + blast, skulls (blue), armor phase, block breaking, blight star; beacons (4 pyramid levels, powers, beam). **Mobs**: +46 kinds (animals with taming/riding/breeding foods, aquatic, bats, bees, parrots, fetchlings, nightwings from insomnia, spikefishs, deep stalker, gustling, mire skeleton, rot tusker, snow/iron golems built from blocks), biome spawn tables, mob persistence (per-chunk storage + mobs.json). **Weather**: rain/snow/thunder cycles, lightning (conversions, fire), snow layers/ice, sleeping skips storms. **Items/blocks**: shield, crossbow, trident, fishing (reference loot), thrown snowballs/eggs/void pearls, mob heads, carved pumpkins, falling blocks, 16-colour concrete/powder/stained glass/glazed terracotta/candles/shellsentry boxes, void chest, double + trapped chests, cake, dyes, smithing table (duskium upgrade, trims), stonecutter  **Blocks/items (later batch)**: copper family (oxidation, waxing, scraping, bulbs, grates), driprock, big dripleaf, murk + sensors/shriekers/catalysts (deep stalker summoning), campfires, beehives, rebirth anchors, sea pickles, turtle eggs, vaults, jukebox + 19 original procedural discs, signs (editable, text in the world), item frames (+ glow), paintings (40 motives, original art), maps (exploration, cartography table zoom/copy/lock), boats + chest boats + bamboo raft (9 woods), armor stands, mob armour (reference spawn odds with regional difficulty, reduction, drops), leads (leash, fence knots), spyglass + FOV effects, goat horns, banners (16 colours, 42 patterns, loom, pattern items, omen banner), fireworks (stars, shapes, trails, twinkle, fades, rockets, crossbow), barrel, smoker, blast furnace, composter, bell, books and quills / written books / lecterns, special crafting (banner/book/map copies, shield decoration), tripwire hooks + string, trapped chest power, murk sensor vibrations, copper bulbs toggling, crafter, bundles, log axes + stripped logs/wood/hyphae/bamboo blocks (axe stripping), hanging signs, chiseled bookshelves, decorated pots, wall torches + soul torches, wind charges, sponges, powder snow (freezing, leather boots), leather dyeing, horse + wolf armour, hollow crystals + dragon respawn ritual, minecart variants (chest/hopper/TNT/furnace), goat horns, advancements (76, five tabs, toasts, L screen), options (FOV, sensitivity, volume). **Worlds**: world list, create (name, seed text, mode, difficulty), difficulty (peaceful/easy/normal/hard damage scaling and starvation limits) | in progress — next: shield banner visuals, more structure-accurate layouts, controller-driven options menu, polish from live play |

## Moving block structures (Engine session, branch claude/free-physics)
Ships are free-moving block structures: boats, airships, aircraft, land vehicles (Ships.swift, ShipPhysics.swift,
ShipRender.swift, ShipPlay.swift, ShipBlocks.swift, ShipTest.swift).
- Build a structure, place a **Ship Helm** on it and use the helm: everything connected to it (not natural terrain,
  fluids or plants; up to 60 000 blocks) becomes a ship. Use the helm again to steer; sneak-use it to dock the ship
  back into the world (snapped to the grid and the nearest quarter turn).
- Parts: Propeller (pushes away from its front, needs an Engine; one engine drives 4 propellers/wheels), Engine,
  Lift Balloon (2 t of lift each; airships hold altitude, Space/Ctrl climb/descend), Airfoil (flat-plate lift for
  aircraft; 4+ airfoils and no balloons = aircraft controls: climb input pitches), Wheel (suspension, rolls along the
  ship's heading, grips sideways). The helm alone paddles a boat slowly. Wool blocks are **sails**: while someone
  steers they turn the wind (direction drifts over time, stronger in rain/thunder) into drive along the heading.
- Physics: 60 Hz substeps; buoyancy from blocks plus the hull's enclosed air (a stone hull floats like a steel ship),
  keel-like water drag, air drag, yaw-rate steering, self-righting, impulse contacts vs terrain and other ships.
- Aboard: the player moves in the ship's frame (World.frame): walking, jumping, ladders, building all work on a
  moving ship. Mobs and items collide with ship blocks in world space (approximate boxes) and are carried.
- Save: ships.json per dimension. Harness: `--ship boat|deck|airship|car`, `--physicstest` (strict, exit 1 on failure).
- Turrets and guns: a **Turret Ring** under a structure makes it a turret when the ship is assembled (it must touch
  the ship only through the ring); turrets turn to the pilot's view. **Cannons** fire shells (click / RT while
  steering, elevated to the view pitch); shells explode on terrain, ships, mobs and players. Explosions (TNT, hissers,
  shells) blow blocks out of ships and push them.
- Vessels (ShipVessels.swift): the **Skyward Frigate** (48-block flying warship, lift envelope, two turrets, broadside
  guns, Marauder crew, captain's chest) and the **Ironstride Siege Carriage** (six big wheels, armoured hull, giant
  three-gun turret). About one 2048-block region in 8 hosts one (seeded); it appears when the player comes within 150
  blocks, patrols around its home, and its turrets track and shell a survival player within 64-80 blocks. Steer one
  (take its helm) to capture it. Its guns hold fire on a player who has boarded. A vessel that loses its helm or
  more than 55% of its hull founders: the crew stops, the guns fall silent and a frigate's envelope lets it down.
  Harness: `--ship gunboat|frigate|carriage`; bench scene `ships`.
- Piloting: ships and aircraft hold their throttle like an engine telegraph (W/S or the stick move it, letting go
  keeps it, it pauses at stop); wheeled vehicles drive only while W is held. Propellers spin with throttle and power; wheels
  (each connected group of wheel blocks, e.g. a 5x5 disc) roll with the ground speed.
- A ship cut in two becomes two ships (hull splitting). A hull destroyed under a turret sets the turret loose.
- Cannon barrels rise with the guns' elevation. Ships darken under cover (their sky light follows the world's around
  them). Far ships sleep (no physics beyond 384 blocks) and free their meshes beyond the render distance. The steering
  hint shows controller buttons when a pad is connected. Advancements: Anchors Aweigh, Prize Crew, Brought Low.
- Known gaps: mobs aboard use approximate collision; ship light is baked in ship space (no world shadows/caves).
- Next: tuning from CI numbers, soldier crews once the Gameplay session adds soldiers (MobKind "soldier" is
  picked up automatically).

## Rendering fix carried from the performance branch (Engine session)
The single-draw-per-section path (base vertex + base instance) draws scrambled, black terrain on the CI runners'
paravirtual GPU (every PR #1 snapshot showed it). Renderer.baseVertexOK now skips it when the device name contains
"Paravirtual" (or with --no-base-vertex). Still to verify on a real M1 that the fast path renders correctly; if not,
the same flag turns it off. Confirmed on CI (spawn.png clean again).
Engine-session perf work since: background gen/mesh operations capture the World weakly (fix for the World leak the
perf handoff left open; watch bench worlds_alive), the culling walk stops above the tallest geometry in range, chunk
workers find circuit components that need periodic work. Ship costs (bench "ships", CI): physics 0.17 ms/frame with a
frigate and a siege carriage under way, frigate mesh 3 ms (background), block edit 0.5 ms. A blast remeshes only the
sections around its hole. The bench also times edit-to-visible, a blast, docking/assembling the frigate, and what
drawing two vessels adds to a 1080p frame. perf/compare.py discounts a slow shared runner using a fixed CPU
calibration workload (calib.cpu_ms) so gated CPU timings don't fail on runner noise.

## CI (compile/test loop)
- `.github/workflows/mac.yml` (macos-14 arm64, Xcode 16 / Swift 6.0.3): `./build.sh` + `./snap.sh` on every push;
  PNGs, WAVs and logs force-pushed to the orphan branch `ci-snaps` (README embeds them).
- Progression test: `Blocksmith --playthrough [--seed N] [--only overworld,emberdeep,stronghold,end,blight]` runs a
  fresh survival world through the real game loop — hand-mined logs, tool tiers, furnace, obsidian from water on lava,
  a lit portal, fortress cinderwisps (rod rate), voidwalker pearls, the way home, seeker eyes, the stronghold gate, the
  Hollow (crystals, wyrm fight, egg, rifts both ways, credits) and the Blight (summon, charge, armour, star, beacon).
  PASS/FAIL/INFO per step, non-zero exit on any failure; CI runs it after the build (log in `ci-snaps/playthrough.log`).
- Harness flags: `--find <biome>`, `--torches`, `--flood`, `--mobs`, `--menu inventory|creative|crafting|furnace`,
  `--drops`, `--survival HP`, `--debug`, `--sim SECONDS`, `--dim emberdeep|end`, `--portal`, `--hostile`, `--nethermobs`,
  `--structure <kind>` (camera at the nearest structure's anchor), `--menu brewing|enchant|anvil|trade`, `--effects`,
  `--spawn kind[:profession|:armour material|boat:variant[:c]],...`, `--place block[:state],...`, `--beacon`, `--weather rain|thunder`, `--ticks SECONDS`,
  `--decor`, `--map`, `--banners`, `--fireworks`, `--menu loom|book|advancements`;
  `Blocksmith --sounds DIR` (renders every sound; fails on silence, clipping, NaN, DC, wrong length, end clicks, loop seams),
  `Blocksmith --music DIR [--seconds N]` (renders every music mood; fails on level/clipping/note/length problems).

## Controls
Keyboard/mouse: WASD, Space (double-tap = fly in creative), Shift sneak, Ctrl sprint, LMB attack/mine (hold),
RMB use/place/eat (hold), MMB pick block, 1–9/scroll hotbar, E inventory, Q drop (Ctrl+Q stack), G swap off hand, R reload, Tab weapon wheel,
M world map, F fly, T / slash commands,
F1 hide HUD, F2 screenshot (~/Pictures/Blocksmith), F3 debug, F5 camera (first person / behind / in front, with a player model).
Menus: click / right-click / shift-click, number keys swap with hotbar, click outside drops, arrow keys move the cursor, Tab switches creative tabs.
Controller (console layout): LS move (full forward = auto-sprint), RS look, A jump, B / RS click sneak (hold or toggle), L3 sprint,
RT attack/mine, LT use/place/eat, LB/RB hotbar, Y inventory, X pick block, D-pad ↓ drop (hold: whole stack), ↑ fly, → swap off hand,
← command console, View camera, Menu pause, Share screenshot. Options > Controller: southpaw sticks.
In menus: D-pad/LS move the cursor (held directions repeat), A take/place/select, X split/place one/previous value, Y quick move,
RT drop, B back/close, LB/RB tabs (options pages, creative tabs, advancement tabs, recipe book pages), RS / LT / RT scroll and page.
On-screen keyboard (Y in any text field): A type, X delete, Y space, LT shift, Menu done.

## Voice bug notes
Options > Interface > Bug Notes (Off / Always Listening / Push-to-Talk: F7 or L3 + R3). Speak a bug while playing and it is
appended to ~/Documents/Blocksmith/BugNotes/bug-notes.md, with the transcript (on-device Speech, en-US), build commit,
world + seed, dimension, position/facing, biome, targeted block, mode, time/weather and frame time. A screenshot from when
the note started and the note's .m4a are saved next to it. Mic dot on the HUD, "Note saved" toast, the game never pauses.
Denied permissions grey the option out. CI: `--bugnotetest` (synthesized voice through the real pipeline, stub
transcriber). How a session turns the file into fixes: BUGNOTES.md.

## Couch / TV mode (controller workstream)
Playing on the TV: pair the Xbox controller in System Settings > Bluetooth (hold the pairing button until the logo flashes
fast), plug the Mac into the TV, launch Blocksmith — it opens full screen and the title screen says "<pad> ready". Turn on
Options > Interface > Couch Mode for a bigger HUD; if the TV crops the edges raise Safe Area; on a 4K TV set
Options > Video > Resolution to 75% for a steady 60 fps on the M1.
- `PadManager` (Controller.swift): hotplugging with toasts, the pad dropping out mid-game pauses, player LED, battery shown in
  Options > Controller, rumble through CoreHaptics (hurt, explosions, mining, attacks, bow, landing, thunder, level up; strength option),
  and "last device used" so every prompt shows controller glyphs or key caps automatically (Options: Button Prompts auto/pad/keys).
- Button glyphs (Glyphs.swift): private-use characters drawn by the HUD text renderer as pixel-art badges (coloured A/B/X/Y,
  LB/RB pills, LT/RT triggers, sticks, D-pad arms, Menu/View/Share) and key caps / mouse buttons. Menu legends change with the hovered
  slot ("A Pick up  X Pick up half  Y Quick move" / "A Place all  X Place one"); pad cursor is a bright frame.
- Options (PauseMenu.swift): six pages switched with LB/RB — Keyboard & Mouse, Controller (look speed X/Y, look acceleration, invert,
  dead zone, aim assist, vibration, southpaw, sneak hold/toggle, auto-sprint, prompts), Video (render distance, fullscreen, start in
  fullscreen [default on], VSync, frame-rate cap, resolution scale, FOV, GUI scale), Audio (+ subtitles), Interface (GUI scale, couch
  mode, safe area 0–10 %, button hints, text background, hide HUD, debug), Accessibility (subtitles, colourblind-safe colours,
  text background, tutorial tips). D-pad left/right changes the highlighted setting; every row has a help line; long pages scroll.
  Settings persist in UserDefaults (Settings.swift `@Pref`).
- Menus shrink to a GUI scale that fits the screen and safe area (HudLayout.fitted), so couch mode on a 1080p TV never overflows.
- Worlds (WorldStore.swift): newest first with mode + last played; per-world Play / Rename / Copy / Delete (confirmation with Cancel
  selected; deletes go to the Trash). The open world can be copied but not renamed/deleted. Save and Quit to Title.
- Creative palette: 9 tabs (All, Building, Natural, Functional, Sparkstone, Tools & Combat, Food & Potions, Ingredients, Search) with
  an icon tab strip; Search filters by name (keyboard or on-screen keyboard).
- In game: contextual prompts bottom-right ("RT Mine  LT Place  X Pick Block"), LB/RB beside the hotbar, first-steps tutorial tips
  (look, move, jump, mine, place, inventory, hotbar), subtitles with left/right arrows, aim assist (view slows over hostile mobs and
  while mining; controller only).
- Harness: `--padtest` drives Game.tick with a simulated pad through ~45 checks (pause, options pages/values, keyboard typing,
  world copy/delete/rename, inventory, creative tabs/search, gameplay buttons, look, rumble, TV fit); a failure makes the run exit 3.
  `--pad` (pad glyphs), `--couch`, `--safe N`, `--hints`, `--padview keyboard|worlds|world|confirm|controls|title|video`.
  Options changed by the harness are restored and worlds live in a temp folder. Snapshot shots hide tips/prompts unless `--hints`.
- Later additions: keyboard key rebinding (Options > Keyboard & Mouse > Key Bindings; conflicts swap; prompts follow the
  bindings), crosshair styles (classic / bold / dot), reduced screen flashes, Reset Options (confirmation), sticky block
  targeting for the pad (highlight holds ~0.12 blocks past an edge), on-screen keyboard with a live preview that opens by
  itself for signs and text fields, LB/RB page turning in books, loading screen on world switch (and straight into the
  world afterwards), pad status on the title, "controller disconnected" note on the pause menu.
- Button remapping: Options > Controller > Button Mapping (each logical button with all its uses: "Pick Block / Reload",
  "Hotbar Right / Weapon Wheel", "Camera / World Map (hold)"...; swaps on conflict). Every pad read goes through PadMap.
- Not yet: a free-moving pad cursor option for menus.

### Vehicles, guns, combat HUD, maps (2026-10-01 queue, built on PR #8 vessels + PR #2 guns)
- Vehicles (VehicleControls.swift): one input reader for every vessel kind. Unarmed boats / land vehicles: RT throttle, LT
  reverse/brake, LS steer (W/S + A/D on keys); airships: RT/LT throttle, LS up/down climb; aircraft: RT throttle, LS pitch
  (Options > Controller > Flight Stick: pull back to climb or push up), Space/Ctrl (keys) and RB/LB (pad) climb/descend on all. Armed vessels
  keep PR #8's scheme (RT fires the cannons, stick throttle). B / Shift leaves. On-screen prompts change per vessel.
- Deck guns (Turrets): LT / right-click on a Steelhold deck gun mans it; the barrels follow the view (clamped elevation),
  RT / left-click fires both barrels, 3 s reload shown as a bar, B / Shift steps off.
- Guns: R / X reload (rebindable), RT fire, LT aim down sights (look slows with the zoom), aim assist on the pad snaps toward the
  nearest soldier or hostile in a narrow cone when ADS starts and tracks gently (Options > Aim Assist; line of sight only).
  Weapon wheel (CombatHUD.swift): hold RB / Tab, pick a sector with RS / mouse, release to equip; a quick RB tap still turns
  the hotbar, a quick Tab picks the next gun. Off while steering or manning a gun.
- Combat HUD: ammo + reload (PR #2's counter), hit markers, red damage-direction marks around the crosshair (fade 1.6 s),
  armour wear bars beside the hotbar (survival), vehicle panel (name, km/h, heading, altitude for aircraft, throttle bar,
  hull integrity, lift %, guns ready/loading), deck-gun reload bar.
- Maps (WorldMap.swift): M or hold View opens the world map (pan with LS / D-pad / arrows / drag, zoom with triggers / bumpers
  / scroll, A recentres, legend); biome colours shaded by height, filled by a background worker. Discovered Steelhold bases and
  villages (within 96 blocks) are marked, toasted and saved per world (mapmarks.json). Minimap top-right (Options > Interface).
  Pause menu: World Map.
- Rumble: per gun (rifle crack, light chatter ticks, heavy shotgun / farsight / launcher thumps, dry-fire click), reloads,
  near misses, explosions with distance falloff (cannons, shells), vehicle crashes (sudden velocity change) and hull hits.
- Settings: Video page also holds Graphics (Fancy/Fast) and World Scale (PR #6); one subtitles setting (the audio
  workstream's); Resolution keeps "renderScale" and the Fancy world scale is saved as "fancyWorldScale"; Reset Options covers
  volumes and graphics. Audit.swift (run by --padtest): duplicate settings keys, key bindings (incl. reserved keys), button
  mapping, options rows (ids, labels, help text, every value steps and cycles back), mob save keys, shared names (warning).
- CI: padtest drives the car (RT/LT/B, gauges, hull-hit rumble), the deck gun, the weapon wheel (hold + quick tap), reload,
  ADS snap, the damage indicator, the world map (open/zoom/pan/recentre/close, hold View vs tap), discovery dedupe, rumble
  per gun / explosion distance. `--padview map` / snaps tv_map.png.

## Realistic terrain (branch claude/realistic-terrain, PR #7)
- `Sources/Terrain.swift` drives the overworld surface; `WorldGen` turns it into blocks (density, caves, ores, surface
  rules, trees). Fields: continents (warped fbm), mountain belts (crest + foothills, peaks ~250), hills, mesa terraces,
  sea cliffs, an erosion filter (slope-aligned gullies), a 128-block river graph (steepest descent, rain-weighted
  upstream counts) with valleys, channels, levees, floodplains, deltas, fjords on cold mountain coasts, basin lakes at
  their spill level (salt flats when dry). Climate: latitude-like temperature bands along z (period 9000 blocks; z=0
  temperate, +z warmer), altitude lapse, rainfall with latitude cells, continental drying, rain shadows.
- Also: dry washes and steep river canyons in arid country, table-land plateaus with escarpments, desert dune fields,
  ravines (cave carver, ~1 per 150 chunks), large copper (granite) and iron (tuff) ore veins, swamp pools, boulders,
  fallen logs, shingle beaches on cold coasts.
- Biomes are picked from local climate (+ coherent jitter for ecotones); tints are blended in climate space; trees
  sample the climate with their own offset. `Terrain.implausible` lists pairs that must never touch.
- Handoff (session ended 2026-10-01): last green CI 8adc94a (0 implausible neighbours, 0 uphill rivers on 5 seeds;
  genbench 1.95 ms/chunk cold, 1.40 warm). The final WIP commit (shrubs, climate maps, genbench breakdown, --onland,
  --feature lake|delta, lake/delta tours, wider --find) has not been through CI yet. Left: verify it, tune aerial
  tours, check lakes/deltas/fjords in-game, perf pass on block work, PR #7 lists the rest.
- Harness: `--terrainmap DIR [--seed N --size B --step B --x X --z Z --strict]` writes terrain_<seed>.png +
  relief_<seed>.png and the neighbour check; `--genbench` prints ms/chunk on the perf bench's chunks and a water
  leak count. Caches (macro 16-grid, lattice nodes, river graph) are pure memo tables, so output is order-independent.
RMB use/place/eat (hold), MMB pick block, 1–9/scroll hotbar, E inventory, Q drop (Ctrl+Q stack), F fly, T / slash commands, F1 hide HUD, F2 screenshot
(~/Pictures/Blocksmith), F3 debug, F5 camera (first person / behind / in front, with a player model).
Menus: click / right-click / shift-click, number keys swap with hotbar, click outside drops.
Controller: LS move, RS look, A jump, B sneak, L3 sprint, RT attack/mine, LT use, LB/RB hotbar, Y inventory, View camera,
X pick block (reload while holding a gun), D-pad ↓ drop, D-pad ↑ fly. In menus: D-pad/LS move cursor, A = click, X = right-click, Y = shift-click,
B close, RS scroll creative.
  leak count; the CI step "Terrain check" fails on implausible neighbours or rivers whose surface rises downstream. Caches (macro 16-grid, lattice nodes, river graph) are pure memo tables, so output is order-independent.
Steering a ship (use its helm): W/S or LS throttle, A/D or LS turn, Space/A/RB climb, Ctrl/LB descend, LMB/RT fire
Steering a ship (use its helm): W/S or LS throttle (ships and aircraft hold it like an engine telegraph, pausing at stop; wheeled vehicles drive while held), A/D or LS turn, Space/A/RB climb, Ctrl/LB descend, LMB/RT fire
cannons (turrets follow the view), Shift/B leave the helm, F5 pulls the camera back to fit the ship. Sneak-use the
helm to dock the ship into the world. /vessel frigate|carriage|locate.

## Rendering performance
- Solid cube faces are drawn first without alpha test (keeps the GPU's hidden-surface removal), cutout faces
  (leaves, plants, models) second; far chunks use "fast" leaves (no faces inside canopies). Section meshes are
  carved from pooled 4 MB slabs (one MTLBuffer per section cost a 16 KB page each: rd 24 resident 2.0 GB -> 1.1 GB).
  CI median-of-30 frames at rd 16: 5-7.5 ms on seeds 12345/777/424242, rd 24 12 ms.
- Greedy meshing of flat-lit cube faces (merged quads take repeating UVs from their position in the shader).
- LOD: chunks beyond 8 chunks mesh with flat light (fully merged), no plants/rails/dust, and skip faces facing pitch-dark
  cells; they re-mesh when crossing the boundary. Render distance goes up to 24 in Options.
- Cave culling: each section stores which faces connect through open cells; the renderer walks sections outward from the
  camera through connected faces only (plus frustum). CI rd 12 overworld frame: ~26 ms -> ~9 ms (VM GPU).

## Performance (benchmarks)
`./bench.sh` (CI step "Benchmarks") runs `Blocksmith --bench snaps/bench.json`: gen, mesh, startup, frame (rd 16 at
800p/1080p/4K), edit, mobs, save, and flights at rd 8/16/24 (20 blocks/s for 12 s, paced to 60 fps). `perf/compare.py`
compares with `perf/baseline.json` (table in the ci-snaps README) and fails CI on large regressions of stable metrics.
`perf/profile.sh <scene>` samples a scene with macOS `sample` (CI step "Profile": flight16, meshprof, genprof).
Numbers are from the CI runner (Apple Paravirtual GPU, 3 cores → 2 workers), so absolute values are pessimistic
next to an M1 Air (8 cores → 6 workers, real GPU); compare runs with each other.

| metric (CI) | baseline 37e7b89 | 9a60a5e (final) |
|---|---|---|
| gen, single thread | 1.94 ms/chunk | 1.68 ms/chunk |
| mesh, single thread (full / far LOD) | 9.9 / 9.8 ms/chunk | 2.4 / 1.9 ms/chunk |
| startup: first load r 4 / fill rd 12 | 304 ms / 33.8 s | 118 ms / 4.6 s |
| flight16 frame p50 / p95 / p99 / max | 4.6 / 7.5 / 11.8 / 25.2 ms | 4.1 / 5.2 / 5.9 / 14.4 ms |
| flight24 frame p50 / p95 / p99 / max | 8.7 / 12.4 / 16.7 / 28.0 ms | 7.1 / 8.0 / 8.8 / 10.9 ms |
| flight16 / flight24 coverage min | 77% / 86% | 96% / 97% |
| flight24 resident peak / chunk data / meshes | 771 / 622 / 126 MB | 418 / 222 / 131 MB |
| frame rd 16 GPU p50 800p / 1080p / 4K | 2.9 / 3.3 / 4.4 ms | 1.9 / 2.2 / 3.2 ms |
| edit (sync remesh) | 1.09 ms | 0.43 ms |
| game tick: empty / 150 mobs | 0.46 / 0.94 ms | 0.03 / 0.22 ms |
| save | 2.9 ms/chunk on the main thread, all disk chunks rewritten each autosave | background queue, unchanged chunks skipped |

Open: `--bench` shows `World` objects that outlive their scene (their Game is freed, no jobs queued): something
still references the World (seen after save, tnt, fluids, startup and flight scenes). Would leak a world per world
switch in the app. `bench.log` prints each live world's state.

Findings / changes (performance branch):
- Streaming throughput was capped by scheduling, not CPU: only `maxJobs` jobs were handed out per frame, so ~120
  jobs/s on CI (~360 on an M1) no matter how fast gen/mesh are. Workers now run from an OperationQueue kept 4x deep;
  results are applied within a 4 ms per-frame budget.
- Loaded area is a disc (mesh radius + 1 ring, unload at + 2) instead of a square: ~20% fewer chunks.
- Light is stored per section (nil until meshed; uniform dark / sky sections share one array) instead of 96 KB per chunk.
- Saves: chunks unchanged since their last save/load are skipped (copy-on-write identity check), writes happen on a
  background queue (queued data stays readable, flushed on quit), palette through a flat table.
- GPU buffer pool: freed mesh slices wait 0.25 s before reuse (in-flight frames could read overwritten meshes); tint
  tables come from one shared slab instead of one MTLBuffer each; chunk draws are one draw call per section
  (per-section records read by instance id, base vertex, slab rebound only on change).
- Mesher: per-thread scratch buffers through pointers (the profile showed ~40% of meshing in copy-on-write checks and
  page zeroing of per-section 110K-cell arrays); skylight flood skipped when the shell is all above the heightmap;
  provably dark far (LOD 1) sections skip light/faces entirely. Renderer: cave-culling walk uses a per-frame chunk grid.
- Random ticks drew 3 system-CSPRNG numbers per section per frame (top main-thread cost): now one xorshift draw.
- World.update skips its scheduling scan when nothing changed; LOD boundary has one chunk of hysteresis.
- Worldgen stone fill interpolates the density lattice per column (bit-identical; `--bench` self-checks it).
- Dynamic resolution above 1440p (4K TV): the drawable scales 60-100% with GPU frame time (`dynamicResolution` default).
- Harness: draw calls / drawn quads / visible sections, terrain hash (flags terrain changes), renderer init twice
  (first launch compiles shaders ~0.5 s; the second takes ~15 ms thanks to Metal's cache).

## Couch / TV mode
- In-game pause + options screens (Metal-drawn) drive fully with a controller: FOV, sensitivity, invert Y, stick dead
  zone, render distance, GUI scale (auto/1-6), couch mode (bigger HUD), volume, music, difficulty, game mode, load world,
  new world. Button legends show under every menu when a pad is connected. Text entry (signs, book pages/titles,
  anvil names) works pad-only too via the on-screen keyboard (Y in any text screen).

## Polish (latest)
- Auto-Jump option (hops one-block steps while walking into them; handy on a controller). Long pause/options pages
  use two columns so they fit couch-mode GUI scales.
- Poses: sprint-swimming (0.6 tall, follows the view), crawling when there is no headroom, forced crouch under
  1.5-high gaps (sneak height 1.5, eye 1.27).
- Mob navigation: A* over block cells (walk, jump one, drop three, swim; avoids lava/fire/cactus/fence tops) for
  every mob walking towards something (chasing, food, beds, job sites); 4 searches / 1.5 ms per tick. --pathtest: a zombie
  walks around a 17-block wall to the player in ~9 s.
- Ashen Grove biome (high-weirdness dark forest): Ashbark wood family, ashen moss/carpets, hanging moss,
  nightblooms that open at night, Barkwraith hearts in trunks and the Barkwraith (moves only unobserved, dies with its heart).
- Torch light follows the reference curve with the default-brightness gamma lift; harness moves the camera out of
  solid blocks, finds cave biomes (lush_caves, dripstone_caves, deep_dark); trees stay out of structure footprints.
- Command console (T or /, or Commands... in the pause menu): /time /weather /gamemode /difficulty /tp /give /summon
  /kill /clear /effect /xp /locate /seed /spawnpoint /setblock with Tab completion, history and pad quick buttons.
- Third-person cameras (F5 / View) stop short of blocks and show an original player model with armour and held item.
- Nether wood family shown as Rustcap / Tealcap (display names only).
- Title screen at launch; recipe book in crafting screens (craftable/all, fills the grid).
- Death screen (message, score, Respawn / Title Screen; XP drops as orbs), live compass / recovery compass / clock icons.
- Audio (session: audio and music): every sound synthesized at launch or on first use (no samples). 3D sources through an
  AVAudioEnvironmentNode with distance rolloff, panning, obstruction/occlusion from a block raycast, and reverb that follows a
  cave factor; underwater low-pass; flat / interface / music buses. Looping emitters found by scanning around the player (fire,
  campfires, furnaces, lava, water, portals, beacons, spawners, rebirth anchors), rain / rain-on-roof, underwater, gliding,
  minecart, Emberdeep / Hollow / cave-biome beds; cave, Emberdeep, underwater and mountain-wind stings. Full roster: 16 block
  materials × break/place/step/hit/fall, every player action, doors/containers/mechanisms, bosses, villager work sounds, and
  ambient/hurt/death calls for every mob from 27 voice families. Volume sliders per category (Options → Audio…).
- Music: streaming synth (14 instruments) rendered on a background queue; motif-based composer per mood (title, day, night, rain,
  underground, underwater, creative, Emberdeep, the Hollow, boss). Director: instant switch for dimension/boss/title, else a
  piece every 6-15 min; ducks under a nearby jukebox. Discs are composed pieces (seeded by the disc name, tiled to the disc's
  length) played through a mono stream placed at the nearest playing jukebox (3D + occlusion).
- Audio hooks: mob hurt/death/ambient from the voice table, mob footsteps within 16 blocks, attack variants (crit/sweep/
  knockback/weak), shield block/break, armor equip per material (any path), doors/trapdoors/gates (wood/iron), container lids,
  pistons/levers/buttons/plates/tripwires, TNT fuse, copper wax/scrape, candles, paintings, item frames, pots, crafters,
  composters, vaults, rebirth anchors, sculk shriekers, villager work sounds at job sites, trades/level-ups/refusals, raid
  victory, zombie infection/cure, wyrm flaps/growls/breath, deep stalker heartbeat/sniff/sonic boom/emerge, voidwalker
  teleports, elder curse, gustling shots. Spatial voices are allocated by priority (free, else quietest/soonest-ending).
- Surface ambience by biome and time: birdsong in wooded land by day, owls and crickets at night, swamp frogs, jungle
  insects, surf near oceans, wind on peaks / snowy / dry biomes; rain hushes wildlife. Reverb follows the room (14 probe
  rays: enclosure + size pick small room / chamber / hall / cavern). Audio restarts itself when the output device changes
  (headphones, TV). Young mobs have higher voices. Materials now include netherrack and deepslate. Daytime music takes a
  biome flavour (Snowfields, Dunes, Open Water, Blossom). `--sounds` also writes 8 s soundscapes of 17 places.
- Audio extras: subtitles (Options → Audio: caption + direction arrow per sound, `--subtitles` shot), sounds carry by kind
  (explosions 64 blocks, thunder 160), note blocks with all 16 instruments and mob heads, beehive hum, fireflies, dry grass,
  Barkwraith hearts, boat paddling, a room reverb on the music. CI: `--sounds` 606 sounds / 0 failed, `--music` 14 moods / 0 failed.
- Audio round 2 (2026-10-01; this branch merges PRs #2, #7 and #8 so their content can be wired):
  - Weapons (WeaponAudio.swift): rifle, chatter gun, shotgun, farsight, rocket and arc lance each have their own fire
    (crack, body, ring, servo/pump/bolt, casing), reload, distant echo (automatic beyond 32 blocks) and dry fire;
    bullet impacts per material, near-miss whizzes, flesh hits, grenade bounces, ricochets; deck guns boom with a
    rolling tail, alarms, radio calls, turret whine.
  - Soldiers: an original clipped patter through a helmet comm filter for each rank (alert, attack, reload,
    grenade, retreat, idle, hurt, death) and boots-and-kit footsteps (ironclad plates clank).
  - Vehicles (VehicleAudio.swift): engines idle/full cross-faded by throttle with a starter, propellers by spin,
    rigging wind on airships, wheels on terrain, water on moving hulls, creaks, collisions, splashes, helm cues.
  - Terrain and weather (TerrainAudio.swift): streams and waterfalls from the block scan, mountain wind and
    rockfalls, tundra wind and ice creaks, swamp insects, rain on leaves, snow wind, far thunder beyond 72 blocks.
  - Music: High Passes / Mire / Canopy by biome; Steelhold tension near a garrison; Firefight combat music while
    soldiers or deck guns hunt the player or a raid wave is near (held 15 s after).
  - Aircraft wing rush at speed; the Skyward Frigate's drone carries 160 blocks and the Ironstride Siege Carriage
    clanks on its treads out to ~100; a crewed vessel in gun range scores combat music (tension when near).
    Positional loops now use each sound's own range.
  - Tests: `--sounds` renders and checks every sound (752+) and 35 soundscapes; `--audiotest` (snap.sh) runs the
    ambient director headless in record mode and checks the loops it asks for: car engine and wheels, plane props
    and wing rush, frigate drone, tension/combat levels, mountain/tundra/swamp beds, snow wind (no rain patter).
- Audio possible later: per-voice pitch jitter at playback (varispeed per voice); more distinct voices for rare mobs.
- Landing / sprint dust, item equip animation, denser rain with ground splashes lit by daylight.
- Village life: beds and sleeping, food pickup + breeding, farmers harvesting, golems, midnight zombie sieges.

## Handoff (2026-10-01, session claude/eloquent-lovelace-bsc5v1 winding down)
Last pushed commit d92f9b0: build + 120 snapshots green on CI (ci-snaps-claude-eloquent-lovelace-bsc5v1).
Built in this session (latest round): Blocksmith naming pass + selftest naming audit (0 flagged); pause/options/
create-world/death/title menus; recipe book; F1/F2/F5 + third-person player model; command console; mob A*
pathfinding (doors for villagers/illagers); swim/crawl/forced-crouch poses; auto-jump; Ashen Grove biome (Ashbark
wood family, moss, nightblooms, Barkwraith + heart); resin, bamboo planks/mosaic, firefly bush, bush, leaf litter,
wildflowers, dry grass, cactus flowers; leaning wall torches; solid/cutout render split, fast far leaves, pooled
mesh slabs; reference torch-light curve; ruined portals grounded and kept out of spawn; trees kept out of structure
footprints; per-branch CI snapshot branches; harness: median-of-30 timing, memory/light probes, camera rescue,
cave-biome --find, --ground, --nightvision, --treecheck, --pathtest, --camera/--swim.
Left in this area (for the integration session):
- Underwater view: seabed is no longer black (water-coloured ambient) but the underwater fog ends at 20 blocks, so
  deep floors (seabed_warm/seabed_deep, ~27-33 blocks away) vanish into flat blue; lengthen underwater fog by depth/
  daylight (reference sees ~40-60 blocks in clear daytime water).
- rd 24 resident ~2.0-2.3 GB on the Mac vs ~1 GB accounted (see notes below) - performance work.
- Wall torches lean in 1/16 steps (boxes are integer); a real tilt needs fractional model vertices.
- treecheck reports 1-3 trunks per 200 in a neighbouring biome (trees straddling biome borders) - expected.
Known failing tests: none (snap.sh and --selftest pass on CI at d92f9b0).

## Notes for the parallel sessions
- Performance session: rd 24 resident is ~2.3 GB on the Mac while block+light arrays are ~740 MB (2601 chunks x ~285 KB)
  and Metal ~218 MB (harness prints both). Unaccounted ~1.3 GB: suspects are per-job mesher scratch (48^3 regions,
  n9 copies), generation lattices and allocator high-water. Uniform sections (all air / all stone) could skip their
  block+light arrays. This branch's pooled mesh slabs (MeshArena.swift) already removed the per-section 16 KB pages.
- Visuals session: distant ocean at night shows faint chunk-seam grid on the water surface (QA, seed 777).
## Mobs, villagers, raids (mob workstream, branch claude/epic-hamilton-t5vse7)
- Raids: 3/5/7 waves by difficulty (+1 bonus wave above omen I), reference bonus spawns, a captain per wave,
  siegebeast riders (marauder on Normal wave 5, conjurer + brigand from Hard wave 7), raid weapon enchants by omen level,
  omen absorption into a running raid, Village Hero gifts; day-only patrols sized by regional difficulty.
- Pathfinding (Pathfinding.swift): 8-way A*, ladders/vines/scaffolding, 2x2 footprint for wide mobs, water malus 8,
  fire/lava proximity malus, per-mob fall limits, zombies break wooden doors on Hard.
- Spawning (Spawning.swift): reference categories and caps, per-biome packs, light/sky rules, slimes, water/cave/ambient
  spawns, generation-time animal packs (populated.json), despawn timers, chicken and spider jockeys.
- AI (MobAI.swift): follow ranges with line of sight + memory, sneaking/heads/invisibility, avoidance goals, babies
  follow adults. Villagers (VillageLife.swift): schedules, gossip/reputation (prices, golem hostility at -100), golem
  summoning by sleeping + gossiping villagers. Spawn eggs for every mob; zombie horse; Mirage Caster (illusioner).
- Behaviour (Conversions.swift, Bees.swift, MobAI.swift): zombies drown into Sunken, husks into zombies, skeletons
  freeze into strays, boarlings/tuskers turn undead outside the Emberdeep, tadpoles grow into frogs; Hard zombie
  reinforcements; wandering trader + llamas, village cats, skeleton trap horses; bees with hives, nectar, honey and
  crop pollination; voidwalkers carry blocks and dodge arrows; helmets block sunburn; strays/mire skeletons tip arrows;
  sunken throw tridents; tamed wolves defend the owner; cat morning gifts; sheep graze and regrow wool; foxes sleep by
  day; polar bear mothers; llama spit; pandas with personality genes; axolotls play dead; turtles/frogs lay eggs;
  mules and horse stat inheritance; reference baby odds; Cloudwailer (happy ghast) with harnesses.
- Newest roster, approximations from memory of the reference: Sunscorched Skeleton (parched, weakness arrows, desert,
  sun-proof), Dust Camel (camel husk carrying a dust zombie + sunscorched skeleton), Nautilus (warm oceans) and Sunken
  Nautilus (ridden by 5% of ocean sunken); nautiluses tame with pufferfish and can be saddled and ridden underwater.
  Not yet: the spear, copper golem (needs copper chests).
- More reference details: patrols move as a group (captain leads), structure spawns (watchtower marauders, sea-temple
  spikefish), villagers hide at beds during raids, zombification odds by difficulty, spiders leap, voidwalkers blink
  toward far targets and ignore pumpkin-headed players, loot pickup (55% x regional difficulty), boarling guard triggers
  (chests/gold), soul-fire / warped-fungus repellents, neutral mobs forgive after 30 s, llama caravans, deep stalkers dig
  out of the ground, village cats / desert camels at generation, shearing snow golems and mire skeletons.
- `--mobtests` (MobTests.swift) checks all of the above headlessly and exits non-zero on a failure.
## Graphics (visuals + audio session)
- Fancy = "vibrant" HDR renderer (Vibrant.swift, VibrantShaders.swift): 2048 sun/moon shadow map (64 blocks around the
  camera, texel-snapped, leaves cast dappled shadows, 5-tap PCF), N.L sun light + sky ambient, warm block light,
  emissive texels (lava, flames, lamps, lumenstone, faint ore specks), per-layer materials (glass/ice glossy, metal
  blocks tinted highlights, polished stone sheen, skylit tops wet + glossy in rain), water with refraction of the
  scene, screen-space reflections (sky fallback), Fresnel, depth absorption, caustics on the bed and seen from
  below, HDR sun glint; 5-level bloom, half-res god rays, sun haze, dawn/dusk + rain height mist, highlight
  shoulder tone curve, saturation/contrast/split-tone grade, vignette, night exposure lift. Options: Render Scale
  100/85/70% (world renders smaller, HUD sharp). If the Fancy shaders fail to build, the game falls back to Fast.
  CI frame (1280x800, VM GPU, median of 30): Fast ~2.5 ms, Fancy ~5.7 ms average over the tour.
- Item icons: ItemShapes.swift (89 original silhouettes) painted by ItemTextures.autoPainter (outline, light and
  shade rims, gradient); potions/splash/lingering bottles + tipped arrows use the same art. ItemArt masks remain as
  a fallback for anything without a shape.
- Not done: hardware ray tracing (optional in the brief; the raster path already covers shadows/reflections).
- Later round: dynamic flash lights (Game.addFlash: explosions, lightning, fireworks; ready for muzzle flashes),
  explosion fireballs + flash-lit smoke, HDR glow particles, shoreline foam, rain rings on water, rain puddles that
  mirror the sky, snow glitter, storm darkening, Snell's-window surface from below, HDR-lit clouds (warm sunset tops),
  galactic band at night, firelight flicker, backlit foliage, shadow-map reuse while nothing moved, distance LOD for
  shadow taps and water reflection steps, F3 GPU ms readout. Textures: planks, bark, stone, ores, wool, concrete,
  sand, gravel, dirt, grass. Harness: --gallery (block walls) + 5 family galleries, --boom, shore/underwater_up,
  rd16 Fancy vs Fast ground/aerial shots.
- Performance (CI macos-14 VM GPU, median of 30 offscreen frames, after shadow-map reuse + distance LOD):
  rd 16 aerial 1280x800 Fancy 4.64 ms vs Fast 4.25 ms; rd 16 ground 1440x900 Fancy 4.48 ms vs Fast 4.45 ms;
  tour average Fancy 3.9 ms (was 5.7 before the perf pass). On the Mac, F3 shows the real GPU ms; Render Scale
  85/70% is the lever if a MacBook Air at full retina resolution needs it.
- Also: mobs/player model/arm shaded by the sun shadow map (mobVibFS), pink anti-twilight arch at dusk, world normals
  in HDR shading + shipVibVS / Vibrant.shipSolid|shipCut|shipTrans for ships (wiring in the PR #6 comment); more
  textures: bricks, stone bricks, log ends, glass, terracotta, packed/blue ice, snow, speckled family.
- Volumetric light shafts (composite marches view rays through the shadow map: shafts through canopies even with the
  sun off screen), dimension-tinted ambient (warm Emberdeep, violet Hollow), lava keeps its orange (no white clip),
  ore emission only a faint glint (no x-ray glow in dark caves), night clouds dimmed, Violite/Hollow brick sheen,
  netherrack lumps, torch-lit cave + building galleries (day/night) in CI.
- Integration with the ship PR (#8): chunkVibVS already reads per-instance section records (VibSection); ship
  pipelines need an rgba16Float variant for the Fancy world pass (see the PR #6 comment).
- Options > Graphics: Fancy (default) / Fast, saved in UserDefaults `fancyGraphics`; harness `--fast` renders one shot in Fast
  without touching the saved choice.
- Fancy only: gradient sky dome (deeper blue overhead, warm glow around the sun at dawn/dusk, exactly the fog colour
  below the horizon), 3D cloud boxes (12x12x4, shaded sides, CPU mesh rebuilt only when the wind crosses a cell),
  water Fresnel + sun glint on surfaces seen from above, blob shadows under mobs/items/the third-person player,
  grass and flowers swaying in the wind (vertex shader, top corners only).
- Both modes: textured sun that reddens near the horizon, a moon with 8 phases (one per day), translucent rain/snow,
  lightning with a soft glow, blue-tinted moonlight, branching block-breaking cracks.
- Also both modes: twinkling stars, leaf textures painted as lit clumps, lava hot spots, ambient block particles (torch
  smoke/flames, campfire smoke columns, lava sparks, fire smoke), Emberdeep per-biome fog + drifting embers/spores/ash,
  underwater fog from the biome water colour and daylight, a tunic sleeve on the first-person arm. Fancy: Hollow sky streaks.
- Underground: fog and sky colour fade toward near-black with the smoothed skylight at the eye (far cave walls used to
  fog into bright sky blue). Fancy: terrain/water fog toward the sun takes the same dawn/dusk glow as the sky dome.
- Hisser has an original face (wide-set glowing slit eyes, zigzag mouth) on the mob and its head block.
- QA note "chunk-seam grid on distant night ocean, seed 777": not reproduced in the harness (ocean_night_777 shots,
  rd 16, Fancy and Fast); needs a live-play screenshot if it still shows.
- Harness: `--underwater`, `--crack <0..1>`, `--fast`, `--ambient` (2 s of ambient particles); `Blocksmith --atlas <prefix>`
  writes every texture layer as grid pages (prefix_0.png...) for texture review.

## Steelhold fortresses, soldiers and guns (gameplay session)
- Fortress (MilitaryBase.swift): very rare (at most one per 64x64-chunk region, fairly level plains/savanna/desert/snowy plains/badlands/meadow/forest/taiga), 63 blocks of
  blast-proof steel plating with corner towers. Basement depot + generator + barred vault, ground floor (gate hall,
  barracks, armory, mess hall, workshop), upper floor (command room, quarters, comms, medbay, barracks), roof with
  marksman posts; loot tables steelhold_armory/supply/command/vault. New blocks: steel plating (+stairs/slab), steel floor
  plate, hazard plating, armored glass, light panel, command console, ammo crate.
- Guns (Guns.swift, Ballistics.swift): Steelhold Rifle, Chatter Gun (SMG), Breach Shotgun (9 pellets), Farsight Rifle
  (scope), Skybreaker Launcher (rockets, break blocks), Arc Lance (instant energy beam, ignites). LMB/RT fires (hold for
  automatics), RMB/LT aims (zoom, tighter spread, softer recoil), R / pad X reloads (auto when empty). Ammo is crafted:
  rifle rounds, shotgun shells, heavy rounds, rockets, arc cells; magazine count in the stack tag; head shots x1.5;
  bullets pass through plants and shatter glass. Tracers, muzzle flash, hit marker, ammo readout, 13 synthesized sounds.
- Soldiers (Soldiers.swift): Recruit (20 HP, rifle/SMG, retreats when hurt), Trooper (30 HP, plated, shotgun rush or
  strafing rifle, grenades into cover), Marksman (26 HP, farsight with a red laser before each shot, keeps distance),
  Ironclad (60 HP, heavy armour, no knockback, launcher or arc lance, enrages). They alert each other, chase the last
  sighting, burst-fire and reload; drop their ammo and 25% their gun. Deck guns (150 HP) on the towers traverse slowly,
  solve a ballistic arc and fire twin explosive shells; they cannot depress far, so the wall foot is safe.
- `--mobtests` covers reloads, kills, recoil, pellets, rockets, beams, armour, alerts, marksman laser, deck gun salvos,
  drops, fortress rarity and layout. Snapshots: soldiers, deck_gun, gun_hip/aim/scope, steelhold, steelhold_gate.
- Tactics: soldiers duck into cover to reload, rifle troopers flank, automatic guns lay suppressing fire on the last
  sighting, marksmen relocate after shots; sentries walk the apron; the armory has weapon racks (guns in item frames).
  Gun tooltips (loaded rounds, ammo, damage, rate). Advancements: Behind Steel Walls, Locked and Loaded, Silence the
  Guns, The Bigger They Are.
- Also: player hurt cooldown (0.5 s, bigger hits land the difference; gun rounds skip it), raids saved with the world,
  bow skeletons circle-strafe, raid/patrol captains wear the omen banner.
- Later in the session: explorer maps from cartographers (Sea Temple, Forest Manor, Steelhold for masters), zombies
  trample turtle eggs, gun crosshair that opens with spread, gunfire alerts soldiers within 32 blocks, guns repair at
  the anvil, rounds spark off armour, soldiers tilt guns toward the target, deck-gun barrels recoil, bosses take 35%
  from guns. Playthrough: the test player clears bag junk, retries swallowed clicks, throws the return pearl from a
  settled spot.
- `--mobtests` covers reloads, kills, recoil, pellets, rockets, beams, armour, alerts, cover, marksman laser, deck gun salvos,
  drops, fortress rarity and layout, raid save/restore. Snapshots: soldiers, deck_gun, gun_hip/aim/scope, steelhold, steelhold_gate.

## Known gaps / decisions
- Save format changed with the engine rework (chunks3/, name-paletted); worlds from the 8-bit engine start fresh terrain.
- Terrain is generated with our own noises and numbers: same features, biome logic, rarities and ore distributions as the reference game, but not seed-identical worlds.
- Structure placement is deterministic per chunk: every piece is computed from world position, so structures spanning chunks line up.
- Structures: generated chests/spawners are block entities installed when the chunk generates; a chunk that
  unloads unmodified regenerates but keeps the existing (possibly looted) block entity.
- Emberdeep light: dimension ambient lifts the whole light curve (0.3 in the Emberdeep), approximating the reference
  game's ambient + default-brightness gamma.
- Mobs are saved per chunk (mobs.json) and come back when their chunk loads; natural hostiles are not kept.
- Credits text is original (the reference game's poem is not copied).
- Armor trims show in the tooltip (the player model isn't drawn in first person).
- Raids are saved with the world (raiders rejoin when their chunks load); so are the void chest, weather and insomnia timer.

## Completability (End / Blight) — handoff notes
- `Blocksmith --playthrough` (Sources/Playthrough.swift, CI step "Playthrough") plays seed 12345 from spawn to the
  credits and through the Blight with real input/mining/recipes/portals/mobs. Last runs: everything passes from spawn
  through the wyrm kill (~3 min of game time), egg, rift out (pearl), spire + glider wings, save/reload and credits.
  Still failing at handoff: the Blight fight — with diamond armour, Smite V sword and Power V bow the test player dealt
  ~475 arrow damage + 133 sword hits in 600 s but died ~10 times to skulls and never finished it (check: Blight
  regen/skull damage vs the reference, and the test's melee positioning against a hovering Blight). The return rift
  now uses a pearl in the test; walking into it by body contact (endPortalTick) did not trigger in CI although the
  logged positions overlap — the player gets nudged ~2 blocks in the first frame; worth a look. The egg torch trick
  depends on where the egg hops (up to 20 tries).
- Fixed on the way: persistent bosses/crystals despawning past 128 blocks, wyrm deaths without the death sequence,
  effects on bosses, head/body damage + 25% perch take-off, perch sequence + settling on the pillar, breath clouds,
  arrows bouncing off a perched wyrm / armoured Blight, return rifts (+ pearls and body contact), first-kill-only
  egg/XP, egg teleport, wyrm-kill + rift advancements, Blight movement/heads/difficulty, cinder rod looting, and
  `alive` never going false (dead players re-picked their own drops).

