# Area 5: Combat, Guns, Mobs, AI, Bosses & Raids

Reviewed against `origin/claude/quest-port` (`cb7295fb`, Ledger 385).
Files audited: `Sources/Guns.swift`, `Sources/Ballistics.swift`, `Sources/GunActions.swift`, `Sources/GunParts.swift`, `Sources/GunCrew.swift`, `Sources/GunStationPlay.swift`, `Sources/Soldiers.swift`, `Sources/Mob.swift`, `Sources/MobAI.swift`, `Sources/MobSave.swift`, `Sources/MobsG.swift`, `Sources/Spawning.swift`, `Sources/Projectile.swift`, `Sources/Explosion.swift`, `Sources/Raid.swift`, `Sources/Reckoning.swift`, `Sources/Companions.swift`, `Sources/AshFinal.swift`, `Sources/Hollow.swift`, `Sources/DragonRespawn.swift`.

Skipped (already covered in prior reviews or fixed in `bug-ledger.md`): shotgun pellet volley capping (`Ballistics.swift:491`, Ledger 245), Sturmbrecher burst tuning (`Soldiers.swift:961`, Ledger 246), non-finite mob pruning in `MobManager.update` (`Mob.swift:3027`), deck-gun melee glancing (`Mob.swift:1734`), and VR reload/aiming controls (`02-vr-controls-ui-menus.md`).

---

## Ranked Findings

### 1. [Critical] Blitzlanze Arc Gun and direct rockets/shells instantly one-shot the Ashguard Marshal, Ashguard Chancellor (final boss), and every Citadel Commandant

- **Location:** `Sources/Ballistics.swift:387-390`, `584-615`, `692-697`; `Sources/Soldiers.swift:177-187`
- **Problem:**
  `Soldier.rank(_ k:)` (`Soldiers.swift:183`) returns `4` for `.ashMarshal` and `.ashChancellor`, and Citadel Tower Commandants (`m.commandant == true`) use `.soldierOfficer` / `.soldierIronclad`. While regular bullet hits in `impactMob` (`Ballistics.swift:424`) explicitly exclude bosses (`if m.kind != .ashMarshal && m.kind != .ashChancellor && !m.commandant`), **three other damage paths omit that guard**:
  1. **Arc Gun one-shots bosses (`Ballistics.swift:584,591`):**
     ```swift
     let infantry = Soldier.rank(m.kind) != nil && !m.kind.ashVehicle && m.kind != .deckGun
     ...
     if infantry && fromPlayer && shooter == nil && m.troop != Int8(TroopClass.hannibal.rawValue) { dmg = max(dmg, Float(m.health) + 1) }
     ```
     A single Blitzlanze shot instantly kills the Ashguard Marshal, the **Ashguard Chancellor** (the endgame final boss of the Ash Vault, completely skipping his guard-call and bunker-quake phases in `AshFinal.swift:386-389`), and every Citadel Commandant.
  2. **Arc Gun chain-lightning inherits the boss-inflated `dmg` (`Ballistics.swift:613`):**
     Because `dmg` was raised in-place to `Float(m.health) + 1` before the jump loop, `c.hit(from: from, damage: Int(dmg * 0.6), ...)` arcs 60% of the primary target's entire HP pool onto two nearby enemies — vaporizing nearby Hannibal troopers and bodyguards as collateral damage.
  3. **Direct rockets and shells one-shot bosses (`Ballistics.swift:387-390`, `692-697`):**
     ```swift
     if (s.kind == .rocket && Soldier.rank(m.kind) != nil && m.kind != .deckGun || s.kind == .shell && !m.kind.shellProof), m.health > 0 {
         ...
         m.hit(from: at - dir * 2, damage: m.health + 1000, knockback: 1.2)
     }
     ```
     `MobKind.shellProof` (`:692-697`) lists `.enderDragon`, `.wither`, `.warden`, `.elderGuardian`, `.deckGun`, and `ashVehicle`, **but omits `.ashMarshal`, `.ashChancellor`, and `m.commandant`**. A single direct Himmelsturm/Faustrohr rocket or tank shell deals `m.health + 1000`, instantly killing the Marshal, Chancellor, or Commandant.
- **Concrete suggested change:**
  - Define a shared helper `var isSoldierBoss: Bool { kind == .ashMarshal || kind == .ashChancellor || commandant }` on `Mob` (and add `.ashMarshal, .ashChancellor` to `MobKind.shellProof`).
  - Exclude `m.isSoldierBoss` in `Ballistics.swift:387` (direct rocket/shell instant-kill) and `Ballistics.swift:591` (Arc Gun one-shot).
  - Save `let jumpDmg = damage * (boss ? 0.35 : 1) * 0.6` (using the gun's base beam damage, not the one-shot-inflated `dmg`) for the chain-lightning loop at `Ballistics.swift:613`.
- **Why it matters (players / store):** The Ashguard Marshal and Chancellor are the climactic endgame boss fights of the Ash Vault campaign; having either die in one shot to standard late-game player weapons (Arc Gun or rocket launcher) ruins the finale and skips scripted phases.
- **Risk:** Very low. Scoped exclusively to the three boss flags and Arc Gun jump damage.

---

### 2. [Critical] `MobSave` encoder/decoder mismatch (`SaveIO.writeJSON` vs plain `JSONDecoder`) quarantines and wipes ALL saved villagers, horses, pets, and companions on any non-finite float; sync save also traps on `NaN` positions

- **Location:** `Sources/MobSave.swift:212-235`; `Sources/Save.swift:459-472`
- **Problem:**
  1. On background autosave (`MobSave.swift:221`), `mobs.json` is written via `SaveIO.writeJSON(all, to: url)`, which uses `SaveIO.encoder()` (`Save.swift:459-463`, `.nonConformingFloatEncodingStrategy = .convertToString(..., nan: "nan")`).
  2. On **load** (`MobSave.swift:231`), `MobManager.load` uses a **plain `JSONDecoder()`** instead of `SaveIO.decoder()`:
     ```swift
     guard let all = try? JSONDecoder().decode([String: [MobRecord]].self, from: d) else {
         SaveIO.quarantine(s.dir.appendingPathComponent("mobs.json"), what: "animals and people file")
         return
     }
     ```
     If even a single saved mob had a non-finite float (`yaw`, `bond`, `power`, `shield`, `pos`, etc.) written as `"nan"`/`"inf"` by `SaveIO.writeJSON`, plain `JSONDecoder()` fails and **quarantines `mobs.json` — wiping every villager, tamed horse, wolf, cat, companion, and persistent mob in the dimension**!
  3. On **synchronous save** (`MobSave.swift:222`, quit / exit-to-menu), it falls back to raw `JSONEncoder()` + `try? d.write(to: url, options: .atomic)` — silently failing to write `mobs.json` on any non-finite float and bypassing `SaveIO.storeJSON` (`fsync`, `.bak` backup, disk-full reporting).
  4. `MobManager.save` (`MobSave.swift:217`) computes `Int(floor(m.pos.x))` and `Int(floor(m.pos.z))` without checking `m.pos.x.isFinite && m.pos.z.isFinite`. If a mob's position goes `NaN` before the next `MobManager.update` prune (`Mob.swift:3027`), saving immediately traps and crashes the app.
- **Concrete suggested change:**
  - In `MobManager.save` (`MobSave.swift:216-222`): skip any mob with non-finite `pos` (or clamp/sanitize `yaw` and `extra` floats), and call `SaveIO.storeJSON(all, to: url)` for synchronous saves instead of raw `JSONEncoder()` + `try? d.write`.
  - In `MobManager.load` (`MobSave.swift:231`): decode with `SaveIO.decoder()` (with `.bak` fallback via `SaveIO.loadJSON` before calling `SaveIO.quarantine`), and validate finite `pos`/`yaw` in `Mob.from(_:)`.
- **Why it matters (players / store):** Losing every townsperson, bonded horse, companion, and pet across an entire world on reload (or crashing on exit-save) is a catastrophic save-integrity failure.
- **Risk:** Very low. `SaveIO.decoder()` is a strict superset of plain `JSONDecoder()` and fully backward-compatible with existing `mobs.json` files.

---

### 3. [High] Rocket-armed soldiers fighting rival factions overwrite `aimAt` with `g.player.pos` and fire rockets straight at the player; faction battles also lead targets with `g.player.vel`

- **Location:** `Sources/Soldiers.swift:536`, `892-902`, `1145-1175`
- **Problem:**
  `soldierFire` (`Soldiers.swift:833-942`) is called both when shooting at the player (`:711`, `:572`, `:735`) and when shooting at a **rival faction mob or vessel** (`b.foe` at `:536`). Yet lines `899-901` unconditionally use the player's velocity and position:
  ```swift
  aimAt += g.player.vel * flight
  aimAt.y += 0.5 * 1.5 * flight * flight
  if Guns.isLauncher(b.gun) { aimAt = g.player.pos + V3(0, 0.3, 0) + g.player.vel * flight * 0.6 }
  ```
  - Whenever any rocket-armed soldier (Capital Bulwark, Greywall heavy, Ashguard Faustrohr — **including an allied faction soldier!**) engages a rival faction, line `901` throws away `target` (`foe.point`) and fires its rocket directly at `g.player.pos`.
  - For bullet weapons fighting rival factions (`:899`), leading with `g.player.vel` instead of `foe.vel` drags every soldier's shots off target whenever the player is riding, flying, or sprinting past a faction skirmish.
  - The same velocity bug occurs in `updateDeckGun` (`Soldiers.swift:1145-1175`): when a deck gun locks onto an enemy faction ship (`foe`), line `1175` leads `aimP` with `g.player.vel * (flat0 / v) * 0.5`, so a player flying past in a dropship (83 m/s) or frigate (280 m/s) pulls every nearby base turret's aim 50–100+ blocks off its enemy warship target.
- **Concrete suggested change:**
  - Pass `targetVel: V3` and `atPlayer: Bool` (or `foe: CapTarget?`) into `soldierFire` (using `g.player.vel` when `atPlayer`, `foe.vel` otherwise), and compute launcher aim relative to `target` (`target - V3(0, 1.0, 0) + targetVel * flight * 0.6`, or `g.player.pos + V3(0, 0.3, 0)` only when `atPlayer`).
  - In `updateDeckGun` (`:1145-1175`), store the target's velocity alongside `b.lastSeen` (or use `onPlayer ? g.player.vel : foeVel`) so turrets lead enemy vessels with the vessel's own velocity.
- **Why it matters (players / store):** Getting abruptly blasted by an allied soldier's rocket while watching two factions fight feels broken and unfair, and faction-vs-faction set-piece battles miss wildly whenever the player is moving fast nearby.
- **Risk:** Low. Localized parameter addition to `soldierFire` and `updateDeckGun`.

---

### 4. [High] Village raids instantly fail ("Raid - Defeat") when the player steps out of village load range or enters a portal, and Evoker-summoned Vexes join `r.raiders` and stall waves

- **Location:** `Sources/Raid.swift:156-205`; `Sources/MobsG.swift:325-330`
- **Problem:**
  1. **False raid defeat on chunk unload / dimension change (`Raid.swift:180-198`):**
     `raidTick` checks `dim.dim == .overworld` when *starting* a raid (`:162`), but **not** while updating an active raid (`:180-228`), and `villagersLeft` (`:190`) only scans currently loaded `mobs.mobs`:
     ```swift
     let villagersLeft = mobs.mobs.contains { $0.kind == .villager && simd_length($0.pos - r.center) < 64 }
     ...
     case 1:
         if !villagersLeft { r.state = 3; r.timer = 30; onToast?("Raid - Defeat"); return }
     ```
     Walking ~150 blocks away to grab gear, respawning at a distant bed, or stepping into the Nether/Deep/Hollow stashes all village villagers into `mobs.stored` (`Mob.swift:3029`). On the very next second, `villagersLeft` becomes `false` and **immediately fails the raid ("Raid - Defeat")** even though every villager is alive and safe.
     In addition, `r.rejoin` (`:202`) ticks down while the player is far away or in another dimension, so raiders can't reload in time before `r.rejoin <= 0`.
  2. **Wall-clipping Vexes counted as required raiders (`MobsG.swift:329`, `Raid.swift:185`):**
     `aiEvoker` sets `v.raider = raider` on every summoned Vex (`Hexling`). Because `Raid.swift:185` sweeps all `m.raider` mobs into `r.raiders`, Vexes (which fly through solid walls at `MobsG.swift:300` and live up to 119 s) inflate the raid bar and stall waves while hidden underground or inside solid structures.
- **Concrete suggested change:**
  - At `Raid.swift:180`, pause raid progression (`guard dim.dim == .overworld, world.isLoaded(Int(floor(r.center.x)), Int(floor(r.center.z))), simd_length(coop.nearestPlayerPos(r.center, self) - r.center) < 96 else { return }`) — or check `mobs.stored` before declaring defeat — so raids neither falsely fail nor tick `r.rejoin` while the village is unloaded.
  - In `MobsG.swift:329`, do not set `v.raider = true` on summoned `.vex` mobs (or filter `m.kind != .vex` at `Raid.swift:185`), matching standard raid rules.
- **Why it matters (players / store):** Dying once or briefly leaving a village during a multi-wave raid causes an inexplicable instant defeat, and Vexes clipping into hills make late raid waves feel softlocked.
- **Risk:** Very low. Only guards raid tick against unloaded village state and excludes summoned Vexes from raid membership.

---

### 5. [Medium] Companions teleport into solid walls, lava, or mid-air whenever the player flies, parachutes, or climbs 24+ blocks

- **Location:** `Sources/Companions.swift:143-148`
- **Problem:**
  When a hired companion falls >48 blocks behind or >24 blocks vertically from the player, `companionAI` teleports them blindly to a fixed 2-block ring around `player.pos`:
  ```swift
  if !aboard && (dp > Companions.arrive || abs(pp.y - pos.y) > 24) {
      let a = Float(ObjectIdentifier(self).hashValue & 7) * 0.8
      pos = pp + V3(cosf(a) * 2, 0.2, sinf(a) * 2)
      vel = .zero
      return 0
  }
  ```
  There is no check that the player is grounded, no collision check (`collides`), no solid-floor check, and no lava check:
  - While the player uses a jetpack, parachutes, flies in Creative, or pilots a Sky Skiff / plane without gunner seats, companions repeatedly teleport into thin air next to the player and plummet every 24 blocks in an infinite sky-drop loop.
  - When the player stands next to a cave wall, building wall, cliff, or lava pool, companions teleport straight into solid rock (stuck) or into lava (burning to death).
- **Concrete suggested change:**
  - Only teleport companions when the player is on solid ground (`g.player.onGround && !g.player.flying && g.world.ships.pilot == nil`) — or find the nearest valid standing spot (solid non-liquid floor, 2 air blocks above, `!collides`) in a ring of radius 2–5 around `pp` (falling back to `pp` itself if grounded, and skipping the teleport altogether if the player is airborne over open sky or lava).
- **Why it matters (players / store):** Players spend money, troop armor, and rare guns outfitting hired companions; watching them endlessly rain from the sky or teleport into lava/stone walls breaks immersion and destroys player gear.
- **Risk:** Very low. Standard safe-teleport probe already used elsewhere (`Turrets.exitSpot`, `dismountSpot`).

---

### 6. [Medium] Loyalty tridents thrown into the End void (below `y = -64`) are permanently destroyed instead of returning, and VR hotbar-swapping bypasses `GunActions` manual actions

- **Location:** `Sources/Projectile.swift:174-200`, `294`; `Sources/Ballistics.swift:774-779`; `Sources/GunActions.swift:23`, `42-56`
- **Problem:**
  1. **Loyalty trident void loss (`Projectile.swift:294`):**
     ```swift
     if a.pos.y < -64 { a.dead = true }
     ```
     A trident with the **Loyalty** enchantment thrown off an End island drops below `y = -64` and is deleted forever instead of setting `a.returning = true`. Also, because line `174` skips any arrow outside `w.activeHere(a.pos)` even when `a.returning == true`, flying or pearling away while a Loyalty trident is mid-return freezes it in mid-air indefinitely (and it is lost on reload since `ProjectileManager` is not saved).
  2. **VR manual-action bypass via hotbar switch (`Ballistics.swift:774-779`, `GunActions.swift:23,42-45`):**
     `GunActions.cocked` is a single static `Bool` rather than per-weapon state. After firing a Kessel bolt-action, Brecher pump shotgun, or Sechser revolver — or after inserting a magazine into a charging-handle rifle (`cocked = false`) — switching to another hotbar slot and switching back triggers `GunActions.drawn(gi, rounds: held.tag)`, which resets `cocked = true` for every non-pistol weapon and silently skips the manual bolt/pump/hammer/charging-handle step in VR swing mode.
- **Concrete suggested change:**
  - In `Projectile.swift:294`: if `let t = a.trident, Enchant.level(.loyalty, t) > 0`, set `a.returning = true; a.stuck = false` instead of `a.dead = true` when `a.pos.y < -64`; and exempt `a.returning` tridents from the `!w.activeHere(a.pos)` early `continue` at line `174`.
  - Track per-slot (or per-`ItemStack` flag bit) uncocked state for `GunActions` instead of resetting `cocked = true` unconditionally in `GunActions.drawn`.
- **Why it matters (players / store):** Losing a hard-earned enchanted Loyalty trident in the Hollow/End violates player expectations from the genre, and accidental hotbar toggles make VR weapon-handling mechanics inconsistent.
- **Risk:** Very low. Both fixes are isolated and self-contained.
