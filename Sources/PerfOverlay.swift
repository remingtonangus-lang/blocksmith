import Foundation

// L3 (docs/status/l3-part3.md): an optional performance overlay (Options > Interface > Performance Overlay): two short
// lines in the HUD's top-right corner: frame rate, average and worst frame time over the last second, GPU time; the
// render distance (and what Auto Render Distance has it at), loaded chunks and queued chunk jobs. Shared: the Mac
// renderer and the Quest HUD panel both draw it (Renderer.buildHUD); each host feeds frame times with add(frameMs:).
final class PerfOverlay {
    static let shared = PerfOverlay()
    // A ring of the last 128 frame times (no allocation per frame).
    private var ring = [Double](repeating: 0, count: 128)
    private var head = 0, filled = 0
    private var stamp = [Double](repeating: 0, count: 128)

    func add(frameMs: Double, at now: Double = CFAbsoluteTimeGetCurrent()) {
        ring[head] = frameMs; stamp[head] = now
        head = (head + 1) & 127
        filled = min(128, filled + 1)
    }

    // Average and worst frame time over the frames of the last second (up to 128).
    func window(now: Double = CFAbsoluteTimeGetCurrent()) -> (avg: Double, worst: Double, frames: Int) {
        var sum = 0.0, worst = 0.0, n = 0
        for k in 0..<filled {
            let i = (head - 1 - k + 256) & 127
            guard now - stamp[i] <= 1 else { break }
            sum += ring[i]; worst = max(worst, ring[i]); n += 1
        }
        return (n > 0 ? sum / Double(n) : 0, worst, n)
    }

    func reset() { head = 0; filled = 0 }

    static func lines(fps: Double, gpuMs: Double, game: Game, now: Double = CFAbsoluteTimeGetCurrent()) -> [String] {
        let w = shared.window(now: now)
        var a = "\(Int(fps.rounded())) fps  " + String(format: "%.1f ms (worst %.1f)", w.avg, w.worst)
        if gpuMs > 0 { a += String(format: "  GPU %.1f ms", gpuMs) }
        let world = game.world
        let chosen = game.chosenRenderDistance, rd = world.renderDistance
        let dist = rd < chosen ? "Render distance \(rd) of \(chosen) (auto)" : "Render distance \(rd)"
        return [a, "\(dist)  Chunks \(world.chunks.count), \(world.pendingJobs) jobs"]
    }
}
