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
| C Nether | portals (any 4×5…23×23 frame, linking ×8), lava (flow, fire spread, obsidian/cobble/stone), 5 nether biomes, glowstone/quartz/gold/debris, fungus trees; building families (stairs/slabs/fences/walls, panes, iron bars); structure framework (region grid, per-chunk clipped pieces, loot tables, spawners); nether fortress (bridges, castle corridors, blaze spawner platforms, nether wart rooms, chests); zombified piglin, piglin (bartering), ghast (+ deflectable fireballs), blaze, magma cube, wither skeleton; nether/fortress spawn lists | in progress — next: bastions, hoglin, strider, spawner block logic |
| D End | eyes of ender, strongholds, End, dragon, credits | pending |
| E Terrain parity | biomes, caves, ores, structures, villages | pending |
| F Redstone | dust, torches, repeaters, comparators, pistons, … | pending |
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
- Terrain generator is still the original simple one (height noise + 7 biomes); phase E replaces it.
- Structures: generated chests/spawners are block entities installed when the chunk generates; a chunk that
  unloads unmodified regenerates but keeps the existing (possibly looted) block entity.
- Nether light: dimension ambient lifts the whole light curve (0.3 in the Nether), approximating the reference
  game's ambient + default-brightness gamma.
- Wall torches render as standing torches; chests are single only. Potions/enchanted items are left out of the
  piglin barter table until brewing/enchanting exist.
