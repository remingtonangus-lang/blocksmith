import Foundation
import simd

// The Deep's progression gap pass (docs/status/the-deep-expansion.md "Gap pass", PR 3), run with DeepExpansionTests:
//   keeps      three layouts across keeps, each with its Ember Gate frame, its Warden and the rest of the garrison
//   gates      the Castellan falls -> the gate wakes (advancement), stepping in carries you up, the Gate Shard back down
//              to the gate, saves; a Deep Lift carries you up and the way-up marker finds it
//   balance    a full-gear run (Duskium armour, the best guns): time for the player to kill each Ashguard unit and
//              each to kill the player, a Capital rifleman and the hell band's monsters for scale (D4b, DE1)
//   moods etc  the vault's own bed and music, the seal-break moment, the journals, the new advancements
enum DeepGapTests {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        keeps(g, check)
        gates(g, check)
        bits(g, check)
        balance(g, check)
        print(String(format: "deep gap: checks took %.1f s", CFAbsoluteTimeGetCurrent() - t0))
    }

    // Three layouts over the keeps near the origin on a few seeds; each keep has a gate frame (empty), a Warden and
    // its other guards.
    static func keeps(_ g: Game, _ check: (Bool, String) -> Void) {
        var layouts: [Int: Int] = [:]
        var bad: [String] = []
        var n = 0
        for seed in [UInt64(12345), 777, 424242, 99, 31337] {
            let dg = DeepGen(seed: seed)
            guard let sc = dg.structures else { continue }
            var seen = Set<IVec3>()
            for (x, z) in [(0, 0), (900, 0), (0, 900), (-900, -900)] {
                guard let k = sc.nearest("brimstone_keep", x: x, z: z, maxRegions: 2, accept: { !seen.contains($0.anchor) }) else { continue }
                seen.insert(k.anchor)
                n += 1
                // The keep's chunks as generated (terrain + structures), and the structure mobs inside its walls.
                let c = DeepGates.centre(k)
                var chunks: [Int64: [BlockID]] = [:]
                var mobs: [String] = []
                for cz in floorDiv(k.min.z, CS)...floorDiv(k.max.z, CS) { for cx in floorDiv(k.min.x, CS)...floorDiv(k.max.x, CS)
                    where abs(cx * CS + 8 - c.ox) < 40 && abs(cz * CS + 8 - c.oz) < 40 {
                    var b = dg.generate(cx: cx, cz: cz)
                    let (_, ms) = sc.place(into: &b, cx: cx, cz: cz)
                    chunks[StructureCache.key(cx, cz)] = b
                    mobs += ms.filter { abs($0.1.x - Float(c.ox)) < 26 && abs($0.1.z - Float(c.oz)) < 26 }.map { $0.0 }
                } }
                func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
                    guard let b = chunks[StructureCache.key(floorDiv(x, CS), floorDiv(z, CS))] else { return AIR }
                    return b[Chunk.index(x - floorDiv(x, CS) * CS, y, z - floorDiv(z, CS) * CS)]
                }
                let v = (k.plan as? NSNumber)?.intValue ?? 0
                layouts[v, default: 0] += 1
                let frame = Blocks.id(DeepGates.frameKey)
                let frameOK = get(c.ox - 2, c.f + 4, c.oz - DeepGates.gateBack) == frame && get(c.ox + 2, c.f + 4, c.oz - DeepGates.gateBack) == frame
                    && DeepGates.veil(k).allSatisfy { get($0.x, $0.y, $0.z) == AIR }
                let wardens = mobs.filter { $0.contains(":warden") }.count
                let roles = Set(mobs.map { $0.split(separator: "@").first.map(String.init) ?? $0 })
                if !frameOK || wardens != 1 || roles.count < 5 { bad.append("seed \(seed) keep \(k.anchor.x),\(k.anchor.z) \(BrimstoneKeep.layoutNames[v]): frame \(frameOK) wardens \(wardens) roles \(roles.count)") }
            }
        }
        let names = (0..<3).map { "\(BrimstoneKeep.layoutNames[$0]) \(layouts[$0] ?? 0)" }.joined(separator: ", ")
        check(layouts.count == 3 && bad.isEmpty && n >= 12,
              "deep gap: \(n) keeps over 5 seeds use all three layouts (\(names)), each with an Ember Gate frame, one Castellan and 5+ guard roles\(bad.isEmpty ? "" : ": " + bad.prefix(3).joined(separator: "; "))")
    }

    static func gates(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival
        let saved = (g.wokenGates, g.deepReturn, g.deepEntry, g.deepLifts, g.sealShafts)
        defer {
            (g.wokenGates, g.deepReturn, g.deepEntry, g.deepLifts, g.sealShafts) = saved
            g.survival = wasSurvival
            if g.dim.dim != homeDim { g.changeDimension(to: homeDim, at: home) }
            g.player.pos = home; g.player.vel = .zero
            _ = g.world.loadSync(center: home, radius: 4)
        }
        g.changeDimension(to: .deep, at: V3(0.5, Float(DeepGen.hellBase + 60), 0.5))
        guard let sc = g.world.gen.structures, let k = sc.nearest("brimstone_keep", x: 0, z: 0, maxRegions: 3) else {
            check(false, "deep gap: a keep for the gate"); return
        }
        let c = DeepGates.centre(k)
        let yard = V3(Float(c.ox) + 0.5, Float(c.f + 1), Float(c.oz - 9) + 0.5)
        g.player.pos = yard
        _ = g.world.loadSync(center: yard, radius: 4)
        g.world.pendingMobs.removeAll()
        let w = g.world
        g.survival = true; g.alive = true; g.health = 20; g.menu = nil
        // The Warden, as the keep makes it, dies to the player: the gate wakes.
        guard let warden = Mob.structureMob("piglin_brute:warden@deep", at: V3(Float(c.ox) + 0.5, Float(c.f - 9), Float(c.oz + 2) + 0.5)) else {
            check(false, "deep gap: the Castellan"); return
        }
        let mobs0 = g.mobs.mobs
        g.mobs.mobs = [warden]
        let rec = Mob.from(warden.record)
        check(warden.warden && warden.spec.health >= 200 && warden.scale > 1.2 && rec?.warden == true && rec?.spec.health == warden.spec.health,
              "deep gap: the Keep Castellan is a \(warden.spec.health)-health brute at x\(warden.scale), and stays one through a save")
        let woke0 = DeepGates.woken
        g.player.pos = yard
        warden.health = 1
        warden.killedByPlayer = true
        warden.health = 0
        g.mobDied(warden)
        g.mobs.mobs = mobs0
        let veil = Blocks.id(DeepGates.veilKey)
        let filled = DeepGates.veil(k).filter { w.block($0.x, $0.y, $0.z) == veil }.count
        check(DeepGates.woken == woke0 + 1 && g.wokenGates.contains(DeepGates.keyFor(k)) && filled == 15 && g.advancements.contains("adventure/keep_warden"),
              "deep gap: the Castellan falls and the Ember Gate wakes (\(filled) of 15 veil cells, Castellan's Fall)")
        // The way-up marker in the hell band names the gate.
        g.deepEntry = nil
        g.player.pos = yard + V3(0, 0, 30)
        let line = g.deepWayUpLine() ?? "none"
        check(line.contains("Ember Gate") && line.contains("blocks"), "deep gap: the way-up marker points to the gate (\"\(line)\")")
        // Into the veil: up to the surface; the shard back down to the gate's front.
        g.player.pos = V3(Float(c.ox) + 0.5, Float(c.f + 2), Float(c.oz - DeepGates.gateBack) + 0.5)
        g.gateCooldown = 0
        g.gateHold = 0
        for _ in 0..<10 { g.gatesTick(0.05) }                    // walking through (half a second): stays
        let passed = g.dim.dim == .deep
        for _ in 0..<22 where g.dim.dim == .deep { g.gatesTick(0.05) }
        let up = passed && g.dim.dim == .overworld && g.deepReturn != nil
        g.inventory.held = ItemStack(Items.id("gate_shard"), 1)
        g.gateCooldown = 0
        let used = g.useGateShard()
        let back = g.dim.dim == .deep && simd_length(g.player.pos - DeepGates.front(k)) < 0.6 && g.inventory.held.count == 1
        check(up && used && back, "deep gap: walking through the gate doesn't, standing in it 1.5 s goes home (\(up)), the Gate Shard brings you back to its front, not used up (\(back))")
        // A Deep Lift set down in the vault: the marker finds it, standing on it goes home.
        let lp = IVec3(140, DeepGen.floorBase + 1, 360)
        g.player.pos = V3(Float(lp.x) + 4.5, Float(lp.y), Float(lp.z) + 0.5)
        _ = g.world.loadSync(center: g.player.pos, radius: 3)
        g.world.pendingMobs.removeAll()
        for y in lp.y...(lp.y + 2) { w.setBlock(lp.x, y, lp.z, AIR) }
        w.setBlock(lp.x, lp.y, lp.z, Blocks.id(DeepGates.liftKey))
        g.noteDeepLift(lp, placed: true)
        let vline = g.deepWayUpLine() ?? "none"
        g.player.pos = V3(Float(lp.x) + 0.5, Float(lp.y) + 0.19, Float(lp.z) + 0.5)
        g.gateCooldown = 0
        g.gatesTick(0.05)
        check(vline.contains("Hell Lift") && g.dim.dim == .overworld,
              "deep gap: a Hell Lift in the vault is the way up (\"\(vline)\") and carries you home (now in \(g.dim.dim))")
        // Saved.
        let d = g.saveExtra()
        let before = (g.wokenGates, g.deepReturn, g.deepLifts)
        g.wokenGates = []; g.deepReturn = nil; g.deepLifts = []
        g.loadExtra(d)
        check(g.wokenGates == before.0 && g.deepReturn != nil && simd_length(g.deepReturn! - before.1!) < 0.01 && g.deepLifts == before.2,
              "deep gap: woken gates, the shard's return point and Deep Lifts are saved")
    }

    // The vault's own bed and music, the seal-break moment, the journals, advancements and recipes.
    static func bits(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim
        defer {
            if g.dim.dim != homeDim { g.changeDimension(to: homeDim, at: home) }
            g.player.pos = home; g.player.vel = .zero
        }
        g.changeDimension(to: .deep, at: V3(0.5, Float(DeepGen.hellBase + 60), 0.5))
        let hellMood = g.musicMood()
        g.player.pos = V3(300.5, Float(DeepGen.floorBase + 3), 360.5)
        let vaultMood = g.musicMood()
        check(hellMood == .ember && vaultMood == .vault && MusicMood.vault.label == "The Ash Vault",
              "deep gap: the vault has its own music (\(vaultMood.label)) apart from the hell band's (\(hellMood.label))")
        let synth = SoundBank.render(.ashVaultLoop, variant: 0)
        let peak = synth.map { abs($0) }.max() ?? 0
        check(synth.count > 44100 && peak > 0.05, String(format: "deep gap: the vault's ambient bed synthesizes (%.1f s, peak %.2f)", Float(synth.count) / 44100, peak))
        // The seal break: flash, shake and debris on top of the blast.
        let flashes0 = g.flashes.count, m0 = DeepSeal.moments
        g.shake = 0
        let p0 = g.particles.list.count
        g.player.pos = V3(0.5, Float(DeepSeal.top + 1), 0.5)
        let shafts0 = g.sealShafts
        g.sealShafts.removeAll()
        let at = IVec3(0, DeepSeal.bottom, 0)
        g.sealBreakMoment(at: V3(0.5, Float(DeepSeal.top) - 4, 0.5), shaft: at)
        let once = DeepSeal.moments == m0 + 1
        g.sealBreakMoment(at: V3(2.5, Float(DeepSeal.top) - 4, 0.5), shaft: IVec3(2, DeepSeal.bottom, 0))     // the same shaft, widened
        let marked = g.sealShafts == [at] && DeepSeal.moments == m0 + 1
        g.sealShafts = shafts0
        check(once && marked && g.flashes.count >= flashes0 + 6 && g.shake >= 0.99 && g.particles.list.count >= p0 + 150,
              "deep gap: the seal breaking is a moment (\(g.flashes.count - flashes0) light flashes up the shaft, shake \(g.shake), \(g.particles.list.count - p0) debris and smoke), once per shaft, marked for the way up (\(marked))")
        // Journals: the Keeper's Journal tells of the Sealrock, the keeps and their forge and flux as a soldier's story,
        // with no recipe in it (P328 f), found in Deep fortress and keep chests.
        let kj = DeepJournals.all["keepers_journal"]?.pages.joined(separator: " ") ?? ""
        let missing = ["Sealrock", "Brimstone Keep", "Sunderite", "forge", "flux", "blast furnace"].filter { !kj.contains($0) }
            + ["Two Raw", "make Sunderite", "Three Ingots", "An Ingot and", "at any bench", "compass"].filter { kj.contains($0) }.map { "recipe: " + $0 }
        let inLoot = ["fortress", "brimstone_keep"].allSatisfy { t in Loot.tables[t]?.entries.contains { $0.0 == "keepers_journal" } ?? false }
            && ["ash_supply", "ash_command"].allSatisfy { t in Loot.tables[t]?.entries.contains { $0.0 == "ashguard_journal" } ?? false }
        g.inventory.held = ItemStack(Items.id("keepers_journal"), 1)
        let opened = g.useJournal() && (g.menu as? BookMenu)?.pages.count == DeepJournals.all["keepers_journal"]?.pages.count
        g.closeMenu()
        check(missing.isEmpty && inLoot && opened, "deep gap: the Keeper's Journal tells of the seal, the keeps, their forge and flux as a story with no recipe, is in fortress and keep chests, and reads as a book\(missing.isEmpty ? "" : " (missing \(missing))")")
        let advs = ["adventure/deep_hell", "adventure/keep_warden", "adventure/break_seal", "adventure/ash_vault", "adventure/ash_victory", "adventure/sunderite"]
        let have = advs.filter { id in Advancements.all.contains { $0.id == id } }
        let trophies = ["warden_brand", "gate_shard", "sealrock_shard", "marshal_cap"].filter { Items.has($0) }
        let marshal = MobKind.ashMarshal.ashSpec.drops.contains { $0.0 == "marshal_cap" }
        check(have.count == advs.count && trophies.count == 4 && marshal && ["deep_lift", "gate_shard", "sealbound_bricks"].allSatisfy { k in Recipes.all.contains { Items.key($0.result.item) == k } },
              "deep gap: an advancement for each Deep milestone (\(have.count)), a reward for each layer (\(trophies.joined(separator: ", "))), Deep Lift and Gate Shard recipes")
    }

    // MARK: Balance: a full-gear run (D4b, DE1)

    struct Duel { let name: String; let toKillPlayer: Float?; let playerKills: Float?; let weapon: String }

    // Duskium armour, food full, normal difficulty; the unit `dist` blocks off on the open vault floor. Returns how long
    // the unit takes to do 20 points of damage to the player (who stands still; their health is topped up each tick)
    // and how long the player, aiming and firing `gun`, takes to kill it. nil: not within the time limit.
    static func duel(_ g: Game, _ make: (V3) -> Mob?, gun: String, ammo: String, dist: Float, limit: Float = 60) -> (Float?, Float?) {
        let w = g.world
        let spot = V3(130.5, Float(DeepGen.floorBase + 1), 380.5)
        func place() -> Mob? {
            g.mobs.mobs.removeAll(); w.pendingMobs.removeAll(); g.arms.slugs.removeAll()
            g.ashStrikes.removeAll(); g.ashSpot = nil
            g.ashAlarm = 0; g.ashAlarmLevel = 0; g.ashReinforceT = 999; g.ashPatrolT = 999
            guard let m = make(spot + V3(0, 0, -dist)) else { return nil }
            m.aggro = true
            m.soldierBrain.lastSeen = g.player.eye; m.soldierBrain.seenAgo = 0
            g.mobs.mobs = [m]
            g.player.pos = spot; g.player.vel = .zero
            return m
        }
        // 1. The unit on the player.
        var toKill: Float?
        if let m = place() {
            var dealt = 0, t: Float = 0
            while t < limit && m.health > 0 {
                g.health = 20; g.hunger = 20; g.saturation = 5
                g.player.pos = spot; g.player.vel = .zero
                let face = m.pos - g.player.eye
                g.player.yaw = atan2f(face.x, face.z) + .pi; g.player.pitch = 0
                g.tick(0.05)
                dealt += max(0, 20 - g.health)
                t += 0.05
                if !g.alive { g.alive = true; g.health = 20; dealt += 20 }
                if dealt >= 20 { toKill = t; break }
            }
            if toKill == nil {
                let own = g.arms.slugs.filter { $0.shooter == ObjectIdentifier(m) }.count
                print("deep balance duel trace \(m.kind.key): dealt \(dealt) in \(t) s; alive \(m.health > 0), aggro \(m.aggro), seen \(m.soldierBrain.seenAgo), "
                      + "its rounds in flight \(own), \(String(format: "%.1f", simd_length(m.pos - g.player.pos))) blocks off at y \(m.pos.y)")
            }
        }
        // 2. The player on the unit: aim at its middle and hold the trigger. The unit is held where it stands (it still
        // turns and fires): a pure damage race, the same for every unit (the Marshal charging in and out of the blast
        // swung his time from 44 s to over 180 s between runs).
        var kill: Float?
        if let m = place() {
            let hold = m.pos
            g.inventory.held = ItemStack(Items.id(gun), 1)
            for i in 0..<9 where i != g.inventory.selected { g.inventory.main[i] = ItemStack(Items.id(ammo), Items.def(Items.id(ammo)).maxStack) }
            let pm = PadManager.shared
            var t: Float = 0
            var trace = "\(m.health)"
            let hits0 = g.arms.hits, slugs0 = Armory.fired
            var probe = ""
            defer { print("deep balance duel trace \(m.kind.key): health \(trace) at \(m.pos.y), killed \(t) s, alive \(m.health > 0); \(Armory.fired - slugs0) rounds fired, \(g.arms.hits - hits0) hits, \(String(format: "%.1f", simd_length(m.pos - g.player.pos))) blocks off, gun \(g.heldGun != nil); \(probe)") }
            while t < limit && m.health > 0 {
                if Int(t * 20) % 10 == 0 && t < 5 { trace += " \(m.health)/\(m.lastHurtAmount)" }
                g.health = 20; g.hunger = 20
                g.player.pos = spot; g.player.vel = .zero
                let aim = m.pos + V3(0, m.height * 0.5, 0) - g.player.eye
                g.player.yaw = atan2f(aim.x, aim.z) + .pi
                g.player.pitch = atan2f(aim.y, simd_length(V2(aim.x, aim.z)))
                var p = PadSnapshot(); p.rt = (Int(t * 20) % 2 == 0 || (Guns.index(g.inventory.held.item).map { Guns.all[$0].auto } ?? true)) ? 1 : 0
                pm.simulated = p
                if probe.isEmpty && t > 3 {
                    // (why no round lands: the sight line from the eye, the mob's box and the first block on it, the slugs
                    // in flight and where they are)
                    let e = g.player.eye, d = simd_normalize(aim)
                    let mh = m.rayHit(e, d, maxDist: 40), bh = Armory.blockHit(w, e, d, 40)
                    let sl = g.arms.slugs.prefix(3).map { String(format: "(%.1f %.1f %.1f) dead %@ shooter %@", $0.pos.x, $0.pos.y, $0.pos.z, $0.dead ? "y" : "n", $0.shooter == nil ? "nil" : "set") }
                    probe = String(format: "probe: eye (%.1f %.1f %.1f) mob (%.1f %.1f %.1f) h %.2f w %.2f; mob ray %@, block ray %@; mobs %d riding %@; slugs %@",
                                   e.x, e.y, e.z, m.pos.x, m.pos.y, m.pos.z, m.height, m.halfW, mh.map { String(format: "%.2f", $0) } ?? "none",
                                   bh.map { "\(String(format: "%.2f", $0.0)) \(Blocks.key(w.block($0.1.x, $0.1.y, $0.1.z)))" } ?? "none",
                                   g.mobs.mobs.count, g.riding === m ? "it" : "no", sl.joined(separator: ", "))
                }
                g.tick(0.05)
                m.pos.x = hold.x; m.pos.z = hold.z; m.vel.x = 0; m.vel.z = 0
                g.mobs.mobs.removeAll { $0 !== m }; w.pendingMobs.removeAll()     // one unit: no crews, squads or calls
                t += 0.05
                if !g.alive { g.alive = true; g.health = 20 }
            }
            pm.simulated = nil
            if m.health <= 0 { kill = t }
        }
        g.mobs.mobs.removeAll(); g.arms.slugs.removeAll()
        return (toKill, kill)
    }

    static var report: [Duel] = []

    static func balance(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival, wasDiff = g.difficulty
        let wasTime = g.time               // ~20 minutes of duels: put the clock back (later checks open shops by the hour)
        let wasVictory = g.ashVictory      // the Marshal's duel kills him: the army's standing down is put back after
        let wasStage = g.ashStage, wasWave = g.ashWave   // (and his fall starts the last battle: put back too)
        g.ashVictory = false
        let armourSlots = g.inventory.armor.slots, mainSlots = g.inventory.main.slots, held = g.inventory.held
        defer {
            g.inventory.armor.slots = armourSlots; g.inventory.main.slots = mainSlots; g.inventory.held = held
            g.survival = wasSurvival; g.difficulty = wasDiff; g.alive = true; g.health = 20; g.time = wasTime
            g.ashVictory = wasVictory; g.ashAlarm = 0; g.ashAlarmLevel = 0; g.ashSquadsSent = 0
            g.ashStage = wasStage; g.ashWave = wasWave; g.lastWar.wave.removeAll(); g.lastWar.spawned = false; g.ashStrikes.removeAll()
            if g.dim.dim != homeDim { g.changeDimension(to: homeDim, at: home) }
            g.player.pos = home; g.player.vel = .zero
            _ = g.world.loadSync(center: home, radius: 4)
        }
        g.changeDimension(to: .deep, at: V3(130.5, Float(DeepGen.floorBase + 1), 380.5))
        _ = g.world.loadSync(center: g.player.pos, radius: 4)
        g.survival = true; g.alive = true; g.difficulty = 2; g.menu = nil; g.paused = false
        for (i, part) in ["helmet", "chestplate", "leggings", "boots"].enumerated() { g.inventory.armor[i] = ItemStack(Items.id("netherite_\(part)"), 1) }
        func ash(_ key: String) -> (V3) -> Mob? { { p in Mob.structureMob(key, at: p) } }
        func capital(_ k: MobKind) -> (V3) -> Mob? { { p in Mob(k, at: p) } }
        func deep(_ key: String) -> (V3) -> Mob? { { p in Mob.structureMob(key + "@deep", at: p + V3(0, Float(DeepGen.hellBase - DeepGen.floorBase + 40), 0)).map { m in m.pos = p; return m } } }
        // The Marshal on his own (his guard calls are a separate fight: DeepTests.war).
        let marshalAlone: (V3) -> Mob? = { p in
            let m = Mob.structureMob("ash_marshal@ash", at: p)
            m?.soldierBrain.ashCalls = 2; m?.soldierBrain.clock = 0.01
            return m
        }
        let cases: [(String, (V3) -> Mob?, String, String, Float)] = [
            ("Capital rifleman (surface, for scale)", capital(.soldierRecruit), "gun_rifle", "capital_rounds", 18),
            ("Blight Skeleton (hell band)", deep("wither_skeleton"), "gun_rifle", "capital_rounds", 6),
            ("Boarling Brute (hell band)", deep("piglin_brute"), "gun_rifle", "capital_rounds", 6),
            ("Keep Castellan", ash("piglin_brute:warden@deep"), "gun_rifle", "capital_rounds", 6),
            ("Ashguard Rifleman", ash("soldier_recruit@ash"), "gun_rifle", "capital_rounds", 18),
            ("Ashguard Stormer", ash("soldier_trooper@ash"), "gun_rifle", "capital_rounds", 18),
            ("Ashguard Heavy", ash("soldier_ironclad@ash"), "gun_rifle", "capital_rounds", 18),
            ("Ashguard Half-track", ash("ash_halftrack@ash"), "gun_launcher", "rocket_ammo", 20),
            ("Cinder Tank (rifle)", ash("ash_tank@ash"), "gun_rifle", "capital_rounds", 24),
            ("Cinder Tank (launcher)", ash("ash_tank@ash"), "gun_launcher", "rocket_ammo", 24),
            ("The Ash Marshal", marshalAlone, "gun_launcher", "rocket_ammo", 16),
        ]
        report = []
        // Seeded duels (a single duel's spread and hit luck swung a rifleman's time by 2x). The numbers still shift a
        // little with what ran before (a full questcheck vs --deep-only): the rules below hold with room to spare.
        let wasDeterministic = Rand.deterministic
        defer { Rand.deterministic = wasDeterministic }
        for (i, (name, make, gun, ammo, dist)) in cases.enumerated() {
            // The two riflemen the harder-than-the-surface rule compares: three seeds each, averaged (one seed's hit luck
            // swung the ratio from 1.2 to 1.6 between runs).
            let seeds = name.hasPrefix("Capital rifleman") || name.hasPrefix("Ashguard Rifleman") ? 3 : 1
            var runs: [(Float?, Float?)] = []
            for k in 0..<seeds {
                Rand.seed(0xBA1A_0000 + UInt64(i) + UInt64(k) * 0x100)
                runs.append(duel(g, make, gun: gun, ammo: ammo, dist: dist, limit: name.hasPrefix("The Ash Marshal") ? 180 : 60))   // the boss: a long fight
            }
            func mean(_ xs: [Float?]) -> Float? { xs.contains { $0 == nil } ? nil : xs.compactMap { $0 }.reduce(0, +) / Float(xs.count) }
            let (a, b) = (mean(runs.map { $0.0 }), mean(runs.map { $0.1 }))
            report.append(Duel(name: name, toKillPlayer: a, playerKills: b, weapon: Items.def(Items.id(gun)).display))
            print("deep balance: \(name): kills full-gear player in \(a.map { String(format: "%.1f s", $0) } ?? "> 60 s"); player kills it in \(b.map { String(format: "%.1f s", $0) } ?? (name.hasPrefix("The Ash Marshal") ? "> 180 s" : "> 60 s")) (\(Items.def(Items.id(gun)).display))")
        }
        func r(_ n: String) -> Duel? { report.first { $0.name.hasPrefix(n) } }
        let cap = r("Capital rifleman"), rifle = r("Ashguard Rifleman"), tankR = r("Cinder Tank (rifle)"), tankL = r("Cinder Tank (launcher)")
        // Harder than the surface: the Ashguard rifleman takes longer to kill and kills faster than a Capital one; the tank
        // shrugs off rifles (or takes far longer) and falls to the launcher; every unit can be beaten with full gear.
        // (P358, Oct 16 "the Nazis are still too tough": a soldier of any side dies to two rifle rounds, so the Ashguard
        // rifleman is harder only by his aim and his gun, not by taking longer to drop.)
        let harder = (rifle?.toKillPlayer ?? .infinity) < (cap?.toKillPlayer ?? 0)
        let armoured = (tankR?.playerKills == nil || (tankR?.playerKills ?? 0) > 3 * (tankL?.playerKills ?? .infinity)) && tankL?.playerKills != nil
        let beatable = report.filter { !$0.name.hasPrefix("Cinder Tank (rifle)") }.allSatisfy { $0.playerKills != nil }
        let fair = report.allSatisfy { ($0.toKillPlayer ?? .infinity) > 2 }
        check(harder && armoured && beatable && fair,
              "deep balance: full gear, Ashguard rifleman \(f(rifle?.playerKills)) to kill / kills you in \(f(rifle?.toKillPlayer)) vs Capital \(f(cap?.playerKills)) / \(f(cap?.toKillPlayer)); tank \(f(tankR?.playerKills)) by rifle, \(f(tankL?.playerKills)) by launcher; all beatable \(beatable), none faster than 2 s \(fair)")
    }
    static func f(_ t: Float?) -> String { t.map { String(format: "%.1f s", $0) } ?? "> 60 s" }
}
