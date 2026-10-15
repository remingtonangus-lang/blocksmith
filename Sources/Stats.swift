import Foundation
import simd

// Q2c-console-57: the world's statistics (Pause > Statistics): what he has done in this world, saved with it in the
// world extras ("stats"). Counters are plain additions where things happen (mining, placing, kills, deaths, crafting,
// eating, fishing); time and distance once per game tick. A world saved before this counts from its next load.
enum Stats {
    private(set) static var c: [String: Double] = [:]
    private static var lastPos: V3?
    static func add(_ k: String, _ n: Double = 1) { c[k, default: 0] += n }
    // Q2c-console-59: this life's length (play time since the last respawn) and the longest one.
    static var life: Double { max(0, (c["time"] ?? 0) - (c["lifeStart"] ?? 0)) }
    static func lifeEnded() { if life > (c["bestLife"] ?? 0) { c["bestLife"] = life } }
    static func lifeBegan() { c["lifeStart"] = c["time"] ?? 0 }
    // The play time in a saved world's extras string (nil when it has none), for the worlds list.
    static func playedIn(_ s: String?) -> Double? {
        guard let s else { return nil }
        for kv in s.split(separator: ";") where kv.hasPrefix("time=") { return Double(kv.dropFirst(5)) }
        return nil
    }

    static func encode() -> String { c.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";") }
    static func decode(_ s: String?) {
        c = [:]; lastPos = nil
        for kv in (s ?? "").split(separator: ";") {
            let p = kv.split(separator: "=")
            if p.count == 2, let v = Double(p[1]) { c[String(p[0])] = v }
        }
    }

    // Once per game tick (20 a second): play time, and the distance moved on foot or riding (a teleport, a respawn or
    // a portal jump of more than 8 blocks in one tick isn't distance).
    static func tick(_ g: Game) {
        guard g.alive else { lastPos = nil; return }
        add("time", 0.05)
        let p = g.player.pos
        defer { lastPos = p }
        guard let l = lastPos else { return }
        let d = simd_length(V2(p.x - l.x, p.z - l.z))
        guard d > 0.001 && d < 8 else { return }
        add(g.riding != nil || g.world.ships.aboard != nil || g.world.ships.pilot != nil ? "ride" : "walk", Double(d))
    }

    static func count(_ v: Double) -> String {
        let n = Int(v.rounded())
        guard n >= 1000 else { return "\(n)" }
        var s = "", d = String(n)
        while d.count > 3 { s = "," + String(d.suffix(3)) + s; d = String(d.dropLast(3)) }
        return d + s
    }
    static func distance(_ m: Double) -> String { m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000) }
    static func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    // The page's rows (label, value).
    static func rows(_ g: Game) -> [String] {
        let v = { (k: String) in c[k] ?? 0 }
        return ["Time played: " + duration(v("time")),
                "Days survived: \(Int(g.time / DAY_LENGTH) + 1)",
                "On foot: " + distance(v("walk")) + "   Riding: " + distance(v("ride")),
                "Blocks mined: " + count(v("mined")) + "   Placed: " + count(v("placed")),
                "Creatures defeated: " + count(v("kills")) + "   Deaths: " + count(v("deaths")),
                "Items crafted: " + count(v("crafted")),
                "Food eaten: " + count(v("eaten")) + "   Fish caught: " + count(v("fish")),
                "Longest life: " + duration(max(v("bestLife"), life))]
    }
}
