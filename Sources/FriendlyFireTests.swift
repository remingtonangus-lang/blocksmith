import Foundation
import simd

// Friendly fire (Q2, scorecard "Behaviour: no friendly fire"; `questcheck --friendlyfire-only`, and part of every
// questcheck run). The Ashguard is measured in its biggest battle (AshVaultGapTests); here each of the other soldier
// factions (the Capital, Greywall Command at fortress tier, the Meridian Navy) fights the player as a squad on open
// ground: twelve soldiers of every rank in three ranks, the player 20 blocks ahead, so the rear ranks fire through the
// front ones and the heavies' launchers land among them. The player never attacks and is kept alive, so every hit a
// soldier takes came from its own side (a round, a blast, a blow). Each squad must also have fought (the player hit).
enum FriendlyFireTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, surv0 = g.survival, fly0 = g.player.flying, mobs0 = g.mobs.mobs, time0 = g.time, menu0 = g.menu
        let riding0 = g.riding, credits0 = g.credits
        let fx = Int(floor(pos0.x)) - 60, fz = Int(floor(pos0.z)) + 60
        _ = w.loadSync(center: V3(Float(fx), pos0.y, Float(fz)), radius: 3)
        let py = min(CH - 14, w.topY(fx, fz) + 30)
        var placed: [(IVec3, BlockID)] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { placed.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        defer {
            Mob.onHit = nil
            for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }
            g.mobs.mobs = mobs0; g.riding = riding0; g.credits = credits0
            g.survival = surv0; g.player.flying = fly0; g.player.pos = pos0; g.player.vel = .zero; g.time = time0
            if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }; g.menu = menu0
            g.health = 20; g.alive = true
        }
        // A stone field 41 x 21 with nothing above it.
        for z in (fz - 10)...(fz + 10) { for x in (fx - 12)...(fx + 28) {
            put(x, py, z, STONE)
            for y in (py + 1)...(py + 8) where w.block(x, y, z) != AIR { put(x, y, z, AIR) }
        } }
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
        g.riding = nil; g.credits = nil
        g.survival = true; g.player.flying = false; g.time = DAY_LENGTH * 0.25
        let stand = V3(Float(fx + 20) + 0.5, Float(py + 1), Float(fz) + 0.5)

        // Three ranks of four, facing the player along +x: recruits in front, troopers and marksmen behind, the
        // heavies (launchers, ashsaws, arc guns at fortress tier) and an officer at the back.
        let ranks: [[String]] = [["soldier_recruit", "soldier_recruit", "soldier_trooper", "soldier_recruit"],
                                 ["soldier_trooper", "soldier_marksman", "soldier_trooper", "soldier_marksman"],
                                 ["soldier_ironclad", "soldier_officer", "soldier_ironclad", "soldier_ironclad"]]
        let factions: [(String, Faction)] = [("Capital", .steelhold), ("Greywall", .greywall), ("Meridian", .meridian)]
        var rows: [String] = [], bad: [String] = [], quiet: [String] = []
        for (name, f) in factions {
            g.mobs.mobs.removeAll(); g.arms.slugs.removeAll(); g.arms.beams.removeAll(); g.drops.items.removeAll()
            var squad: [Mob] = []
            for (r, rank) in ranks.enumerated() {
                for (i, key) in rank.enumerated() {
                    let at = V3(Float(fx - r * 2) + 0.5, Float(py + 1), Float(fz - 3 + i * 2) + 0.5)
                    let m: Mob
                    if f == .greywall, let gm = TroopTests.grey(key, .fortress, at) { m = gm }
                    else { m = Mob(MobKind.keys.first { $0.value == key }?.key ?? .soldierTrooper, at: at); m.faction = f.rawValue }
                    m.yaw = -.pi / 2
                    m.aggro = true; m.lockTime = 30
                    m.soldierBrain.lastSeen = g.player.eye; m.soldierBrain.seenAgo = 0
                    g.mobs.mobs.append(m); squad.append(m)
                }
            }
            var ff: [String: (Int, Int)] = [:]
            Mob.onHit = { m, src, d in
                guard m.faction == f.rawValue, d > 0, m.health > 0 else { return }
                let near = squad.filter { $0 !== m && $0.health > 0 && simd_length($0.pos - src) < 3 }.min { simd_length($0.pos - src) < simd_length($1.pos - src) }
                let k = "\(m.kind.key) by \(near.map { $0.kind.key } ?? "blast/other")"
                let e = ff[k] ?? (0, 0)
                ff[k] = (e.0 + 1, e.1 + d)
            }
            var taken: Float = 0
            for _ in 0..<(72 * 20) {
                g.health = 20; g.alive = true; g.player.pos = stand; g.player.vel = .zero
                if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
                g.tick(1.0 / 72)
                taken += Float(max(0, 20 - g.health))
            }
            Mob.onHit = nil
            let hits = ff.values.reduce(0) { $0 + $1.0 }
            let list = ff.sorted { $0.value.0 > $1.value.0 }.prefix(4).map { "\($0.key) \($0.value.0)x \($0.value.1) hp" }.joined(separator: ", ")
            let alive = squad.filter { $0.health > 0 }.count
            rows.append("\(name) \(hits) hits (\(alive)/\(squad.count) standing, the player took \(Int(taken)) hp)" + (list.isEmpty ? "" : ": " + list))
            if hits > 0 { bad.append(name) }
            if taken < 4 { quiet.append(name) }
        }
        g.mobs.mobs.removeAll(); g.arms.slugs.removeAll(); g.arms.beams.removeAll()
        print("friendly fire: " + rows.joined(separator: "; "))
        check(bad.isEmpty && quiet.isEmpty, "friendly fire: no soldier squad hurts its own in 20 s against the player (12 each, three ranks firing through each other): "
              + rows.map { $0.components(separatedBy: " (").first ?? $0 }.joined(separator: ", ")
              + (bad.isEmpty ? "" : "; own hits: " + bad.joined(separator: ", ")) + (quiet.isEmpty ? "" : "; never fought: " + quiet.joined(separator: ", ")))
    }
}
