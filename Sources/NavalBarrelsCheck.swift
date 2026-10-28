import Foundation
import simd

// P477 (Oct 27 19:21, "Big, medium, and small gun barrels, and then fit them into the current naval gun systems we
// have. Or all gun systems"): questcheck --navalbarrels builds every Capital warship's turrets and the world's own
// vessels, and checks that each gun is a breech with bored barrels laid on from it (a calibre on every cannon), that
// the crews lay it for its own flat shell, and that one volley leaves as that shell at the mount's own punch (the
// same gun on a hull he built hits with the barrels' full punch).
enum NavalBarrelsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let high = g.player.pos + V3(0, 90, 0)
        func volley(_ t: Ship) -> [Shell] {
            let n0 = w.ships.shells.count
            t.reload = 0
            _ = w.ships.fire(t, pitch: 0, game: nil)
            let out = Array(w.ships.shells.dropFirst(n0))
            w.ships.shells.removeLast(w.ships.shells.count - n0)
            return out
        }
        // Capital warships (built as the world builds them, not put in the world).
        for (kind, hb, faction) in [("crawler", Capital.crawler(), Faction.ironback), ("dropship", Capital.dropship(), .stormwarden),
                                    ("capfrigate", Capital.capitalFrigate(), .meridian), ("warfrigate", Capital.frigate(), .stormwarden)] {
            let ships = Capital.makeShips(hb, ids: (0..<24).map { 950_000 + $0 }, name: kind, role: kind, faction: faction)
            let guns = ships.dropFirst().filter { !$0.cannons.isEmpty }
            var bare = 0, unlaid = 0, wrong: [String] = []
            for t in guns {
                t.pos = high; t.prevPos = high
                if t.cannonCalibre.contains(0) { bare += 1 }
                let (v, gr) = t.shellFlight
                if kind != "dropship" && (abs(t.gunSpeed - v) > 0.01 || abs(t.gunGravity - gr) > 0.01) { unlaid += 1 }
                for sh in volley(t) where sh.kind != 6 || abs(sh.power - t.gunPower) > 0.001 || abs(simd_length(sh.vel) - v) > 0.5 {
                    wrong.append(String(format: "kind %d power %.2f/%.2f speed %.0f/%.0f", sh.kind, sh.power, t.gunPower, simd_length(sh.vel), v))
                }
            }
            let cals = Set(guns.flatMap { $0.cannonCalibre }).sorted(), tubes = Set(guns.flatMap { $0.cannonLength }).sorted()
            check(!guns.isEmpty && bare == 0 && unlaid == 0 && wrong.isEmpty,
                  "navalbarrels: \(kind): \(guns.count) gun mounts, calibres \(cals), tubes \(tubes); \(bare) without barrels, \(unlaid) laid for another shell, volleys off: \(wrong.prefix(3))")
        }
        // The world's own vessels (crewed at their mounts' own punch), and the same siege gun on a hull he built.
        for (kind, role) in [(NavalPatrol.role, NavalPatrol.role), ("sloop", "sloop"), ("frigate", "frigate"), ("carriage", "carriage"), ("his carriage", "")] {
            let bp: Blueprint = kind == NavalPatrol.role ? NavalPatrol.destroyer() : kind == "sloop" ? Corsairs.sloop()
                : kind == "frigate" ? Vessels.frigate() : Vessels.carriage()
            let s = w.ships.spawn(bp, at: high + V3(0, 30, 0), yaw: 0, name: kind, role: role)
            defer { w.ships.remove(s) }
            let guns = w.ships.turrets(of: s).filter { !$0.cannons.isEmpty }
            var bare = 0, powers: [Float] = [], kinds = Set<Int>()
            for t in guns {
                if t.cannonCalibre.contains(0) { bare += 1 }
                for sh in volley(t) { powers.append(sh.power); kinds.insert(sh.kind) }
            }
            let want: Float = role.isEmpty ? CannonCalibre.maxPower : Ship(id: -1, grid: ShipGrid(sx: 1, sy: 1, sz: 1)).gunPower
            check(guns.count == bp.turrets.count && bare == 0 && kinds == [6] && !powers.isEmpty && powers.allSatisfy { abs($0 - want) < 0.001 },
                  "navalbarrels: \(kind): \(guns.count) of \(bp.turrets.count) turrets armed, \(bare) without barrels, shells \(kinds.sorted()) at power \(Set(powers).sorted()) (want \(want))")
        }
    }
}
