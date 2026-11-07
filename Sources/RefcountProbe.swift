import Foundation

// Item 8 (Nov 8): which of the game's busiest objects carry a weak-reference side table. Any weak reference ever made to
// an object gives it one for life, and from then on every retain and release of it takes the runtime's slow path
// (callgrind of the worst-case soak: a fifth of all reference counting). BS_RCPROBE=1 prints the census per soak scene.
enum RefcountProbe {
    // The object's reference-count word (64-bit runtimes): the top two bits both set = the count lives in a side table.
    static func slow(_ o: AnyObject) -> Bool {
        let p = Unmanaged.passUnretained(o).toOpaque()
        let bits = p.load(fromByteOffset: 8, as: UInt64.self)
        return bits >> 62 == 3
    }
    static func census(_ g: Game) -> String {
        func frac<T: AnyObject>(_ name: String, _ list: [T]) -> String {
            "\(name) \(list.filter { slow($0) }.count)/\(list.count)"
        }
        let w = g.world
        var parts: [String] = []
        parts.append("world \(slow(w) ? "slow" : "fast")")
        parts.append("game \(slow(g) ? "slow" : "fast")")
        parts.append("ships manager \(slow(w.ships) ? "slow" : "fast")")
        parts.append("player \(slow(g.player) ? "slow" : "fast")")
        parts.append(frac("mobs", g.mobs.mobs))
        parts.append(frac("ships", w.ships.list))
        parts.append(frac("chunks", Array(w.chunks.values)))
        return parts.joined(separator: ", ")
    }
}
