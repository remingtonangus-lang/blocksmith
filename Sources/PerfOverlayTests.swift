import Foundation

// L3 perf overlay (docs/status/l3-part3.md): the frame window, the two lines, the Interface option, and the HUD drawing
// them only when it is on. Shared: questcheck runs it (the Quest's HUD host builds the same HUD as the Mac).
enum PerfOverlayTests {
    static func run(_ g: Game, hud: () -> Int, check: (Bool, String) -> Void) {
        let po = PerfOverlay.shared
        po.reset()
        // 1. The window: 71 frames of 13.9 ms and one of 30 in the last second; older frames don't count.
        let now = 1000.0
        for i in 0..<20 { po.add(frameMs: 80, at: now - 3 + Double(i) * 0.01) }     // a hitch 3 s ago
        for i in 0..<71 { po.add(frameMs: 13.9, at: now - 0.99 + Double(i) * 0.0139) }
        po.add(frameMs: 30, at: now)
        let w = po.window(now: now)
        check(w.frames == 72 && abs(w.avg - (13.9 * 71 + 30) / 72) < 0.01 && w.worst == 30,
              "perf overlay: the last second's frames (\(w.frames), " + String(format: "avg %.2f ms, worst %.1f ms", w.avg, w.worst) + "), the hitch 3 s ago dropped")
        // 2. The lines: frame rate and times, GPU, the render distance (marked when Auto Render Distance holds it lower).
        let rd0 = g.world.activeDistance, gov = g.rdGovernor
        g.rdGovernor = RenderDistanceGovernor(chosen: rd0 + 4)
        let lines = PerfOverlay.lines(fps: 71.6, gpuMs: 9.24, game: g, now: now)
        g.rdGovernor = gov
        let plain = PerfOverlay.lines(fps: 72, gpuMs: 0, game: g, now: now)
        check(lines.count >= 2 && lines[0].hasPrefix("72 fps") && lines[0].contains("worst 30.0") && lines[0].contains("GPU 9.2")
              && lines[1].contains("active \(rd0) of \(rd0 + 4) (auto)") && lines[1].contains("jobs")
              && plain[1].hasPrefix("Render distance \(rd0)  ") && !plain[0].contains("GPU"),
              "perf overlay: \"\(lines[0])\" / \"\(lines[1])\"")
        // 3. The option (Options > Interface) toggles it and the HUD draws it only when on (Reset Options turns it off).
        PrefsSandbox.begin()
        defer { PrefsSandbox.end() }
        let st = Settings.shared, was = st.perfOverlay, debug = g.showDebug
        st.perfOverlay = false; g.showDebug = false
        let off = hud()
        let pm = PauseMenu(game: g)
        pm.act("options", back: false)
        pm.cat = .interface
        pm.build()
        let row = pm.rows.first { $0.1 == "perf" }?.0 ?? "(no row)"
        pm.act("perf", back: false)
        pm.build()
        let on = hud()
        let row2 = pm.rows.first { $0.1 == "perf" }?.0 ?? "(no row)"
        st.perfOverlay = was; g.showDebug = debug
        check(row == "Performance Overlay: Off" && row2 == "Performance Overlay: On" && on > off && PauseMenu.help["perf"] != nil,
              "perf overlay: Options > Interface \"\(row)\" -> \"\(row2)\", the HUD draws it (\(off) -> \(on) vertices)")
        po.reset()
    }
}
