import Foundation
import simd
import Metal
import CVulkan

// P283 (Oct 14 19:37, Oct 15 11:53-11:55: "auto 12 render distance, so clearly we got performance issues", "it was
// not able to handle 21", down to 7 while flying over new country): the Quest frame's CPU side in his own scenes, on
// the Quest renderer (questcheck --perfscenes [--rd 12,16] [--only NAME] [--blockworld]). Each scene is his note's
// world and spot, loaded as the headset loads it (a Polygons world unless --blockworld, the Quest's far-detail, leaf
// and hand-over settings), then played frame by frame at 72 Hz as QuestApp.frame does: Game.tick (with its streaming)
// and the world's record into a small offscreen target. Two phases: standing still 5 s, then flying on 10 s at his
// creative speed. Per phase: tick and record ms (mean, p95, worst), the tick stages that cost the most (TickProf), the
// record stages, sections, draws and quads, and how far the meshing fell behind. The lavapipe GPU is not an Adreno:
// its times are left out; the quads and draws are what the headset's GPU pays for.
enum QuestPerf {
    struct Spot { let name: String; let seed: UInt64; let x: Float; let y: Float; let z: Float; let yaw: Float; let pitch: Float }
    // (y as the notes show it: internal - 64; yaw as the notes', degrees, 0 north, clockwise)
    static let spots: [Spot] = [
        Spot(name: "homestead", seed: 6665340019718134347, x: 2932.8, y: 69.0, z: -240.6, yaw: 333, pitch: -4),
        Spot(name: "taiga", seed: 6665340019718134347, x: 4323.3, y: 67.5, z: -594.3, yaw: 80, pitch: -20),
        Spot(name: "ocean", seed: 3931512493184456980, x: 11576.9, y: 62.8, z: -12552.1, yaw: 165, pitch: -23),
        Spot(name: "darkforest", seed: 1997562484558922131, x: 7668.3, y: 209.7, z: -5667.8, yaw: 103, pitch: -36),
    ]

    final class Phase {
        var tick: [Double] = [], record: [Double] = []
        var stages: [String: (sum: Double, worst: Double)] = [:]
        var sections = 0, draws = 0, quads = 0, frames = 0
        func add(tick t: Double, record r: Double, scene: SceneRenderer) {
            tick.append(t); record.append(r); frames += 1
            sections += scene.visibleCount; draws += scene.drawCalls; quads += scene.drawnQuads
            for i in 0..<TickProf.count {
                let k = TickProf.names[i].description, ms = TickProf.times[i] * 1000
                let o = stages[k] ?? (0, 0)
                stages[k] = (o.sum + ms, max(o.worst, ms))
            }
        }
        static func stat(_ a: [Double]) -> String {
            guard !a.isEmpty else { return "-" }
            let s = a.sorted()
            return String(format: "mean %.2f p95 %.2f worst %.1f", a.reduce(0, +) / Double(a.count), s[min(s.count - 1, s.count * 95 / 100)], s.last!)
        }
        func report(_ label: String, stagesLine: String, behind: String) -> String {
            let n = max(1, frames)
            let top = stages.sorted { $0.value.sum > $1.value.sum }.prefix(7)
                .map { "\($0.key) \(String(format: "%.2f", $0.value.sum / Double(n)))/\(String(format: "%.1f", $0.value.worst))" }.joined(separator: ", ")
            return "  \(label): tick \(Phase.stat(tick)) | record \(Phase.stat(record)) | sections \(sections / n), draws \(draws / n), quads \(quads / n)\n"
                + "    tick stages (mean/worst ms): \(top)\n    record stages (ms a frame): \(stagesLine)\n    meshing: \(behind)"
        }
    }

    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run(ctx: VkContext) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 5; World.leafNear = 2   // (QuestApp)
        SceneRenderer.skipGPU = !CommandLine.arguments.contains("--gpu")
        let rds = (arg("--rd") ?? "12,16").split(separator: ",").compactMap { Int($0) }
        let only = arg("--only").map { Set($0.split(separator: ",").map(String.init)) }
        let field = !CommandLine.arguments.contains("--blockworld")
        let standFrames = Int(arg("--stand") ?? "") ?? 360, flyFrames = Int(arg("--flyframes") ?? "") ?? 720
        print("perfscenes: \(field ? "Polygons (field)" : "block") worlds, rd \(rds), \(standFrames) + \(flyFrames) frames at 72 Hz, \(ProcessInfo.processInfo.activeProcessorCount) cores, P283 savings \(TickProf.lighter ? "on" : "off (BS_P283=0)")\(SceneRenderer.skipGPU ? ", GPU commands dropped" : "")")
        for sp in spots where only == nil || only!.contains(sp.name) {
            for rd in rds {
                do { try scene(sp, rd: rd, field: field, ctx: ctx, standFrames: standFrames, flyFrames: flyFrames) }
                catch { print("perfscenes: \(sp.name) rd \(rd): \(error)"); return 1 }
            }
        }
        return 0
    }

    static func scene(_ sp: Spot, rd: Int, field: Bool, ctx: VkContext, standFrames: Int, flyFrames: Int) throws {
        let device = sharedSystemDevice
        let w = World(seed: sp.seed, device: device, save: nil)
        if field { FieldTerrain.newWorlds = true; w.makeFieldWorld() }
        w.renderDistance = rd
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = field
        SmoothTerrain.use(world: field, world: w)
        g.survival = false
        g.paused = false                                                   // (a new Game starts paused)
        g.input.captured = true
        g.time = 0.2 * DAY_LENGTH
        g.player.flying = true
        g.player.pos = V3(sp.x, sp.y + Float(YOFF), sp.z)
        let a0 = CFAbsoluteTimeGetCurrent()
        _ = w.loadSync(center: g.player.pos, radius: rd)
        let loadS = CFAbsoluteTimeGetCurrent() - a0

        let scene = try SceneRenderer(ctx: ctx, device: device as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: g)
        wr.landmarkHost = Renderer(game: g)
        let size = 48
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let targets = [try scene.makeTarget(image: img.image, width: size, height: size), try scene.makeTarget(image: img.image, width: size, height: size)]
        let yaw = -sp.yaw * .pi / 180, pitch = sp.pitch * .pi / 180
        let t = tanf(52 * .pi / 180)                                       // the Quest 3's field of view, about 104 degrees
        let ringFar: Float = FarRing.enabled && g.world.dim == Dim.overworld ? FarRing.outer + 96 : 0
        let far = max(Float(rd * 16 + 96), ringFar)
        let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t * 0.95, tanDown: -t * 0.95, near: 0.05, far: far)
        func camera() -> EyeCamera {
            let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
            let vps = ([-0.032, 0.032] as [Float]).map { proj * XRMath.inversePose(head, head.act(V3($0, 0, 0))) }
            return EyeCamera(center: g.player.eye, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, V3(0, 0, 0)), yaw: yaw, pitch: pitch, far: far)
        }
        let dt: Float = 1.0 / 72
        var fi = 0
        func frame(_ ph: Phase?, fly: Bool) throws {
            if g.menu != nil { g.closeMenu() }                             // (nothing in the way of the controls)
            g.cine.active = false
            g.player.yaw = yaw; g.player.pitch = fly ? 0 : pitch
            // Flying on as he did: the stick forward, sprinting (the creative flight's own speed).
            let inp = g.input
            inp.keys.removeAll(keepingCapacity: true)
            var pad = PadSnapshot()
            if fly { pad.ly = 1 }                                          // (the left stick full forward)
            PadManager.shared.touch = pad
            inp.control = fly
            inp.captured = true
            inp.mouseDX = 0; inp.mouseDY = 0
            let a = CFAbsoluteTimeGetCurrent()
            g.tick(Double(dt))
            let tk = (CFAbsoluteTimeGetCurrent() - a) * 1000
            let s = scene.beginFrame()
            let b = CFAbsoluteTimeGetCurrent()
            wr.record(s, targets[fi % 2], camera())
            let rc = (CFAbsoluteTimeGetCurrent() - b) * 1000
            vkCmdEndRenderPass(s.cmd)
            try scene.submit(s)
            fi += 1
            ph?.add(tick: tk, record: rc, scene: scene)
        }
        World.editTally = [:]
        var mark = (w.perf, World.syncEdits, World.asyncEdits, CFAbsoluteTimeGetCurrent())
        func behind() -> String {
            let p = w.perf, secs = max(0.001, CFAbsoluteTimeGetCurrent() - mark.3)
            let ms = p.meshSections - mark.0.meshSections, mj = p.meshJobs - mark.0.meshJobs
            let line = "\(w.pendingJobs) jobs pending, \(w.chunks.count) chunks loaded; meshed \(ms) sections in \(mj) jobs "
                + String(format: "(%.1f ms each, worker time %.0f%% of the phase)", (p.meshSeconds - mark.0.meshSeconds) * 1000 / Double(max(1, ms)),
                         (p.meshSeconds - mark.0.meshSeconds) * 100 / secs)
                + ", \(p.genChunks - mark.0.genChunks) chunks made; block edits \(World.syncEdits - mark.1) remeshed at once, \(World.asyncEdits - mark.2) in the background"
            mark = (p, World.syncEdits, World.asyncEdits, CFAbsoluteTimeGetCurrent())
            // Which block changes those were (the five most common old -> new pairs; "bg" = remeshed in the background).
            let top = (World.editTally ?? [:]).sorted { $0.value > $1.value }.prefix(5).map { k, n in
                "\(k >> 32 == 1 ? "bg " : "")\(Blocks.def(BlockID(k >> 16 & 0xFFFF)).name)->\(Blocks.def(BlockID(k & 0xFFFF)).name) \(n)"
            }
            let cells = World.editCells.count, again = World.editCells.values.filter { $0 > 1 }.count
            World.editTally = [:]; World.editCells = [:]
            return line + (top.isEmpty ? "" : "\n    edits: " + top.joined(separator: ", ") + "; \(cells) cells, \(again) changed twice or more")
        }
        for _ in 0..<90 { try frame(nil, fly: false) }                  // settle (first meshes in, the far ring built)
        _ = wr.takeStages()
        _ = behind()
        let stand = Phase()
        for _ in 0..<standFrames { try frame(stand, fly: false) }
        let standStages = wr.takeStages(), standBehind = behind()
        let quadsStand = scene.quadBreakdown()
        let flight = Phase()
        // (he flies over the land, not into the hill in front of him: the flight starts 30 blocks over the highest
        // ground within 64 blocks ahead)
        var top = Int(g.player.pos.y)
        for d in stride(from: 0, through: 64, by: 4) {
            let x = Int(g.player.pos.x - sinf(yaw) * Float(d)), z = Int(g.player.pos.z - cosf(yaw) * Float(d))
            if let c = w.chunkAt(x, z) { top = max(top, Int(c.height[mod(x, CS) + mod(z, CS) * CS])) }
        }
        g.player.pos.y = Float(top + 30); g.player.vel = V3(0, 0, 0)
        let from = g.player.pos
        for i in 0..<flyFrames {
            try frame(flight, fly: true)
            if i == 60 { print("    flying: at \(Int(g.player.pos.y) - YOFF), \(String(format: "%.1f", simd_length(g.player.vel))) b/s, on the ground \(g.player.onGround)") }
        }
        let speed = simd_length(V2(g.player.pos.x - from.x, g.player.pos.z - from.z)) / (Float(flyFrames) * dt)
        let flyStages = wr.takeStages(), flyBehind = behind()
        scene.waitIdle()
        print("perfscene \(sp.name) rd \(rd) (seed \(sp.seed) at \(Int(sp.x)), \(Int(sp.z)); loaded in \(String(format: "%.1f", loadS)) s, \(g.mobs.mobs.count) mobs, \(w.ships.list.count) ships)")
        print(stand.report("standing", stagesLine: standStages, behind: standBehind))
        print("    quads: \(quadsStand)")
        print(flight.report(String(format: "flying %.0f b/s", speed), stagesLine: flyStages, behind: flyBehind))
        PadManager.shared.touch = nil
        World.editTally = nil; World.editCells = [:]
        withExtendedLifetime((img, targets, wr)) {}
    }
}
