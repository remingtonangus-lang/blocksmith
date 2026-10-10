import Foundation

// Auto Render Distance (Quest comfort option): a two-way controller fed one window of frame statistics at a time
// (QuestApp's FrameStats, every 5 s). Pure value type, no clocks or globals, so a synthetic frame-time trace can drive
// it in a test (`Blocksmith --rdgovernortest`, QuestSim's rdgovernor case).
//
// Down: two windows in a row (10 s) that miss frames (> 5%) with the CPU or GPU near the budget (> 80%) take one step
// off, not below `floor`. A single hitch, a chunk-loading burst (fast flight, a raise's new ring), a menu, a pause or
// a save is not evidence: those windows count neither way.
// Up: once the frame has headroom for `hold` seconds (no missed frames, and the busier of CPU and GPU, scaled by the
// next step's extra area ((rd+1)/rd)^2, still under 70% of the budget) it takes one step back up, never above the
// player's chosen distance. Hysteresis: the raise test (70% after scaling) sits well below the drop test (80%), every
// step waits a settle time, and a drop soon after a raise doubles the hold (up to 5 min) so a scene on the edge does
// not see-saw; five quiet minutes back at the chosen distance reset it.
// Only `chosen` is the player's setting (saved); `current` is session state and is never written anywhere.
struct RenderDistanceGovernor {
    struct Window {
        var seconds: Double            // window length
        var frames: Int
        var missed: Int                // frames over 1.5x the budget
        var cpuMs: Double              // mean CPU frame time (tick + record)
        var gpuMs: Double              // mean GPU frame time
        var budgetMs: Double           // 1000 / refresh rate
        var loading = false            // chunk-loading burst in the window
        var excused = false            // a menu, pause, save or dimension change in the window
    }
    enum Action: Equatable { case none, lowerRate, lower(Int), raise(Int) }

    private(set) var chosen: Int
    private(set) var current: Int
    let floor: Int
    // Tunables (seconds and budget fractions).
    static let missFrac = 0.05, busyFrac = 0.8, raiseFrac = 0.7
    static let badToDrop = 2, settle = 10.0, baseHold = 20.0, maxHold = 300.0, failWindow = 60.0, calmReset = 300.0
    private(set) var hold = RenderDistanceGovernor.baseHold
    private var badStreak = 0, good = 0.0, sinceChange = 1e9, sinceRaise = 1e9, sinceDrop = 1e9

    init(chosen: Int, floor: Int = 4) {
        self.chosen = chosen; self.current = chosen; self.floor = min(floor, chosen)
    }

    var lowered: Bool { current < chosen }

    // The player picked a distance (pause menu): it is the new ceiling and the current distance; history is cleared.
    mutating func setChosen(_ rd: Int) {
        chosen = rd; current = rd
        badStreak = 0; good = 0; sinceChange = 1e9; sinceRaise = 1e9; sinceDrop = 1e9; hold = Self.baseHold
    }

    // Whether a window is a sustained miss at the budget / has room for one more step.
    static func isBad(_ w: Window) -> Bool {
        w.frames > 0 && Double(w.missed) > Double(w.frames) * missFrac && max(w.cpuMs, w.gpuMs) > w.budgetMs * busyFrac
    }
    static func hasRoom(_ w: Window, at rd: Int) -> Bool {
        let grow = Double(rd + 1) / Double(max(1, rd))
        let need: Double = max(w.cpuMs, w.gpuMs) * grow * grow
        return w.frames > 0 && w.missed * 100 <= w.frames && need < w.budgetMs * raiseFrac
    }

    // One window in; what to do. `canLowerRate`: the display runs above 72 Hz and the host can drop it (the first
    // step down, before any distance). The host applies .lower/.raise by setting the world's distance to the value.
    mutating func observe(_ w: Window, canLowerRate: Bool = false) -> Action {
        sinceChange += w.seconds; sinceRaise += w.seconds; sinceDrop += w.seconds
        // Five minutes at the choice since the last step either way: forget the backoff.
        if current == chosen && sinceDrop > Self.calmReset && sinceRaise > Self.calmReset { hold = Self.baseHold }
        if w.excused || w.loading || sinceChange < Self.settle { return .none }
        if Self.isBad(w) {
            good = 0
            badStreak += 1
            guard badStreak >= Self.badToDrop else { return .none }
            badStreak = 0
            if canLowerRate { sinceChange = 0; return .lowerRate }
            guard current > floor else { return .none }
            current -= 1
            // Dropping again soon after a raise: that step did not fit; wait longer before the next try.
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            return .lower(current)
        }
        badStreak = 0
        guard current < chosen, Self.hasRoom(w, at: current) else { good = 0; return .none }
        good += w.seconds
        guard good >= hold else { return .none }
        current += 1
        good = 0; sinceChange = 0; sinceRaise = 0
        return .raise(current)
    }

    // The host could not lower the refresh rate after .lowerRate: take the distance step instead.
    mutating func rateUnavailable() -> Action {
        guard current > floor else { return .none }
        current -= 1
        if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
        sinceChange = 0; sinceDrop = 0
        return .lower(current)
    }
}

// Synthetic traces for the controller (Mac `--rdgovernortest`, QuestSim). Returns the number of failed checks.
enum RenderDistanceGovernorTest {
    // A scene whose frame cost grows with the drawn area: base + k * rd^2 (ms); 5 s windows at 72 Hz. Frames over
    // 1.5x the budget are "missed" when the mean is over the budget (a crude but monotonic model).
    static func window(cost: Double, budget: Double = 1000.0 / 72, loading: Bool = false, excused: Bool = false) -> RenderDistanceGovernor.Window {
        let frames = 360
        let over = cost / budget
        let missed = over <= 0.9 ? 0 : Int(Double(frames) * min(1, (over - 0.9) * 2))
        return .init(seconds: 5, frames: frames, missed: missed, cpuMs: cost * 0.8, gpuMs: cost, budgetMs: budget, loading: loading, excused: excused)
    }

    static func run(log: (String) -> Void = { print($0) }) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ what: String) { log("  \(ok ? "ok  " : "FAIL") \(what)"); if !ok { fails += 1 } }
        func cost(_ base: Double, _ k: Double, _ rd: Int) -> Double { base + k * Double(rd * rd) }

        // 1. A heavy stretch (town at 16 costs 16 ms) for 60 s, then normal play (16 costs 9 ms) for 6 minutes.
        var g = RenderDistanceGovernor(chosen: 16)
        var trace: [Int] = [], toasts: [String] = []
        for i in 0..<84 {
            let heavy = i < 12
            let c = heavy ? cost(6, 10.0 / 256, g.current) : cost(4, 5.0 / 256, g.current)
            switch g.observe(window(cost: c)) {
            case .raise(let r): toasts.append("up \(r)")
            case .lower(let r): toasts.append("down \(r)")
            default: break
            }
            trace.append(g.current)
        }
        let minRD = trace.min() ?? 16
        let steps = (1..<trace.count).map { (trace[$0] - trace[$0 - 1]).signum() }.filter { $0 != 0 }
        let changes = steps.isEmpty ? 0 : (1..<steps.count).filter { steps[$0] != steps[$0 - 1] }.count
        log("trace 1 (heavy 60 s, then light): " + trace.map(String.init).joined(separator: " "))
        check(minRD < 16, "a sustained heavy stretch lowers the distance (min \(minRD))")
        check(trace.last == 16, "it climbs back to the chosen 16 once there is headroom (end \(trace.last ?? 0))")
        check(trace.allSatisfy { $0 <= 16 }, "never above the chosen distance")
        check(changes <= 1, "one way down then one way up, no oscillation (\(changes) direction changes)")
        check(toasts.contains { $0.hasPrefix("up") }, "raises are reported (toast)")

        // 2. A single bad window (a hitch), loading bursts, menus: no drop.
        g = RenderDistanceGovernor(chosen: 16)
        let heavy = window(cost: 16)
        _ = g.observe(heavy); _ = g.observe(window(cost: 9))
        _ = g.observe(heavy); _ = g.observe(window(cost: 9))
        check(g.current == 16, "isolated bad windows do not lower it")
        for _ in 0..<10 { _ = g.observe(window(cost: 16, loading: true)) }
        check(g.current == 16, "chunk-loading bursts (fast flight) do not lower it")
        for _ in 0..<10 { _ = g.observe(window(cost: 16, excused: true)) }
        check(g.current == 16, "menus, pauses and saves do not lower it")

        // 3. An edge scene: 16 misses, 15 looks like it has room for 16 (the area model is optimistic here), so every raise
        // fails. 20 minutes: the backoff must stop it see-sawing every few windows.
        g = RenderDistanceGovernor(chosen: 16)
        var raiseAt: [Int] = [], drops = 0, missedWindows = 0
        for i in 0..<240 {
            let c: Double = g.current >= 16 ? 14.5 : (g.current == 15 ? 8.5 : 7.0)
            let w = window(cost: c)
            if RenderDistanceGovernor.isBad(w) { missedWindows += 1 }
            switch g.observe(w) { case .raise: raiseAt.append(i * 5); case .lower: drops += 1; default: break }
        }
        let gaps = zip(raiseAt.dropFirst(), raiseAt).map { $0 - $1 }
        log("trace 3 (edge scene, 20 min): \(drops) drops, raises at \(raiseAt.map { "\($0) s" }.joined(separator: ", ")), ends at \(g.current), hold \(Int(g.hold)) s")
        check(zip(gaps.dropFirst(), gaps).allSatisfy { $0 >= $1 }, "retries back off: the gaps between raises grow (\(gaps))")
        check(raiseAt.filter { $0 >= 600 }.count <= 2, "after the backoff, at most one retry every 5 minutes")
        check(missedWindows <= 24, "frames are missed in at most 10% of the windows (\(missedWindows) of 240)")
        check(g.current >= 15, "and it stays at the best fitting distance (\(g.current))")

        // 4. The player's choice is the ceiling and resets the state; the refresh rate goes first.
        g = RenderDistanceGovernor(chosen: 16)
        _ = g.observe(heavy, canLowerRate: true)
        check(g.observe(heavy, canLowerRate: true) == .lowerRate, "above 72 Hz, the first step lowers the refresh rate")
        g.setChosen(12)
        check(g.current == 12 && g.chosen == 12, "a menu choice sets both the ceiling and the distance")
        for _ in 0..<60 { _ = g.observe(window(cost: 4)) }
        check(g.current == 12, "headroom never raises it above the chosen distance")
        var f = RenderDistanceGovernor(chosen: 5)
        for _ in 0..<40 { _ = f.observe(window(cost: 30)) }
        check(f.current == 4, "never below the floor (4)")
        log("rdgovernor: \(fails == 0 ? "PASS" : "FAIL (\(fails))")")
        return fails
    }

    // A game with a governor stepped down: the save (meta) and the pause menu keep the player's choice, a menu choice
    // resets the ceiling. Leaves the game as it found it. Returns the number of failed checks.
    static func gameChecks(_ g: Game, log: (String) -> Void = { print($0) }) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ what: String) { log("  \(ok ? "ok  " : "FAIL") \(what)"); if !ok { fails += 1 } }
        let keep = (g.rdGovernor, g.world.renderDistance, g.onRenderDistanceChanged)
        g.onRenderDistanceChanged = nil
        var gov = RenderDistanceGovernor(chosen: 16)
        g.world.renderDistance = 16
        for _ in 0..<12 { if case .lower(let rd) = gov.observe(window(cost: 16)) { g.world.renderDistance = rd } }
        g.rdGovernor = gov
        check(g.world.renderDistance < 16, "the game's world steps down (\(g.world.renderDistance))")
        check(g.meta.renderDistance == 16, "the save keeps the chosen 16, not the stepped-down \(g.world.renderDistance)")
        check(g.chosenRenderDistance == 16 && PauseMenu.rdLabel(g).hasPrefix("Render Distance: 16 (auto"),
              "the menu shows the choice and the current distance (\(PauseMenu.rdLabel(g)))")
        g.setRenderDistance(12)
        check(g.world.renderDistance == 12 && g.chosenRenderDistance == 12 && g.meta.renderDistance == 12,
              "a menu choice sets the world, the ceiling and the save")
        g.rdGovernor = keep.0
        g.world.renderDistance = keep.1
        g.onRenderDistanceChanged = keep.2
        log("rdgovernor game: \(fails == 0 ? "PASS" : "FAIL (\(fails))")")
        return fails
    }
}
