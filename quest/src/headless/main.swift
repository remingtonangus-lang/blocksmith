import Foundation
import Metal
import simd

// questcheck: the Quest build's shared-code test on a Linux host (quest/tools/linux-check.sh build, CI quest.yml).
// Runs what the headset runs minus the GPU/XR: world generation and meshing on the worker queue into host buffers,
// then scripted Touch-controller play through Game.tick (walk, turn, jump, break and place, inventory, pause), a
// save + reload round trip, and the mixer. Prints timings; exits non-zero on a failed check.
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}
setvbuf(stdout, nil, _IOLBF, 0)

let seed: UInt64 = 12345
// --xr SECONDS: the real Quest app loop (QuestApp) against the desktop OpenXR runtime (Monado), then exit.
if let secs = Double(arg("--xr") ?? "") {
    let tmpXR = FileManager.default.temporaryDirectory.appendingPathComponent("questxr-\(getpid())")
    QuestPaths.setDataRoot(tmpXR.path)
    do {
        let xr = try XRSession(platform: XRPlatform())
        let app = try QuestApp(xr: xr)
        let start = CFAbsoluteTimeGetCurrent()
        var frames = 0
        while CFAbsoluteTimeGetCurrent() - start < secs {
            if !app.frame() { break }
            frames += 1
        }
        print("xr: \(frames) frames in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)) s; world loaded: \(app.game != nil)")
        app.shutdown()
        exit(app.game != nil ? 0 : 1)
    } catch { print("FAIL xr: \(error)"); exit(1) }
}
// --render OUT.png: build the world on a Vulkan device (lavapipe on Linux) and render a stereo frame through the
// Quest renderer; otherwise meshes go to host memory.
let renderPath = arg("--render") ?? arg("--questsim").map { _ in "" }
var vkctx: VkContext?
if renderPath != nil {
    do { vkctx = try VkContext.standalone(); print("vulkan: \(vkctx!.deviceName)") } catch { print("FAIL vulkan: \(error)"); exit(1) }
    sharedSystemDevice = QuestDevice(vkctx!)
}
let device = sharedSystemDevice
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("questcheck-\(getpid())")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
QuestPaths.setDataRoot(tmp.path)

let t0 = CFAbsoluteTimeGetCurrent()
let world = World(seed: seed, device: device, save: nil)
world.renderDistance = 6
let game = Game(world: world, save: nil, persistent: false)
let spawn = game.findSpawn()
game.player.pos = spawn
game.paused = false
game.time = 0.25 * DAY_LENGTH
let (gen, mesh) = world.loadSync(center: spawn, radius: 4)
print(String(format: "load: gen %.2f s, mesh %.2f s (setup %.2f s total)", gen, mesh, CFAbsoluteTimeGetCurrent() - t0))
check(world.chunks.count > 40, "chunks generated (\(world.chunks.count))")
// --capitals-only: just the Capital city checks (Sources/CapitalTownTests.swift), for quick iteration.
if CommandLine.arguments.contains("--capitals-only") {
    TownTests.capitals({ World(seed: UInt64(arg("--seed") ?? "") ?? seed, device: device, save: nil) }, check)
    print(failures == 0 ? "capitals: all checks passed" : "capitals: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
do {   // the simd shim's array-free 4x4 inverse and transpose
    let m = simd_float4x4(SIMD4(2, 0.5, 0, 0), SIMD4(-1, 3, 0.25, 0), SIMD4(0.5, 0, 1.5, 0), SIMD4(4, -2, 7, 1))
    let e = m * m.inverse, i = matrix_identity_float4x4, t = m.transpose
    let err = max(simd_length(e.columns.0 - i.columns.0), simd_length(e.columns.1 - i.columns.1),
                  simd_length(e.columns.2 - i.columns.2), simd_length(e.columns.3 - i.columns.3))
    check(err < 1e-5 && t[1, 0] == m[0, 1] && t[3, 2] == m[2, 3], String(format: "simd shim: inverse (error %.1e) and transpose", err))
}
let warm = QuestWarmup.run()                                          // as the app's loading thread does
check(warm.ms < 500, String(format: "warmup tables built (%.0f ms)", warm.ms))
var quads = 0, sections = 0
for c in world.chunks.values { for s in c.sections where !s.empty { quads += s.opaqueQuads + s.transQuads; sections += 1 } }
check(quads > 10_000, "terrain meshed: \(sections) sections, \(quads) quads")
check(MeshArena.shared.slabBytes > 0, "mesh arena holds \(MeshArena.shared.slabBytes >> 20) MB of host slabs")
if let path = renderPath, !path.isEmpty, let ctx = vkctx {
    do {
        game.player.pitch = -0.2
        if let up = Float(arg("--up") ?? "") { game.player.pos.y += up; game.player.flying = true }
        if let t = Double(arg("--time") ?? "") { game.time = t * DAY_LENGTH }
        // Bug-note screenshot (QuestScreenshot) during the main view: GPU blit 640 -> 320 px wide.
        let shotBlit = tmp.appendingPathComponent("shots/shot_blit.png").path
        QuestScreenshot.targetWidth = 320
        QuestScreenshot.request(path: shotBlit)
        try RenderTest.render(game: game, ctx: ctx, path: path, yaw: Float(arg("--yaw") ?? "") ?? 0.6, pitch: Float(arg("--pitch") ?? "") ?? -0.25)
        QuestScreenshot.waitForWrites()
        func pngSize(_ p: String) -> (Int, Int, Int) {
            guard let d = FileManager.default.contents(atPath: p), d.count > 24 else { return (0, 0, 0) }
            let b = [UInt8](d)
            func be(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
            return (be(16), be(20), d.count)
        }
        do {
            let (w, h, n) = pngSize(shotBlit)
            check(QuestScreenshot.lastWritten == shotBlit && w == 320 && h == 320 && n > 2000 && QuestScreenshot.lastMeanLuma > 10,
                  "screenshot (blit): \(w)x\(h), \(n) bytes, mean luma \(QuestScreenshot.lastMeanLuma)")
        }
        // The CPU fallback (full-size copy, box-filtered on the utility queue) on a small extra view.
        let shotCopy = tmp.appendingPathComponent("shots/shot_copy.png").path
        QuestScreenshot.forceCopy = true
        QuestScreenshot.targetWidth = 100
        QuestScreenshot.request(path: shotCopy)
        try RenderTest.render(game: game, ctx: ctx, path: tmp.appendingPathComponent("shots/scene_small.png").path, width: 200, height: 160,
                              yaw: 0.6, pitch: -0.25)
        QuestScreenshot.waitForWrites()
        do {
            let (w, h, n) = pngSize(shotCopy)
            check(QuestScreenshot.lastWritten == shotCopy && w == 100 && h == 80 && n > 500 && QuestScreenshot.lastMeanLuma > 10,
                  "screenshot (copy + CPU downscale): \(w)x\(h), \(n) bytes, mean luma \(QuestScreenshot.lastMeanLuma)")
        }
        QuestScreenshot.forceCopy = false
        QuestScreenshot.targetWidth = 640
        // A second view toward the nearest volcano, from 700 blocks away (past the render distance, so only its
        // impostor from Sources/LandmarkRender.swift draws there; the camera may stand over unloaded ground).
        if let wg = world.gen as? WorldGen {
            let e = game.player.eye
            let near = wg.terrain.volcanoes(near: e.x, e.z, reach: 8000)
                .min { simd_length(V2($0.x - e.x, $0.z - e.z)) < simd_length(V2($1.x - e.x, $1.z - e.z)) }
            if let v = near {
                let saved = game.player.pos
                let dir = simd_normalize(V2(e.x - v.x, e.z - v.z) + V2(1e-3, 0))
                game.player.pos = V3(v.x + dir.x * 700, Float(YOFF) + v.base + 40, v.z + dir.y * 700)
                let lp = path.replacingOccurrences(of: ".png", with: "_landmark.png")
                try RenderTest.render(game: game, ctx: ctx, path: lp, yaw: atan2f(dir.x, dir.y), pitch: 0.05)
                check(RenderTest.landmarkVerts > 0, "volcano impostor 700 blocks away drawn (\(RenderTest.landmarkVerts) vertices)")
                game.player.pos = saved
            } else { print("render: no volcano within 8000 blocks of spawn (impostor view skipped)") }
        }
        // The water look (water.frag: Fresnel sky, glint, swell, depth, shore foam): from a beach toward the sea, at
        // noon; compared with the Mac's Fancy water by eye (Quest v63: the water had never been ported).
        do {
            let e = game.player.eye
            var shore: (Int, Int)?
            var seaDir: (Float, Float) = (1, 0)
            search: for r in stride(from: 8, through: 1600, by: 8) {
                for dir in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
                    let x = Int(e.x) + dir.0 * r, z = Int(e.z) + dir.1 * r
                    if world.gen.column(x, z).height < SEA - 6 && world.gen.column(x - dir.0 * 14, z - dir.1 * 14).height >= SEA {
                        shore = (x - dir.0 * 14, z - dir.1 * 14); seaDir = (Float(dir.0), Float(dir.1)); break search
                    }
                }
            }
            if let sh = shore {
                let (sx, sz) = sh
                let saved = (game.player.pos, game.player.flying, game.time)
                // From the shore point toward the deep water it was found by (looking down at 0.3 rad it saw only the beach).
                game.player.flying = true
                game.time = 0.22 * DAY_LENGTH
                let views: [(String, Float, Float, Float, Float)] = [         // name, along the sea direction, side, yaw offset, pitch
                    ("_water.png", -2, 0, 0, -0.14),
                    ("_water_ocean.png", 30, 0, 0, -0.08),          // out over deep water, looking out to sea
                    ("_water_back.png", 30, 0, .pi / 2, -0.1),       // the same spot, side-on to the sun direction
                ]
                for (name, along, side, dyaw, pitch) in views {
                    let px = Float(sx) + 0.5 + seaDir.0 * along - seaDir.1 * side, pz = Float(sz) + 0.5 + seaDir.1 * along + seaDir.0 * side
                    game.player.pos = V3(px, Float(SEA) + 1.2, pz)
                    _ = world.loadSync(center: game.player.pos, radius: 4)
                    // RenderTest's yaw: forward = (-sin yaw, -cos yaw).
                    let yaw = atan2f(-seaDir.0, -seaDir.1) + dyaw
                    print("render: water view \(name) " + String(format: "at (%.1f, %.1f) yaw %.1f deg pitch %.1f deg, time 0.22 (Mac: --seed 12345 --x %.0f --z %.0f --yaw %.0f --pitch %.0f --time 0.22)",
                                 px, pz, yaw * 180 / .pi, pitch * 180 / .pi, px, pz, yaw * 180 / .pi, pitch * 180 / .pi))
                    try RenderTest.render(game: game, ctx: ctx, path: path.replacingOccurrences(of: ".png", with: name), yaw: yaw, pitch: pitch)
                }
                (game.player.pos, game.player.flying, game.time) = saved
            } else { print("render: no shore within 1600 blocks (water view skipped)") }
        }
        // --golden DIR: the Quest copies of the golden shots (docs/STORE_QUALITY.md; the Mac list is tools/golden.sh):
        // the world shots this renderer can stage from spawn, compared build to build by a reviewer.
        if let dir = arg("--golden") {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let saved = (game.player.pos, game.player.flying, game.time)
            let savedMobs = game.mobs.mobs
            game.player.flying = true
            var shots: [(String, V3, Double, Float, Float, Bool)] = [         // name, position, day fraction, yaw, pitch, rain
                ("spawn", spawn, 0.2, 0.5, -0.2, false),
                ("aerial", spawn + V3(0, 30, 0), 0.25, 3.5, -0.45, false),
                ("dusk", spawn + V3(0, 2, 0), 0.49, -1.57, -0.07, false),
                ("night", spawn + V3(0, 2, 0), 0.75, 0.5, 0.15, false),
                ("rain", spawn + V3(0, 1, 0), 0.3, 0.5, -0.1, true),
            ]
            if let s = world.gen.structures?.nearest("capital_city", x: Int(spawn.x), z: Int(spawn.z), maxRegions: 16) {
                let c = V3(Float(s.min.x + s.max.x) / 2, Float(s.anchor.y), Float(s.min.z + s.max.z) / 2)
                let ext = Float(max(s.max.x - s.min.x, s.max.z - s.min.z))
                // Within the questcheck world's 6-chunk view (from 0.6 x the extent out the city was all fog).
                shots.append(("capital_city", c + V3(0, ext * 0.22, ext * 0.36), 0.27, 0, -0.55, false))   // forward = -z
                // The Capital market (CapitalTown.swift): the general store's front from the walkway, keeper and
                // townsfolk spawned. Storefronts face north, the sign over the door.
                world.pendingMobs.removeAll()
                _ = world.loadSync(center: c, radius: 6)
                for (name, p) in world.pendingMobs { if let m = Mob.structureMob(name, at: p) { game.mobs.mobs.append(m) } }
                game.mobs.rebuildIndex()
                if let (_, kp) = world.pendingMobs.first(where: { $0.0 == "villager:shop_general" }),
                   let (sp, _) = world.blockEntities.first(where: { $0.1.kind == .sign && $0.1.lines.contains(ShopKind.general.name)
                       && abs(Float($0.0.x) - kp.x) < 8 && abs(Float($0.0.z) - kp.z) < 8 }) {
                    let target = V3(Float(sp.x) + 0.5, Float(sp.y) - 0.5, Float(sp.z) + 0.5)
                    let eye = target + V3(-3, 0.6, -6)
                    let f = simd_normalize(target - eye)
                    shots.append(("capital_market", eye - V3(0, game.player.eyeHeight, 0), 0.26, atan2f(-f.x, -f.z), asinf(f.y), false))
                } else { print("golden: no general store in the capital (capital_market skipped)") }
                world.pendingMobs.removeAll()
            }
            // A town (TownBuildings.swift): the shop fronts and signs around the square, from above one side.
            if let s = world.gen.structures?.nearest("village", x: Int(spawn.x), z: Int(spawn.z), maxRegions: 12) {
                let c = V3(Float(s.min.x + s.max.x) / 2, Float(s.anchor.y), Float(s.min.z + s.max.z) / 2)
                shots.append(("town", c + V3(0, 14, 22), 0.26, 0, -0.45, false))
                // The general store from up its street (the sign is outward of the keeper), with the townsfolk spawned.
                world.pendingMobs.removeAll()
                _ = world.loadSync(center: c, radius: 6)
                for (name, p) in world.pendingMobs { if let m = Mob.structureMob(name, at: p) { game.mobs.mobs.append(m) } }
                game.mobs.rebuildIndex()
                if let (_, kp) = world.pendingMobs.first(where: { $0.0 == "villager:shop_general" }),
                   let (sp, _) = world.blockEntities.first(where: { $0.1.kind == .sign && $0.1.lines.contains(ShopKind.general.name)
                       && abs(Float($0.0.x) - kp.x) < 8 && abs(Float($0.0.z) - kp.z) < 8 }) {
                    let out = simd_normalize(V3(Float(sp.x) + 0.5 - kp.x, 0, Float(sp.z) + 0.5 - kp.z))
                    let card = abs(out.x) > abs(out.z) ? V3(out.x > 0 ? 1 : -1, 0, 0) : V3(0, 0, out.z > 0 ? 1 : -1)
                    // From across the street, a little to one side and above head height, looking at the sign: the
                    // first of a few candidate spots with a clear line of sight (towns differ; a house may stand opposite).
                    let side = V3(-card.z, 0, card.x)
                    let target = V3(Float(sp.x) + 0.5, Float(sp.y) + 0.5, Float(sp.z) + 0.5)
                    let solid = { (q: V3) -> Bool in Blocks.opaque[Int(world.block(Int(floorf(q.x)), Int(floorf(q.y)), Int(floorf(q.z))))] }
                    var pick: V3?
                    search: for out in [7, 5, 9, 4] as [Float] { for sd in [3, -3, 0, 6, -6] as [Float] { for up in [3, 5, 2, 7] as [Float] {
                        let eye = target + card * out + side * sd + V3(0, up, 0)
                        let n = Int(simd_length(target - eye) * 4)
                        if (0..<(n - 2)).allSatisfy({ !solid(eye + (target - eye) * (Float($0) / Float(n))) }) { pick = eye; break search }
                    } } }
                    if let eye = pick {
                        let f = simd_normalize(target - eye)
                        shots.append(("town_shop", eye - V3(0, game.player.eyeHeight, 0), 0.26, atan2f(-f.x, -f.z), asinf(f.y), false))
                    } else { print("golden: no clear view of the general store (town_shop skipped)") }
                }
                world.pendingMobs.removeAll()
            }
            // Boreal Station: the nearest one (BorealStation.views: yard from the air, the gate, a corridor, the hall, the stairs).
            if let s = world.gen.structures?.nearest(BorealStation.kind, x: Int(spawn.x), z: Int(spawn.z), maxRegions: 6) {
                _ = world.loadSync(center: V3(Float(s.anchor.x), Float(s.anchor.y), Float(s.anchor.z - 32)), radius: 4)
                for (n, p, yaw, pitch, t) in BorealStation.views(world, s) { shots.append((n, p, t, yaw, pitch, false)) }
            }
            for (name, p, t, yaw, pitch, rain) in shots {
                game.player.pos = p
                game.time = t * DAY_LENGTH
                game.weather.raining = rain; game.weather.rain = rain ? 1 : 0
                _ = world.loadSync(center: p, radius: 6)
                try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/\(name).png", yaw: yaw, pitch: pitch)
                print("golden: \(dir)/\(name).png")
            }
            game.weather.raining = false; game.weather.rain = 0
            (game.player.pos, game.player.flying, game.time) = saved
            game.mobs.mobs = savedMobs; game.mobs.rebuildIndex()
            _ = world.loadSync(center: game.player.pos, radius: 6)        // the spawn area back for the mob draw test
        }
        try MobDrawTest.run(game: game, ctx: ctx, check: check)
    } catch { check(false, "render: \(error)") }
    if CommandLine.arguments.contains("--render-only") { exit(failures == 0 ? 0 : 1) }
}
if let out = arg("--questsim"), let ctx = vkctx {
    do { try QuestSim.run(game: game, ctx: ctx, out: out, check: check) } catch { check(false, "questsim: \(error)") }
    // Monkey input through the VR layer (QuestFuzz): BLOCKSMITH_FUZZ_SECONDS / --fuzz-seed to run longer or another seed.
    let fuzzSeconds = Int(ProcessInfo.processInfo.environment["BLOCKSMITH_FUZZ_SECONDS"] ?? "") ?? 60
    let fuzzSeed = UInt64(arg("--fuzz-seed") ?? "") ?? 1
    do { try QuestFuzz.run(game: game, ctx: ctx, seconds: fuzzSeconds, seed: fuzzSeed, check: check) } catch { check(false, "questfuzz: \(error)") }
    if CommandLine.arguments.contains("--questsim-only") { print(failures == 0 ? "questsim: all checks passed" : "questsim: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }
}

// Horses alone (iterating on Sources/HorseTests.swift); the full run does them at the end.
if CommandLine.arguments.contains("--horse-only") {
    HorseTests.run(game: game, check: check)
    print(failures == 0 ? "horsetests: all checks passed" : "horsetests: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}

// Boreal Station (Sources/BorealTests.swift): real stations from three seeds, walked, lit and looked over.
if !CommandLine.arguments.contains("--no-boreal") { BorealTests.run(device: device, check: check) }
if CommandLine.arguments.contains("--boreal-only") { print(failures == 0 ? "borealtest: all checks passed" : "borealtest: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }

// Path search cost (mob AI runs these on the frame thread): 60 searches between random points around the spawn.
do {
    var rng = SRng(7)
    var pfMs: [Double] = []
    var found = 0, pathHash = 0
    let pfAlloc0 = AllocCount.now
    for i in 0..<60 {
        let ax = Int(spawn.x) + rng.int(40) - 20, az = Int(spawn.z) + rng.int(40) - 20
        let bx = ax + rng.int(40) - 20, bz = az + rng.int(40) - 20
        let a = V3(Float(ax) + 0.5, Float(world.topY(ax, az) + 1), Float(az) + 0.5)
        let b = V3(Float(bx) + 0.5, Float(world.topY(bx, bz) + 1), Float(bz) + 0.5)
        let t = CFAbsoluteTimeGetCurrent()
        if let path = PathFinder.find(world, from: a, to: b, tall: 2, maxNodes: i % 3 == 0 ? 1500 : 400) {
            found += 1
            for q in path { pathHash = pathHash &* 31 &+ q.x &* 73856093 &+ q.y &* 19349663 &+ q.z &* 83492791 }
        }
        pfMs.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
    }
    let total = pfMs.reduce(0, +)
    pfMs.sort()
    print(String(format: "pathfind: 60 searches (%d found, paths hash %016llx), total %.1f ms, median %.2f ms, worst %.2f ms", found, UInt64(bitPattern: Int64(pathHash)), total, pfMs[30], pfMs.last!)
          + (AllocCount.now.map { ", \(($0 - (pfAlloc0 ?? 0)) / 60) allocations a search" } ?? ""))
    // World.block, the read every game system makes (collision, raycasts, mob AI): 1M reads around the spawn.
    var sum = 0
    let tb = CFAbsoluteTimeGetCurrent()
    for i in 0..<1_000_000 {
        let x = Int(spawn.x) - 24 + (i & 47), z = Int(spawn.z) - 24 + ((i >> 6) & 47), y = Int(spawn.y) + YOFF - 8 + ((i >> 12) & 15)
        sum &+= Int(world.block(x, y, z))
    }
    print(String(format: "world.block: %.1f ns per read (%d)", (CFAbsoluteTimeGetCurrent() - tb) * 1e3, sum & 1))
    // The horizon ring's first sampling (HorizonRing.swift: synchronous when there is none yet).
    if let wg = world.gen as? WorldGen {
        let th = CFAbsoluteTimeGetCurrent()
        let snap = HorizonRing.sample(wg, seed: world.seed, x0: Int(spawn.x) - 1280, z0: Int(spawn.z) - 1280, n: HorizonRing.cells * 2 + 1, s: HorizonRing.spacing)
        print(String(format: "horizon ring: %d samples in %.0f ms", snap.h.count, (CFAbsoluteTimeGetCurrent() - th) * 1000))
    }
    if CommandLine.arguments.contains("--pathfind-only") { exit(0) }      // (profiling)
}

// Play: 20 s at 72 Hz through the Touch-pad path (PadManager.touch, as the XR layer feeds it).
let pm = PadManager.shared
var tickMs: [Double] = []
var tickAllocs: [Int] = []
var slow: [(Double, Double, Int, Int, Int)] = []
let frames = 72 * 20
let p0 = game.player.pos
for i in 0..<frames {
    var p = PadSnapshot()
    p.ly = 1
    p.rx = 0.2
    if i % 144 < 4 { p.a = true }
    if i == 500 { p.y = true }
    if i == 540 { p.b = true }
    if i == 800 || i == 840 { p.menu = true }
    pm.touch = p
    let a = CFAbsoluteTimeGetCurrent()
    world.update(center: game.player.pos)  // streaming first (game.tick's own call then finds little left)
    let b = CFAbsoluteTimeGetCurrent()
    let al0 = AllocCount.now
    if i == 1000 || i == 1001 { AllocCount.traced("tick\(i)") { game.tick(1.0 / 72) } } else { game.tick(1.0 / 72) }
    if let x = al0, let y = AllocCount.now { tickAllocs.append(y - x) }
    let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
    tickMs.append(ms)
    slow.append((ms, (b - a) * 1000, i, world.chunks.count, game.mobs.mobs.count))
}
pm.touch = nil
// The slowest frames, split into world streaming (results applied, scheduling) and the rest of the game tick.
slow.sort { $0.0 > $1.0 }
for (ms, upd, i, ch, mobs) in slow.prefix(6) {
    print(String(format: "  slow tick #%d: %.2f ms (world.update %.2f, game %.2f) chunks %d mobs %d", i, ms, upd, ms - upd, ch, mobs))
}
tickMs.sort()
if !tickAllocs.isEmpty {
    let late = Array(tickAllocs.suffix(tickAllocs.count / 2)).sorted()      // the second 10 s: past the first-use work
    print(String(format: "tick allocations (frame thread, second half): median %d, p90 %d, worst %d, total %d",
                 late[late.count / 2], late[late.count * 9 / 10], late.last!, late.reduce(0, +)))
}
print(String(format: "ticks: median %.2f ms, p99 %.2f ms, worst %.2f ms", tickMs[tickMs.count / 2], tickMs[tickMs.count * 99 / 100], tickMs.last!))
let moved = simd_length(V2(game.player.pos.x - p0.x, game.player.pos.z - p0.z))
check(game.player.pos.x.isFinite && game.player.pos.y.isFinite, "player position finite")
check(moved > 10, String(format: "walked %.1f blocks with the left stick", moved))
check(game.menu == nil, "menus closed again (\(game.menu.map { String(describing: type(of: $0)) } ?? "none"))")

// The Meridian frigate's Tidebreaker (Sources/MainGunTests.swift): barrel, shockwave, a shot through Game.tick with the
// frame time after the impact; with --render, stereo frames of the barrel, the charge, the blast and the crater
// (next to the --render PNG).
do {
    let shotDir = renderPath.flatMap { $0.isEmpty ? nil : ($0 as NSString).deletingLastPathComponent }
    let render: ((String, Float, Float) -> Void)? = shotDir.flatMap { dir in vkctx.map { ctx in { name, yaw, pitch in
        do {
            try RenderTest.render(game: game, ctx: ctx, path: (dir.isEmpty ? "." : dir) + "/\(name).png", yaw: yaw, pitch: pitch)
            print("render: \(dir)/\(name).png")
        } catch { check(false, "maingun render \(name): \(error)") }
    } } }
    MainGunTests.run(game, check, render: render)
    if CommandLine.arguments.contains("--maingun-only") { print(failures == 0 ? "maingun: all checks passed" : "maingun: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }
}

// Mixer: a few sounds through the software mixer.
if let snd = SoundEngine() {
    snd.setListener(eye: V3(0, 70, 0), yaw: 0, pitch: 0, cave: 0, underwater: false)
    // A sound not synthesized yet waits (rendered off the game thread) and plays at the next listener update once ready.
    let anvilQueued = !snd.ready(.anvil)
    snd.play(.anvil, volume: 0.01)
    let w0 = CFAbsoluteTimeGetCurrent()
    while !(snd.ready(.explode) && snd.ready(.click) && snd.ready(.anvil)) && CFAbsoluteTimeGetCurrent() - w0 < 10 { usleep(5000) }
    check(!anvilQueued || snd.waitingCount == 1, "mixer: an unsynthesized sound waits instead of rendering on the game thread")
    snd.setListener(eye: V3(0, 70, 0), yaw: 0, pitch: 0, cave: 0, underwater: false)
    check(snd.waitingCount == 0, "mixer: the waiting sound plays once synthesized")
    snd.play(.click)
    snd.play(.explode, at: V3(4, 70, 0))
    var buf = [Float](repeating: 0, count: 2 * 2048)
    var peakL: Float = 0, peakR: Float = 0
    buf.withUnsafeMutableBufferPointer { b in
        for _ in 0..<4 {
            snd.render(b.baseAddress!, frames: 2048)
            for i in 0..<2048 { peakL = max(peakL, abs(b[2 * i])); peakR = max(peakR, abs(b[2 * i + 1])) }
        }
    }
    check(peakL > 0.01 && peakR > peakL, String(format: "mixer: explosion to the right is louder right (L %.2f R %.2f)", peakL, peakR))
}

// Saves: a world with a SaveManager, a placed block, save, reload.
let save = SaveManager(name: "questcheck")
let w2 = World(seed: seed, device: device, save: save)
w2.renderDistance = 3
_ = w2.loadSync(center: spawn, radius: 2)
let bx = Int(spawn.x), bz = Int(spawn.z)
let by = Int(spawn.y) + YOFF + 3
w2.setBlock(bx, by, bz, Blocks.id("gold_block"))
w2.saveAll()
SaveIO.flush()
let w3 = World(seed: seed, device: device, save: SaveManager(name: "questcheck"))
w3.renderDistance = 3
_ = w3.loadSync(center: spawn, radius: 2)
check(w3.block(bx, by, bz) == Blocks.id("gold_block"), "saved block survives a reload")

// Texture cache round trip (the headset caches the painted textures between launches).
let texLevels = TextureGen.mipChain(size: 16, layers: 0..<12)
let texURL = TextureCache.url(dir: tmp.path + "/cache", size: 16, layers: 12)
TextureCache.store(texLevels, texURL)
let texBack = TextureCache.load(texURL)
check(texBack == texLevels && texLevels.count == 5, "texture cache round trip (\(texLevels.count) levels, \(texLevels.map(\.count).reduce(0, +)) bytes)")

// Towns of people and shops (Sources/TownTests.swift).
TownTests.run(game: game, makeWorld: { World(seed: seed, device: device, save: nil) }, check: check)

// Horses: gaits, stamina, bond, footing, crashes, nerves (Sources/HorseTests.swift, docs/status/horses.md).
HorseTests.run(game: game, check: check)

try? FileManager.default.removeItem(at: tmp)
print(failures == 0 ? "questcheck: all checks passed" : "questcheck: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
