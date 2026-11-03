import Foundation

// P420 (Remington, Oct 23 21:16 and 21:32: "I need a list of what is causing all the compute"): the frame's cost per
// system, smoothed over the last moments of play and frozen while a menu is open. P510: each voice note carries its
// summary (what is heavy where he stands; the pause menu's Compute page is gone). The frame loop feeds it (QuestApp:
// the frame split and the world renderer's record stages); the game tick's stages come from TickProf. No allocation per frame: fixed arrays,
// tick stages keyed by their StaticString's address.
enum ComputeCost {
    static let k = 0.03                                     // smoothing per frame (half of it gone in ~0.3 s at 72 fps)
    private(set) static var fps = 0.0, rate = 0.0, frameMs = 0.0, cpuMs = 0.0, tickMs = 0.0, recordMs = 0.0, gpuMs = 0.0
    private(set) static var fed = false
    // Record stages (WorldRenderer.stageNames), ms a frame.
    private(set) static var stageNames: [String] = []
    private(set) static var stages: [Double] = []
    // Game tick stages, ms a frame.
    static let tickCap = 96
    private static var tickNames = [StaticString](repeating: "", count: tickCap)
    private static var tickTimes = [Double](repeating: 0, count: tickCap)
    private static var tickCount = 0
    private static var tickNow = [Double](repeating: 0, count: tickCap)

    @inline(__always) private static func ease(_ a: inout Double, _ v: Double) { a = fed ? a + (v - a) * k : v }

    // One played frame (not in a menu or paused): its split, ms, and the record stages' time this frame (ms).
    static func frame(frameMs f: Double, cpu: Double, tick: Double, record: Double, gpu: Double, rate r: Double,
                      stageNames names: [String], stageMs: [Double]) {
        if stages.count != stageMs.count { stages = stageMs; stageNames = names }
        for i in stageMs.indices { ease(&stages[i], stageMs[i]) }
        ease(&frameMs, f); ease(&cpuMs, cpu); ease(&tickMs, tick); ease(&recordMs, record); ease(&gpuMs, gpu)
        fps = frameMs > 0 ? 1000 / frameMs : 0
        rate = r
        foldTick()
        fed = true
    }

    // The tick just run (TickProf), stage by stage; a stage that didn't run this frame eases towards 0.
    private static func foldTick() {
        for i in 0..<tickCount { tickNow[i] = 0 }
        for j in 0..<TickProf.count {
            let n = TickProf.names[j], t = TickProf.times[j] * 1000
            guard n.hasPointerRepresentation else { continue }
            var at = -1
            for i in 0..<tickCount where tickNames[i].utf8Start == n.utf8Start { at = i; break }
            if at < 0 && tickCount < tickCap { at = tickCount; tickNames[at] = n; tickTimes[at] = 0; tickCount += 1 }
            if at >= 0 { tickNow[at] += t }
        }
        for i in 0..<tickCount { tickTimes[i] += (tickNow[i] - tickTimes[i]) * k }
    }

    // His names for the record stages: what draws the terrain (the cull and the draw lists), the far land (middle
    // ring and the landmark impostors), water and glass, and the rest.
    static let groups: [(String, [String])] = [
        ("Terrain (finding and drawing it)", ["table", "walk", "horizon", "occlusion", "list", "records", "terrain"]),
        ("Far land (middle ring, landmarks)", ["ring", "landmarks"]),
        ("Mobs", ["mobs"]), ("Ships and vehicles", ["ships"]), ("Entities (items, projectiles)", ["entities"]),
        ("Particles", ["particles"]), ("Water and glass", ["translucent"]), ("Sky", ["sky"]),
        ("HUD and menus", ["hud", "ui"]), ("Frame setup", ["uniforms"])]

    // P510: one line for a voice note: the frame split and the three heaviest drawing systems and tick stages.
    static func summary(_ g: Game) -> String {
        func ms(_ v: Double) -> String { String(format: "%.1f", v) }
        var s = String(format: "%.0f fps", fps) + ", CPU \(ms(cpuMs)) ms (tick \(ms(tickMs)), drawing \(ms(recordMs))), GPU \(ms(gpuMs)) ms"
        var parts: [(String, Double)] = []
        for (name, keys) in groups {
            var t = 0.0
            for key in keys { if let i = stageNames.firstIndex(of: key), i < stages.count { t += stages[i] } }
            parts.append((name.split(separator: " (").first.map(String.init) ?? name, t))
        }
        let top = parts.sorted { $0.1 > $1.1 }.prefix(3).filter { $0.1 >= 0.05 }
        if !top.isEmpty { s += "; drawing: " + top.map { "\($0.0) \(ms($0.1))" }.joined(separator: ", ") }
        let order = (0..<tickCount).sorted { tickTimes[$0] > tickTimes[$1] }.prefix(3).filter { tickTimes[$0] >= 0.05 }
        if !order.isEmpty { s += "; tick: " + order.map { "\(tickNames[$0].description) \(ms(tickTimes[$0]))" }.joined(separator: ", ") }
        return s
    }
}
