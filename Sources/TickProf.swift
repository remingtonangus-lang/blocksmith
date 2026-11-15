import Foundation

// Where a slow game tick went: Game.tickSeat / advance mark their stages here (no allocation: fixed arrays of
// StaticString names). The frame loops (Quest perf line, the bench) read the slowest stage of the slowest tick, so a
// device log names the cause of a hitch instead of just "tick 60 ms".
enum TickProf {
    static let cap = 160
    private(set) static var names = [StaticString](repeating: "", count: cap)
    private(set) static var times = [Double](repeating: 0, count: cap)
    private(set) static var count = 0
    private static var last = 0.0
    // P283: the frame savings that change how often something runs (far calm mobs on a slower beat, the far horizon
    // rebuilt every few frames). BS_P283=0 turns them off, so questcheck --perfscenes can measure what they save.
    static let lighter = ProcessInfo.processInfo.environment["BS_P283"] != "0"

    private static var start = 0.0
    private(set) static var tick = 0             // ticks begun (a frame's shared budgets reset on a new one)
    private(set) static var prevTotal = 0.0      // seconds from the last tick's begin to its last mark
    // Nov 15: every stage's time summed over a window of ticks (the headset's 5 s perf line), so the line says where
    // an ordinary tick's time goes, not only what the one slowest tick did. A flat table by first-seen order; a stage
    // is found again at the slot it had last tick (the marks come in the same order nearly every tick).
    private static var accNames = [StaticString](repeating: "", count: cap)
    private static var accKey = [UnsafeRawPointer?](repeating: nil, count: cap)
    private static var accTime = [Double](repeating: 0, count: cap)
    private static var accCount = 0
    private(set) static var accTicks = 0
    private static func fold() {
        var hint = 0
        for i in 0..<count {
            let key = UnsafeRawPointer(names[i].utf8Start)
            var j = -1
            if hint < accCount && accKey[hint] == key { j = hint }
            else { for k in 0..<accCount where accKey[k] == key { j = k; break } }
            if j < 0 {
                guard accCount < cap else { continue }
                j = accCount; accCount += 1
                accKey[j] = key; accNames[j] = names[i]; accTime[j] = 0
            }
            accTime[j] += times[i]
            hint = j + 1
        }
        accTicks += 1
    }
    // The window's `n` costliest stages as average ms a tick, "mobs 2.10, arms 1.40, ..."; starts a new window.
    static func windowTop(_ n: Int) -> String {
        guard accTicks > 0 else { return "-" }
        var order = Array(0..<accCount)
        order.sort { accTime[$0] > accTime[$1] }
        let parts = order.prefix(n).map { "\(accNames[$0].description) \(String(format: "%.2f", accTime[$0] * 1000 / Double(accTicks)))" }
        for k in 0..<accCount { accTime[k] = 0 }
        accTicks = 0
        return parts.joined(separator: ", ")
    }
    // The `n` slowest stages of the tick just run, "name 12.3 + name 4.5 + ...".
    static func topStages(_ n: Int) -> String {
        var order = Array(0..<count)
        order.sort { times[$0] > times[$1] }
        return order.prefix(n).map { "\(names[$0].description) \(String(format: "%.1f", times[$0] * 1000))" }.joined(separator: " + ")
    }

    @inline(__always) static func begin() {
        if start > 0 { prevTotal = last - start; fold() }
        count = 0; last = CFAbsoluteTimeGetCurrent(); start = last; tick &+= 1
    }

    // Seconds since this tick began.
    static var elapsed: Double { CFAbsoluteTimeGetCurrent() - start }

    // The time since the previous mark (or begin) is charged to `name`.
    @inline(__always) static func mark(_ name: StaticString) {
        let t = CFAbsoluteTimeGetCurrent()
        if count < cap { names[count] = name; times[count] = t - last; count += 1 }
        last = t
    }

    // The stage under way (the last one marked: what runs now is charged to the next mark).
    static var after: String { count > 0 ? "after " + names[count - 1].description : "tick start" }

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
