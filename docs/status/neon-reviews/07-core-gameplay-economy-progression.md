# Area 7 Review — Core Survival, Crafting, Towns, Economy & Sparkstone

**Base reviewed:** `origin/claude/quest-port` at `cb7295fb` (Ledger 385).
**Files inspected:** `Sources/Game.swift`, `Sources/TownLaw.swift`, `Sources/TownServices.swift`, `Sources/TownConquest.swift`, `Sources/TownJail.swift`, `Sources/Shops.swift`, `Sources/Wallet.swift`, `Sources/Property.swift`, `Sources/Quartermaster.swift`, `Sources/MailOrder.swift`, `Sources/Repairs.swift`, `Sources/Upgrades.swift`, `Sources/WeaponPrinter.swift`, `Sources/Workstations.swift`, `Sources/Menu.swift`, `Sources/MenuMagic.swift`, `Sources/CraftingBook.swift`, `Sources/Crafter.swift`, `Sources/Enchant.swift`, `Sources/Potions.swift`, `Sources/GamePotions.swift`, `Sources/TechSalvage.swift`, `Sources/BlockEntities.swift`, `Sources/GameCircuit.swift`, `Sources/Circuit.swift`, `Sources/MinecartVariants.swift`, `Sources/Farming.swift`.

Ranked by player impact and Meta Horizon Store VRC compliance. Skips issues already fixed in `docs/status/bug-ledger.md` or covered in prior reviews.

---

## 1. [Critical] Buying a Town House Deed (`$80`) makes your own house *more* hostile than an unowned house: `TownLaw.isTownOwned` omits `Property.owns(p)` while `TownLaw.isTownSpot` checks it

- **Where:** `Sources/TownLaw.swift:155-175, 198-203, 308-328, 378-394`; `Sources/Property.swift:4-7, 39-69`
- **What happens:**
  - `Property.swift:5-7` promises that using a `$80` Town House Deed inside an unoccupied town building makes its blocks and containers yours so *"they stop being town property (`TownLaw.isTownOwned`), so you can rebuild it and keep your things in its chests."*
  - However, `if Property.owns(p) { return false }` was added **only** to `TownLaw.isTownSpot` (`TownLaw.swift:157`), and **omitted from `TownLaw.isTownOwned`** (`TownLaw.swift:165-175`).
  - Both vandalism (`TownLaw.broke` at `:318`) and chest theft (`TownLaw.opened` at `:379`) check `isTownOwned(g, p)`, NOT `isTownSpot`.
  - Worse, `TownLaw.placed` (`TownLaw.swift:199`) guards on `guard isTownSpot(g, p) else { return }`. Because `isTownSpot` returns `false` inside your purchased house, **every block and chest you place yourself inside your own `$80` house is skipped and never recorded in `placedSet`!**
  - Result: breaking any wall/floor block (even ones you built yourself) or withdrawing your own gear from a chest you placed inside your own bought house, while any townsperson walks past a window, triggers town theft/vandalism heat, reputation loss, bounty, and a sheriff gunfight/arrest.
- **Concrete suggested change:**
  - Add `if Property.owns(p) { return false }` at the top of `TownLaw.isTownOwned(_:_:)` (`Sources/TownLaw.swift:166`, right after `if let f = forceTown { return f }`).
- **Why it matters:** Buying a house in town is a core `$80` economy milestone (D28). Having your own purchased home turn the sheriff on you for breaking or opening things you placed yourself is an immediately infuriating progression break.
- **Risk:** Minimal. One-line guard matching the documented contract in `Property.swift:6`.

---

## 2. [Critical] Quartermaster's "Fortify Homestead" (`$300`) offer is impossible to buy in normal gameplay

- **Where:** `Sources/Quartermaster.swift:17, 79-96`; `Sources/Property.swift:15, 76-80`; `Sources/Shops.swift:270, 570, 750`
- **What happens:**
  - `QuartermasterMenu` is only opened through a **town gunsmith's counter** (`ShopService.quartermaster`, `Shops.swift:270, 750`), which requires standing within 10 blocks of the gunsmith inside a town (`Shops.swift:570`).
  - `Property.homestead` (`Property.swift:15, 77-80`) refuses to stake a homestead within `wildFromTown = 120` blocks of any town (`"Too close to town"`).
  - Yet `Quartermaster.fortify(_:)` (`Quartermaster.swift:80-85`) insists the player is currently standing inside a homestead bounding box:
    ```swift
    let p = IVec3(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.y)), Int(floor(g.player.pos.z)))
    guard let b = (TownLaw.state.property ?? []).first(where: { $0.count == 6 && $0[3] - $0[0] == 24
            && p.x >= $0[0] && p.x <= $0[3] && p.z >= $0[2] && p.z <= $0[5] }) else {
        return ("Stand on your homestead to order its walls.", false)
    }
    ```
  - Because the player is always inside a town (at least 120 blocks from any homestead) whenever they open the Quartermaster menu, `fortify` **always** fails with `"Stand on your homestead to order its walls."` — making the `$300` late-game money sink completely unreachable.
- **Concrete suggested change:**
  1. In `Quartermaster.fortify(_:)` (`Sources/Quartermaster.swift:81-95`), locate the player's nearest (or most recent) unfortified homestead in `TownLaw.state.property` (`$0.count == 6 && $0[3] - $0[0] == 24`) without requiring `p` to be inside it. If the player has no homestead yet, return `"Stake a homestead with a Homestead Deed first."`
  2. Because the homestead is ≥120 blocks away and its chunks may be unloaded (`g.world.isLoaded(x, z)` at `:90` would silently skip unloaded wall segments!), persist a `pendingFortify: [[Int]]?` list on `TownLaw.Saved` (or synchronously load the 2×2 homestead chunks around `(cx, cz)` before building the wall, or stamp the wall on arrival in `TownLaw.tick` once all 4 corners `(cx ± r, cz ± r)` are loaded).
- **Why it matters:** A prominently listed `$300` spine progression reward (`Quartermaster.offers[1]`) is literally unpurchasable in survival gameplay.
- **Risk:** Low.

---

## 3. [High] Mail-Order Catalog delivers a blank, unenchanted `enchanted_book` (`ench == 0`) for `$60.00` and still sells retired `experience_bottle` crates (`$24.00`)

- **Where:** `Sources/MailOrder.swift:19-20, 44-50`; `Sources/TechSalvage.swift:10-12`; `Sources/Structures.swift:988-989, 1126-1128`
- **What happens:**
  1. `MailOrder.catalog` (`MailOrder.swift:20`) sells `"enchanted_book"` for `$60.00` (`6000` cents, `"A mystery volume from the coast"`). When the player collects the parcel the next day, `MailOrder.collect(_:)` (`MailOrder.swift:48`) creates `ItemStack(Items.id(o[0]), Int(o[1]) ?? 1)` without assigning any enchantment (`ench == 0`). Compare `Loot.stack` (`Structures.swift:988-989`), which populates `st.ench = Enchant.pack(Enchant.randomly(Items.id("book")))`. The player pays `$60.00` and waits a full in-game day for a blank, unusable book that adds nothing at an anvil and gives nothing at a grindstone.
  2. `MailOrder.catalog` (`MailOrder.swift:19`) also still sells `"experience_bottle"` × 4 for `$24.00`, even though `Game.xpOn` is `false` (`TechSalvage.swift:11`, P508) and experience bottles were removed from all loot chests (`Structures.swift:1126-1128`) in favor of `TechSalvage`. Players spending `$24.00` on `"Bottled know-how"` get zero XP levels when throwing them.
- **Concrete suggested change:**
  1. In `MailOrder.collect(_:)` (`Sources/MailOrder.swift:47-50`), when `o[0] == "enchanted_book"`, roll an enchantment onto the stack (`st.ench = Enchant.pack(Enchant.randomly(Items.id("book")))`, matching `Loot.stack`).
  2. In `MailOrder.catalog` (`Sources/MailOrder.swift:19`), gate `"experience_bottle"` behind `Game.xpOn` (or replace it with a useful non-XP item / hide it when `!Game.xpOn`).
- **Why it matters:** Both are expensive town-economy purchases (`$60` and `$24`) that silently waste the player's money on dead/broken items.
- **Risk:** Minimal.

---

## 4. [High] Dispenser scooping fluids/powder snow with stacked empty buckets deletes up to 15 buckets per pulse, and `Game.useBucket()` erases fluid sources 5–12 blocks below even when rejecting the draw

- **Where:** `Sources/GameCircuit.swift:331-335`; `Sources/Game.swift:2915-2929` (`useBucket`, `cb7295fb` lines)
- **What happens:**
  1. Empty `bucket` items stack to `16` (`Items.swift:215`). In `Game.dispense` (`GameCircuit.swift:331-335`), scooping `powder_snow`, `WATER`, `LAVA`, or `FUEL` overwrites the slot directly:
     ```swift
     case "bucket" where Blocks.key(fb) == "powder_snow":
         world.setBlock(front.x, front.y, front.z, AIR); c[slot] = ItemStack(Items.id("powder_snow_bucket"), 1)
     case "bucket":
         if fb == WATER || fb == LAVA || fb == FUEL { world.setBlock(front.x, front.y, front.z, AIR); c[slot] = ItemStack(Items.id(...), 1) }
     ```
     If the slot holds a stack of 2–16 empty buckets, `c[slot] = ...` **silently deletes the remaining 1–15 buckets** (45 iron ingots lost in one pulse!). Compare `glass_bottle` right above it (`GameCircuit.swift:234-240`), which properly calls `take()`, `c.add(filled)`, and spawns overflow.
  2. In `Game.useBucket()` (`Sources/Game.swift:2915-2929` on `origin/claude/quest-port`), looking straight down (`dir.y < -0.8`, well-rope reach `12`) deletes the fluid source block **before** checking whether it is actually inside a well shaft:
     ```swift
     world.setBlock(f.x, f.y, f.z, Blocks.isWaterlogged(cur) ? Blocks.dry[Int(cur)] : AIR)      // drains a waterlogged block
     // Past arm's length it was drawn up a shaft: only a narrow one (walls on two sides over the water) counts.
     let drawn = t > 5 && RecordedNov15.shaft(world, f)
     if t > 5 && !drawn { return false }
     ```
     Standing on a bridge, dock, cliff, or ship deck 6–12 blocks above open water, lava, or fuel and clicking Use with an empty bucket returns `false` (player gets no filled bucket) **while permanently deleting the fluid source block below**.
- **Concrete suggested change:**
  1. In `GameCircuit.swift:331-335`, decrement one empty bucket with `take()` and insert the filled bucket via `let rest = c.add(ItemStack(filledID, 1)); if !rest.isEmpty { drops.spawn(rest, at: from, vel: fd * 4 + V3(0, 1, 0), delay: 0.5) }`, mirroring `glass_bottle` (`GameCircuit.swift:234-240`).
  2. In `Game.useBucket()` (`Sources/Game.swift:2918-2921`), move `let drawn = t > 5 && RecordedNov15.shaft(world, f); if t > 5 && !drawn { return false }` **above** `world.setBlock(f.x, f.y, f.z, ...)`.
- **Why it matters:** Players building Sparkstone water/lava/fuel dispensers lose stacks of iron buckets, and players using buckets near docks/ships/bridges accidentally grief water/lava sources without getting a bucketful.
- **Risk:** Low. Localized 5-line fixes.

---

## 5. [High] Automated brewing stand fueling broken since P508 switched fuel to Brimsalt, and saving mid-brew cancels the brew and wastes fuel

- **Where:** `Sources/GameCircuit.swift:398-413`; `Sources/MenuMagic.swift:24, 55`; `Sources/Potions.swift:190-219`; `Sources/BlockEntities.swift:69, 86, 110`
- **What happens:**
  1. P508 switched brewing stand fuel from `"blaze_powder"` to `HellWorks.brimsalt` (`"brimsalt"`) in both `BlockEntity.tickBrewing()` (`Potions.swift:192`) and `BrewingMenu` (`MenuMagic.swift:24`).
  2. However, `Game.containerInsert` (`GameCircuit.swift:404`) still checks `"blaze_powder"`:
     ```swift
     else if Items.key(one.item) == "blaze_powder" && dir != 1 { slot = 4 }
     ```
     (And `BrewingMenu.quickMoveTargets` at `MenuMagic.swift:55` still checks `"blaze_powder"` instead of `HellWorks.brimsalt`.)
     As a result, hoppers and droppers feeding a brewing stand from the side **reject Brimsalt completely** (breaking automated fuel supply) while **pushing Blaze Powder into the fuel slot** where `tickBrewing()` never consumes it — jamming slot 4 and breaking automated Strength potion brewing.
  3. In `BlockEntity` (`BlockEntities.swift:69, 86, 110`), `fuel` and `brewTime` are saved to disk, but **`brewIngredient` is omitted from `CodingKeys`, `init(from:)`, and `encode(to:)`**. When a world is saved mid-brew (`brewTime > 0`) and reloaded, `brewIngredient` initializes to `0`; on the first tick after load, `tickBrewing()` (`Potions.swift:199`) sees `ing.item != brewIngredient`, cancels the in-progress brew (`brewTime = 0`), and immediately spends a second fuel charge to restart the 20-second brew.
- **Concrete suggested change:**
  1. In `GameCircuit.swift:404`, change `"blaze_powder"` to `HellWorks.brimsalt` (and update `MenuMagic.swift:55` to `HellWorks.brimsalt` too, so Blaze Powder shift-clicks straight into the ingredient slot).
  2. In `BlockEntity.tickBrewing()` (`Potions.swift:198-199`), either persist `brewIngredient` (by item key in `BlockEntity` `CodingKeys`) or, when `brewTime > 0 && brewIngredient == 0 && can`, re-bind `brewIngredient = ing.item` on the first tick after load instead of aborting the brew.
- **Why it matters:** Automated Sparkstone brewing stands cannot be fueled by hoppers, Blaze Powder jams the fuel slot, and saving mid-brew wastes Brimsalt fuel.
- **Risk:** Low.

---

## 6. [Medium] Dying while a workstation/inventory screen is open bypasses death-chest stashing, and dying in jail triggers "Jailbreak!" if your bed is within 64 blocks

- **Where:** `Sources/Game.swift:1105-1119, 3446-3466` (`cb7295fb` lines); `Sources/TownJail.swift:276-287`
- **What happens:**
  1. In `Game.die` (`Game.swift:3446-3466`), `inventory.armor`, `inventory.main`, and `inventory.offhand` are emptied into `lost` / `deathChests` **before** line `3466` runs `if menu != nil { closeMenu() }`. `closeMenu()` (`Game.swift:1112-1117`) calls `m.onClose()` (returning open crafting-table, anvil, smithing, stonecutter, and grindstone slot contents to `inventory.add`) and returns `carried` (the cursor stack) to `inventory.add`. Any items in an open workstation or on the cursor at the moment of death are placed back into the player's inventory *after* death stashing — letting players keep items across death (or losing them out of the expected death chest if they die again).
  2. In `Jail.tick` (`TownJail.swift:276-286`), if a player dies while serving a jail term and respawns at their bed inside the same town (within `64` blocks of the cell, e.g., an owned town house or saloon room), `simd_length(g.player.pos - c) > 64` (`:278`) is `false`, `!inCell(g.player.pos, t)` (`:280`) is `true`, and `jailbreak(g)` fires immediately — docking `-10` honour, adding `+$10` bounty, turning the town hostile, and keeping all confiscated weapons impounded.
- **Concrete suggested change:**
  1. In `Game.die` (`Sources/Game.swift:3446`), call `if menu != nil { closeMenu() }` **before** collecting `lost` from `inventory`, so cursor and open workstation items are cleanly stashed in the player's death chest with the rest of their gear.
  2. In `Game.die` (or `Game.respawn`), if `Jail.term != nil`, call `Jail.release(self)` on death/respawn (or mark `term` as ended by death) so respawning at a nearby bed in the same town never triggers a false `jailbreak(g)`.
- **Why it matters:** Keeps survival death-stashing consistent when killed while crafting/sorting in VR, and prevents a punitive false jailbreak loop when dying in a town cell.
- **Risk:** Low.
