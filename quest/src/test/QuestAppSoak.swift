import Foundation
import simd
import CVulkan

// Ledger 261 (Fable, Nov 17: Meta's second review, VRC.Quest.Performance.1, "fluctuates under and over 60 frames per
// second ... throughout the duration of the app experience"): a reviewer's first minutes through the real app loop,
// QuestApp.frame(), on a stand-in runtime (XRSession(headless:)): the app started, the world it opens loaded and
// handed over, the first-launch panel closed, a walk, then Create New World and a walk in that. Every frame handed to
// the "compositor" is counted against the 72 Hz vsyncs it missed and its frame-thread time; the headset estimate is
// host ms x 1.7 (store-vrc-performance), so a frame over 8.2 host ms would miss the headset's 13.9 ms.
//   questcheck --appsoak [--walk SECONDS] [--seeds FIRST,NEW] [--keep DIR]      (a fresh data folder each run, as a first launch)
// GPU time is not measured (SceneRenderer.skipGPU): only the frame thread and what holds it.
enum QuestAppSoak {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }
    static let headsetFactor = 1.7
    static let budgetMs = 1000.0 / 72

    final class Phase {
        let name: String
        let start = CFAbsoluteTimeGetCurrent()
        var frames = 0, skipped = 0, worstGap = 0, late = 0, missed = 0
        var worstMs = 0.0, worstAt = 0.0
        var slow: [(Double, Double, String)] = []          // (seconds in, ms, what)
        var end = 0.0
        init(_ name: String) { self.name = name }
        func add(skipped s: Int, ms: Double, what: () -> String) {
            frames += 1
            skipped += s; worstGap = max(worstGap, s)
            let est = ms * QuestAppSoak.headsetFactor
            if est > QuestAppSoak.budgetMs { late += 1 }
            if est > QuestAppSoak.budgetMs * 1.5 { missed += 1 }
            let at = CFAbsoluteTimeGetCurrent() - start
            if ms > worstMs { worstMs = ms; worstAt = at }
            if est > QuestAppSoak.budgetMs * 1.5 && slow.count < 400 { slow.append((at, ms, what())) }
        }
        var line: String {
            String(format: "appsoak: %-22@ %5d frames in %5.1f s; host: %d vsyncs missed (longest gap %d), worst frame %.1f ms at %.1f s; headset estimate: %d over 13.9 ms, %d over 20.8 ms (%.2f%%)",
                   name as NSString, frames, (end > 0 ? end : CFAbsoluteTimeGetCurrent()) - start, skipped, worstGap + 1, worstMs, worstAt, late, missed,
                   frames > 0 ? 100 * Double(missed) / Double(frames) : 0)
        }
    }

    static func run(ctx: VkContext) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        let walk = Double(arg("--walk") ?? "") ?? 20
        let root = arg("--keep") ?? FileManager.default.temporaryDirectory.appendingPathComponent("appsoak-\(getpid())").path
        QuestPaths.setDataRoot(root)
        SceneRenderer.skipGPU = true
        QuestApp.lapsOn = true
        QuestApp.soakSeeds = (arg("--seeds") ?? "").split(separator: ",").compactMap { UInt64($0) }
        var xr: XRSession, app: QuestApp
        var phases: [Phase] = []
        var phase = Phase("start to the world")
        phases.append(phase)
        do {
            xr = try XRSession(headless: ctx, width: 64, height: 64)
            app = try QuestApp(xr: xr)
        } catch { print("FAIL appsoak: \(error)"); return 1 }
        xr.hlHanded = { s, ms in
            phase.add(skipped: s, ms: ms) {
                (app.game == nil ? "loading" : "tick: " + TickProf.summary()) + " | frame: " + app.lapLine + (app.recordLine.isEmpty ? "" : " | record: " + app.recordLine)
            }
        }
        func frames(until done: () -> Bool, limit: Double) -> Bool {
            let t0 = CFAbsoluteTimeGetCurrent()
            while !done() {
                if CFAbsoluteTimeGetCurrent() - t0 > limit { return false }
                if !app.frame() { return false }
            }
            return true
        }
        func next(_ name: String) { phase.end = CFAbsoluteTimeGetCurrent(); phase = Phase(name); phases.append(phase) }
        func walkFor(_ secs: Double) {
            var hand = XRHand(); hand.stick = V2(0, 1); hand.aimValid = true; hand.gripValid = true
            hand.aimPos = V3(-0.2, 1.2, -0.3); hand.gripPos = hand.aimPos
            if let g = app.game { print("appsoak: walking from \(g.player.pos) (paused \(g.paused), menu \(g.menu.map { String(describing: type(of: $0)) } ?? "none"))") }
            xr.hlInput[0] = hand
            let t0 = CFAbsoluteTimeGetCurrent()
            var f = 0
            while CFAbsoluteTimeGetCurrent() - t0 < secs {
                if let g = app.game { g.survival = false; g.alive = true; g.health = 20 }       // (nothing ends the walk)
                f += 1
                var r = XRHand(); r.aimValid = true; r.gripValid = true; r.aimPos = V3(0.2, 1.2, -0.3); r.gripPos = r.aimPos; r.stick = V2(f % 720 < 360 ? 0.3 : -0.3, 0)               // (looking about as he walks)
                xr.hlInput[1] = r
                if !app.frame() { break }
            }
            xr.hlInput = [XRHand(), XRHand()]
        }
        func closeMenus() {
            guard let g = app.game else { return }
            if g.menu != nil { g.closeMenu() }
            g.paused = false
        }

        guard frames(until: { app.game != nil }, limit: 600) else { print("FAIL appsoak: the first world never arrived"); return 1 }
        let pos0 = app.game.map { $0.player.pos } ?? .zero
        next("first-launch panel 3 s")
        _ = frames(until: { false }, limit: 3)
        closeMenus()
        next("walk \(Int(walk)) s")
        walkFor(walk)
        let moved = simd_distance(app.game.map { $0.player.pos } ?? .zero, pos0)

        next("create new world")
        app.game?.appAction?("newworld")
        guard frames(until: { app.game != nil }, limit: 600) else { print("FAIL appsoak: the new world never arrived"); return 1 }
        closeMenus()
        next("new world: walk \(Int(walk)) s")
        walkFor(walk)

        // Item 4: the autosave (Game.tick's 60 s save, taken here between two frames, as inside one), standing.
        next("autosave")
        app.game?.saveNow(background: true)
        _ = frames(until: { false }, limit: 3)
        // Item 5 (part): the pause menu opened, then Save and Quit to the title (PauseMenu "totitle").
        next("pause menu open")
        app.game?.paused = true
        _ = frames(until: { false }, limit: 2)
        next("save and quit to title")
        (app.game?.menu as? PauseMenu)?.act("totitle", back: false)
        _ = frames(until: { false }, limit: 3)
        // Quit Game (the title's quit: saved on the loading thread behind "Saving the world", then the app exits).
        next("quit game")
        app.game?.appAction?("quit")
        let quitStart = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - quitStart < 120 { if !app.frame() { break } }
        let quitSecs = CFAbsoluteTimeGetCurrent() - quitStart
        app.shutdown()
        // Item 3: the app started again on the same data: the world just saved opens.
        next("reopen the saved world")
        let app2: QuestApp
        do {
            let xr2 = try XRSession(headless: ctx, width: 64, height: 64)
            xr2.hlHanded = xr.hlHanded
            app2 = try QuestApp(xr: xr2)
            app = app2
            xr = xr2
        } catch { print("FAIL appsoak: reopen \(error)"); return 1 }
        guard frames(until: { app.game != nil }, limit: 600) else { print("FAIL appsoak: the saved world never reopened"); return 1 }
        closeMenus()
        next("reopened: walk \(Int(walk / 2)) s")
        walkFor(walk / 2)

        phase.end = CFAbsoluteTimeGetCurrent()
        print("")
        for p in phases {
            print(p.line)
            for (at, ms, what) in p.slow.prefix(12) {
                print(String(format: "appsoak:    %6.2f s  %6.1f ms  %@", at, ms, what))
            }
            if p.slow.count > 12 { print("appsoak:    (\(p.slow.count - 12) more)") }
        }
        print(String(format: "appsoak: walked %.0f blocks in the first world; quit took %.1f s", moved, quitSecs))
        let total = phases.reduce(0) { $0 + $1.missed }, all = phases.reduce(0) { $0 + $1.frames }
        print(String(format: "appsoak: all phases: %d frames, %d over 20.8 ms on the headset estimate (%.2f%%)", all, total,
                     all > 0 ? 100 * Double(total) / Double(all) : 0))
        // The gate: the loading scene and the hand-overs (start, create) never hold a frame past 1.5x the headset's
        // budget; the walks are reported for the steady rate (Fable's view governor), not gated here.
        let gatedNames: Set<String> = ["start to the world", "create new world", "autosave", "pause menu open", "save and quit to title",
                                       "quit game", "reopen the saved world"]
        let gated = phases.filter { gatedNames.contains($0.name) }
        let held = gated.reduce(0) { $0 + $1.missed }
        print(held == 0 ? "ok   appsoak: the app start, Create New World, saves, the pause menu, quit and reopening hold no frame (headset estimate under 20.8 ms)"
                        : "FAIL appsoak: \(held) frames over 20.8 ms (headset estimate) in " + gated.filter { $0.missed > 0 }.map { $0.name }.joined(separator: ", "))
        app.shutdown()
        return held == 0 ? 0 : 1
    }
}
