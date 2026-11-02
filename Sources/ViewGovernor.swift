import Foundation

// P425 (Remington, Oct 24: "make it auto choose how far to set the render distance"): Auto View Distance. A two-way
// controller fed one window of frame statistics at a time (QuestApp's FrameStats, every 5 s) that sets the VIEW
// distance (how far the land is drawn, 8 to 24 chunks in steps of 2; the Options slider of P415 is its ceiling), while
// RenderDistanceGovernor keeps stepping the active distance. Pure value type: a synthetic trace can drive it.
//
// P403 measured the headset GPU-bound on the quads it draws, and the quads growing with the view a little faster than
// its first power (jungle 542k at 12, 699k at 16, 884k at 20, 1.11M at 24), so the GPU time of a frame at another view
// is modelled as gpu * (view' / view) ^ exponent (1.2: a touch pessimistic, so a raise undershoots rather than see-saws).
// Down: a window whose GPU mean is past `severeFrac` of the budget (not while loading, unless the next is too) drops at
// once to the view the model says fits `fitFrac`; two windows in a row past `dropFrac` (or missing frames with the GPU
// near the budget) take one step. Up: `hold` seconds with headroom for the next step (its modelled GPU under `fitFrac`
// of the budget, at most 1 % missed frames) raise it to the view that fits, at most three steps, never past the
// slider. A drop within a minute of a raise doubles the hold (up to four minutes); five quiet minutes at the slider
// reset it. Loading bursts, menus and saves count neither way. `current` is session state (QuestSettings keeps the
// last value so the next launch starts there instead of at the slider and dropping again).
struct ViewGovernor {
    struct Window {
        var seconds: Double
        var frames: Int
        var missed: Int                 // frames over 1.5x the budget
        var gpuMs: Double               // mean GPU frame time
        var budgetMs: Double            // the drawn frame's budget (twice the display's with space warp)
        var loading = false
        var excused = false
        // P499: dynamic resolution (DynamicResolution, Quest) and what it knows. With it on the GPU time sits near the
        // budget by design (it trades pixels for time), so the time alone no longer says whether the view fits.
        var dynRes = false
        var scale = 1.0                 // the eye resolution at the window's end (1 = full)
        var pixelShare = 0.0            // the share of the GPU time that follows the pixels (its probe; 0 = not known)
    }
    enum Action: Equatable { case none, lower(Int), raise(Int) }

    static let floor = 8, ceiling = 24, step = 2, exponent = 1.2
    static let dropFrac = 0.92, severeFrac = 1.25, fitFrac = 0.8, missFrac = 0.05
    static let badToDrop = 2, settle = 8.0, baseHold = 20.0, maxHold = 240.0, failWindow = 60.0, calmReset = 300.0
    // P440 (Oct 24 evening: 20-23 fps at view 16 flying into new land, "why isn't it auto rendering?"): the GPU had room,
    // the frames were lost to the CPU making land, and a loading window never counted. Two windows in a row missing
    // more than a quarter of their frames, loading or not, now take a step down whatever the GPU says.
    static let heavyMissFrac = 0.25
    // Store review (Meta, Nov 2, VRC.Quest.Performance.1: "fluctuates under and over 60 frames per second"): a frame
    // the headset misses shows twice (1.5x the budget or more), so 56 fps at 72 Hz is about a fifth of the frames missed.
    // With dynamic resolution on, a window was bad only once the eye had dropped to its floor, and the heavy rule
    // wanted a quarter missed twice running: a frame bound by triangles (the resolution's probe takes its drop back
    // and the scale sits at 1) or by the CPU could miss a fifth of its frames for ever and the view never came down
    // (his Nov 1-2 jungle notes, 49-59 fps on foot). Now any window missing more than `dynMissFrac` is bad whatever
    // the resolution says, and one window past `fastMissFrac` steps down at once.
    static let dynMissFrac = 0.04, fastMissFrac = 0.12

    private(set) var chosen: Int
    private(set) var current: Int
    private(set) var hold = ViewGovernor.baseHold
    private var badStreak = 0, severeStreak = 0, heavyStreak = 0, good = 0.0, sinceChange = 1e9, sinceRaise = 1e9, sinceDrop = 1e9

    static func even(_ rd: Int) -> Int { max(floor, min(ceiling, rd / step * step)) }

    init(chosen: Int, current: Int? = nil) {
        self.chosen = Self.even(chosen)
        self.current = min(self.chosen, Self.even(current ?? chosen))
    }

    var lowered: Bool { current < chosen }

    // The slider moved: the new ceiling, and the view the player asked for; history cleared.
    mutating func setChosen(_ rd: Int) {
        chosen = Self.even(rd); current = chosen
        badStreak = 0; severeStreak = 0; heavyStreak = 0; good = 0; sinceChange = 1e9; sinceRaise = 1e9; sinceDrop = 1e9; hold = Self.baseHold
    }

    // The modelled GPU time of the window's frame drawn at another view. P499 (Oct 30 evening, 64-72 fps: "the view
    // distance never rises again, it's stuck at eight... even though it easily could"): only the part of the frame that
    // is not its pixels grows with the view. His Oct 30 captures were pixel-bound (15-26 ms at 31k-175k quads); the
    // whole frame scaled by the view kept every raise out of reach at 8.
    static func gpu(_ w: Window, from: Int, to: Int) -> Double {
        let f = share(w)
        return w.gpuMs * (f + (1 - f) * pow(Double(to) / Double(max(1, from)), exponent))
    }
    // The pixels' share: the probe's when it has run; with dynamic resolution on and no probe yet, most of it (his
    // captures); without dynamic resolution, none (the P425 model as it was).
    static func share(_ w: Window) -> Double {
        if w.pixelShare > 0 { return min(0.95, w.pixelShare) }
        return w.dynRes ? 0.6 : 0
    }
    // P499: with dynamic resolution on, the eye resolution the view `to` would settle at (it fits the frame to 88 % of
    // the budget by its pixels): the view's extra triangles come out of the pixels.
    static let keepScale = 0.85, dynFit = 0.88, dynFloor = 0.62      // (dynFloor: just over DynamicResolution.minScale)
    static func scaleAt(_ w: Window, from: Int, to: Int) -> Double {
        let f = share(w)
        let pix = w.gpuMs * f, rest = w.gpuMs * (1 - f) * pow(Double(to) / Double(max(1, from)), exponent)
        let room = w.budgetMs * dynFit - rest
        guard pix > 0.01, room > 0 else { return 0 }
        return min(1, w.scale * (room / pix).squareRoot())
    }
    // Whether the next view up fits: under dynamic resolution, at an eye resolution no lower than keepScale.
    static func roomFor(_ w: Window, from: Int, to: Int) -> Bool {
        w.dynRes ? scaleAt(w, from: from, to: to) >= keepScale : gpu(w, from: from, to: to) < w.budgetMs * fitFrac
    }
    // (With dynamic resolution on, a frame near the budget is only bad once the resolution has nothing left to give.)
    static func isBad(_ w: Window) -> Bool {
        guard w.frames > 0 else { return false }
        if Double(w.missed) > Double(w.frames) * dynMissFrac { return true }
        if w.dynRes && w.scale > dynFloor { return false }
        return w.gpuMs > w.budgetMs * dropFrac || (Double(w.missed) > Double(w.frames) * missFrac && w.gpuMs > w.budgetMs * 0.8)
    }
    static func isSevere(_ w: Window) -> Bool { w.frames > 0 && w.gpuMs > w.budgetMs * severeFrac && (!w.dynRes || w.scale <= dynFloor) }
    // The largest view (even, in range) whose modelled GPU time fits `fitFrac` of the budget (under dynamic resolution:
    // whose eye resolution stays at keepScale or over).
    func fitting(_ w: Window) -> Int {
        var rd = Self.ceiling
        while rd > Self.floor && !Self.roomFor(w, from: current, to: rd) { rd -= Self.step }
        return rd
    }

    mutating func observe(_ w: Window) -> Action {
        sinceChange += w.seconds; sinceRaise += w.seconds; sinceDrop += w.seconds
        if current == chosen && sinceDrop > Self.calmReset && sinceRaise > Self.calmReset { hold = Self.baseHold }
        severeStreak = !w.excused && Self.isSevere(w) ? severeStreak + 1 : 0
        if severeStreak >= (w.loading ? 2 : 1) && sinceChange >= Self.settle * 0.5 && current > Self.floor {
            good = 0; badStreak = 0; severeStreak = 0
            current = min(current - Self.step, fitting(w))
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            return .lower(current)
        }
        heavyStreak = !w.excused && w.frames > 0 && Double(w.missed) > Double(w.frames) * Self.heavyMissFrac ? heavyStreak + 1 : 0
        let fast = !w.excused && !w.loading && w.frames > 0 && Double(w.missed) > Double(w.frames) * Self.fastMissFrac
        if (heavyStreak >= 2 || fast) && sinceChange >= Self.settle && current > Self.floor {
            good = 0; badStreak = 0; heavyStreak = 0
            current -= Self.step
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            return .lower(current)
        }
        if w.excused || w.loading || sinceChange < Self.settle { return .none }
        if Self.isBad(w) {
            good = 0
            badStreak += 1
            guard badStreak >= Self.badToDrop, current > Self.floor else { return .none }
            badStreak = 0
            current -= Self.step
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            return .lower(current)
        }
        badStreak = 0
        let next = current + Self.step
        guard current < chosen, w.frames > 0, w.missed * 100 <= w.frames,
              Self.roomFor(w, from: current, to: next) else { good = 0; return .none }
        good += w.seconds
        guard good >= hold else { return .none }
        current = min(chosen, current + 3 * Self.step, max(next, fitting(w)))
        good = 0; sinceChange = 0; sinceRaise = 0
        return .raise(current)
    }
}

// P499: synthetic traces for Auto View Distance with dynamic resolution on (QuestSim's viewgovernor case). A scene whose
// GPU time is its pixels (P at full resolution, times the scale squared) plus its triangles (G at view 8, growing as
// the view to the 1.2); dynamic resolution holds the frame at 88 % of the budget between 0.6 and 1 of the eye. Each
// 5 s window reports what the headset would: the GPU time, the scale and the probe's pixel share. Returns the failures.
enum ViewGovernorTest {
    static func run(log: (String) -> Void = { print($0) }) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ what: String) { log("  \(ok ? "ok  " : "FAIL") \(what)"); if !ok { fails += 1 } }
        let budget = 1000.0 / 72
        // (views it held, last view, worst share of missed frames)
        func play(_ pix: Double, _ tri: Double, chosen: Int, start: Int, minutes: Double) -> ([Int], Int, Double) {
            var g = ViewGovernor(chosen: chosen, current: start)
            var views: [Int] = [], worstMiss = 0.0
            for _ in 0..<Int(minutes * 12) {
                let geo = tri * pow(Double(g.current) / 8, ViewGovernor.exponent)
                let need = (budget * 0.88 - geo) / pix
                let s = need > 0 ? max(0.6, min(1, need.squareRoot())) : 0.6
                let p = pix * s * s, gpu = p + geo
                let over = gpu / budget
                let missed = over <= 0.95 ? 0 : Int(360 * min(1, (over - 0.95) * 2))
                worstMiss = max(worstMiss, Double(missed) / 360)
                let w = ViewGovernor.Window(seconds: 5, frames: 360, missed: missed, gpuMs: gpu, budgetMs: budget,
                                            dynRes: true, scale: s, pixelShare: p / gpu)
                _ = g.observe(w)
                if views.last != g.current { views.append(g.current) }
            }
            return (views, g.current, worstMiss)
        }
        // 1. His Oct 30 evening, flying over sea and plain at 64-72 fps (10 ms of pixels, 2 ms of triangles at view 8):
        // stuck at 8 before; it climbs while the eye keeps 85 % or more.
        let (v1, end1, m1) = play(10, 2, chosen: 24, start: 8, minutes: 4)
        check(end1 >= 14 && m1 < 0.02, "viewgovernor: light ground with dynamic resolution climbs from 8 (views \(v1), missed \(Int(m1 * 100))%)")
        // 2. His Oct 30 afternoon ground (16 ms of pixels): it stays at 8 and lets the resolution carry the frame.
        let (v2, end2, _) = play(16, 2, chosen: 24, start: 8, minutes: 4)
        check(end2 == 8, "viewgovernor: heavy ground holds view 8 (views \(v2))")
        // 3. A triangle-heavy scene at 16 (8 ms of triangles at view 8): the frame does not fit even at 70 %, it comes down
        // and does not see-saw.
        let (v3, end3, _) = play(6, 8, chosen: 16, start: 16, minutes: 10)
        check(end3 < 16 && v3.count <= 4, "viewgovernor: a triangle-bound view comes down and stays (views \(v3))")
        // 4. Store review (Nov 2): a frame bound by its triangles under dynamic resolution (the probe takes its drops back,
        // the eye stays at 100 %) missing a fifth of its frames: it comes down within 15 s, and stays down.
        var g4 = ViewGovernor(chosen: 16, current: 16)
        var t4 = 0.0, v4: [Int] = []
        for _ in 0..<12 {
            let miss = g4.current >= 14 ? 72 : 0                  // (56 fps at 14 and over; fits at 12)
            let w = ViewGovernor.Window(seconds: 5, frames: 360, missed: miss, gpuMs: budget * 0.97, budgetMs: budget,
                                        dynRes: true, scale: 1, pixelShare: 0.1)
            if case .lower = g4.observe(w), t4 == 0 { t4 = Double(v4.count + 1) * 5 }
            v4.append(g4.current)
        }
        check(v4.last ?? 16 <= 12 && (v4.firstIndex { $0 < 16 } ?? 99) <= 2, "viewgovernor: a triangle-bound view missing a fifth of its frames under dynamic resolution comes down at once (views \(v4))")
        return fails
    }
}
