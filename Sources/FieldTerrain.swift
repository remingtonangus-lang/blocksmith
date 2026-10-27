import Foundation
import simd

// PG1 rewrite (backlog: POLYGON REWRITE REOPENED, Oct 14): in a field world the natural terrain is not a block grid. Each
// chunk keeps a density field, one sample per cell centre (1/32 block, > 0 inside the ground, a signed distance to the
// surface near it), and the ground's material per sample (FieldMat). That field is what is generated, saved, loaded,
// meshed (dual contouring: Mesher.smoothQuads on the stored densities, no block faces), dug and blasted. The chunk's
// block array (BlockStore.data) holds only what is not terrain: built blocks, plants, trees, fluids, structures.
//
// A cell inside the ground reads as its material through every block query (BlockStore's subscript), so mining, drops,
// light, spawning, pathing and the rest of the game see the ground the field describes; writing a block into the ground
// opens the field there, and writing natural ground adds to the field (World.setBlock rounds the shape).
//
// Block worlds (made before the field, or with the block option) never have a field and are unchanged.
struct FieldData {
    var fd: [Int8]
    var fm: [UInt8]
    var fine: [Int: [Int8]] = [:]          // P377 step 1: edited sections' two samples per block (BlockStore.fine)
    var borderSeeds: [Int] = []            // P380 (2): a cell of each small piece that reached the chunk's side
}

// The materials the ground can be made of: every natural ground and rock state (ShapeClass .terrain), index 0 = none.
enum FieldMat {
    static let blocks: [BlockID] = table.0
    static let index: [UInt8] = table.1
    private static let table: ([BlockID], [UInt8]) = {
        var list: [BlockID] = [AIR]
        var idx = [UInt8](repeating: 0, count: Blocks.count)
        for i in 0..<Blocks.count where SmoothTerrain.natural[i] && Blocks.opaque[i] {
            guard list.count < 256 else { break }          // (past 255 a state stays a block in the built layer)
            idx[i] = UInt8(list.count)
            list.append(BlockID(i))
        }
        return (list, idx)
    }()
}

enum FieldTerrain {
    static let scale: Float = 32                         // density units per block
    static let outside: Int8 = -127                      // far outside the ground (and above the stored part)
    static let inside: Int8 = 127                        // far inside
    static let cellIn: Int8 = 16                         // a cell's centre half a block inside (a filled cell)
    static let cellOut: Int8 = -16                       // ...half a block outside (an opened cell)
    @inline(__always) static func q(_ d: Float) -> Int8 { Int8(max(-127, min(127, (d * scale).rounded()))) }
    @inline(__always) static func f(_ v: Int8) -> Float { Float(v) / scale }

    // New Polygons worlds are field worlds (written as a marker in the save: terrain-field.txt); a new world made with
    // block terrain, and every world saved before the field (no marker), stays a block world. `--blockworlds` (tests,
    // before/after measurements) makes new Polygons worlds the old way.
    static var newWorlds = !CommandLine.arguments.contains("--blockworlds")
    // Worlds with no save (harness, tests): `--field` makes them field worlds; a co-op guest takes the host's choice.
    static var unsaved = CommandLine.arguments.contains("--field")

    // Harness (`--fieldstats`): the surface cells split has shaped, by where the distance came from: the generator's own
    // continuous fields, a rule's shape, or rounded from the cells round it.
    static let statsOn = CommandLine.arguments.contains("--fieldstats")
    static let statsLock = NSLock()
    static var stats = [0, 0, 0]
    // The cells rounded from cells, by what made them (harness): beside water, beside lava, ground the generator's field
    // calls open (added: banks, fills), open where it calls ground (carved: ravines, sinkholes, ponds), the rest.
    static var why = [Int](repeating: 0, count: 5)
    // ...and by what the generator's field said there and the cell's block (the commonest are printed).
    static var whyKeys: [String: Int] = [:]
    static func statsLine() -> String {
        statsLock.lock(); defer { statsLock.unlock() }
        let t = max(1, stats.reduce(0, +))
        let r = max(1, why.reduce(0, +))
        func pc(_ k: Int) -> Double { Double(why[k]) * 100 / Double(r) }
        let top = whyKeys.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key) \(Int(Double($0.value) * 100 / Double(r)))%" }
        return String(format: "fieldstats: %d surface cells: %.1f%% generator field, %.1f%% rule shapes, %.1f%% rounded from cells"
                      + " (of those: %.0f%% by water, %.0f%% by lava, %.0f%% added ground, %.0f%% carved, %.0f%% other)",
                      t, Double(stats[0]) * 100 / Double(t), Double(stats[1]) * 100 / Double(t), Double(stats[2]) * 100 / Double(t),
                      pc(0), pc(1), pc(2), pc(3), pc(4)) + "\nfieldstats: rounded cells by cause: " + top.joined(separator: ", ")
    }

    static var keptBuilt: [ChunkKey: Int] = [:]       // (harness, StructureCache.traceKinds)

    // Loose ground (soil, sand, gravel, mud): what a structure lays of it shapes the ground (a garden, a levelled yard, a
    // track) and joins the field; the rock, sandstone, terracotta and snow it builds with stay its blocks.
    static let loose: [Bool] = (0..<Blocks.count).map { i in
        [.dirt, .grass, .sand, .gravel, .mud, .soul].contains(Blocks.def(BlockID(i)).sound)
    }

    // ...of it, what things grow in (soil and turf, not sand or gravel; and moss): P388's gardens on a structure's floor.
    static let gardenSoil: [Bool] = (0..<Blocks.count).map { i in
        [.dirt, .grass].contains(Blocks.def(BlockID(i)).sound) || Blocks.key(Blocks.groupBase[i]) == "moss_block"
    }

    // What the cells read as: the built layer with the ground under it.
    static func merge(_ b: inout [BlockID], _ f: FieldData) {
        let mats = FieldMat.blocks
        for i in 0..<min(b.count, f.fd.count) where b[i] == AIR && f.fd[i] > 0 { b[i] = mats[Int(f.fm[i])] }
    }

    // MARK: Generation

    // The generator's chunk, block by block, becomes the field: every natural ground cell leaves the block array and is
    // ground in the field with its material. The surface's shape comes from the generator's own continuous fields where
    // the overworld has them (the terrain density and the three cave fields, as signed distances: SmoothField), so the
    // ground is the shape the generator meant, not the cells it was rounded to; where a rule of the generator placed or
    // cleared ground on its own (banks, ponds, ravines, dungeons, structures) and in the other dimensions, the distance
    // comes from the ground round the cell (half the cell, half its 3x3x3 neighbourhood). Away from the surface the
    // field is just inside or outside.
    // `built` (StructWriter.mark): cells a structure built; their natural rock stays in the block array (a pyramid's
    // sandstone, a ruin's stone, an igloo's snow are built blocks, not ground).
    // MARK: Carved shapes (WorldGen.generate's `carved` distances)

    // The nearer of a cell's carved distance and d (NaN: none yet).
    @inline(__always) static func carveMin(_ cd: UnsafeMutablePointer<Float>, _ i: Int, _ d: Float) {
        let c = cd[i]
        cd[i] = c.isNaN || d < c ? d : c
    }

    // A carver's rough edge in field worlds: world-stable smooth noise (-0.5...0.5, about 3 blocks across and a finer
    // fifth on top) where the block world rolls a hash per cell, so the walls are rough rock, not cell-sized pits.
    @inline(__always) static func roughEdge(_ x: Int, _ y: Int, _ z: Int, _ salt: UInt32) -> Float {
        let p = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        return DetailMesh.noise(p, 0.33, salt) * 0.4 + DetailMesh.noise(p, 1.1, salt ^ 0x9E37) * 0.1
    }

    // Signed distance (blocks, + outside) from a point at (dx, dy, dz) off an ellipsoid's centre to its surface
    // (horizontal radius r, vertical h, scaled by sqrt(k)): the normalized radius's excess over its gradient.
    @inline(__always) static func ellipsoidDistance(_ dx: Float, _ dy: Float, _ dz: Float, _ r: Float, _ h: Float, _ k: Float) -> Float {
        let ux = dx / (r * r), uy = dy / (h * h), uz = dz / (r * r)
        let e = dx * dx / (r * r) + dy * dy / (h * h) + dz * dz / (r * r)
        let q = e.squareRoot(), t = max(0.05, k).squareRoot()
        guard q > 1e-3 else { return -min(r, h) * t }
        let g = (ux * ux + uy * uy + uz * uz).squareRoot() / q
        return max(-4, min(4, (q - t) / max(g, 1e-4)))
    }

    // P297 (a): moss, mushrooms and the like the generator set on a fallen trunk come off in a field world: the trunk
    // lies on the drawn ground, lower and thinner than its block (ShapeTrunks.timber), and they floated over it.
    static func clearFallenTops(_ b: inout [BlockID]) {
        let trunkT = ShapeTrunks.isTrunk, axisT = ShapeTrunks.axisOf, opaqueT = Blocks.opaque, leafT = Mesher.leafT
        let top = min(CH - 1, b.count / CSQ - 1)
        guard top > 1 else { return }
        for y in 1..<top { for z in 0..<CS { for x in 0..<CS {
            let i = x + z * CS + y * CSQ
            let t = b[i]
            guard t != AIR, !opaqueT[Int(t)], !leafT[Int(t)], !Blocks.isLiquid(t) else { continue }
            let u = b[i - CSQ]
            guard trunkT[Int(u)] else { continue }
            var lying = axisT[Int(u)] != 1
            if !lying && !trunkT[Int(b[i - 2 * CSQ])] {
                if x > 0 && trunkT[Int(b[i - CSQ - 1])] || x < CS - 1 && trunkT[Int(b[i - CSQ + 1])]
                    || z > 0 && trunkT[Int(b[i - CSQ - CS])] || z < CS - 1 && trunkT[Int(b[i - CSQ + CS])] { lying = true }
            }
            if lying { b[i] = AIR }
        } } }
    }

    static func split(_ b: inout [BlockID], cx: Int, cz: Int, gen: TerrainGenerator, built: [UInt8]? = nil, carved: [Float]? = nil,
                      added: [Float]? = nil) -> FieldData {
        let n = CSQ * CH
        var fd = [Int8](repeating: outside, count: n)
        var fm = [UInt8](repeating: 0, count: n)
        let idx = FieldMat.index, looseT = loose, garden = gardenSoil
        var top = 0, kept = 0
        for i in 0..<n {
            let m = idx[Int(b[i])]
            guard m != 0 else { continue }
            if let built, built[i] != 0 && !looseT[Int(b[i])] { kept += 1; continue }
            // P388: soil a structure laid on its own floor (a roof garden, a planter: on a block that stays a block) stays
            // its blocks, as in a block world; as ground it was a small floating piece, taken out from under what grew in it.
            if let built, built[i] != 0, garden[Int(b[i])], i >= CSQ, b[i - CSQ] != AIR, Blocks.collide[Int(b[i - CSQ])] { kept += 1; continue }
            fm[i] = m; fd[i] = inside; b[i] = AIR; top = i
        }
        if StructureCache.traceKinds && kept > 0 {           // (harness: natural rock a structure built, kept as blocks)
            StructureCache.kindsLock.lock(); keptBuilt[ChunkKey(x: cx, z: cz)] = kept; StructureCache.kindsLock.unlock()
        }
        let topY = min(CH - 1, top / CSQ + 1)
        let wg = gen as? WorldGen
        let F: SmoothField? = wg != nil ? SmoothField() : nil
        // The other dimensions' own continuous ground (TerrainGenerator.groundField), made distances by its gradient.
        let G: [Float]? = wg == nil ? gen.groundField(cx: cx, cz: cz) : nil
        func genGround(_ lx: Int, _ y: Int, _ lz: Int, _ i: Int) -> Float? {
            guard let G else { return nil }
            let v = G[i]
            guard !v.isNaN else { return nil }
            func g(_ dx: Int, _ dy: Int, _ dz: Int) -> Float? {
                let x = lx + dx, yy = y + dy, z = lz + dz
                guard x >= 0 && x < CS && z >= 0 && z < CS && yy >= 0 && yy < CH else { return nil }
                let w = G[x + z * CS + yy * CSQ]
                return w.isNaN ? nil : w
            }
            func diff(_ a: Float?, _ b: Float?) -> Float? {
                if let a, let b { return (a - b) * 0.5 }
                if let a { return a - v }
                if let b { return v - b }
                return nil
            }
            guard let gx = diff(g(1, 0, 0), g(-1, 0, 0)), let gy = diff(g(0, 1, 0), g(0, -1, 0)), let gz = diff(g(0, 0, 1), g(0, 0, -1))
            else { return nil }
            let l = (gx * gx + gy * gy + gz * gz).squareRoot()
            return l > 1e-4 ? v / l : nil
        }
        let N = SmoothField.N, NN = SmoothField.NN, SO = (N - 16) / 2
        @inline(__always) func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { fd[x + z * CS + y * CSQ] > 0 }
        var st = [Int](repeating: 0, count: 3)
        for sy in 0..<NSEC {
            let y0 = sy * 16
            if y0 > topY { break }
            let y1 = min(CH - 1, y0 + 15)
            // Uniform rows (with the rows just above and below): nothing to refine unless a border cliff might need it.
            var anySolid = false, anyOpen = false
            for y in max(0, y0 - 1)...min(CH - 1, y1 + 1) {
                for c in 0..<CSQ { if fd[c + y * CSQ] > 0 { anySolid = true } else { anyOpen = true }; if anySolid && anyOpen { break } }
                if anySolid && anyOpen { break }
            }
            if !anySolid { continue }
            if !anyOpen && wg == nil { continue }
            if let F, let g = wg { F.prepare(g, x0: cx * CS - SO, y0: y0 - SO, z0: cz * CS - SO) }
            for y in y0...y1 { for lz in 0..<CS { for lx in 0..<CS {
                let i = lx + lz * CS + y * CSQ
                let s = fd[i] > 0
                var edge = false
                if y > 0 && solid(lx, y - 1, lz) != s { edge = true }
                else if y < CH - 1 && solid(lx, y + 1, lz) != s { edge = true }
                else if lx > 0 && solid(lx - 1, y, lz) != s { edge = true }
                else if lx < CS - 1 && solid(lx + 1, y, lz) != s { edge = true }
                else if lz > 0 && solid(lx, y, lz - 1) != s { edge = true }
                else if lz < CS - 1 && solid(lx, y, lz + 1) != s { edge = true }
                let si = (lx + SO) + (lz + SO) * N + (y - y0 + SO) * NN
                // A cell on the chunk's side: the generator says what the ground beyond it is (a cliff on the border).
                if !edge, let F, lx == 0 || lx == CS - 1 || lz == 0 || lz == CS - 1 {
                    if lx == 0 && F.solid(si - 1) != s { edge = true }
                    else if lx == CS - 1 && F.solid(si + 1) != s { edge = true }
                    else if lz == 0 && F.solid(si - N) != s { edge = true }
                    else if lz == CS - 1 && F.solid(si + N) != s { edge = true }
                }
                guard edge else { continue }
                var d: Float
                // The carvers' own shapes (lava pockets, ravines, sinkholes): the ground is the generator's field with
                // them taken out (the nearer surface of the two).
                let c = carved?[i] ?? .nan, a = added?[i] ?? .nan
                var cg: Float = !c.isNaN && F != nil && y >= 1 ? min(F!.genDistance(si), c) : .nan
                // P297 (c): ground the generator added (boulders): the farther of the ground and the added shape.
                if !a.isNaN, let F, y >= 1 { cg = max(cg.isNaN ? F.genDistance(si) : cg, a) }
                if !cg.isNaN && (cg > 0) == s {
                    d = max(-1.5, min(1.5, cg)); st[0] += 1
                } else if !c.isNaN, F == nil, (c > 0) == s {
                    d = max(-1.5, min(1.5, c)); st[0] += 1
                } else if let F, y >= 1, F.solid(si) == s {
                    d = max(-1.5, min(1.5, F.genDistance(si))); st[0] += 1
                } else if let gd = genGround(lx, y, lz, i), (gd > 0) == s {
                    d = max(-1.5, min(1.5, gd)); st[0] += 1
                } else {
                    st[2] += 1
                    if statsOn {
                        var k = 4
                        func near(_ t: (BlockID) -> Bool) -> Bool {
                            for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                                let x = lx + dx, yy = y + dy, z = lz + dz
                                if x >= 0 && x < CS && z >= 0 && z < CS && yy >= 0 && yy < CH && t(b[x + z * CS + yy * CSQ]) { return true }
                            }
                            return false
                        }
                        if near({ Blocks.fluidKind[Int($0)] == 1 }) { k = 0 }
                        else if near({ Blocks.fluidKind[Int($0)] == 2 }) { k = 1 }
                        else if F != nil { k = s ? 2 : 3 }
                        let gv = G?[i] ?? .nan
                        let src = F != nil ? "gen" : (G == nil ? "nofield" : gv.isNaN ? "cap" : (gv > 0) == s ? "flat" : "sign")
                        let tag = src + (s ? " ground " + Blocks.key(FieldMat.blocks[Int(fm[i])]) : " open " + Blocks.key(b[i]))
                        statsLock.lock(); why[k] += 1; whyKeys[tag, default: 0] += 1; statsLock.unlock()
                    }
                    var cnt = 0, tot = 0
                    for dy in -1...1 { let yy = y + dy; guard yy >= 0 && yy < CH else { continue }
                        for dz in -1...1 { let zz = lz + dz; guard zz >= 0 && zz < CS else { continue }
                            for dx in -1...1 { let xx = lx + dx; guard xx >= 0 && xx < CS else { continue }
                                tot += 1; if solid(xx, yy, zz) { cnt += 1 } } } }
                    let m = Float(cnt) / Float(max(1, tot))
                    d = (0.5 * (s ? 1 : 0) + 0.5 * m - 0.5) * 2
                }
                d = s ? max(d, 0.04) : min(d, -0.04)
                // P338 step 7: what a structure built keeps the ground to its faces. A cell it laid as ground (rail
                // ballast, a levelled yard) is filled to its faces, a cell it built or cleared (a floor, a rail, a room)
                // keeps the ground out to its faces, and ground beside one stops at the shared face: rails sit on their
                // bed and plank floors on flat ground instead of the generator's slope bulging through them.
                if let built {
                    if built[i] != 0 { d = s ? max(d, 0.5) : min(d, -0.5) }
                    else if s {
                        func owned(_ j: Int) -> Bool { built[j] != 0 && fd[j] <= 0 }
                        if y < CH - 1 && owned(i + CSQ) || y > 0 && owned(i - CSQ)
                            || lx > 0 && owned(i - 1) || lx < CS - 1 && owned(i + 1)
                            || lz > 0 && owned(i - CS) || lz < CS - 1 && owned(i + CS) { d = min(d, 0.5) }
                    }
                }
                fd[i] = q(d)
            } } }
        }
        FieldTerrain.holdPools(&b, &fd, &fm, cx: cx, cz: cz)   // P378 step 2: the drawn ground holds each pool
        if statsOn { statsLock.lock(); for k in 0..<3 { stats[k] += st[k] }; statsLock.unlock() }
        if let wg, wg.fieldWorld, built != nil { Railways.shapeBed(wg, &fd, cx: cx, cz: cz) }        // P379 step 3
        var out = FieldData(fd: fd, fm: fm)
        FieldTerrain.dropFloaters(&out)                     // P351 step 3: no small floating ground
        return out
    }

    // MARK: Saving

    // Field file: lzfse("FLD1", u32 cell count, u16 material count, material names (u16 length + utf8), densities (one
    // byte per cell), materials (one byte per cell, an index into the names)). Names keep it valid as the registry grows.
    // P377 step 1: "FLD2" when the chunk has fine sections (edited ground): the same, then u8 section count and per
    // section u8 index + 32^3 samples. A chunk without any is still written as FLD1 (older builds keep reading it).
    static func encode(_ f: FieldData) -> [UInt8]? {
        var map = [UInt8](repeating: 0, count: 256)
        var names: [String] = [""]
        var mats = [UInt8](repeating: 0, count: f.fm.count)
        for i in 0..<f.fm.count {
            let m = Int(f.fm[i])
            if m == 0 { continue }
            if map[m] == 0 { map[m] = UInt8(names.count); names.append(Blocks.saveKey(FieldMat.blocks[m])) }
            mats[i] = map[m]
        }
        var d = Data((f.fine.isEmpty ? "FLD1" : "FLD2").utf8)
        let n = UInt32(f.fd.count)
        d.append(contentsOf: [UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255), UInt8(n >> 24)])
        d.append(contentsOf: [UInt8(names.count & 255), UInt8(names.count >> 8)])
        for name in names {
            let u = Array(name.utf8)
            d.append(contentsOf: [UInt8(u.count & 255), UInt8(u.count >> 8)])
            d.append(contentsOf: u)
        }
        f.fd.withUnsafeBytes { d.append(contentsOf: $0) }
        d.append(contentsOf: mats)
        if !f.fine.isEmpty {
            let keys = f.fine.keys.sorted().filter { $0 >= 0 && $0 < 256 && f.fine[$0]!.count == FineField.count }
            d.append(UInt8(keys.count))
            for k in keys { d.append(UInt8(k)); f.fine[k]!.withUnsafeBytes { d.append(contentsOf: $0) } }
        }
        guard let c = try? (d as NSData).compressed(using: .lzfse) as Data else { return nil }
        return [UInt8](c)
    }

    static func decode(_ bytes0: [UInt8]) -> FieldData? {
        guard let raw = try? (Data(bytes0) as NSData).decompressed(using: .lzfse) as Data else { return nil }
        let b = [UInt8](raw)
        guard b.count >= 10, b[0] == 0x46, b[1] == 0x4C, b[2] == 0x44, b[3] == 0x31 || b[3] == 0x32 else { return nil }
        let v2 = b[3] == 0x32
        var p = 4
        func u16() -> Int { defer { p += 2 }; return p + 1 < b.count ? Int(b[p]) | Int(b[p + 1]) << 8 : 0 }
        let n = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
        p = 8
        guard n > 0 && n <= CSQ * CH && n % BlockStore.section == 0 else { return nil }
        let nn = u16()
        var pal = [UInt8](repeating: 0, count: max(1, nn))
        for k in 0..<nn {
            let len = u16()
            guard p + len <= b.count else { return nil }
            let name = String(decoding: b[p..<(p + len)], as: UTF8.self)
            p += len
            if k > 0, let id = SaveMigration.blockID(name) { pal[k] = FieldMat.index[Int(id)] }
        }
        guard v2 ? b.count - p > n * 2 : b.count - p == n * 2 else { return nil }
        var fine: [Int: [Int8]] = [:]
        if v2 {
            var q = p + n * 2
            let k = Int(b[q]); q += 1
            guard b.count - q == k * (1 + FineField.count) else { return nil }
            for _ in 0..<k {
                let sy = Int(b[q]); q += 1
                fine[sy] = b[q..<(q + FineField.count)].map { Int8(bitPattern: $0) }
                q += FineField.count
            }
        }
        var fd = [Int8](repeating: 0, count: n), fm = [UInt8](repeating: 0, count: n)
        for i in 0..<n { fd[i] = Int8(bitPattern: b[p + i]) }
        for i in 0..<n {
            let k = Int(b[p + n + i])
            fm[i] = k < pal.count ? pal[k] : 0
            if fm[i] == 0 && fd[i] > 0 { fd[i] = cellOut }         // a material this build doesn't know: open
        }
        return FieldData(fd: fd, fm: fm, fine: fine)
    }
}

extension SaveManager {
    func groundURL(_ k: ChunkKey) -> URL { chunkDir.appendingPathComponent("t.\(k.x).\(k.z).lz") }

    // The chunk's saved field, or nil (none saved: a block world's chunk, or a field file lost: the caller regenerates).
    func loadField(_ k: ChunkKey) -> FieldData? {
        if let queued = SaveIO.pendingStore(chunkURL(k).path) { return queued.isField ? queued.field : nil }
        guard let d = try? Data(contentsOf: groundURL(k)) else { return nil }
        guard let f = FieldTerrain.decode([UInt8](d)) else {
            SaveIO.quarantine(groundURL(k), what: "ground of the world (chunk \(k.x), \(k.z))")
            return nil
        }
        return f
    }

    func saveField(_ k: ChunkKey, _ f: FieldData) {
        guard let c = FieldTerrain.encode(f) else { SaveIO.report("Couldn't pack the ground of chunk \(k.x), \(k.z) for saving"); return }
        SaveIO.store(Data(c), to: groundURL(k))
    }

    // A world marker that is only read (never written).
    func hasMarker(_ marker: String) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) }
}

// MARK: The generator's field chunk

// A field world's chunk as the generator makes it: the ground as its density field and its materials, and what is
// built on and in it as blocks (structures, trees, plants, fluids), with the structures' containers and mobs.
struct FieldChunk {
    var built: [BlockID]
    var ground: FieldData
    var entities: [(IVec3, BlockEntity)]
    var mobs: [(String, V3)]
}

extension TerrainGenerator {
    // PG1 rewrite: the generator lays its chunk down (terrain, caves, ores, fluids, trees), its structures are built into
    // it (marked, so their stone stays blocks), and the ground leaves the cells for the field: shaped by the
    // generator's own continuous fields (FieldTerrain.split), never kept as cells.
    func generateField(cx: Int, cz: Int) -> FieldChunk {
        var b: [BlockID]
        var carved: [Float]? = nil, added: [Float]? = nil
        if let wg = self as? WorldGen {
            var cd = [Float](repeating: .nan, count: CSQ * CH)
            var ad = [Float](repeating: .nan, count: CSQ * CH)
            b = cd.withUnsafeMutableBufferPointer { c in ad.withUnsafeMutableBufferPointer { a in
                wg.generate(cx: cx, cz: cz, carved: c.baseAddress, added: a.baseAddress) } }
            carved = cd; added = ad
        } else { b = fieldBlocks(cx: cx, cz: cz) }
        var mark = [UInt8](repeating: 0, count: b.count)
        var ents: [(IVec3, BlockEntity)] = [], mobs: [(String, V3)] = []
        if let st = structures {
            (ents, mobs) = mark.withUnsafeMutableBufferPointer { m in st.place(into: &b, cx: cx, cz: cz, mark: m.baseAddress) }
        }
        ents += World.orphanEntities(b, ChunkKey(x: cx, z: cz), have: ents)
        _ = PlantSupport.dropFloating(&b)
        FieldTerrain.clearFallenTops(&b)
        WorldGen.settleGrass(&b)                            // (P474: no grass left to die under what covers it)
        let ground = FieldTerrain.split(&b, cx: cx, cz: cz, gen: self, built: mark, carved: carved, added: added)
        return FieldChunk(built: b, ground: ground, entities: ents, mobs: mobs)
    }
}

// MARK: The field in the world

extension World {
    // The ground's density at a cell (blocks, + inside); -4 outside the loaded field world (and in block worlds).
    @inline(__always) func fieldDensity(_ x: Int, _ y: Int, _ z: Int) -> Float {
        if y < 0 { return 4 }
        if y >= CH { return -4 }
        guard let c = chunkAt(x, z), c.blocks.isField else { return -4 }
        return FieldTerrain.f(c.blocks.density(Chunk.index(mod(x, CS), y, mod(z, CS))))
    }

    // The ground's density at a point (blocks, + inside): trilinear between the eight cell centres round it, or between
    // the fine samples where the ground was edited (P377 step 1, FineField.swift).
    func fieldDensity(at p: V3) -> Float { fineNear(p) ? fineDensity(at: p) : coarseDensity(at: p) }

    // ...from the cells alone.
    func coarseDensity(at p: V3) -> Float {
        let qx = p.x - 0.5, qy = p.y - 0.5, qz = p.z - 0.5
        let x0 = Int(floor(qx)), y0 = Int(floor(qy)), z0 = Int(floor(qz))
        let tx = qx - Float(x0), ty = qy - Float(y0), tz = qz - Float(z0)
        let c000 = fieldDensity(x0, y0, z0), c100 = fieldDensity(x0 + 1, y0, z0)
        let c010 = fieldDensity(x0, y0 + 1, z0), c110 = fieldDensity(x0 + 1, y0 + 1, z0)
        let c001 = fieldDensity(x0, y0, z0 + 1), c101 = fieldDensity(x0 + 1, y0, z0 + 1)
        let c011 = fieldDensity(x0, y0 + 1, z0 + 1), c111 = fieldDensity(x0 + 1, y0 + 1, z0 + 1)
        let a = c000 + (c100 - c000) * tx, b = c010 + (c110 - c010) * tx
        let c = c001 + (c101 - c001) * tx, d = c011 + (c111 - c011) * tx
        let e = a + (b - a) * ty, f = c + (d - c) * ty
        return e + (f - e) * tz
    }

    // Shapes the field round a cell after setBlock changed it (field worlds): ground opened there (dug, blasted, built
    // into) leaves a round hollow, ground placed there a round lump. Only the field's distances move; the cell's own
    // solidity was already set by the write.
    func fieldShape(_ x: Int, _ y: Int, _ z: Int, opened: Bool) {
        let ctr = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        // (An opened cell is a ball 0.8 across its middle: a shaft dug a cell at a time leaves the body room at the cells'
        // floors and ceilings, where 0.72 squeezed it to 0.3 from the middle.)
        fieldSphere(ctr, radius: opened ? 0.8 : 0.62, carve: opened, material: nil, keepCell: IVec3(x, y, z))
    }

    // Subtracts (carve) or adds a sphere to the field: d = min(d, |p - c| - r) or max(d, r - |p - c|). Cells whose
    // solidity flips are written through the block layer (so the game sees them open or filled); a fill takes
    // `material` (or the commonest ground round it). Sections touched are remeshed by the caller's setBlock or here.
    @discardableResult
    // `keepSolid`: only the surface moves (a blast's bowl walls, a bullet's dent): no cell turns from ground to open or
    // back, so nothing is removed without its drop.
    func fieldSphere(_ ctr: V3, radius r: Float, carve: Bool, material: UInt8?, keepCell: IVec3? = nil, keepSolid: Bool = false,
                     remesh: Bool = false) -> [IVec3] {
        var flipped: [IVec3] = []
        let outerBox = changeBox                                    // (P440: this sphere's changes measured)
        changeBox = (IVec3(Int.max, Int.max, Int.max), IVec3(Int.min, Int.min, Int.min))
        let prepared = prepareFine(ctr, radius: r)                  // P377 step 1 (FineField.swift)
        let reach = Int(ceil(r + 1.5))
        let cxI = Int(floor(ctr.x)), cyI = Int(floor(ctr.y)), czI = Int(floor(ctr.z))
        var touched: [(Chunk, Int)] = []
        for y in max(0, cyI - reach)...min(CH - 1, cyI + reach) {
            for z in (czI - reach)...(czI + reach) {
                for x in (cxI - reach)...(cxI + reach) {
                    guard let c0 = chunkAt(x, z) else { continue }
                    let c = c0.hollow || !c0.cacheDropped ? editing(c0) : c0          // P376 (a shell refilled; its cached meshes stale)
                    guard c.blocks.isField else { continue }
                    let p = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                    let dist = simd_length(p - ctr)
                    let i = Chunk.index(mod(x, CS), y, mod(z, CS))
                    let d0 = FieldTerrain.f(c.blocks.density(i))
                    let d1 = carve ? min(d0, dist - r) : max(d0, r - dist)
                    var q = FieldTerrain.q(d1)
                    let was = d0 > 0
                    // Bedrock and the Wardstone stay ground, but their surface gives way a little to a hollow beside them
                    // (left whole, a cell dug out next to them kept a wall of their full density round the body: the
                    // playthrough's miner, stood in a dug cell at the bottom of the world, was shoved out every tick).
                    let unbreakable = carve && was && Blocks.hardness[Int(FieldMat.blocks[Int(c.blocks.material(i))])] < 0
                    if unbreakable { q = max(q, 8) }
                    if keepSolid && was != (q > 0) { q = was ? 1 : -1 }
                    if q == c.blocks.density(i) { continue }
                    let now = q > 0
                    if let k = keepCell, k.x == x && k.y == y && k.z == z && was != now { continue }   // (setBlock decided it)
                    if was != now {
                        if now && c.blocks.raw(i) != AIR { continue }      // a fill never swallows a built block
                        let m = material ?? fieldNeighbourMaterial(x, y, z)
                        c.blocks.setDensity(i, now ? max(q, 1) : min(q, -1), material: now ? m : nil, follow: false)
                        flipped.append(IVec3(x, y, z))
                        c.modified = true
                        c.recomputeHeight(mod(x, CS), mod(z, CS))
                    } else {
                        c.blocks.setDensity(i, q, material: nil, follow: false)
                        c.modified = true
                    }
                    noteChange(x, y, z)
                    let sy = y >> 4
                    if !touched.contains(where: { $0.0 === c && $0.1 == sy }) { touched.append((c, sy)) }
                }
            }
        }
        if !prepared.isEmpty {
            for (c, sy) in fineSphere(ctr, radius: r, carve: carve, prepared: prepared) {
                c.modified = true
                if !touched.contains(where: { $0.0 === c && $0.1 == sy }) { touched.append((c, sy)) }
            }
        }
        // A changed sample moves the surface in the dual cells round it: the sections on either side of a border remesh.
        var all: [(Chunk, Int)] = []
        for (c, sy) in touched {
            for dz in -1...1 { for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { continue }
                for s in max(0, sy - 1)...min(NSEC - 1, sy + 1) where !all.contains(where: { $0.0 === n && $0.1 == s }) { all.append((n, s)) }
            } }
        }
        for (n, s) in all { n.sections[s].version += 1 }
        let box = changeBox!
        changeBox = outerBox
        if box.lo.x <= box.hi.x { noteChange(box.lo.x, box.lo.y, box.lo.z); noteChange(box.hi.x, box.hi.y, box.hi.z) }
        // P440 (Oct 24 20:55, "a five hundred millisecond freeze every time I place a block"): the frame remeshes only the
        // sections within a cell of a sample the sphere changed (the dual cells round it), usually one, not the up to 27
        // round every touched section; the others follow on a worker ahead of the queue (World.update's edited-chunk
        // pass), as the light round an edit always has.
        if remesh && !deferRemesh && box.lo.x <= box.hi.x {
            for (n, s) in all where World.near(n, s, box, grow: 1) { remeshSync(n, s) }
        }
        fieldStamp &+= 1
        if carve && !flipped.isEmpty && !collapsing { collapseQueue.append((IVec3(cxI, cyI, czI), min(6, Int(ceil(r)) + 1))) }   // P351 (GroundCollapse)
        return flipped
    }

    // The commonest ground material among the six cells round a cell (a fill that names none).
    func fieldNeighbourMaterial(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        var best: UInt8 = FieldMat.index[Int(DIRT)], n = 0
        var seen: [(UInt8, Int)] = []
        for (dx, dy, dz) in [(0, -1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, 1, 0)] {
            guard y + dy >= 0 && y + dy < CH, let c = chunkAt(x + dx, z + dz) else { continue }
            let i = Chunk.index(mod(x + dx, CS), y + dy, mod(z + dz, CS))
            guard c.blocks.ground(i) else { continue }
            let m = c.blocks.material(i)
            if let k = seen.firstIndex(where: { $0.0 == m }) { seen[k].1 += 1 } else { seen.append((m, 1)) }
        }
        for (m, c) in seen where c > n { best = m; n = c }
        return best
    }

    // MARK: Collision (PG2 rewrite)

    // Might the field's ground reach into cell (x, y, z) (local index i in chunk c)? It or one of its six neighbours is
    // inside the ground.
    @inline(__always) func fieldNear(_ c: Chunk, _ x: Int, _ y: Int, _ z: Int, _ i: Int) -> Bool {
        let st = c.blocks
        guard st.isField else { return false }
        if st.ground(i) || (y > 0 && st.ground(i - CSQ)) || (y < CH - 1 && st.ground(i + CSQ)) { return true }
        let lx = i & 15, lz = (i >> 4) & 15
        if lx > 0 { if st.ground(i - 1) { return true } } else if let n = chunkAt(x - 1, z), n.blocks.ground(i + 15) { return true }
        if lx < 15 { if st.ground(i + 1) { return true } } else if let n = chunkAt(x + 1, z), n.blocks.ground(i - 15) { return true }
        if lz > 0 { if st.ground(i - CS) { return true } } else if let n = chunkAt(x, z - 1), n.blocks.ground(i + 15 * CS) { return true }
        if lz < 15 { if st.ground(i + CS) { return true } } else if let n = chunkAt(x, z + 1), n.blocks.ground(i - 15 * CS) { return true }
        return false
    }

    // The field's ground inside cell (x, y, z) as collision boxes: the cell in 4 x 4 quarter-block columns, each solid
    // from the lowest to the highest point of its centre line where the field (trilinear between cell centres, as the
    // mesh draws it) is inside the ground. A buried cell is one box; under open air the columns' tops follow the drawn
    // slope to within an eighth of a block, so bodies stand on the surface they see. Cached per cell (fieldStamp).
    func fieldBoxes(_ x: Int, _ y: Int, _ z: Int, _ out: inout [(V3, V3)]) {
        let key = (x & 0xFFFFF) | ((z & 0xFFFFF) << 20) | ((y & 0x3FF) << 40) | ((fieldStamp & 0x1FFF) << 50)
        let slot = Int(UInt(bitPattern: key &* -0x61C8864680B583EB) >> 53)
        let base = slot * 32
        if fieldColKey[slot] != key, FineField.enabled, let fc = chunkAt(x, z), !fc.blocks.fine.isEmpty,
           fineNear(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)) {
            fieldColKey[slot] = key
            fieldColVal.withUnsafeMutableBufferPointer { fineColumns(x, y, z, $0.baseAddress! + base) }      // P377 step 1
        }
        if fieldColKey[slot] != key {
            fieldColKey[slot] = key
            withUnsafeTemporaryAllocation(of: Float.self, capacity: 27) { D in
                for dz in -1...1 { for dx in -1...1 {
                    let c = chunkAt(x + dx, z + dz)
                    for dy in -1...1 {
                        let yy = y + dy
                        var d: Float
                        if yy < 0 { d = 4 } else if yy >= CH { d = -4 }
                        else if let c, c.blocks.isField { d = FieldTerrain.f(c.blocks.density(Chunk.index(mod(x + dx, CS), yy, mod(z + dz, CS)))) }
                        else { d = -4 }
                        D[(dx + 1) + (dz + 1) * 3 + (dy + 1) * 9] = d
                    }
                } }
                for v in 0..<4 { for u in 0..<4 {
                    let px = (Float(u) + 0.5) / 4 - 0.5, pz = (Float(v) + 0.5) / 4 - 0.5
                    let ix = px < 0 ? 0 : 2, iz = pz < 0 ? 0 : 2
                    let wx = abs(px), wz = abs(pz)
                    func lv(_ l: Int) -> Float {
                        let o = l * 9
                        let a = D[1 + 3 + o] * (1 - wx) + D[ix + 3 + o] * wx
                        let b = D[1 + iz * 3 + o] * (1 - wx) + D[ix + iz * 3 + o] * wx
                        return a * (1 - wz) + b * wz
                    }
                    let dm = lv(0), d0 = lv(1), dp = lv(2)
                    let v0 = (dm + d0) * 0.5, v1 = d0, v2 = (d0 + dp) * 0.5      // at the cell's bottom, middle, top
                    var lo: Float = -1, hi: Float = -1
                    if v0 > 0 { lo = 0 } else if v1 > 0 { lo = 0.5 * v0 / (v0 - v1) } else if v2 > 0 { lo = 0.5 + 0.5 * v1 / (v1 - v2) }
                    if v2 > 0 { hi = 1 } else if v1 > 0 { hi = 0.5 + 0.5 * v1 / (v1 - v2) } else if v0 > 0 { hi = 0.5 * v0 / (v0 - v1) }
                    let k = base + (u + v * 4) * 2
                    fieldColVal[k] = lo; fieldColVal[k + 1] = hi
                } }
            }
        }
        var full = true
        for k in 0..<16 where fieldColVal[base + k * 2] != 0 || fieldColVal[base + k * 2 + 1] != 1 { full = false; break }
        let o = V3(Float(x), Float(y), Float(z))
        if full { out.append((o, o + 1)); return }
        for v in 0..<4 {
            var u = 0
            while u < 4 {
                let k = base + (u + v * 4) * 2
                let lo = fieldColVal[k], hi = fieldColVal[k + 1]
                var u1 = u + 1
                while u1 < 4 && fieldColVal[base + (u1 + v * 4) * 2] == lo && fieldColVal[base + (u1 + v * 4) * 2 + 1] == hi { u1 += 1 }
                if lo >= 0 && hi - lo > 0.01 {
                    out.append((o + V3(Float(u) * 0.25, lo, Float(v) * 0.25), o + V3(Float(u1) * 0.25, hi, Float(v + 1) * 0.25)))
                }
                u = u1
            }
        }
    }

    // Harness (`--view ... --field --fieldwalk`): the player dropped at the view spot walks 4 s along each of 8 headings
    // from there; reports how far the feet stood from the field's surface under them and the headings that stalled.
    static func fieldWalkCheck(_ g: Game) -> String {
        let w = g.world
        let start = g.player.pos
        var worst: Float = 0, sum: Float = 0, signed: Float = 0, n = 0, stalls = 0, travelled: Float = 0
        func surface(_ p: V3) -> Float? {
            var y = p.y + 1.2, prev = w.fieldDensity(at: V3(p.x, y, p.z))
            if prev > 0 { return nil }
            while y > p.y - 1.2 {
                let d = w.fieldDensity(at: V3(p.x, y - 0.05, p.z))
                if d > 0 { return y - 0.05 * prev / (prev - d) }
                prev = d; y -= 0.05
            }
            return nil
        }
        for k in 0..<8 {
            g.player.pos = start; g.player.vel = .zero; g.player.flying = false
            g.player.yaw = Float(k) * .pi / 4
            for _ in 0..<60 { g.player.update(dt: 1.0 / 30, input: MoveInput(), world: w) }
            let p0 = g.player.pos
            for f in 0..<120 {
                g.player.update(dt: 1.0 / 30, input: MoveInput(forward: 1), world: w)
                if f % 3 == 0, g.player.onGround, !w.solidAt(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.y - 0.3)), Int(floor(g.player.pos.z))) || w.fieldNear(g.player.pos),
                   let s = surface(g.player.pos) {
                    let gap = g.player.pos.y - s
                    worst = max(worst, abs(gap)); sum += abs(gap); signed += gap; n += 1
                }
            }
            let moved = simd_length(V2(g.player.pos.x - p0.x, g.player.pos.z - p0.z))
            travelled += moved
            if moved < 6 { stalls += 1 }
        }
        g.player.pos = start
        return String(format: "fieldwalk: %d samples, mean |gap| %.3f (signed %.3f), worst %.3f; %.1f blocks walked, %d of 8 headings stalled",
                      n, sum / Float(max(1, n)), signed / Float(max(1, n)), worst, travelled, stalls)
    }

    // PG2 rewrite (harness, --fieldbodies): animals and dropped items let fall onto the field ground round the player,
    // run for five seconds through their own updates; each one as drawn (its position and eased view offset) against the
    // drawn surface under its middle. Nothing should sink or hover by more than an eighth of a block.
    static func fieldBodiesCheck(_ g: Game) -> String {
        let w = g.world
        // The first entry into the ground going down a column from y0 (0.1 steps, then the linear crossing).
        func surface(_ x: Float, _ z: Float, from y0: Float, to y1: Float) -> Float? {
            var y = y0, prev = w.fieldDensity(at: V3(x, y, z))
            while y > y1 {
                let d = w.fieldDensity(at: V3(x, y - 0.1, z))
                if d > 0 && prev <= 0 { return y - 0.1 * prev / (prev - d) }
                prev = d; y -= 0.1
            }
            return nil
        }
        let kinds: [MobKind] = [.cow, .sheep, .pig, .chicken]
        var mobs: [Mob] = [], items: [ItemEntity] = []
        let c = g.player.pos
        for k in 0..<16 {
            let a = Float(k) * .pi / 8, r: Float = 4 + Float(k % 4) * 2
            let x = c.x + cosf(a) * r, z = c.z + sinf(a) * r
            // On the open ground (the view spot can be inside a hill or a cave: --at's default height).
            let top = Float(w.gen.column(Int(floor(x)), Int(floor(z))).height)
            guard let s = surface(x, z, from: top + 8, to: top - 8) else { continue }
            let m = Mob(kinds[k % kinds.count], at: V3(x, s + 1, z))
            m.persistent = true
            g.mobs.mobs.append(m); mobs.append(m)
            let e = ItemEntity(ItemStack(Items.id("cobblestone"), 1), at: V3(x + 0.6, s + 1.2, z - 0.6), vel: .zero, delay: 999)
            g.drops.items.append(e); items.append(e)
        }
        let verbose = ProcessInfo.processInfo.environment["FIELDBODIES_VERBOSE"] != nil
        let spawnY = mobs.map { $0.pos.y }
        var hist = [[String]](repeating: [], count: mobs.count), told = [Bool](repeating: false, count: mobs.count)
        for t in 0..<150 {
            g.mobs.update(1.0 / 30, game: g)
            _ = g.drops.update(1.0 / 30, game: g)
            guard verbose else { continue }
            // A body that drops well under where it was put (into the ground): its last ticks and the column it fell through.
            for (k, m) in mobs.enumerated() {
                let p = m.pos
                hist[k].append(String(format: "t%d %.2f %.2f %.2f vel %.2f gnd %@ d %.2f", t, p.x, p.y, p.z, m.vel.y, m.onGround ? "1" : "0",
                                      w.fieldDensity(at: p + V3(0, 0.05, 0))))
                if hist[k].count > 8 { hist[k].removeFirst() }
                guard !told[k] && p.y < spawnY[k] - 4 else { continue }
                told[k] = true
                var col: [String] = []
                var y = spawnY[k] + 1, prev = w.fieldDensity(at: V3(p.x, y, p.z))
                while y > p.y - 2 {
                    let d = w.fieldDensity(at: V3(p.x, y - 0.25, p.z))
                    if (d > 0) != (prev > 0) { col.append(String(format: "%@ at %.2f", d > 0 ? "in" : "out", y - 0.25)) }
                    prev = d; y -= 0.25
                }
                print("fieldbodies: \(m.kind.key) fell from \(spawnY[k]): " + hist[k].joined(separator: "; ") + "\n  column: " + col.joined(separator: ", "))
            }
        }
        var n = 0, sunk = 0, hover = 0, airborne = 0, other = 0
        var sum: Float = 0, worst: Float = 0, rest: Float = 0
        // Resting on something built or in water (a log, leaves, a pond) is not the field's to judge.
        func onField(_ p: V3) -> Bool {
            for dy: Float in [0.1, -0.2, -0.7] {
                let x = Int(floor(p.x)), y = Int(floor(p.y + dy)), z = Int(floor(p.z))
                guard y >= 0 && y < CH, let c = w.chunkAt(x, z) else { continue }
                let r = c.blocks.raw(Chunk.index(mod(x, CS), y, mod(z, CS)))
                if Blocks.collide[Int(r)] || Blocks.isLiquid(r) { return false }
            }
            return true
        }
        func score(_ p: V3, _ viewDY: Float, _ ground: Bool, _ what: String, _ vel: V3) {
            let s = surface(p.x, p.z, from: p.y + 1, to: p.y - 1.5)
            if verbose {
                print(String(format: "fieldbodies: %@ at %.2f %.2f %.2f vel %.2f %.2f %.2f %@, drawn %+.2f, surface under it ", what, p.x, p.y, p.z,
                             vel.x, vel.y, vel.z, ground ? "on ground" : "in the air", viewDY) + (s.map { String(format: "%.2f", $0) } ?? "none"))
            }
            guard onField(p) else { other += 1; return }
            guard ground else { airborne += 1; return }
            guard let s else { return }
            let gap = p.y + viewDY - s
            n += 1; sum += abs(gap); worst = max(worst, abs(gap)); rest += abs(p.y - s)
            if gap < -0.125 { sunk += 1 } else if gap > 0.125 { hover += 1 }
        }
        for m in mobs where g.mobs.mobs.contains(where: { $0 === m }) { score(m.pos, m.viewDY, m.onGround, m.kind.key, m.vel) }
        for e in items where g.drops.items.contains(where: { $0 === e }) { score(e.pos, e.viewDY, e.onGround, "item", e.vel) }
        return String(format: "fieldbodies: %d animals, %d items; %d resting on the field: drawn mean |gap| %.3f, worst %.3f (bodies %.3f); %d sunk, %d hovering, %d still falling; %d in water or on built blocks",
                      mobs.count, items.count, n, sum / Float(max(1, n)), worst, rest / Float(max(1, n)), sunk, hover, airborne, other)
    }
}

extension World {
    // Is the cell under a point inside or beside the field's ground? (harness)
    func fieldNear(_ p: V3) -> Bool {
        let x = Int(floor(p.x)), y = Int(floor(p.y - 0.3)), z = Int(floor(p.z))
        guard y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
        return fieldNear(c, x, y, z, Chunk.index(mod(x, CS), y, mod(z, CS)))
    }

    // MARK: Carving (PG1 rewrite: digging, blasts and rounds subtract shapes from the field)

    // World.carve in a field world: a ball subtracted from the field. .dig takes every ground cell whose centre the ball
    // reaches (`remove` sees each first: drops, debris), .shape and .dent only move the surface inside the cells (a
    // blast's bowl after its rays broke what they broke; a round's mark). Returns the cells removed.
    func fieldCarve(at c: V3, radius r: Float, mode: CarveMode, remove: ((IVec3, BlockID) -> Void)?) -> Int {
        guard r > 0.05 else { return 0 }
        if mode == .dig, let remove {
            let reach = Int(ceil(r))
            let cx = Int(floor(c.x)), cy = Int(floor(c.y)), cz = Int(floor(c.z))
            for y in max(0, cy - reach)...min(CH - 1, cy + reach) { for z in (cz - reach)...(cz + reach) { for x in (cx - reach)...(cx + reach) {
                let p = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                guard let ch = chunkAt(x, z) else { continue }
                let i = Chunk.index(mod(x, CS), y, mod(z, CS))
                guard ch.blocks.ground(i), simd_length(p - c) < r else { continue }
                let b = ch.blocks[i]
                if Blocks.hardness[Int(b)] < 0 { continue }
                remove(IVec3(x, y, z), b)
            } } }
        }
        let flipped = fieldSphere(c, radius: mode == .dent ? r * 0.8 : r, carve: true, material: nil, keepSolid: mode != .dig)
        for p in flipped {
            if !damage.isEmpty { damage.removeValue(forKey: p) }
            queueSupportChecks(p.x, p.y, p.z, STONE, AIR)
            scheduleFluid(around: p)
        }
        return flipped.count
    }

    // MARK: Rays (PG2 rewrite)

    // Where a ray first enters the field's ground between t0 and t1 (sampled every 0.1 block, then halved down to a
    // hundredth), and the ground cell there: the cell holding the point, or the ground cell nearest it.
    func fieldRaySegment(_ o: V3, _ d: V3, from t0: Float, to t1: Float) -> (cell: IVec3, at: V3, t: Float)? {
        guard t1 >= t0 else { return nil }
        var out = t0, hit: Float?
        if fieldDensity(at: o + d * t0) > 0 { hit = t0 }
        else {
            var t = t0
            while hit == nil {
                let tn = min(t1, t + 0.1)
                if fieldDensity(at: o + d * tn) > 0 { hit = tn; out = t; break }
                if tn >= t1 { break }
                t = tn
            }
        }
        guard var inT = hit else { return nil }
        if inT > out {
            for _ in 0..<6 { let m = (out + inT) * 0.5; if fieldDensity(at: o + d * m) > 0 { inT = m } else { out = m } }
        }
        let p = o + d * inT
        return (fieldCell(p, along: d), p, inT)
    }

    // The ground cell for a point on the field's surface: the cell holding it, else the first ground cell the ray goes on
    // into (`along`: the ray's direction; the cell the crosshair is over), else the ground cell nearest it.
    func fieldCell(_ p0: V3, along d: V3? = nil) -> IVec3 {
        func ground(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
            return c.blocks.ground(Chunk.index(mod(x, CS), y, mod(z, CS)))
        }
        var p = p0
        if let d {
            for k in 0..<4 {
                let q = p0 + d * (Float(k) * 0.2)
                if ground(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))) { return IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))) }
            }
            p = p0 + d * 0.3
        }
        let bx = Int(floor(p.x)), by = Int(floor(p.y)), bz = Int(floor(p.z))
        if ground(bx, by, bz) { return IVec3(bx, by, bz) }
        var best = IVec3(bx, by, bz), bd = Float.greatestFiniteMagnitude
        for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where ground(bx + dx, by + dy, bz + dz) {
            let q = V3(Float(bx + dx) + 0.5, Float(by + dy) + 0.5, Float(bz + dz) + 0.5)
            let dd = simd_length_squared(q - p)
            if dd < bd { bd = dd; best = IVec3(bx + dx, by + dy, bz + dz) }
        } } }
        return best
    }

    // The field's gradient at p (points into the ground).
    func fieldGradient(_ p: V3) -> V3 {
        let h: Float = 0.25
        return V3(fieldDensity(at: p + V3(h, 0, 0)) - fieldDensity(at: p - V3(h, 0, 0)),
                  fieldDensity(at: p + V3(0, h, 0)) - fieldDensity(at: p - V3(0, h, 0)),
                  fieldDensity(at: p + V3(0, 0, h)) - fieldDensity(at: p - V3(0, 0, h)))
    }

    // A new world made as Polygons (WorldRequest.setUp, App.makeGame) becomes a field world before its first chunk: the
    // choice is kept in the save as terrain-field.txt and never changes for that world.
    func makeFieldWorld() {
        guard chunks.isEmpty, FieldTerrain.newWorlds else { return }
        if let save {
            try? FileManager.default.createDirectory(at: save.dir, withIntermediateDirectories: true)
            try? "natural terrain is a density field (PG1 rewrite, Oct 14)\n".write(to: save.dir.appendingPathComponent("terrain-field.txt"),
                                                                                     atomically: true, encoding: .utf8)
            try? "railways on a gentle grade (P379)\n".write(to: save.dir.appendingPathComponent("railway-grade.txt"), atomically: true, encoding: .utf8)
        }
        fieldTerrain = true
    }
}
