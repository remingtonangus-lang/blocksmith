import Foundation

// Ledger 263 (Remington, Nov 17 16:19 AST: "set up measures so he stays above 60 fps when he plays... a warning in the
// headset when the frame rate dips below 60, so he can say out loud what's going on at that moment"): a playtest-only
// frame-rate warning. Options > Interface > Frame Rate Warning (off by default, and its row shows only in playtest
// builds, beside Bug Notes: the store build never shows it; the no-hint-text rule stands for normal play), or the debug
// property BS_FPSWARN=1. While on: any second (a sliding one-second window of handed frames) under 60 fps shows a small
// red mark with the rate at the HUD's right edge and gives one short haptic pulse (at most one every 10 s); the mark
// clears once the rate has been back over 70 for 2 s. Each dip (not each second) writes one capture beside the voice
// notes (BugNotes.savePerfCapture, vn-perf-*.txt): time, rate, where, view, quads, eye resolution, GPU and CPU ms, the
// slowest tick stage, riding what. BS_OLDFPSWARN=1 turns the whole warning off (the before side).
final class FpsWarning {
    static let shared = FpsWarning()
    static let old = Env.all["BS_OLDFPSWARN"] == "1"
    static let forced = Env.all["BS_FPSWARN"] == "1"
    static let low = 60, clearAbove = 70
    static let clearSeconds = 2.0, pulseGap = 10.0

    var enabled: Bool { !FpsWarning.old && (FpsWarning.forced || Settings.shared.fpsWarning) }

    // A ring of the last 256 frames' hand-over times and their CPU, GPU and tick ms (no allocation per frame).
    private static let n = 256
    private var stamp = [Double](repeating: 0, count: FpsWarning.n)
    private var cpu = [Double](repeating: 0, count: FpsWarning.n)
    private var gpu = [Double](repeating: 0, count: FpsWarning.n)
    private var tick = [Double](repeating: 0, count: FpsWarning.n)
    private var stage = [StaticString](repeating: "-", count: FpsWarning.n)
    private var stageMs = [Double](repeating: 0, count: FpsWarning.n)
    private var head = 0, filled = 0

    private(set) var showing = false
    private(set) var shownFps = 0
    private var goodSince = -1.0, lastPulse = -1e9
    private(set) var warnings = 0, captures = 0, pulses = 0
    // Set by the host: write a capture (true when written), and give the pulse.
    var onCapture: ((String) -> Bool)?
    var onPulse: (() -> Void)?

    func reset() {
        head = 0; filled = 0; showing = false; shownFps = 0; goodSince = -1; lastPulse = -1e9
        warnings = 0; captures = 0; pulses = 0
    }

    // The frames handed over in the second up to `now`; nil until a whole second of frames is in hand (just loaded).
    func rate(at now: Double) -> Int? {
        guard filled > 0 else { return nil }
        var count = 0, covered = false
        for k in 0..<filled {
            let i = (head - 1 - k + 2 * FpsWarning.n) % FpsWarning.n
            if now - stamp[i] > 1 { covered = true; break }
            count += 1
        }
        return covered ? count : nil
    }

    // One frame handed to the compositor at `now` (seconds). `place` is asked for the capture's words only when a dip
    // begins.
    func add(at now: Double, cpuMs: Double, gpuMs: Double, tickMs: Double, place: () -> String) {
        guard enabled else { if showing || filled > 0 { reset() }; return }
        stamp[head] = now; cpu[head] = cpuMs; gpu[head] = gpuMs; tick[head] = tickMs
        (stage[head], stageMs[head]) = tickMs > 0 ? TickProf.top() : ("-", 0)
        head = (head + 1) % FpsWarning.n
        filled = min(FpsWarning.n, filled + 1)
        guard let fps = rate(at: now) else { return }
        if fps < FpsWarning.low {
            goodSince = -1
            if !showing {
                showing = true
                warnings += 1
                if now - lastPulse >= FpsWarning.pulseGap { lastPulse = now; pulses += 1; onPulse?() }
                shownFps = fps
                if onCapture?(captureText(fps: fps, now: now, place: place())) == true { captures += 1 }
            }
            shownFps = min(shownFps, fps)
        } else if showing {
            if fps > FpsWarning.clearAbove {
                if goodSince < 0 { goodSince = now }
                if now - goodSince >= FpsWarning.clearSeconds { showing = false; goodSince = -1 }
            } else { goodSince = -1 }
        }
    }

    private func captureText(fps: Int, now: Double, place: String) -> String {
        var sc = 0.0, sg = 0.0, worstTick = 0.0, n = 0
        var worstStage: StaticString = "-", worstStageMs = 0.0
        for k in 0..<filled {
            let i = (head - 1 - k + 2 * FpsWarning.n) % FpsWarning.n
            if now - stamp[i] > 1 { break }
            sc += cpu[i]; sg += gpu[i]; n += 1
            if tick[i] > worstTick { worstTick = tick[i]; worstStage = stage[i]; worstStageMs = stageMs[i] }
        }
        let d = Double(max(1, n))
        var t = "perf capture (frame rate warning) \(Date())\n"
        t += "fps: \(fps) in the last second (warning \(warnings))\n"
        t += place + "\n"
        t += String(format: "cpu %.2f ms, gpu %.2f ms a frame (last second); slowest tick %.1f ms: %@ %.1f ms\n",
                    sc / d, sg / d, worstTick, "\(worstStage)" as NSString, worstStageMs)
        return t
    }

    // The mark on the HUD: a red square and the rate, at the right edge, a third of the way down.
    static func mark() -> String? {
        let w = shared
        guard w.enabled, w.showing else { return nil }
        return "\(w.shownFps) fps"
    }
}
