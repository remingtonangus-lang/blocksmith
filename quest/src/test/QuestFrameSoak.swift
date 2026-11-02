import Foundation
import simd
import Metal
import CVulkan

// Store review (Meta, Nov 2: VRC.Quest.Performance.1 failed on build 0.129 b18429a6, "Your app fluctuates under and
// over 60 frames per second... the frame rate must maintain a steady rate above 60"). questcheck --framesoak [--only
// crawler,citadel,naval,train,hell,battle] [--seconds 40] [--rd 10]: each of the heavy scenes of normal play, played in
// real time at 72 Hz with the headset's settings (QuestApp's world statics, a Polygons world, its mesh workers running
// beside the frame as they do on the headset), the frame thread doing what QuestApp.frame does: Game.tick, then the
// world's record on the Quest renderer. Every frame's split is kept; the report gives, per scene, the frame thread's
// time (host ms and the headset's estimate), how many frames the headset would miss on the CPU side, the longest run
// of them, what the slowest frames spent their time on, and the GPU's load as the quads and draws it is handed.
// The headset's estimate is the host time x `questFactor` (P385: his headset log had the record at 10-12 ms where the
// host took 6.95 ms for the same view; 1.7 is the pessimistic end). The cloud has no Adreno: the GPU side is the quads
// and draws, never a time.
enum QuestFrameSoak {
    static let questFactor = 1.7
    static let budgetMs = 1000.0 / 72
    static var hostBudgetMs: Double { budgetMs / questFactor }

    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    // A scene: its world, where he is and what he does each frame.
    struct Setup {
        var name: String
        var what: String
        var seed: UInt64
        var dim: Dim = .overworld
        var at: V3                       // (internal y)
        var prepare: (Game) -> Void      // after the first load, before the frames
        var step: (Game, Int) -> Void    // every frame, before the tick
    }

    static let crawlerSeed: UInt64 = 7653607216494784574
    static let crawlerAt = V3(-22251.7, 160.4, 15846.4)

    // The crawler at his Nov 2 spot (FAILURES list: "i can't see shit around me when i am driving it"), driving on at
    // 8 b/s with him at its helm; its main gun fired ahead every 5 s.
    static func crawlerScene(parkedBy citadel: Bool) -> Setup {
        var crawler: Ship?
        var aim = V3(0, 0, 0)
        return Setup(name: citadel ? "citadel" : "crawler",
                     what: citadel ? "the crawler parked 40 blocks off a capital citadel's wall, main gun firing into it every 5 s, the garrison awake"
                                   : "driving the Ironback Crawler at 8 b/s over new land, main gun fired ahead every 5 s",
                     seed: crawlerSeed, at: crawlerAt,
                     prepare: { g in
            let w = g.world
            w.ships.encounters = false
            var home = g.player.pos
            var yaw: Float = 0
            if citadel, let st = w.gen.structures?.nearest("military_base", x: Int(home.x), z: Int(home.z), maxRegions: 24) {
                let cx = Float(st.min.x + st.max.x) / 2, cz = Float(st.min.z + st.max.z) / 2
                home = V3(Float(st.min.x) - 40, home.y, cz)
                aim = V3(cx, Float(st.pieces[0].min.y + 12), cz)
                yaw = -.pi / 2                                       // (facing east, at the citadel)
                g.player.pos = home
                _ = w.loadSync(center: home, radius: w.renderDistance)
                for (name, p) in w.pendingMobs { if let m = Mob.structureMob(name, at: p) { g.mobs.mobs.append(m) } }
                w.pendingMobs.removeAll()
                print(String(format: "framesoak: citadel at %.0f %.0f, the crawler 40 blocks off its west wall", cx, cz))
            }
            w.ships.spawnCapital("crawler", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z))), yaw: yaw, region: nil, sync: true)
            guard let c = w.ships.capitals.first(where: { $0.role == "crawler" }), let st = w.ships.capState[c.id], let hc = c.helm else {
                print("framesoak: no crawler could be spawned"); return
            }
            st.crewDone = Set(0..<st.crew.count); st.crewless = true
            st.testTurn = 0; st.testSpeed = citadel ? 0 : 8
            crawler = c
            g.player.flying = false
            g.player.pos = c.toWorld(V3(Float(hc.x) + 0.5, Float(hc.y) + 1.02, Float(hc.z) + 1.5))
            g.player.vel = c.velocity(at: g.player.pos)
            g.player.yaw = yaw; g.player.pitch = -0.15
        }, step: { g, f in
            guard let c = crawler, let st = g.world.ships.capState[c.id] else { return }
            if citadel { g.survival = true; g.health = 20; g.alive = true }
            if f % 360 == 180 {
                let mw = c.toWorld(st.mainGunMuzzle)
                let dir = citadel ? simd_normalize(aim - mw + V3(1e-5, 0, 0)) : simd_normalize(c.dirToWorld(st.mainGunDir) + V3(0, -0.08, 0))
                g.world.ships.fireMainGun(c, st, dir: dir, game: g)
            }
        })
    }

    // A naval gun fight: two hostile Meridian frigates shelling him on a stone float at sea (the P283 ocean spot).
    static func navalScene() -> Setup {
        Setup(name: "naval", what: "two hostile frigates firing on him at sea, 80-100 blocks off",
              seed: 3931512493184456980, at: V3(11576.9, 62.8 + Float(YOFF), -12552.1),
              prepare: { g in
            let w = g.world
            w.ships.encounters = false
            let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
            let top = SEA
            for dz in -3...3 { for dx in -3...3 { w.setBlock(x + dx, top, z + dz, STONE) } }
            g.player.pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
            g.player.flying = false
            g.survival = true; g.difficulty = 2
            w.ships.spawnCapital("capfrigate", home: IVec3(x, 0, z + 90), yaw: 0, region: nil, sync: true)
            w.ships.spawnCapital("capfrigate", home: IVec3(x - 85, 0, z - 30), yaw: .pi / 2, region: nil, sync: true)
            g.player.yaw = .pi; g.player.pitch = -0.1
            print("framesoak: \(w.ships.capitals.count) frigates at sea round him")
        }, step: { g, _ in g.survival = true; g.health = 20; g.alive = true })
    }

    // Riding a passenger train from the cab along the nearest line to his jungle spot (seed of FAILURES 3).
    static func trainScene() -> Setup {
        var drive: (() -> Void)?
        return Setup(name: "train", what: "driving a passenger train from the cab, regulator open",
                     seed: crawlerSeed, at: V3(-5572, 141, 2813),
                     prepare: { g in
            guard let gen = g.world.gen as? WorldGen else { return }
            let ax = Int(g.player.pos.x), az = Int(g.player.pos.z)
            guard let l = Railways.near(gen, x0: ax - 3000, z0: az - 3000, x1: ax + 3000, z1: az + 3000, pad: 0)
                .filter({ $0.stations.count >= 2 })
                .min(by: { abs($0.minX - ax) + abs($0.minZ - az) < abs($1.minX - ax) + abs($1.minZ - az) }) else { print("framesoak: no line near"); return }
            let t = Trains.track(l)
            let c0 = l.cells[l.stations[0].index]
            g.player.pos = V3(Float(c0.x) + 0.5, Float(c0.y), Float(c0.z - 2) + 0.5)
            _ = g.world.loadSync(center: g.player.pos, radius: g.world.renderDistance)
            Trains.trains.removeAll()
            var at = g.time
            for k in 0..<Int(t.period) { let a = t.at(g.time + Double(k)); if a.stop == 0 && a.dir > 0 { at = g.time + Double(k) + 1; break } }
            g.time = at
            Trains.forceKind = .passenger
            Trains.tick(g)
            Trains.forceKind = nil
            guard let tr = Trains.trains[t.id], let lead = tr.cars.first else { print("framesoak: no train built on \(l.name)"); return }
            _ = Trains.use(g, lead)
            drive = { tr.throttle = 2; if g.riding == nil, let c = tr.cars.first { _ = Trains.use(g, c) } }
            print("framesoak: on \(l.name) (\(l.cells.count) cells), \(tr.cars.count) cars")
        }, step: { _, _ in drive?() })
    }

    // The Emberdeep: flying on through it at 8 b/s from over a fortress, its mobs about.
    static func hellScene() -> Setup {
        Setup(name: "hell", what: "the Emberdeep, flying on at 8 b/s from a fortress",
              seed: crawlerSeed, dim: .nether, at: V3(0, 80 + Float(YOFF) - 64, 0),
              prepare: { g in
            if let st = g.world.gen.structures?.nearest("fortress", x: 0, z: 0, maxRegions: 16) {
                g.player.pos = V3(Float(st.anchor.x) + 0.5, Float(st.anchor.y + 6), Float(st.anchor.z) + 0.5)
                print("framesoak: fortress at \(st.anchor.x) \(st.anchor.y) \(st.anchor.z)")
            }
            g.player.flying = true
            g.player.yaw = 0.7; g.player.pitch = -0.2
        }, step: { g, _ in
            g.player.flying = true
            let yaw = g.player.yaw
            g.player.pos += V3(-sinf(yaw), 0, -cosf(yaw)) * (8.0 / 72)
            g.player.vel = .zero
        })
    }

    // The biggest battle: the Ash Vault citadel's north gate at Total War (AshVaultGapTests.battleScene).
    static func battleScene() -> Setup {
        var stand = V3(0, 0, 0)
        return Setup(name: "battle", what: "the Ash Vault citadel's gate at Total War, every garrison awake",
                     seed: crawlerSeed, at: V3(0, 160, 0),
                     prepare: { g in stand = AshVaultGapTests.battleScene(g); g.player.yaw = .pi; g.player.pitch = 0.05 },
                     step: { g, _ in g.health = 20; g.alive = true; g.ashSpot = stand; g.ashSpotSeen = g.clock })
    }

    // Ordinary play (Meta didn't say where the dips were: "These fluctuations can be found in the game"): on foot with
    // the stick forward, or flying at the creative sprint, through his own slow spots.
    static func moving(_ name: String, _ what: String, seed: UInt64, x: Float, y: Float, z: Float, yaw: Float, pitch: Float, fly: Bool) -> Setup {
        Setup(name: name, what: what, seed: seed, at: V3(x, y + Float(YOFF), z),
              prepare: { g in
            g.player.flying = fly
            g.survival = !fly
            g.player.yaw = -yaw * .pi / 180; g.player.pitch = pitch * .pi / 180
            if fly {
                // (over the land, not into the hill ahead: 30 over the highest ground within 64 blocks)
                var top = Int(g.player.pos.y)
                for d in stride(from: 0, through: 64, by: 4) {
                    let px = Int(g.player.pos.x - sinf(g.player.yaw) * Float(d)), pz = Int(g.player.pos.z - cosf(g.player.yaw) * Float(d))
                    if let c = g.world.chunkAt(px, pz) { top = max(top, Int(c.height[mod(px, CS) + mod(pz, CS) * CS])) }
                }
                g.player.pos.y = Float(top + 30)
            } else {
                let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
                var y = CH - 2
                while y > 1 && !g.world.solidAt(px, y - 1, pz) { y -= 1 }
                g.player.pos.y = Float(y) + 0.01
            }
        }, step: { g, f in
            if !fly { g.survival = true; g.health = 20; g.alive = true }
            var pad = PadSnapshot()
            pad.ly = 1
            pad.rx = f % 720 < 360 ? 0.25 : -0.25            // (looking about as he walks)
            PadManager.shared.touch = pad
            g.input.control = fly
        })
    }

    static var ordinary: [Setup] {
        [moving("jungle", "walking through his Nov 2 08:23 jungle (49-56 fps in his notes)", seed: crawlerSeed, x: -5583.8, y: 75.7, z: 2823.8, yaw: 344, pitch: -20, fly: false),
         moving("town", "walking through Stone Gulch, the savanna town (P374: 45-54 fps)", seed: 13480747113613945685, x: 6094.4, y: 88.0, z: 688.6, yaw: 123, pitch: -12, fly: false),
         moving("forest", "flying at the creative sprint over the Oct 24 forest", seed: 5663059916303033239, x: 692.3, y: 119.8, z: 638.9, yaw: 340, pitch: -20, fly: true),
         moving("taiga", "flying at the creative sprint into new taiga (Oct 24: 41-49 fps)", seed: 5933896066598527833, x: 4740.5, y: 143.5, z: -3278.6, yaw: 320, pitch: -20, fly: true)]
    }

    static var scenes: [Setup] { ordinary + [crawlerScene(parkedBy: false), crawlerScene(parkedBy: true), navalScene(), trainScene(), hellScene(), battleScene()] }

    struct Slow { var cpu: Double; var tick: Double; var record: Double; var why: String }

    static func run(ctx: VkContext) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 99; World.leafNear = QuestApp.leafNear
        World.editLane = true; GroundSettle.spread = true                           // (QuestApp)
        // (as the game runs, not the host checks' fixtures: bases planned on workers, the headset's world rules)
        StructureCache.plansOffThread = true
        World.resultsProfile = true                                                // (the slowest single hand-over, per scene)
        ShipManager.stepRate = 72; ShipManager.stepSlack = 0.2 / 72                // (QuestApp: one ship step a drawn frame)
        Blueprints.on = true; TownSizes.on = true; MobVary.on = true; Soldier.unarmedPeace = true
        World.fewerLakesUnsaved = true; World.lessWaterUnsaved = true; WorldRules.p44 = true
        SceneRenderer.skipGPU = true
        let only = arg("--only").map { Set($0.split(separator: ",").map(String.init)) }
        let secs = Int(arg("--seconds") ?? "") ?? 40
        let rd = Int(arg("--rd") ?? "") ?? 10
        print(String(format: "framesoak: %d s a scene in real time at 72 Hz, view %d, %d cores; the headset's frame thread taken as %.1fx the host's (budget %.1f ms there = %.1f ms here)",
                     secs, rd, ProcessInfo.processInfo.activeProcessorCount, questFactor, budgetMs, hostBudgetMs))
        var bad = 0
        var table: [String] = []
        for sc in scenes where only == nil || only!.contains(sc.name) {
            do { let (ok, line) = try scene(sc, rd: rd, secs: secs, ctx: ctx); table.append(line); if !ok { bad += 1 } }
            catch { print("framesoak: \(sc.name): \(error)"); return 1 }
        }
        print("framesoak summary (headset estimate; a miss = a frame thread over \(String(format: "%.1f", budgetMs)) ms there):")
        for l in table { print("  " + l) }
        return bad == 0 ? 0 : 1
    }

    static func pct(_ a: [Double], _ p: Int) -> Double { a.isEmpty ? 0 : a.sorted()[min(a.count - 1, a.count * p / 100)] }

    static func scene(_ sc: Setup, rd: Int, secs: Int, ctx: VkContext) throws -> (Bool, String) {
        let device = sharedSystemDevice
        TextureGen.registerAll()
        let w = World(seed: sc.seed, device: device, save: nil, dim: sc.dim)
        let field = sc.dim == .overworld
        if field { FieldTerrain.newWorlds = true; w.makeFieldWorld() }
        w.renderDistance = rd
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = field
        SmoothTerrain.use(world: field, world: w)
        g.survival = false
        g.paused = false
        g.input.captured = true
        g.time = 0.2 * DAY_LENGTH
        g.player.flying = true
        g.player.pos = sc.at
        let a0 = CFAbsoluteTimeGetCurrent()
        _ = w.loadSync(center: g.player.pos, radius: rd)
        StructureCache.plansOffThread = false                            // (the scene's own lookups answered at once)
        sc.prepare(g)
        _ = g.spawnPoint                                // (a save has it; a fresh game settles it at its spawn, not mid-soak)
        StructureCache.plansOffThread = true
        let loadS = CFAbsoluteTimeGetCurrent() - a0

        let scene = try SceneRenderer(ctx: ctx, device: device as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: g)
        wr.landmarkHost = Renderer(game: g)
        let size = 48
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let targets = [try scene.makeTarget(image: img.image, width: size, height: size), try scene.makeTarget(image: img.image, width: size, height: size)]
        let t = tanf(52 * .pi / 180)
        func camera() -> EyeCamera {
            let gw = g.world
            let ringFar: Float = FarRing.enabled && gw.dim == Dim.overworld ? FarRing.outer + 96 : 0
            let ships = gw.ships.list.contains { $0.kinematic }
            let far = max(Float(gw.renderDistance * 16 + 96), ringFar, ships ? 1000 : 0)
            let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t * 0.95, tanDown: -t * 0.95, near: 0.05, far: far)
            let head = simd_quatf(angle: g.player.yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: g.player.pitch, axis: V3(1, 0, 0))
            let vps = ([-0.032, 0.032] as [Float]).map { proj * XRMath.inversePose(head, head.act(V3($0, 0, 0))) }
            return EyeCamera(center: g.player.eye, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, V3(0, 0, 0)),
                             yaw: g.player.yaw, pitch: g.player.pitch, far: far)
        }
        let dt = 1.0 / 72
        var cpu: [Double] = [], ticks: [Double] = [], recs: [Double] = [], quads: [Double] = [], draws: [Double] = []
        var slow: [Slow] = []
        var misses = 0, run = 0, longest = 0
        // (the frame thread's own CPU time too: on the 4-core host the mesh and gen workers can take its core for a few
        // ms; a missed frame whose CPU time fits the budget was the host's scheduler, not the game's work)
        var cpuMisses = 0, cpuRun = 0, cpuLongest = 0
        @inline(__always) func threadMs() -> Double {
            var ts = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
            return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
        }
        let frames = secs * 72
        let warm = 3 * 72                                                    // (the first 3 s: first meshes in, not counted)
        World.resultsWorstMs = 0; World.resultsWorst = ""; Explosion.worstMs = 0; Explosion.worstLaps = ""
        let t0 = CFAbsoluteTimeGetCurrent()
        var mobsPeak = 0, shellsPeak = 0
        var stages: [String: (Double, Double)] = [:]
        for f in 0..<(frames + warm) {
            if g.menu != nil { g.closeMenu() }
            g.cine.active = false
            g.input.keys.removeAll(keepingCapacity: true)
            g.input.captured = true
            sc.step(g, f)
            let a = CFAbsoluteTimeGetCurrent()
            let ta = threadMs()
            g.tick(dt)
            let tk = (CFAbsoluteTimeGetCurrent() - a) * 1000
            let tickWhy = TickProf.summary()
            if f >= warm {
                for i in 0..<TickProf.count {
                    let k = TickProf.names[i].description, ms = TickProf.times[i] * 1000
                    let o = stages[k] ?? (0, 0)
                    stages[k] = (o.0 + ms, max(o.1, ms))
                }
            }
            let s = scene.beginFrame()
            let b = CFAbsoluteTimeGetCurrent()
            wr.record(s, targets[f % 2], camera())
            let rc = (CFAbsoluteTimeGetCurrent() - b) * 1000
            vkCmdEndRenderPass(s.cmd)
            let own = threadMs() - ta
            try scene.submit(s)
            if f >= warm {
                let c = tk + rc
                if own * questFactor > budgetMs { cpuMisses += 1; cpuRun += 1; cpuLongest = max(cpuLongest, cpuRun) } else { cpuRun = 0 }
                cpu.append(c); ticks.append(tk); recs.append(rc)
                quads.append(Double(scene.drawnQuads)); draws.append(Double(scene.drawCalls))
                mobsPeak = max(mobsPeak, g.mobs.mobs.count); shellsPeak = max(shellsPeak, g.world.ships.shells.count)
                if c * questFactor > budgetMs {
                    misses += 1; run += 1; longest = max(longest, run)
                    if slow.count < 400 {
                        let st = wr.stageFrame
                        let top = st.indices.sorted { st[$0] > st[$1] }.prefix(2)
                            .map { "\(WorldRenderer.stageNames[min($0, WorldRenderer.stageNames.count - 1)]) \(String(format: "%.1f", st[$0]))" }.joined(separator: " + ")
                        slow.append(Slow(cpu: c, tick: tk, record: rc, why: "tick: \(tickWhy); record: \(top); own CPU \(String(format: "%.1f", own))"))
                    }
                } else { run = 0 }
            }
            // Paced as the headset paces its frames (xrWaitFrame), so the mesh and gen workers get the time they get there.
            let due = t0 + Double(f + 1) * dt
            let now = CFAbsoluteTimeGetCurrent()
            if due > now { usleep(useconds_t((due - now) * 1_000_000)) }
        }
        scene.waitIdle()
        let n = Double(max(1, cpu.count))
        let mean = cpu.reduce(0, +) / n
        print(String(format: "framesoak %@ (%@): loaded in %.1f s; %d frames; peak %d mobs, %d shells in flight, %d ships",
                     sc.name, sc.what, loadS, cpu.count, mobsPeak, shellsPeak, g.world.ships.list.count))
        print(String(format: "    frame thread (host ms): mean %.2f p95 %.2f p99 %.2f worst %.1f; tick mean %.2f p99 %.2f worst %.1f; record mean %.2f p99 %.2f worst %.1f",
                     mean, pct(cpu, 95), pct(cpu, 99), cpu.max() ?? 0, ticks.reduce(0, +) / n, pct(ticks, 99), ticks.max() ?? 0,
                     recs.reduce(0, +) / n, pct(recs, 99), recs.max() ?? 0))
        print(String(format: "    headset estimate: mean %.1f ms, p99 %.1f ms, worst %.0f ms; %d frames of %d over %.1f ms (%.2f%%), longest run %d",
                     mean * questFactor, pct(cpu, 99) * questFactor, (cpu.max() ?? 0) * questFactor, misses, cpu.count, budgetMs, Double(misses) * 100 / n, longest))
        print(String(format: "    by the frame thread's own CPU time: %d frames over (%.2f%%), longest run %d (the rest of the misses: the host's scheduler)",
                     cpuMisses, Double(cpuMisses) * 100 / n, cpuLongest))
        print(String(format: "    GPU load: quads p50 %.0fk p95 %.0fk max %.0fk; draws p50 %.0f p95 %.0f max %.0f",
                     pct(quads, 50) / 1000, pct(quads, 95) / 1000, (quads.max() ?? 0) / 1000, pct(draws, 50), pct(draws, 95), draws.max() ?? 0))
        print("    tick stages (mean/worst ms): " + stages.sorted { $0.value.0 > $1.value.0 }.prefix(10)
            .map { "\($0.key) \(String(format: "%.2f/%.1f", $0.value.0 / n, $0.value.1))" }.joined(separator: ", "))
        print("    tick stages by worst (ms): " + stages.sorted { $0.value.1 > $1.value.1 }.prefix(8)
            .map { "\($0.key) \(String(format: "%.1f", $0.value.1))" }.joined(separator: ", "))
        if Explosion.worstMs > 0 { print(String(format: "    slowest blast: %.1f ms (%@)", Explosion.worstMs, Explosion.worstLaps)) }
        print("    record stages (ms a frame): " + wr.takeStages())
        print(String(format: "    slowest hand-over of a finished job: %.1f ms (%@)", World.resultsWorstMs, World.resultsWorst))
        // What the slow frames were doing: the most common slowest stage, and the five slowest frames.
        var why: [String: Int] = [:]
        for s in slow { why[String(s.why.split(separator: ";").first ?? ""), default: 0] += 1 }
        if !slow.isEmpty {
            print("    slow frames' tick leaders: " + why.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) x\($0.value)" }.joined(separator: ", "))
            for s in slow.sorted(by: { $0.cpu > $1.cpu }).prefix(6) {
                print(String(format: "    slow: %.1f ms (tick %.1f, record %.1f): %@", s.cpu, s.tick, s.record, s.why))
            }
        }
        PadManager.shared.touch = nil
        withExtendedLifetime((img, targets, wr)) {}
        let ok = Double(misses) / n < 0.005 && longest < 3
        let line = String(format: "%@ %@: mean %.1f ms, p99 %.1f, worst %.0f; %d misses (%.2f%%), longest run %d; quads p95 %.0fk",
                          ok ? "ok  " : "SLOW", sc.name, mean * questFactor, pct(cpu, 99) * questFactor, (cpu.max() ?? 0) * questFactor,
                          misses, Double(misses) * 100 / n, longest, pct(quads, 95) / 1000)
        return (ok, line)
    }
}
