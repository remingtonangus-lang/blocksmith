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
// --worldgencheck [N]: the world-gen placement rules over N seeds (Sources/WorldGenCheck.swift), generator only.
if CommandLine.arguments.contains("--worldgencheck") { exit(WorldGenCheck.run()) }
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
    // The headset's imported art (AndroidMain reads assets/texpack.bin the same way), so CI renders show the real
    // textures instead of the procedural fallback (done audit 25b6).
    if TextureImport.pack == nil { TextureImport.load(FileManager.default.contents(atPath: "Resources/texpack.bin")) }
}
let device = sharedSystemDevice
// --structcheck [--seeds A,B --per N --kinds K,... --dims D --strict --out FILE]: the structure walkability check
// (Sources/StructCheck.swift) on the Linux host, as the Mac's `--structcheck` runs it.
if CommandLine.arguments.contains("--structcheck") { exit(StructCheck.run(device: device)) }
// --gencheck [--seeds A,B --areas N]: the generated-world defect scan (Sources/GenCheck.swift: floating trunks and
// plants, leaks, ...), as the Mac's `--gencheck` runs it.
if CommandLine.arguments.contains("--gencheck") { exit(GenCheck.run(device: device)) }
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
// --towns-only: just the towns of people, law, honour and frontier town checks (Sources/TownTests.swift, HonourTests.swift).
if CommandLine.arguments.contains("--towns-only") {
    TownTests.run(game: game, makeWorld: { World(seed: seed, device: device, save: nil) }, check: check)
    print(failures == 0 ? "towns: all checks passed" : "towns: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// Hell's own mobs and the gate into hell (Sources/HellMobsTests.swift); --hell-only stops after them.
HellMobsTests.run(game, check: check)
if CommandLine.arguments.contains("--hell-only") && renderPath == nil {
    print(failures == 0 ? "hell: all checks passed" : "hell: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// The Sparkstone Workshop's circuit benches (Sources/CircuitWorkshopTests.swift); --workshop-only stops after them.
CircuitWorkshopTests.run(game, check: check)
// L3 perf overlay (Sources/PerfOverlayTests.swift): its window, lines, option and HUD drawing on the Quest's HUD host.
PerfOverlayTests.run(game, hud: { Renderer(game: game).buildHUD(1280, 720).count }, check: check)
// L3 volcano eruptions (Sources/EruptionTests.swift): rarity, bursts near and far, the boom, the sound.
EruptionTests.run(game, check: check)
// L3 placement rules keep old saves (Sources/L3GuardTests.swift).
L3GuardTests.run(game, check: check)
// L3 VR combat feel (Sources/VRCombatFeelTests.swift): wind-ups, parry, hit-stop and feel, trail, bow, assist.
VRCombatFeelTests.run(game, check: check)
if CommandLine.arguments.contains("--workshop-only") {
    print(failures == 0 ? "workshop: all checks passed" : "workshop: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --capitals-only: just the Capital city checks (Sources/CapitalTownTests.swift), for quick iteration.
if CommandLine.arguments.contains("--capitals-only") {
    TownTests.capitals({ World(seed: UInt64(arg("--seed") ?? "") ?? seed, device: device, save: nil) }, check)
    print(failures == 0 ? "capitals: all checks passed" : "capitals: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// L3 ground: which plants sway, the mesher's marks for the shader, the rustle (Sources/PlantTests.swift); the look on the
// Quest renderer is PlantRenderTest under --render (--ground-only stops after it, --ground-shots DIR keeps the frames).
PlantTests.run(game, check: check)
OreTests.run(check: check)
do {   // the simd shim's array-free 4x4 inverse and transpose
    let m = simd_float4x4(SIMD4(2, 0.5, 0, 0), SIMD4(-1, 3, 0.25, 0), SIMD4(0.5, 0, 1.5, 0), SIMD4(4, -2, 7, 1))
    let e = m * m.inverse, i = matrix_identity_float4x4, t = m.transpose
    let err = max(simd_length(e.columns.0 - i.columns.0), simd_length(e.columns.1 - i.columns.1),
                  simd_length(e.columns.2 - i.columns.2), simd_length(e.columns.3 - i.columns.3))
    check(err < 1e-5 && t[1, 0] == m[0, 1] && t[3, 2] == m[2, 3], String(format: "simd shim: inverse (error %.1e) and transpose", err))
}
// Create New World with Terrain Smooth (docs/status/polygon-test.md): the menu's action through the parse and setup
// QuestApp.appAction / load use, then the option and the mesher mode must hold before the first loadSync.
do {
    let was = SmoothTerrain.enabled
    for (action, smooth) in [("create:1:2:1:Polygon Test:12345", true), ("create:0:3:0:Block Test:hello", false)] {
        guard let req = WorldRequest.create(action: action) else { check(false, "create action parses: \(action)"); continue }
        let wantName = smooth ? "Polygon Test" : "Block Test", wantDiff = smooth ? 2 : 3
        let wantSeed: UInt64? = smooth ? 12345 : 0xa430d84680aabd0b   // FNV-1a of "hello"
        let fieldsOK: Bool = req.name == wantName && req.survival == smooth && req.difficulty == wantDiff
        check(fieldsOK && req.smooth == smooth && req.seed == wantSeed, "create action parses: \(action)")
        SmoothTerrain.set(!smooth, world: nil)            // the previous world's mode, which the new one must replace
        let cw = World(seed: req.seed ?? seed, device: device, save: nil)
        cw.renderDistance = 2
        let cg = Game(world: cw, save: nil, persistent: false)
        req.setUp(cg, meta: nil)
        check(cg.smoothTerrain == smooth && SmoothTerrain.enabled == (SmoothTerrain.forced ?? smooth),
              "new world from the menu: Terrain \(smooth ? "Smooth" : "Blocks") set before loadSync (option \(cg.smoothTerrain), mesher \(SmoothTerrain.enabled))")
        _ = cw.loadSync(center: cg.player.pos, radius: 1)
        check(SmoothTerrain.enabled == (SmoothTerrain.forced ?? smooth) && !cw.chunks.isEmpty, "new world loads in its terrain mode")
    }
    check(WorldRequest.create(action: "create:1:2:1:Name") == nil, "a short create action is ignored")
    SmoothTerrain.set(was, world: nil)
}
let warm = QuestWarmup.run()                                          // as the app's loading thread does
check(warm.ms < 500, String(format: "warmup tables built (%.0f ms)", warm.ms))
var quads = 0, sections = 0
for c in world.chunks.values { for s in c.sections where !s.empty { quads += s.opaqueQuads + s.transQuads; sections += 1 } }
check(quads > 10_000, "terrain meshed: \(sections) sections, \(quads) quads")
check(MeshArena.shared.slabBytes > 0, "mesh arena holds \(MeshArena.shared.slabBytes >> 20) MB of host slabs")
// With --render: hell's own mobs lined up on the arena HellMobsTests fought on (hell_mobs.png next to the PNG).
if let path = renderPath, !path.isEmpty, let ctx = vkctx, let c = HellMobsTests.arena {
    let home = game.player.pos, wasFly = game.player.flying
    let shown = HellMobsTests.lineup(game)
    game.player.pos = c + V3(0, 0, 4.5); game.player.flying = true
    let dir = (path as NSString).deletingLastPathComponent
    do { try RenderTest.render(game: game, ctx: ctx, path: (dir.isEmpty ? "." : dir) + "/hell_mobs.png", yaw: 0, pitch: -0.15) }
    catch { check(false, "hell lineup render: \(error)") }
    game.mobs.mobs.removeAll { m in shown.contains { $0 === m } }
    game.player.pos = home; game.player.flying = wasFly
}
HellMobsTests.cleanup(game)
if CommandLine.arguments.contains("--hell-only") {
    print(failures == 0 ? "hell: all checks passed" : "hell: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
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
                // The same view erupting (Sources/Eruptions.swift): the impostor throws glowing bombs and its plume swells.
                let calm = RenderTest.landmarkVerts
                let was = game.eruption
                game.eruption = Eruption(v: v, start: game.clock - 8, length: 25, nextBurst: game.clock + 100)
                try RenderTest.render(game: game, ctx: ctx, path: lp.replacingOccurrences(of: "_landmark", with: "_landmark_erupting"), yaw: atan2f(dir.x, dir.y), pitch: 0.05)
                game.eruption = was
                let erupting = RenderTest.landmarkVerts
                // Calm again (the first view may have drawn before the horizon ring was ready): the bombs are the difference.
                try RenderTest.render(game: game, ctx: ctx, path: lp.replacingOccurrences(of: "_landmark", with: "_landmark_calm"), yaw: atan2f(dir.x, dir.y), pitch: 0.05)
                check(erupting >= RenderTest.landmarkVerts + 18 * 6, "volcano impostor erupting: bombs drawn (\(calm), calm \(RenderTest.landmarkVerts) -> erupting \(erupting) vertices)")
                // The plume shows: the same calm view without the smoke differs (the sky once painted over it).
                let withSmoke = RenderTest.lastRGBA
                WorldRenderer.debugSkip.insert("smoke")
                try RenderTest.render(game: game, ctx: ctx, path: lp.replacingOccurrences(of: "_landmark", with: "_landmark_nosmoke"), yaw: atan2f(dir.x, dir.y), pitch: 0.05)
                WorldRenderer.debugSkip.remove("smoke")
                var plumePx = 0
                for i in stride(from: 0, to: min(withSmoke.count, RenderTest.lastRGBA.count), by: 4) {
                    let d = abs(Int(withSmoke[i]) - Int(RenderTest.lastRGBA[i])) + abs(Int(withSmoke[i + 1]) - Int(RenderTest.lastRGBA[i + 1])) + abs(Int(withSmoke[i + 2]) - Int(RenderTest.lastRGBA[i + 2]))
                    if d > 12 { plumePx += 1 }
                }
                check(plumePx > 300, "volcano plume drawn over the sky on the Quest renderer (\(plumePx) px differ without it)")
                game.player.pos = saved
            } else { print("render: no volcano within 8000 blocks of spawn (impostor view skipped)") }
        }
        // A swamp lily pond (audit 25b6 #1/#10; Mac: snaps/lily_pond.png, the same view): pad rafts on open water.
        do {
            let saved = (game.player.pos, game.player.flying, game.time)
            game.player.flying = true
            game.time = 0.27 * DAY_LENGTH
            game.player.pos = V3(967.5, Float(world.gen.column(967, 1810).height) + 6, 1810.5)
            _ = world.loadSync(center: game.player.pos, radius: 4)
            try RenderTest.render(game: game, ctx: ctx, path: path.replacingOccurrences(of: ".png", with: "_lily_pond.png"), yaw: 0, pitch: -0.61)
            (game.player.pos, game.player.flying, game.time) = saved
        }
        // The Oct 10 playtest's far volcano (docs/status/worldgen-oct10, seed 135623 from x 1334 z 2060, 60 up, noon): the
        // cone's sun-side shading and the horizon ring under it on the Quest renderer. Nothing loaded: ring + impostor only.
        do {
            let vw = World(seed: 135623, device: device, save: nil)
            vw.renderDistance = 6
            let vg = Game(world: vw, save: nil, persistent: false)
            vg.time = 0.25 * DAY_LENGTH
            let x: Float = 1334, z: Float = 2060
            vg.player.pos = V3(x, Float(vw.gen.column(Int(x), Int(z)).height + 60), z)
            vg.player.flying = true
            if let wg = vw.gen as? WorldGen, let v = wg.terrain.volcanoes(near: x, z, reach: 2600)
                .min(by: { simd_length(V2($0.x - x, $0.z - z)) < simd_length(V2($1.x - x, $1.z - z)) }) {
                let d = simd_normalize(V2(x - v.x, z - v.z))
                let vp = path.replacingOccurrences(of: ".png", with: "_volcano135623.png")
                try RenderTest.render(game: vg, ctx: ctx, path: vp, yaw: atan2f(d.x, d.y), pitch: 0.02)
                check(RenderTest.landmarkVerts > 0, "seed 135623 far volcano drawn on the Quest renderer (\(RenderTest.landmarkVerts) vertices, \(Int(simd_length(V2(x - v.x, z - v.z)))) blocks)")
            } else { check(false, "seed 135623: a volcano within 2600 blocks of x 1334 z 2060") }
        }
        // Polygon terrain test (docs/status/polygon-test.md): the same seed 12345 views in Blocks and Smooth on the Quest
        // renderer, each from a fresh world loaded in that mode (the world option a new world is created with).
        do {
            let was = SmoothTerrain.enabled
            let views: [(String, Float, Float, Float, Float, Float)] = [   // name, x, z, height above ground, yaw, pitch
                ("spawn", 0.5, 0.5, 2, 0.5, -0.2), ("hills", 296.5, -423.5, 6, 1.05, -0.26),
                ("slopes", 632.5, 200.5, 4, 3.5, -0.18), ("beach", 8.5, 104.5, 3, 1.57, -0.3)]
            for (name, x, z, up, yaw, pitch) in views {
                var quads: [Int] = [], rec: [Double] = []
                for smooth in [false, true] {
                    let pw = World(seed: 12345, device: device, save: nil)
                    pw.renderDistance = 6
                    let pg = Game(world: pw, save: nil, persistent: false)
                    // As QuestApp does for a new world: the option is set on the game, then applied before any meshing.
                    pg.smoothTerrain = smooth
                    SmoothTerrain.use(world: pg.smoothTerrain, world: pw)
                    pg.time = 0.22 * DAY_LENGTH
                    pg.player.flying = true
                    pg.player.pos = V3(x, Float(pw.gen.column(Int(x), Int(z)).height) + up, z)
                    _ = pw.loadSync(center: pg.player.pos, radius: 6)
                    let pp = path.replacingOccurrences(of: ".png", with: "_polygon_\(name)_\(smooth ? "smooth" : "blocks").png")
                    try RenderTest.render(game: pg, ctx: ctx, path: pp, yaw: yaw, pitch: pitch)
                    quads.append(RenderTest.drawnQuads); rec.append(RenderTest.recordMs)
                }
                print("polygon \(name): quads drawn blocks \(quads[0]) smooth \(quads[1]), " + String(format: "CPU record %.2f -> %.2f ms", rec[0], rec[1]))
                check(quads[0] > 0 && quads[1] > 0 && quads[1] != quads[0], "polygon terrain \(name): blocks and smooth both drawn (and differ) on the Quest renderer")
            }
            SmoothTerrain.set(was, world: nil)
        }
        // The water look (water.frag: Fresnel sky, glint, swell, depth, shore foam): from a beach toward the sea, at
        // noon; compared with the Mac's Fancy water by eye (Quest v63: the water had never been ported).
        do {
            let e = game.player.eye
            var shore: (Int, Int)?
            var seaDir: (Float, Float) = (1, 0)
            // Climate terrain puts the sea far from spawn on some seeds: look along 8 directions out to 3200 blocks.
            search: for r in stride(from: 8, through: 3200, by: 8) {
                for dir in [(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, 1), (-1, -1), (1, -1)] {
                    let x = Int(e.x) + dir.0 * r, z = Int(e.z) + dir.1 * r
                    if world.gen.column(x, z).height < SEA - 6 && world.gen.column(x - dir.0 * 14, z - dir.1 * 14).height >= SEA {
                        shore = (x - dir.0 * 14, z - dir.1 * 14); let len = Float(abs(dir.0) + abs(dir.1)).squareRoot(); seaDir = (Float(dir.0) / len, Float(dir.1) / len); break search
                    }
                }
            }
            // Pinned fallback (audit 25b6 #2): seed 12345 has a beach by the swamp at about (950, 1790) (Mac pond shot).
            if shore == nil, let pin = AuditGapTests.pinnedShore(world.gen) { shore = pin.0; seaDir = pin.1 }
            check(shore != nil, "render: a shore for the water views (8 directions out to 3200 blocks, then the pinned seed-12345 beach)")
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
            }
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
            // Biomes (look upgrade, docs/status/look-upgrade.md): the middle of a forest, a desert, snowy plains and a
            // taiga near spawn, at noon from a little above the ground, so the sky air, the trees and the ground of
            // each read build to build. Spiral out in 64-block steps; the centre and four points 32 out must all match.
            for (biome, yaw) in [("forest", Float(0.6)), ("desert", Float(2.2)), ("snowy_plains", Float(-0.9)), ("taiga", Float(3.6))] {
                var x = 0, z = 0, dx = 0, dz = -1, found: V3?
                for _ in 0..<6000 {
                    let wx = Int(spawn.x) + x * 64, wz = Int(spawn.z) + z * 64
                    if [(0, 0), (32, 0), (-32, 0), (0, 32), (0, -32)].allSatisfy({ world.gen.column(wx + $0.0, wz + $0.1).biome.name == biome }) {
                        found = V3(Float(wx) + 0.5, 0, Float(wz) + 0.5); break
                    }
                    if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
                    x += dx; z += dz
                }
                guard var p = found else { print("golden: no \(biome) near spawn (biome_\(biome) skipped)"); continue }
                _ = world.loadSync(center: p, radius: 2)
                p.y = Float(world.topY(Int(floorf(p.x)), Int(floorf(p.z))) + 1) + 3
                shots.append(("biome_\(biome)", p, 0.24, yaw, -0.12, false))
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
        let skyDir = arg("--sky-dir") ?? tmp.appendingPathComponent("shots").path
        try? FileManager.default.createDirectory(atPath: skyDir, withIntermediateDirectories: true)
        try SkyTest.run(game: game, ctx: ctx, dir: skyDir, check: check)
        try PlantRenderTest.run(game: game, ctx: ctx, dir: arg("--ground-shots"), check: check)
        if CommandLine.arguments.contains("--ground-only") { print(failures == 0 ? "groundtest: all checks passed" : "groundtest: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }
        PowderwightTest.run(game: game, check: check)
        TreeTest.run(check: check)
        if let shots = arg("--tree-shots") { try TreeShots.run(game: game, ctx: ctx, dir: shots) }
        MobAnimTest.run(game: game, check: check)
        // --workshop-shots DIR: the Sparkstone Workshop deck from its walkway (CircuitWorkshop.swift), built east of
        // the spawn, run a few seconds so the clocks tick and the door shuts, then cleared.
        if let dir = arg("--workshop-shots") {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let saved = (game.player.pos, game.player.flying, game.time)
            let x0 = Int(spawn.x) + 160, z0 = Int(spawn.z)
            _ = world.loadSync(center: V3(Float(x0 + CircuitWorkshop.deckLength / 2), spawn.y, Float(z0)), radius: 5)
            var top = SEA
            for x in stride(from: 0, through: CircuitWorkshop.deckLength, by: 4) { top = max(top, world.topY(x0 + x, z0)) }
            let o = IVec3(x0, min(CH - 12, top + 12), z0)
            let at = CircuitWorkshop.build(world, at: o)
            for _ in 0..<70 { world.redstone.tick() }
            game.player.flying = true
            game.time = 0.27 * DAY_LENGTH
            let views: [(String, V3, Float, Float)] = [
                ("workshop_walkway", V3(Float(o.x) - 3, Float(o.y) + 2.5, Float(o.z) - 3), -1.9, -0.3),
                ("workshop_door", V3(Float(at["piston_door"]!.x) + 5.5, Float(o.y) + 1.2, Float(o.z) - 5), .pi, -0.08),
                ("workshop_sorter", V3(Float(at["hopper_sorter"]!.x) + 6, Float(o.y) + 4, Float(o.z) - 4), 2.55, -0.35),
            ]
            for (name, p, yaw, pitch) in views {
                game.player.pos = p
                _ = world.loadSync(center: p, radius: 5)
                try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/\(name).png", yaw: yaw, pitch: pitch)
                print("workshop: \(dir)/\(name).png")
            }
            CircuitWorkshop.clear(world, at: o)
            (game.player.pos, game.player.flying, game.time) = saved
            _ = world.loadSync(center: game.player.pos, radius: 6)
        }
        if let shots = arg("--mob-shots") { try MobPortraits.run(game: game, ctx: ctx, dir: shots, kinds: (arg("--mob-kinds") ?? "creeper").split(separator: ",").map(String.init)) }
        if CommandLine.arguments.contains("--sky-only") { print(failures == 0 ? "skytest: all checks passed" : "skytest: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }
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
    game.vrHead = nil; game.vrAim = nil          // the VR layer set them each frame; the shared checks after this run off the headset
    if CommandLine.arguments.contains("--questsim-only") { print(failures == 0 ? "questsim: all checks passed" : "questsim: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }
}

// Horses alone (iterating on Sources/HorseTests.swift); the full run does them at the end.
if CommandLine.arguments.contains("--horse-only") {
    HorseTests.run(game: game, check: check)
    print(failures == 0 ? "horsetests: all checks passed" : "horsetests: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}

// The Deep (Sources/DeepTests.swift + DeepExpansionTests.swift): layers, seam, the Ashguard war, the Sealrock, Sunderite,
// Brimstone Keeps, the vault's sky and the army's strength.
// The Deep's checks run minutes of game time (duels, wars, the biggest battle): the clock and weather go back after,
// or the checks below meet a different hour (night spawns crowded the walk check and moved every town check after it).
let deepWas = (game.time, game.weather)
if !CommandLine.arguments.contains("--no-deep") { DeepTests.run(game, check) }
// With --render: the Ash Vault under its own sky and a Brimstone Keep, through the Quest renderer (next to the PNG).
if let path = renderPath, !path.isEmpty, let ctx = vkctx {
    let dir = (path as NSString).deletingLastPathComponent
    let home = game.player.pos
    func shot(_ name: String, at p: V3, yaw: Float, pitch: Float) {
        game.changeDimension(to: .deep, at: p)
        game.player.pos = p; game.player.vel = .zero; game.player.flying = true
        _ = game.world.loadSync(center: p, radius: 6)
        do {
            try RenderTest.render(game: game, ctx: ctx, path: (dir.isEmpty ? "." : dir) + "/\(name).png", yaw: yaw, pitch: pitch)
            print("render: \(dir)/\(name).png")
        } catch { check(false, "deep render \(name): \(error)") }
    }
    do {
        let dg = DeepGen(seed: seed)
        let fy = Float(dg.floorY(0, 90) + 3)
        shot("deep_vault", at: V3(0.5, fy, 90.5), yaw: 0, pitch: 0.12)
        shot("deep_vault_sky", at: V3(0.5, fy, 90.5), yaw: 0.6, pitch: 0.75)
        if let k = dg.structures?.nearest("brimstone_keep", x: 0, z: 0) {
            let ox = (k.min.x + k.max.x) / 2, oz = (k.min.z + k.max.z) / 2
            shot("deep_keep", at: V3(Float(ox) + 0.5, Float(DeepGen.hellBase + BrimstoneKeep.floorUp + 9), Float(oz + BrimstoneKeep.causeway) + 0.5), yaw: 0, pitch: -0.12)
        }
    }
    // The biggest battle's draw side (gap pass D5/DE14): the citadel at Total War from the north gate, looking in, with
    // the vault's fog budget (sections and units wholly past the fog are left out) and without it.
    do {
        let savedMobs = game.mobs.mobs, savedVictory = game.ashVictory
        let stand = AshVaultGapTests.battleScene(game)
        // Out to render distance 10 (the headset plays at 16): past the vault's fog (AshSky.fogEnd 130 + 8), so the
        // budget has something to cut. The wider load wakes more garrisons.
        let rd0 = game.world.renderDistance
        game.world.renderDistance = 10
        _ = game.world.loadSync(center: stand, radius: 10)
        for (name, p) in game.world.pendingMobs { if let m = Mob.structureMob(name, at: p) { game.mobs.mobs.append(m) } }
        game.world.pendingMobs.removeAll()
        game.player.pos = stand
        game.player.flying = true
        let out = (dir.isEmpty ? "." : dir) + "/deep_battle.png"
        var with = RenderTest.lastStats, without = RenderTest.lastStats
        SoldierRig.lodBuilt = [0, 0, 0, 0]
        do {
            SceneRenderer.fogCullOff = true
            try RenderTest.render(game: game, ctx: ctx, path: out, yaw: .pi, pitch: 0.05)
            without = RenderTest.lastStats
            SceneRenderer.fogCullOff = false
            try RenderTest.render(game: game, ctx: ctx, path: out, yaw: .pi, pitch: 0.05)
            with = RenderTest.lastStats
            print("render: \(out)")
        } catch { SceneRenderer.fogCullOff = false; check(false, "deep render battle: \(error)") }
        let units = game.mobs.mobs.filter { $0.health > 0 && $0.faction == Faction.ashguard.rawValue }.count
        game.world.renderDistance = rd0
        do {
            // Which models carry the mob pass: units in reach and in view of the camera, by kind, with their part counts.
            SoldierRig.eye = game.player.eye; SoldierRig.drawing = true
            var byKind: [String: (Int, Int)] = [:]
            let look = V3(-sinf(Float.pi), 0, -cosf(Float.pi))
            for m in game.mobs.mobs where m.health > 0 {
                let d = m.pos - game.player.eye
                if simd_length(d) > 152 || (simd_length(d) > 64 && simd_dot(simd_normalize(d), look) < 0.5) { continue }
                let n = mobModelParts(m).count
                let e = byKind["\(m.kind)", default: (0, 0)]
                byKind["\(m.kind)"] = (e.0 + 1, e.1 + n)
            }
            SoldierRig.drawing = false
            print("deep battle draw by kind (units, parts): " + byKind.sorted { $0.value.1 > $1.value.1 }.map { "\($0.key) \($0.value.0)/\($0.value.1)" }.joined(separator: ", "))
        }
        print("deep battle draw stages: \(RenderTest.lastStages); soldier rigs by level (near, mid, far, silhouette) \(SoldierRig.lodBuilt); culled \(MobDrawStats.culled), dropped \(MobDrawStats.dropped)")
        print(String(format: "deep battle draw: %d units; fog budget on: %d sections, %d draws, %d quads, %d units in reach, CPU record %.2f ms; off: %d sections, %d draws, %d quads, %d units, %.2f ms",
                     units, with.sections, with.draws, with.quads, with.mobsDrawn, with.recordMs,
                     without.sections, without.draws, without.quads, without.mobsDrawn, without.recordMs))
        // The fog ends at AshSky.fogEnd: nothing past it is drawn, and the battle's record stays inside a 72 Hz frame's
        // CPU share (4 ms of 13.9).
        // The budget: the fog cuts sections, terrain and units, and the mob pass stays inside a third of the frame's
        // shared vertex scratch (the rest: dropped items, particles, hands, HUD); past it the farthest units would drop.
        let mobBytes = with.mobVerts * MemoryLayout<MobVert>.stride, mobBudget = SceneRenderer.scratchSize / 3
        check(units >= 40 && with.sections < without.sections && with.mobsDrawn < without.mobsDrawn && mobBytes <= mobBudget,
              String(format: "ash vault draw: the biggest battle (%d units, render distance 10) with the fog budget: %d sections, %d quads, %d units in reach, %d mob vertices (%.1f of %.1f MB), record %.1f ms; without: %d sections, %d quads, %d units, %d vertices, %.1f ms",
                     units, with.sections, with.quads, with.mobsDrawn, with.mobVerts, Double(mobBytes) / 1048576, Double(mobBudget) / 1048576, with.recordMs,
                     without.sections, without.quads, without.mobsDrawn, without.mobVerts, without.recordMs))
        game.mobs.mobs = savedMobs; game.ashVictory = savedVictory
        game.ashAlarm = 0; game.ashAlarmLevel = 0; game.ashStrikes.removeAll(); game.arms.slugs.removeAll()
    }
    game.changeDimension(to: .overworld, at: home)
    game.player.pos = home; game.player.vel = .zero; game.player.flying = false
    _ = game.world.loadSync(center: home, radius: 4)
}
(game.time, game.weather) = deepWas
// ... and the spawn's wild mobs go: the Deep's checks unload and reload the overworld several times, and what wandered
// back (zombies, slimes, pigs on the path) varied run to run. The walk below sets where every later check stands, and
// a pig in its way moved the town checks onto rougher ground (the sheriff's line of fire blocked).
game.mobs.mobs.removeAll()
if CommandLine.arguments.contains("--deep-only") { print(failures == 0 ? "deeptest: all checks passed" : "deeptest: \(failures) FAILED"); exit(failures == 0 ? 0 : 1) }

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
