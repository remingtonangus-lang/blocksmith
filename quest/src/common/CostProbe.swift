import Foundation

/// Where the headset's GPU time goes, measured in play without changing the picture (Nov 16, ledger 170).
///
/// The forest capture of Nov 15 said only "pixel-bound" (10 % fewer pixels gave 7 % less GPU time). Counted off the
/// headset, half of that view's fragments are the sky dome and the cloud decks (about 560 and 610 shader operations
/// each), and the land's solid pass is the dearest shader (about 1,200). What each costs in milliseconds can only be
/// read on the headset, so after a slow window the next one runs two short trials, 24 frames each:
///   1. the sky dome and the clouds are drawn a second time (the dome writes the same colour again, the clouds' second
///      draw blends as nothing): the extra GPU time is what the sky costs;
///   2. the land's opaque passes are drawn a second time (every fragment fails the depth test, so nothing is shaded):
///      the extra GPU time is what the land's triangles cost before a pixel is shaded.
/// The perf line then reads "sky drawn twice +N ms, land drawn twice +N ms". Off unless BS_COSTPROBE=1 (ledger 380).
enum CostProbe {
    // Ledger 380 (Neon review 2, item 3, checked): on by default it drew the sky and the land twice for 24 frames
    // each after every slow window, in the scenes already over budget, and those frames fed the view and resolution
    // governors. Measuring only: BS_COSTPROBE=1 turns it on (the gate's trials ask for it).
    static let on = Env.all["BS_COSTPROBE"] == "1"
    private(set) static var frame = -1          // -1: idle
    private static var sums = [Double](repeating: 0, count: 4), counts = [Int](repeating: 0, count: 4)
    private(set) static var sky = 0.0, land = 0.0, fresh = false

    /// Frames 0..<24 plain, 30..<54 sky twice, 60..<84 plain, 90..<114 land twice. The GPU time read in a frame is an
    /// earlier frame's, so each stretch is measured from its 6th frame to 4 frames past its end.
    static var skyTwice: Bool { (frame >= 30 && frame < 54) || force == "sky" }
    static var landTwice: Bool { (frame >= 90 && frame < 114) || force == "land" }
    /// Harness: BS_COSTFORCE=sky|land draws the second copy in every frame (the picture must not change).
    static let force = Env.all["BS_COSTFORCE"] ?? ""

    static func arm() { if on && frame < 0 { frame = 0; for i in 0..<4 { sums[i] = 0; counts[i] = 0 } } }

    static func add(gpuMs: Double) {
        guard frame >= 0 else { return }
        let stretch = frame / 30, at = frame % 30
        if stretch < 4 && at >= 6 && at < 28 { sums[stretch] += gpuMs; counts[stretch] += 1 }
        frame += 1
        if frame >= 120 {
            frame = -1
            guard counts.allSatisfy({ $0 > 0 }) else { return }
            let m = (0..<4).map { sums[$0] / Double(counts[$0]) }
            sky = m[1] - m[0]; land = m[3] - m[2]; fresh = true
        }
    }

    /// The last trial's answer, once.
    static func line() -> String {
        guard fresh else { return "" }
        fresh = false
        return String(format: " | sky drawn twice %+.2f ms gpu, land drawn twice %+.2f ms gpu", sky, land)
    }
}
