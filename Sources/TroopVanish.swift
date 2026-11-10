import Foundation
import simd

// Week plan item 27 ("troops don't vanish: sweep for soldiers disappearing at some view angles or distances; fix every
// cause"). Every soldier (a Capital rank, a deck gun, anything with a soldier's brain) taken out of the world without
// dying is noted here with the rule that took it and whether he could see it then: in front of him (inside a 60 degree
// cone round his look) with nothing between his eye and its head. One seen going is a soldier vanishing in plain sight.
// The frame soak, the launch and --vanishcheck print the tally.
enum TroopVanish {
    static var on = false
    private(set) static var counts: [String: (all: Int, seen: Int)] = [:]
    private(set) static var seenNotes: [String] = []

    static func troop(_ m: Mob) -> Bool { m.kind.steelhold || m.brain != nil }

    static func reset() { counts = [:]; seenNotes = [] }

    // `rule`: what took it (despawn far, despawn random, dawn, rout, unload).
    static func note(_ m: Mob, _ rule: String, _ g: Game) {
        guard on, troop(m) else { return }
        let eye = g.player.eye
        let head = m.pos + V3(0, m.height * 0.9, 0)
        let to = head - eye
        let d = simd_length(to)
        let inCone = d > 0.01 && simd_dot(to / d, g.player.look) > 0.5
        let seen = inCone && d < Float(g.world.renderDistance * CS) && g.world.canSee(eye, head)
        var c = counts[rule] ?? (0, 0)
        c.all += 1
        if seen { c.seen += 1 }
        counts[rule] = c
        if seen && seenNotes.count < 12 {
            seenNotes.append(String(format: "%@ %@ at %.0f blocks", m.kind.key, rule, d))
        }
    }

    static var line: String {
        if counts.isEmpty { return "no soldier left the world without dying" }
        let parts = counts.keys.sorted().map { k -> String in
            let c = counts[k]!
            return "\(k) \(c.all) (\(c.seen) in plain sight)"
        }
        return parts.joined(separator: ", ") + (seenNotes.isEmpty ? "" : "; seen: " + seenNotes.joined(separator: "; "))
    }
}
