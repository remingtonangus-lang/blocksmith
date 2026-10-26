import Foundation
import simd

// P460's Boreal vehicles check (questcheck --borealcars): a Capital Boreal Station's own trucks and tank come as the
// Capital's (faction, names, winter colours), keep it through a save, and a crew bailing out of one is the Capital's.
enum BorealCarsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let at = g.player.pos
        var made: [Mob] = []
        for (k, _, _) in BorealStation.vehicles {
            guard let m = Mob.structureMob(k, at: at) else { check(false, "borealcars: \(k) makes a mob"); continue }
            made.append(m)
        }
        check(made.count == 3 && made.allSatisfy { $0.boreal && $0.faction == Faction.steelhold.rawValue },
              "borealcars: a Boreal Station keeps \(made.map { $0.spec.name }.joined(separator: ", ")), the Capital's")
        if let t = made.first(where: { $0.kind == .ashTank }) {
            let ash = Mob(.ashTank, at: at)
            let a = ashVehicleParts(ash).map { $0.color }, b = ashVehicleParts(t).map { $0.color }
            let pale = b.filter { $0.x > 0.4 && $0.y > 0.4 && $0.z > 0.4 }.count, paleAsh = a.filter { $0.x > 0.4 && $0.y > 0.4 && $0.z > 0.4 }.count
            check(pale > paleAsh + 10, "borealcars: the Boreal Tank is drawn in winter white (\(pale) pale parts, the Ashguard's \(paleAsh))")
            if let back = Mob.from(t.record) {
                check(back.boreal && back.spec.name == t.spec.name, "borealcars: saved and loaded it stays the \(back.spec.name) (faction \(back.faction))")
            } else { check(false, "borealcars: the tank's record loads") }
        }
        if let tr = made.first(where: { $0.kind == .ashTruck }) {
            let n0 = g.mobs.mobs.count
            g.mobs.mobs.append(tr)
            g.ashEmpty(tr)
            let crew = g.mobs.mobs.dropFirst(n0 + 1)
            check(!crew.isEmpty && crew.allSatisfy { $0.faction != Faction.ashguard.rawValue },
                  "borealcars: its crew of \(crew.count) climbs out as the Capital's soldiers")
            g.mobs.mobs.removeLast(g.mobs.mobs.count - n0)
        }
        // Knocked out on the surface it brews up and breaks into white plate (the Ashguard's did only below).
        if let t = made.first(where: { $0.kind == .ashTank }) {
            let n0 = g.mobs.mobs.count, d0 = g.debris.bodies.count
            t.health = 0
            g.mobDied(t)
            let crew = g.mobs.mobs.dropFirst(n0)
            check(g.dim.dim != .deep && g.debris.bodies.count > d0 && crew.allSatisfy { $0.faction != Faction.ashguard.rawValue },
                  "borealcars: a Boreal Tank knocked out on the surface breaks into \(g.debris.bodies.count - d0) pieces, its \(crew.count) crew the Capital's")
            g.mobs.mobs.removeLast(g.mobs.mobs.count - n0)
        }
    }
}
