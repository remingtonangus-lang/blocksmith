# Status

Goal (from Remington, 2026-09-30): make Blocksmith play like the reference game as closely as practical —
every block, sparkstone, Emberdeep, End, terrain/caves/structures/villages with the same rarities, raids, the
Blight, and a completable game. Assets stay original/procedural (no copied textures, sounds or decompiled
code); mechanics, names and numbers follow the reference game.

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
| D End | 128 strongholds in rings (portal room, libraries, prisons, fountains), eyes of ender, hollow gate (12 frames, 10% pre-filled), the Hollow (central island, 10 spikes with crystals/cages, bedrock fountain, 1000-block void, outer islands, spiral), hollow wyrm (circle/strafe/charge/perch, breath clouds, crystal healing, 12000 XP, egg, gateways), hollow spires + ships (glider wings), shellsentrys (levitation), glider wings flight + rockets, credits | done (untested in live play) |
| E Terrain parity | new surface generator: 5 climate noises → all 53 surface biomes (multi-noise tables), continentalness/erosion/weirdness height with rivers, plateaus, windswept hills and 250-block peaks, 3D density overhangs; cheese/spaghetti/noodle caves, aquifers, lava below y −55; 1.18 ore distributions + granite/diorite/andesite/tuff/dirt/gravel blobs; geodes, dungeons, lush/driprock/deep-dark cave decoration; per-biome surfaces (badlands bands, hoodoos, podzol, snow) and a final freeze pass; 20 tree shapes (fancy oak, mega spruce/jungle, acacia, dark oak, mangrove, cherry, huge mushrooms, ice spikes); vegetation incl. two-tall plants, sugar cane, cacti, bamboo, kelp, corals, lily pads, icebergs. Structures: villages (5 styles), desert pyramids, jungle temples, swamp huts, igloos, marauder watchtowers, ruined portals, shipwrecks, buried treasure, mineshafts, desert wells, strongholds  Big structures: sea temples (spikefishs, elder spikefishs, sponge rooms, gold core), forest manors (3 floors, brigands/conjurers, loot), buried citadels (murk, shriekers, deeprock, loot), proving halls (tuff/copper halls, proving spawners, vaults), ocean ruins, trail ruins (suspicious gravel), fossils | done — structures are hand-built approximations of the reference layouts |
| F Sparkstone | power levels 0–15 with strong/weak conduction; dust networks (cross/line shapes, slopes), torches (1-tick inverters, burnout), levers, buttons (stone/wood timings), pressure plates (incl. weighted), repeaters (delay, locking), comparators (compare/subtract, container fill), observers, pistons + sticky pistons (12-block limit, slime/honey groups, quasi-connectivity, entity pushing), sparkstone lamps/blocks, dispensers (arrows, fire charges, buckets, TNT, bone meal, armor), droppers, hoppers (5 slots, 8-tick transfers, locking, furnaces), note blocks (13 instruments × 25 pitches), daylight detectors, targets; doors/trapdoors/gates/TNT/bells react to power; rails (10 shapes incl. slopes/curves, auto-shaping), powered/detector/activator rails, rideable minecarts | done — not yet: tripwire, trapped chest, murk sensor, lectern output, crafter |
| G Long tail | **Effects**: all 39 status effects with reference numbers (regen/poison/blight timing, absorption + health boost hearts, speed/slowness/jump/slow falling/levitation, haste/fatigue mining, resistance, fire resistance, water breathing, night vision, blindness/darkness fog, hunger, ill omen/siege omen/hero), HUD icons + inventory list. **Brewing**: brewing stand (cinderwisp fuel, 20 s brews, 3 bottles), every potion (normal/long/strong) × drink/splash/lingering/tipped arrows, full recipe table incl. fermented spider eye corruption, witches using the reference potion logic. **Enchanting**: 42 enchantments (weights, level windows, exclusivity), table with bookshelves + lapis + XP and the reference selection algorithm, books, anvil (combine/repair/rename, prior-work penalty, too expensive, wear), grindstone, all effects (sharpness/smite/bane, knockback, fire aspect, looting, sweeping, efficiency, silk touch, fortune, unbreaking, mending, protection family, feather falling, thorns, respiration, aqua affinity, deep stride, swift sneak, ghost stride, power/punch/flame/infinity, multishot/piercing/quick charge, loyalty/riptide/channeling/impaling, luck/lure, curses). **Villagers**: 13 professions from job sites, 5 levels, reference trade tables, demand pricing, restocking, trading screen, nitwits, biome robes, zombie villagers + curing discount, wandering trader. **Raids**: omen bottles → Ill Omen → Siege Omen → 5(+1) waves of marauders/brigands/conjurers (fangs, vexes)/witches/siegebeasts (riders), raid bar, Village Hero; marauder patrols with captains. **Blight**: ghost sand + skulls summoning, 11 s charge + blast, skulls (blue), armor phase, block breaking, blight star; beacons (4 pyramid levels, powers, beam). **Mobs**: +46 kinds (animals with taming/riding/breeding foods, aquatic, bats, bees, parrots, fetchlings, nightwings from insomnia, spikefishs, deep stalker, gustling, mire skeleton, rot tusker, snow/iron golems built from blocks), biome spawn tables, mob persistence (per-chunk storage + mobs.json). **Weather**: rain/snow/thunder cycles, lightning (conversions, fire), snow layers/ice, sleeping skips storms. **Items/blocks**: shield, crossbow, trident, fishing (reference loot), thrown snowballs/eggs/void pearls, mob heads, carved pumpkins, falling blocks, 16-colour concrete/powder/stained glass/glazed terracotta/candles/shellsentry boxes, void chest, double + trapped chests, cake, dyes, smithing table (duskium upgrade, trims), stonecutter  **Blocks/items (later batch)**: copper family (oxidation, waxing, scraping, bulbs, grates), driprock, big dripleaf, murk + sensors/shriekers/catalysts (deep stalker summoning), campfires, beehives, rebirth anchors, sea pickles, turtle eggs, vaults, jukebox + 19 original procedural discs, signs (editable, text in the world), item frames (+ glow), paintings (40 motives, original art), maps (exploration, cartography table zoom/copy/lock), boats + chest boats + bamboo raft (9 woods), armor stands, mob armour (reference spawn odds with regional difficulty, reduction, drops), leads (leash, fence knots), spyglass + FOV effects, goat horns, banners (16 colours, 42 patterns, loom, pattern items, omen banner), fireworks (stars, shapes, trails, twinkle, fades, rockets, crossbow), barrel, smoker, blast furnace, composter, bell, books and quills / written books / lecterns, special crafting (banner/book/map copies, shield decoration), tripwire hooks + string, trapped chest power, murk sensor vibrations, copper bulbs toggling, crafter, bundles, log axes + stripped logs/wood/hyphae/bamboo blocks (axe stripping), hanging signs, chiseled bookshelves, decorated pots, wall torches + soul torches, wind charges, sponges, powder snow (freezing, leather boots), leather dyeing, horse + wolf armour, hollow crystals + dragon respawn ritual, minecart variants (chest/hopper/TNT/furnace), goat horns, advancements (76, five tabs, toasts, L screen), options (FOV, sensitivity, volume). **Worlds**: world list, create (name, seed text, mode, difficulty), difficulty (peaceful/easy/normal/hard damage scaling and starvation limits) | in progress — next: shield banner visuals, more structure-accurate layouts, controller-driven options menu, polish from live play |

## CI (compile/test loop)
- `.github/workflows/mac.yml` (macos-14 arm64, Xcode 16 / Swift 6.0.3): `./build.sh` + `./snap.sh` on every push;
  PNGs, WAVs and logs force-pushed to the orphan branch `ci-snaps` (README embeds them).
- Harness flags: `--find <biome>`, `--torches`, `--flood`, `--mobs`, `--menu inventory|creative|crafting|furnace`,
  `--drops`, `--survival HP`, `--debug`, `--sim SECONDS`, `--dim emberdeep|end`, `--portal`, `--hostile`, `--nethermobs`,
  `--structure <kind>` (camera at the nearest structure's anchor), `--menu brewing|enchant|anvil|trade`, `--effects`,
  `--spawn kind[:profession|:armour material|boat:variant[:c]],...`, `--place block[:state],...`, `--beacon`, `--weather rain|thunder`, `--ticks SECONDS`,
  `--decor`, `--map`, `--banners`, `--fireworks`, `--menu loom|book|advancements`;
  `Blocksmith --sounds DIR`.

## Controls
Keyboard/mouse: WASD, Space (double-tap = fly in creative), Shift sneak, Ctrl sprint, LMB attack/mine (hold),
RMB use/place/eat (hold), MMB pick block, 1–9/scroll hotbar, E inventory, Q drop (Ctrl+Q stack), F fly, T / slash commands, F1 hide HUD, F2 screenshot
(~/Pictures/Blocksmith), F3 debug, F5 camera (first person / behind / in front, with a player model).
Menus: click / right-click / shift-click, number keys swap with hotbar, click outside drops.
Controller: LS move, RS look, A jump, B sneak, L3 sprint, RT attack/mine, LT use, LB/RB hotbar, Y inventory, View camera,
X pick block, D-pad ↓ drop, D-pad ↑ fly. In menus: D-pad/LS move cursor, A = click, X = right-click, Y = shift-click,
B close, RS scroll creative.

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
- Background music director (calm procedural pieces every 10-20 min, dimension moods), cave ambience, disc titles.
- Landing / sprint dust, item equip animation, denser rain with ground splashes lit by daylight.
- Village life: beds and sleeping, food pickup + breeding, farmers harvesting, golems, midnight zombie sieges.

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
- Raids are not saved across a reload (an unfinished raid ends); the void chest, weather and insomnia timer are.
