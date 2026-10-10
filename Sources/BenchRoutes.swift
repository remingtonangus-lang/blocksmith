import Foundation
import Metal
import simd

// The six benchmark routes of docs/STORE_QUALITY.md (objective 1): fixed camera paths through Game.tick and the full
// renderer, logging frame time (p50/p99, hitches > 25 ms per minute), world load time and resident memory.
//   Blocksmith --bench snaps/route_forest.json --scenes route_forest [--secs 30] [--rd N] [--quest]
//   tools/bench_routes.sh [--quest] [--secs N]      all six, each in its own process -> snaps/routes.{json,md}
// Routes: plains (spawn), forest, village, cave, capital (Capital city, the Steelhold base's battle ground) and
// ashvault (through the Ashguard citadel in the Deep, its units spawning and fighting as the chunks load).
// Playtest routes (Oct 10 voice notes, seed 2943808052895834412 unless --seed is given): flyover (fast creative flight,
// 60 blocks/s 50 blocks up, over the taiga and peaks where Auto Render Distance stepped 16 -> 13) and taiga (a walk
// through the taiga village at -280 -1030 where the headset showed 53 fps).
// --quest: Quest-equivalent load on the Mac: two eye views per tick at 1440x1584 (Quest 2 recommended per-eye
// size), the Quest default render distance 8, budget 13.9 ms (72 Hz). The Quest renderer is Vulkan and its GPU is
// slower, so this is a proxy for CPU-side cost and scene load; device numbers come from the app's logcat perf line.
extension Bench {
    static let playtestSeed: UInt64 = 2943808052895834412

    static func route(_ device: MTLDevice, _ benchSeed: UInt64, _ name: String) {
        let seed = (name == "flyover" || name == "taiga") && arg("--seed") == nil ? playtestSeed : benchSeed
        let quest = CommandLine.arguments.contains("--quest")
        if quest { World.fluidSeconds = 0.002; World.lodNear = 5; World.leafNear = 2; World.handoverSeconds = 0.0015 }   // as QuestApp
        if let v = arg("--handover").flatMap({ Double($0) }) { World.handoverSeconds = v / 1000 }   // ms (before/after runs)
        if let v = arg("--lodnear").flatMap({ Int($0) }) { World.lodNear = v }
        if let v = arg("--leafnear").flatMap({ Int($0) }) { World.leafNear = v }
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
        case "flyover":
            p = V3(-859, 0, -710); speed = 60; over = 50; heading = atan2(-127, 276)
        case "taiga":
            if let s = world.gen.structures?.nearest("village", x: -280, z: -1030, maxRegions: 4) {
                p = V3(Float(s.min.x - 24), 0, Float(s.min.z + s.max.z) / 2)
            } else { print("bench route_taiga: no village found near -280 -1030") }
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
        var hitchLines = 0
        var quadSum = 0, drawSum = 0                       // terrain quads / section draws per eye frame
        // Mean and worst ms per tick stage over the run (TickProf), keyed by the stage name's address (no allocation).
        var stageSum: [Int: (StaticString, Double, Double)] = [:]
        var upd: [Double] = []; upd.reserveCapacity(frames)   // World.update (streaming hand-over) ms per tick
        var missed = 0                                         // frames over 1.5x the budget (the headset's "missed")
        var lagSum = 0.0, lagN = 0
        // The tick's own CPU time (thread clock): unlike wall time, other processes on a shared Mac don't inflate it.
        var tickCPU: [Double] = []; tickCPU.reserveCapacity(frames)
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
                let b = now, bc = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                game.tick(dt)
                let tk = now - b
                tickCPU.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - bc) / 1e6)
                for j in 0..<TickProf.count {
                    let nm = TickProf.names[j], key = Int(bitPattern: nm.utf8Start)
                    let o = stageSum[key] ?? (nm, 0, 0)
                    stageSum[key] = (nm, o.1 + TickProf.times[j], max(o.2, TickProf.times[j]))
                }
                upd.append(world.perf.updateSeconds * 1000)
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
            if max(tk + e, g) * 1000 > budget * 1.5 { missed += 1 }
            // A hitch's split (first eight): tick vs CPU encode vs GPU, so a non-tick hitch is named too.
            if max(tk + e, g) * 1000 > 25 && hitchLines < 8 {
                hitchLines += 1
                print("bench \(name) hitch at \(f(Double(i) * dt, 1)) s: tick \(f(tk * 1000)) (\(TickProf.top().0)) encode \(f(e * 1000)) gpu \(f(g * 1000)) ms, jobs \(world.pendingJobs)")
            }
            if i % 30 == 0 { peak = max(peak, residentMB()) }
            // Streaming lag: chunks inside the drawn disc not meshed yet (holes and pop-in), sampled once a second.
            if i % Int(1 / dt) == 0 {
                let cx = Int(floor(p.x / 16)), cz = Int(floor(p.z / 16)), r = rd
                var n = 0, m = 0
                for dz in -r...r { for dx in -r...r where world.inMeshRadius(dx, dz) {
                    n += 1
                    if !(world.chunks[ChunkKey(x: cx + dx, z: cz + dz)]?.meshedOnce ?? false) { m += 1 }
                } }
                lagSum += Double(m) / Double(max(1, n)) * 100; lagN += 1
            }
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
        let fc = dist(tickCPU)
        put("\(k).tick_cpu_ms", fc, "mean,p50,p99")
        put("\(k).gpu_ms", fg, "p50,p99")
        put("\(k).hitches_per_min", perMin)
        put("\(k).resident_start_mb", mem0)
        put("\(k).resident_peak_mb", peak)
        put("\(k).resident_growth_pct", (mem1 - mem0) / max(mem0, 1) * 100)
        put("\(k).mobs", Double(game.mobs.mobs.count))
        put("\(k).quads", Double(quadSum / max(1, frames)))
        put("\(k).draws", Double(drawSum / max(1, frames)))
        put("\(k).budget_ms", budget)
        // Loaded terrain by detail level: solid / cut-out (leaves, plants) / translucent quads (what the GPU draws at most).
        var q = [[Int]](repeating: [0, 0, 0, 0], count: 2)
        for c in world.chunks.values { for sec in c.sections where sec.meshedVersion >= 0 {
            let l = c.lod == 1 ? 1 : 0
            q[l][0] += sec.solidQuads; q[l][1] += sec.opaqueQuads - sec.solidQuads; q[l][2] += sec.transQuads; q[l][3] += 1
        } }
        // Far cut-out quads by face (0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z) and merged (larger than one block).
        var byFace = [Int](repeating: 0, count: 8), merged = 0
        for c in world.chunks.values where c.lod == 1 { for sec in c.sections where sec.meshedVersion >= 0 && sec.opaqueQuads > sec.solidQuads {
            guard let b = sec.opaqueBuf else { continue }
            let p = (b.buffer.contents() + b.offset).bindMemory(to: UInt32.self, capacity: sec.opaqueQuads * 8)
            for qi in sec.solidQuads..<sec.opaqueQuads {
                byFace[Int((p[qi * 8] >> 27) & 7)] += 1
                let w1 = p[qi * 8 + 1]
                if w1 & 31 == 31 && (w1 >> 5) & 31 == 31 { merged += 1 }
            }
        } }
        print("bench \(k) far cut quads by face: \(byFace.prefix(6).map { "\($0 / 1000)k" }.joined(separator: " ")), greedy-path \(merged / 1000)k")
        print("bench \(k) loaded quads: near solid \(q[0][0] / 1000)k cut \(q[0][1] / 1000)k trans \(q[0][2] / 1000)k (\(q[0][3]) sections) | far solid \(q[1][0] / 1000)k cut \(q[1][1] / 1000)k trans \(q[1][2] / 1000)k (\(q[1][3]) sections)")
        let fu = dist(upd)
        put("\(k).update_ms", fu, "mean,p99")
        put("\(k).missed_pct", Double(missed) / Double(max(1, frames)) * 100)
        put("\(k).unmeshed_pct", lagSum / Double(max(1, lagN)))
        let top = stageSum.values.sorted { $0.1 > $1.1 }.prefix(8)
        for (nm, sum, _) in top { put("\(k).stage.\(nm.description)", sum * 1000 / Double(max(1, frames))) }
        print("bench \(k) tick stages, mean ms (worst): " + top.map { "\($0.0) \(f($0.1 * 1000 / Double(max(1, frames)), 3)) (\(f($0.2 * 1000)))" }.joined(separator: ", "))
        print("bench \(k): tick thread CPU mean \(f(fc.mean, 3)) p50 \(f(fc.p50)) p99 \(f(fc.p99)) ms")
        print("bench \(k): world.update mean \(f(fu.mean, 3)) p99 \(f(fu.p99)) ms, missed (> 1.5x budget) \(f(Double(missed) / Double(max(1, frames)) * 100, 1))% of frames, chunks generated \(world.perf.genChunks), sections meshed \(world.perf.meshSections), drawn disc not meshed yet \(f(lagSum / Double(max(1, lagN)), 1))% (mean)")
        put("\(k).pass", over99 && perMin <= 1 ? 1 : 0)
        let sp = spikes.sorted { $0.value.0 > $1.value.0 }.prefix(6).map { "\($0.key) x\($0.value.0) (max \(f($0.value.1)) ms)" }
        if !sp.isEmpty { print("bench \(k) tick spikes > 4 ms by stage: " + sp.joined(separator: ", ")) }
        print("bench \(k): frame p50 \(f(fe.p50)) p99 \(f(fe.p99)) max \(f(fe.max)) ms (budget \(f(budget, 1))), \(f(perMin, 1)) hitches >25 ms/min | tick p99 \(f(ft.p99)) GPU p99 \(f(fg.p99)) ms | load \(f(load, 1)) s | resident \(f(mem0, 0)) -> \(f(mem1, 0)) MB (peak \(f(peak, 0))) | \(game.mobs.mobs.count) mobs, \(quadSum / max(1, frames) / 1000)k quads, \(drawSum / max(1, frames)) draws | \(over99 && perMin <= 1 ? "PASS" : "FAIL")")
    }
}
