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
        let cells: [[Float]]?       // lay / reap: block cells relative to `at`, one every `dur` seconds
        let head: Float?            // shoot: the aim's height up the target mob (0 feet, 1 top; default 0.86, a head shot)
    }
    struct Anchor: Decodable {
        let near: String?
        let from: [Float]?
        let at: [Float]?
        let find: String?
        let rail: Int?
        let train: String?
        let station: String?        // a Boreal Station camera spot (BorealStation.views name) as the anchor
        let cave: Bool?             // the nearest open cave room under the subject (a 5 x 3 x 5 pocket of air)
        let deep: String?           // in the Deep: "vault" (the Ash Vault's floor) or "hell" (open space over the lava sea)
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
        let cruise: Float?          // the frigate flies on along its keel at this speed (blocks/s), the camera with it
        let skip: [String]?         // render layers left out of this shot only (QUEST_SKIP names, e.g. "ships")
        let follow: Bool?           // false: the camera keeps its own keyframes while the frigate flies past (default true)
        let hold: String?           // first person: the VR hands drawn, holding this item (an item key; "" or "hands": empty hands)
        let playerMount: String?    // "horse": the camera rides a saddled horse that gallops along the camera's heading
        let heldScale: Float?       // the game's Held Item Size option for this shot (default 0.8, its smallest)
        let hands: [[Float]]?       // the right and left hands' rest offsets from the eye (metres, view space: x right, y up, -z ahead)
        let handTilt: Float?        // degrees the held item tips down from the view (default 10)
        let anchor: Anchor?
        let cam: [Key]
        let events: [Ev]?
    }

    static func run(ctx: VkContext) -> Int32 {
        guard let path = arg("--cine"), let data = FileManager.default.contents(atPath: path) else { print("cine: no shot file"); return 1 }
        let shots: [Shot]
        do { shots = try JSONDecoder().decode([Shot].self, from: data) } catch { print("cine: bad shot file: \(error)"); return 1 }
        let out = arg("--out") ?? "cine"
        // The Deep meshes only the layer the player stands in (World.deepLayerCut); the cine camera flies free of the
        // harness's player, so a hell shot showed only its nearest chunks. A player in hell sees all of hell: mesh both.
        World.deepLayerCut = false
        // The headset steps ships once a drawn frame (QuestApp); left at 60 Hz under 72 Hz ticks, a cruising frigate took
        // one or two steps a video frame and juddered (Remington, Nov 11: "the frigate was moving choppily").
        ShipManager.stepRate = 72; ShipManager.stepSlack = 0.2 / 72
        let only = Set((arg("--only") ?? "").split(separator: ",").map(String.init))
        let W = Int(arg("--w") ?? "") ?? 1920, H = Int(arg("--h") ?? "") ?? 1080
        let still = CommandLine.arguments.contains("--still")     // the middle frame of each shot only
        for s in shots where only.isEmpty || only.contains(s.name) {
            let skipBase = WorldRenderer.debugSkip
            WorldRenderer.debugSkip.formUnion(s.skip ?? [])
            WorldRenderer.debugSkip.insert("outline")       // never the aimed-at block's outline (Carbon v2: it showed on the grass in `ride`)
            defer { WorldRenderer.debugSkip = skipBase }
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
            if let fr = frigate { fr.captured = (s.events ?? []).contains { $0.do == "fire" }; fr.vel = .zero; fr.angVel = .zero; origin = fr.pos; print("cine: \(s.name): frigate at \(Int(fr.pos.x)) \(Int(fr.pos.y)) \(Int(fr.pos.z))") }
        }
        if let dk = a?.deep, let dg = w.gen as? DeepGen {
            let x = Int(floor(origin.x)), z = Int(floor(origin.z))
            _ = w.loadSync(center: V3(origin.x, 100, origin.z), radius: 2)
            var y = dg.floorY(x, z) + 1
            if dk == "hell" {
                y = DeepGen.hellBase + 33
                while y < DeepGen.crustTop - 8 && !(w.isAir(x, y, z) && w.isAir(x, y + 1, z)) { y += 1 }
            }
            origin.y = Float(y)
            print("cine: \(s.name): the Deep (\(dk)) at \(x) \(y) \(z): \(dg.layerName(x, y, z) ?? "-")")
        }
        if a?.cave == true {
            let px = Int(floor(origin.x)), pz = Int(floor(origin.z))
            func room(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                for dy in -1...1 { for dz in -2...2 { for dx in -2...2 where !w.isAir(x + dx, y + dy, z + dz) { return false } } }
                return w.solidAt(x, y - 2, z)
            }
            search: for r in stride(from: 0, through: 96, by: 4) { for dz in stride(from: -r, through: r, by: 4) { for dx in stride(from: -r, through: r, by: 4) where max(abs(dx), abs(dz)) == r {
                _ = w.loadSync(center: V3(Float(px + dx), 80, Float(pz + dz)), radius: 1)
                var y = w.gen.column(px + dx, pz + dz).height - 10
                while y > 20 { if room(px + dx, y, pz + dz) { origin = V3(Float(px + dx) + 0.5, Float(y - 1), Float(pz + dz) + 0.5); print("cine: \(s.name): cave at \(px + dx) \(y) \(pz + dz)"); break search }; y -= 1 }
            } } }
        }
        let overworld = w.dim == .overworld && a?.cave != true
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
                var top = overworld ? min(CH - 2, w.topY(ix, iz) + 1) : Int(origin.y) + 12
                if !overworld { while top > 1 && !w.isAir(ix, top, iz) { top -= 1 } }
                while top > 1 && !(w.groundAt(ix, top - 1, iz) || (w.solidAt(ix, top - 1, iz) && !leafy(w.block(ix, top - 1, iz)))) { top -= 1 }
                if top > 1 { y = Float(overworld ? max(top, SEA) : top) }
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
        var start = sample(s.cam, 0, camPos)
        g.player.pos = start - V3(0, g.player.eyeHeight, 0)
        let lt = w.loadSync(center: start, radius: w.renderDistance)
        _ = w.loadSync(center: origin, radius: min(6, w.renderDistance))
        // The ground asked before the chunks loaded was the generator's guess; the field world's own surface can stand a
        // block or more off it, and v3's eye heights came out at knee height. Ask again now that the ground is loaded.
        groundSeen.removeAll()
        start = sample(s.cam, 0, camPos)
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
        if s.hold != nil { QuestSettings.heldScale = s.heldScale ?? 0.8 }
        let rig = try Rig(game: g, ctx: ctx, width: W, height: H, fovDeg: s.fov ?? 70, hold: s.hold)
        if let hs = s.hands, hs.count > 0, hs[0].count == 3 { rig.rest[1] = V3(hs[0][0], hs[0][1], hs[0][2]) }
        if let hs = s.hands, hs.count > 1, hs[1].count == 3 { rig.rest[0] = V3(hs[1][0], hs[1][1], hs[1][2]) }
        if let tl = s.handTilt { rig.tilt = tl * .pi / 180 }
        // Hand work (lay, reap, shoot): when the right hand reaches out (a block placed, a crop cut) and where it aims.
        var reach: [(t: Double, at: V3)] = []          // the moment a hand action lands and its world spot
        var aims: [(t0: Double, t1: Double, at: () -> V3)] = []
        var shots: [(t: Double, at: () -> V3)] = []
        var lays: [(t: Double, c: IVec3, id: BlockID, cut: Bool)] = []
        var marchers: [(m: Mob, goal: V3, speed: Float)] = []      // spawned with `to`: they advance on their goal
        // Riding: the player on a saddled horse at the first camera spot, galloping along the camera's heading; the
        // camera is the rider's eye from then on (the keys only give the look direction).
        var mount: Mob?
        if s.playerMount == "horse" {
            let d0 = sample(s.cam, 0, camLook) - start
            let hy = atan2f(-d0.x, -d0.z)
            let h = Mob(.horse, at: V3(start.x, ground(start.x, start.z) + 0.05, start.z))
            h.variant = (15 << 4) | (8 << 8)
            h.breed = HorseBreed.saddlebred.rawValue
            h.owner = true; h.saddled = true; h.persistent = true; h.health = 30
            h.yaw = hy
            g.mobs.mobs.append(h); g.mobs.rebuildIndex()
            g.riding = h; g.player.flying = false; g.player.moveYaw = nil; g.player.yaw = hy
            g.player.pos = h.pos + V3(0, h.height * 0.75, 0)
            mount = h
        }
        let fps = s.fps ?? 30
        let frames = max(1, Int(s.seconds * Double(fps)))
        var events = (s.events ?? []).sorted { $0.t < $1.t }
        var builds: [(cells: [(IVec3, BlockID)], t0: Double, dur: Double, done: Int)] = []
        let perFrame = max(1, 72 / fps)
        let baseTime = g.time
        print(String(format: "cine: %@: ready after %.1f s; %d frames at %dx%d", s.name, CFAbsoluteTimeGetCurrent() - t0, frames, W, H))
        var tick = 0
        var cruiseFrom: V3?
        var cruiseRot: Quat?
        // Townsfolk and animals that wander up to the lens are walked off out of shot (scripted mobs stay put).
        func clearCamera(_ eye: V3) {
            // (Scripted soldiers too, a step closer: v2's camera walked into and through troopers, Nov 13 review.)
            for m in g.mobs.mobs where !m.kind.ashVehicle && m.kind != .deckGun && m.mount == nil && m.health > 0 {
                let d = V3(m.pos.x - eye.x, 0, m.pos.z - eye.z), l = simd_length(d)
                let r: Float = m.persistent ? 2.6 : 3.5
                if l < r && abs(m.pos.y - eye.y) < 4 { m.pos += (l > 0.01 ? d / l : V3(1, 0, 0)) * (r + 0.1 - l) }
            }
        }
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
                    let goal = e.to.map { rel($0, true) }
                    for i in 0..<n {
                        let ang = Float(i) * 2.399, r = sp * sqrtf(Float(i) / Float(max(1, n)))
                        let q = V3(p.x + cosf(ang) * r, 0, p.z + sinf(ang) * r)
                        let at = V3(q.x, ground(q.x, q.z) + 0.05, q.z)
                        if let m = Mob.structureMob(e.mob ?? "soldier_trooper", at: at) ?? MobKind.named(e.mob ?? "").map({ Mob($0, at: at) }) {
                            if let y = e.yaw { m.yaw = -y * .pi / 180 }
                            m.persistent = true
                            g.mobs.mobs.append(m)
                            if let gl = goal { marchers.append((m, gl + (q - p), e.power ?? 3.2)) }
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
                case "clear":                                // every mob of kind `mob` within `spread` of the spot leaves the shot
                    let r = e.spread ?? 16
                    if let k = MobKind.named(e.mob ?? "") {
                        g.mobs.mobs.removeAll { $0.kind == k && simd_length($0.pos - p) < r }
                        g.mobs.rebuildIndex()
                    }
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
                        if let st2 = w.ships.gunState(fr), let ap = w.ships.mainGunAimPoint(fr, st2) {
                            let r = ap - origin
                            print(String(format: "cine: %@: main gun aim point %.0f %.0f %.0f (from the anchor %.0f %.0f %.0f)", s.name, ap.x, ap.y, ap.z, r.x, r.y, r.z))
                        }
                    }
                case "impact":                              // a Tidebreaker slug striking the spot (the frigate's own blast)
                    if let fr = frigate { w.ships.mainGunImpact(at: p, owner: fr.id, game: g, along: simd_normalize(p - fr.pos)) }
                case "build":
                    builds.append((cabin(at: IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))), size: e.size ?? [7, 4, 6], w: w), t, e.dur ?? 6, 0))
                case "farm":                                 // a field: moist farmland (a water row down the middle) whose crop grows over `dur`
                    let sz = e.size ?? [9, 9], crop = e.block ?? "wheat"
                    let top = crop == "beetroots" ? 3 : 7
                    var soil: [(IVec3, BlockID)] = [], grow: [(IVec3, BlockID)] = []
                    let x0 = Int(floor(p.x)), z0 = Int(floor(p.z)), y = Int(floor(p.y))
                    for z in 0..<sz[1] { for x in 0..<sz[0] {
                        let water = x == sz[0] / 2
                        soil.append((IVec3(x0 + x, y - 1, z0 + z), water ? WATER : Blocks.id("farmland_moist")))
                        soil.append((IVec3(x0 + x, y, z0 + z), AIR))
                    } }
                    for st in 0...top { for z in 0..<sz[1] { for x in 0..<sz[0] where x != sz[0] / 2 {
                        grow.append((IVec3(x0 + x, y, z0 + z), Blocks.id(crop) + BlockID(st)))
                    } } }
                    builds.append((soil, t, 0.05, 0))
                    builds.append((grow, t + 0.1, e.dur ?? 5, 0))
                case "rider":                                // a traveller on horseback trotting off along `yaw`
                    let ang = (e.yaw ?? 0) * .pi / 180
                    let at = V3(p.x, p.y + 0.05, p.z)
                    let horse = Mob(.horse, at: at)
                    horse.saddled = true; horse.posse = Riders.riding; horse.persistent = true
                    let r = Mob(.villager, at: at + V3(0, horse.height * 0.8, 0))
                    r.home = at
                    Townsfolk.setup(r, game: g)
                    if var v = r.villager { v.role = "rider"; v.locked = true; v.profession = "none"; r.villager = v }
                    r.posse = Riders.riding; r.persistent = true; r.mount = horse
                    let d = e.spread ?? 60
                    let gx = p.x + sinf(ang) * d, gz = p.z - cosf(ang) * d
                    r.patrolGoal = V3(gx, ground(gx, gz), gz)
                    horse.yaw = -ang; r.yaw = -ang
                    g.mobs.mobs.append(horse); g.mobs.mobs.append(r); g.mobs.rebuildIndex()
                case "time":
                    g.time = (e.power.map(Double.init) ?? 0.27) * DAY_LENGTH
                case "place":                                // a block (torch, lantern...) at the spot, and n more round it
                    let id = Blocks.has(e.block ?? "torch") ? Blocks.id(e.block ?? "torch") : Blocks.id("torch")
                    let n = e.n ?? 1, sp = e.spread ?? 4
                    for i in 0..<n {
                        let ang = Float(i) * 2.399, r = n == 1 ? 0 : sp * sqrtf(Float(i + 1) / Float(n))
                        let qx = p.x + cosf(ang) * r, qz = p.z + sinf(ang) * r
                        let qy = (e.ground ?? true) ? ground(qx, qz) : p.y
                        w.setBlock(Int(floor(qx)), Int(floor(qy)), Int(floor(qz)), id)
                    }
                case "lay", "reap":                          // the player's hand places (or cuts) each cell in turn
                    let cut = e.do == "reap"
                    let id: BlockID = cut ? AIR : (Blocks.has(e.block ?? "oak_planks") ? Blocks.id(e.block ?? "oak_planks") : Blocks.id("oak_planks"))
                    let base = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                    for (i, c) in (e.cells ?? [[0, 0, 0]]).enumerated() where c.count == 3 {
                        let cell = IVec3(base.x + Int(c[0]), base.y + Int(c[1]), base.z + Int(c[2]))
                        let tt = t + Double(i) * (e.dur ?? 0.3) + 0.18
                        lays.append((tt, cell, id, cut))
                        reach.append((tt, V3(Float(cell.x) + 0.5, Float(cell.y) + 0.5, Float(cell.z) + 0.5)))
                    }
                case "shoot", "aim":                         // the held gun aimed (and fired `n` rounds) at a mob near the spot, or the spot
                    let n = e.do == "aim" ? 0 : (e.n ?? 1), gap = e.dur ?? 0.45
                    let r = e.spread ?? 4, hk = e.head ?? 0.86
                    var target: Mob?
                    if e.mob != nil || e.spread != nil {
                        target = g.mobs.mobs.filter { $0.health > 0 && $0 !== mount && !$0.kind.ashVehicle && $0.kind != .horse
                            && (e.mob == nil || MobKind.named(e.mob!) == $0.kind || ($0.kind.ashVehicle && e.mob == "vehicle"))
                            && simd_length(V3($0.pos.x - p.x, 0, $0.pos.z - p.z)) < r }
                            .min { simd_length($0.pos - p) < simd_length($1.pos - p) }
                        if target == nil, e.mob == "vehicle" { target = g.mobs.mobs.filter { $0.kind.ashVehicle && simd_length($0.pos - p) < r }.first }
                    }
                    let fixed = p + V3(0, e.at.map { _ in 0 } ?? 0, 0)
                    let tm = target
                    let at: () -> V3 = {
                        guard let m = tm else { return fixed }
                        let c = m.pos + V3(0, m.height * (m.kind.ashVehicle ? 0.5 : hk), 0)
                        return c + V3(m.vel.x, 0, m.vel.z) * min(0.3, simd_length(c - g.player.eye) / 150)
                    }
                    aims.append((t, t + 0.35 + Double(max(0, n - 1)) * gap + 0.5, at))
                    for i in 0..<n { shots.append((t + 0.35 + Double(i) * gap, at)) }
                    if let m = tm { print("cine: \(s.name): \(e.do) at \(m.kind) \(Int(m.pos.x)) \(Int(m.pos.z))") } else { print("cine: \(s.name): \(e.do) at the spot (no mob found)") }
                case "survival":
                    g.survival = (e.power ?? 1) > 0
                case "rain":
                    g.weather.raining = (e.power ?? 1) > 0
                default:
                    print("cine: unknown event \(e.do)")
                }
            }
            // The hand's work due by now: blocks laid or cut, rounds fired.
            while let l = lays.first, l.t <= t {
                lays.removeFirst()
                let old = w.block(l.c.x, l.c.y, l.c.z)
                if l.cut { if old != AIR { g.particles.blockBreak(old, at: l.c) } }
                w.setBlock(l.c.x, l.c.y, l.c.z, l.id)
            }
            if !shots.isEmpty { shots.sort { $0.t < $1.t } }
            while let sh = shots.first, sh.t <= t {
                shots.removeFirst()
                if let gi = g.heldGun {
                    var h = g.inventory.held; h.tag = Guns.all[gi].mag; g.inventory.held = h
                    g.arms.cooldown = 0; g.arms.spin = 1
                    let muzzle = rig.muzzle(), aim = sh.at()
                    g.vrAim = (muzzle, simd_normalize(aim - muzzle))
                    g.fireHeldGun(gi)
                    g.vrAim = nil
                }
            }
            rig.aimAt = aims.last { $0.t0 <= t && t <= $0.t1 }.map { $0.at() }
            // A reach: out over 0.18 s to the cell, back over 0.25 s.
            rig.reach = nil
            for r in reach {
                let u = (t - (r.t - 0.18))
                if u >= 0 && u < 0.43 { rig.reach = (r.at, Float(u < 0.18 ? u / 0.18 : 1 - (u - 0.18) / 0.25)) }
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
            var eye = sample(s.cam, t, camPos), look = sample(s.cam, t, camLook)
            if let h = mount {
                let d = look - eye
                g.player.yaw = atan2f(-d.x, -d.z)
                g.input.keys.insert(KeyBinds.key(.forward))
                for _ in 0..<perFrame {
                    if g.riding !== h { g.riding = h }
                    g.health = 20
                    g.tick(dt); tick += 1
                    calm()
                }
                eye = g.player.eye; look = eye + d
                if f % 30 == 0 { _ = w.loadSync(center: eye, radius: min(w.renderDistance, 6)) }
                if still && f != frames / 2 { continue }
                let dn = simd_normalize(d)
                try rig.shoot(still ? dir + ".png" : String(format: "%@/f%05d.png", dir, f), eye: eye, yaw: atan2f(-dn.x, -dn.z), pitch: asinf(max(-1, min(1, dn.y))))
                continue
            }
            let follows = s.cruise != nil && (s.follow ?? true)
            if follows, let fr = frigate {
                if cruiseFrom == nil { cruiseFrom = fr.pos }
                let off = fr.pos - cruiseFrom!
                eye += off; look += off
            }
            for _ in 0..<perFrame {
                hold(eye)
                for mr in marchers where mr.m.health > 0 {
                    let d = V3(mr.goal.x - mr.m.pos.x, 0, mr.goal.z - mr.m.pos.z), l = simd_length(d)
                    if l > 1.2 {
                        let v = d / l * mr.speed
                        mr.m.vel.x = v.x; mr.m.vel.z = v.z
                        mr.m.yaw = -atan2f(d.x, -d.z)
                    }
                }
                if let fr = frigate {
                    if s.cruise == nil { fr.vel = .zero }
                    fr.angVel = .zero
                }
                g.tick(dt); tick += 1
                calm()
                clearCamera(eye)
            }
            FrigateBoarding.cables.removeAll()      // the boarding winch's line: a play aid, not for the store footage
            // The cruise is posed, not flown: the frigate's own AI steers her on her patrol heading every tick and
            // overwrote the speed set above, so she drifted engine block first (Remington, Nov 1 and Nov 11: "the
            // frigate was moving backwards"). Her bow is local -Z (the drive exhaust streams aft along +Z): a positive
            // cruise carries her bow first at an even speed, her heading as she was spawned.
            if let cr = s.cruise, let fr = frigate {
                if cruiseFrom == nil { cruiseFrom = fr.pos }
                if cruiseRot == nil { cruiseRot = fr.rot }
                let bow = simd_normalize(cruiseRot!.act(V3(0, 0, -1)))
                fr.rot = cruiseRot!; fr.angVel = .zero
                fr.pos = cruiseFrom! + bow * (cr * Float(Double(tick) * dt)); fr.vel = bow * cr
            }
            // The camera rides with the frigate as drawn: its offset from the pose after this frame's ticks.
            if follows, let fr = frigate, let c0 = cruiseFrom {
                eye = sample(s.cam, t, camPos) + (fr.pos - c0); look = sample(s.cam, t, camLook) + (fr.pos - c0)
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
        let half = (sz + 1) / 2
        // the plot cleared first (grass tufts, flowers, a stray branch's leaves over it)
        // (the ground itself only inside the walls: clearing it in the margin round them cut a trench into an uphill
        // plot, a dark slot along the footing in the trailer, Nov 11)
        for y in 1...(h + half + 2) { for z in -1...sz { for x in -1...sx where !w.isAir(o.x + x, o.y + y, o.z + z) {
            let margin = x < 0 || z < 0 || x >= sx || z >= sz
            if margin && (w.solidAt(o.x + x, o.y + y, o.z + z) || w.groundAt(o.x + x, o.y + y, o.z + z)) { continue }
            cells.append((IVec3(o.x + x, o.y + y, o.z + z), AIR))
        } } }
        // footing: a stone course under the whole floor, carried down to firm ground wherever the plot falls away
        for z in 0..<sz { for x in 0..<sx {
            var y = o.y
            while y > o.y - 6 && (y == o.y || !(w.solidAt(o.x + x, y, o.z + z) || w.groundAt(o.x + x, y, o.z + z))) { cells.append((IVec3(o.x + x, y, o.z + z), stone)); y -= 1 }
            cells.append((IVec3(o.x + x, y, o.z + z), stone))
            // ...and two courses on into the ground: the smooth ground rounds off under a course's lower edge on a
            // slope, and the trailer showed a dark slot under the footing there (Nov 11 dissection).
            cells.append((IVec3(o.x + x, y - 1, o.z + z), stone)); cells.append((IVec3(o.x + x, y - 2, o.z + z), stone))
        } }
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
        // (each course a solid slab resting on the one under it, so nothing hangs or falls while it goes up)
        for k in 0..<half {
            for z in k..<max(k + 1, sz - k) { for x in -1...sx {
                let edge = z == k || z == sz - 1 - k || k == half - 1
                let gableEnd = x == -1 || x == sx
                if gableEnd && !edge { continue }                     // the eaves overhang the gables by one; no loose slab ends
                cells.append((IVec3(o.x + x, o.y + h + 1 + k, o.z + z), edge ? roof : plank))
            } }
        }
        _ = w
        return cells
    }

    // One renderer for a shot's frames; each frame drawn once into the left eye (the second eye's view is the same).
    final class Rig {
        let game: Game, scene: SceneRenderer, wr: WorldRenderer, img: VkImg, targets: [RenderTarget], readback: VkBuf
        let width: Int, height: Int, proj: float4x4, far: Float
        var n = 0
        // First person (Shot.hold): the headset's own hand drawing (QuestControls) on scripted controller poses.
        let host: SimHost?, controls: QuestControls?
        var rest = [V3(-0.24, -0.38, -0.36), V3(0.2, -0.32, -0.46)]    // the left and right hands' rest offsets from the eye
        var tilt: Float = 0.18                                          // the held item tipped down from the view (radians)
        var aimAt: V3?                                                  // the right hand pointing its item at this spot
        var reach: (at: V3, k: Float)?                                  // the right hand reaching out toward a spot (k 0...1)
        private var lastHead = simd_quatf(angle: 0, axis: V3(0, 1, 0)), lastEye = V3.zero
        private var aimRot: simd_quatf?
        // Where the right hand's rounds leave from (the last drawn pose's grip, a little ahead along its aim).
        func muzzle() -> V3 {
            let off = rest[1]
            let p = lastEye + lastHead.act(off)
            let d = aimAt.map { simd_normalize($0 - p) } ?? lastHead.act(V3(0, 0, -1))
            return p + d * 0.3
        }
        init(game: Game, ctx: VkContext, width: Int, height: Int, fovDeg: Float, hold: String? = nil) throws {
            self.game = game; self.width = width; self.height = height
            scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
            try scene.uploadTextures()
            wr = WorldRenderer(scene: scene, game: game)
            wr.landmarkHost = Renderer(game: game)
            if let item = hold {
                let h = SimHost(scene: scene)
                let c = QuestControls(app: h, game: game, panel: try HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH))
                h.controls = c
                host = h; controls = c
                wr.extraOpaque = { s, eye in c.drawOpaque(s, eye: eye) }
                game.inventory.selected = 0
                if !item.isEmpty && item != "hands" && Items.has(item) { game.inventory.held = ItemStack(Items.id(item), 1) }
                else {
                    if !item.isEmpty && item != "hands" { print("cine: no item \(item)") }
                    game.inventory.held = .empty                    // empty hands (the creative inventory's first slot showed a grass block)
                }
            } else { host = nil; controls = nil }
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
            lastHead = head; lastEye = eye
            if let sim = host?.sim {
                // The head at the tracking origin looking along the camera; the hands at rest below it, the aiming
                // (right) hand forward, held items pointing a little down. Recentred once so tracking maps onto the eye.
                let headY: Float = 1.62
                sim.headPos = V3(0, headY, 0); sim.headRot = head
                let down = simd_quatf(angle: -tilt, axis: V3(1, 0, 0))
                let t = Float(n) / 30
                let bob = V3(0, 0.008 * sinf(t * 2 * .pi * 1.2), 0)
                // The aiming hand turned (eased) to point at the aim spot: its forward (-Z) along the line from the grip.
                var want: simd_quatf? = nil
                if let a = aimAt {
                    let gp = eye + head.act(rest[1])
                    let d = simd_normalize(a - gp)
                    let yawA = atan2f(-d.x, -d.z), pitA = asinf(max(-1, min(1, d.y)))
                    want = simd_quatf(angle: yawA, axis: V3(0, 1, 0)) * simd_quatf(angle: pitA, axis: V3(1, 0, 0))
                }
                if let w = want { aimRot = aimRot.map { simd_slerp($0, w, 0.35) } ?? simd_slerp(head * down, w, 0.35) }
                else if let r = aimRot { let back = simd_slerp(r, head * down, 0.3); aimRot = simd_length(back.vector - (head * down).vector) < 0.01 ? nil : back }
                for hi in 0..<2 {
                    var hd = XRHand()
                    hd.aimValid = true; hd.gripValid = true
                    var off = rest[hi] + bob
                    var rot = head * down
                    if hi == 1 {
                        if let r = aimRot { rot = r; off.y += 0.05; off.z -= 0.04 }      // raised to aim
                        if let (at, k) = reach {                                    // reaching out to the spot and back
                            let local = head.inverse.act(at - eye)
                            let toward = simd_normalize(local - off)
                            off += toward * (0.3 * k)
                        }
                    }
                    hd.gripPos = sim.headPos + head.act(off); hd.aimPos = hd.gripPos
                    hd.gripRot = rot
                    hd.aimRot = hd.gripRot
                    sim.hands[hi] = hd
                }
                host!.handed.refresh(dt: 1.0 / 30, walk: false)      // the hands as QuestControls reads them
                // The tracking space stands on the camera's own feet: the game's collision can lift the player out of a
                // slope the camera key dips into, and the hands then floated a metre over the view (v3 build shot).
                if game.riding == nil { game.player.pos = eye - V3(0, game.player.eyeHeight, 0) }
                host!.rig.update(xr: sim, game: game)
            }
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
