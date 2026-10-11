import Foundation
import simd

// L1 part 3 trees (docs/status/look-upgrade.md): shape checks on single trees grown into an empty chunk buffer, plus a
// screenshot sheet (`questcheck --render X --tree-shots DIR`). World-wide sanity (floating trunks, orphan leaves) is
// `questcheck --gencheck`.
enum TreeTest {
    static let groundY = YOFF + 4

    // One tree grown at (8, groundY + 1, 8) of a blank chunk on a flat grass floor; the buffer and the seed's shape.
    static func grow(_ kind: TreeKind, seed: UInt64, at: (Int, Int) = (8, 8)) -> [BlockID] {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let grass = Blocks.id("grass_block")
        for z in 0..<CS { for x in 0..<CS { b[Chunk.index(x, groundY, z)] = grass; b[Chunk.index(x, groundY - 1, z)] = DIRT } }
        b.withUnsafeMutableBufferPointer { buf in
            let w = TreeWriter(b: buf.baseAddress!, bx: 0, bz: 0)
            var rng = SRng(seed | 1)
            TreePlacer.build(w, kind, at.0, groundY + 1, at.1, &rng)
        }
        return b
    }

    static func isLog(_ id: BlockID) -> Bool { let k = Blocks.key(id); return k.hasSuffix("_log") || k.hasSuffix("_wood") }

    static func run(check: (Bool, String) -> Void) {
        let leafT = Mesher.leafT
        // Per kind: how many distinct silhouettes 40 seeds give, every log joined to the ground through logs, every
        // leaf within 5 of a log, nothing clipped at the buffer's edge (the 7-block placement margin holds).
        let kinds: [(TreeKind, String, Int)] = [(.oak, "oak", 4), (.birch, "birch", 4), (.spruce, "spruce", 4), (.pine, "pine", 2),
                                                (.deadOak, "dead oak", 2), (.fallenOak, "fallen oak", 2), (.ancientOak, "ancient oak", 2),
                                                (.stumpOak, "stump", 1), (.tallBirch, "tall birch", 3)]
        for (kind, name, wantShapes) in kinds {
            var shapes = Set<Int>(), floating = 0, orphan = 0, clipped = 0, maxH = 0, logs = 0
            for s in 0..<40 {
                let sd = UInt64(s) &* 0x9E37 &+ 77
                // Grown at (8, 8) the buffer shows 8 blocks to -x/-z and 7 to +x/+z; grown again at (7, 7) the other way
                // round: a block on the far edge is past the 7-block placement margin (a neighbour chunk would cut it).
                let b2 = grow(kind, seed: sd, at: (7, 7))
                for y in (groundY + 1)..<CH { for i in 0..<CS where b2[Chunk.index(CS - 1, y, i)] != AIR || b2[Chunk.index(i, y, CS - 1)] != AIR { clipped += 1 } }
                let b = grow(kind, seed: sd)
                var logSet = Set<Int>(), leafs: [(Int, Int, Int)] = []
                var sig = Hasher()
                for y in (groundY + 1)..<CH { for z in 0..<CS { for x in 0..<CS {
                    let id = b[Chunk.index(x, y, z)]
                    if id == AIR { continue }
                    if x == 0 || z == 0 { clipped += 1 }
                    maxH = max(maxH, y - groundY)
                    if isLog(id) { logSet.insert(Chunk.index(x, y, z)); logs += 1; sig.combine(Chunk.index(x, y, z) >> 2) }
                    else if leafT[Int(id)] { leafs.append((x, y, z)) }
                } } }
                // Silhouette: the logs on a coarse grid plus the crown's height and width (two seeds of one shape differ
                // only in leaf noise and a block of height).
                let ys = leafs.map { $0.1 }, xs = leafs.map { $0.0 }
                sig.combine(((ys.max() ?? 0) - (ys.min() ?? 0)) / 2); sig.combine(((xs.max() ?? 0) - (xs.min() ?? 0)) / 2)
                shapes.insert(sig.finalize())
                // Logs joined to the ground: flood from the logs on the floor through face and diagonal neighbours.
                var seen = Set<Int>(), stack: [Int] = []
                for i in logSet where i / CSQ == groundY + 1 { stack.append(i); seen.insert(i) }
                while let i = stack.popLast() {
                    let y = i / CSQ, z = (i % CSQ) / CS, x = i % CS
                    for dy in -1...1 { for dz in -1...1 { for dx in -1...1 {
                        let nx = x + dx, ny = y + dy, nz = z + dz
                        guard nx >= 0, nx < CS, nz >= 0, nz < CS, ny > groundY, ny < CH else { continue }
                        let j = Chunk.index(nx, ny, nz)
                        if logSet.contains(j) && seen.insert(j).inserted { stack.append(j) }
                    } } }
                }
                floating += logSet.count - seen.count
                for (x, y, z) in leafs {
                    var near = false
                    outer: for dy in -5...5 { for dz in -5...5 { for dx in -5...5 {
                        let nx = x + dx, ny = y + dy, nz = z + dz
                        if nx >= 0, nx < CS, nz >= 0, nz < CS, ny > groundY, ny < CH, logSet.contains(Chunk.index(nx, ny, nz)) { near = true; break outer }
                    } } }
                    if !near { orphan += 1 }
                }
            }
            check(shapes.count >= wantShapes && floating == 0 && orphan == 0 && clipped == 0 && logs > 0,
                  "trees: \(name): \(shapes.count) shapes in 40 seeds (want \(wantShapes)+), \(floating) floating logs, \(orphan) leaves far from wood, \(clipped) blocks past the margin, up to \(maxH) tall")
        }
        for (k, c) in LeafCoverage.report() {
            check(c.allSatisfy { $0 >= 0.5 }, "trees: \(k) at \(TextureGen.size) px keeps a full canopy at every mip (cutout cover " + c.map { String(format: "%.2f", $0) }.joined(separator: " ") + ")")
        }
        // The ancient oak is the giant: a 2x2 trunk at least 9 tall.
        let a = grow(.ancientOak, seed: 5)
        let trunk2 = (0..<9).allSatisfy { k in [(8, 8), (9, 8), (8, 9), (9, 9)].allSatisfy { isLog(a[Chunk.index($0.0, groundY + 1 + k, $0.1)]) } }
        check(trunk2, "trees: the ancient oak stands on a 2x2 trunk 9+ tall")
        // A fallen trunk lies on the ground: bark-all-round wood resting on the floor, never on air.
        var lying = 0, hanging = 0
        let wood = Blocks.id("oak_wood")
        for s in 0..<20 {
            let b = grow(.fallenOak, seed: UInt64(s) &* 31 &+ 3)
            for z in 0..<CS { for x in 0..<CS { for y in (groundY + 1)...(groundY + 3) where b[Chunk.index(x, y, z)] == wood {
                if b[Chunk.index(x, y - 1, z)] == AIR { hanging += 1 } else { lying += 1 }
            } } }
        }
        check(lying > 40 && hanging == 0, "trees: fallen trunks lie on the ground (\(lying) lengths, \(hanging) over air)")
        // Woodland litter only where woods grow: the same pick never turns a plains oak into a stump or a fallen log,
        // and some forest picks do; ancient oaks stay rare.
        var plainsLitter = 0, forestLitter = 0, ancient = 0, n = 0
        for i in 0..<4000 {
            let pick = Float(i) / 4000
            if let k = TreePlacer.choose(.plains, 0.001, pick, YOFF + 6), [.deadOak, .stumpOak, .fallenOak].contains(k) { plainsLitter += 1 }
            if let k = TreePlacer.choose(.forest, 0.001, pick, YOFF + 6) {
                n += 1
                if [.deadOak, .stumpOak, .fallenOak, .stumpBirch].contains(k) { forestLitter += 1 }
                if k == .ancientOak { ancient += 1 }
            }
        }
        check(plainsLitter == 0 && forestLitter > n / 50 && forestLitter < n / 5 && ancient > 0 && ancient < n / 40,
              "trees: litter in woods only (forest \(forestLitter) of \(n), plains \(plainsLitter)), ancient oaks rare (\(ancient))")
    }
}

// The screenshot sheet: each group grown in a row on a floating grass pad high over the spawn, at noon.
enum TreeShots {
    static func run(game: Game, ctx: VkContext, dir: String) throws {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = game.player
        let saved = (p.pos, p.flying, game.time, game.mobs.mobs, game.weather)
        defer { (p.pos, p.flying, game.time, game.mobs.mobs, game.weather) = saved; game.mobs.rebuildIndex() }
        p.flying = true
        game.mobs.mobs = []; game.mobs.rebuildIndex()
        game.weather = Weather(); game.weather.rain = 0
        let w = game.world
        let sp = game.findSpawn()
        let groups: [(String, [(TreeKind, UInt64)])] = [
            ("oaks", (0..<6).map { (.oak, UInt64($0 * 13 + 5)) }),
            ("birches", (0..<6).map { (.birch, UInt64($0 * 13 + 5)) }),
            ("spruces", (0..<3).map { (.spruce, UInt64($0 * 13 + 5)) } + (0..<3).map { (.pine, UInt64($0 * 13 + 5)) }),
            ("woodland", [(.deadOak, 3), (.deadSpruce, 4), (.stumpOak, 5), (.fallenOak, 6), (.stumpBirch, 7), (.fallenOak, 9)]),
            ("ancient", [(.oak, 5), (.ancientOak, 3), (.ancientOak, 8), (.fancyOak, 4)]),
        ]
        for (gi, (name, trees)) in groups.enumerated() {
            // Rows far apart (each its own chunks), 64 blocks over the spawn.
            let ox = Int(floor(sp.x)) + gi * 160, oz = Int(floor(sp.z)), oy = Int(floor(sp.y)) + 64
            _ = w.loadSync(center: V3(Float(ox + 30), Float(oy), Float(oz)), radius: 4)
            var edits: [(IVec3, BlockID)] = []
            for (i, (kind, seed)) in trees.enumerated() {
                let b = TreeTest.grow(kind, seed: seed)
                let tx = ox + i * 11
                for y in (TreeTest.groundY - 1)..<min(CH, TreeTest.groundY + 30) { for z in 0..<CS { for x in 0..<CS {
                    let id = b[Chunk.index(x, y, z)]
                    if id != AIR { edits.append((IVec3(tx + x - 8, oy + y - TreeTest.groundY, oz + z - 8), id)) }
                } } }
            }
            for (q, id) in edits { w.setBlockAsync(q.x, q.y, q.z, id) }
            let x1 = ox + trees.count * 11
            w.remeshArea(x0: ox - 10, z0: oz - 10, x1: x1 + 10, z1: oz + 10, y0: oy - 4, y1: oy + 30)
            game.time = 0.22 * DAY_LENGTH
            let target = V3(Float(ox + x1) / 2, Float(oy) + 6, Float(oz))
            let eye = target + V3(0, 4, -Float(trees.count) * 7)
            p.pos = eye - V3(0, p.eyeHeight, 0)
            let f = simd_normalize(target - eye)
            try RenderTest.render(game: game, ctx: ctx, path: "\(dir)/trees_\(name).png", width: 640, height: 360,
                                  yaw: atan2f(-f.x, -f.z), pitch: asinf(f.y), fovDeg: 75)
            for (q, _) in edits { w.setBlockAsync(q.x, q.y, q.z, AIR) }
        }
    }
}

// Leaf textures as the Quest samples them: the share of texels passing the cutout (0.5) at each mip level.
enum LeafCoverage {
    static func report() -> [(String, [Float])] {
        TextureGen.registerAll()
        var out: [(String, [Float])] = []
        for key in ["oak_leaves", "birch_leaves", "spruce_leaves", "jungle_leaves"] {
            let id = Int(Blocks.id(key))
            let layer = Int(Blocks.tex[id * 6 + 2])
            let levels = TextureGen.mipChain(layers: layer..<(layer + 1))
            var cov: [Float] = []
            var n = TextureGen.size
            for d in levels where n >= 1 {
                var pass = 0
                for i in stride(from: 3, to: n * n * 4, by: 4) where d[i] >= 128 { pass += 1 }
                cov.append(Float(pass) / Float(n * n)); n /= 2
            }
            out.append((key, cov))
        }
        return out
    }
}
