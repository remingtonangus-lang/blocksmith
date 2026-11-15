import Foundation
import simd

// Checks for the Nov 15 morning playtest's fixes (Opus lane, docs/playtests/2026-11-15) that need no world of their own
// (questcheck suite; --nov15 alone).
enum Nov15MorningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        radar(g, check)
        carriage(check)
        repeater(check)
        escort(g, check)
        sheetIce(g, check)
        customs(g, check)
        check(HeavyTurret.oldStationReach || HeavyTurret.drawnReach(g) >= Float(max(8, g.world.renderDistance) * CS),
              "Nov 15 Boreal Station: its guns lay on a vehicle he drives out to his view (\(Int(HeavyTurret.drawnReach(g))) blocks, was 110 / 220)")
    }

    // 08:31 ("the radar should follow where I'm looking"): the scope and the bearings turn with the head, not the body.
    static func radar(_ g: Game, _ check: (Bool, String) -> Void) {
        let was = (g.vrHeadYaw, g.player.yaw)
        defer { g.vrHeadYaw = was.0; g.player.yaw = was.1 }
        g.player.yaw = 0
        g.vrHeadYaw = 1.2
        check(Game.oldRadarYaw || abs(g.radarYaw - 1.2) < 1e-4,
              String(format: "Nov 15 radar: the scope's up is where his head looks (%.2f with the head at 1.20, the body at 0)", g.radarYaw))
    }

    // 08:05 ("get rid of that tail on the siege carriage"): nothing hangs off its stern; troops climb a side ladder.
    static func carriage(_ check: (Bool, String) -> Void) {
        let b = Vessels.carriage()
        let past = b.cells.keys.filter { $0.z > 22 }.count
        let ladder = Blocks.has("ladder") ? Blocks.groupBase[Int(Blocks.id("ladder"))] : AIR
        let rungs = (1...7).filter { y in b.cells[IVec3(-6, y, Vessels.carriageLadderZ)].map { Blocks.groupBase[Int($0)] == ladder } ?? false }.count
        check(Vessels.oldCarriageLadder || (past == 0 && rungs == 7),
              "Nov 15 carriage: no tail past its stern (\(past) cells), a 7-rung ladder up its side by the wheels (\(rungs))")
    }

    // 08:22:13 ("loaded 90/90 but not firing"): a charge-handle gun with a magazine slotted by hand shows its handle back.
    static func repeater(_ check: (Bool, String) -> Void) {
        let was = (GunActions.manual, GunActions.cocked)
        defer { (GunActions.manual, GunActions.cocked) = was }
        GunActions.manual = true; GunActions.cocked = false
        let drawn = GunActions.slideDrawn(Guns.repeater)
        GunActions.cocked = true
        let home = GunActions.slideDrawn(Guns.repeater)
        check(GunActions.oldChargeLook || (drawn == 1 && home == 0),
              "Nov 15 Slate Repeater: uncocked, its charging handle stands back (\(drawn)); worked, it is home (\(home))")
    }

    // 08:40-08:41 (the escort): follows him, rides behind him on his horse, and the contract fails the moment they die.
    static func escort(_ g: Game, _ check: (Bool, String) -> Void) {
        let saved = (TownLaw.state.contracts, g.riding, g.player.pos)
        let mobs0 = g.mobs.mobs
        defer { TownLaw.state.contracts = saved.0; g.riding = saved.1; g.player.pos = saved.2; g.mobs.mobs = mobs0 }
        let p = g.player.pos
        let m = Mob(.villager, at: g.world.freeSpawn(p + V3(16, 0, 0)))
        m.persistent = true; m.customName = "Ada Testwell"; m.escort = !Contracts.oldEscort
        g.mobs.mobs.append(m)
        var all = TownLaw.state.contracts ?? [:]
        all["Testmoor#0"] = Contract(day: 0, kind: "escort", board: "Testmoor", destAt: [Int(p.x) + 2000, Int(p.z)], pay: 400, honour: 7, taken: true, who: m.customName)
        TownLaw.state.contracts = all
        let d0 = simd_length(V2(m.pos.x - p.x, m.pos.z - p.z))
        for _ in 0..<120 { g.mobs.update(0.05, game: g) }
        let d1 = simd_length(V2(m.pos.x - p.x, m.pos.z - p.z))
        check(Contracts.oldEscort || d1 < min(d0 - 6, 8),
              String(format: "Nov 15 escort: follows him on foot (%.1f -> %.1f blocks in 6 s)", d0, d1))
        let horse = Mob(.horse, at: g.world.freeSpawn(p + V3(2, 0, 0)))
        horse.yaw = 0.7
        g.mobs.mobs.append(horse)
        g.riding = horse
        m.pos = horse.pos + V3(3, 0, 0)
        for _ in 0..<4 { g.mobs.update(0.05, game: g) }
        let fwd = V3(-sinf(horse.yaw), 0, -cosf(horse.yaw))
        let behind = simd_dot(m.pos - horse.pos, fwd)
        check(Contracts.oldEscort || (m.mount === horse && behind < -0.3),
              String(format: "Nov 15 escort: rides his horse behind him (mounted %@, %.2f along its heading)", m.mount === horse ? "yes" : "no", behind))
        g.riding = nil
        for _ in 0..<2 { g.mobs.update(0.05, game: g) }
        check(Contracts.oldEscort || m.mount == nil, "Nov 15 escort: he gets down, they get down beside the horse")
        m.health = 0
        Contracts.mobDied(g, m)
        let failed = TownLaw.state.contracts?["Testmoor#0"]?.failed ?? false
        check(Contracts.oldEscort || failed, "Nov 15 escort: killed, the contract is off at once (failed \(failed))")
    }

    // 08:39:11 ("Shooting at ice should put bullet holes in it"): a pistol round holes the sheet, five go through it.
    static func sheetIce(_ g: Game, _ check: (Bool, String) -> Void) {
        let s = Game.seaIceID, w = g.world
        guard s != AIR, !BlockWear.oldIceHoles else { return }
        let p = IVec3(Int(floor(g.player.pos.x)) + 5, 320, Int(floor(g.player.pos.z)) + 5)
        let old = (0..<3).map { w.block(p.x, p.y - $0, p.z) }
        defer { for k in 0..<3 { w.setBlock(p.x, p.y - k, p.z, old[k]) } }
        w.setBlock(p.x, p.y - 2, p.z, STONE); w.setBlock(p.x, p.y - 1, p.z, WATER); w.setBlock(p.x, p.y, p.z, s)
        var seen: [String] = []
        for k in 0..<6 {
            let from = V3(Float(p.x) + 0.3 + Float(k) * 0.08, Float(p.y) + 4, Float(p.z) + 0.6)
            g.arms.spawn(Slug(pos: from, vel: V3(0, -150, 0), kind: .bullet, damage: 4, fromPlayer: true, shooter: nil, by: "Player", life: 0.6, gravity: 0))
            for _ in 0..<8 { g.arms.update(1.0 / 60, g) }
            seen.append(Blocks.key(w.block(p.x, p.y, p.z)))
        }
        let holed = Blocks.has("sea_ice[1]") ? Blocks.id("sea_ice[1]") : AIR
        check(seen.first == "sea_ice[1]" && seen.contains("sea_ice[2]") && seen.last == Blocks.key(WATER) && Loot.drops(holed, ItemStack.empty).isEmpty,
              "Nov 15 ice: pistol rounds hole sheet ice, then shoot it through to the water (\(seen.joined(separator: ", ")))")
    }

    // 08:15:45-08:16:02 ("I don't think I can actually pay anything here... Customs. Pay here. I don't even know what that
    // means"): the post's signs say what the duty is on, and an officer stands in the booth who takes it or waves him on.
    static func customs(_ g: Game, _ check: (Bool, String) -> Void) {
        guard !Countries.oldCustoms else { return }
        let here = Countries.at(g, g.player.pos)
        guard let into = Countries.neighbours(g, here).first else { check(false, "Nov 15 customs: no neighbouring country"); return }
        let s = (Int(floor(g.player.pos.x)) + 40, Int(floor(g.player.pos.z)) + 40)
        let w = g.world
        let gy = w.gen.column(s.0, s.1).height
        var saved: [(IVec3, BlockID)] = []
        for dz in -3...3 { for dx in -3...5 { for y in (gy - 5)...(gy + 7) { saved.append((IVec3(s.0 + dx, y, s.1 + dz), w.block(s.0 + dx, y, s.1 + dz))) } } }
        let mobs0 = g.mobs.mobs
        defer {
            for (q, b) in saved { w.setBlock(q.x, q.y, q.z, b); w.blockEntities[q] = nil }
            g.mobs.mobs = mobs0
        }
        Countries.build(g, at: s, here, into)
        Countries.officer(g, at: s, into: into)
        let sign = w.blockEntities[IVec3(s.0, gy + 1, s.1 - 2)]
        let off = Countries.officerAt(g, s)
        let talked = off.map { Countries.talk(g, $0) } ?? false
        check(sign?.lines.first == "CUSTOMS" && (sign?.lines[2].contains("ore") ?? false) && off != nil && talked,
              "Nov 15 customs: the post's sign reads \"\(sign?.lines.joined(separator: " / ") ?? "none")\", an officer stands in its booth (\(off != nil)) and answers him (\(talked))")
    }
}
