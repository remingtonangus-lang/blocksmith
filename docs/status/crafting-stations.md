# Crafting stations: does one bench do everything?

## Plain answer for Remington
- One Crafting Table (3x3) makes every shaped and shapeless recipe in the game, steel gear, guns and ammo included. There is no tiered or per-material workbench and no armoury/forge bench (none found in the code).
- Steel is the only material with its own station rule: Steel Blend (2 iron ingots + coal) smelts into a Steel Ingot only in a Blast Furnace; a plain Furnace refuses it.
- Guns are plain crafting-table recipes (steel ingots + a Firing Mechanism); the gate is the loot, not a bench: Firing Mechanism / Targeting Optic / Radar Module only come from Capital citadel and armoury chests.
- The inventory 2x2 grid is the same recipe list, just limited to 4 cells: planks, sticks, torches, a Crafting Table and 3-item sidearm recipes fit; anything bigger needs the table.
- Optional/special stations: Smithing Table (Duskium upgrades, armor trims), Brewing Stand, Enchanting Table, Anvil, Loom etc. Only Duskium upgrade and potions/enchanting truly require their station.

## Stations
All stations open from `Game.openBlock` (Sources/Game.swift:1427-1522). Crafting itself is one function: `Recipes.match(grid, size, size)` (Recipes.swift:481), with size 2 for the inventory and 3 for the table (Menu.swift:345, 403).

| Station (display name, key) | What it does / required for | Recipes or items that REQUIRE it | Opened by |
|---|---|---|---|
| Inventory grid (2x2), `InventoryMenu` | Same recipe list as the table, 4 cells | Nothing requires it; fits any recipe whose bounding box is <=2x2 (shapeless <=4 items). Crafting Table `Recipes.swift:74` is `##/##`. | Inventory key (Game.swift:678); Quest uses the same menu |
| Crafting Table, `crafting_table` | 3x3 grid + recipe book (`CraftingBookMenu`), includes fireworks special-craft (Menu.swift:316) | Every recipe wider/taller than 2x2 or with >4 shapeless items: tools, armor incl. steel (Recipes.swift:222-229), rocket ammo (Guns.swift:89), rifle/SMG/shotgun/sniper/launcher/arc gun (Guns.swift:93-98) | Right-click (Game.swift:1430) |
| Furnace, `furnace` | Smelts ores, food, clay, sand etc. | Raw titanium -> titanium ingot (save key `diamond`, Recipes.swift:523); does NOT take Steel Blend (BlockEntities.swift:157) | Right-click (1431) |
| Blast Furnace, `blast_furnace` | Ores/ingots/nuggets only, 2x speed and 2x fuel burn (BlockEntities.swift:115-116, 160-162) | Steel Blend -> Steel Ingot: the only place it works (BlockEntities.swift:157, Recipes.swift:523). Built from 5 iron, a Furnace, 3 smooth stone (Recipes.swift:172) | Right-click (1435) |
| Smoker, `smoker` | Food only, 2x speed (BlockEntities.swift:159) | Nothing | Right-click (1435) |
| Campfire / Ghost Campfire, `campfire`, `soul_campfire` | Cooks up to 4 foods, 30 s each, no fuel menu | Nothing | Right-click with raw food (GameBlocks.swift:17-30) |
| Stonecutter, `stonecutter` | One stone block -> stairs/slabs/walls/bricks (Workstations.swift:85-110), derived from the crafting recipes | Nothing: every cut is also a crafting-table recipe | Right-click (1480) |
| Smithing Table, `smithing_table` | "Upgrade Gear": template + base + addition | Duskium Upgrade (diamond gear + Duskium ingot -> Duskium gear, Workstations.swift:36-46) and all armor trims; no recipe for Duskium tools exists on the table. Template recipe: Recipes.swift:365 | Right-click (1479) |
| Loom, `loom` | Banner patterns (Banners.swift:292) | Patterned banners only; plain banners are table recipes | Right-click (1503) |
| Cartography Table, `cartography_table` | Clone/zoom/lock maps (Maps.swift:103) | Map cloning/extending only | Right-click (1502) |
| Grindstone, `grindstone` | "Repair & Disenchant" (Workstations.swift:168) | Removing enchantments | Right-click (1481) |
| Anvil (+ chipped/damaged), `anvil` | "Repair & Name": combine items, rename, merge enchants (MenuMagic.swift:127) | Renaming; XP-cost repair | Right-click (1521) |
| Brewing Stand, `brewing_stand` | Potions (Potions.swift:98 table) | Every potion | Right-click (1474) |
| Enchanting Table, `enchanting_table` | Enchant with lapis + XP | Enchanted gear (non-book) | Right-click (1478) |
| Crafter, `crafter` | Automated 3x3 crafter, same `Recipes.match` (Crafter.swift:37-50) | Nothing; needs circuit power | Right-click (1453) |
| Composter, `composter` | Compost scraps -> bone meal (Workblocks.swift) | Bone meal from scraps | Right-click (1432 area, `useComposter`) |
| Ship Helm, `ship_helm` (Ships.swift / ShipBlocks.swift:38) | Assembles a connected block structure into a ship/vehicle and pilots it | Not a crafting station (block recipe is `ShipBlocks.swift:226`) | Right-click (ship code) |
| Chests/Barrel/Shell boxes/Beacon/Lectern | Storage or effect, not crafting | n/a | n/a |

Steelhold fortresses (MilitaryBase.swift) place steel blocks and chests but define no craft bench; its loot tables hold guns, ammo and components (Structures.swift:385-420, e.g. `ash_armory`).

## Surprises vs. what a classic-game player expects
1. Steel is blast-furnace-only: `steel_blend` is the single item hard-gated to one furnace type (BlockEntities.swift:157). A Furnace silently will not accept it.
2. Guns are gated by looted parts, not stations: the code comment says "guns need components looted at Capital citadels" (Guns.swift:86). Ammo (rifle rounds, shells, heavy rounds, rocket ammo, arc cells) is plainly craftable at the table (Guns.swift:87-91). A sidearm (2 steel + Firing Mechanism, 3 items) can be assembled in the 2x2 inventory grid; the rest are 5-8 items and need the table.
3. Titanium is the renamed diamond tier: ore drops Raw Titanium (Loot.swift:152), smelting yields save-key `diamond`; nothing needs a special bench for titanium gear.
4. Smithing Table covers only Duskium upgrades and armor trims; steel/copper gear is a plain table recipe, and there is no armory/forge/gun bench. Also no tiered workbenches: no such station found.
5. The Stonecutter, Loom, Cartography Table, Grindstone and Smoker are conveniences; no crafting-table recipe is blocked behind them (Stonecutter outputs are derived from table recipes, Workstations.swift:88). Quest: no Quest-only crafting UI found; it reuses the same menus (quest/src/app/QuestControls.swift:452 only lists them as interactables).
