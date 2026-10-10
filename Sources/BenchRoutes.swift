import Foundation
import Metal
import simd

// The six benchmark routes of docs/STORE_QUALITY.md (objective 1): fixed camera paths through Game.tick and the full
// renderer, logging frame time (p50/p99, hitches > 25 ms per minute), world load time and resident memory.
//   Blocksmith --bench snaps/route_forest.json --scenes route_forest [--secs 30] [--rd N] [--quest]
//   tools/bench_routes.sh [--quest] [--secs N]      all six, each in its own process -> snaps/routes.{json,md}
// Routes: plains (spawn), forest, village, cave, capital (Capital city, the Steelhold base's battle ground) and
// ashvault (through the Ashguard citadel in the Deep, its units spawning and fighting as the chunks load).
// --quest: Quest-equivalent load on the Mac: two eye views per tick at 1440x1584 (Quest 2 recommended per-eye
// size), the Quest default render distance 8, budget 13.9 ms (72 Hz). The Quest renderer is Vulkan and its GPU is
// slower, so this is a proxy for CPU-side cost and scene load; device numbers come from the app's logcat perf line.
extension Bench {
    static func route(_ device: MTLDevice, _ seed: UInt64, _ name: String) {
        let quest = CommandLine.arguments.contains("--quest")
        if quest { World.fluidSeconds = 0.002 }      // as QuestApp sets it
        if let v = arg("--lodnear").flatMap({ Int($0) }) { World.lodNear = v }
        let rd = Int(arg("--rd") ?? "") ?? 8
        let seconds = Double(arg("--secs") ?? "") ?? 30
        let dim: Dim = name == "ashvault" ? .deep : .overworld
        let world = World(seed: seed, device: device, save: nil, dim: dim)
        world.renderDistance = rd
        let game = Game(world: world, save: nil, persistent: false)
        game.paused = false
        game.time = 0.27 * DAY_LENGTH
        game.player.flying = true
        func ground(_ x: Float, _ z: Float) -> Float {
            if let d = world.gen as? DeepGen { return Float(d.floorY(Int(floor(x)), Int(floor(z))) + 1) }
            return Float(max(world.gen.column(Int(floor(x)), Int(floor(z))).height, SEA) + 1)
        }
        // Start point, speed (blocks/s), height over the ground (nil: a fixed y), heading (radians, 0 = +x).
        var p = game.findSpawn()
        var speed: Float = 5.6, over: Float? = 1.62, heading: Float = 0
        switch name {
        case "plains": break                                               // sprint speed across the spawn area
        case "forest":
            if let f = Snapshot.findBiome(world.gen, "forest", interior: true) { p = f }
        case "village", "capital":
            let kind = name == "village" ? "village" : "capital_city"
            if let s = world.gen.structures?.nearest(kind, x: Int(p.x), z: Int(p.z), maxRegions: 16) {
                // Cross the footprint through its middle, starting just outside the west edge.
                p = V3(Float(s.min.x - 24), 0, Float(s.min.z + s.max.z) / 2)
                if name == "capital" { speed = 10; over = 22 }
            } else { print("bench route_\(name): no \(kind) found near spawn") }
        case "cave":
            // The first open cave space around displayed y -20 near spawn, then a slow walk-speed flight at that level.
            let x0 = Int(p.x), z0 = Int(p.z), y0 = YOFF - 20
            search: for r in stride(from: 0, through: 96, by: 2) { for dz in stride(from: -r, through: r, by: 2) { for dx in stride(from: -r, through: r, by: 2) where max(abs(dx), abs(dz)) == r {
                for dy in stride(from: -16, through: 16, by: 2) where world.block(x0 + dx, y0 + dy, z0 + dz) == AIR && world.block(x0 + dx, y0 + dy + 1, z0 + dz) == AIR {
                    p = V3(Float(x0 + dx) + 0.5, Float(y0 + dy) + 1, Float(z0 + dz) + 0.5); break search
                }
            } } }
            speed = 4.3; over = nil
        case "ashvault":
            p = V3(-90, 0, 4); speed = 6; over = 3            // the citadel stands at x 0, z 0
        default: print("bench: unknown route \(name)"); return
        }
        if let o = over { p.y = ground(p.x, p.z) + o }
        game.player.pos = p
        game.player.yaw = -.pi / 2 + heading                      // looking along +x, the travel direction
        game.player.pitch = -6 * .pi / 180
        let a = now
        _ = world.loadSync(center: p, radius: rd)
        let load = now - a
        let (ew, eh) = quest ? (1440, 1584) : (1920, 1080)
        guard let r = try? Renderer(device: device, game: game, colorFormat: .bgra8Unorm),
              let target = OffscreenTarget(device, ew, eh) else { return }
        for _ in 0..<3 { _ = r.benchFrame(target) }
        let budget = quest ? 1000.0 / 72 : 1000.0 / 60
        let dt = quest ? 1.0 / 72 : 1.0 / 60
        let frames = Int(seconds / dt)
        var est: [Double] = [], tick: [Double] = [], gpu: [Double] = []
        var spikes: [String: (Int, Double)] = [:]
        var quadSum = 0, drawSum = 0                       // terrain quads / section draws per eye frame
        est.reserveCapacity(frames); tick.reserveCapacity(frames); gpu.reserveCapacity(frames)
        let mem0 = residentMB()
        var peak = mem0
        let start = now
        for i in 0..<frames {
            p.x += speed * Float(dt) * cos(heading); p.z += speed * Float(dt) * sin(heading)
            if let o = over { let want = ground(p.x, p.z) + o; p.y = want > p.y ? want : max(want, p.y - 6 * Float(dt)) }
            game.player.pos = p
            game.player.vel = .zero
            let (tk, e, g): (Double, Double, Double) = autoreleasepool {
                let b = now
                game.tick(dt)
                let tk = now - b
                var (e, g) = r.benchFrame(target)
                quadSum += r.drawnQuads; drawSum += r.drawCalls
                if quest { let (e2, g2) = r.benchFrame(target); e += e2; g += g2 }   // the second eye
                return (tk, e, g)
            }
            tick.append(tk * 1000); gpu.append(g * 1000)
            // Tick spikes (a quarter of the Quest budget on the M1, about a full frame on the Quest's XR2): which stage.
            if tk * 1000 > 4 {
                let (n, ms) = TickProf.top()
                let old = spikes[n.description] ?? (0, 0)
                spikes[n.description] = (old.0 + 1, max(old.1, ms))
            }
            est.append(max(tk + e, g) * 1000)
            if i % 30 == 0 { peak = max(peak, residentMB()) }
            let slack = start + Double(i + 1) * dt - now
            if slack > 0 { usleep(useconds_t(slack * 1e6)) }
        }
        let mem1 = residentMB()
        peak = max(peak, mem1)
        let k = "route_\(name)\(quest ? "_quest" : "")"
        let fe = dist(est), ft = dist(tick), fg = dist(gpu)
        let hitches = est.filter { $0 > 25 }.count
        let perMin = Double(hitches) / (seconds / 60)
        let over99 = fe.p99 <= budget
        put("\(k).load_ms", load * 1000)
        put("\(k).frame_ms", fe, "p50,p99,max")
        put("\(k).tick_ms", ft, "p50,p99")
        put("\(k).gpu_ms", fg, "p50,p99")
        put("\(k).hitches_per_min", perMin)
        put("\(k).resident_start_mb", mem0)
        put("\(k).resident_peak_mb", peak)
        put("\(k).resident_growth_pct", (mem1 - mem0) / max(mem0, 1) * 100)
        put("\(k).mobs", Double(game.mobs.mobs.count))
        put("\(k).quads", Double(quadSum / max(1, frames)))
        put("\(k).draws", Double(drawSum / max(1, frames)))
        put("\(k).budget_ms", budget)
        put("\(k).pass", over99 && perMin <= 1 ? 1 : 0)
        let sp = spikes.sorted { $0.value.0 > $1.value.0 }.prefix(6).map { "\($0.key) x\($0.value.0) (max \(f($0.value.1)) ms)" }
        if !sp.isEmpty { print("bench \(k) tick spikes > 4 ms by stage: " + sp.joined(separator: ", ")) }
        print("bench \(k): frame p50 \(f(fe.p50)) p99 \(f(fe.p99)) max \(f(fe.max)) ms (budget \(f(budget, 1))), \(f(perMin, 1)) hitches >25 ms/min | tick p99 \(f(ft.p99)) GPU p99 \(f(fg.p99)) ms | load \(f(load, 1)) s | resident \(f(mem0, 0)) -> \(f(mem1, 0)) MB (peak \(f(peak, 0))) | \(game.mobs.mobs.count) mobs, \(quadSum / max(1, frames) / 1000)k quads, \(drawSum / max(1, frames)) draws | \(over99 && perMin <= 1 ? "PASS" : "FAIL")")
    }
}
