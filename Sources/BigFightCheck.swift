import Foundation
import simd

// P450 (Remington, Oct 25 09:08-09:18, the Reckoning on the surface: "Should have drop ships and everything pestering me";
// "I should have a bunch of bombs coming down"; "all the factions are trying to kill each other"): questcheck --bigfight
// starts the hunt with a Capital and a Greywall band 150 blocks either side of him and runs the whole game for 170 s with
// him standing in the open: shells come down round him, each band flies in more than one squad, and the two armies'
// troops leave each other be.
enum BigFightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let mobs0 = g.mobs.mobs, victory0 = g.ashVictory, survival0 = g.survival, diff0 = g.difficulty, toast0 = g.onToast
        let pos0 = g.player.pos, fly0 = g.player.flying
        let ships0 = Set(g.world.ships.list.map { ObjectIdentifier($0) })
        defer {
            g.mobs.mobs = mobs0; g.ashVictory = victory0; g.survival = survival0; g.difficulty = diff0; g.onToast = toast0
            g.alive = true; Reckoning.reset(); g.player.pos = pos0; g.player.flying = fly0; g.ashStrikes.removeAll()
            for s in g.world.ships.list where !ships0.contains(ObjectIdentifier(s)) { g.world.ships.remove(s); g.world.ships.capState.removeValue(forKey: s.id) }
        }
        let w = g.world
        _ = w.loadSync(center: pos0, radius: 6)
        let px = Int(floor(pos0.x)), pz = Int(floor(pos0.z))
        let stand = V3(pos0.x, Float(w.topY(px, pz) + 1), pos0.z)
        g.player.pos = stand; g.player.flying = false
        g.mobs.mobs = []; g.ashVictory = true; g.survival = true; g.difficulty = 2; g.alive = true
        Reckoning.own(g)
        Reckoning.reset()
        Reckoning.stage = 2
        let p = V2(stand.x, stand.z)
        Reckoning.hunts = [Reckoning.Hunt(side: .capital, pos: p + V2(150, 0), waiting: Reckoning.Side.capital.roster),
                           Reckoning.Hunt(side: .greywall, pos: p - V2(150, 0), waiting: Reckoning.Side.greywall.roster)]
        var toasts: [String] = []
        g.onToast = { toasts.append($0) }
        let shells0 = Reckoning.barrageShells
        var t: Float = 0, infighting = 0, nearRivals = 0, maxTroops = 0
        var log: [String] = []
        while t < 170 {
            g.health = 20; g.alive = true
            g.tick(0.05)
            t += 0.05
            g.player.pos = stand; g.player.vel = .zero
            guard Int((t * 20).rounded()) % 20 == 0 else { continue }
            // Once a second: soldiers of the two armies near him, and any of them aiming at the other army.
            let troops = g.mobs.mobs.filter { $0.health > 0 && Reckoning.hunting($0.factionValue) && simd_length(V2($0.pos.x, $0.pos.z) - p) < 120 }
            maxTroops = max(maxTroops, troops.count)
            for m in troops {
                if let f = m.soldierBrain.foe, f.mob.map({ Reckoning.hunting($0.factionValue) && $0.factionValue != m.factionValue }) == true
                    || f.ship.map({ Reckoning.hunting($0.factionValue) && $0.factionValue != m.factionValue }) == true { infighting += 1 }
                if troops.contains(where: { $0.factionValue != m.factionValue && simd_length($0.pos - m.pos) < 64 }) { nearRivals += 1 }
            }
            if Int(t.rounded()) % 20 == 0 {
                log.append(String(format: "%.0f s: %d troops near him, %d shells so far", t, troops.count, Reckoning.barrageShells - shells0))
            }
        }
        let shells = Reckoning.barrageShells - shells0
        let drops = toasts.filter { $0.contains("dropship is coming") }.count
        let capDrops = toasts.filter { $0.contains("Capital dropship") }.count, greyDrops = toasts.filter { $0.contains("Greywall dropship") }.count
        check(shells >= 12, "bigfight: \(shells) marked shells come down round him in 170 s (every band within 200 blocks fires every 20 s)")
        check(capDrops >= 2 && greyDrops >= 2, "bigfight: \(drops) dropships fly squads in (Capital \(capDrops), Greywall \(greyDrops)): "
              + toasts.filter { $0.contains("dropship") }.joined(separator: " / "))
        check(infighting == 0 && maxTroops >= 6, "bigfight: the two armies hunting him leave each other be: \(infighting) soldier-seconds aimed at the other army "
              + "(\(nearRivals) soldier-seconds with a rival within 64 blocks; up to \(maxTroops) troops round him); " + log.joined(separator: "; "))
    }
}
