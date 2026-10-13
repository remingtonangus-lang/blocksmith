import Foundation
import Metal
import simd

// P124 (Oct 12 PM, "a frame drop with a freeze of about a second"): a persistent survival game walked across new
// ground and left standing, every tick timed; the slowest ticks with their slowest stages (TickProf).
enum HitchProbe {
    struct Slow { let ms: Double; let at: Double; let stages: String }

    // Walks `walk` seconds at `speed` (m/s) along +x from the spawn, then stands `stand` seconds; returns every tick
    // over `over` ms (slowest first) and the worst main-thread autosave.
    static func run(device: MTLDevice, seed: UInt64, walk: Double, stand: Double, speed: Float = 7, over: Double = 40,
                    rd: Int = 6, start: V2? = nil) -> (slow: [Slow], ticks: Int, save: Double) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("p124-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let off0 = StructureCache.plansOffThread
        StructureCache.plansOffThread = true                      // as in the game: base ticks never plan starts themselves
        defer { SaveIO.flush(); try? FileManager.default.removeItem(at: root); StructureCache.plansOffThread = off0 }
        let save = SaveManager(dir: root.appendingPathComponent("Hitch", isDirectory: true))
        let w = World(seed: seed, device: device, save: save)
        w.renderDistance = rd
        let g = Game(world: w, save: save, persistent: true)
        g.saveNow()
        var p = g.spawnPoint
        if let s = start { p = V3(s.x, Float(w.gen.column(Int(s.x), Int(s.y)).height + 3), s.y) }
        g.player.pos = p
        g.survival = true; g.paused = false; g.player.flying = true
        _ = w.loadSync(center: p, radius: 4)
        var slow: [Slow] = [], ticks = 0, worstSave = 0.0
        let dt = 1.0 / 72
        var t = 0.0
        while t < walk + stand {
            if t < walk {
                p.x += speed * Float(dt)
                let top = w.topY(Int(floor(p.x)), Int(floor(p.z)))
                if top > 0 { p.y = Float(top) + 3 }
                g.player.pos = p; g.player.vel = .zero
            }
            g.health = 20; g.hunger = 20
            if g.menu != nil { g.menu = nil }
            let t0 = CFAbsoluteTimeGetCurrent()
            g.tick(dt)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            ticks += 1
            if t > 3 && ms > over { slow.append(Slow(ms: ms, at: t, stages: TickProf.summary())) }
            t += dt
        }
        let s0 = CFAbsoluteTimeGetCurrent()
        g.saveNow(background: true)
        worstSave = (CFAbsoluteTimeGetCurrent() - s0) * 1000
        return (slow.sorted { $0.ms > $1.ms }, ticks, worstSave)
    }
}
