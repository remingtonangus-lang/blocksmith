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
// of the budget, at most 1 % missed frames) raise it one step (store review, Nov 2: it was up to three), never past the
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
        var quads = 0                   // ledger 234: quads drawn a frame, the window's mean (0 = not known)
    }
    enum Action: Equatable { case none, lower(Int), raise(Int) }

    static let floor = 8, ceiling = 24, step = 2, exponent = 1.2
    static let dropFrac = 0.92, severeFrac = 1.25, fitFrac = 0.8, missFrac = 0.05
    static let badToDrop = 2, settle = 8.0, maxHold = 240.0, failWindow = 60.0, calmReset = 300.0
    // Ledger 233 (store review, Nov 17: "fluctuates under and over 60 frames per second"): steadier before farther.
    // (a) a raise waits 45 s of room, not 20; (b) a view that had to come down is not tried again for ten minutes:
    // raises stop one step under it (`lid`), so the frame does not see-saw at the edge of what the headset can draw.
    // BS_OLDVIEWGOV=1 = before.
    static let steady = Env.all["BS_OLDVIEWGOV"] != "1"
    // Ledger 380: BS_VIEWHOLD / BS_VIEWLID (seconds) for headset trials.
    static let baseHold = Env.all["BS_VIEWHOLD"].flatMap { Double($0) } ?? (steady ? 45.0 : 20.0)
    static let lidFor = Env.all["BS_VIEWLID"].flatMap { Double($0) } ?? 600.0
    // P440 (Oct 24 evening: 20-23 fps at view 16 flying into new land, "why isn't it auto rendering?"): the GPU had room,
    // the frames were lost to the CPU making land, and a loading window never counted. Two windows in a row missing
    // more than a quarter of their frames, loading or not, now take a step down whatever the GPU says.
    static let heavyMissFrac = 0.25
    // Ledger 234 (store review, Nov 17; his Quest on the six held views of the gate's spots route): the frame time
    // follows the quads drawn and nothing else. 61k (savanna) and 88k (forest) held 72 fps at 12.2-12.5 ms of GPU;
    // 143k (jungle at view 8) ran 67 fps at 14.5 ms, 229k (jungle at 16) 52 fps at 19.3 ms and 410k (taiga at 16)
    // 24 fps at 42.7 ms, each with the eye resolution already at its 60 % floor and the GPU at 640 MHz, 98 % busy.
    // Waiting for missed frames to say so (two 5 s windows, a step of two chunks at a time) is the fluctuation the
    // review saw. So the view also keeps a budget of quads: over `quadCap` it comes down at once (FrameStats asks every
    // second) to the view that fits, and a raise needs the next view's quads under 90 % of it. Quads grow slower than
    // the view (the far copies thin them: 143k at 8, 229k at 16 = the 0.68th power), so a drop is sized by the 0.8th
    // power (lands a little low) and a raise by the 1.2th (a little careful). BS_QUADCAP=0 = before.
    // The same route at fixed views: at 6 every spot held 72 (jungle 102k quads at 12.7 ms, taiga 64k); at 8 the jungle
    // (141k) and the taiga ran 68-69 fps; at 10, 57 and 48. So under the quad budget, and only under it, the view may
    // go one step under the floor, to 6 (BS_QUADFLOOR=8 = not).
    // Ledger 380 (first store update, Nov 20: "render distance is abysmal ... at least 12 most of the time"): the
    // 105k budget was set before ledger 235 halved the land's shader. His Quest on build 908ca9d, the six spots held at
    // view 12: every spot 72 fps (min 70, 0 s under 70), jungle 148k quads at 12.9 ms GPU (eye 85 %), forest 125k at
    // 12.6, village 106k at 12.8, beach 76k at 11.6. So the budget is now 170k: view 12 fits every spot with room, and
    // past it the view still comes down at once (the 229k / 410k views that ran 52 and 24 fps stay out).
    static let quadCap = Env.all["BS_QUADCAP"].flatMap { Int($0) } ?? 170_000
    // Ledger 380: the view the first store update keeps. Under it a raise waits `keepHold` seconds of room, not 45.
    static let keepView = Env.all["BS_KEEPVIEW"].flatMap { Int($0) } ?? 12, keepHold = 15.0
    // Ledger 382 (the same night's reviewer route, 3376e5a): the frigate's GPU took the view 12 -> 10 (right), then its
    // ten-minute lid kept the cheap train leg at 10, one loading second of 178k quads took it to 8 at once, and 121k at 8
    // never passed the raise test (158k predicted at 10 against 90 % of the budget). Under `keepView`: a lid is lifted
    // once he is `lidLeave` blocks from where it was set (another place; the same place keeps its ten minutes), the
    // budget drop wants two seconds over in a row (one second over by a quarter still drops), and a raise needs the next
    // step's quads under the budget itself. BS_OLDKEEP=1 = as 380.
    static let keepOld = Env.all["BS_OLDKEEP"] == "1"
    static let lidLeave: Float = 160
    var lidded: Bool { lid < Self.keepView && !Self.keepOld }
    mutating func placeChanged() { if lidded { lid = Self.ceiling } }
    // Ledger 384 (Nov 20 playtest, 3376e5a: "it took too long to bounce back after a drop"): under `keepView` the climb
    // back is quick. A raise waits `keepFastHold` seconds of room (not 15) and `keepSettle` after the last change (not
    // 8): 6 -> 12 in about 15 s once there is room, where it took over a minute. The build he played (3376e5a) also
    // kept a lid ten minutes wherever he went; ledger 382 already lifts it 160 blocks away. In the same place the lid
    // keeps its ten minutes (ledger 233, the store review's "fluctuates": a place that misses frames at 12 must not
    // try it every minute; check 5). BS_OLDCLIMB=1 = as 382.
    static let oldClimb = keepOld || Env.all["BS_OLDCLIMB"] == "1"
    static let keepFastHold = 4.0, keepSettle = 3.0
    var climbing: Bool { !Self.oldClimb && current < Self.keepView }
    var holdNow: Double { current < Self.keepView ? (Self.oldClimb ? min(hold, Self.keepHold) : Self.keepFastHold) : hold }
    static let quadFloor = Env.all["BS_QUADFLOOR"].flatMap { Int($0) } ?? 6
    static let quadSettle = 2.0
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
    private(set) var lid = ViewGovernor.ceiling          // (ledger 233: the highest view a raise may reach for now)
    private var lidAge = 0.0
    private var sinceQuadDrop = 1e9
    private var overSeconds = 0.0
    // Why the last window did not raise the view (the perf line prints it while the view is under the slider).
    private(set) var note = ""

    static func even(_ rd: Int) -> Int { max(floor, min(ceiling, rd / step * step)) }

    init(chosen: Int, current: Int? = nil) {
        self.chosen = Self.even(chosen)
        self.current = min(self.chosen, max(Self.quadCap > 0 ? min(Self.floor, Self.quadFloor) : Self.floor, min(Self.ceiling, (current ?? chosen) / Self.step * Self.step)))
    }

    var lowered: Bool { current < chosen }

    // The slider moved: the new ceiling, and the view the player asked for; history cleared.
    mutating func setChosen(_ rd: Int) {
        chosen = Self.even(rd); current = chosen
        lid = Self.ceiling; lidAge = 0
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

    // Ledger 382: the share of the budget a raise's predicted quads must fit (all of it up to `keepView`).
    static func raiseRoom(_ next: Int) -> Double { !keepOld && next <= keepView ? 1.0 : 0.9 }
    // Ledger 234: the view that keeps `quads` (drawn at `view`) inside the budget.
    static func viewFor(quads: Int, at view: Int) -> Int {
        var rd = view
        while rd > quadFloor && Double(quads) * pow(Double(rd) / Double(max(1, view)), 0.8) > Double(quadCap) { rd -= step }
        return rd
    }
    // Ledger 234: asked about once a second with the quads drawn a frame over that second. Not a view that failed on
    // its frames, so no lid: the raise's own quad test keeps it from coming straight back.
    mutating func overQuads(_ quads: Int, seconds: Double) -> Action {
        sinceQuadDrop += seconds
        overSeconds = Self.quadCap > 0 && quads > Self.quadCap ? overSeconds + seconds : 0
        guard Self.quadCap > 0, quads > Self.quadCap, current > Self.quadFloor, sinceQuadDrop >= Self.quadSettle else { return .none }
        if !Self.keepOld && current <= Self.keepView && overSeconds < 2 && Double(quads) < Double(Self.quadCap) * 1.25 { return .none }
        let to = Self.viewFor(quads: quads, at: current)
        guard to < current else { return .none }
        current = to
        good = 0; badStreak = 0; severeStreak = 0; heavyStreak = 0
        sinceChange = 0; sinceDrop = 0; sinceQuadDrop = 0
        return .lower(current)
    }

    // Ledger 298: Auto View off (the slider a ceiling, the quad budget alone): a step back up once the next step's quads
    // fit 90 % of the budget for `baseHold` seconds running, at least `quadSettle` after a drop.
    private var quadGood = 0.0
    mutating func quadRaise(_ quads: Int, seconds: Double) -> Action {
        sinceQuadDrop += seconds
        guard Self.quadCap > 0, current < chosen, sinceQuadDrop >= Self.quadSettle, quads > 0 else { quadGood = 0; return .none }
        let next = min(chosen, current + Self.step)
        let quadsNext = Double(quads) * pow(Double(next) / Double(max(1, current)), Self.exponent)
        guard quadsNext <= Double(Self.quadCap) * Self.raiseRoom(next) else { quadGood = 0; return .none }
        quadGood += seconds
        guard quadGood >= (current < Self.keepView ? (Self.oldClimb ? min(Self.baseHold, Self.keepHold) : Self.keepFastHold) : Self.baseHold) else { return .none }
        quadGood = 0
        current = next
        return .raise(current)
    }

    mutating func observe(_ w: Window) -> Action {
        sinceChange += w.seconds; sinceRaise += w.seconds; sinceDrop += w.seconds
        lidAge += w.seconds
        if lidAge >= Self.lidFor { lid = Self.ceiling }
        if current == chosen && sinceDrop > Self.calmReset && sinceRaise > Self.calmReset { hold = Self.baseHold }
        severeStreak = !w.excused && Self.isSevere(w) ? severeStreak + 1 : 0
        if severeStreak >= (w.loading ? 2 : 1) && sinceChange >= Self.settle * 0.5 && current > Self.floor {
            good = 0; badStreak = 0; severeStreak = 0
            current = min(current - Self.step, fitting(w))
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            if Self.steady { lid = max(Self.floor, min(lid, current)); lidAge = 0 }
            return .lower(current)
        }
        heavyStreak = !w.excused && w.frames > 0 && Double(w.missed) > Double(w.frames) * Self.heavyMissFrac ? heavyStreak + 1 : 0
        let fast = !w.excused && !w.loading && w.frames > 0 && Double(w.missed) > Double(w.frames) * Self.fastMissFrac
        if (heavyStreak >= 2 || fast) && sinceChange >= Self.settle && current > Self.floor {
            good = 0; badStreak = 0; heavyStreak = 0
            current -= Self.step
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            if Self.steady { lid = max(Self.floor, min(lid, current)); lidAge = 0 }
            return .lower(current)
        }
        if w.excused || w.loading || sinceChange < (climbing ? Self.keepSettle : Self.settle) {
            note = w.excused ? "excused" : (w.loading ? "loading" : "settling")
            return .none
        }
        if Self.isBad(w) {
            note = "bad window"
            good = 0
            badStreak += 1
            guard badStreak >= Self.badToDrop, current > Self.floor else { return .none }
            badStreak = 0
            current -= Self.step
            if sinceRaise < Self.failWindow { hold = min(Self.maxHold, hold * 2) }
            sinceChange = 0; sinceDrop = 0
            if Self.steady { lid = max(Self.floor, min(lid, current)); lidAge = 0 }
            return .lower(current)
        }
        badStreak = 0
        let next = current + Self.step
        let quadsNext = Double(w.quads) * pow(Double(next) / Double(max(1, current)), Self.exponent)
        let quadRoom = Self.quadCap <= 0 || w.quads <= 0 || quadsNext <= Double(Self.quadCap) * Self.raiseRoom(next)
        guard current < chosen, current < lid, w.frames > 0, w.missed * 100 <= w.frames, quadRoom,
              Self.roomFor(w, from: current, to: next) else {
            good = 0
            if current >= chosen { note = "at the slider \(chosen)" }
            else if current >= lid { note = "under the lid \(lid)" }
            else if w.frames <= 0 || w.missed * 100 > w.frames { note = "missed \(w.missed) of \(w.frames)" }
            else if !quadRoom { note = "quads \(w.quads) would be \(Int(quadsNext)) at \(next)" }
            else { note = String(format: "no room: eye %.2f at %d (share %.2f, gpu %.1f)", Self.scaleAt(w, from: current, to: next), next, Self.share(w), w.gpuMs) }
            return .none
        }
        good += w.seconds
        note = String(format: "room for %.0f of %.0f s", good, holdNow)
        guard good >= holdNow else { return .none }
        // Store review (Nov 2): one step at a time. Three at once (up to six chunks more of land to make and draw) was a
        // burst of new land on the workers and the frame, and when the model was wrong a dip as deep as the jump: the
        // "fluctuates under and over 60" Meta saw. A step that holds is followed by the next after `hold` again.
        current = min(chosen, next)
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
        // 5. Ledger 233 (store review, Nov 17): a place that holds view 10 and misses a fifth of its frames at 12. In ten
        // minutes it tries 12 once and stays at 10 (it tried again every minute or two before: frames lost each time).
        var g5 = ViewGovernor(chosen: 16, current: 8)
        var tries5 = 0, badWindows5 = 0
        for _ in 0..<120 {
            let at12 = g5.current >= 12
            let w = ViewGovernor.Window(seconds: 5, frames: 360, missed: at12 ? 72 : 0, gpuMs: budget * (at12 ? 0.97 : 0.6), budgetMs: budget,
                                        dynRes: true, scale: 1, pixelShare: 0.1)
            if at12 { badWindows5 += 1 }
            if case .raise(let rd) = g5.observe(w), rd == 12 { tries5 += 1 }
        }
        check(tries5 == 1 && g5.current == 10, "viewgovernor: a view that had to come down is left alone for ten minutes (12 tried \(tries5) times in 10 min, \(badWindows5 * 5) s of missed frames, ends at \(g5.current))")
        // 6. Ledger 234 (store review, Nov 17): his jungle, 143k quads at view 8 and 229k at 16. Walking in at 16, the
        // view comes down in the first second asked, before a frame window has ended; on open land (40k at 8) it climbs,
        // and stops where the next step would pass the budget.
        if ViewGovernor.quadCap > 0 {
            var g6 = ViewGovernor(chosen: 16, current: 16)
            func jungle(_ v: Int) -> Int { Int(143_000 * pow(Double(v) / 8, 0.68)) }
            var secs6 = 0
            for s in 1...10 { if case .lower = g6.overQuads(jungle(g6.current), seconds: 1) { secs6 = s; break } }
            let fit6 = Double(jungle(16)) * pow(Double(g6.current) / 16, 0.8) <= Double(ViewGovernor.quadCap)
            check(secs6 > 0 && secs6 <= 3 && g6.current < 16 && fit6, "viewgovernor: over the quad budget the view comes down at once (\(jungle(16)) quads at 16: view \(g6.current) after \(secs6) s)")
            var g7 = ViewGovernor(chosen: 24, current: 8)
            func plain(_ v: Int) -> Int { Int(40_000 * pow(Double(v) / 8, 1.0)) }
            var top7 = 8, over7 = 0
            for _ in 0..<240 {
                let q = plain(g7.current)
                if q > ViewGovernor.quadCap { over7 += 1 }
                let w = ViewGovernor.Window(seconds: 5, frames: 360, missed: 0, gpuMs: budget * 0.5, budgetMs: budget,
                                            dynRes: true, scale: 1, pixelShare: 0.5, quads: q)
                _ = g7.observe(w); _ = g7.overQuads(q, seconds: 5)
                top7 = max(top7, g7.current)
            }
            check(top7 >= 14 && over7 == 0, "viewgovernor: with room in the frame the view climbs only while the next step's quads fit (top view \(top7), \(plain(top7)) quads, \(over7) windows over the budget)")
            // 7. Ledger 298 (Auto View off, slider 22): his taiga flight comes down to the budget at once; over open land
            // it climbs back a step at a time on the quads alone and stops at the slider.
            var g8 = ViewGovernor(chosen: 22, current: 22)
            func taiga(_ v: Int) -> Int { Int(64_000 * pow(Double(v) / 6, 0.9)) }
            var secs8 = 0
            for s in 1...10 { if case .lower = g8.overQuads(taiga(g8.current), seconds: 1) { secs8 = s; break } }
            let low8 = g8.current
            var top8 = low8, over8 = 0
            for _ in 0..<600 {
                let q = plain(g8.current) / 2
                if q > ViewGovernor.quadCap { over8 += 1 }
                if case .none = g8.overQuads(q, seconds: 1) { _ = g8.quadRaise(q, seconds: 1) }
                top8 = max(top8, g8.current)
            }
            check(secs8 > 0 && secs8 <= 3 && low8 < 22 && taiga(low8) <= ViewGovernor.quadCap * 11 / 10 && top8 == 22 && over8 == 0,
                  "viewgovernor: Auto View off, the slider's 22 held by the quad budget (taiga \(taiga(22)) quads: view \(low8) after \(secs8) s; open land back to \(top8), \(over8) s over)")
        }
        // 8. Ledger 382: at view 12 one loading second over the budget does not drop it (two in a row do), and a lid set
        // under 12 is lifted when he is somewhere else.
        if ViewGovernor.quadCap > 0 && !ViewGovernor.keepOld {
            var g9 = ViewGovernor(chosen: 24, current: 12)
            let spike = ViewGovernor.quadCap * 105 / 100
            let one = g9.overQuads(spike, seconds: 1), calm = g9.overQuads(ViewGovernor.quadCap / 2, seconds: 1)
            _ = g9.overQuads(spike, seconds: 1)
            let two = g9.overQuads(spike, seconds: 1)
            check(one == .none && calm == .none && two != .none, "viewgovernor: one second over the quad budget is a spike, two are a drop (\(one), \(two))")
            var g10 = ViewGovernor(chosen: 24, current: 12)
            for _ in 0..<4 {
                _ = g10.observe(ViewGovernor.Window(seconds: 5, frames: 360, missed: 120, gpuMs: budget * 1.3, budgetMs: budget,
                                                   dynRes: true, scale: 0.6, pixelShare: 0.1))
            }
            let lidded = g10.lidded
            g10.placeChanged()
            check(lidded && !g10.lidded, "viewgovernor: a lid under 12 is lifted in another place (lidded \(lidded), view \(g10.current))")
        }
        // 9. Ledger 384: after a drop to 6, once the frames have room again, back at 12 within 20 s (5 s windows).
        if !ViewGovernor.oldClimb {
            var g11 = ViewGovernor(chosen: 24, current: 6)
            let calm = ViewGovernor.Window(seconds: 5, frames: 360, missed: 0, gpuMs: budget * 0.5, budgetMs: budget,
                                           dynRes: true, scale: 1.0, pixelShare: 0.3, quads: 60_000)
            var t11 = 0.0
            while g11.current < 12 && t11 < 120 { _ = g11.observe(calm); t11 += 5 }
            check(g11.current >= 12 && t11 <= 20,
                  "viewgovernor: under 12 it climbs back fast (6 -> \(g11.current) in \(Int(t11)) s; BS_OLDCLIMB=1: as 382)")
        }
        return fails
    }
}
