import Foundation
import simd

// Battles you can join (backlog T12, the C2 leftover). Near an active front (within 120 blocks of the line, WarFront)
// the two countries' soldiers now meet in the flesh: every few minutes a squad of each side marches up to the line
// near you, 32 blocks apart, and they fight it out (soldiers of different factions engage each other on sight:
// CapitalShips.nearestFoe). Both sides leave you alone at first; shoot one side and you have joined the other (the side
// you hurt fires back, the other keeps holding fire: FactionRep.repAllied). When one side is wiped out the winner's
// country gains strength on the war map and the loser's loses it (WarFront.addMight), more when you fought in it.
// Walk off 260 blocks or let five minutes pass and the battle breaks off. Battle soldiers count for their countries,
// not for the Capital or Greywall standing (FactionRep.repSoldierKilled skips them).
enum FrontBattle {
    final class Battle {
        let war: String
        let sides: [Country]
        var mobs: [[Mob]]
        var angered: Set<Int> = []
        var kills = [0, 0]
        let start: Double
        let at: V3
        init(war: String, sides: [Country], mobs: [[Mob]], start: Double, at: V3) {
            self.war = war; self.sides = sides; self.mobs = mobs; self.start = start; self.at = at
        }
    }
    static var current: Battle?
    static var next: Double = 90
    static var fought = 0, decided = 0              // counters (harness)
    static let near: Float = 120
    static let gap: Float = 16                      // each squad starts this far its own side of the line
    static let squad = ["soldier_officer", "soldier_trooper", "soldier_trooper", "soldier_trooper", "soldier_marksman"]
    static let ranks = ["Officer", "Rifleman", "Rifleman", "Rifleman", "Marksman"]

    static func side(_ m: Mob) -> Int? {
        guard let b = current else { return nil }
        for i in 0..<2 where b.mobs[i].contains(where: { $0 === m }) { return i }
        return nil
    }
}

extension Game {
    // Once a second (Countries.tick, after the war ambience).
    func frontBattleTick() {
        if let b = FrontBattle.current { frontBattleWatch(b); return }
        guard clock >= FrontBattle.next, dim.dim == .overworld, alive, !Countries.state.wars.isEmpty else { return }
        FrontBattle.next = clock + 60
        let p = player.pos
        // P203: no battle squads at a Greywall base (they read as its guards coming back after it was cleared).
        if let sc = world.gen.structures, let gs = sc.nearestIfReady(Greywall.kind, x: Int(p.x), z: Int(p.z)) {
            let (gx, gz) = Greywall.centre(gs)
            if simd_length(V2(p.x - Float(gx), p.z - Float(gz))) < 260 { return }
        }
        // R23: nor at a Capital citadel (a Greywall-coloured squad marching through its garrison read as one mixed base).
        if bases.records.values.contains(where: { simd_length(V2(p.x - Float($0.cx), p.z - Float($0.cz))) < 260 }) { return }
        let here = Countries.at(self, p)
        for n in Countries.neighbours(self, here) {
            let k = Countries.warKey(here.key, n.key)
            guard Countries.state.wars[k] != nil else { continue }
            let L = WarFront.line(here, n)
            let f = WarFront.front(k)
            guard abs(L.s(p.x, p.z) - f) < FrontBattle.near else { continue }
            guard Rand.float(in: 0..<1) < 0.5 else { return }
            let t = simd_dot(V2(p.x, p.z) - L.mid, L.along) + Rand.float(in: -30...30)
            let c = L.point(f, t)
            guard world.isLoaded(Int(floor(c.x)), Int(floor(c.y))), simd_length(c - V2(p.x, p.z)) < 110 else { return }
            var mobsBySide: [[Mob]] = [[], []]
            for (i, country) in [L.lo, L.hi].enumerated() {
                let sgn: Float = i == 0 ? -1 : 1                         // lo holds the ground below the line
                for (j, key) in FrontBattle.squad.enumerated() {
                    let q = L.point(f + sgn * (FrontBattle.gap + Float(j % 2) * 3), t + Float(j - 2) * 3)
                    let x = Int(floor(q.x)), z = Int(floor(q.y))
                    guard world.isLoaded(x, z) else { continue }
                    let top = world.topY(x, z)
                    if Blocks.isLiquid(world.rawBlock(x, top, z)) { continue }
                    guard let m = Mob.structureMob(key + (i == 1 ? "@grey" : ""), at: V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)) else { continue }
                    m.persistent = false
                    m.leash = nil
                    m.customName = "\(country.name) \(FrontBattle.ranks[j])"
                    m.soldierBrain.ready = true
                    let foe = L.point(f - sgn * FrontBattle.gap, t)
                    m.soldierBrain.lastSeen = V3(foe.x, Float(top + 1), foe.y); m.soldierBrain.seenAgo = 0
                    mobs.mobs.append(m)
                    mobsBySide[i].append(m)
                }
            }
            guard !mobsBySide[0].isEmpty && !mobsBySide[1].isEmpty else {
                for m in mobsBySide.flatMap({ $0 }) { m.health = -2000 }
                mobs.mobs.removeAll { $0.health == -2000 }
                return
            }
            FrontBattle.current = FrontBattle.Battle(war: k, sides: [L.lo, L.hi], mobs: mobsBySide, start: clock,
                                                     at: V3(c.x, p.y, c.y))
            FrontBattle.fought += 1
            onToast?("\(L.lo.name) and \(L.hi.name) soldiers are fighting on the front nearby: shoot one side to fight for the other")
            sfx(.shipCannon, 0.7, at: V3(c.x, p.y, c.y))
            return
        }
    }

    private func frontBattleWatch(_ b: FrontBattle.Battle) {
        for i in 0..<2 {
            // The side you hurt now fights you too.
            if !b.angered.contains(i), b.mobs[i].contains(where: { clock - $0.playerHurtAt < 2 }) {
                b.angered.insert(i)
                if !b.angered.contains(1 - i) { onToast?("You've joined the battle on \(b.sides[1 - i].name)'s side") }
            }
            b.mobs[i].removeAll { d in d.health <= 0 || !mobs.mobs.contains(where: { $0 === d }) }
        }
        let far = simd_length(V2(player.pos.x - b.at.x, player.pos.z - b.at.z)) > 260
        let over = b.mobs[0].isEmpty || b.mobs[1].isEmpty
        guard over || far || clock - b.start > 300 else { return }
        if over && !(b.mobs[0].isEmpty && b.mobs[1].isEmpty) {
            let w = b.mobs[0].isEmpty ? 1 : 0
            let joined = b.angered == [1 - w] && b.kills[1 - w] > 0
            WarFront.addMight(b.sides[w], joined ? 10 : 5)
            WarFront.addMight(b.sides[1 - w], joined ? -10 : -5)
            FrontBattle.decided += 1
            onToast?("\(b.sides[w].name) holds the field\(joined ? ": you fought with them, and their line is stronger for it" : "")")
        } else if far {
            for m in b.mobs.flatMap({ $0 }) { m.health = -2000 }        // out of sight: the battle moved on
            mobs.mobs.removeAll { $0.health == -2000 }
        }
        FrontBattle.current = nil
        FrontBattle.next = clock + 180
    }

    // A battle soldier's death (from repSoldierKilled): counted for the battle, not the faction standing.
    func frontBattleKilled(_ m: Mob) -> Bool {
        guard let b = FrontBattle.current, let i = FrontBattle.side(m) else { return false }
        if m.killedByPlayer { b.kills[i] += 1; b.angered.insert(i); WarFront.addMight(b.sides[i], -2) }
        return true
    }
}
