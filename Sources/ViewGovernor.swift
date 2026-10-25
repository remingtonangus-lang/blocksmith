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
    }
    enum Action: Equatable { case none, lower(Int), raise(Int) }

    static let floor = 8, ceiling = 24, step = 2, exponent = 1.2
    static let dropFrac = 0.92, severeFrac = 1.25, fitFrac = 0.8, missFrac = 0.05
    static let badToDrop = 2, settle = 8.0, baseHold = 20.0, maxHold = 240.0, failWindow = 60.0, calmReset = 300.0
    // P440 (Oct 24 evening: 20-23 fps at view 16 flying into new land, "why isn't it auto rendering?"): the GPU had room,
    // the frames were lost to the CPU making land, and a loading window never counted. Two windows in a row missing
    // more than a quarter of their frames, loading or not, now take a step down whatever the GPU says.
    static let heavyMissFrac = 0.25

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

    // The modelled GPU time of the window's frame drawn at another view.
    static func gpu(_ w: Window, from: Int, to: Int) -> Double {
        w.gpuMs * pow(Double(to) / Double(max(1, from)), exponent)
    }
    static func isBad(_ w: Window) -> Bool {
        guard w.frames > 0 else { return false }
        return w.gpuMs > w.budgetMs * dropFrac || (Double(w.missed) > Double(w.frames) * missFrac && w.gpuMs > w.budgetMs * 0.8)
    }
    static func isSevere(_ w: Window) -> Bool { w.frames > 0 && w.gpuMs > w.budgetMs * severeFrac }
    // The largest view (even, in range) whose modelled GPU time fits `fitFrac` of the budget.
    func fitting(_ w: Window) -> Int {
        var rd = Self.ceiling
        while rd > Self.floor && Self.gpu(w, from: current, to: rd) > w.budgetMs * Self.fitFrac { rd -= Self.step }
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
        if heavyStreak >= 2 && sinceChange >= Self.settle && current > Self.floor {
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
              Self.gpu(w, from: current, to: next) < w.budgetMs * Self.fitFrac else { good = 0; return .none }
        good += w.seconds
        guard good >= hold else { return .none }
        current = min(chosen, current + 3 * Self.step, max(next, fitting(w)))
        good = 0; sinceChange = 0; sinceRaise = 0
        return .raise(current)
    }
}
