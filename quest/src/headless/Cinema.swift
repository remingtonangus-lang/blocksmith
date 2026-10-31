import Foundation
import simd
import Metal
import CVulkan

// Store trailer footage (questcheck --cine SHOTS.json --out DIR [--w W --h H --only NAME,...]): scripted camera moves
// through the real game, rendered by the Quest renderer one eye at a time. Each shot builds its own world (seed, field
// ground, the headset's detail rings), finds its subject (a structure, a biome, a railway, or a spot), runs the game for
// a warm-up so townsfolk walk and soldiers take their posts, then plays its events (spawns, blasts, a tank breaking up,
// a frigate's main gun, a cabin going up block by block) while the camera flies its keyframes, the game ticking at the
// headset's 72 Hz between frames. Frames go to DIR/NAME/f00000.png; tools/cine.sh encodes them.
// The camera is the player (flying, creative unless the shot asks for survival, kept alive), so the world streams round it.
enum Cinema {
    struct Key: Decodable { let t: Double; let pos: [Float]; let look: [Float]; let ground: Bool?; let cut: Bool? }   // cut: a hard cut to this key
    struct Ev: Decodable {
        let t: Double
        let `do`: String
        let at: [Float]?
        let to: [Float]?
        let power: Float?
        let fire: Bool?
        let mob: String?
        let n: Int?
        let spread: Float?
        let yaw: Float?
        let pitch: Float?
        let dur: Double?
        let size: [Int]?
        let block: String?
        let ground: Bool?
    }
    struct Anchor: Decodable {
        let near: String?
        let from: [Float]?
        let at: [Float]?
        let find: String?
        let rail: Int?
        let train: String?
        let station: String?        // a Boreal Station camera spot (BorealStation.views name) as the anchor
        let frigate: [Float]?       // dx, dz, yaw (degrees): a Meridian frigate spawned there; the subject is then the frigate
    }
    struct Shot: Decodable {
        let name: String
        let seed: UInt64?
        let dim: String?
        let field: Bool?
        let rd: Int?
        let time: Double?
        let timeRate: Double?       // day fractions a second of footage (a time-lapse)
        let seconds: Double
        let fps: Int?
        let rain: Bool?
        let fov: Float?
        let warm: Double?
        let survival: Bool?
        let peaceful: Bool?         // night monsters cleared each frame (a town at dusk without the undead)
        let anchor: Anchor?
        let cam: [Key]
        let events: [Ev]?
    }

    static func run(ctx: VkContext) -> Int32 {
        guard let path = arg("--cine"), let data = FileManager.default.contents(atPath: path) else { print("cine: no shot file"); return 1 }
        let shots: [Shot]
        do { shots = try JSONDecoder().decode([Shot].self, from: data) } catch { print("cine: bad shot file: \(error)"); return 1 }
        let out = arg("--out") ?? "cine"
        let only = Set((arg("--only") ?? "").split(separator: ",").map(String.init))
        let W = Int(arg("--w") ?? "") ?? 1920, H = Int(arg("--h") ?? "") ?? 1080
        let still = CommandLine.arguments.contains("--still")     // the middle frame of each shot only
        for s in shots where only.isEmpty || only.contains(s.name) {
            do { try shoot(s, ctx: ctx, dir: out + "/" + s.name, W: W, H: H, still: still) } catch { print("cine: \(s.name) failed: \(error)"); return 1 }
        }
        return 0
    }

    // Catmull-Rom through the keys (clamped ends), eased in time so a move starts and lands softly.
    static func sample(_ keys: [Key], _ t: Double, _ f: (Key) -> V3) -> V3 {
        if keys.count == 1 { return f(keys[0]) }
        var i = 0
        while i < keys.count - 2 && t > keys[i + 1].t { i += 1 }
        var a = keys[max(0, i - 1)], b = keys[i], c = keys[i + 1], d = keys[min(keys.count - 1, i + 2)]
        if c.cut == true { return f(b) }                  // held until the cut
        if b.cut == true { a = b }
        if d.cut == true { d = c }
        var u = Float(max(0, min(1, (t - b.t) / max(1e-6, c.t - b.t))))
        if keys.count == 2 { u = u * u * (3 - 2 * u) }
        let p0 = f(a), p1 = f(b), p2 = f(c), p3 = f(d)
        let u2 = u * u, u3 = u2 * u
        let r = (p1 * 2 + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 + (p3 - p0 + (p1 - p2) * 3) * u3) * 0.5
        return r
    }

    static func shoot(_ s: Shot, ctx: VkContext, dir: String, W: Int, H: Int, still: Bool) throws {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = World(seed: s.seed ?? 7639458412018979794, device: sharedSystemDevice, save: nil, dim: Dim(rawValue: s.dim ?? "") ?? .overworld)
        w.renderDistance = s.rd ?? 10
        let field = s.field ?? true
        if field { w.makeFieldWorld() }
        World.lodNear = 99; World.leafNear = QuestApp.leafNear
        let g = Game(world: w, save: nil, persistent: false)
        if field { g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w) }
        g.time = (s.time ?? 0.27) * DAY_LENGTH
        g.player.flying = true
        if s.rain == true { g.weather.raining = true; g.weather.rain = 1 }
        // The subject.
        var origin = V3(0, Float(SEA), 0)
        let a = s.anchor
        if let at = a?.at, at.count == 3 { origin = V3(at[0], at[1], at[2]) }
        let from = a?.from ?? [origin.x, origin.z]
        if let kind = a?.near, let st = w.gen.structures?.nearest(kind, x: Int(from[0]), z: Int(from[1]), maxRegions: 16) {
            origin = V3(Float(st.min.x + st.max.x) / 2 + 0.5, Float(st.anchor.y), Float(st.min.z + st.max.z) / 2 + 0.5)
            if kind == BorealStation.kind, let n = a?.station, let v = BorealStation.views(w, st).first(where: { $0.0 == n }) { origin = v.1 }
            print("cine: \(s.name): \(kind) at \(Int(origin.x)) \(Int(origin.y)) \(Int(origin.z)) (box \(st.max.x - st.min.x) x \(st.max.z - st.min.z))")
        } else if let kind = a?.near { print("cine: \(s.name): no \(kind) near \(from)") }
        if let want = a?.find {
            var x = 0, z = 0, dx = 0, dz = -1
            for _ in 0..<20000 {
                let wx = Int(from[0]) + x * 48, wz = Int(from[1]) + z * 48
                if [(0, 0), (24, 0), (-24, 0), (0, 24), (0, -24)].allSatisfy({ w.gen.column(wx + $0.0, wz + $0.1).biome.name == want }) {
                    origin = V3(Float(wx) + 0.5, Float(w.gen.column(wx, wz).height), Float(wz) + 0.5); print("cine: \(s.name): \(want) at \(wx) \(wz)"); break
                }
                if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
                x += dx; z += dz
            }
        }
        var railLine: Railways.Line?, railCell = 0
        if let rf = a?.rail, let gen = w.gen as? WorldGen {
            let ax = Int(from[0]), az = Int(from[1])
            if let l = Railways.near(gen, x0: ax - 3000, z0: az - 3000, x1: ax + 3000, z1: az + 3000, pad: 0)
                .min(by: { abs($0.minX - ax) + abs($0.minZ - az) < abs($1.minX - ax) + abs($1.minZ - az) }), !l.cells.isEmpty {
                railCell = min(l.cells.count - 1, max(0, Int(Float(l.cells.count - 1) * Float(rf) / 100)))
                let c = l.cells[railCell]
                origin = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5)
                railLine = l
                print("cine: \(s.name): railway \(l.name) cell \(railCell) at \(c.x) \(c.y) \(c.z)")
            }
        }
        var frigate: Ship?
        if let fa = a?.frigate, fa.count >= 2 {
            let n0 = w.ships.list.count
            _ = w.loadSync(center: origin + V3(fa[0], 0, fa[1]), radius: 3)
            w.ships.spawnCapital("capfrigate", home: IVec3(Int(origin.x + fa[0]), 0, Int(origin.z + fa[1])), yaw: (fa.count > 2 ? fa[2] : 0) * .pi / 180, region: nil, sync: true)
            frigate = w.ships.list.dropFirst(n0).first { $0.role == "capfrigate" }
            if let fr = frigate { fr.captured = true; fr.vel = .zero; fr.angVel = .zero; origin = fr.pos; print("cine: \(s.name): frigate at \(Int(fr.pos.x)) \(Int(fr.pos.y)) \(Int(fr.pos.z))") }
        }
        // The ground under a point as it stood when first asked (later blasts, craters and building don't move a camera
        // key or a look target mid-shot): the loaded world's top solid ground, else the generator's height.
        var groundSeen: [Int64: Float] = [:]
        func leafy(_ b: BlockID) -> Bool { let k = Blocks.key(Blocks.groupBase[Int(b)]); return k.hasSuffix("_leaves") || k.hasSuffix("_log") || k.hasSuffix("_wood") }
        func ground(_ x: Float, _ z: Float) -> Float {
            let ix = Int(floor(x)), iz = Int(floor(z))
            let key = (Int64(ix) << 32) ^ Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: iz)))
            if let y = groundSeen[key] { return y }
            var y = Float(max(w.gen.column(ix, iz).height, SEA - 1) + 1)
            if w.chunkAt(ix, iz) != nil {
                var top = min(CH - 2, w.topY(ix, iz) + 1)
                while top > 1 && !(w.groundAt(ix, top - 1, iz) || (w.solidAt(ix, top - 1, iz) && !leafy(w.block(ix, top - 1, iz)))) { top -= 1 }
                if top > 1 { y = Float(max(top, SEA)) }
            }
            groundSeen[key] = y
            return y
        }
        // A point relative to the subject; `onGround`: its y over the ground there rather than over the subject.
        func rel(_ v: [Float], _ onGround: Bool) -> V3 {
            let p = origin + V3(v[0], 0, v[2])
            return V3(p.x, (onGround ? ground(p.x, p.z) : origin.y) + v[1], p.z)
        }
        let camPos = { (k: Key) -> V3 in rel(k.pos, k.ground ?? false) }
        let camLook = { (k: Key) -> V3 in rel(k.look, k.ground ?? false) }
        let start = sample(s.cam, 0, camPos)
        g.player.pos = start - V3(0, g.player.eyeHeight, 0)
        let lt = w.loadSync(center: start, radius: w.renderDistance)
        _ = w.loadSync(center: origin, radius: min(6, w.renderDistance))
        print(String(format: "cine: %@: %d chunks (gen %.0f ms, mesh %.0f ms)", s.name, w.chunks.count, lt.gen * 1000, lt.mesh * 1000))
        // The train on its line (the clock set to when the timetable has it at the cell).
        if let kn = s.anchor?.train, let l = railLine {
            Trains.forceKind = ["passenger": .passenger, "cargo": .cargo, "troop": .troop][kn] ?? .passenger
            let t = Trains.track(l)
            var best = 0.0, bd = Float.greatestFiniteMagnitude, tt = 0.0
            while tt < t.period { let p = t.at(tt); if abs(p.s - Float(railCell)) < bd { bd = abs(p.s - Float(railCell)); best = tt }; tt += 0.1 }
            g.time = best - (s.warm ?? 0) - 1
        }
        g.paused = false
        g.survival = s.survival ?? false
        g.player.flying = true
        let dt = 1.0 / 72
        func hold(_ eye: V3) {
            g.player.pos = eye - V3(0, g.player.eyeHeight, 0); g.player.vel = .zero; g.player.flying = true
            g.health = 20
        }
        func calm() {
            guard s.peaceful == true else { return }
            let night: Set<MobKind> = [.zombie, .skeleton, .creeper, .spider, .enderman, .witch, .slime, .phantom, .drowned, .husk, .stray,
                                       .caveSpider, .zombieVillager, .silverfish, .endermite, .bogged, .parched]
            let n0 = g.mobs.mobs.count
            g.mobs.mobs.removeAll { night.contains($0.kind) }
            if g.mobs.mobs.count != n0 { g.mobs.rebuildIndex() }
        }
        // Warm-up: the game runs at the first camera spot.
        let warm = Int((s.warm ?? 3) * 72)
        for i in 0..<warm { hold(start); g.tick(dt); calm(); if i % 144 == 143 { _ = w.loadSync(center: start, radius: w.renderDistance) } }
        let rig = try Rig(game: g, ctx: ctx, width: W, height: H, fovDeg: s.fov ?? 70)
        let fps = s.fps ?? 30
        let frames = max(1, Int(s.seconds * Double(fps)))
        var events = (s.events ?? []).sorted { $0.t < $1.t }
        var builds: [(cells: [(IVec3, BlockID)], t0: Double, dur: Double, done: Int)] = []
        let perFrame = max(1, 72 / fps)
        let baseTime = g.time
        print(String(format: "cine: %@: ready after %.1f s; %d frames at %dx%d", s.name, CFAbsoluteTimeGetCurrent() - t0, frames, W, H))
        var tick = 0
        for f in 0..<frames {
            let t = Double(f) / Double(fps)
            // Events due by this frame.
            while let e = events.first, e.t <= t {
                events.removeFirst()
                let p = rel(e.at ?? [0, 0, 0], e.ground ?? true)
                switch e.do {
                case "explode":
                    Explosion.explode(at: p, power: e.power ?? 4, game: g, fire: e.fire ?? false)
                case "spawn":
                    let n = e.n ?? 1, sp = e.spread ?? 3
                    for i in 0..<n {
                        let ang = Float(i) * 2.399, r = sp * sqrtf(Float(i) / Float(max(1, n)))
                        let q = V3(p.x + cosf(ang) * r, 0, p.z + sinf(ang) * r)
                        let at = V3(q.x, ground(q.x, q.z) + 0.05, q.z)
                        if let m = Mob.structureMob(e.mob ?? "soldier_trooper", at: at) ?? MobKind.named(e.mob ?? "").map({ Mob($0, at: at) }) {
                            if let y = e.yaw { m.yaw = -y * .pi / 180 }
                            m.persistent = true
                            g.mobs.mobs.append(m)
                        }
                    }
                    g.mobs.rebuildIndex()
                case "vehicle":
                    let k = MobKind.named(e.mob ?? "ash_tank") ?? .ashTank
                    let m = Mob(k, at: V3(p.x, p.y + 0.05, p.z))
                    m.ashSetup()
                    m.yaw = -(e.yaw ?? 0) * .pi / 180
                    m.persistent = true
                    g.mobs.mobs.append(m); g.mobs.rebuildIndex()
                case "wreck":                                // every Ashguard vehicle within `spread` of the spot breaks up
                    let r = e.spread ?? 6
                    for m in g.mobs.mobs where [MobKind.ashTank, .ashHalftrack, .ashArtillery, .ashTruck, .ashBehemoth].contains(m.kind) && simd_length(m.pos - p) < r {
                        Explosion.explode(at: m.pos + V3(0, 1, 0), power: e.power ?? 3, game: g, fire: true, except: m, breakBlocks: false)
                        m.health = 0
                        g.ashUnitDied(m)
                    }
                    g.mobs.mobs.removeAll { $0.health <= 0 && [MobKind.ashTank, .ashHalftrack, .ashArtillery, .ashTruck, .ashBehemoth].contains($0.kind) }
                    g.mobs.rebuildIndex()
                case "frigate":
                    let n0 = w.ships.list.count
                    w.ships.spawnCapital("capfrigate", home: IVec3(Int(p.x), 0, Int(p.z)), yaw: (e.yaw ?? 0) * .pi / 180, region: nil, sync: true)
                    frigate = w.ships.list.dropFirst(n0).first { $0.role == "capfrigate" }
                    if let fr = frigate { fr.captured = true; fr.vel = .zero; fr.angVel = .zero; print("cine: \(s.name): frigate at \(Int(fr.pos.x)) \(Int(fr.pos.y)) \(Int(fr.pos.z))") }
                case "fire":
                    if let fr = frigate, let st = w.ships.capState[fr.id] {
                        st.mainGunCD = 0
                        fr.vel = .zero; fr.angVel = .zero
                        if let pk = e.pitch { w.ships.pointHull(fr, pitch: pk * .pi / 180) }
                        print("cine: \(s.name): main gun \(w.ships.playerMainGun(fr, game: g) ? "charging" : "not ready")")
                    }
                case "impact":                              // a Tidebreaker slug striking the spot (the frigate's own blast)
                    if let fr = frigate { w.ships.mainGunImpact(at: p, owner: fr.id, game: g, along: simd_normalize(p - fr.pos)) }
                case "build":
                    builds.append((cabin(at: IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))), size: e.size ?? [7, 4, 6], w: w), t, e.dur ?? 6, 0))
                case "time":
                    g.time = (e.power.map(Double.init) ?? 0.27) * DAY_LENGTH
                case "rain":
                    g.weather.raining = (e.power ?? 1) > 0
                default:
                    print("cine: unknown event \(e.do)")
                }
            }
            // Cabins going up: the share of their blocks due by now, bottom first.
            for i in builds.indices {
                let b = builds[i]
                let due = min(b.cells.count, Int(Double(b.cells.count) * max(0, min(1, (t - b.t0) / b.dur))))
                if due > b.done {
                    w.editBatch { for k in b.done..<due { let (c, id) = b.cells[k]; w.setBlock(c.x, c.y, c.z, id) } }
                    builds[i].done = due
                }
            }
            let eye = sample(s.cam, t, camPos), look = sample(s.cam, t, camLook)
            for _ in 0..<perFrame {
                hold(eye)
                if let fr = frigate { fr.vel = .zero; fr.angVel = .zero }
                g.tick(dt); tick += 1
                calm()
            }
            if let r = s.timeRate { g.time = baseTime + r * t * DAY_LENGTH }
            if f % 30 == 0 { _ = w.loadSync(center: eye, radius: min(w.renderDistance, 6)) }
            if still && f != frames / 2 { continue }
            let d = simd_normalize(look - eye)
            let yaw = atan2f(-d.x, -d.z), pitch = asinf(max(-1, min(1, d.y)))
            try rig.shoot(still ? dir + ".png" : String(format: "%@/f%05d.png", dir, f), eye: eye, yaw: yaw, pitch: pitch)
            if f % 30 == 0 { print(String(format: "cine: %@: frame %d/%d (%.0f s), %d mobs, %d particles", s.name, f, frames, CFAbsoluteTimeGetCurrent() - t0, g.mobs.mobs.count, g.particles.list.count)) }
        }
        print(String(format: "cine: %@: done in %.0f s", s.name, CFAbsoluteTimeGetCurrent() - t0))
    }

    // A frontier cabin as block cells in building order (floor, walls course by course with a door and windows, a
    // pitched roof), so it rises the way a player builds it.
    static func cabin(at o: IVec3, size: [Int], w: World) -> [(IVec3, BlockID)] {
        let sx = size.count > 0 ? size[0] : 7, h = size.count > 1 ? size[1] : 4, sz = size.count > 2 ? size[2] : 6
        func id(_ k: String, _ alt: String) -> BlockID { Blocks.has(k) ? Blocks.id(k) : Blocks.id(alt) }
        let log = id("spruce_log", "oak_log"), plank = id("spruce_planks", "oak_planks"), glass = id("glass_pane", "glass")
        let stone = id("cobblestone", "stone"), roof = id("dark_oak_planks", "oak_planks"), door = id("oak_planks", "oak_planks")
        var cells: [(IVec3, BlockID)] = []
        // footing: a stone course under the whole floor
        for z in 0..<sz { for x in 0..<sx { cells.append((IVec3(o.x + x, o.y, o.z + z), stone)) } }
        for y in 1...h {
            var ring: [(IVec3, BlockID)] = []
            for z in 0..<sz { for x in 0..<sx where x == 0 || z == 0 || x == sx - 1 || z == sz - 1 {
                let corner = (x == 0 || x == sx - 1) && (z == 0 || z == sz - 1)
                let doorway = z == 0 && x == sx / 2 && y <= 2
                let window = !corner && y == 2 && ((z == 0 && (x == 1 || x == sx - 2)) || ((x == 0 || x == sx - 1) && z == sz / 2))
                if doorway { continue }
                ring.append((IVec3(o.x + x, o.y + y, o.z + z), corner ? log : (window ? glass : plank)))
            } }
            cells += ring
        }
        _ = door
        // roof: gables along x, stepping in over z
        let half = (sz + 1) / 2
        for k in 0...half {
            for x in -1...sx {
                for z in [k - 1, sz - k] where z >= -1 && z <= sz {
                    cells.append((IVec3(o.x + x, o.y + h + 1 + k, o.z + z), roof))
                }
                if k > 0 && (x == 0 || x == sx - 1) {
                    for z in k..<max(k, sz - k) { cells.append((IVec3(o.x + x, o.y + h + k, o.z + z), plank)) }
                }
            }
        }
        _ = w
        return cells
    }

    // One renderer for a shot's frames; each frame drawn once into the left eye (the second eye's view is the same).
    final class Rig {
        let game: Game, scene: SceneRenderer, wr: WorldRenderer, img: VkImg, targets: [RenderTarget], readback: VkBuf
        let width: Int, height: Int, proj: float4x4, far: Float
        var n = 0
        init(game: Game, ctx: VkContext, width: Int, height: Int, fovDeg: Float) throws {
            self.game = game; self.width = width; self.height = height
            scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
            try scene.uploadTextures()
            wr = WorldRenderer(scene: scene, game: game)
            wr.landmarkHost = Renderer(game: game)
            img = try VkImg(ctx, width: width, height: height, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
            targets = [try scene.makeTarget(image: img.image, width: width, height: height),
                       try scene.makeTarget(image: img.image, width: width, height: height)]
            let tv = tanf(fovDeg * .pi / 360)                     // fovDeg is the vertical field of view
            let th = tv * Float(width) / Float(height)
            let ringFar: Float = FarRing.enabled && game.dim.dim == .overworld ? FarRing.outer + 96 : 0
            far = max(Float(game.world.renderDistance * 16 + 96), ringFar)
            proj = XRMath.projection(tanLeft: -th, tanRight: th, tanUp: tv, tanDown: -tv, near: 0.05, far: far)
            readback = try VkBuf(ctx, size: width * height * 4 * 2, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        }
        func shoot(_ path: String, eye: V3, yaw: Float, pitch: Float) throws {
            let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
            let vp = proj * XRMath.inversePose(head, .zero)
            game.player.yaw = yaw; game.player.pitch = pitch
            let cam = EyeCamera(center: eye, viewProj: [vp, vp], cullViewProj: vp, yaw: yaw, pitch: pitch, far: far)
            // The first frame twice (what it starts building is in it); after that once a frame, as in play.
            for _ in 0..<(n == 0 ? 2 : 1) {
                let s = scene.beginFrame()
                wr.record(s, targets[n % 2], cam)
                n += 1
                vkCmdEndRenderPass(s.cmd)
                vkBarrier(s.cmd, img.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                          srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                          srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
                var r = VkBufferImageCopy()
                r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
                r.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
                vkCmdCopyImageToBuffer(s.cmd, img.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
                try scene.submit(s)
                scene.waitIdle()
            }
            let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: width * height * 4)
            var out = [UInt8](repeating: 0, count: width * height * 4)
            for i in 0..<(width * height) { out[i * 4] = src[i * 4]; out[i * 4 + 1] = src[i * 4 + 1]; out[i * 4 + 2] = src[i * 4 + 2]; out[i * 4 + 3] = 255 }
            try PNG.encode(rgba: out, width: width, height: height).write(to: URL(fileURLWithPath: path))
        }
    }
}
