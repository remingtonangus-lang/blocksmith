import Foundation

// Nov 14 (Remington, 00:31: "Anyway to force 72 fps like, it takes priority for compute and if someone else wants to run
// and overflow it it just doesn't because fps takes priority? This is just in case the store rejects us again. Also,
// can we make it so the quest is constantly using all of its compute all the time on something... make that auto
// render perfectly in touch with available compute"; ledger 126).
//
// Until now each kind of work that can wait had a fixed slice of its own (chunk installs 1.5 ms, water 2 ms, carving
// 1.6 ms, random ticks 1.2 ms, the crawler's crush 1.2 ms, falling ground 0.8 ms...): none knew of the others, so a
// frame where several were busy at once ran over, and a quiet frame left its time unused while land waited to be
// installed.
//
// One clock for the frame. The frame loop says when the frame began and how long it may take (`begin`); what the
// frame must do (input, the player, mobs, ships, recording the picture) is not asked; everything that can wait asks
// here what it may take (`grant`) before it runs:
// - never more than the frame has left before its deadline (the display's period, less what recording the picture
//   takes, less a margin), so work that can wait cannot push a frame over;
// - more than its usual slice when the last frames had room to spare (up to `most` times), so a quiet frame's time
//   goes into bringing the world in sooner instead of into nothing;
// - a job that has been refused gets a little all the same after `patience` frames, so nothing stops for ever
//   under a frame that is always full (the world must still load).
// The workers (chunk generation and meshing, JobPool) are told as well: after a late frame fewer of them take new
// jobs for a moment, so the frame's own threads are not kept off the cores; with room, all of them run.
//
// Not armed (the host checks, the Mac, a deterministic run): every grant is the job's usual slice, as before.
// BS_GOVERNOR=0: never armed.
enum FrameGovernor {
    static let enabled = ProcessInfo.processInfo.environment["BS_GOVERNOR"] != "0"
    private(set) static var armed = false

    // The frame under way.
    private(set) static var frame = 0
    private static var start = 0.0                 // when it began (CFAbsoluteTime)
    private(set) static var period = 1.0 / 72      // what it may take, whole
    private static var recordEMA = 0.004           // what recording the picture took lately (after the tick)
    static var margin = 0.0010                     // kept clear before the deadline
    static var floorShare = 0.35                   // the tick is never given less than this share of the period

    // How much of the tick's time the frame's own work left free lately, 0...1 (smoothed), and how many of the last 72
    // frames were late.
    private(set) static var spare = 0.0
    private(set) static var late = 0               // frames over their period, of the last `window`
    private static var lateBits: UInt64 = 0, lateBits2: UInt64 = 0
    static let window = 72

    // Harness and the perf line.
    private(set) static var grants = 0, refused = 0, forced = 0, boosted = 0
    private(set) static var lateTotal = 0, frames = 0
    private(set) static var worstOver = 0.0        // the most a frame ran past its period, seconds

    // The seconds the game's tick may take this frame: the period less the picture's recording and the margin.
    static var tickBudget: Double { max(period * floorShare, period - recordEMA - margin) }

    // What the frame must do whatever happens (the tick less the work that can wait), lately; and this frame's count of
    // the work that can wait so far.
    private(set) static var mustEMA = 0.004
    private static var deferred = 0.0

    // Seconds the work that can wait may still take this frame (never under 0); .infinity when not armed. Early in
    // the tick (the world's streaming runs first) what the frame must still do is not done yet: its usual time is
    // kept back for it; later, what it really took counts.
    @inline(__always) static var left: Double {
        guard armed else { return .infinity }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let must = max(mustEMA * 1.1, elapsed - deferred)
        return max(0, min(tickBudget - elapsed, tickBudget - must - deferred))
    }

    // The frame loop, first thing in a frame: `period` seconds is what the drawn frame may take (the display's period;
    // twice that with space warp).
    static func begin(period p: Double, now: Double = CFAbsoluteTimeGetCurrent()) {
        guard enabled else { return }
        if armed && start > 0 { close(now: now) }
        armed = true
        period = max(1.0 / 144, min(0.1, p))
        start = now
        deferred = 0
        frame &+= 1
    }

    // The frame loop, after the tick: how long the tick took is known here; what is left of its budget is the spare.
    private static var tickEnd = 0.0
    static func ticked(now: Double = CFAbsoluteTimeGetCurrent()) {
        guard armed else { return }
        tickEnd = now
        let used = now - start
        let must = max(0, used - deferred)
        mustEMA = must > mustEMA ? mustEMA * 0.5 + must * 0.5 : mustEMA * 0.9 + must * 0.1
        // (the spare is what the frame's own work leaves: the work that can wait is what is to fill it)
        let free = max(0, min(1, 1 - must / tickBudget))
        // (quick to see a full frame, slow to trust an empty one: one heavy frame takes the boost away at once)
        spare = free < spare ? spare * 0.5 + free * 0.5 : spare * 0.92 + free * 0.08
    }

    // The frame loop, after the picture is recorded and submitted.
    static func recorded(now: Double = CFAbsoluteTimeGetCurrent()) {
        guard armed, tickEnd > 0 else { return }
        let r = max(0, now - tickEnd)
        recordEMA = r > recordEMA ? recordEMA * 0.7 + r * 0.3 : recordEMA * 0.95 + r * 0.05
    }

    private static func close(now: Double) {
        let took = now - start
        frames += 1
        // (late: the frame loop's own work ran past the period; a frame that only waited for the display is not)
        let busy = tickEnd > 0 ? (tickEnd - start) + recordEMA : took
        let over = busy - period
        let wasLate = over > 0
        if wasLate { lateTotal += 1; worstOver = max(worstOver, over) }
        let out = lateBits2 >> 7 & 1                    // (the bit leaving the 72-frame window)
        lateBits2 = (lateBits2 << 1 | lateBits >> 63) & 0xFF
        lateBits = lateBits << 1 | (wasLate ? 1 : 0)
        late += (wasLate ? 1 : 0) - Int(out)
        tickEnd = 0
        JobPool.shared.setHeld(workersHeld)
    }

    // How many of the world's workers take no new job just now: none with room; after late frames a share of them,
    // more the more frames were late, never all (the world must still arrive).
    static var workersHeld: Int {
        guard armed, late > 0 else { return 0 }
        let n = JobPool.shared.workers
        let share = min(0.75, Double(late) / 8)          // (8 late frames in the last second: three quarters held)
        return min(n - 1, Int((Double(n) * share).rounded(.up)))
    }

    // The kinds of work that can wait (each keeps count of the frames it has been refused).
    enum Job: Int, CaseIterable {
        case handover, fluid, lava, randomTicks, gravity, settle, crush, carve, loadCheck, collapse, tip, groundCollapse, ghosts
    }
    private static var starved = [Int](repeating: 0, count: Job.allCases.count)
    private(set) static var took = [Double](repeating: 0, count: Job.allCases.count)        // (seconds, for the soak's line)
    static let patience = 12

    // What a job that can wait may take this frame, in seconds; 0: not this frame. `base`: its usual slice. `most`: how
    // many times that when frames have room. A job refused `patience` frames in a row gets `least` all the same.
    static func slice(_ job: Job, _ base: Double, most: Double = 4, least: Double = 0.0004) -> Double {
        guard armed else { return base }
        grants += 1
        let room = left
        // With room to spare the slice grows: nothing more at a quarter spare, all of `most` at three quarters.
        let k = max(0, min(1, (spare - 0.25) / 0.5))
        let want = base * (1 + (most - 1) * k)
        if room >= base * 0.25 {
            if k > 0 && room > base { boosted += 1 }
            starved[job.rawValue] = 0
            return min(want, room)
        }
        if starved[job.rawValue] >= patience { forced += 1; starved[job.rawValue] = 0; return min(base, least) }
        starved[job.rawValue] += 1
        refused += 1
        return 0
    }

    // A job that needs `want` seconds whole or not at all (a load check, a body let go): may it run now?
    static func room(_ job: Job, for want: Double) -> Bool {
        guard armed else { return true }
        if left >= want { starved[job.rawValue] = 0; return true }
        if starved[job.rawValue] >= patience { forced += 1; starved[job.rawValue] = 0; return true }
        starved[job.rawValue] += 1
        refused += 1
        return false
    }

    // Seconds a job took, counted by the job itself.
    @inline(__always) static func charge(_ job: Job, _ seconds: Double) {
        guard armed, seconds > 0 else { return }
        deferred += seconds; took[job.rawValue] += seconds
    }
    // The job is done for this frame: what it took (since `t0`).
    @inline(__always) static func done(_ job: Job, since t0: Double) {
        guard armed else { return }
        let s = CFAbsoluteTimeGetCurrent() - t0
        if s > 0 { deferred += s; took[job.rawValue] += s }
    }

    // For the perf line and the soak.
    static var line: String {
        guard armed else { return "governor off" }
        return String(format: "governor: tick budget %.1f ms, must %.1f ms, spare %.0f%%, late %d/%d (all %d of %d, worst +%.1f ms), grants %d (boosted %d, refused %d, forced %d), workers held %d",
                      tickBudget * 1000, mustEMA * 1000, spare * 100, late, window, lateTotal, frames, worstOver * 1000, grants, boosted, refused, forced, workersHeld)
    }

    static func tookLine(frames: Int) -> String {
        let n = Double(max(1, frames))
        return Job.allCases.filter { took[$0.rawValue] > 0 }.sorted { took[$0.rawValue] > took[$1.rawValue] }
            .map { String(format: "%@ %.2f", "\($0)", took[$0.rawValue] * 1000 / n) }.joined(separator: ", ")
    }

    // Checks: a frame loop of their own.
    static func disarm() { armed = false; start = 0; tickEnd = 0; late = 0; lateBits = 0; lateBits2 = 0; spare = 0; deferred = 0; mustEMA = 0.004; JobPool.shared.setHeld(0) }
    static func resetCounts() { took = [Double](repeating: 0, count: Job.allCases.count); grants = 0; refused = 0; forced = 0; boosted = 0; lateTotal = 0; frames = 0; worstOver = 0 }
}
