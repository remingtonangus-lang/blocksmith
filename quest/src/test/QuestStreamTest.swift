import Foundation
import simd
import Metal

// P446 (Oct 25, New World (4): "it's literally trying to render it from the bottom up"; "I can see so far away
// underground"; a village half drawn for about 20 s): how new land comes in round a player who arrives at a spot, in
// real time with the headset's world settings (QuestApp). Each second: chunks made and drawn in the view, chunks whose
// ground surface is drawn, chunks drawn under the surface but not at it (what he saw), section meshes made for a section
// that changed meanwhile (and how many were drawn), sections invalidated over the surface and under it, the queue.
//   questcheck --streamtest --seed S --at X,Y,Z [--rd 10] [--seconds 30] [--speed B/S] [--look YAW,PITCH]
//              [--shots 2,5,10 --out DIR]      (--speed: flying on along the look's heading, as in creative)
enum QuestStreamTest {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run(ctx: VkContext?) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = (Double(ProcessInfo.processInfo.environment["BS_HANDOVERMS"] ?? "") ?? 1.5) / 1000; World.lodNear = 99; World.leafNear = QuestApp.leafNear
        World.editLane = true                                                       // (QuestApp)
        let at = (arg("--at") ?? "0,160,0").split(separator: ",").compactMap { Float($0) }
        let look = (arg("--look") ?? "0,-20").split(separator: ",").compactMap { Float($0) }
        let rd = Int(arg("--rd") ?? "") ?? 10
        let secs = Int(arg("--seconds") ?? "") ?? 30
        let speed = Float(arg("--speed") ?? "") ?? 0
        let shots = Set((arg("--shots") ?? "").split(separator: ",").compactMap { Int($0) })
        let out = arg("--out") ?? "."
        // P484 (--shaft D): at 3 s a shaft is dug from the ground's top under him down D blocks and he stands in it, as
        // when he mines straight down in survival; each line then says whether the world counts him under the ground and
        // how many chunks within 8 still keep their buried sections undrawn (holes in the caves he can see).
        let shaft = Int(arg("--shaft") ?? "")
        TextureGen.registerAll()
        let w = World(seed: UInt64(arg("--seed") ?? "") ?? 12345, device: sharedSystemDevice, save: nil)
        w.renderDistance = rd
        w.makeFieldWorld()
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w)
        g.survival = false
        g.time = 0.3 * DAY_LENGTH
        let p = g.player
        p.pos = V3(at[0], at[1], at[2]); p.flying = true
        let yaw = -look[0] * .pi / 180, pitch = look[1] * .pi / 180          // (the note's yaw, as --view)
        p.yaw = yaw; p.pitch = pitch
        g.paused = false
        let dt = 1.0 / 72
        print("streamtest: seed \(w.seed) at \(Int(at[0])) \(Int(at[1]) - YOFF) \(Int(at[2])), view \(rd), \(w.maxJobs) workers, \(secs) s, speed \(speed) b/s; stale meshes \(World.keepStale ? "drawn" : "thrown away (BS_STALEMESH=0)"), edits ahead of the queue \(World.frontAll ? "every change, no cap (BS_FRONTALL=1)" : "edits only, half the workers"), light reach \(World.narrowLight ? "16 blocks unless the top moved" : "up to the top (BS_NARROWLIGHT=0)")")
        let tally = ProcessInfo.processInfo.environment["BS_EDITTALLY"] == "1"
        if tally { World.editTally = [:]; World.editCells = [:] }
        var versions: [ChunkKey: [Int]] = [:]
        var stale0 = 0, drawn0 = 0, async0 = World.asyncEdits, sync0 = World.syncEdits
        var perf0 = w.perf
        var firstAll: Double? = nil, firstSurf: Double? = nil
        let t0 = CFAbsoluteTimeGetCurrent()
        var shift = 0.0
        var ticks: [Double] = [], allTicks: [Double] = []
        for f in 0..<(secs * 72) {
            if g.menu != nil { g.closeMenu() }
            g.cine.active = false
            g.input.keys.removeAll(keepingCapacity: true)
            p.flying = true
            p.yaw = yaw; p.pitch = pitch
            if speed > 0 { p.pos += V3(-sinf(yaw), 0, -cosf(yaw)) * (speed * Float(dt)) }
            if let d = shaft, f == 3 * 72 {
                let x = Int(floor(p.pos.x)), z = Int(floor(p.pos.z))
                var top = CH - 1
                while top > 0 && !w.solidAt(x, top, z) { top -= 1 }
                for y in (top - d)...top { w.setBlock(x, y, z, AIR) }
                p.pos = V3(Float(x) + 0.5, Float(top - d), Float(z) + 0.5)
                print("streamtest: shaft dug at \(x) \(z) from \(top - YOFF) down to \(top - d - YOFF)")
            }
            if shaft != nil && f > 3 * 72 { p.flying = false }
            p.vel = .zero
            let tt = CFAbsoluteTimeGetCurrent()
            g.tick(dt)
            ticks.append((CFAbsoluteTimeGetCurrent() - tt) * 1000)
            // (As the headset's frame does every frame: the middle ring follows him, built in the background.)
            if (f + 1) % 18 == 0 { FarRing.shared.request(g, eye: p.eye) }
            if (f + 1) % 72 == 0 {
                let sec = (f + 1) / 72
                let c0 = ChunkKey(x: floorDiv(Int(floor(p.pos.x)), CS), z: floorDiv(Int(floor(p.pos.z)), CS))
                var inView = 0, made = 0, drawn = 0, shellN = 0, surf = 0, underOnly = 0, surfStale = 0, bumpUp = 0, bumpDeep = 0
                for dz in -rd...rd { for dx in -rd...rd where w.inMeshRadius(dx, dz) {
                    inView += 1
                    let k = ChunkKey(x: c0.x + dx, z: c0.z + dz)
                    guard let c = w.chunks[k] else { continue }
                    made += 1
                    if c.meshedOnce { drawn += 1 }
                    // P474 (Oct 29): a shell past the active distance (P376) is made and drawn from its kept meshes; its
                    // blocks are gone, so its surface counts as drawn (before, every shell counted as a gap: at view 16
                    // about 240 of 861 chunks "missing" while the workers sat idle with nothing left to make).
                    if c.hollow { if c.meshedOnce { surf += 1; shellN += 1 }; continue }
                    // The ground's top at the chunk's middle column, and its section.
                    let col = 8 + 8 * CS
                    var y = min(min(CH, c.blocks.storedCount / CSQ) - 1, Int(c.height[col]))
                    while y > 0 && !c.blocks.ground(col + y * CSQ) { y -= 1 }
                    let ss = max(0, y) >> 4
                    let s = c.sections[ss]
                    if s.meshedVersion >= 0 { surf += 1; if s.needsMesh { surfStale += 1 } }
                    else if (0..<ss).contains(where: { c.sections[$0].meshedVersion >= 0 && !c.sections[$0].empty }) { underOnly += 1 }
                    let low = c.groundLow >> 4
                    let now = c.sections.map { $0.version }
                    if let was = versions[k] {
                        for i in 0..<NSEC where now[i] != was[i] { if i >= low { bumpUp += now[i] - was[i] } else { bumpDeep += now[i] - was[i] } }
                    }
                    versions[k] = now
                } }
                let pf = w.perf
                let el = CFAbsoluteTimeGetCurrent() - t0 - shift
                if firstSurf == nil && surf >= inView { firstSurf = el }
                if firstAll == nil && drawn >= inView { firstAll = el }
                let tmean = ticks.reduce(0, +) / Double(max(1, ticks.count)), tworst = ticks.max() ?? 0
                if sec > 2 { allTicks += ticks }
                ticks.removeAll(keepingCapacity: true)
                print(String(format: "streamtest: %3d s (%.1f): tick %.2f ms mean, %.1f worst; %d in view, made %d, drawn %d (%d of them shells), surface drawn %d (out of date %d), under it only %d; meshes for a changed section %d (drawn %d); bumps over the low ground %d, under %d; edits %d + %d in the background, fluid cells waiting %d + %d lava; gen %d (%.0f ms), mesh jobs %d (%d sections, %.0f ms); jobs %d; handed over %d in %.0f ms, %d left waiting",
                             sec, el, tmean, tworst, inView, made, drawn, shellN, surf, surfStale, underOnly, World.staleMeshes - stale0, World.staleDrawn - drawn0, bumpUp, bumpDeep,
                             World.syncEdits - sync0, World.asyncEdits - async0, w.fluidPending.count, w.lavaPending.count,
                             pf.genChunks - perf0.genChunks, (pf.genSeconds - perf0.genSeconds) * 1000, pf.meshJobs - perf0.meshJobs,
                             pf.meshSections - perf0.meshSections, (pf.meshSeconds - perf0.meshSeconds) * 1000, w.pendingJobs,
                             World.handedOver, World.handoverSpent * 1000, World.leftWaiting))
                if shaft != nil {
                    var held = 0
                    for dz in -8...8 { for dx in -8...8 { if let c = w.chunks[ChunkKey(x: c0.x + dx, z: c0.z + dz)], c.deferredBuried > 0 { held += 1 } } }
                    print("streamtest: under the ground \(w.underground); chunks within 8 with buried sections undrawn: \(held)")
                }
                World.handedOver = 0; World.handoverSpent = 0
                stale0 = World.staleMeshes; drawn0 = World.staleDrawn; perf0 = pf; async0 = World.asyncEdits; sync0 = World.syncEdits
                if shots.contains(sec), let ctx {
                    let ts = CFAbsoluteTimeGetCurrent()
                    let path = "\(out)/stream-\(sec)s.png"
                    do { try RenderTest.render(game: g, ctx: ctx, path: path, width: 640, height: 480, yaw: yaw, pitch: pitch); print("streamtest: \(path)") }
                    catch { print("streamtest: shot failed: \(error)") }
                    shift += CFAbsoluteTimeGetCurrent() - ts                      // (the shot's time is left out of the clock)
                }
            }
            let due = t0 + shift + Double(f + 1) * dt
            let now = CFAbsoluteTimeGetCurrent()
            if due > now { usleep(useconds_t((due - now) * 1_000_000)) }
        }
        if tally {
            let top = (World.editTally ?? [:]).sorted { $0.value > $1.value }.prefix(12).map { k, n in
                "\(k >> 32 != 0 ? "async " : "")\(Blocks.key(BlockID(truncatingIfNeeded: (k >> 16) & 0xFFFF))) -> \(Blocks.key(BlockID(truncatingIfNeeded: k & 0xFFFF))) x\(n)"
            }
            print("streamtest: edits: \(World.editCells.count) cells changed; " + top.joined(separator: "; "))
            World.editTally = nil
        }
        allTicks.sort()
        let p99 = allTicks.isEmpty ? 0 : allTicks[min(allTicks.count - 1, allTicks.count * 99 / 100)]
        print(String(format: "streamtest: every surface in view drawn at %@, every chunk at %@; meshes for a changed section %d in all, %d drawn; ticks after the first 2 s: %.2f ms mean, %.1f ms at the 99th percentile, %.1f worst",
                     firstSurf.map { String(format: "%.1f s", $0) } ?? "never", firstAll.map { String(format: "%.1f s", $0) } ?? "never",
                     World.staleMeshes, World.staleDrawn, allTicks.reduce(0, +) / Double(max(1, allTicks.count)), p99, allTicks.last ?? 0))
        return 0
    }
}
