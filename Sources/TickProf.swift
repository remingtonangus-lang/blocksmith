import Foundation

// Where a slow game tick went: Game.tickSeat / advance mark their stages here (no allocation: fixed arrays of
// StaticString names). The frame loops (Quest perf line, the bench) read the slowest stage of the slowest tick, so a
// device log names the cause of a hitch instead of just "tick 60 ms".
enum TickProf {
    static let cap = 96
    private(set) static var names = [StaticString](repeating: "", count: cap)
    private(set) static var times = [Double](repeating: 0, count: cap)
    private(set) static var count = 0
    private static var last = 0.0

    @inline(__always) static func begin() { count = 0; last = CFAbsoluteTimeGetCurrent() }

    // The time since the previous mark (or begin) is charged to `name`.
    @inline(__always) static func mark(_ name: StaticString) {
        let t = CFAbsoluteTimeGetCurrent()
        if count < cap { names[count] = name; times[count] = t - last; count += 1 }
        last = t
    }

    // The slowest stage of the tick just run: (name, ms).
    static func top() -> (StaticString, Double) {
        var bi = -1, bt = 0.0
        for i in 0..<count where times[i] > bt { bi = i; bt = times[i] }
        return bi < 0 ? ("-", 0) : (names[bi], bt * 1000)
    }

    // The two slowest stages, "name 12.3 + name 4.5" (for logs).
    static func summary() -> String {
        var a = -1, b = -1
        for i in 0..<count {
            if a < 0 || times[i] > times[a] { b = a; a = i } else if b < 0 || times[i] > times[b] { b = i }
        }
        guard a >= 0 else { return "-" }
        var s = "\(names[a].description) \(String(format: "%.1f", times[a] * 1000))"
        if b >= 0 { s += " + \(names[b].description) \(String(format: "%.1f", times[b] * 1000))" }
        return s
    }
}
