import Foundation
import simd

// Week plan item 71 ("no pop-in: the passenger train and other spawns never appear in plain sight"), the other side of
// item 27 (TroopVanish). Every mob that comes into the world while a harness has this on is noted by what it is and
// whether he could see the spot it came in at (MobManager.inPlainSight) well inside the drawn view (24 blocks short of
// its edge, where the ground itself is still coming in). One seen is a spawn popping in in front of him.
// The frame soak prints the tally (from its fourth second: the scene's own setup is not a spawn).
enum PopIn {
    private(set) static var on = false
    private(set) static var counts: [String: (all: Int, seen: Int)] = [:]
    private(set) static var seenNotes: [String] = []

    // From now on (the mobs already in the world are not new).
    static func arm(_ g: Game) {
        counts = [:]; seenNotes = []
        for m in g.mobs.mobs { m.popNoted = true }
        on = true
    }
    static func disarm() { on = false }

    static func label(_ m: Mob) -> String {
        var s = m.kind.key
        if m.posse != 0 { s += " posse \(m.posse)" }
        if Trains.isCar(m) { s += " (train car)" }
        if m.deck != nil { s += " (aboard)" }
        return s
    }

    static func note(_ m: Mob, _ g: Game) {
        let d = simd_length(m.pos + V3(0, m.height * 0.9, 0) - g.player.eye)
        let seen = d < Float(g.world.renderDistance * CS - 24) && MobManager.inPlainSight(m, g)
        let k = label(m)
        var c = counts[k] ?? (0, 0)
        c.all += 1
        if seen { c.seen += 1 }
        counts[k] = c
        if seen && seenNotes.count < 12 { seenNotes.append(String(format: "%@ at %.0f blocks", k, d)) }
    }

    static var line: String {
        if counts.isEmpty { return "no mob came into the world" }
        let seen = counts.values.reduce(0) { $0 + $1.seen }, all = counts.values.reduce(0) { $0 + $1.all }
        let top = counts.sorted { $0.value.all > $1.value.all }.prefix(8).map { "\($0.key) \($0.value.all) (\($0.value.seen) seen)" }
        return "\(all) came in, \(seen) in plain sight: " + top.joined(separator: ", ")
            + (seenNotes.isEmpty ? "" : "; seen: " + seenNotes.joined(separator: "; "))
    }
}
