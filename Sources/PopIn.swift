import Foundation
import simd

// Nov 4 (week item 71, no pop-in; bug ledger 13, 15, 16): things made near him to come at him (trains, vessels,
// dropships, the Reckoning's warship and crawler) were made at fixed distances, inside the fog past view 8 (it ends
// 16 x view - 12 out), so they appeared out of nothing in plain sight.
extension World {
    // How far off a thing `size` blocks from its middle to its near end is made so all of it is past the fog at his view.
    func pastFog(_ least: Float, size: Float = 0) -> Float { max(least, Float(renderDistance * CS) - 4 + size) }
}

extension Game {
    // Where he looks across: the headset's yaw in VR, else the body's.
    var lookYaw: Float { vrHeadYaw ?? player.yaw }
    // Item 27/71: where his eyes point, the headset's own direction in VR (player.look follows the hand's aim there).
    var viewLook: V3 {
        let y = lookYaw, p = vrHeadPitch ?? player.pitch
        return V3(-sinf(y) * cosf(p), sinf(p), -cosf(y) * cosf(p))
    }
    // Could he see a thing at `at` reaching `halfWidth` to each side from where he stands? Within 70 degrees of his
    // look either way (Quest 3 shows about 55 each side; the rest for a turn of the head while it's made) plus its width.
    func inSight(_ at: V2, halfWidth: Float = 0) -> Bool {
        let p = V2(player.pos.x, player.pos.z), to = at - p, d = simd_length(to)
        if d < 1 { return true }
        let look = V2(-sinf(lookYaw), -cosf(lookYaw))
        let off = acosf(max(-1, min(1, simd_dot(look, to / d))))
        return off < 70 * .pi / 180 + atanf(halfWidth / d)
    }
}

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
