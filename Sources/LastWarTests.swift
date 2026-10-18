import Foundation
import simd

// The last war below the Ash Vault (backlog B7; AshArms, AshLook, AshLines, AshFinal; docs/status/the-last-war.md).
// `questcheck --lastwar-only` runs just these.
enum LastWarTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival, wasDiff = g.difficulty
        let wasMenu = g.menu
        let wasMobs = g.mobs.mobs, wasVictory = g.ashVictory, wasStage = g.ashStage, wasWave = g.ashWave
        defer {
            g.mobs.mobs = wasMobs
            g.ashVictory = wasVictory; g.ashStage = wasStage; g.ashWave = wasWave
            g.lastWar.wave.removeAll(); g.lastWar.spawned = false; g.lastWar.inBunker = 0
            g.ashStrikes.removeAll(); g.arms.slugs.removeAll()
            g.credits = nil; g.creditsAsh = false
            g.menu = wasMenu                      // a shell that downed the test player opened the death screen
            g.survival = wasSurvival; g.difficulty = wasDiff; g.alive = true; g.health = 20
            if g.dim.dim != homeDim { g.changeDimension(to: homeDim, at: home) }
            g.player.pos = home; g.player.vel = .zero; g.player.flying = false
            _ = g.world.loadSync(center: home, radius: 4)
            print(String(format: "lastwar: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        }
        arms(check)
        looks(check)
        g.changeDimension(to: .deep, at: V3(0.5, Float(DeepGen.floorBase + 2), -30.5))
        lines(g, check)
        bunker(g, check)
        battle(g, check)
    }

    // The army drawn up in a row facing the camera (+z), for the --render shot.
    static func lineup(at c: V3) -> [Mob] {
        let row: [(String, Float, Float)] = [("ash_behemoth", -11, 0), ("ash_tank", -5, 0), ("ash_halftrack", 0.5, 0), ("ash_artillery", 5, 0),
            ("soldier_recruit", 8, 2), ("soldier_trooper", 9.2, 2), ("soldier_marksman", 10.4, 2), ("soldier_ironclad", 11.6, 2),
            ("soldier_officer", 12.8, 2), ("ash_marshal", -2.5, 4.5), ("ash_chancellor", 3.5, 4.5)]
        var out: [Mob] = []
        for (key, dx, dz) in row {
            guard let m = Mob.structureMob(key + "@ash", at: c + V3(dx, 0, dz)) else { continue }
            m.yaw = .pi
            m.soldierBrain.turret = .pi
            out.append(m)
        }
        return out
    }

    // The army's own period-style arms: four guns with specs, models, icons and voices; every rank carries one.
    static func arms(_ check: (Bool, String) -> Void) {
        var bad: [String] = []
        let painters = TextureGen.painters()
        for i in [Guns.kessel, Guns.hagel, Guns.sturmwind, Guns.ashsaw] {
            let s = Guns.all[i]
            if !Items.has(s.key) { bad.append("\(s.key): no item") }
            if s.name.isEmpty || s.mag <= 0 || s.damage <= 0 { bad.append("\(s.key): spec") }
            let m = AshArms.model(i)
            if m.parts.count < 8 || m.parts.count > 60 { bad.append("\(s.key): \(m.parts.count) model parts") }
            if AshArms.icons[s.key] == nil && painters[s.key] == nil { bad.append("\(s.key): no icon") }
        }
        var synth = Synth(seed: 7)
        for slot in 16...19 {
            let a = synth.render(.gun(slot), pitch: 1)
            let peak = a.reduce(0) { max($0, abs($1)) }
            if a.count < 400 || peak < 0.05 { bad.append("gun sound \(slot): \(a.count) samples, peak \(peak)") }
        }
        let all: UInt64 = Enchant.pack([(.stability, 3), (.extendedMag, 3), (.penetration, 1), (.quickReload, 2)])
        for i in [Guns.kessel, Guns.hagel, Guns.sturmwind, Guns.ashsaw] {
            let v = (Guns.models[i].count + Guns.upgradeParts(i, all, magOut: false).count + 1) * 36
            if v > 1336 { bad.append("\(Guns.all[i].key): \(v) vertices upgraded") }
        }
        check(bad.isEmpty, "lastwar: the Kessel, Hagel, Sturmwind and Ashsaw have items, models (within the arm buffer upgraded), icons and sounds \(bad)")
        // Loadouts: every Ashguard rank carries the army's own arms, and heavies the Ashsaw.
        var wrong: [String] = []
        for key in ["soldier_recruit", "soldier_trooper", "soldier_marksman", "soldier_ironclad", "soldier_officer", "ash_marshal", "ash_chancellor"] {
            for _ in 0..<6 {
                guard let m = Mob.structureMob(key + "@ash", at: V3(0, 100, 0)) else { wrong.append(key); break }
                if !Guns.isAshArm(m.variant) { wrong.append("\(key): \(Guns.all[m.variant].key)") }
                if key == "soldier_ironclad" && m.variant != Guns.ashsaw { wrong.append("heavy without the Ashsaw") }
            }
        }
        check(wrong.isEmpty, "lastwar: every Ashguard rank carries period-style arms, heavies the Ashsaw \(wrong)")
    }

    // Uniforms and vehicles build, the Behemoth and Chancellor register, and the emblem is mirror-symmetric (so it can
    // never read as a hooked cross).
    static func looks(_ check: (Bool, String) -> Void) {
        var bad: [String] = []
        for k in [MobKind.ashTank, .ashBehemoth, .ashHalftrack, .ashArtillery, .ashTruck, .ashChancellor, .ashMarshal,
                  .soldierRecruit, .soldierTrooper, .soldierMarksman, .soldierIronclad, .soldierOfficer] {
            let m = Mob.structureMob(k.key + "@ash", at: V3(0, 100, 0)) ?? Mob(k, at: V3(0, 100, 0))
            let n = mobModelParts(m).count
            if n < 10 || n > 260 { bad.append("\(k.key): \(n) parts") }
            if MobKind.named(k.key) != k { bad.append("\(k.key): key") }
        }
        let back = (try? JSONEncoder().encode(Mob(.ashBehemoth, at: .zero).record)).flatMap { try? JSONDecoder().decode(MobRecord.self, from: $0) }.flatMap { Mob.from($0) }
        if back?.kind != .ashBehemoth { bad.append("behemoth save") }
        check(bad.isEmpty, "lastwar: every Ashguard unit, the Behemoth and the Chancellor build models and save \(bad)")
        let p = TextureGen.painters()
        var missing: [String] = []
        for n in ["ash_banner_top", "ash_banner_mark", "ash_banner", "ash_banner_end", "ash_bunkercrete", "ash_blastdoor", "ash_wire"]
            + (0..<9).map({ "ash_standard_\($0)" }) where p[n] == nil || !Blocks.has(n) { missing.append(n) }
        func cls(_ c: V4) -> Int { c.x + c.y + c.z < 0.3 ? 0 : (c.x > 0.6 && c.z < 0.3 ? 2 : 1) }   // black, the orange mark, cloth
        var asym = 0, white = 0, black = 0
        for Y in 0..<48 { for X in 0..<48 {
            func px(_ x: Int, _ y: Int) -> V4 { p["ash_standard_\((y / 16) * 3 + x / 16)"]!(x % 16, y % 16) }
            guard missing.isEmpty else { break }
            let a = cls(px(X, Y)), b = cls(px(47 - X, Y))
            if a != b { asym += 1 }
            if a == 2 { white += 1 } else if a == 0 { black += 1 }
        } }
        check(missing.isEmpty && asym == 0 && white > 200 && black > 200,
              "lastwar: banners, standard, bunker blocks painted; the emblem is mirror-symmetric (\(asym) odd pixels, \(white) orange, \(black) black) \(missing)")
        check(Blocks.def(Blocks.id("ash_bunkercrete")).hardness < 0 && Blocks.def(Blocks.id("ash_blastdoor")).hardness < 0 && !Blocks.collide[Int(Blocks.id("ash_wire"))],
              "lastwar: bunker concrete and the blast door break for nothing; wire can be walked into")
    }

    // The lines in a generated vault: teeth, wire, trench and parapet where AshLines says, and the roads open through
    // both lines.
    static func lines(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        guard let dg = w.gen as? DeepGen else { check(false, "lastwar: the Deep has no DeepGen"); return }
        let concrete = Blocks.id("ash_concrete"), wire = Blocks.id("ash_wire"), bags = Blocks.id("ash_sandbags")
        var seen: [AshLines.Cut: Int] = [:], right = 0, total = 0
        func ray(_ deg: Float, from r0: Float, to r1: Float) {
            let a = deg * .pi / 180
            _ = w.loadSync(center: V3(sinf(a) * (r0 + r1) / 2, Float(DeepGen.floorBase), -cosf(a) * (r0 + r1) / 2), radius: 2)
            var r = r0
            while r <= r1 {
                let cx = Int(floor(sinf(a) * r)), cz = Int(floor(-cosf(a) * r))
                r += 3
                for (ox, oz) in [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)] {
                let x = cx + ox, z = cz + oz
                let k = AshLines.cut(x, z)
                guard k != .none else { continue }
                let f = dg.floorY(x, z)
                total += 1
                seen[k, default: 0] += 1
                let ok: Bool
                switch k {
                case .tooth: ok = w.block(x, f + 1, z) == concrete && w.block(x, f + 2, z) == concrete
                case .wire: ok = w.block(x, f + 1, z) == wire
                case .post: ok = w.block(x, f + 1, z) == AshLines.post
                case .trench: ok = w.block(x, f, z) == AIR && w.block(x, f - 2, z) == AshLines.duckboard
                case .parapet: ok = w.block(x, f + 1, z) == bags
                case .none: ok = true
                }
                if ok { right += 1 }
                }
            }
        }
        ray(37.5, from: 396, to: 440)        // the Ember Line between two bunkers
        ray(-140, from: 396, to: 440)
        ray(20, from: 50, to: 72)            // the Last Line (Chebyshev: crossing the north face)
        let kinds = [AshLines.Cut.tooth, .wire, .trench, .parapet].filter { (seen[$0] ?? 0) > 0 }.count
        check(total > 40 && kinds == 4 && right * 10 >= total * 9,
              "lastwar: the lines are dug where AshLines says (\(right)/\(total) columns; teeth \(seen[.tooth] ?? 0), wire \(seen[.wire] ?? 0), trench \(seen[.trench] ?? 0), parapet \(seen[.parapet] ?? 0))")
        // Roads through both lines: walkable (steps of one block, two of headroom) on the road's centre lines.
        var blocked: [String] = []
        for (dx, dz, from, to) in [(0, -1, 380, 456), (1, 0, 380, 456), (0, -1, 44, 76), (-1, 0, 44, 76), (0, 1, 44, 76)] {
            _ = w.loadSync(center: V3(Float(dx * (from + to) / 2), Float(DeepGen.floorBase), Float(dz * (from + to) / 2)), radius: 3)
            for lane in [-1, 1] {
                var last: Int?
                for d in from...to {
                    let x = dx * d + (dz != 0 ? lane : 0), z = dz * d + (dx != 0 ? lane : 0)
                    func stand(_ y: Int) -> Bool {
                        Blocks.collide[Int(w.block(x, y, z))] && !Blocks.collide[Int(w.block(x, y + 1, z))] && !Blocks.collide[Int(w.block(x, y + 2, z))]
                    }
                    if last == nil {
                        var y = DeepGen.floorBase + 3
                        while y > DeepGen.floorBase - 10 && !stand(y) { y -= 1 }
                        last = y
                    }
                    guard let y = [last! + 1, last!, last! - 1].first(where: stand) else { blocked.append("(\(x), \(z))"); break }
                    last = y
                }
            }
        }
        check(blocked.isEmpty, "lastwar: the roads run open through the Ember Line and the Last Line \(blocked)")
        // Bunkers and gates stand on the lines.
        let starts = AshWar.starts(seed: w.seed)
        let bunkers = starts.filter { $0.kind == "ash_bunker" }.count, gates = starts.filter { $0.kind == "ash_checkpoint" || $0.kind == "ash_lastgate" }.count
        check(bunkers == 28 && gates == 8 && starts.last?.kind == "ash_finalbunker",
              "lastwar: 28 MG bunkers and 8 checkpoints on the lines, the Chancellor's Bunker built last (\(bunkers), \(gates))")
    }

    // The Chancellor's Bunker under the command bunker: sealed, the stairs walkable, the rooms there, and saved vaults get
    // it stamped in.
    static func bunker(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        _ = w.loadSync(center: V3(0, 20, 24), radius: 3)
        let door = AshFinal.door, bc = AshFinal.bc
        var hatch = 0
        for z in AshFinal.hatchZ { for x in AshFinal.hatchX where w.block(x, AshFinal.hatchY, z) == door { hatch += 1 } }
        // The stairs: each step one block lower, at least two blocks of air over it (the top steps open to the hatch).
        var steps: [String] = []
        for z in 3...17 {
            let fy = AshFinal.hatchY - 1 - (z - 2)
            for x in 7...9 {
                let ok = Blocks.collide[Int(w.block(x, fy, z))] && w.block(x, fy + 1, z) == AIR
                    && (w.block(x, fy + 2, z) == AIR || (fy + 2 == AshFinal.hatchY && w.block(x, fy + 2, z) == door))
                if !ok { steps.append("(\(x), \(fy), \(z))") }
            }
        }
        let study = (32...43).allSatisfy { z in w.block(12, AshFinal.y0 + 1, z) == AIR && w.block(12, AshFinal.y0 + 2, z) == AIR }
        // Sealed: the shell's outer faces are bunker concrete all round (the stairs come in through the north face).
        var leaks = 0
        let y0 = AshFinal.y0
        for z in 17...47 { for y in (y0 - 1)...(y0 + 6) where w.block(-17, y, z) != bc || w.block(17, y, z) != bc { leaks += 1 } }
        for x in -17...17 { for y in (y0 - 1)...(y0 + 6) {
            if w.block(x, y, 47) != bc { leaks += 1 }
            if w.block(x, y, 17) != bc && !((7...9).contains(x) && y > y0 - 1 && y <= y0 + 4) { leaks += 1 }
        } }
        for z in 17...47 { for x in -17...17 where w.block(x, y0 - 1, z) != bc || w.block(x, y0 + 6, z) != bc { leaks += 1 } }
        check(hatch == 9 && steps.isEmpty && study && leaks == 0,
              "lastwar: the blast door shuts the stairs (\(hatch)/9), steps walkable \(steps.prefix(4)), the study is there (\(study)), the shell is sealed (\(leaks) leaks)")
        // Nothing breaks in: a blast on the hatch leaves it.
        let wasSurvival = g.survival
        g.survival = true
        Explosion.explode(at: V3(8.5, Float(AshFinal.hatchY + 1), 3.5), power: 4, game: g)
        g.survival = wasSurvival
        var still = 0
        for z in AshFinal.hatchZ { for x in AshFinal.hatchX where w.block(x, AshFinal.hatchY, z) == door { still += 1 } }
        check(still == 9, "lastwar: an explosion on the blast door leaves it shut (\(still)/9)")
        // Stamp: a saved chunk from before the bunker gets it; a stamped one and a chunk out of reach stay as they are.
        var old = [BlockID](repeating: EMBERSLATE, count: CSQ * CH)
        AshFinal.stamp(&old, cx: 0, cz: 1)
        let stamped = old.filter { $0 == bc }.count
        var again = old
        if let i = again.firstIndex(of: AIR) { again[i] = EMBERSLATE }
        AshFinal.stamp(&again, cx: 0, cz: 1)
        var far = [BlockID](repeating: EMBERSLATE, count: CSQ * CH)
        AshFinal.stamp(&far, cx: 4, cz: 1)
        var hatchChunk = [BlockID](repeating: EMBERSLATE, count: CSQ * CH)
        AshFinal.stamp(&hatchChunk, cx: 0, cz: 0)
        check(stamped > 1000 && again.filter { $0 == AIR }.count == old.filter { $0 == AIR }.count - 1 && !far.contains(bc)
              && hatchChunk[Chunk.index(8, AshFinal.hatchY, 3)] == door,
              "lastwar: saved vault chunks get the bunker stamped in once (\(stamped) concrete), others are left alone")
    }

    // The last battle: the Marshal's fall, three waves, a save mid-battle, the blast door opening, the Chancellor's
    // calls and his death, which ends the war.
    static func battle(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let stand = V3(0.5, Float(DeepGen.floorBase + 1), -30.5)
        _ = w.loadSync(center: stand, radius: 6)
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        g.survival = true; g.paused = false; g.menu = nil; g.alive = true; g.difficulty = 2
        g.player.flying = false
        g.ashVictory = false; g.ashStage = 0; g.ashWave = 0
        var pin = stand
        func sim(_ secs: Float, until: () -> Bool = { false }) {
            var e: Float = 0
            while e < secs {
                g.health = 20
                g.tick(0.05)
                g.health = 20; g.alive = true
                g.player.pos = pin; g.player.vel = .zero
                w.pendingMobs.removeAll()
                e += 0.05
                if until() { return }
            }
        }
        func kill(_ ms: [Mob]) { for m in ms { m.killedByPlayer = true; m.hit(from: m.pos + V3(1, 0, 0), damage: m.health + 900) } }
        g.player.pos = stand
        guard let marshal = Mob.structureMob("ash_marshal@ash", at: stand + V3(0, 0, -6)) else { check(false, "lastwar: no Marshal"); return }
        g.mobs.mobs.append(marshal)
        kill([marshal])
        sim(1)
        check(g.ashStage == 1 && !g.ashVictory && g.credits == nil, "lastwar: the Marshal's fall starts the last battle, not the ending (stage \(g.ashStage))")
        // Wave one: infantry and half-tracks, out on the floor, already hunting.
        sim(12) { g.lastWar.spawned }
        let w1 = g.lastWar.wave
        let dists = w1.map { simd_length(V2($0.pos.x - stand.x, $0.pos.z - stand.z)) }
        check(g.ashWave == 0 && w1.count >= 7 && w1.contains { $0.kind == .ashHalftrack }
              && w1.allSatisfy { $0.aggro && $0.faction == Faction.ashguard.rawValue && !$0.keepOnUnload }
              && dists.allSatisfy { $0 > 25 && $0 < 75 },
              "lastwar: wave 1 comes in (\(w1.count) units at \(Int(dists.min() ?? 0))-\(Int(dists.max() ?? 0)) blocks, hunting, not saved)")
        // Unloaded alive (the player ran off, left the vault or died): the wave regroups and comes again, never skipped.
        let ids1 = Set(w1.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { ids1.contains(ObjectIdentifier($0)) }
        sim(2) { !g.lastWar.spawned }
        let regrouped = g.ashWave == 0 && !g.lastWar.spawned
        sim(10) { g.lastWar.spawned }
        let w1b = g.lastWar.wave
        check(regrouped && w1b.count >= 7, "lastwar: a wave that unloads alive regroups and comes again (\(w1b.count) units), not skipped")
        kill(Array(w1b.dropLast(2)))
        sim(2) { g.ashWave == 1 }
        check(g.ashWave == 1 && !g.lastWar.spawned, "lastwar: wave 1 is beaten with two stragglers left; a breather")
        // Save mid-battle: the stage and wave are kept; the wave in progress comes again.
        g.lastWar.breather = 0
        sim(2) { g.lastWar.spawned }
        let tanks = g.lastWar.wave.filter { $0.kind == .ashTank }.count
        g.ashStrikes.removeAll()
        sim(16) { !g.ashStrikes.isEmpty }
        let barrage = !g.ashStrikes.isEmpty
        let d = g.saveExtra()
        let ids = Set(g.lastWar.wave.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { ids.contains(ObjectIdentifier($0)) }       // not kept: a wave isn't saved
        g.ashStage = 0; g.ashWave = 0
        g.loadExtra(d)
        let resumed = g.ashStage == 1 && g.ashWave == 1 && !g.lastWar.spawned
        sim(10) { g.lastWar.spawned }
        check(tanks == 3 && barrage && resumed && g.lastWar.wave.filter { $0.kind == .ashTank }.count == 3,
              "lastwar: wave 2 brings three tanks and barrages (\(tanks), \(barrage)); after a reload the battle resumes at wave 2 (\(resumed))")
        kill(g.lastWar.wave)
        sim(2) { g.ashWave == 2 }
        g.lastWar.breather = 0
        sim(2) { g.lastWar.spawned }
        let w3 = g.lastWar.wave
        let bar = g.ashBossBar()
        let behemoth = w3.contains { $0.kind == .ashBehemoth }
        // A busy last stand: the whole of wave 3 thinking, aiming and firing costs little per game tick.
        sim(1)
        let live3 = w3.filter { $0.health > 0 }
        let tt = CFAbsoluteTimeGetCurrent()
        for _ in 0..<60 { for m in live3 { m.update(0.05, game: g) }; g.health = 20; g.alive = true }
        let ms = (CFAbsoluteTimeGetCurrent() - tt) * 1000 / 60
        // And the whole game tick (shells, blasts, particles, remeshing) with the wave against without it.
        func tickCost() -> Double { let t = CFAbsoluteTimeGetCurrent(); sim(3); return (CFAbsoluteTimeGetCurrent() - t) * 1000 / 60 }
        let full = tickCost()
        let held = g.mobs.mobs, ids3 = Set(live3.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { ids3.contains(ObjectIdentifier($0)) }
        let slugs = g.arms.slugs
        g.arms.slugs.removeAll()
        g.ashStage = 0                                   // (the battle would count the held-out wave as gone)
        let base = tickCost()
        g.ashStage = 1
        g.mobs.mobs = held; g.arms.slugs = slugs
        check(behemoth && bar?.0 == "Ashguard Behemoth" && w3.count >= 6,
              "lastwar: wave 3 is the Behemoth with tanks and heavies, under a boss bar (\(w3.count) units, \(bar?.0 ?? "no bar"))")
        check(ms < 1.5 && full - base < 4, String(format: "lastwar: the last wave's %d units cost %.2f ms a tick to think; the whole tick %.2f ms against %.2f ms without them",
                                                   live3.count, ms, full, base))
        kill(g.lastWar.wave)
        sim(2) { g.ashStage == 2 }
        var open = 0
        for z in AshFinal.hatchZ { for x in AshFinal.hatchX where w.block(x, AshFinal.hatchY, z) == AIR { open += 1 } }
        check(g.ashStage == 2 && open == 9 && g.advancements.contains("adventure/ash_last_battle"),
              "lastwar: the last army beaten (stage \(g.ashStage), \(g.lastWar.wave.count) left), the blast door opens (\(open)/9) and the advancement")
        // Down in the bunker: the Chancellor and two heavies wait in the study.
        g.mobs.mobs.removeAll()
        pin = V3(8.5, Float(AshFinal.y0 + 1), 22.5)
        _ = w.loadSync(center: pin, radius: 3)
        sim(5) { g.mobs.mobs.contains { $0.kind == .ashChancellor } }
        guard let ch = g.mobs.mobs.first(where: { $0.kind == .ashChancellor }) else { check(false, "lastwar: the Chancellor never came"); return }
        check(simd_length(ch.pos - AshFinal.chancellorAt) < 2 && g.ashBossBar()?.0 == "The Ash Chancellor" && ch.persistent,
              "lastwar: the Ash Chancellor waits in his study under his boss bar")
        func guardCount() -> Int { g.mobs.mobs.filter { $0.faction == Faction.ashguard.rawValue && $0.kind != .ashChancellor && $0.health > 0 }.count }
        pin = V3(8.5, Float(AshFinal.y0 + 1), 34.5)          // into the study, face to face
        sim(1)
        let before = guardCount()
        ch.aggro = true
        ch.health = Int(Float(ch.spec.health) * 0.6)
        sim(1)
        let called = guardCount() - before
        g.shake = 0
        ch.health = Int(Float(ch.spec.health) * 0.45)
        sim(0.3)
        let shook = g.shake > 0
        check(called >= 4 && shook, "lastwar: the Chancellor calls his guard (\(called)) and the bunker shakes at half health (\(shook))")
        kill([ch])
        sim(1)
        check(g.ashVictory && g.ashStage == 3 && g.creditsAsh && g.credits != nil && g.advancements.contains("adventure/ash_victory")
              && AshWar.epilogue.contains("THE END"),
              "lastwar: the Chancellor's death ends the war (victory, the ending, the advancement)")
        var e2 = g.saveExtra()
        e2["ashStage"] = nil
        g.ashStage = 0
        g.loadExtra(e2)
        check(g.ashStage == 3, "lastwar: a save with the old victory flag counts the war as won")
        g.credits = nil; g.creditsAsh = false
    }
}
