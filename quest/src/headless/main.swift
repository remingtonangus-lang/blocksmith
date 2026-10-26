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

let seed: UInt64 = CommandLine.arguments.firstIndex(of: "--worldseed").flatMap { i in i + 1 < CommandLine.arguments.count ? UInt64(CommandLine.arguments[i + 1]) : nil } ?? 12345
WorldRules.p44 = false                 // fixture seeds keep their cities and citadels (WorldRules.p44)
StructureCache.plansOffThread = false   // base ticks find their sites at once (P124: HitchProbe turns the worker planning on)
Blueprints.on = false                  // upgrades fit without blueprints (P138: --p12pm-only P138 turns them on)
TownSizes.on = false                   // and their towns as they were (C13 town sizes: --sizes-only turns them on)
MobVary.on = false                      // checks count exact blows and steps (the P55 check turns it on)
// --worldgencheck [N]: the world-gen placement rules over N seeds (Sources/WorldGenCheck.swift), generator only.
if CommandLine.arguments.contains("--worldgencheck") { exit(WorldGenCheck.run()) }
// --deepscan: the Deep's layers over a few seeds (P323, Sources/DeepScan.swift), generator only.
if CommandLine.arguments.contains("--deepscan") { exit(DeepScan.run()) }
// --agent BOT / --behaviorsim: the bots and the mob behaviour sim, shared with the Mac (Sources/Agent*.swift,
// Sources/BehaviorSim.swift), on the Linux host too (Q2: scorecard "Behaviour" measured off the Mac).
if arg("--agent") != nil { exit(AgentRun.run()) }
// --ridecheck [--scenes A,B --seed N --scale F --out DIR]: bots riding the capital vehicles (Sources/RideCheck.swift).
if CommandLine.arguments.contains("--ridecheck") { exit(RideCheck.run()) }
if CommandLine.arguments.contains("--ashdrive") { exit(AshDriveCheck.run()) }     // P324 (Sources/AshCommandeer.swift)
// --gunloudness: each player gun's shot (4 takes) as heard (P424's measure: the loudest 50 ms, roughly A-weighted),
// in dB against the rifle, after its levelling gain (P435: a gun's new sound is levelled against the others).
if CommandLine.arguments.contains("--gunloudness") {
    func loud(_ x: [Float]) -> Float {
        let y = Synth.lowpass(Synth.highpass(Synth.highpass(x, 400), 400), 7000)
        let w = Int(Synth.sr * 0.05)
        var acc: Float = 0, best: Float = 0
        for i in y.indices { acc += y[i] * y[i]; if i >= w { acc -= y[i - w] * y[i - w] }; best = max(best, acc) }
        return 10 * log10f(max(best / Float(w), 1e-12))
    }
    func avg(_ k: Int) -> Float { (0..<4).map { loud(SoundBank.render(.gun(k), variant: $0)) }.reduce(0, +) / 4 }
    let ref = avg(0)
    for k in [0, 1, 2, 3, 4, 5, WeaponAudio.sidearmSlot, 16, 17, 18, 19, WeaponAudio.rotarySlot] {
        print(String(format: "gunloudness: slot %2d  %+5.1f dB against the rifle", k, avg(k) - ref))
    }
    exit(0)
}
if CommandLine.arguments.contains("--behaviorsim") { exit(BehaviorSim.run()) }
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
let renderPath = arg("--render") ?? arg("--questsim").map { _ in "" } ?? arg("--view") ?? (CommandLine.arguments.contains("--touchmatrix-only") || CommandLine.arguments.contains("--batch-only") || CommandLine.arguments.contains("--perfscenes")
    || CommandLine.arguments.contains("--spacewarp") || CommandLine.arguments.contains("--launch") || CommandLine.arguments.contains("--launch-prepare")
    || CommandLine.arguments.contains("--memscene") || CommandLine.arguments.contains("--memsim") || CommandLine.arguments.contains("--streamtest") ? "" : nil)
var vkctx: VkContext?
if renderPath != nil {
    do { vkctx = try VkContext.standalone(); print("vulkan: \(vkctx!.deviceName)") } catch { print("FAIL vulkan: \(error)"); exit(1) }
    sharedSystemDevice = QuestDevice(vkctx!)
    // The headset's imported art (AndroidMain reads assets/texpack.bin the same way), so CI renders show the real
    // textures instead of the procedural fallback (done audit 25b6).
    if TextureImport.pack == nil { TextureImport.load(FileManager.default.contents(atPath: "Resources/texpack.bin")) }
}
let device = sharedSystemDevice
// --controllerpic OUT.svg [--left]: P402 (3), the loading scene's controller picture (quest/src/app/ControllerPicture.swift).
if let out = arg("--controllerpic") {
    try? ControllerPicture.svg(leftHanded: CommandLine.arguments.contains("--left")).write(toFile: out, atomically: true, encoding: .utf8)
    print("controllerpic: wrote \(out)"); exit(0)
}
// --saveacross write|read DIR: P395 (3), a save carried from an older build to this one (Sources/SaveAcross.swift).
if let i = CommandLine.arguments.firstIndex(of: "--saveacross"), i + 2 < CommandLine.arguments.count {
    exit(SaveAcross.run(device: device, mode: CommandLine.arguments[i + 1], dir: CommandLine.arguments[i + 2]))
}
// --perfscenes [--rd 12,16] [--only NAME,...] [--blockworld]: the Quest frame's CPU side in the playtest scenes (P283,
// quest/src/test/QuestPerf.swift).
if CommandLine.arguments.contains("--perfscenes"), let ctx = vkctx { exit(QuestPerf.run(ctx: ctx)) }
// --freezetest [--rd 8]: the Oct 23 base freezes (a bulkhead door opened, a wall block broken), frame by frame (P416).
if CommandLine.arguments.contains("--freezetest") { exit(QuestFreezeTest.run()) }
// --toppletest: what nothing holds falls whole, as itself (P407: a tower past the load fill, a tree on a broken plinth).
if CommandLine.arguments.contains("--toppletest") { exit(QuestToppleTest.run()) }
// --spacewarp: P403 7b, the space warp's motion vectors of a moving mob (quest/src/test/SpaceWarpCheck.swift).
if CommandLine.arguments.contains("--spacewarp"), let ctx = vkctx { exit(SpaceWarpCheck.run(ctx: ctx)) }
// --launch DIR / --launch-prepare DIR [--rd 24]: the headset's launch path timed stage by stage (P400,
// quest/src/test/QuestLaunch.swift).
if CommandLine.arguments.contains("--launch") || CommandLine.arguments.contains("--launch-prepare"), let ctx = vkctx { exit(QuestLaunch.run(ctx: ctx)) }
// --flytest DIR [--rd 24] [--seconds 60] [--walk]: flying flat out over a new world; the speed never drops while the
// world loads (P414, quest/src/test/QuestFlyTest.swift).
if CommandLine.arguments.contains("--flytest") { exit(QuestFlyTest.run()) }
if CommandLine.arguments.contains("--stationcheck") { exit(QuestStationCheck.run()) }  // P454 (Sources/BorealOps.swift)
// --vehiclecheck: P449, the Ash Vault's vehicles and the frigate's helm (quest/src/test/QuestVehicleCheck.swift).
if CommandLine.arguments.contains("--vehiclecheck") { exit(QuestVehicleCheck.run()) }
// --orderscheck: P456, intercepted orders point at places really built, in several kinds (quest/src/test/QuestOrdersCheck.swift).
if CommandLine.arguments.contains("--orderscheck") { exit(QuestOrdersCheck.run()) }
// --shovecheck: P455, a heavy vehicle pushes through trees on its engine (quest/src/test/QuestShoveCheck.swift).
if CommandLine.arguments.contains("--shovecheck") { exit(QuestShoveCheck.run()) }
// --detailcheck (P451): a cold sea keeps its ice through the spring melt; pumpkins grow in patches.
if CommandLine.arguments.contains("--detailcheck") { exit(QuestDetailCheck.run()) }
// --treerepair: P447, old second stems and kinks tidied out of saved land (quest/src/test/QuestTreeRepair.swift).
if CommandLine.arguments.contains("--treerepair") { exit(QuestTreeRepair.run()) }
// --streamtest --seed S --at X,Y,Z [--rd 10] [--seconds 30] [--speed B/S] [--shots 2,5 --out DIR]: new land coming in
// round a player, second by second (P446, quest/src/test/QuestStreamTest.swift).
if CommandLine.arguments.contains("--streamtest") { exit(QuestStreamTest.run(ctx: vkctx)) }
// --placecheck: P448, blocks placed in a field world (quest/src/test/QuestPlaceCheck.swift).
if CommandLine.arguments.contains("--placecheck") { exit(QuestPlaceCheck.run()) }
// --blastcheck: P452, a blast leaves nothing to pick up but valuable blocks (quest/src/test/QuestBlastCheck.swift).
if CommandLine.arguments.contains("--blastcheck") { exit(QuestBlastCheck.run()) }
// --memscene NAME DIR / --memsim DIR [--minutes 20]: resident memory at view 24 in his scenes and over a long play
// (P401, quest/src/test/QuestMemory.swift).
if CommandLine.arguments.contains("--memscene") || CommandLine.arguments.contains("--memsim"), let ctx = vkctx { exit(QuestMemory.run(ctx: ctx)) }
// --settings-phase P ROOT: one launch of the settings check (quest/src/headless/SettingsCheck.swift), before anything
// else touches UserDefaults.
if let i = CommandLine.arguments.firstIndex(of: "--settings-phase"), i + 2 < CommandLine.arguments.count {
    exit(SettingsCheck.phase(CommandLine.arguments[i + 1], root: CommandLine.arguments[i + 2]))
}
// --texdump OUT.png a,b,c [--size N]: the named texture layers side by side at N px (128), for looks work in a thread
// (BLOCKSMITH_PAINTED=a,b shows the painters' version of a layer that has imported art).
if let out = arg("--texdump"), let i = CommandLine.arguments.firstIndex(of: "--texdump"), i + 2 < CommandLine.arguments.count {
    if TextureImport.pack == nil { TextureImport.load(FileManager.default.contents(atPath: "Resources/texpack.bin")) }
    TextureGen.registerAll()
    let names = CommandLine.arguments[i + 2].split(separator: ",").map(String.init)
    let n = Int(arg("--size") ?? "") ?? 128
    var sheet = [UInt8](repeating: 0, count: n * n * 4 * names.count)
    for (k, name) in names.enumerated() {
        let l = Tex.id(name)
        let px = TextureGen.base(size: n, layers: Int(l)..<(Int(l) + 1))
        for y in 0..<n { for x in 0..<n { for c in 0..<4 { sheet[((y * names.count * n) + k * n + x) * 4 + c] = px[(y * n + x) * 4 + c] } } }
    }
    try? PNG.encode(rgba: sheet, width: n * names.count, height: n).write(to: URL(fileURLWithPath: out))
    print("texdump: \(names.count) layers -> \(out)")
    exit(0)
}
// --objectcensus [--field] [--seed S] (P389 step 1): the multi-cell objects at Stone Gulch, the nearest capital city and
// the nearest base, counted by kind (Sources/ObjectCensus.swift).
if CommandLine.arguments.contains("--objectcensus") {
    let w = World(seed: UInt64(arg("--seed") ?? "") ?? 13480747113613945685, device: device, save: nil, dim: .overworld)
    w.renderDistance = 4
    let g = Game(world: w, save: nil, persistent: false)
    print(World.objectCensus(g))
    exit(0)
}
// --view OUT.png --seed S --at X,Y,Z [--look YAW,PITCH] [--time FRAC] [--rd N]: one frame of the Quest renderer at a
// spot (a voice note's repro line: yaw in degrees as the note gives it, pitch in degrees), for looks work in a thread.
if let out = arg("--view"), let ctx = vkctx {
    let at = (arg("--at") ?? "0,100,0").split(separator: ",").compactMap { Float($0) }
    let look = (arg("--look") ?? "0,-10").split(separator: ",").compactMap { Float($0) }
    // --dim nether|end|deep: that dimension's world instead (looks work; PG6 field checks).
    let vw = World(seed: UInt64(arg("--seed") ?? "") ?? 12345, device: device, save: nil, dim: Dim(rawValue: arg("--dim") ?? "") ?? .overworld)
    vw.renderDistance = Int(arg("--rd") ?? "") ?? 6
    // --field (P412/P404): a Polygons field world, as the headset makes new worlds (QuestApp: makeFieldWorld, smoothTerrain).
    let viewField = CommandLine.arguments.contains("--field")
    if viewField { vw.makeFieldWorld() }
    // --questlod: the headset's far-detail and leaf rings (QuestApp: lodNear 99, leafNear 99: full detail everywhere, P339) instead of the Mac's.
    if CommandLine.arguments.contains("--questlod") { World.lodNear = 99; World.leafNear = QuestApp.leafNear }
    if let ln = Int(arg("--leafnear") ?? "") { World.leafNear = ln }     // P403: the fast-leaves ring under test
    let vg = Game(world: vw, save: nil, persistent: false)
    if viewField { vg.smoothTerrain = true; SmoothTerrain.use(world: true, world: vw) }
    vg.time = (Double(arg("--time") ?? "") ?? 0.25) * DAY_LENGTH
    vg.player.pos = V3(at[0], at[1], at[2]); vg.player.flying = true
    // --find BIOME: spiral out from --at in 48-block steps to a column of that biome (looks work: hills, peaks, beaches).
    if let want = arg("--find") {
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<20000 {
            let wx = Int(at[0]) + x * 48, wz = Int(at[2]) + z * 48
            if vw.gen.column(wx, wz).biome.name == want || (vw.gen as? DeepGen)?.layerName(wx, Int(at[1]), wz) == want { vg.player.pos = V3(Float(wx) + 0.5, at[1], Float(wz) + 0.5); print("view: \(want) at \(wx) \(wz)"); break }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
    }
    // --near KIND: the eye --off blocks (22) off the nearest structure of that kind from --at, looking at it (PG6 checks).
    var nearYaw: Float? = nil
    if let kind = arg("--near"), let st = vw.gen.structures?.nearest(kind, x: Int(at[0]), z: Int(at[2]), maxRegions: 16) {
        let off = Float(arg("--off") ?? "") ?? 22
        vg.player.pos = V3(Float(st.anchor.x) + off * 0.7, at[1], Float(st.anchor.z) + off * 0.7)
        nearYaw = .pi / 4
        // --inside: at the anchor's own height (structures underground: cities, chambers, keeps, the Vault's sites).
        if CommandLine.arguments.contains("--inside") { vg.player.pos.y = Float(st.anchor.y) + 2 }
        print("view: \(kind) at \(st.anchor.x) \(st.anchor.y) \(st.anchor.z)")
    }
    // --rail [N]: the eye beside the nearest town railway's middle (P337 looks work), 8 blocks south and 5 up, facing
    // north; N picks the cell at N/100 along the line instead of the middle.
    if CommandLine.arguments.contains("--rail"), let gen = vw.gen as? WorldGen {
        let ax = Int(at[0]), az = Int(at[2])
        if let l = Railways.near(gen, x0: ax - 3000, z0: az - 3000, x1: ax + 3000, z1: az + 3000, pad: 0)
            .min(by: { abs($0.minX - ax) + abs($0.minZ - az) < abs($1.minX - ax) + abs($1.minZ - az) }), !l.cells.isEmpty {
            let f = Float(arg("--rail").flatMap { Int($0) } ?? 50) / 100
            let c = l.cells[min(l.cells.count - 1, max(0, Int(Float(l.cells.count - 1) * f)))]
            vg.player.pos = V3(Float(c.x) + 0.5, Float(c.y) + 5, Float(c.z) + 8.5)
            nearYaw = 0
            print("view: railway \(l.name), \(l.cells.count) cells, \(l.stations.count) stations; eye by \(c.x) \(c.y) \(c.z)")
        }
    }
    // --up N: the eye N blocks over the ground (or the sea) under it.
    if let up = Float(arg("--up") ?? "") {
        let h = vw.gen.column(Int(floor(vg.player.pos.x)), Int(floor(vg.player.pos.z))).height
        vg.player.pos.y = Float(max(h, SEA) + 1) + up
    }
    let lt = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
    print(String(format: "view: %d chunks: gen %.0f ms, mesh %.0f ms (wall, all cores)", vw.chunks.count, lt.gen * 1000, lt.mesh * 1000))
    // P437 (h): --edittime: place a block in the first air cell beside a solid one near the eye, then break it, and
    // time each step (the write with its remesh, the structure check, falling-block checks) as the game runs them.
    if CommandLine.arguments.contains("--edittime") {
        if CommandLine.arguments.contains("--editlane") { World.editLane = true }       // (P440: as on the headset)
        let ex = Int(floor(vg.player.pos.x)), ez = Int(floor(vg.player.pos.z))
        var cells: [IVec3] = []
        for dy in -6...6 { for dz in -3...3 { for dx in -3...3 {
            let x = ex + dx, y = Int(floor(vg.player.pos.y)) + dy, z = ez + dz
            if vw.block(x, y, z) == AIR && (Blocks.opaque[Int(vw.block(x, y - 1, z))] || vw.solidAt(x, y - 1, z)) { cells.append(IVec3(x, y, z)) }
        } } }
        if cells.isEmpty {
            // (P440: no air over solid round the eye: the ground's top under it, from the column down)
            for dz in -2...2 { for dx in -2...2 {
                let x = ex + dx, z = ez + dz
                var y = CH - 2
                while y > 1 && !vw.solidAt(x, y - 1, z) { y -= 1 }
                if y > 1 && !vw.solidAt(x, y, z) { cells.append(IVec3(x, y, z)) }
            } }
            print("edittime: none round the eye; \(cells.count) on the ground under it (top \(cells.first?.y ?? -1))")
        }
        print("edittime: \(cells.count) candidate cells; on \(cells.first.map { Blocks.key(vw.block($0.x, $0.y - 1, $0.z)) } ?? "-")")
        func t(_ f: () -> Void) -> Double { let t0 = CFAbsoluteTimeGetCurrent(); f(); return (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
        for c in cells.prefix(4) {
            print("edittime: \(vw.loadQueue.count) checks waiting before; cleared")
            vw.loadQueue.removeAll(); vw.loadQueued.removeAll()
            // (as Game places a built block on field ground: the write, then the ground rising to its floor, meshed together)
            let m0 = World.syncMeshes
            let place = t { vw.editBatch { vw.setBlock(c.x, c.y, c.z, Blocks.id("stone_bricks")); vw.meetGround(c.x, c.y, c.z, Blocks.id("stone_bricks")) } }
            print("edittime: place meshed \(World.syncMeshes - m0) sections on the frame")
            print("edittime: place queued \(vw.loadQueue.count), grounded \(vw.loadQueue.first.map { Structure.grounded(vw, $0) } ?? false)")
            let sp = t { Structure.tick(vg) }
            let m1 = World.syncMeshes
            let brk = t { vw.setBlock(c.x, c.y - 1, c.z, AIR) }
            print("edittime: break meshed \(World.syncMeshes - m1) sections on the frame")
            let sb = t { Structure.tick(vg) }
            let tick = t { vg.gravityTick() }
            print(String(format: "edittime: at %d %d %d (under: %@) place %.1f ms + structure %.1f ms; break below %.1f ms + structure %.1f ms; gravity %.1f ms; worst check %.1f ms",
                         c.x, c.y, c.z, Blocks.key(vw.block(c.x, c.y - 2, c.z)), place, sp, brk, sb, tick, Structure.worstMs))
        }
        // P440: stone put on the ground as the game does it (the write, then the ground swelling toward the aim), against
        // what the frame meshed before (every section round the touched ones: 27 at most, besides the write's own).
        if vw.fieldTerrain, let c = cells.dropFirst(4).first ?? cells.first {
            let stone = Blocks.id("stone")
            let m0 = World.syncMeshes
            let ms = t {
                vw.editBatch {
                    vw.setBlock(c.x, c.y, c.z, stone)
                    vw.fieldSphere(V3(Float(c.x) + 0.5, Float(c.y) + 0.45, Float(c.z) + 0.5), radius: 0.62, carve: false,
                                   material: FieldMat.index[Int(stone)], keepSolid: true, remesh: true)
                }
            }
            let meshed = World.syncMeshes - m0
            let lane = t { World.editQueue.sync {} }
            if World.editLane { print(String(format: "edittime: the edit lane had its meshes ready %.1f ms later", lane)) }
            var ring: [(Chunk, Int)] = []
            let sy = c.y >> 4
            for dz in -1...1 { for dx in -1...1 {
                guard let n = vw.chunkAt(c.x + dx * CS, c.z + dz * CS) else { continue }
                for s in max(0, sy - 1)...min(NSEC - 1, sy + 1) { ring.append((n, s)) }
            } }
            let old = t { for (n, s) in ring { vw.remeshSync(n, s) } }
            print(String(format: "edittime: stone on the ground at %d %d %d: %.1f ms on the frame (%d sections meshed); before, the ring of %d sections alone took %.1f ms",
                         c.x, c.y, c.z, ms, meshed, ring.count, old))
        }
    }
    // P446 (Oct 25 09:13, "it's freezing every time I break a block", fps 4 mining dirt with a full pack): --digtime N
    // mines N ground cells by the eye as the game mines them (survival, the pack full: a chip and its bite at each crack
    // level, then the break with its drop into the pack, the dig's carve), each step timed on the frame. --bites N first
    // scatters N blast bites round the eye (a fought-over field: World.biteList walks them all for every section).
    // --drops N: N dropped items lying round the eye, then 3 s of the item update and drawing, timed.
    if let nb = Int(arg("--bites") ?? "") {
        let e = vg.player.pos
        var made = 0, tries = 0
        while made < nb && tries < nb * 20 {
            tries += 1
            let x = Int(floor(e.x)) + Int.random(in: -24...24), z = Int(floor(e.z)) + Int.random(in: -24...24)
            var y = Int(floor(e.y)) + 8
            while y > 1 && !vw.solidAt(x, y, z) { y -= 1 }
            guard y > 1 else { continue }
            vw.addBite(IVec3(x, y, z), at: V3(Float(x) + 0.5, Float(y) + 1, Float(z) + 0.5), axis: V3(0, 1, 0), radius: 0.4, depth: 0.2, seed: UInt32(made), sync: false)
            made += 1
        }
        print("view: bites: \(made) scattered round the eye (\(vw.bites.count) bitten blocks)")
    }
    if let n = Int(arg("--digtime") ?? "") {
        if CommandLine.arguments.contains("--editlane") { World.editLane = true }       // (as on the headset)
        vg.survival = true; vg.paused = false
        var fill = 0
        while fill < 60 && vg.inventory.add(ItemStack(Items.id("cobblestone"), 64)).isEmpty { fill += 1 }
        print("view: digtime: pack filled with \(fill) stacks; edit lane \(World.editLane ? "on" : "off")")
        let ex = Int(floor(vg.player.pos.x)), ez = Int(floor(vg.player.pos.z))
        var cells: [IVec3] = []
        for dz in -3...3 { for dx in -3...3 where cells.count < n {
            var y = Int(floor(vg.player.pos.y)) + 2
            while y > 1 && !vw.groundAt(ex + dx, y, ez + dz) { y -= 1 }
            if y > 1 { cells.append(IVec3(ex + dx, y, ez + dz)) }
        } }
        func t(_ f: () -> Void) -> Double { let t0 = CFAbsoluteTimeGetCurrent(); f(); return (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
        for _ in 0..<36 { vg.tick(1.0 / 72) }
        for p in cells {
            let b = vw.block(p.x, p.y, p.z)
            let hp = V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5)
            var strikes: [Double] = []
            for level in 1...7 {
                let m0 = World.syncMeshes
                strikes.append(t {
                    vw.chip(p, level: level, face: 2, remesh: false)
                    vw.addBite(p, at: hp, axis: V3(0, -1, 0), radius: 0.22 + 0.025 * Float(level), depth: 0.1, seed: UInt32(level), sync: true)
                })
                if level == 1 { print("view: digtime: a strike meshed \(World.syncMeshes - m0) sections on the frame") }
            }
            let m1 = World.syncMeshes
            let brk = t {
                vg.breakBlock(p, b, drop: true, toPack: true)
                if SmoothTerrain.natural[Int(b)] { _ = vw.carve(at: hp - V3(0, 0.25, 0), radius: Game.digRadius(b), mode: .shape) }
            }
            let brkMeshed = World.syncMeshes - m1
            var worst = 0.0
            for _ in 0..<36 { worst = max(worst, t { vg.tick(1.0 / 72) }) }
            let lane = t { World.editQueue.sync {} }
            print(String(format: "view: digtime: %@ at %d %d %d: strikes %@ ms; break %.1f ms (%d sections meshed on the frame); worst of the next 36 ticks %.1f ms; edit lane done %.1f ms later; %d drops lying",
                         Blocks.key(b), p.x, p.y, p.z, strikes.map { String(format: "%.1f", $0) }.joined(separator: " "), brk, brkMeshed, worst, lane, vg.drops.items.count))
        }
    }
    if let n = Int(arg("--drops") ?? "") {
        let e = vg.player.pos
        let kinds = ["dirt", "cobblestone", "oak_log", "sand", "gravel", "stone", "iron_ingot", "arrow"].map { Items.id($0) }
        for i in 0..<n {
            let x = e.x + Float.random(in: -24...24), z = e.z + Float.random(in: -24...24)
            var y = Int(floor(e.y)) + 8
            while y > 1 && !vw.solidAt(Int(floor(x)), y, Int(floor(z))) { y -= 1 }
            vg.drops.spawn(ItemStack(kinds[i % kinds.count], 1 + i % 5), at: V3(x, Float(y) + 1.2, z), vel: .zero)
        }
        vg.paused = false
        let buf = UnsafeMutablePointer<EntityVert>.allocate(capacity: 600_000)
        defer { buf.deallocate() }
        var upd: [Double] = [], drw: [Double] = [], quads = 0
        for f in 0..<216 {
            let t0 = CFAbsoluteTimeGetCurrent()
            vg.drops.update(1.0 / 72, game: vg)
            let t1 = CFAbsoluteTimeGetCurrent()
            var wr = EntityWriter(out: buf, capacity: 600_000)
            vg.drops.write(&wr, eye: vg.player.eye, right: V3(1, 0, 0), up: V3(0, -1, 0), world: vw, daylight: 1, time: 0)
            let t2 = CFAbsoluteTimeGetCurrent()
            if f >= 144 { upd.append((t1 - t0) * 1000); drw.append((t2 - t1) * 1000); quads = wr.n / 6 }
        }
        let asleep = vg.drops.items.filter { $0.asleep }.count
        print(String(format: "view: drops: %d lying (%d asleep): update %.2f ms mean, %.2f worst; drawing %.2f ms mean (%d quads) over the last second",
                     vg.drops.items.count, asleep, upd.reduce(0, +) / Double(upd.count), upd.max() ?? 0, drw.reduce(0, +) / Double(drw.count), quads))
    }
    // P337 step 7: --rail plays 4 s through Game.tick beside the line and reports what the trains cost a frame.
    if CommandLine.arguments.contains("--rail") {
        vg.paused = false; vg.survival = false
        var trainMs = 0.0, worst = 0.0, mobMs = 0.0, frames = 0
        for _ in 0..<288 {
            vg.tick(1.0 / 72)
            var t = 0.0
            for i in 0..<TickProf.count {
                let n = TickProf.names[i].description
                if n == "trains" { t += TickProf.times[i] * 1000 } else if n == "mobs" { mobMs += TickProf.times[i] * 1000 }
            }
            trainMs += t; worst = max(worst, t); frames += 1
        }
        let cars = vg.mobs.mobs.filter { Trains.isCar($0) }.count
        print(String(format: "view: train upkeep %.3f ms a frame (worst %.2f), mobs incl. moving cars %.2f ms, over %d frames; %d cars built, %d trains known",
                     trainMs / Double(frames), worst, mobMs / Double(frames), frames, cars, Trains.trains.count))
    }
    if CommandLine.arguments.contains("--fallen") { AshFallen.refresh(vg); print("view: \(AshFallen.mobs.count) fallen") }   // P326: the Ash Vault's dead
    // The note's "facing" yaw is the player's yaw negated (VoiceNoteCore).
    var yaw = (nearYaw ?? 0) - look[0] * .pi / 180, pitch = look[1] * .pi / 180
    // --breakup [SECONDS]: a Cinder Tank 14 blocks ahead destroyed (P464: it comes apart in pieces), its pieces
    // flying for SECONDS (0.6) before the picture.
    if CommandLine.arguments.contains("--breakup") {
        let f = V3(-sinf(yaw), 0, -cosf(yaw))
        let at = vg.player.pos + f * 14
        let gx = Int(floor(at.x)), gz = Int(floor(at.z))
        var gy = Int(vg.player.pos.y)
        while gy > 1 && !vw.solidAt(gx, gy - 1, gz) { gy -= 1 }
        let tk = Mob(.ashTank, at: V3(at.x, Float(gy), at.z))
        tk.ashSetup()
        tk.yaw = yaw + 0.6
        let n0 = vg.debris.bodies.count
        vg.ashUnitDied(tk)
        let n1 = vg.debris.bodies.count
        let secs = Float(arg("--breakup") ?? "") ?? 0.6
        var tt: Float = 0
        while tt < secs { vg.debris.tick(1.0 / 72, world: vw); tt += 1.0 / 72 }
        print("view: breakup: a Cinder Tank came apart in \(n1 - n0) pieces (\(vg.debris.bodies.count) live after \(secs) s)")
    }
    // --fighterskin [PITCH,ROLL]: a Salvaged Fighter (P464) on the ground 16 blocks ahead, side-on, optionally tilted
    // (degrees); BS_FIGHTERBLOCKS=1 draws its blocks instead of the fighter model.
    if CommandLine.arguments.contains("--fighterskin") {
        let f = V3(-sinf(yaw), 0, -cosf(yaw))
        let at = vg.player.pos + f * 16
        let gx = Int(floor(at.x)), gz = Int(floor(at.z))
        var gy = Int(vg.player.pos.y)
        while gy > 1 && !vw.solidAt(gx, gy - 1, gz) { gy -= 1 }
        let fp = vw.ships.spawn(AshWrecks.salvagedFighter(), at: V3(at.x, Float(gy) + 1.2, at.z), yaw: yaw + .pi / 2, name: AshWrecks.fighterName, role: "capplane")
        fp.initialBlocks = fp.blockCount
        AshWrecks.setDown(fp, vw)
        let tilt = (arg("--fighterskin") ?? "").split(separator: ",").compactMap { Float($0) }
        if tilt.count == 2 {
            fp.rot = fp.rot * Quat(angle: tilt[0] * .pi / 180, axis: V3(1, 0, 0)) * Quat(angle: tilt[1] * .pi / 180, axis: V3(0, 0, 1))
            fp.pos.y += 4
        }
        fp.mesh.rebuildAll(fp, device: vw.device, queue: vw.ships.meshQueue)
        AshWrecks.syncSkins(vw)
        let sk = AshWrecks.skinMobs
        print("view: Salvaged Fighter at \(Int(fp.pos.x)) \(Int(fp.pos.y)) \(Int(fp.pos.z)), \(fp.blockCount) blocks, skin \(sk.count) (\(sk.first.map { String(format: "%.1f %.1f %.1f", $0.pos.x, $0.pos.y, $0.pos.z) } ?? "-")), hidden \(fp.hidden)")
    }
    // --sidecarskin [DEG]: an Ashguard Sidecar (P461) on the ground 6 blocks ahead, turned DEG from facing the eye (90:
    // side-on, its left showing); BS_FIGHTERBLOCKS=1 draws its blocks instead of the motorcycle model.
    if CommandLine.arguments.contains("--sidecarskin") {
        let f = V3(-sinf(yaw), 0, -cosf(yaw))
        let at = vg.player.pos + f * 6
        let gx = Int(floor(at.x)), gz = Int(floor(at.z))
        var gy = Int(vg.player.pos.y) + 4
        while gy > 1 && !vw.solidAt(gx, gy - 1, gz) { gy -= 1 }
        let sc = vw.ships.spawn(AshCommandeer.sidecar(), at: V3(at.x, Float(gy) + 3, at.z), yaw: yaw + (Float(arg("--sidecarskin") ?? "") ?? 90) * .pi / 180, name: AshCommandeer.sidecarName, role: "")
        sc.role = nil
        VehicleWorks.settle(sc, on: V3(at.x, Float(gy), at.z))
        sc.initialBlocks = sc.blockCount
        sc.mesh.rebuildAll(sc, device: vw.device, queue: vw.ships.meshQueue)
        AshWrecks.syncSkins(vw, dt: 0.1)
        print("view: Ashguard Sidecar at \(Int(sc.pos.x)) \(Int(sc.pos.y)) \(Int(sc.pos.z)), \(sc.blockCount) blocks, skins \(AshWrecks.skinMobs.count), hidden \(sc.hidden)")
    }
    // --cave: the eye in the nearest open cave below (spiralling out from the spot until one has room round the eye).
    if CommandLine.arguments.contains("--cave") {
        let px = Int(floor(vg.player.pos.x)), pz = Int(floor(vg.player.pos.z))
        func room(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            for dy in -1...1 { for dz in -2...2 { for dx in -2...2 where vw.block(x + dx, y + dy, z + dz) != AIR { return false } } }
            return true
        }
        search: for r in stride(from: 0, through: 64, by: 4) { for dz in stride(from: -r, through: r, by: 4) { for dx in stride(from: -r, through: r, by: 4) where max(abs(dx), abs(dz)) == r {
            _ = vw.loadSync(center: V3(Float(px + dx), 80, Float(pz + dz)), radius: 1)
            let top = vw.gen.column(px + dx, pz + dz).height
            var y = top - 8
            while y > 20 { if room(px + dx, y, pz + dz) { vg.player.pos = V3(Float(px + dx) + 0.5, Float(y), Float(pz + dz) + 0.5); print("view: cave at \(px + dx) \(y) \(pz + dz)"); break search }; y -= 1 }
        } } }
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
    }
    // --cavemouth (P392 step 7): the eye just inside the nearest cave mouth round the spot (open cells with natural rock over
    // them, open sky 4-6 blocks one way, the cave going on 4 blocks the other), facing out; --look's yaw turns from there.
    if CommandLine.arguments.contains("--cavemouth") {
        let px = Int(floor(vg.player.pos.x)), pz = Int(floor(vg.player.pos.z))
        func top(_ x: Int, _ z: Int) -> Int { Int(vw.chunkAt(x, z)?.height[mod(x, CS) + mod(z, CS) * CS] ?? -1) }
        func open2(_ x: Int, _ y: Int, _ z: Int) -> Bool { vw.isAir(x, y, z) && vw.isAir(x, y + 1, z) }
        var best: (Int, Int, Int, Int, Int)? = nil, bestD = Int.max
        for z in (pz - 160)...(pz + 160) { for x in (px - 160)...(px + 160) {
            let d2 = (x - px) * (x - px) + (z - pz) * (z - pz)
            if d2 >= bestD { continue }
            let h = top(x, z)
            guard h > 0 else { continue }
            var y = h - 3
            while y > max(8, h - 40) {
                defer { y -= 1 }
                guard open2(x, y, z), vw.groundAt(x, y + 3, z) || vw.groundAt(x, y + 4, z) else { continue }      // (natural rock over it, not a roof)
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    var sky = false
                    for k in 4...6 where open2(x + dx * k, y, z + dz * k) && top(x + dx * k, z + dz * k) < y { sky = true }
                    guard sky, open2(x - dx * 4, y, z - dz * 4), open2(x - dx * 2, y, z - dz * 2), open2(x + dx * 2, y, z + dz * 2) else { continue }
                    best = (x, y, z, dx, dz); bestD = d2
                    break
                }
                if bestD == d2 { break }
            }
        } }
        if let (x, y, z, dx, dz) = best {
            vg.player.pos = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            yaw = atan2f(-Float(dx), -Float(dz)) - look[0] * .pi / 180
            print("view: cave mouth at \(x) \(y) \(z), facing out (\(dx), \(dz))")
            _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        } else { print("view: no cave mouth within 160 blocks") }
    }
    // --meshbench: mesh the 5x5 chunks round the eye three ways (blocks, round-2 smooth, field smooth) and print the time
    // and quads of each (P142 cost on the mesh workers; single thread, this build's optimization level).
    // --groundline: the smooth ground offset (World.smoothGroundOffset, the view follows it) at 12 standing spots ahead.
    if CommandLine.arguments.contains("--fieldwalk") { print(World.fieldWalkCheck(vg)) }     // (PG2 rewrite)
    if CommandLine.arguments.contains("--fieldbodies") { print(World.fieldBodiesCheck(vg)) } // (PG2 rewrite)
    if FieldTerrain.statsOn { print(FieldTerrain.statsLine()) }
    // --fielddump: the ground the view's centre ray meets, and the field's densities (1/32 block) round it, slice by slice.
    // --collapse (P351): a cave carved under the ground in front of the eye with a loose ball of ground left inside it;
    // one more dig beside the ball and a second of play: the ball must leave the field and fall as debris.
    if CommandLine.arguments.contains("--collapse"), vw.fieldTerrain {
        let fx = Int(vg.player.pos.x), fz = Int(vg.player.pos.z) - 12
        let top = Int(vw.chunkAt(fx, fz)?.height[mod(fx, CS) + mod(fz, CS) * CS] ?? 100)
        let ctr = V3(Float(fx) + 0.5, Float(top - 9) + 0.5, Float(fz) + 0.5)
        vw.collapsing = true
        _ = vw.fieldSphere(ctr, radius: 6, carve: true, material: nil, remesh: true)
        _ = vw.fieldSphere(ctr, radius: 1.6, carve: false, material: FieldMat.index[Int(STONE)], remesh: true)
        // (a neck from the ball up to the cave's roof holds it)
        for k in 0..<7 { _ = vw.fieldSphere(ctr + V3(0, 1.5 + Float(k) * 0.75, 0), radius: 0.9, carve: false, material: FieldMat.index[Int(STONE)], remesh: true) }
        vw.collapsing = false
        func ballCells() -> Int {
            var n = 0
            for y in -2...2 { for z in -2...2 { for x in -2...2 where vw.isGround(IVec3(Int(ctr.x) + x, Int(ctr.y) + y, Int(ctr.z) + z)) { n += 1 } } }
            return n
        }
        let before = ballCells(), floaters = FieldTerrain.floatersDropped
        let held = ballCells()                                   // (still held by the neck)
        vg.paused = false
        for _ in 0..<10 { vg.tick(1.0 / 72) }
        let stillHeld = ballCells()
        _ = vw.fieldSphere(ctr + V3(0, 3.2, 0), radius: 1.3, carve: true, material: nil, remesh: true)     // the neck cut
        vg.paused = false
        for _ in 0..<72 { vg.tick(1.0 / 72) }
        let after = ballCells()
        print("view: collapse \(after == 0 && before > 0 && stillHeld == held ? "OK" : "FAIL"): ball \(before) cells, \(stillHeld) while the neck held, \(after) after the cut, \(GroundCollapse.dropped) cells dropped as debris, \(vg.debris.count) debris pieces; generation took out \(floaters) floating cells")
    }
    if CommandLine.arguments.contains("--fielddump") {
        let dir = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        let eye = vg.player.pos + V3(0, 1.62, 0)
        if vw.raycast(eye, dir, maxDist: 60) != nil, let h = vw.fieldHit {
            print("fielddump: hit \(h.at) cell \(h.cell.x) \(h.cell.y) \(h.cell.z)")
            for dy in stride(from: 2, through: -2, by: -1) {
                var lines: [String] = []
                for dz in -3...3 {
                    var row = ""
                    for dx in -3...3 {
                        let x = h.cell.x + dx, y = h.cell.y + dy, z = h.cell.z + dz
                        let d = vw.chunkAt(x, z).map { Int($0.blocks.density(Chunk.index(mod(x, CS), y, mod(z, CS)))) } ?? 0
                        row += String(format: "%5d", d) + (mod(x, CS) == 15 ? " |" : "")
                    }
                    lines.append(row + (mod(h.cell.z + dz, CS) == 15 ? "   (chunk border below)" : ""))
                }
                print("fielddump: y \(h.cell.y + dy) (x \(h.cell.x - 3)...\(h.cell.x + 3), z down \(h.cell.z - 3)...\(h.cell.z + 3))\n" + lines.joined(separator: "\n"))
            }
        } else { print("fielddump: the centre ray meets no ground") }
    }
    // --probe R: every built block (not air, water or ground in the field) within R blocks of the eye that has water
    // or air under it, with what is under it (P377 step 4: things floating over water).
    if let r = Int(arg("--probe") ?? "") {
        let e = vg.player.pos
        let ex = Int(floor(e.x)), ey = Int(floor(e.y)), ez = Int(floor(e.z))
        for y in max(1, ey - r)...min(CH - 2, ey + r) { for z in (ez - r)...(ez + r) { for x in (ex - r)...(ex + r) {
            let b = vw.rawBlock(x, y, z), u = vw.rawBlock(x, y - 1, z)
            guard b != AIR && !Blocks.isLiquid(b) && (u == AIR || Blocks.isLiquid(u)) && Blocks.opaque[Int(b)] else { continue }
            print("probe: \(x) \(y) \(z) \(Blocks.key(b)) over \(Blocks.key(u))")
        } } }
        if let sc = vw.gen.structures, let st = sc.nearest("shipwreck", x: ex, z: ez, maxRegions: 2) {
            print("probe: nearest shipwreck anchor \(st.anchor)")
        }
    }
    // --fluidprobe R (P378 step 2): every water and lava cell within R blocks of the eye: its state, the ground's density
    // in it, under it and beside it (1/32 block, > 0 inside), what is built under and beside it, the block light over it
    // and the brightest in the open cells round it; then the pools taken out and rims raised as the chunks were made.
    // --fluidticks N (P378): N water ticks (and a lava tick every sixth) before the frame, the way the game runs them
    // round the player, so a view shows fluids as they settle in play rather than as generated.
    if let n = Int(arg("--fluidticks") ?? "") {
        vw.activeCenter = vg.player.pos                                     // (the fluids round the player run: FarTicks)
        for k in 0..<n { vw.fluidTick(); if k % 6 == 5 { vw.fluidTick(lava: true) } }
        let px = Int(floor(vg.player.pos.x)), pz = Int(floor(vg.player.pos.z)), rr = vw.renderDistance * CS
        vw.remeshArea(x0: px - rr, z0: pz - rr, x1: px + rr, z1: pz + rr, y0: 0, y1: CH - 1)
        print("fluidticks: \(n) water ticks, \(n / 6) lava ticks")
    }
    // --fluidslope N (P378 step 4): N water sources set on open sloping ground round the eye (a cell whose four sides'
    // drawn floors differ by 0.2 to 1 block), 40 water ticks each; where the spread went against the drawn ground (the
    // mean height of the floors it reached against the source's, and the share on higher floors).
    if let want = Int(arg("--fluidslope") ?? "") {
        vw.activeCenter = vg.player.pos
        let ex = Int(floor(vg.player.pos.x)), ez = Int(floor(vg.player.pos.z))
        var srcs = 0, cells = 0, up = 0, sum: Float = 0, level = 0, levelUp = 0, levelSum: Float = 0
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool { vw.fluidCell(x, y, z) == AIR && vw.builtBlock(x, y, z) == AIR }
        search: for r in stride(from: 4, through: 64, by: 4) { for dz in stride(from: -r, through: r, by: 4) { for dx in stride(from: -r, through: r, by: 4) where max(abs(dx), abs(dz)) == r {
            let x = ex + dx, z = ez + dz
            guard vw.isLoaded(x - 8, z - 8) && vw.isLoaded(x + 8, z + 8) else { continue }
            var y = CH - 2
            while y > 2 && open(x, y, z) { y -= 1 }
            y += 1
            guard y > SEA - 4, open(x, y, z) else { continue }
            var dry = true
            for qz in (z - 8)...(z + 8) { for qx in (x - 8)...(x + 8) { for qy in (y - 4)...(y + 2) where Blocks.fluidKind[Int(vw.builtBlock(qx, qy, qz))] != 0 { dry = false } } }
            guard dry else { continue }
            let f0 = vw.drawnFloor(x, y, z)
            guard f0 > Float(y) - 1 else { continue }
            var lo = Float.infinity, hi = -Float.infinity
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] { guard open(x + d.x, y, z + d.z) else { continue search }; let f = vw.drawnFloor(x + d.x, y, z + d.z); lo = min(lo, f); hi = max(hi, f) }
            guard hi - lo >= 0.2 && hi - lo <= 1 else { continue }
            vw.setBlock(x, y, z, WATER)
            for _ in 0..<40 { vw.fluidTick() }
            var wet: [IVec3] = []
            for qz in (z - 8)...(z + 8) { for qx in (x - 8)...(x + 8) { for qy in (y - 6)...(y + 1) where Blocks.fluidKind[Int(vw.builtBlock(qx, qy, qz))] == 1 {
                wet.append(IVec3(qx, qy, qz))
                guard qx != x || qy != y || qz != z else { continue }
                let f = vw.drawnFloor(qx, qy, qz)
                cells += 1; sum += f - f0; if f > f0 + 0.1 { up += 1 }
                if qy == y { level += 1; levelSum += f - f0; if f > f0 + 0.1 { levelUp += 1 } }   // (spread at its own height)
            } } }
            for c in wet { vw.setBlock(c.x, c.y, c.z, AIR) }
            for _ in 0..<12 { vw.fluidTick() }
            srcs += 1
            if srcs >= want { break search }
        } } }
        let mean = cells > 0 ? sum / Float(cells) : 0, share = cells > 0 ? Float(up) / Float(cells) : 0
        let levelMean = level > 0 ? levelSum / Float(level) : 0, levelShare = level > 0 ? Float(levelUp) / Float(level) : 0
        print("fluidslope: " + (srcs > 0 && mean < -0.1 && share < 0.25 && levelShare < 0.1 ? "ok" : "FAIL") + String(format: " %d sources on sloping ground, %d cells reached, their floors %.2f blocks against the source's on average, %.0f%% on higher ground",
                     srcs, cells, mean, share * 100))
        print(String(format: "fluidslope: at the source's own height %d cells, their floors %.2f blocks against the source's, %.0f%% on higher ground", level, levelMean, levelShare * 100))
    }
    if let r = Int(arg("--fluidprobe") ?? "") {
        let e = vg.player.pos
        let ex = Int(floor(e.x)), ey = Int(floor(e.y)), ez = Int(floor(e.z))
        var n = 0
        func side(_ x: Int, _ y: Int, _ z: Int) -> String { let b = vw.builtBlock(x, y, z); return b == AIR ? "." : Blocks.key(b) }
        func dens(_ x: Int, _ y: Int, _ z: Int) -> Int { vw.chunkAt(x, z).map { Int($0.blocks.density(Chunk.index(mod(x, CS), y, mod(z, CS)))) } ?? -99 }
        // (the brightest block light in the open cells round it, two out: what lights the ground beside it)
        func near(_ x: Int, _ y: Int, _ z: Int) -> Int {
            var m = 0
            for dy in -2...2 { for dz in -2...2 { for dx in -2...2 where vw.builtBlock(x + dx, y + dy, z + dz) == AIR && dens(x + dx, y + dy, z + dz) <= 0 {
                m = max(m, Int(vw.lightAt(x + dx, y + dy, z + dz).block)) } } }
            return m
        }
        for y in max(1, ey - r)...min(CH - 2, ey + r) { for z in (ez - r)...(ez + r) { for x in (ex - r)...(ex + r) {
            let b = vw.builtBlock(x, y, z)
            guard Blocks.fluidKind[Int(b)] != 0 else { continue }
            n += 1
            if n <= 300 {
                print("fluidprobe: \(x) \(y) \(z) \(Blocks.key(b)) level \(Blocks.fluidLevel[Int(b)]) density \(dens(x, y, z)) under \(dens(x, y - 1, z)) \(Blocks.key(vw.builtBlock(x, y - 1, z))) sides \(dens(x + 1, y, z)) \(dens(x - 1, y, z)) \(dens(x, y, z + 1)) \(dens(x, y, z - 1)) [\(side(x + 1, y, z)) \(side(x - 1, y, z)) \(side(x, y, z + 1)) \(side(x, y, z - 1))] light own \(vw.lightAt(x, y, z).block) above \(vw.lightAt(x, y + 1, z).block) beside \(near(x, y, z)) (emit bits \(vw.chunkAt(x, z).map { String($0.blocks.emitMask >> UInt32(max(0, (y >> 4) - 1)) & 7, radix: 2) } ?? "-"))")
            }
        } } }
        for l in (FieldTerrain.poolLog ?? []) { print("poollog: " + l) }
        print("fluidprobe: \(n) fluid cells; \(FieldTerrain.perchedDropped) perched cells taken out and \(FieldTerrain.rimsRaised) rim cells raised as the chunks were made")
    }
    // --finedig N (P377 step 1): N cells dug in a row ahead the way the game digs (the cell, then a ball where the blow
    // landed, off the cell's middle), then the frame; ground quads in the 3 x 3 chunks round the player, fine sections
    // and their memory, and a save round trip of a fine chunk's field file. BS_FINE=0: the cells-only before.
    if let n = Int(arg("--finedig") ?? "") {
        let fx = -sinf(yaw), fz = -cosf(yaw)
        var dug = 0
        for k in 0..<n {
            let side: Float = k % 3 == 0 ? 0.3 : (k % 3 == 1 ? -0.35 : 0.1)
            let px = vg.player.pos.x + fx * (3 + Float(k) * 0.7) - fz * side, pz = vg.player.pos.z + fz * (3 + Float(k) * 0.7) + fx * side
            var y = Int(vg.player.pos.y) + 4
            while y > 1 && vw.fieldDensity(at: V3(px, Float(y) + 0.5, pz)) <= 0 { y -= 1 }
            guard y > 1 else { continue }
            var top = Float(y) + 1
            while top > Float(y) && vw.fieldDensity(at: V3(px, top, pz)) <= 0 { top -= 0.05 }
            vw.setBlock(Int(floor(px)), y, Int(floor(pz)), AIR)
            vw.carve(at: V3(px, top - 0.25, pz), radius: 0.62, mode: .shape)
            dug += 1
        }
        let pcx = floorDiv(Int(floor(vg.player.pos.x)), CS), pcz = floorDiv(Int(floor(vg.player.pos.z)), CS)
        vw.remeshArea(x0: (pcx - 1) * CS, z0: (pcz - 1) * CS, x1: (pcx + 2) * CS - 1, z1: (pcz + 2) * CS - 1, y0: 0, y1: CH - 1)
        var gq = 0
        for dz in -1...1 { for dx in -1...1 { if let c = vw.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] { for s in c.sections { gq += s.groundQuads } } } }
        let t = FineField.tally(vw)
        var rt = "no fine chunk", bytes = 0
        if let c = vw.chunks.values.first(where: { !$0.blocks.fine.isEmpty }), let e = FieldTerrain.encode(c.blocks.field), let d = FieldTerrain.decode(e) {
            rt = d.fine == c.blocks.fine && d.fd == c.blocks.field.fd ? "same" : "DIFFERENT"
            bytes = e.count
        }
        print("finedig: \(dug) cells dug; ground quads in the 3x3 chunks \(gq); fine sections \(t.sections) (\(t.bytes / 1024) KB); field file round trip \(rt) (\(bytes) bytes packed)")
    }
    // --fieldblast: a power-4 blast on the ground 8 blocks ahead, then the frame (PG1 rewrite: the crater in the field).
    if CommandLine.arguments.contains("--fieldblast") {
        let fx = vg.player.pos.x - sinf(yaw) * 8, fz = vg.player.pos.z - cosf(yaw) * 8
        var fy = Int(vg.player.pos.y) + 6
        while fy > 1 && !Blocks.collide[Int(vw.block(Int(floor(fx)), fy, Int(floor(fz))))] { fy -= 1 }
        Explosion.explode(at: V3(fx, Float(fy) + 0.6, fz), power: 4, game: vg, decay: true)
        vw.remeshArea(x0: Int(fx) - 12, z0: Int(fz) - 12, x1: Int(fx) + 12, z1: Int(fz) + 12, y0: fy - 12, y1: fy + 12)
        print("fieldblast: at \(Int(fx)) \(fy) \(Int(fz))")
    }
    if CommandLine.arguments.contains("--groundline") {
        var out: [String] = []
        for k in 1...12 {
            let x = vg.player.pos.x - sinf(yaw) * Float(k) * 0.5, z = vg.player.pos.z - cosf(yaw) * Float(k) * 0.5
            var y = Int(vg.player.pos.y) + 4
            while y > 1 && !Blocks.opaque[Int(vw.block(Int(floor(x)), y, Int(floor(z))))] { y -= 1 }
            out.append(String(format: "%.2f", vw.smoothGroundOffset(V3(x, Float(y + 1), z))))
        }
        print("groundline: " + out.joined(separator: " "))
    }
    // --adaptivecheck (P381): the adaptive ground against the full ground round the eye (AdaptiveGroundTests.swift).
    if CommandLine.arguments.contains("--adaptivecheck") { print(AdaptiveGround.check(vw, eye: vg.player.pos)) }
    if CommandLine.arguments.contains("--adaptivewalk") { print(AdaptiveGround.walkCheck(vg)) }
    // --farcheck (P384): every far copy against what it stands for round the eye (AdaptiveGroundTests.swift).
    if CommandLine.arguments.contains("--farcheck") { print(AdaptiveGround.farCheck(vw, eye: vg.player.pos)) }
    if CommandLine.arguments.contains("--meshbench") {
        let pcx = floorDiv(Int(floor(vg.player.pos.x)), CS), pcz = floorDiv(Int(floor(vg.player.pos.z)), CS)
        let was = (SmoothTerrain.enabled, SmoothTerrain.fromField)
        let detailWas = Mesher.detailMeshes
        for (name, on, fld, det) in [("blocks", false, false, false), ("round2", true, false, false), ("field", true, true, false),
                                     ("realistic", true, true, true)] {
            SmoothTerrain.enabled = on; SmoothTerrain.fromField = fld; Mesher.detailMeshes = det
            var ms = 0.0, quads = 0, secs = 0, dq = 0
            for dz in -2...2 { for dx in -2...2 {
                guard let c = vw.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], let nb = vw.neighbourhood(c) else { continue }
                for sy in 0..<NSEC {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let m = Mesher.buildSection(nb.0, nb.1, sy: sy, site: vw.smoothSite(c), chunk: (c.cx, c.cz))
                    ms += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    if !m.opaque.isEmpty { secs += 1 }
                    quads += m.opaque.count / 8; dq += m.detail.count / DetailMesh.wordsPerQuad
                }
            } }
            print(String(format: "meshbench %@: %.1f ms, %d sections with geometry, %d quads, %d detail quads", name, ms, secs, quads, dq))
        }
        (SmoothTerrain.enabled, SmoothTerrain.fromField) = was
        Mesher.detailMeshes = detailWas
    }
    // --dig N: a plus-shaped pit N deep dug into the ground 6 blocks ahead (P142: digging leaves a dent in smooth land).
    if let n = Int(arg("--dig") ?? "") {
        let gx = Int(floor(vg.player.pos.x - sinf(yaw) * 6)), gz = Int(floor(vg.player.pos.z - cosf(yaw) * 6))
        var gy = Int(vg.player.pos.y)
        while gy > 1 && !Blocks.opaque[Int(vw.block(gx, gy, gz))] { gy -= 1 }
        for (ox, oz) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] { for d in 0..<n { vw.setBlock(gx + ox, gy - d, gz + oz, AIR) } }
        vw.setBlock(gx + 3, gy + 1, gz, Blocks.id("dirt"))          // and a placed block on the ground beside it
        print("view: dug \(n) at \(gx) \(gy) \(gz)")
        vw.remeshArea(x0: gx - 8, z0: gz - 8, x1: gx + 8, z1: gz + 8, y0: gy - 8, y1: gy + 8)    // (the game remeshes the ring in the background)
        if let p = arg("--dig-eye").map({ $0.split(separator: ",").compactMap { Float($0) } }), p.count == 3 {
            vg.player.pos = V3(Float(gx) + 0.5 + p[0], Float(gy) + p[1], Float(gz) + 0.5 + p[2])
        }
    }
    // --cutlog N (P433): the Nth log from the foot of the nearest living trunk within 16 blocks of the eye is struck out
    // (as a creative blow does), the sections round it remeshed: the tree must draw as before with that cell missing.
    func nearestTrunk() -> (Int, Int, Int)? {
        let ex = Int(floor(vg.player.pos.x)), ey = Int(floor(vg.player.pos.y)), ez = Int(floor(vg.player.pos.z))
        var best: (Int, Int, Int, Int)? = nil           // x, foot y, z, distance squared
        for z in (ez - 16)...(ez + 16) { for x in (ex - 16)...(ex + 16) {
            var y = ey + 24
            while y > ey - 12 {
                let b = Int(vw.block(x, y, z))
                guard ShapeTrunks.isLog[b], Int(ShapeTrunks.axisOf[b]) == 1 else { y -= 1; continue }
                var foot = y
                while ShapeTrunks.isLog[Int(vw.block(x, foot - 1, z))] { foot -= 1 }
                var top = y
                while ShapeTrunks.isLog[Int(vw.block(x, top + 1, z))] { top += 1 }
                let under = Int(vw.block(x, foot - 1, z))
                var crown = false
                for dy in -2...6 { for dz in -3...3 { for dx in -3...3 where Mesher.leafT[Int(vw.block(x + dx, top + dy, z + dz))] { crown = true } } }
                let d2 = (x - ex) * (x - ex) + (z - ez) * (z - ez)
                if top - foot + 1 >= 4 && crown && (Blocks.opaque[under] || Blocks.collide[under]) && (best == nil || d2 < best!.3) { best = (x, foot, z, d2) }
                y = foot - 1
            }
        } }
        return best.map { ($0.0, $0.1, $0.2) }
    }
    if let n = Int(arg("--cutlog") ?? "") {
        if let (x, foot, z) = nearestTrunk() {
            let cy = foot + max(0, n - 1)
            print("view: cutlog: trunk at \(x) \(foot) \(z), log \(n) (y \(cy)) struck out")
            vw.setBlock(x, cy, z, AIR)
            vw.remeshArea(x0: x - 10, z0: z - 10, x1: x + 10, z1: z + 10, y0: cy - 12, y1: cy + 24)
        } else { print("view: cutlog: no living trunk within 16 blocks") }
    }
    // --fell S (P441): the foot log of the nearest living trunk is cut as the game cuts it (Game.breakBlock: what stood
    // on it comes loose and topples away from the eye), then the game runs S seconds before the render.
    if let secs = Double(arg("--fell") ?? "") {
        if CommandLine.arguments.contains("--editlane") { World.editLane = true }       // (as on the headset)
        if let (x, foot, z) = nearestTrunk() {
            let p = IVec3(x, foot, z), b = vw.block(x, foot, z)
            vg.paused = false
            // (warmed up first: the first ticks after load pay one-time costs, 11 s of "input+hud" in a debug build)
            var before = 0.0
            for _ in 0..<36 { let t0 = CFAbsoluteTimeGetCurrent(); vg.tick(1.0 / 72); before = max(before, (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
            print(String(format: "view: fell: worst of 36 ticks before the cut %.1f ms", before))
            let ships0 = vw.ships.list.count
            // --felledits (P428): every block change from the cut on, and the ground cells round the tree that opened or
            // closed, printed after the run.
            let trace = CommandLine.arguments.contains("--felledits")
            var ground0: [IVec3: Bool] = [:]
            if trace {
                World.editTally = [:]; World.editCells = [:]
                for yy in (foot - 6)...(foot + 6) { for zz in (z - 14)...(z + 14) { for xx in (x - 14)...(x + 14) {
                    ground0[IVec3(xx, yy, zz)] = vw.groundAt(xx, yy, zz)
                } } }
            }
            let tb = CFAbsoluteTimeGetCurrent()
            vg.breakBlock(p, b, drop: false)
            print(String(format: "view: fell: the cut took %.1f ms; ", (CFAbsoluteTimeGetCurrent() - tb) * 1000)
                  + "trunk at \(x) \(foot) \(z) cut at its foot; \(vw.ships.list.count - ships0) body loose")
            let frames = Int(secs * 72)
            var worst = 0.0, worstAt = 0, worstWhat = "", sum = 0.0
            for i in 0..<frames {
                let t0 = CFAbsoluteTimeGetCurrent()
                vg.tick(1.0 / 72)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                sum += ms
                if ms > worst { worst = ms; worstAt = i; worstWhat = TickProf.summary() }
            }
            print(String(format: "view: fell: worst tick %.1f ms at frame %d (mean %.1f): ", worst, worstAt, sum / Double(max(1, frames))) + worstWhat)
            if trace {
                let top = (World.editTally ?? [:]).sorted { $0.value > $1.value }.prefix(12).map { k, n in
                    "\(k >> 32 != 0 ? "async " : "")\(Blocks.key(BlockID(truncatingIfNeeded: (k >> 16) & 0xFFFF))) -> \(Blocks.key(BlockID(truncatingIfNeeded: k & 0xFFFF))) x\(n)"
                }
                print("view: felledits: \(World.editCells.count) cells changed in the background; " + top.joined(separator: "; "))
                let moved = ground0.filter { vw.groundAt($0.key.x, $0.key.y, $0.key.z) != $0.value }.keys.sorted { ($0.y, $0.z, $0.x) < ($1.y, $1.z, $1.x) }
                print("view: felledits: \(moved.count) ground cells round the tree changed: " + moved.prefix(30).map {
                    "\($0.x),\($0.y),\($0.z) \(ground0[$0]! ? "opened" : "filled") (\(Blocks.key(vw.block($0.x, $0.y, $0.z))))"
                }.joined(separator: "; "))
                World.editTally = nil
            }
            // --noremesh (P428): the frame shows the meshes the game itself made while it ran (see --settlemesh), not a
            // fresh synchronous remesh round the cut.
            if !CommandLine.arguments.contains("--noremesh") {
                vw.remeshArea(x0: x - 12, z0: z - 12, x1: x + 12, z1: z + 12, y0: foot - 8, y1: foot + 30)
            }
            if let s = vw.ships.list.last(where: { Felling.isFelled($0) }) {
                print(String(format: "view: fell: after %.1f s the body is at %.1f %.1f %.1f, tipped %.0f deg, %d blocks; worst tick %.1f ms",
                             secs, s.pos.x, s.pos.y, s.pos.z, acosf(max(-1, min(1, s.rot.act(V3(0, 1, 0)).y))) * 180 / .pi, s.blockCount, worst))
                // --fellview YAW,PITCH,DIST (as --look): the eye DIST blocks from the stump, looking at it (P428).
                if let fv = arg("--fellview")?.split(separator: ",").compactMap({ Float($0) }), fv.count == 3 {
                    yaw = -fv[0] * .pi / 180; pitch = fv[1] * .pi / 180
                    let vd = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
                    vg.player.yaw = yaw; vg.player.pitch = pitch
                    vg.player.pos = V3(Float(x) + 0.5, Float(foot) + 1, Float(z) + 0.5) - vd * fv[2] - (vg.player.eye - vg.player.pos)
                }
            }
        } else { print("view: fell: no living trunk within 16 blocks") }
    }
    // --tick S (P428): the game runs S seconds on its own clock (nothing else done) before the render.
    if let secs = Double(arg("--tick") ?? "") {
        vg.paused = false
        for _ in 0..<Int(secs * 72) { vg.tick(1.0 / 72) }
    }
    // --settlemesh (P428): the world keeps updating at the eye until no generation or mesh job is out (at most 120 s),
    // so the frame shows what the game would draw once its own mesher caught up.
    if CommandLine.arguments.contains("--settlemesh") {
        let t0 = CFAbsoluteTimeGetCurrent()
        var quiet = 0, rounds = 0
        while quiet < 5 && CFAbsoluteTimeGetCurrent() - t0 < 120 {
            vw.update(center: vg.player.pos); rounds += 1
            quiet = vw.jobsOut == 0 ? quiet + 1 : 0
            usleep(20_000)
        }
        print(String(format: "view: settlemesh: %d updates, %.1f s, %d jobs still out", rounds, CFAbsoluteTimeGetCurrent() - t0, vw.jobsOut))
    }
    // --finelist (P428): the chunks within 4 of the eye holding half-block (fine) ground samples, and their sections.
    if CommandLine.arguments.contains("--finelist") {
        let ecx = floorDiv(Int(floor(vg.player.pos.x)), CS), ecz = floorDiv(Int(floor(vg.player.pos.z)), CS)
        var rows: [String] = []
        for dz in -4...4 { for dx in -4...4 {
            guard let c = vw.chunks[ChunkKey(x: ecx + dx, z: ecz + dz)], !c.blocks.fine.isEmpty else { continue }
            rows.append("\(c.cx),\(c.cz) [\(c.blocks.fine.keys.sorted().map(String.init).joined(separator: " "))]")
        } }
        print("view: finelist: \(rows.count) chunks with fine samples (eye in \(ecx),\(ecz)): " + rows.joined(separator: "; "))
    }
    // --sign TEXT: stand just inside the door under the nearest street sign with that line (the town nearest --at),
    // looking in (the generator moves towns between builds, so a note's position may no longer hold the building).
    if let want = arg("--sign"), let sc = vw.gen.structures,
       let s = sc.nearest("village", x: Int(at[0]), z: Int(at[2]), maxRegions: 12, accept: { _ in true }) {
        vg.player.pos = V3(Float(s.anchor.x), 140, Float(s.anchor.z))
        _ = vw.loadSync(center: vg.player.pos, radius: max(3, vw.renderDistance))
        let signs = vw.blockEntities.filter { $0.value.kind == .sign && $0.value.lines.contains(want) }.map { $0.key }
        if let p = signs.min(by: { abs($0.x - s.anchor.x) + abs($0.z - s.anchor.z) < abs($1.x - s.anchor.x) + abs($1.z - s.anchor.z) }) {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where Blocks.shape[Int(vw.block(p.x + dx, p.y - 2, p.z + dz))] == "door" {
                let d = V3(Float(dx), 0, Float(dz))
                vg.player.pos = V3(Float(p.x + dx) + 0.5, Float(p.y - 2), Float(p.z + dz) + 0.5) + d * Float(arg("--in").flatMap(Int.init) ?? 1)
                yaw = atan2f(-d.x, -d.z) + look[0] * .pi / 180; pitch = look[1] * .pi / 180
                print("view: \(want) sign at \(p.x) \(p.y) \(p.z), standing at \(vg.player.pos)")
            }
        }
    }
    // --scene waterstep: water spilling over a one-block step on a stone shelf in the air at --at, settled for 8 s
    // of fluid ticks; seen from the side, 12 blocks off along +x (P18: "water moving down a block looks weird from the
    // side"). --look still turns the view.
    if arg("--scene") == "waterstep" {
        let bx = Int(floor(at[0])), by = Int(floor(at[1])), bz = Int(floor(at[2]))
        _ = vw.loadSync(center: V3(Float(bx), Float(by), Float(bz)), radius: vw.renderDistance)   // (fluids tick in loaded chunks only)
        for x in (bx - 14)...(bx + 14) { for z in (bz - 14)...(bz + 14) {         // wide enough that the spread stays on it
            vw.setBlock(x, by, z, STONE)
            if z <= bz { vw.setBlock(x, by + 1, z, STONE) }
            for y in (by + (z <= bz ? 2 : 1))...(by + 6) { vw.setBlock(x, y, z, AIR) }
        } }
        for x in (bx - 1)...(bx + 1) { vw.setBlock(x, by + 2, bz - 2, WATER) }
        vg.player.pos = V3(Float(bx + 7) + 0.5, Float(by + 2), Float(bz) + 0.5)
        for _ in 0..<32 { vw.fluidTick() }                  // 8 s of water steps (Game.tick pauses behind the title menu)
        vg.player.pos = V3(Float(bx + 12) + 0.5, Float(by + 3), Float(bz) + 0.5); vg.player.vel = .zero
        yaw += .pi / 2
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
    }
    // --scene torches: a stone wall with a wall torch facing each way round a pillar, a standing torch and a lawn of
    // short grass and flowers in front, in the air at --at, seen from 4 blocks off (P86 wall torches, P75 grass bits).
    if arg("--scene") == "torches" {
        let bx = Int(floor(at[0])), by = Int(floor(at[1])), bz = Int(floor(at[2]))
        for x in (bx - 6)...(bx + 6) { for z in (bz - 8)...(bz + 2) {
            vw.setBlock(x, by, z, Blocks.id("grass_block"))
            for y in (by + 1)...(by + 5) { vw.setBlock(x, y, z, z == bz - 8 ? STONE : AIR) }
        } }
        for y in (by + 1)...(by + 3) { vw.setBlock(bx + 3, y, bz - 5, STONE) }        // a pillar: torches on its four sides
        vw.setBlock(bx, by + 2, bz - 7, TORCH + 2)                                     // on the back wall, facing the camera
        vw.setBlock(bx - 2, by + 2, bz - 7, Blocks.id("soul_torch[2]"))
        vw.setBlock(bx + 3, by + 2, bz - 4, TORCH + 2)
        vw.setBlock(bx + 2, by + 2, bz - 5, TORCH + 3)
        vw.setBlock(bx + 4, by + 2, bz - 5, TORCH + 4)
        vw.setBlock(bx - 4, by + 1, bz - 5, TORCH)
        for x in (bx - 6)...(bx + 6) { for z in (bz - 4)...(bz + 1) where (x * 7 + z * 13) % 3 != 0 {
            vw.setBlock(x, by + 1, z, (x + z) % 7 == 0 ? Blocks.id("poppy") : Blocks.id("short_grass"))
        } }
        let dist = Float(arg("--dist") ?? "") ?? 10                // the camera's distance from the back wall
        vg.player.pos = V3(Float(bx) + 0.5 + (Float(arg("--dx") ?? "") ?? 0), Float(by + 1), Float(bz - 7) + dist); vg.player.vel = .zero
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
    }
    // --scene machines (P442): the copper-circuit machines on a stone platform in the air at --at (daylight), fronts
    // south toward the camera, which stands --dist (6) blocks south of the row: dispenser, dropper, piston, sticky
    // piston, observer, a pushed piston with its head, a dispenser facing up and an observer facing away. --look turns
    // the view (try 25,-20 to see fronts, sides and tops).
    if arg("--scene") == "machines" {
        let bx = Int(floor(at[0])), by = Int(floor(at[1])), bz = Int(floor(at[2]))
        for x in (bx - 10)...(bx + 10) { for z in (bz - 6)...(bz + 8) {
            vw.setBlock(x, by, z, Blocks.id("smooth_stone"))
            for y in (by + 1)...(by + 4) { vw.setBlock(x, y, z, AIR) }
        } }
        let keys = ["dispenser[3]", "dropper[3]", "piston[3]", "sticky_piston[3]", "observer[3]", "piston[9]", "dispenser[1]", "observer[2]"]
        let z = bz - 3
        for (k, key) in keys.enumerated() {
            let x = bx - keys.count + 1 + 2 * k
            vw.editBatch { vw.setBlock(x, by + 1, z, Blocks.id(key)) }
            if key == "piston[9]" { vw.setBlock(x, by + 1, z + 1, Blocks.id("piston_head[3]")) }
        }
        let dist = Float(arg("--dist") ?? "") ?? 6
        vg.player.pos = V3(Float(bx) + 0.5, Float(by + 1), Float(z) + 0.5 + dist); vg.player.vel = .zero
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        vw.remeshArea(x0: bx - 12, z0: bz - 8, x1: bx + 12, z1: bz + 10, y0: by - 4, y1: by + 6)
        print("view: machines: \(keys.count) placed in a row at z \(z), y \(by + 1)")
    }
    // --pour lava|water [--pourticks N] (P443): a bucket emptied where the eye looks, as Game.useBucket pours it, then
    // N game ticks (default 720, 10 s) before the render, from 4 blocks back; prints the cells it reached and what
    // each stands on.
    if let kind = arg("--pour") {
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        let dir = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        let lava = kind == "lava", fluid = lava ? LAVA : WATER
        vg.player.yaw = yaw; vg.player.pitch = pitch
        if let at = vg.bucketCell(dir: dir, target: vw.raycast(vg.player.eye, dir, maxDist: 5)) {
            vg.pourFluid(fluid, at: at)
            print("view: pour: \(kind) at \(at.x) \(at.y) \(at.z) on \(Blocks.key(vw.block(at.x, at.y - 1, at.z))), ground there \(vw.groundAt(at.x, at.y - 1, at.z))")
            vg.paused = false
            for _ in 0..<(Int(arg("--pourticks") ?? "") ?? 720) { vg.tick(1.0 / 72) }    // (the game's own fluid clock)
            vg.player.pos += V3(-dir.x, 0, -dir.z) * 4                                    // (stepped back to see it)
            // --pourview YAW,PITCH,DIST (as --look): the eye DIST blocks from the poured cell, looking at it.
            if let pv = arg("--pourview")?.split(separator: ",").compactMap({ Float($0) }), pv.count == 3 {
                yaw = -pv[0] * .pi / 180; pitch = pv[1] * .pi / 180
                let vd = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
                vg.player.yaw = yaw; vg.player.pitch = pitch
                vg.player.pos = V3(Float(at.x) + 0.5, Float(at.y) + 0.5, Float(at.z) + 0.5) - vd * pv[2] - (vg.player.eye - vg.player.pos)
            }
            var cells: [String] = []
            for y in (at.y - 6)...(at.y + 1) { for z in (at.z - 6)...(at.z + 6) { for x in (at.x - 6)...(at.x + 6) {
                let b = vw.block(x, y, z)
                guard Blocks.fluidKind[Int(b)] == (lava ? 2 : 1) else { continue }
                let u = vw.block(x, y - 1, z)
                if Blocks.fluidKind[Int(u)] == 0 { cells.append("\(x),\(y),\(z) lv\(Blocks.fluidLevel[Int(b)]) on \(Blocks.key(u))\(vw.groundAt(x, y - 1, z) ? "" : " (no ground)")") }
            } } }
            print("view: pour: \(cells.count) bottom cells: " + cells.prefix(24).joined(separator: "; "))
            vw.remeshArea(x0: at.x - 10, z0: at.z - 10, x1: at.x + 10, z1: at.z + 10, y0: at.y - 10, y1: at.y + 6)
        } else { print("view: pour: nothing to pour on") }
    }
    // --scene groundthings (P382): copper wire and the other things that lie on the ground laid on the field's ground in
    // front of the eye (GroundDrapeTests.swift); --groundcheck prints how far each is off the drawn ground.
    if arg("--scene") == "groundthings" {
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        let things = GroundDrape.placeScene(vg, yaw: yaw)
        print("view: \(things.count) things laid on the ground")
        let px = Int(floor(vg.player.pos.x)), pz = Int(floor(vg.player.pos.z)), py = Int(floor(vg.player.pos.y))
        vw.remeshArea(x0: px - 16, z0: pz - 16, x1: px + 16, z1: pz + 16, y0: py - 48, y1: py + 8)
        if CommandLine.arguments.contains("--groundcheck") { print(GroundDrape.check(vw, things)) }
    }
    // --scene genthings (P398 (b)): what the generator itself laid on the field's ground within --reach N blocks (24) of the eye (moss
    // carpets in a lush cave, plants, snow, ...): --groundcheck prints how far each is off the drawn ground.
    if arg("--scene") == "genthings" {
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        let ex = Int(floor(vg.player.pos.x)), ey = Int(floor(vg.player.pos.y)), ez = Int(floor(vg.player.pos.z))
        var things: [(IVec3, String)] = []
        var seen: [String: Int] = [:]
        let reach = Int(arg("--reach") ?? "") ?? 24
        // P409: plants (crosses) too, and those standing over nothing: no ground in their cell's lower half or the cell
        // below, and no solid block under them (each must stand on the drawn ground).
        var overAir: [String: Int] = [:], plants = 0
        let crossR = RenderType.cross.rawValue
        for y in max(2, ey - reach)...min(CH - 2, ey + reach) { for z in (ez - reach)...(ez + reach) { for x in (ex - reach)...(ex + reach) {
            let b = vw.rawBlock(x, y, z)
            guard b != AIR else { continue }
            if Blocks.render[Int(b)] == crossR && !Blocks.isLiquid(b) && !Blocks.key(b).hasSuffix("vine") && !Blocks.key(b).contains("vines") {   // (vines hang)
                let under = vw.rawBlock(x, y - 1, z)
                if Blocks.render[Int(under)] != crossR {           // (the foot of a stack)
                    plants += 1
                    if vw.fieldDensity(at: V3(Float(x) + 0.5, Float(y) - 0.5, Float(z) + 0.5)) <= 0
                        && vw.fieldDensity(at: V3(Float(x) + 0.5, Float(y) - 0.25, Float(z) + 0.5)) <= 0
                        && !Blocks.collide[Int(under)] { overAir[Blocks.key(b), default: 0] += 1 }
                }
            }
            guard GroundDrape.seat[Int(b)] != 0 || Blocks.render[Int(b)] == crossR && !Blocks.isLiquid(b) else { continue }
            seen[Blocks.key(b), default: 0] += 1
            guard vw.fieldDensity(at: V3(Float(x) + 0.5, Float(y) - 0.5, Float(z) + 0.5)) > 0
                    || vw.fieldDensity(at: V3(Float(x) + 0.5, Float(y) - 1.5, Float(z) + 0.5)) > 0 else { continue }
            things.append((IVec3(x, y, z), Blocks.key(b)))
        } } }
        print("view: \(plants) plants in reach, \(overAir.values.reduce(0, +)) over air (" + overAir.keys.sorted().map { "\($0) \(overAir[$0]!)" }.joined(separator: ", ") + ")")
        print("view: \(things.count) generated things on the ground (seated things in reach: " + seen.keys.sorted().map { "\($0) \(seen[$0]!)" }.joined(separator: ", ") + ")")
        if CommandLine.arguments.contains("--groundcheck") { print(GroundDrape.check(vw, things)) }
    }
    // --scene spawncamp (P402): a new survival world's spawn with its abandoned camp (Sources/SpawnCamp.swift), the eye at
    // the spawn (--look picks the view; 0,-15 is the way a new player first faces).
    if arg("--scene") == "spawncamp" {
        vg.survival = true
        vg.player.pos = vg.spawnPoint
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        if let c = vg.placeSpawnCamp() {
            print("view: spawn \(vg.player.pos), camp fire \(c.fire), bench \(c.bench), chest \(c.chest), frame \(c.frame.count) blocks, tree \(c.tree.map { "\($0)" } ?? "none"), \(c.path.count) torches on the way")
        } else { print("view: no camp at the spawn \(vg.player.pos)") }
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
    }
    // --scene meetground (P387): stone, planks, lamps and chests placed on the ground ahead (the ground rises to meet
    // them, World.meetGround), then things in a section's first row over ground in the section below (GroundMeetTests.swift);
    // --meetcheck prints the gap under each.
    if arg("--scene") == "meetground" {
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        let blocks = World.meetScene(vg, yaw: yaw), low = World.lowRowScene(vg)
        print("view: \(blocks.count) blocks placed, \(low.count) things in a first row")
        let px = Int(floor(vg.player.pos.x)), pz = Int(floor(vg.player.pos.z)), py = Int(floor(vg.player.pos.y))
        vw.remeshArea(x0: px - 20, z0: pz - 20, x1: px + 20, z1: pz + 20, y0: py - 48, y1: py + 8)
        if CommandLine.arguments.contains("--meetcheck") {
            print(World.meetCheck(vw, blocks))
            print(GroundDrape.check(vw, low))
        }
    }
    // --scene fire (P373 a): fire on netherrack and grass, a campfire and a soul fire on a lawn, seen from --dist (6).
    if arg("--scene") == "fire" {
        let bx = Int(floor(at[0])), by = Int(floor(at[1])), bz = Int(floor(at[2]))
        for x in (bx - 5)...(bx + 5) { for z in (bz - 8)...(bz + 2) {
            vw.setBlock(x, by, z, Blocks.id("grass_block"))
            for y in (by + 1)...(by + 5) { vw.setBlock(x, y, z, AIR) }
        } }
        vw.setBlock(bx - 2, by, bz - 4, Blocks.id("netherrack")); vw.setBlock(bx - 2, by + 1, bz - 4, Blocks.id("fire"))
        vw.setBlock(bx - 1, by, bz - 4, Blocks.id("netherrack")); vw.setBlock(bx - 1, by + 1, bz - 4, Blocks.id("fire"))
        vw.setBlock(bx + 1, by + 1, bz - 4, Blocks.id("campfire"))
        if Blocks.has("soul_fire") { vw.setBlock(bx + 3, by, bz - 4, Blocks.id("soul_sand")); vw.setBlock(bx + 3, by + 1, bz - 4, Blocks.id("soul_fire")) }
        let dist = Float(arg("--dist") ?? "") ?? 6
        vg.player.pos = V3(Float(bx) + 0.5, Float(by + 1), Float(bz - 4) + dist); vg.player.vel = .zero
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
    }
    // --mob KEY[,KEY...]: those mobs side by side --mobdist blocks ahead (default 3), facing the camera (model checks,
    // P185); --aggro shows them hostile.
    if let ks = arg("--mob") {
        let ahead = V3(-sinf(yaw), 0, -cosf(yaw)), right = V3(cosf(yaw), 0, -sinf(yaw))
        let keys = ks.split(separator: ",").map(String.init)
        let d = Float(arg("--mobdist") ?? "") ?? 3
        for (i, k) in keys.enumerated() {
            guard let kind = MobKind.named(k) else { continue }
            let off = (Float(i) - Float(keys.count - 1) / 2) * 1.6
            let at = vg.player.pos + ahead * d + right * off
            let m = Mob(kind, at: V3(at.x, Float(vw.topY(Int(floor(at.x)), Int(floor(at.z))) + 1), at.z))
            m.yaw = yaw + .pi + (Float(arg("--mobyaw") ?? "") ?? 0) * .pi / 180     // --mobyaw DEG: turned (a profile at 90)
            if let c = Float(arg("--mobclock") ?? "") { m.callTimer = c }               // --mobclock S: the call clock (P295 idles)
            m.aggro = CommandLine.arguments.contains("--aggro")
            if CommandLine.arguments.contains("--aim") { m.aimHold = 1 }              // --aim: archers drawn on the camera (P444)
            if let s = Int(arg("--mobseed") ?? "") { m.coatSeed = UInt32(truncatingIfNeeded: s + i * 7919) }   // --mobseed N: their looks
            m.persistent = true
            if CommandLine.arguments.contains("--boreal") && kind.ashVehicle { m.borealSetup() }     // --boreal: P460's winter vehicles
            vg.mobs.mobs.append(m)
        }
        vg.mobs.rebuildIndex()
    }
    // --scene shapes: the realistic world's shape classes side by side on a lawn in the air at --at (organic objects,
    // cut timber, a log wall, a post), seen from --dist blocks off (8).
    if arg("--scene") == "shapes" {
        let bx = Int(floor(at[0])), by = Int(floor(at[1])), bz = Int(floor(at[2]))
        for x in (bx - 9)...(bx + 9) { for z in (bz - 8)...(bz + 3) {
            vw.setBlock(x, by, z, Blocks.id("grass_block"))
            for y in (by + 1)...(by + 6) { vw.setBlock(x, y, z, AIR) }
        } }
        func put(_ x: Int, _ y: Int, _ z: Int, _ k: String) { if Blocks.has(k) { vw.setBlock(bx + x, by + y, bz + z, Blocks.id(k)) } }
        put(-7, 1, -2, "pumpkin"); put(-5, 1, -1, "carved_pumpkin[south]"); put(-3, 1, -2, "melon"); put(-6, 1, -4, "jack_o_lantern[south]")
        put(-1, 1, -2, "hay_block"); put(-1, 2, -2, "hay_block"); put(0, 1, -2, "hay_block[x]"); put(1, 1, -2, "hay_block[x]")
        for x in 3...5 { for z in -5...(-3) { put(x, 4, z, "red_mushroom_block") } }
        for y in 1...3 { put(4, y, -4, "mushroom_stem") }
        put(7, 1, -2, "glowstone"); put(7, 2, -2, "glowstone"); put(8, 1, -2, "glowstone"); put(7, 1, -3, "nether_wart_block")
        put(6, 1, 0, "sponge"); put(-8, 1, 0, "dried_kelp_block")
        for x in -4...(-1) { put(x, 1, -7, "oak_log[x]"); put(x, 2, -7, "oak_log[x]") }      // a log wall
        put(0, 1, -7, "spruce_log"); put(0, 2, -7, "spruce_log")                            // a post
        put(2, 1, -6, "oak_log")                                                            // a stump
        for x in -8...(-6) { for y in 1...2 { put(x, y, -6, "bricks") } }; put(-8, 3, -6, "bricks")   // built blocks
        for y in 1...3 { put(5, y, -6, "oak_planks") }; put(6, 1, -6, "stone_bricks"); put(8, 1, -5, "iron_block")
        let dist = Float(arg("--dist") ?? "") ?? 8
        vg.player.pos = V3(Float(bx) + 0.5 + (Float(arg("--dx") ?? "") ?? 0), Float(by + 2), Float(bz - 2) + dist); vg.player.vel = .zero
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        vw.remeshArea(x0: bx - 12, z0: bz - 12, x1: bx + 12, z1: bz + 6, y0: by - 4, y1: by + 8)
    }
    // --scene damage: the realistic world's blows at --at (with --smooth): craters in a stone wall (one hit seven times),
    // bullet holes in bricks, a pit in the ground, chips and a broken block's pieces simulated for --settle seconds
    // (default 0.5: some still in the air).
    if arg("--scene") == "damage" {
        let bx = Int(floor(at[0])), by = Int(floor(at[1])), bz = Int(floor(at[2]))
        for x in (bx - 9)...(bx + 9) { for z in (bz - 8)...(bz + 3) {
            vw.setBlock(x, by, z, Blocks.id("grass_block"))
            for y in (by + 1)...(by + 6) { vw.setBlock(x, y, z, AIR) }
        } }
        let wz = bz - 6
        for x in -6...(-2) { for y in 1...3 { vw.setBlock(bx + x, by + y, wz, STONE) } }
        for x in 1...4 { for y in 1...3 { vw.setBlock(bx + x, by + y, wz, Blocks.id("bricks")) } }
        func bite(_ x: Int, _ y: Int, _ z: Int, _ c: V3, _ n: V3, _ r: Float, _ d: Float, _ k: UInt32) {
            vw.addBite(IVec3(bx + x, by + y, z), at: V3(Float(bx + x), Float(by + y), Float(z)) + c, axis: n, radius: r, depth: d, seed: hash3(x, y, z, k), sync: false)
        }
        let front = V3(0, 0, 1)
        for lv in 1...7 { bite(-4, 2, wz, V3(0.5, 0.45, 1), front, 0.22 + 0.025 * Float(lv), 0.1, UInt32(lv)) }   // mined almost through
        for lv in 1...3 { bite(-2, 1, wz, V3(0.7, 0.6, 1), front, 0.25, 0.1, UInt32(10 + lv)) }                // started
        bite(-6, 3, wz, V3(0.95, 0.3, 1), front, 0.3, 0.14, 21); bite(-5, 3, wz, V3(0.05, 0.3, 1), front, 0.3, 0.14, 22)  // across a seam
        var k: UInt32 = 40
        for (x, y) in [(1, 1), (1, 2), (2, 2), (2, 3), (3, 1), (3, 2), (4, 3), (4, 1)] {                     // a burst of rounds
            for _ in 0..<2 { k += 1; let h = hash3(x, y, Int(k), 7); bite(x, y, wz, V3(0.2 + 0.6 * Float(h & 255) / 255, 0.2 + 0.6 * Float((h >> 8) & 255) / 255, 1), front, 0.08, 0.06, k) }
        }
        for lv in 1...5 { bite(0, 0, bz - 3, V3(0.5, 1, 0.5), V3(0, 1, 0.3), 0.24 + 0.03 * Float(lv), 0.1, UInt32(60 + lv)) }   // a pit in the turf
        let settle = Float(arg("--settle") ?? "") ?? 0.5
        vg.debris.shatter(STONE, cell: IVec3(bx - 3, by + 1, wz + 1), impact: V3(Float(bx - 3) + 0.5, Float(by + 1) + 0.6, Float(wz + 2)),
                          direction: V3(0, 0, -1), count: 6, speed: 1.2, seed: 99)
        for i in 0..<4 {
            let c = V3(Float(bx - 4) + 0.5, Float(by + 2) + 0.45, Float(wz + 1))
            vg.debris.chips(STONE, cell: IVec3(bx - 4, by + 2, wz), at: c, normal: front, blow: V3(0, 0, -1), radius: 0.26, seed: UInt32(200 + i))
        }
        vg.debris.shatter(Blocks.id("bricks"), cell: IVec3(bx + 2, by + 4, wz), impact: V3(Float(bx + 2) + 0.5, Float(by + 4) + 0.5, Float(wz) + 0.5),
                          direction: V3(0, 1, 1), count: 8, speed: 4, seed: 7, crowding: 0.3)
        var t: Float = 0, worst = 0.0, sum = 0.0, n = 0
        while t < settle {
            let t0 = CFAbsoluteTimeGetCurrent()
            vg.debris.tick(1 / 72, world: vw); t += 1 / 72
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            worst = max(worst, ms); sum += ms; n += 1
        }
        print(String(format: "view: %d debris pieces after %.1f s, step %.3f ms mean, %.3f ms worst", vg.debris.count, settle, sum / Double(max(1, n)), worst))
        let st = vg.debris.bodies.stats
        print("view: debris last step: awake \(st.awake), substeps \(st.substeps), ground queries \(st.groundQueries), fixed contacts \(st.fixedContacts), pairs \(st.pairs), iterations \(st.iterations)")
        let dist = Float(arg("--dist") ?? "") ?? 7
        vg.player.pos = V3(Float(bx) + 0.5 + (Float(arg("--dx") ?? "") ?? 0), Float(by + 1), Float(bz - 2) + dist); vg.player.vel = .zero
        _ = vw.loadSync(center: vg.player.pos, radius: vw.renderDistance)
        vw.remeshArea(x0: bx - 12, z0: bz - 12, x1: bx + 12, z1: bz + 6, y0: by - 4, y1: by + 8)
    }
    // --scene rubble: on the natural ground 4 blocks ahead (with --find/--up), a block of the ground there mined from above
    // (a bowl dug along the look) and two blocks' worth of broken pieces dropped onto the slope, settled for --settle s
    // (default 4): do they lie on the drawn surface?
    if arg("--scene") == "rubble" {
        let ahead = V3(-sinf(yaw), 0, -cosf(yaw))
        let gx = Int(floor(vg.player.pos.x + ahead.x * 4)), gz = Int(floor(vg.player.pos.z + ahead.z * 4))
        var gy = Int(vg.player.pos.y) + 6
        while gy > 1 && !Blocks.opaque[Int(vw.block(gx, gy, gz))] { gy -= 1 }
        let b = vw.block(gx, gy, gz)
        let look = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        for lv in 1...6 {
            vw.addBite(IVec3(gx, gy, gz), at: V3(Float(gx) + 0.5, Float(gy) + 1, Float(gz) + 0.5), axis: -look,
                       radius: 0.22 + 0.025 * Float(lv), depth: 0.1, seed: UInt32(lv), sync: false)
        }
        for (k, dx) in [-1, 1].enumerated() {
            let c = IVec3(gx + dx, gy + 2, gz)
            vg.debris.shatter(b, cell: c, impact: V3(Float(c.x) + 0.5, Float(c.y) + 1, Float(c.z) + 0.5), direction: V3(0, -1, 0),
                              count: 6, speed: 1.2, seed: UInt32(31 + k))
        }
        let settle = Float(arg("--settle") ?? "") ?? 4
        var t: Float = 0
        while t < settle { vg.debris.tick(1 / 72, world: vw); t += 1 / 72 }
        print("view: rubble on \(Blocks.key(b)) at \(gx) \(gy) \(gz), \(vg.debris.count) pieces")
        vw.remeshArea(x0: gx - 3, z0: gz - 3, x1: gx + 3, z1: gz + 3, y0: gy - 3, y1: gy + 3)
    }
    // --scene ragdoll [--mobs K,K,..] [--mobdist D]: creatures in a row D blocks ahead (default 5) killed by a blow from
    // the camera, falling as ragdolls (realistic world: with --smooth), settled for --settle s (default 3).
    if arg("--scene") == "ragdoll" {
        let ahead = V3(-sinf(yaw), 0, -cosf(yaw)), right = V3(cosf(yaw), 0, -sinf(yaw))
        let keys = (arg("--mobs") ?? "zombie,cow,villager,spider,chicken,skeleton,pig,wolf").split(separator: ",").map(String.init)
        let d = Float(arg("--mobdist") ?? "") ?? 5
        for (i, k) in keys.enumerated() {
            guard let kind = MobKind.named(k) else { print("view: no mob \(k)"); continue }
            let off = (Float(i) - Float(keys.count - 1) / 2) * 1.8
            let at = vg.player.pos + ahead * d + right * off
            let bx = Int(floor(at.x)), bz = Int(floor(at.z))
            var gy = vw.topY(bx, bz)                                  // the ground, not a tree crown
            while gy > 1 && !(Blocks.opaque[Int(vw.block(bx, gy, bz))] && SmoothTerrain.natural[Int(vw.block(bx, gy, bz))]) { gy -= 1 }
            let m = Mob(kind, at: V3(at.x, Float(gy + 1), at.z))
            m.yaw = yaw + .pi + Float(i) * 0.9
            m.viewDY = vw.smoothGroundOffset(m.pos)
            m.vel = ahead * 5.5 + V3(0, 5, 0)
            m.health = 0
            vg.mobs.addCorpse(m, vg)
        }
        let settle = Float(arg("--settle") ?? "") ?? 3
        let rw = vg.debris.ragdolls
        var t: Float = 0, steps = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        while t < settle { vg.mobs.corpseTick(1 / 72, vg); vg.debris.tick(1 / 72, world: vw); t += 1 / 72; steps += 1 }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / Double(max(1, steps))
        for c in vg.mobs.corpses {
            guard let r = c.ragdoll else { print("view: \(c.kind) no ragdoll"); continue }
            let p = rw.pose(r.id, 0).position
            print("view: \(c.kind) \(rw.boneCount(r.id)) bones, \(rw.isAwake(r.id) ? "awake" : "asleep"), body at "
                  + String(format: "%.2f %.2f %.2f, joint gap %.3f", p.x, p.y, p.z, rw.jointGap(r.id)))
        }
        print(String(format: "view: ragdolls %d live, %d awake, %.3f ms a step (%d steps)", rw.liveCount, rw.awakeCount, ms, steps))
    }
    // --drop KEY: a dropped stack of that item 1.6 blocks ahead, floating at eye height (how drops draw, P47).
    if let k = arg("--drop"), Items.has(k) {
        let ahead = V3(-sinf(yaw), 0, -cosf(yaw))
        let e = ItemEntity(ItemStack(Items.id(k), 1), at: vg.player.eye + ahead * 1.6 - V3(0, 0.3, 0), vel: .zero, delay: 9)
        vg.drops.items.append(e)
    }
    do {
        // --w/--h/--fov: P375's headset-resolution shots (Quest 3: 2064 x 2208 an eye, about 104 degrees across).
        let vwid = Int(arg("--w") ?? "") ?? 640, vhei = Int(arg("--h") ?? "") ?? 640, vfov = Float(arg("--fov") ?? "") ?? 90
        // --pixelpair (P375): the same frame with the full ground grid everywhere (OUT-full.png) and with far sections
        // drawing their merged ground (OUT), and how many pixels differ.
        // --turnshots N (P385 step 5): a 360 degree head turn in N frames, one shot a frame (OUT-000.png ...).
        // --scene objects (P389): the ten object kinds struck where they stand, shots OUT-<kind>-1..4.png (ObjectBreakTests).
        if arg("--scene") == "objects" {
            let rig = try RenderTest.ShotRig(game: vg, ctx: ctx, width: vwid, height: vhei, fovDeg: vfov)
            let base = out.hasSuffix(".png") ? String(out.dropLast(4)) : out
            print(ObjectBreakTests.run(vg, base: base) { path, eye, y, p in
                do { try rig.shoot(path, eye: eye, yaw: y, pitch: p) } catch { print("objects: shot \(path) failed: \(error)") }
            })
            exit(0)
        }
        if let n = Int(arg("--turnshots") ?? ""), n > 0 {
            try RenderTest.renderTurn(game: vg, ctx: ctx, path: out, width: vwid, height: vhei, yaw: yaw, pitch: pitch, fovDeg: vfov, frames: n)
            exit(0)
        }
        var fullRGBA: [UInt8] = []
        if CommandLine.arguments.contains("--pixelpair") {
            SceneRenderer.drawMerged = false
            try RenderTest.render(game: vg, ctx: ctx, path: out.replacingOccurrences(of: ".png", with: "-full.png"), width: vwid, height: vhei,
                                  yaw: yaw, pitch: pitch, fovDeg: vfov)
            fullRGBA = RenderTest.lastRGBA
            SceneRenderer.drawMerged = true
        }
        try RenderTest.render(game: vg, ctx: ctx, path: out, width: vwid, height: vhei, yaw: yaw, pitch: pitch, fovDeg: vfov)
        print("view: " + RenderTest.lastBreakdown.replacingOccurrences(of: "\n", with: "\nview: "))      // P403 step 2
        if !fullRGBA.isEmpty && fullRGBA.count == RenderTest.lastRGBA.count {
            let b = RenderTest.lastRGBA
            var over8 = 0, over32 = 0, sum = 0
            for i in stride(from: 0, to: b.count, by: 4) {
                let d = max(abs(Int(b[i]) - Int(fullRGBA[i])), abs(Int(b[i + 1]) - Int(fullRGBA[i + 1])), abs(Int(b[i + 2]) - Int(fullRGBA[i + 2])))
                sum += d; if d > 8 { over8 += 1 }; if d > 32 { over32 += 1 }
            }
            let n = b.count / 4
            print(String(format: "view: pixelpair %d pixels, %d differ by more than 8 of 255 (%.3f%%), %d by more than 32 (%.3f%%), mean difference %.3f",
                         n, over8, Double(over8) * 100 / Double(n), over32, Double(over32) * 100 / Double(n), Double(sum) / Double(n)))
        }
        if GroundMerge.merged > 0 { print("view: \(GroundMerge.replaced) ground quads merged into \(GroundMerge.merged) for far sections (P375)") }
        if AdaptiveGround.trisIn > 0 { print("view: adaptive ground (P381) \(AdaptiveGround.trisIn) triangles -> \(AdaptiveGround.trisOut) near (tol \(AdaptiveGround.tolerance)); far copy \(AdaptiveGround.farIn) quads -> \(AdaptiveGround.farOut); ground positions \(AdaptiveGround.positions), \(AdaptiveGround.splitPositions) drawn with 2+ vertices (P383)") }
        if Mesher.mergedWater > 0 { print("view: \(Mesher.mergedWater) far water cells drawn in merged quads (P184)") }
        print("view: wrote \(out)"); exit(0)
    } catch { print("FAIL view: \(error)"); exit(1) }
}
// --notespots FILE.json (P377 step 2): the two field debug counters (PerfOverlay's third line: natural ground meshed as
// cubes, and ground cell reads a frame) at every spot of a list of voice-note positions ([{seed, dim, x, y, z, day,
// time}], tools: the notes' Position lines), each read in a field world of the note's seed with the player standing
// there for 36 frames (survival, on foot). Prints one line a spot and the totals; non-zero values are listed.
if let path = arg("--notespots") {
    struct Spot: Decodable { let seed: String; let dim: String; let x: Float; let y: Float; let z: Float; let day: String; let time: String }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let spots = try? JSONDecoder().decode([Spot].self, from: data) else {
        print("notespots: can't read \(path)"); exit(1)
    }
    World.lodNear = 99; World.leafNear = 99; World.deterministic = true
    FieldTerrain.newWorlds = true
    StructureCache.traceKinds = true                     // (natural rock a structure built, to tell buildings from ground)
    var cubesTotal = 0, readsTotal = 0, bad: [String] = []
    var cur: (key: String, w: World, g: Game)? = nil
    let limit = Int(arg("--limit") ?? "") ?? Int.max
    for (n, sp) in spots.prefix(limit).enumerated() {
        let key = sp.seed + "/" + sp.dim
        if cur?.key != key {
            let dim: Dim = sp.dim == "Hell" ? .deep : (sp.dim == "The Emberdeep" ? .nether : (sp.dim == "The Hollow" ? .end : .overworld))
            FieldTerrain.keptBuilt = [:]; StructureCache.kinds = [:]
            let w = World(seed: UInt64(sp.seed) ?? 0, device: device, save: nil, dim: dim)
            w.makeFieldWorld()
            w.renderDistance = 3; w.activeDistance = 3
            let g = Game(world: w, save: nil, persistent: false)
            g.smoothTerrain = true
            SmoothTerrain.use(world: true, world: w)
            g.survival = true; g.paused = false; g.input.captured = true
            cur = (key, w, g)
        }
        let (_, w, g) = cur!
        g.player.flying = false
        g.player.pos = V3(sp.x, sp.y + Float(YOFF), sp.z)
        g.player.vel = .zero
        _ = w.loadSync(center: g.player.pos, radius: 3)
        for _ in 0..<4 { g.tick(1.0 / 72) }                          // (meshes in)
        g.player.pos = V3(sp.x, sp.y + Float(YOFF), sp.z); g.player.vel = .zero
        BlockStore.countReads = true; BlockStore.groundReads = 0
        BlockStore.traceReads = CommandLine.arguments.contains("--trace")
        let frames = 36
        for _ in 0..<frames { g.tick(1.0 / 72) }
        BlockStore.countReads = false
        BlockStore.traceReads = false
        let reads = BlockStore.groundReads / frames
        var cubes = 0
        let pcx = floorDiv(Int(floor(sp.x)), CS), pcz = floorDiv(Int(floor(sp.z)), CS)
        for dz in -2...2 { for dx in -2...2 {
            guard let c = w.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] else { continue }
            for s in c.sections { cubes += s.naturalCubes }
        } }
        // Ground left in the built layer that no structure built (any is a generation path that kept ground as cells):
        // counted as ground drawn as cubes too.
        var unbuilt = 0
        for dz in -2...2 { for dx in -2...2 {
            let k = ChunkKey(x: pcx + dx, z: pcz + dz)
            guard let c = w.chunks[k] else { continue }
            var g = 0
            for i in 0..<(CSQ * CH) where FieldMat.index[Int(c.blocks.raw(i))] != 0 { g += 1 }
            unbuilt += max(0, g - (FieldTerrain.keptBuilt[k] ?? 0))
        } }
        cubes += unbuilt
        // (--trace: which natural blocks the built layer holds here)
        if CommandLine.arguments.contains("--trace") {
            var keys: [String: Int] = [:], ground = 0, kept = 0
            var kinds = Set<String>()
            for dz in -2...2 { for dx in -2...2 {
                let k = ChunkKey(x: pcx + dx, z: pcz + dz)
                guard let c = w.chunks[k] else { continue }
                for i in 0..<(CSQ * CH) {
                    let b = c.blocks.raw(i)
                    if b != AIR && SmoothTerrain.natural[Int(b)] { keys[Blocks.key(b), default: 0] += 1 }
                    if FieldMat.index[Int(b)] != 0 { ground += 1 }
                }
                kept += FieldTerrain.keptBuilt[k] ?? 0
                kinds.formUnion(StructureCache.kinds[k] ?? [])
            } }
            print("notespots   built-layer natural blocks: " + keys.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            print("notespots   ground materials in the built layer \(ground), kept there by a structure's mark \(kept) (structures: \(kinds.sorted().joined(separator: " ")))")
        }
        cubesTotal += cubes; readsTotal += reads
        let line = String(format: "notespots %3d %@ %@ %@ %@ at %.1f %.1f %.1f: ground as cubes %d, ground cell reads %d/frame",
                          n, sp.day, sp.time, sp.dim, sp.seed, sp.x, sp.y, sp.z, cubes, reads)
        print(line)
        if cubes > 0 || reads > 0 { bad.append(line) }
    }
    print("notespots: \(min(limit, spots.count)) spots, ground as cubes total \(cubesTotal), ground cell reads total \(readsTotal)/frame; \(bad.count) spots non-zero")
    for b in bad { print("  NONZERO " + b) }
    for (k, v) in BlockStore.readers.sorted(by: { $0.value > $1.value }).prefix(80) { print("notespots reader \(v * 64): \(k)") }
    exit(bad.isEmpty ? 0 : 2)
}
// --structcheck [--seeds A,B --per N --kinds K,... --dims D --strict --out FILE]: the structure walkability check
// (Sources/StructCheck.swift) on the Linux host, as the Mac's `--structcheck` runs it.
if CommandLine.arguments.contains("--structcheck") { exit(StructCheck.run(device: device)) }
// --gencheck [--seeds A,B --areas N]: the generated-world defect scan (Sources/GenCheck.swift: floating trunks and
// plants, leaks, ...), as the Mac's `--gencheck` runs it.
if CommandLine.arguments.contains("--gencheck") { exit(GenCheck.run(device: device)) }
// --fieldsave (PG1 rewrite): a field world saved and opened again keeps its ground cell for cell (density, material and
// the built layer) after a ball is carved out of it and another added near spawn.
if CommandLine.arguments.contains("--fieldsave") {
    FieldTerrain.newWorlds = true
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fieldsave-\(getpid())")
    try? FileManager.default.removeItem(at: dir)
    let w1 = World(seed: 4242, device: device, save: SaveManager(dir: dir))
    w1.makeFieldWorld()
    _ = w1.loadSync(center: V3(8, 150, 8), radius: 2)
    func groundTop(_ x: Int, _ z: Int) -> Int {
        var y = CH - 1
        while y > 1 && !(w1.chunkAt(x, z)?.blocks.ground(Chunk.index(mod(x, CS), y, mod(z, CS))) ?? false) { y -= 1 }
        return y
    }
    let dug = w1.fieldSphere(V3(8.5, Float(groundTop(8, 8)) + 0.5, 8.5), radius: 2.3, carve: true, material: nil)
    let added = w1.fieldSphere(V3(20.5, Float(groundTop(20, 8)) + 1.2, 8.5), radius: 1.8, carve: false, material: nil)
    w1.setBlock(14, w1.topY(14, 14) + 1, 14, Blocks.id("cobblestone"))
    w1.saveAll(); SaveIO.flush()
    let w2 = World(seed: 4242, device: device, save: SaveManager(dir: dir))
    _ = w2.loadSync(center: V3(8, 150, 8), radius: 2)
    var cells = 0, bad = 0, chunks = 0
    for (k, c1) in w1.chunks where c1.modified {      // (the saved ones; the rest generate again from the seed)
        guard let c2 = w2.chunks[k] else { continue }
        chunks += 1
        for i in 0..<(CSQ * CH) {
            cells += 1
            let d1 = c1.blocks.density(i)
            if c1.blocks.raw(i) != c2.blocks.raw(i) || d1 != c2.blocks.density(i) || (d1 > 0 && c1.blocks.material(i) != c2.blocks.material(i)) {
                if bad < 6 {
                    print("fieldsave: differs at \(k.x * CS + i % CS) \(i / CSQ) \(k.z * CS + (i / CS) % CS) (saved \(c1.modified)): "
                          + "\(Blocks.key(c1.blocks.raw(i))) / \(Blocks.key(c2.blocks.raw(i))), density \(d1) / \(c2.blocks.density(i)), "
                          + "material \(c1.blocks.material(i)) / \(c2.blocks.material(i))")
                }
                bad += 1
            }
        }
    }
    print("fieldsave: field world \(w1.fieldTerrain) -> \(w2.fieldTerrain); \(dug.count) cells dug, \(added.count) added; \(chunks) saved chunks, \(cells) cells compared, \(bad) differ")
    try? FileManager.default.removeItem(at: dir)
    // A world saved before the field (no terrain-field.txt) opens as the block world it was, block for block.
    let dirB = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blocksave-\(getpid())")
    try? FileManager.default.removeItem(at: dirB)
    let b1 = World(seed: 4242, device: device, save: SaveManager(dir: dirB))
    _ = b1.loadSync(center: V3(8, 150, 8), radius: 2)
    b1.setBlock(14, b1.topY(14, 14) + 1, 14, Blocks.id("cobblestone"))
    b1.setBlock(9, b1.topY(9, 9), 9, AIR)
    b1.saveAll(); SaveIO.flush()
    let b2 = World(seed: 4242, device: device, save: SaveManager(dir: dirB))
    _ = b2.loadSync(center: V3(8, 150, 8), radius: 2)
    var bCells = 0, bBad = 0, bField = 0
    for (k, c1) in b1.chunks {
        guard let c2 = b2.chunks[k] else { continue }
        if c1.blocks.isField || c2.blocks.isField { bField += 1 }
        for i in 0..<(CSQ * CH) { bCells += 1; if c1.blocks[i] != c2.blocks[i] { bBad += 1 } }
    }
    print("fieldsave: block world \(b1.fieldTerrain) -> \(b2.fieldTerrain); \(bCells) cells compared, \(bBad) differ, \(bField) chunks with a field")
    try? FileManager.default.removeItem(at: dirB)
    exit(bad == 0 && w2.fieldTerrain && chunks > 0 && dug.count > 0 && added.count > 0 && !b1.fieldTerrain && !b2.fieldTerrain
         && bBad == 0 && bField == 0 && bCells > 0 ? 0 : 1)
}
// --playthrough [--only overworld,emberdeep,stronghold,end,blight] [--seed N]: the Mac's scripted full-game run
// (Sources/Playthrough.swift), so cloud threads can run it too.
if CommandLine.arguments.contains("--playthrough") { exit(Playthrough.run()) }
// --hellcheck: P292, hell made our own (Sources/HellCheck.swift): its fortress, roost, lands, spawns and old saves.
if CommandLine.arguments.contains("--hellcheck") { exit(HellCheck.run()) }
// --modelcheck: P295, the rebuilt people and animals (Sources/ModelCheck.swift): detail levels, feet, grazing, heads.
if CommandLine.arguments.contains("--modelcheck") { exit(ModelCheck.run()) }
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
// --loadtest: P388 weight and bond strength (Sources/StructureTests.swift): the test builds, then a house with the
// titanium pile that brought the test roof down, built through World.setBlock and left to the game's ticks (the queue checks it, it falls, what lands crushes).
if CommandLine.arguments.contains("--loadtest") {
    let b = IVec3(Int(spawn.x) + 6, 300, Int(spawn.z) + 6)
    print(Structure.loadTest(world, at: b))
    let h = IVec3(b.x, 330, b.z + 12)
    var built: [(IVec3, BlockID)] = []
    func put(_ x: Int, _ y: Int, _ z: Int, _ key: String) {
        let id = Blocks.id(key); world.setBlock(h.x + x, h.y + y, h.z + z, id)
        if y > 0 { built.append((IVec3(h.x + x, h.y + y, h.z + z), id)) }
    }
    for z in 0..<7 { for x in 0..<7 {
        put(x, 0, z, "bedrock")
        if x == 0 || x == 6 || z == 0 || z == 6 { for y in 1...3 { put(x, y, z, "oak_planks") } }
        put(x, 4, z, "oak_planks")
    } }
    for y in 5..<(5 + max(3, Structure.tiDownAt)) { for z in 2...4 { for x in 2...4 { put(x, y, z, "diamond_block") } } }
    game.player.pos = V3(Float(h.x) + 3, Float(h.y) + 1, Float(h.z) - 4); game.player.flying = true
    let t1 = CFAbsoluteTimeGetCurrent()
    for _ in 0..<720 { game.tick(1.0 / 72) }
    let left = built.filter { world.builtBlock($0.0.x, $0.0.y, $0.0.z) == $0.1 }.count
    print(String(format: "loadtest in play: %d checks (worst %.2f ms), %d blocks fell, %d crushed on landing, %d of %d built blocks still where they were built (10 s of ticks in %.1f s)",
                 Structure.checks, Structure.worstMs, Structure.fallen, Structure.crushed, left, built.count, CFAbsoluteTimeGetCurrent() - t1))
    exit(0)
}
// --loadcheck: P388 (5), every generated structure type's pieces checked whole (Sources/StructureTests.swift).
if CommandLine.arguments.contains("--loadcheck") { exit(Structure.loadCheck(device: device)) }
// --settletest: P380 ground and object physics in field worlds (Sources/GroundSettleTests.swift).
if CommandLine.arguments.contains("--settletest") {
    GroundSettleTests.run(game, check: check)
    print(failures == 0 ? "settle: all checks passed" : "settle: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --treesheet DIR (with --render X): P406's designed trees: the shape checks, then one contact sheet per species.
if let dir = arg("--treesheet"), let ctx = vkctx {
    TreeTest.run(check: check)
    do { try TreeShots.run(game: game, ctx: ctx, dir: dir, designs: true) } catch { print("FAIL treesheet: \(error)"); failures += 1 }
    print(failures == 0 ? "trees: all checks passed" : "trees: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --rail-only: C1 railways and trains (Sources/RailwayTests.swift).
if CommandLine.arguments.contains("--rail-only") {
    if !CommandLine.arguments.contains("--railride") { RailwayTests.run(game, check: check) }
    RailwayTests.ride(game, check: check)
    print(failures == 0 ? "rail: all checks passed" : "rail: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --horsecoats-only: G9 horse coats (quest/src/test/HorseCoatShots.swift); with --render X it renders the lineup and the
// rider's view through the Quest renderer (--horse-shots DIR keeps the PNGs).
if CommandLine.arguments.contains("--horsecoats-only") {
    if let ctx = vkctx {
        do { try HorseCoatShots.run(game: game, ctx: ctx, dir: arg("--horse-shots"), check: check) } catch { check(false, "horsecoats render: \(error)") }
    } else { HorseCoatShots.modelChecks(check) }
    print(failures == 0 ? "horsecoats: all checks passed" : "horsecoats: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --maingun-quick: just the Tidebreaker checks (Sources/MainGunTests.swift), without the run --maingun-only sits behind.
if CommandLine.arguments.contains("--maingun-quick") {
    MainGunTests.run(game, check, render: nil)
    print(failures == 0 ? "maingun: all checks passed" : "maingun: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --frigatecheck: P325, the Meridian frigate's interior, flight, main gun and crash from its helm (Sources/FrigateCheck.swift).
if CommandLine.arguments.contains("--checklist-only") {          // P399: the in-game playtest checklist page
    PlaytestChecklistCheck.run(game, check)
    print(failures == 0 ? "checklist: all checks passed" : "checklist: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--difficulty-only") {          // P358: hits to kill and a fight per level
    DifficultyCheck.run(game, check)
    print(failures == 0 ? "difficulty: all checks passed" : "difficulty: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--throw-only") {             // P371: thrown held things
    ThrownHeldCheck.run(game, check)
    print(failures == 0 ? "throw: all checks passed" : "throw: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--gunparts-only") {          // P372: emplacement gun parts and handles
    GunPartsCheck.run(game, check)
    print(failures == 0 ? "gunparts: all checks passed" : "gunparts: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--dropflight") {           // P461: a taken dropship lands, sprints and crushes
    DropFlightCheck.run(game, check)
    print(failures == 0 ? "dropflight: all checks passed" : "dropflight: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--brigandcheck") {         // P460: a Brigand takes pistol rounds
    BrigandRoundsCheck.run(game, check)
    print(failures == 0 ? "brigandcheck: all checks passed" : "brigandcheck: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--soldierrange") {         // P460: riflemen fire out to their gun's reach
    SoldierRangeCheck.run(game, check)
    print(failures == 0 ? "soldierrange: all checks passed" : "soldierrange: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--lavamelt") {         // P461: a hull in lava rides it and melts
    LavaMeltCheck.run(game, check)
    print(failures == 0 ? "lavamelt: all checks passed" : "lavamelt: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--droptroops") {           // P460: what a Capital Dropship's landed troops do
    DropTroopsCheck.run(game, check)
    print(failures == 0 ? "droptroops: all checks passed" : "droptroops: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--frigatedecks") {         // P450/P461: the Stormwarden Frigate's decks and stairs
    FrigateDecksCheck.run(check)
    print(failures == 0 ? "frigatedecks: all checks passed" : "frigatedecks: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--bigfight") {              // P450: the Reckoning's barrages, dropships and truce
    BigFightCheck.run(game, check)
    print(failures == 0 ? "bigfight: all checks passed" : "bigfight: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--sandbreak") {             // P462: dug beach sand stays ground
    SandBreakCheck.run(game, check)
    print(failures == 0 ? "sandbreak: all checks passed" : "sandbreak: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--cityfloat") {             // P462: Capital City's pillars on the ground
    CityFloatCheck.run(game, check)
    print(failures == 0 ? "cityfloat: all checks passed" : "cityfloat: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--fueldepot") {             // P461: dropship fuel cans and Fuel Depot bases
    FuelDepotCheck.run(game, check)
    print(failures == 0 ? "fueldepot: all checks passed" : "fueldepot: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--borealcars") {            // P460: a Boreal Station's own trucks and tank
    BorealCarsCheck.run(game, check)
    print(failures == 0 ? "borealcars: all checks passed" : "borealcars: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--shellthrough") {          // P464: his deck-gun shells into a frigate's side
    ShellThroughCheck.run(game, check)
    print(failures == 0 ? "shellthrough: all checks passed" : "shellthrough: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--huntcrawler") {          // P460: the Reckoning's Capital band brings a crawler
    HuntCrawlerCheck.run(game, check)
    print(failures == 0 ? "huntcrawler: all checks passed" : "huntcrawler: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--frigatecheck") {
    FrigateCheck.run(game, check)
    print(failures == 0 ? "frigate: all checks passed" : "frigate: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --ashfront: P326, the Ash Vault as the last war's front: its ground, sky, set pieces, fallen, bases, arms, old saves.
if CommandLine.arguments.contains("--ashfront") {
    AshFrontCheck.run(game, check)
    print(failures == 0 ? "ashfront: all checks passed" : "ashfront: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --rules-only: the Mac --rulescheck world rules (Sources/RulesCheck.swift) beside the questcheck player.
if CommandLine.arguments.contains("--rules-only") {
    let n = RulesCheck.run(game)
    print(n == 0 ? "rules: all checks passed" : "rules: \(n) FAILED"); exit(n == 0 ? 0 : 1)
}
// --trigger-only: the Mac --questbugs VR trigger spam check (Sources/TriggerSpamCheck.swift).
if CommandLine.arguments.contains("--trigger-only") {
    TriggerSpamCheck.run(game, check: check)
    print(failures == 0 ? "trigger: all checks passed" : "trigger: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --sizes-only: C13 town sizes (Sources/TownSizesTests.swift).
if CommandLine.arguments.contains("--sizes-only") {
    TownSizesTests.run(game, check: check)
    print(failures == 0 ? "sizes: all checks passed" : "sizes: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --mines-only: C12 mining towns (Sources/MiningTownsTests.swift).
if CommandLine.arguments.contains("--mines-only") {
    MiningTownsTests.run(game, check: check)
    print(failures == 0 ? "mines: all checks passed" : "mines: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --contracts-only: C11 jobs and contracts (Sources/ContractsTests.swift).
if CommandLine.arguments.contains("--contracts-only") {
    ContractsTests.run(game, check: check)
    print(failures == 0 ? "contracts: all checks passed" : "contracts: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --legends-only: C10 legendary weapons and armour (Sources/LegendariesTests.swift).
if CommandLine.arguments.contains("--legends-only") {
    LegendariesTests.run(game, check: check)
    print(failures == 0 ? "legends: all checks passed" : "legends: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --seasons-only: C9 seasons (Sources/SeasonsTests.swift).
if CommandLine.arguments.contains("--seasons-only") {
    SeasonsTests.run(game, check: check)
    print(failures == 0 ? "seasons: all checks passed" : "seasons: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --mind-only: C4 the villager mind interface (Sources/VillagerMindTests.swift).
if CommandLine.arguments.contains("--mind-only") {
    VillagerMindTests.run(game, check: check)
    print(failures == 0 ? "mind: all checks passed" : "mind: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --nation-only: C3 your own nation (Sources/NationTests.swift).
if CommandLine.arguments.contains("--nation-only") {
    NationTests.run(game, check: check)
    print(failures == 0 ? "nation: all checks passed" : "nation: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --towns-only: just the towns of people, law, honour and frontier town checks (Sources/TownTests.swift, HonourTests.swift).
if CommandLine.arguments.contains("--towns-only") {
    TownTests.run(game: game, makeWorld: { World(seed: seed, device: device, save: nil) }, check: check)
    print(failures == 0 ? "towns: all checks passed" : "towns: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --basetest-only [phase]: the Mac snap shard's citadel scenes (Sources/BaseTests.swift) at the citadel nearest spawn,
// as `--structure military_base --basetest patrol` frames it (cloud threads can see which citadel G12's rules leave).
if let i = CommandLine.arguments.firstIndex(of: "--basetest-only") {
    let phase = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : "patrol"
    var from = game.findSpawn(varied: false)               // the Mac snapshot's origin (reference shots keep it)
    if let j = CommandLine.arguments.firstIndex(of: "--from"), j + 1 < CommandLine.arguments.count {
        let xz = CommandLine.arguments[j + 1].split(separator: ",").compactMap { Float($0) }
        if xz.count == 2 { from = V3(xz[0], from.y, xz[1]) }    // --worldseed S --from X,Z: a playtest's citadel
    }
    if let s = world.gen.structures?.nearest("military_base", x: Int(from.x), z: Int(from.z), maxRegions: 6) {
        print("basetest: citadel at \(s.anchor.x) \(s.anchor.z)")
        game.player.pos = V3(Float(s.anchor.x), Float(s.anchor.y + 1), Float(s.anchor.z))
        _ = world.loadSync(center: game.player.pos, radius: 6)
        let ok = BaseTests.run(game: game, world: world, phase: phase)
        print(ok ? "basetest: all checks passed" : "basetest: FAILED"); exit(ok ? 0 : 1)
    }
    print("basetest: no citadel within 6 regions"); exit(1)
}
// --factions-structures-only: the Mac --questbugs checks on where Capital cities and citadels stand from the spawn
// (FactionTests.structures: findable, never at the spawn, the structure guard).
if CommandLine.arguments.contains("--factions-structures-only") {
    FactionTests.structures(check)
    print(failures == 0 ? "factions structures: all checks passed" : "factions structures: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --p12pm-only [P1xx]: the Oct 12 afternoon playtest fixes (Sources/PlaytestOct12PMTests.swift, backlog P107-P139).
if let i = CommandLine.arguments.firstIndex(of: "--p12pm-only") {
    let only = i + 1 < CommandLine.arguments.count && CommandLine.arguments[i + 1].hasPrefix("P") ? CommandLine.arguments[i + 1] : nil
    PlaytestOct12PMTests.run(game, only: only, check: check)
    print(failures == 0 ? "p12pm: all checks passed" : "p12pm: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --p11-only: the Oct 11 Quest playtest fixes (Sources/PlaytestOct11Tests.swift, backlog P1-P38).
if CommandLine.arguments.contains("--p11-only") {
    PlaytestOct11Tests.run(game, check)
    print(failures == 0 ? "p11: all checks passed" : "p11: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --p12-only: the Oct 12 AM Quest playtest fixes (Sources/PlaytestOct12Tests.swift, backlog P68-P97).
if CommandLine.arguments.contains("--p12-only") {
    PlaytestOct12Tests.run(game, check)
    print(failures == 0 ? "p12: all checks passed" : "p12: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --smooth2-only: polygon terrain round 2 (Sources/SmoothRound2Tests.swift, backlog P106).
// --shapecensus: the realistic world's shape class of every block (Sources/ShapeClass.swift).
if CommandLine.arguments.contains("--shapecensus") { print(ShapeClass.census()); exit(0) }
if CommandLine.arguments.contains("--smooth2-only") {
    SmoothRound2Tests.run(game, check: check)
    print(failures == 0 ? "smooth2: all checks passed" : "smooth2: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --greywall-only: the Greywall Command bases (Sources/GreywallTests.swift, backlog A1).
if CommandLine.arguments.contains("--navy-only") {
    NavyTests.run(game: game, check: check)
    print(failures == 0 ? "navy: all checks passed" : "navy: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --liberation-only: outlaw camps freed, their trader and fast travel (Sources/LiberationTests.swift, backlog O1).
if CommandLine.arguments.contains("--liberation-only") {
    LiberationTests.run(game, check: check)
    print(failures == 0 ? "liberation: all checks passed" : "liberation: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --companions-only: hired companions (Sources/CompanionTests.swift, backlog O2).
if CommandLine.arguments.contains("--companions-only") {
    CompanionTests.run(game, check: check)
    print(failures == 0 ? "companions: all checks passed" : "companions: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --factionrep-only: faction reputation (Sources/FactionRepTests.swift, backlog O3).
if CommandLine.arguments.contains("--factionrep-only") {
    FactionRepTests.run(game, check: check)
    print(failures == 0 ? "factionrep: all checks passed" : "factionrep: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --repair-only: repairs and gun grades (Sources/RepairTests.swift, backlog O4).
if CommandLine.arguments.contains("--repair-only") {
    RepairTests.run(game, check: check)
    print(failures == 0 ? "repair: all checks passed" : "repair: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --raids-only: faction raids (Sources/FactionRaidsTests.swift, backlog O5).
if CommandLine.arguments.contains("--raids-only") {
    FactionRaidsTests.run(game, check: check)
    print(failures == 0 ? "raids: all checks passed" : "raids: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --trophies-only: trophy room and museum (Sources/TrophiesTests.swift, backlog O6).
if CommandLine.arguments.contains("--trophies-only") {
    TrophiesTests.run(game, check: check)
    print(failures == 0 ? "trophies: all checks passed" : "trophies: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --weather-only: weather that matters (Sources/WeatherWarTests.swift, backlog O7).
if CommandLine.arguments.contains("--weather-only") {
    WeatherWarTests.run(game, check: check)
    print(failures == 0 ? "weather: all checks passed" : "weather: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --oct13-only: Oct 13 playtest items (Sources/PlaytestOct13Tests.swift, backlog P146-P174).
if CommandLine.arguments.contains("--oct13-only") {
    PlaytestOct13Tests.run(game, check: check)
    print(failures == 0 ? "oct13: all checks passed" : "oct13: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --oct14-only [P2xx]: Oct 14 midday playtest items (Sources/PlaytestOct14Tests.swift, backlog P250-P265); with
// --render X, frames of what an item builds land next to X.
if let i = CommandLine.arguments.firstIndex(of: "--oct14-only") {
    let next = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : ""
    let shotDir = renderPath.flatMap { $0.isEmpty ? nil : ($0 as NSString).deletingLastPathComponent }
    let render: ((String, V3, Float, Float) -> Void)? = shotDir.flatMap { dir in vkctx.map { ctx in { name, at, yaw, pitch in
        let was = game.player.pos
        game.player.pos = at - V3(0, game.player.eyeHeight, 0)
        _ = game.world.loadSync(center: at, radius: 3)
        do {
            try RenderTest.render(game: game, ctx: ctx, path: (dir.isEmpty ? "." : dir) + "/\(name).png", yaw: yaw, pitch: pitch)
            print("render: \(dir)/\(name).png")
        } catch { check(false, "oct14 render \(name): \(error)") }
        game.player.pos = was
    } } }
    PlaytestOct14Tests.run(game, only: next.hasPrefix("P") ? next : nil, render: render, check: check)
    print(failures == 0 ? "oct14: all checks passed" : "oct14: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --water-only: P44 surface water in new worlds (Sources/NetTests.swift WaterTests).
if CommandLine.arguments.contains("--water-only") {
    WaterTests.run(check: check)
    print(failures == 0 ? "water: all checks passed" : "water: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --net-only: C14 Play Together over loopback (Sources/NetTests.swift).
if CommandLine.arguments.contains("--net-only") {
    NetTests.run(game, device: device, check: check)
    print(failures == 0 ? "net: all checks passed" : "net: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--tower-only") { PlaytestOct13Tests.towers(game); exit(0) }
// --freeze-only: the P169 gallop probe (Sources/PlaytestOct13Tests.swift).
if CommandLine.arguments.contains("--freeze-only") {
    PlaytestOct13Tests.freezes(game, check: check)
    print(failures == 0 ? "freeze: all checks passed" : "freeze: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --batch-only: batched terrain draws (P146): the same frame drawn per section and batched: far fewer draw calls,
// the same quads and the same picture.
if CommandLine.arguments.contains("--batch-only"), let ctx = vkctx {
    var runs: [(Int, Int, Double, [UInt8])] = []
    for on in [false, true] {
        SceneRenderer.batchDraws = on
        do { try RenderTest.render(game: game, ctx: ctx, path: tmp.appendingPathComponent("batch_\(on).png").path, width: 320, height: 320, yaw: 0.6, pitch: -0.25) }
        catch { check(false, "batch render: \(error)") }
        runs.append((RenderTest.lastStats.draws, RenderTest.drawnQuads, RenderTest.recordMs, RenderTest.lastRGBA))
    }
    let a = runs[0].3, b = runs[1].3
    let differ = a.count == b.count ? zip(a, b).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 6 ? 1 : 0) } : -1
    check(runs[1].0 * 3 < runs[0].0 && runs[1].1 == runs[0].1 && differ >= 0 && differ * 500 < a.count,
          String(format: "P146: batched terrain: %d draws instead of %d, %d quads both ways, %d of %d channels differ; record %.2f -> %.2f ms",
                 runs[1].0, runs[0].0, runs[1].1, differ, a.count, runs[0].2, runs[1].2))
    print(failures == 0 ? "batch: all checks passed" : "batch: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --radio-only: radio spoofing at a base's console (Sources/RadioTests.swift, backlog C6).
if CommandLine.arguments.contains("--radio-only") {
    RadioTests.run(game: game, check: check)
    print(failures == 0 ? "radio: all checks passed" : "radio: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --mapfog-only: map fog of war and the compass strip (Sources/MapFogTests.swift, backlog A5).
if CommandLine.arguments.contains("--mapfog-only") {
    MapFogTests.run(game: game, check: check)
    print(failures == 0 ? "mapfog: all checks passed" : "mapfog: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --skyisle-only: sky isles and the Grapple Line (Sources/SkyIsleTests.swift, backlog C7).
if CommandLine.arguments.contains("--skyisle-only") {
    SkyIsleTests.run(device: device, game: game, check: check)
    print(failures == 0 ? "skyisle: all checks passed" : "skyisle: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --overlaps-only: structure piece overlaps over 12 seeds (Sources/OverlapTests.swift, Q2; OVERLAP_SEEDS=N).
if CommandLine.arguments.contains("--overlaps-only") {
    OverlapTests.run(check: check)
    print(failures == 0 ? "overlaps: all checks passed" : "overlaps: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --musiclevels-only: every mood's music through the leveller, loudness and peaks (Sources/MusicLevelTests.swift, Q2).
if CommandLine.arguments.contains("--musiclevels-only") {
    MusicLevelTests.run(check: check)
    print(failures == 0 ? "musiclevels: all checks passed" : "musiclevels: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --touchmatrix-only: the Touch conflict matrix alone (needs Vulkan: lavapipe).
if CommandLine.arguments.contains("--touchmatrix-only"), let ctx = vkctx {
    do { try QuestTouchMatrix.run(game: game, ctx: ctx, check: check) } catch { check(false, "touchmatrix: \(error)") }
    print(failures == 0 ? "touchmatrix: all checks passed" : "touchmatrix: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --vrtext-only: text size in degrees on the headset's panels (VRTextCheck.swift, Q2).
if CommandLine.arguments.contains("--vrtext-only") {
    VRTextCheck.run(game: game, check: check)
    print(failures == 0 ? "vrtext: all checks passed" : "vrtext: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --settings-only: options persist across launches and Reset Options resets them all (SettingsCheck.swift, Q2).
if CommandLine.arguments.contains("--settings-only") {
    SettingsCheck.run(check: check)
    print(failures == 0 ? "settings: all checks passed" : "settings: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --friendlyfire-only: soldier squads of the Capital, Greywall and the Meridian Navy never hurt their own
// (Sources/FriendlyFireTests.swift, Q2).
if CommandLine.arguments.contains("--friendlyfire-only") {
    FriendlyFireTests.run(game: game, check: check)
    print(failures == 0 ? "friendlyfire: all checks passed" : "friendlyfire: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --latency-only: every control answers in the frame that reads the press (Sources/InputLatencyTests.swift, Q2).
if CommandLine.arguments.contains("--latency-only") {
    InputLatencyTests.run(game: game, check: check)
    print(failures == 0 ? "latency: all checks passed" : "latency: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --firsthour-only: a next goal at every step of the story path (Sources/Goals.swift, GoalTests.swift, Q2).
if CommandLine.arguments.contains("--firsthour-only") {
    GoalTests.run(game: game, check: check)
    print(failures == 0 ? "firsthour: all checks passed" : "firsthour: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --notext: P328 (NO TEXT) checks that used to read hint text, as they read now. Goals are bare names. The emerald tip,
// the citadel lead and the hotbar say nothing. The Keeper's Journal tells a story with no recipe. Boreal Station's bar
// is a readout.
if CommandLine.arguments.contains("--notext") {
    GoalTests.run(game: game, check: check)
    G20Tests.powderwightAndEmerald(game, check)
    PlaytestOct12PMTests.p139(game, check)
    PlaytestOct12Tests.hotbarHints(game, check)
    DeepGapTests.bits(game, check)
    BorealTests.run(device: device, check: check)
    print(failures == 0 ? "notext: all checks passed" : "notext: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --balance-only: combat time-to-kill duels against the night roster (Sources/BalanceTests.swift, Q2; --write-balance).
if CommandLine.arguments.contains("--balance-only") {
    BalanceTests.run(game: game, check: check)
    print(failures == 0 ? "balance: all checks passed" : "balance: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --savesoak-only: 100 save/load cycles (Sources/SaveSoakTests.swift, Q2; SOAK_CYCLES=N).
if CommandLine.arguments.contains("--savesoak-only") {
    SaveSoakTests.run(device: device, check: check)
    print(failures == 0 ? "savesoak: all checks passed" : "savesoak: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --submarine-only: submarines, mines and sonar (Sources/SubmarineTests.swift, backlog C8).
if CommandLine.arguments.contains("--submarine-only") {
    SubmarineTests.run(game: game, check: check)
    print(failures == 0 ? "submarine: all checks passed" : "submarine: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --skiff-only: the Sky Skiff, the ready-made flyer (Sources/SkySkiffTests.swift, backlog A4).
if CommandLine.arguments.contains("--skiff-only") {
    SkySkiffTests.run(game: game, check: check)
    print(failures == 0 ? "skiff: all checks passed" : "skiff: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--troopclasses-only") {
    TroopTests.run(game: game, check: check)
    print(failures == 0 ? "troopclasses: all checks passed" : "troopclasses: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--greywall-only") {
    GreywallTests.run(device: device, game: game, check: check)
    print(failures == 0 ? "greywall: all checks passed" : "greywall: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// --posecheck-only: just the pose oracle (the full run does it last: it builds every model and draws random guns).
if CommandLine.arguments.contains("--posecheck-only") {
    check(PoseCheck.run(game: game), "posecheck: \(PoseCheck.failures.count) failed \(PoseCheck.failures.prefix(6).joined(separator: ", "))")
    exit(failures == 0 ? 0 : 1)
}
// Hell's own mobs and the gate into hell (Sources/HellMobsTests.swift); --hell-only stops after them.
HellMobsTests.run(game, check: check)
if CommandLine.arguments.contains("--hell-only") && renderPath == nil {
    print(failures == 0 ? "hell: all checks passed" : "hell: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// The last war below the Ash Vault (Sources/LastWarTests.swift); --lastwar-only stops after it.
if CommandLine.arguments.contains("--lastwar-only") || !CommandLine.arguments.contains("--hell-only") { LastWarTests.run(game, check: check) }
// With --render: the citadel's south gate, the army drawn up, an Ember Line bunker and the Chancellor's study (Quest
// renderer, next to the PNG).
if let path = renderPath, !path.isEmpty, let ctx = vkctx, !CommandLine.arguments.contains("--hell-only") {
    let dir = (path as NSString).deletingLastPathComponent
    let home = game.player.pos, wasMobs = game.mobs.mobs
    func shot(_ name: String, at p: V3, yaw: Float, pitch: Float, mobs: [Mob] = []) {
        game.changeDimension(to: .deep, at: p)
        game.player.pos = p; game.player.vel = .zero; game.player.flying = true
        _ = game.world.loadSync(center: p, radius: 5)
        game.world.pendingMobs.removeAll()
        game.mobs.mobs = mobs
        do {
            try RenderTest.render(game: game, ctx: ctx, path: (dir.isEmpty ? "." : dir) + "/\(name).png", yaw: yaw, pitch: pitch)
            print("render: \(dir)/\(name).png")
        } catch { check(false, "lastwar render \(name): \(error)") }
        game.mobs.mobs = []
    }
    let fy = Float(DeepGen.floorBase + 1)
    shot("lastwar_gate", at: V3(0.5, fy + 3, 80.5), yaw: 0, pitch: 0.06)
    shot("lastwar_army", at: V3(0.5, fy + 2.2, 58.5), yaw: 0, pitch: -0.08, mobs: LastWarTests.lineup(at: V3(0.5, fy, 47.5)))
    shot("lastwar_command", at: V3(0.5, fy + 3, -26.5), yaw: .pi, pitch: 0.02)
    let a: Float = 37.5 * .pi / 180
    shot("lastwar_line", at: V3(sinf(a) * 444, fy + 4, -cosf(a) * 444), yaw: -a + .pi, pitch: -0.12)
    shot("lastwar_study", at: V3(8.5, Float(AshFinal.y0) + 2.6, 33.5), yaw: .pi, pitch: -0.05)
    game.mobs.mobs = wasMobs
    game.changeDimension(to: .overworld, at: home)
    game.player.pos = home; game.player.vel = .zero; game.player.flying = false
    _ = game.world.loadSync(center: home, radius: 4)
}
if CommandLine.arguments.contains("--lastwar-only") {
    print(failures == 0 ? "lastwar: all checks passed" : "lastwar: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
// The Sparkstone Workshop's circuit benches (Sources/CircuitWorkshopTests.swift); --workshop-only stops after them.
CircuitWorkshopTests.run(game, check: check)
// L3 perf overlay (Sources/PerfOverlayTests.swift): its window, lines, option and HUD drawing on the Quest's HUD host.
PerfOverlayTests.run(game, hud: { Renderer(game: game).buildHUD(1280, 720).count }, check: check)
// L3 volcano eruptions (Sources/EruptionTests.swift): rarity, bursts near and far, the boom, the sound.
EruptionTests.run(game, check: check)
// L3 placement rules keep old saves (Sources/L3GuardTests.swift).
L3GuardTests.run(game, check: check)
L3GuardTests.g12(game, check: check)       // (G12 and old saves)
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
            // Above the tallest block there (heightmap with the trees), as the Mac snapshot: the terrain height alone
            // put the first renders inside a swamp oak's crown.
            game.player.pos.y = Float(max(world.gen.column(967, 1810).height, world.topY(967, 1810))) + 6
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
        // P8 (Oct 11 AM playtest, 08:47:53 "the volcano in the distance doesn't look great", build 0.129 from before the
        // far-view fixes): his view on the Quest renderer with the terrain loaded, toward the nearest volcano.
        do {
            let vw = World(seed: 3931512493184456980, device: device, save: nil)
            vw.renderDistance = World.lodNear
            let vg = Game(world: vw, save: nil, persistent: false)
            vg.time = 0.29 * DAY_LENGTH
            let x: Float = 5800.9, z: Float = -5520.1
            vg.player.pos = V3(x, Float(vw.gen.column(Int(x), Int(z)).height + 40), z)
            vg.player.flying = true
            _ = vw.loadSync(center: vg.player.pos, radius: World.lodNear)
            if let wg = vw.gen as? WorldGen, let v = wg.terrain.volcanoes(near: x, z, reach: 2600)
                .min(by: { simd_length(V2($0.x - x, $0.z - z)) < simd_length(V2($1.x - x, $1.z - z)) }) {
                let d = simd_normalize(V2(x - v.x, z - v.z))
                try RenderTest.render(game: vg, ctx: ctx, path: path.replacingOccurrences(of: ".png", with: "_volcanoP8.png"), yaw: atan2f(d.x, d.y), pitch: -0.05)
                check(RenderTest.landmarkVerts > 0, "P8 playtest far volcano drawn on the Quest renderer (\(RenderTest.landmarkVerts) vertices, \(Int(simd_length(V2(x - v.x, z - v.z)))) blocks)")
            } else { check(false, "P8: a volcano within 2600 blocks of the playtest note") }
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
            // Pinned fallback (audit 25b6 #2): seed 12345 has a beach at about (-2680, 36) (AuditGapTests.pinnedShore): the 8-direction search from spawn finds no deep sea there.
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
    // Touch input conflicts per context (quest/src/test/QuestTouchMatrix.swift, Q2).
    do { try QuestTouchMatrix.run(game: game, ctx: ctx, check: check) } catch { check(false, "touchmatrix: \(error)") }
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

// Greywall Command bases (Sources/GreywallTests.swift, backlog A1): the faction, rarity, and a real base of every tier walked.
// Each Lane A group must leave the player and world as it found them: a skiff check that left the player flying moved
// every later check (boarding, the Reckoning, roads, the sheriff, outlaws, countries) onto other ground.
func leaves(_ name: String, _ body: () -> Void) {
    let fly = game.player.flying, enc = game.world.ships.encounters, surv = game.survival, pos = game.player.pos, menu = game.menu == nil
    let menu0 = game.menu
    // Put it all back after the check, so one group's leftover fails that group, not every group after it.
    defer { game.player.flying = fly; game.world.ships.encounters = enc; game.survival = surv; game.player.pos = pos; game.player.vel = .zero; game.menu = menu0 }
    body()
    let moved = simd_length(game.player.pos - pos)
    check(game.player.flying == fly && game.world.ships.encounters == enc && game.survival == surv && moved < 1 && (game.menu == nil) == menu,
          "\(name): leaves the player and world as it found them (flying \(game.player.flying)/\(fly), encounters \(game.world.ships.encounters)/\(enc), survival \(game.survival)/\(surv), moved \(String(format: "%.1f", moved)), menu \(game.menu == nil ? "none" : "open"))")
}
leaves("greywall") { if !CommandLine.arguments.contains("--no-greywall") { GreywallTests.run(device: device, game: game, check: check) } }
leaves("troopclasses") { TroopTests.run(game: game, check: check) }
leaves("navy") { NavyTests.run(game: game, check: check) }
leaves("skiff") { SkySkiffTests.run(game: game, check: check) }
leaves("mapfog") { MapFogTests.run(game: game, check: check) }
leaves("radio") { RadioTests.run(game: game, check: check) }
leaves("skyisle") { SkyIsleTests.run(device: device, game: game, check: check) }
leaves("submarine") { SubmarineTests.run(game: game, check: check) }
leaves("savesoak") { SaveSoakTests.run(device: device, cycles: 5, check: check) }     // the full 100 in --savesoak-only (about 9 s a cycle)
leaves("balance") { BalanceTests.run(game: game, check: check) }
MusicLevelTests.run(check: check)
OverlapTests.run(check: check)
SettingsCheck.run(check: check)
leaves("latency") { InputLatencyTests.run(game: game, check: check) }
leaves("firsthour") { GoalTests.run(game: game, check: check) }
leaves("vrtext") { VRTextCheck.run(game: game, check: check) }
leaves("friendlyfire") { FriendlyFireTests.run(game: game, check: check) }

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
    // A slug from the helm, through Game.tick, craters a citadel (FactionTests.frigate; done audit 25b6, G1).
    FactionTests.frigate(game, check)
    // Aboard the Meridian frigate from the ground: the winch, the ladder, the helm (G11).
    BoardingTests.run(game, check)
    // The first citadel can be found: orders in outlaw camps (G6).
    FindabilityTests.run(game, check)
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

// The Oct 11 Quest playtest fixes (Sources/PlaytestOct11Tests.swift).
PlaytestOct11Tests.run(game, check)
// The Oct 12 AM Quest playtest fixes (Sources/PlaytestOct12Tests.swift).
leaves("p12") { PlaytestOct12Tests.run(game, check) }

// Towns of people and shops (Sources/TownTests.swift).
TownTests.run(game: game, makeWorld: { World(seed: seed, device: device, save: nil) }, check: check)

// Horses: gaits, stamina, bond, footing, crashes, nerves (Sources/HorseTests.swift, docs/status/horses.md).
HorseTests.run(game: game, check: check)

// The pose oracle (Sources/PoseCheck.swift; the Mac fast lane runs it too): limbs, soldiers' hands, heads and weapons in
// every stance.
check(PoseCheck.run(game: game), "posecheck: \(PoseCheck.failures.count) failed \(PoseCheck.failures.prefix(6).joined(separator: ", "))")

try? FileManager.default.removeItem(at: tmp)
print(failures == 0 ? "questcheck: all checks passed" : "questcheck: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
