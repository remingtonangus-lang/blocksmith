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
// --render OUT.png: build the world on a Vulkan device (lavapipe on Linux) and render a stereo frame through the
// Quest renderer; otherwise meshes go to host memory.
let renderPath = arg("--render")
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
var quads = 0, sections = 0
for c in world.chunks.values { for s in c.sections where !s.empty { quads += s.opaqueQuads + s.transQuads; sections += 1 } }
check(quads > 10_000, "terrain meshed: \(sections) sections, \(quads) quads")
check(MeshArena.shared.slabBytes > 0, "mesh arena holds \(MeshArena.shared.slabBytes >> 20) MB of host slabs")
if let path = renderPath, let ctx = vkctx {
    do {
        game.player.pitch = -0.2
        if let up = Float(arg("--up") ?? "") { game.player.pos.y += up; game.player.flying = true }
        if let t = Double(arg("--time") ?? "") { game.time = t * DAY_LENGTH }
        try RenderTest.render(game: game, ctx: ctx, path: path, yaw: Float(arg("--yaw") ?? "") ?? 0.6, pitch: Float(arg("--pitch") ?? "") ?? -0.25)
    } catch { check(false, "render: \(error)") }
    if CommandLine.arguments.contains("--render-only") { exit(failures == 0 ? 0 : 1) }
}

// Play: 20 s at 72 Hz through the Touch-pad path (PadManager.touch, as the XR layer feeds it).
let pm = PadManager.shared
var tickMs: [Double] = []
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
    game.tick(1.0 / 72)
    world.update(center: game.player.pos)
    tickMs.append((CFAbsoluteTimeGetCurrent() - a) * 1000)
}
pm.touch = nil
tickMs.sort()
print(String(format: "ticks: median %.2f ms, p99 %.2f ms, worst %.2f ms", tickMs[tickMs.count / 2], tickMs[tickMs.count * 99 / 100], tickMs.last!))
let moved = simd_length(V2(game.player.pos.x - p0.x, game.player.pos.z - p0.z))
check(game.player.pos.x.isFinite && game.player.pos.y.isFinite, "player position finite")
check(moved > 10, String(format: "walked %.1f blocks with the left stick", moved))
check(game.menu == nil, "menus closed again (\(game.menu.map { String(describing: type(of: $0)) } ?? "none"))")

// Mixer: a few sounds through the software mixer.
if let snd = SoundEngine() {
    snd.setListener(eye: V3(0, 70, 0), yaw: 0, pitch: 0, cave: 0, underwater: false)
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

try? FileManager.default.removeItem(at: tmp)
print(failures == 0 ? "questcheck: all checks passed" : "questcheck: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
