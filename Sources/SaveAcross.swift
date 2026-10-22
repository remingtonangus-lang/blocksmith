import Foundation
import Metal
import simd

// P395 (3): a save carried across builds. `questcheck --saveacross write DIR`, built from an older commit, makes a field
// world in DIR and changes it as a player would (blocks placed and broken, ground dug and blasted, water and lava,
// sand falling, a struck object, a train's timetable), saves it and writes DIR/expect.json with what it left; the
// current build's `questcheck --saveacross read DIR` opens the folder as the app does and checks each of them came back.
enum SaveAcross {
    struct Expect: Codable {
        var build = ""
        var field = false
        var cells: [[Int]] = []                 // x, y, z of every block read back
        var keys: [String] = []
        var probes: [[Float]] = []              // points of ground (dug, blasted and untouched round them)
        var dens: [Float] = []
        var pos: [Float] = []
        var sand: [Int] = []                    // x, z, top and bottom of the falling sand's column
        var trainID: Int64 = -1
        var objectID = -1, objectCuts = 0, objectPieces = 0
        var objectVolume: Float = 0
    }
    static let seed: UInt64 = 424243

    static func open(_ device: MTLDevice, _ dir: URL) -> Game {
        let save = SaveManager(dir: dir)
        let meta = save.loadMeta()
        let w = World(seed: seed, device: device, save: save)
        if meta == nil { w.makeFieldWorld() }           // (a new world is a field world, as App.makeGame makes it)
        w.renderDistance = 3
        let g = Game(world: w, save: save, persistent: true)
        if let m = meta { g.apply(m) } else { g.player.pos = g.spawnPoint; g.survival = true }
        _ = w.loadSync(center: g.player.pos, radius: 3)
        return g
    }

    static func run(device: MTLDevice, mode: String, dir path: String) -> Int32 {
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        let expectURL = dir.appendingPathComponent("expect.json")
        if mode == "write" {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let e = write(device, dir)
            guard let d = try? JSONEncoder().encode(e) else { print("saveacross: FAIL expect.json"); return 1 }
            try? d.write(to: expectURL)
            print("saveacross: wrote \(path) (\(e.cells.count) cells, \(e.probes.count) ground points, object \(e.objectID), train \(e.trainID))")
            return 0
        }
        guard let d = try? Data(contentsOf: expectURL), let e = try? JSONDecoder().decode(Expect.self, from: d) else {
            print("saveacross: FAIL no expect.json in \(path)"); return 1
        }
        return read(device, dir, e)
    }

    static func write(_ device: MTLDevice, _ dir: URL) -> Expect {
        var e = Expect()
        e.build = ProcessInfo.processInfo.environment["SAVEACROSS_BUILD"] ?? ""
        var g: Game! = open(device, dir)
        let w = g.world
        e.field = w.fieldTerrain
        let h = g.player.pos
        let hx = Int(floor(h.x)), hz = Int(floor(h.z))
        var touched: [IVec3] = []
        // Blocks placed on the ground and one broken out of the built ones.
        let palette = ["oak_planks", "cobblestone", "glass", "stone_bricks", "chest"].filter { Blocks.has($0) }.map { Blocks.id($0) }
        for k in 0..<10 {
            let x = hx - 4 + k, z = hz - 3
            let y = w.topY(x, z) + 1
            w.setBlock(x, y, z, palette[k % palette.count])
            w.setBlock(x, y + 1, z, palette[(k + 2) % palette.count])
            touched += [IVec3(x, y, z), IVec3(x, y + 1, z)]
        }
        w.setBlock(touched[4].x, touched[4].y, touched[4].z, AIR)
        // Ground dug (a pit), blasted (a crater's shape) and the water and lava poured in their holes.
        let dig = V3(Float(hx + 6) + 0.5, Float(w.topY(hx + 6, hz + 2)), Float(hz + 2) + 0.5)
        let blast = V3(Float(hx - 6) + 0.5, Float(w.topY(hx - 6, hz + 2)) + 0.5, Float(hz + 2) + 0.5)
        let pool = V3(Float(hx) + 0.5, Float(w.topY(hx, hz + 8)), Float(hz + 8) + 0.5)
        w.carve(at: dig, radius: 2.2, mode: .dig)
        w.carve(at: blast, radius: 2.6, mode: .shape)
        w.carve(at: pool, radius: 1.8, mode: .dig)
        let water = IVec3(Int(floor(pool.x)), Int(floor(pool.y)) - 1, Int(floor(pool.z)))
        w.setBlock(water.x, water.y, water.z, Blocks.id("water"))
        let lavaAt = IVec3(Int(floor(dig.x)), Int(floor(dig.y)) - 1, Int(floor(dig.z)))
        w.setBlock(lavaAt.x, lavaAt.y, lavaAt.z, Blocks.id("lava"))
        g.menu = nil; g.paused = false
        for _ in 0..<40 { g.tick(0.05) }
        // Sand let go over the ground beside the spawn, saved while it falls.
        // (over bare ground: not a tree's leaves or a placed block)
        var sx = hx + 3, sz = hz + 5
        search: for r in 0...6 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            let k = Blocks.key(w.block(hx + 3 + dx, w.topY(hx + 3 + dx, hz + 5 + dz), hz + 5 + dz))
            if !k.contains("leaves") && !k.contains("log") && !touched.contains(IVec3(hx + 3 + dx, w.topY(hx + 3 + dx, hz + 5 + dz) + 1, hz + 5 + dz)) {
                sx = hx + 3 + dx; sz = hz + 5 + dz; break search
            }
        } } }
        let top = w.topY(sx, sz) + 9
        for y in (top - 2)...top { w.setBlock(sx, y, sz, Blocks.id("sand")) }
        g.tick(0.05)
        e.sand = [sx, sz, top, w.topY(sx, sz) + 1]
        for dz in -2...2 { for dx in -2...2 { for dy in -2...1 {
            touched.append(water + IVec3(dx, dy, dz)); touched.append(lavaAt + IVec3(dx, dy, dz))
        } } }
        for (c, r) in [(dig, 3), (blast, 3), (pool, 2)] as [(V3, Int)] {
            for dz in -r...r { for dy in -r...r { for dx in -r...r where (dx + dy + dz) & 1 == 0 {
                let p = c + V3(Float(dx), Float(dy), Float(dz))
                e.probes.append([p.x, p.y, p.z]); e.dens.append(w.fieldDensity(at: p))
            } } }
        }
        // >>B (builds with P337 trains and P389 objects)
        let trainID: Int64 = 4_242_424
        Trains.saved[trainID] = Trains.SavedTrain(id: trainID, delay: 37.5, robbedDay: 3, wrecked: true)
        e.trainID = trainID
        var found: WorldObjects.Group? = nil
        World.scanObjects(w, lo: IVec3(hx - 40, 1, hz - 40), hi: IVec3(hx + 40, CH - 2, hz + 40)) { grp, k in
            if found == nil, WorldObjects.kinds.contains(k), ObjectBreakTests.viewpoint(w, grp) != nil { found = grp }
        }
        if let grp = found, let (eye, _, _) = ObjectBreakTests.viewpoint(w, grp) {
            g.survival = true
            g.inventory.held = ItemStack(Items.id(ObjectBreakTests.tool(for: grp.blocks[0])), 1)
            let mid = ObjectBreakTests.middle(grp)
            for k in 0..<3 {
                _ = ObjectBreakTests.strike(g, eye: eye, at: mid + V3(0, Float(k - 1) * 0.18, 0))
                ObjectBreakTests.settle(g, grp, fly: 0)
            }
            if let (id, o) = w.objectReg.objects.first(where: { $0.value.cells.first == grp.cells.first || Set($0.value.cells) == Set(grp.cells) }) {
                e.objectID = id; e.objectCuts = o.cuts.count; e.objectPieces = o.frags.count
                e.objectVolume = o.broken ? 0 : o.volumes(o.frags).reduce(0, +)
            }
            for c in grp.cells { touched.append(c) }
        }
        g.player.pos = h; g.player.vel = .zero; g.player.flying = false
        // <<B
        var seen = Set<IVec3>()
        for c in touched where seen.insert(c).inserted {
            e.cells.append([c.x, c.y, c.z]); e.keys.append(Blocks.key(w.block(c.x, c.y, c.z)))
        }
        e.pos = [g.player.pos.x, g.player.pos.y, g.player.pos.z]
        g.saveNow()
        SaveIO.flush()
        g = nil
        return e
    }

    static func read(_ device: MTLDevice, _ dir: URL, _ e: Expect) -> Int32 {
        var bad: [String] = []
        let g = open(device, dir)
        let w = g.world
        print("saveacross: loaded a save written by \(e.build.isEmpty ? "an older build" : e.build); field world \(w.fieldTerrain) (was \(e.field))")
        if w.fieldTerrain != e.field { bad.append("field world \(w.fieldTerrain), saved \(e.field)") }
        let p = V3(e.pos[0], e.pos[1], e.pos[2])
        if simd_length(g.player.pos - p) > 0.05 { bad.append("player at \(g.player.pos), saved at \(p)") }
        var lost: [String] = []
        for (c, k) in zip(e.cells, e.keys) {
            let now = Blocks.key(w.block(c[0], c[1], c[2]))
            if now != k { lost.append("\(c[0]) \(c[1]) \(c[2]) \(k) -> \(now)") }
        }
        // (water and lava go on flowing after the save: a cell they reached or left is not a lost edit)
        let fluid = lost.filter { $0.contains("water") || $0.contains("lava") }
        let other = lost.filter { !($0.contains("water") || $0.contains("lava")) }
        print("saveacross: blocks: \(e.cells.count - lost.count) of \(e.cells.count) as saved; \(fluid.count) changed by flowing fluid; \(other.count) other")
        for l in other.prefix(8) { print("  changed: \(l)") }
        if !other.isEmpty { bad.append("\(other.count) blocks came back different") }
        var worst: Float = 0, flips = 0
        for (q, d) in zip(e.probes, e.dens) {
            let now = w.fieldDensity(at: V3(q[0], q[1], q[2]))
            worst = max(worst, abs(now - d))
            if (now > 0) != (d > 0) && abs(now - d) > 0.05 { flips += 1 }
        }
        print(String(format: "saveacross: ground: %d points round the pit, the crater and the pool, %d changed side (ground/open), largest density change %.3f", e.probes.count, flips, worst))
        if flips > 0 { bad.append("\(flips) ground points changed side") }
        if e.sand.count == 4 {
            var col: [String] = []
            for y in stride(from: e.sand[2], through: e.sand[3] - 1, by: -1) where w.block(e.sand[0], y, e.sand[1]) != AIR {
                col.append("\(y): \(Blocks.key(w.block(e.sand[0], y, e.sand[1])))")
            }
            print("saveacross: the falling sand's column after the load (saved mid-fall): " + (col.isEmpty ? "empty (the sand was not kept)" : col.joined(separator: ", ")))
            // (builds before P395 saved no falling blocks: their sand is gone, the loader has nothing to restore)
        }
        // >>B
        if e.trainID >= 0 {
            let t = Trains.saved[e.trainID]
            let ok = t != nil && t!.delay == 37.5 && t!.robbedDay == 3 && t!.wrecked
            print("saveacross: train timetable: \(ok ? "as saved" : "LOST (\(String(describing: t)))")")
            if !ok { bad.append("train timetable") }
        }
        if e.objectID >= 0 {
            let reg = w.objectReg
            reg.startLoaded(w)
            reg.waitIdle()
            let res = reg.poll().first { $0.id == e.objectID }
            let o = reg.objects[e.objectID]
            let v = res.map { r in o.map { $0.volumes(r.frags).reduce(0, +) } ?? -1 } ?? -1
            let ok = o != nil && o!.cuts.count == e.objectCuts && res != nil && res!.frags.count == e.objectPieces && abs(v - e.objectVolume) < 1e-3
            print(String(format: "saveacross: struck object %d: %@ (%d cuts, %d pieces, volume %.4f; saved %d cuts, %d pieces, %.4f)", e.objectID, ok ? "as saved" : "DIFFERENT",
                         o?.cuts.count ?? -1, res?.frags.count ?? -1, v, e.objectCuts, e.objectPieces, e.objectVolume))
            if !ok { bad.append("struck object") }
        } else { print("saveacross: no object struck in this save") }
        // <<B
        if e.sand.count == 4 {
            // (then the game runs 3 s, after the object's check: the sand falls on to the ground)
            g.menu = nil; g.paused = false
            for _ in 0..<60 { g.tick(0.05) }
            var after: [String] = []
            for y in stride(from: e.sand[2], through: e.sand[3] - 1, by: -1) where w.block(e.sand[0], y, e.sand[1]) != AIR {
                after.append("\(y): \(Blocks.key(w.block(e.sand[0], y, e.sand[1])))")
            }
            print("saveacross: ... 3 s later: " + after.joined(separator: ", "))
        }
        print(bad.isEmpty ? "saveacross: OK, the save came back as written" : "saveacross: FAIL: " + bad.joined(separator: "; "))
        return bad.isEmpty ? 0 : 1
    }
}
