# Status

Goal (from Remington, 2026-09-30): make Blocksmith play like the reference game as closely as practical —
every block, redstone, Nether, End, terrain/caves/structures/villages with the same rarities, raids, the
Wither, and a completable game. Assets stay original/procedural (no copied textures, sounds or decompiled
code); mechanics, names and numbers follow the reference game.

## Roadmap / progress
| Phase | Scope | State |
|---|---|---|
| A1 Engine | 16-bit block states (flattened), world y −64…319 (internal 0…383), 16³ section meshing with 48³ local light region, stored per-section light, box models, biome tints, box collision + step-up, name-paletted chunk saves | done, CI-verified |
| A2 Font | original 5×7 pixel font in the texture array; HUD text, toasts, F3 overlay | done |
| A3 Items | item registry (materials, food, tools ×6 tiers, armor ×6), ItemStack/inventory (36 + armor + offhand), survival mining time (hardness/tool/tier formula), drops table, dropped item entities (physics, merge, pickup), durability, attack cooldown, eating, buckets, Q/B drop, death drops | done |
| A4 Containers | MC-style menus (click/right-click/shift-click/number keys, controller cursor), 2×2 + 3×3 crafting with recipe engine (tags, mirroring), furnace (fuel/smelt ticks, lit state), chests, creative palette | done (recipe list keeps growing) |
| B Survival content | zombie/skeleton/creeper/spider/enderman/slime with light-based spawning, combat (cooldown, crits, knockback), armor, bow, beds + sleeping, farming (wheat/carrots/potatoes/beetroot, farmland moisture, bone meal), breeding, TNT + explosions, XP, fire | done |
| C Nether | portals, lava, 5 nether biomes, fortresses (bridges, castle, blaze spawners, wart rooms), bastions (housing, treasure, stables, bridge), blackstone set, spawners, zombified piglin (group anger), piglin (bartering, gold armor), brute, hoglin, strider, ghast (deflectable fireballs), blaze, magma cube, wither skeleton (wither effect), nether wart | done |
| D End | 128 strongholds in rings (portal room, libraries, prisons, fountains), eyes of ender, end portal (12 frames, 10% pre-filled), the End (central island, 10 spikes with crystals/cages, bedrock fountain, 1000-block void, outer islands, chorus), ender dragon (circle/strafe/charge/perch, breath clouds, crystal healing, 12000 XP, egg, gateways), end cities + ships (elytra), shulkers (levitation), elytra flight + rockets, credits | done (untested in live play) |
| E Terrain parity | new overworld generator: 5 climate noises → all 53 overworld biomes (multi-noise tables), continentalness/erosion/weirdness height with rivers, plateaus, windswept hills and 250-block peaks, 3D density overhangs; cheese/spaghetti/noodle caves, aquifers, lava below y −55; 1.18 ore distributions + granite/diorite/andesite/tuff/dirt/gravel blobs; geodes, dungeons, lush/dripstone/deep-dark cave decoration; per-biome surfaces (badlands bands, hoodoos, podzol, snow) and a final freeze pass; 20 tree shapes (fancy oak, mega spruce/jungle, acacia, dark oak, mangrove, cherry, huge mushrooms, ice spikes); vegetation incl. two-tall plants, sugar cane, cacti, bamboo, kelp, corals, lily pads, icebergs. Structures: villages (5 styles), desert pyramids, jungle temples, swamp huts, igloos, pillager outposts, ruined portals, shipwrecks, buried treasure, mineshafts, desert wells, strongholds | in progress — next: ocean monuments, ocean ruins, woodland mansions, ancient cities, trail ruins, trial chambers, fossils |
| F Redstone | power levels 0–15 with strong/weak conduction; dust networks (cross/line shapes, slopes), torches (1-tick inverters, burnout), levers, buttons (stone/wood timings), pressure plates (incl. weighted), repeaters (delay, locking), comparators (compare/subtract, container fill), observers, pistons + sticky pistons (12-block limit, slime/honey groups, quasi-connectivity, entity pushing), redstone lamps/blocks, dispensers (arrows, fire charges, buckets, TNT, bone meal, armor), droppers, hoppers (5 slots, 8-tick transfers, locking, furnaces), note blocks (13 instruments × 25 pitches), daylight detectors, targets; doors/trapdoors/gates/TNT/bells react to power; rails (10 shapes incl. slopes/curves, auto-shaping), powered/detector/activator rails, rideable minecarts | done — not yet: tripwire, trapped chest, sculk sensor, lectern output, crafter |
| G Long tail | villagers/trading, raids, Wither, enchanting, brewing, … | pending |

## CI (compile/test loop)
- `.github/workflows/mac.yml` (macos-14 arm64, Xcode 16 / Swift 6.0.3): `./build.sh` + `./snap.sh` on every push;
  PNGs, WAVs and logs force-pushed to the orphan branch `ci-snaps` (README embeds them).
- Harness flags: `--find <biome>`, `--torches`, `--flood`, `--mobs`, `--menu inventory|creative|crafting|furnace`,
  `--drops`, `--survival HP`, `--debug`, `--sim SECONDS`, `--dim nether|end`, `--portal`, `--hostile`, `--nethermobs`,
  `--structure <kind>` (camera at the nearest structure's anchor); `Blocksmith --sounds DIR`.

## Controls
Keyboard/mouse: WASD, Space (double-tap = fly in creative), Shift sneak, Ctrl sprint, LMB attack/mine (hold),
RMB use/place/eat (hold), MMB pick block, 1–9/scroll hotbar, E inventory, Q drop (Ctrl+Q stack), F fly, F3 debug.
Menus: click / right-click / shift-click, number keys swap with hotbar, click outside drops.
Controller: LS move, RS look, A jump, B sneak, L3 sprint, RT attack/mine, LT use, LB/RB hotbar, Y or View inventory,
X pick block, D-pad ↓ drop, D-pad ↑ fly. In menus: D-pad/LS move cursor, A = click, X = right-click, Y = shift-click,
B close, RS scroll creative.

## Known gaps / decisions
- Save format changed with the engine rework (chunks3/, name-paletted); worlds from the 8-bit engine start fresh terrain.
- Terrain is generated with our own noises and numbers: same features, biome logic, rarities and ore distributions as the reference game, but not seed-identical worlds.
- Structure placement is deterministic per chunk: every piece is computed from world position, so structures spanning chunks line up.
- Structures: generated chests/spawners are block entities installed when the chunk generates; a chunk that
  unloads unmodified regenerates but keeps the existing (possibly looted) block entity.
- Nether light: dimension ambient lifts the whole light curve (0.3 in the Nether), approximating the reference
  game's ambient + default-brightness gamma.
- Mobs and minecarts are not saved with the world yet (they respawn/despawn like before).
- Shulker boxes, item frames, dragon heads and ladders are not implemented yet (the end-ship elytra sits in a chest).
- Credits text is original (the reference game's poem is not copied).
- Wall torches render as standing torches; chests are single only. Potions/enchanted items are left out of the
  piglin barter table until brewing/enchanting exist.
