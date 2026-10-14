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

    // New worlds are field worlds (written as a marker in the save: terrain-field.txt).
    // (Off until collision runs against the field: `--field` makes new worlds field worlds meanwhile.)
    static var newWorlds = CommandLine.arguments.contains("--field")
    // Worlds with no save (harness, tests): `--field` makes them field worlds; a co-op guest takes the host's choice.
    static var unsaved = CommandLine.arguments.contains("--field")

    // Harness (`--fieldstats`): the surface cells split has shaped, by where the distance came from: the generator's own
    // continuous fields, a rule's shape, or rounded from the cells round it.
    static let statsOn = CommandLine.arguments.contains("--fieldstats")
    static let statsLock = NSLock()
    static var stats = [0, 0, 0]
    static func statsLine() -> String {
        statsLock.lock(); defer { statsLock.unlock() }
        let t = max(1, stats.reduce(0, +))
        return String(format: "fieldstats: %d surface cells: %.1f%% generator field, %.1f%% rule shapes, %.1f%% rounded from cells",
                      t, Double(stats[0]) * 100 / Double(t), Double(stats[1]) * 100 / Double(t), Double(stats[2]) * 100 / Double(t))
    }

    // Loose ground (soil, sand, gravel, mud): what a structure lays of it shapes the ground (a garden, a levelled yard, a
    // track) and joins the field; the rock, sandstone, terracotta and snow it builds with stay its blocks.
    static let loose: [Bool] = (0..<Blocks.count).map { i in
        [.dirt, .grass, .sand, .gravel, .mud, .soul].contains(Blocks.def(BlockID(i)).sound)
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
    static func split(_ b: inout [BlockID], cx: Int, cz: Int, gen: TerrainGenerator, built: [UInt8]? = nil) -> FieldData {
        let n = CSQ * CH
        var fd = [Int8](repeating: outside, count: n)
        var fm = [UInt8](repeating: 0, count: n)
        let idx = FieldMat.index, looseT = loose
        var top = 0
        for i in 0..<n {
            let m = idx[Int(b[i])]
            guard m != 0 else { continue }
            if let built, built[i] != 0 && !looseT[Int(b[i])] { continue }
            fm[i] = m; fd[i] = inside; b[i] = AIR; top = i
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
                if let F, y >= 1, F.solid(si) == s {
                    d = max(-1.5, min(1.5, F.genDistance(si))); st[0] += 1
                } else if let gd = genGround(lx, y, lz, i), (gd > 0) == s {
                    d = max(-1.5, min(1.5, gd)); st[0] += 1
                } else {
                    st[2] += 1
                    var cnt = 0, tot = 0
                    for dy in -1...1 { let yy = y + dy; guard yy >= 0 && yy < CH else { continue }
                        for dz in -1...1 { let zz = lz + dz; guard zz >= 0 && zz < CS else { continue }
                            for dx in -1...1 { let xx = lx + dx; guard xx >= 0 && xx < CS else { continue }
                                tot += 1; if solid(xx, yy, zz) { cnt += 1 } } } }
                    let m = Float(cnt) / Float(max(1, tot))
                    d = (0.5 * (s ? 1 : 0) + 0.5 * m - 0.5) * 2
                }
                d = s ? max(d, 0.04) : min(d, -0.04)
                fd[i] = q(d)
            } } }
        }
        if statsOn { statsLock.lock(); for k in 0..<3 { stats[k] += st[k] }; statsLock.unlock() }
        return FieldData(fd: fd, fm: fm)
    }

    // MARK: Saving

    // Field file: lzfse("FLD1", u32 cell count, u16 material count, material names (u16 length + utf8), densities (one
    // byte per cell), materials (one byte per cell, an index into the names)). Names keep it valid as the registry grows.
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
        var d = Data("FLD1".utf8)
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
        guard let c = try? (d as NSData).compressed(using: .lzfse) as Data else { return nil }
        return [UInt8](c)
    }

    static func decode(_ bytes0: [UInt8]) -> FieldData? {
        guard let raw = try? (Data(bytes0) as NSData).decompressed(using: .lzfse) as Data else { return nil }
        let b = [UInt8](raw)
        guard b.count >= 10, b[0] == 0x46, b[1] == 0x4C, b[2] == 0x44, b[3] == 0x31 else { return nil }
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
        guard b.count - p == n * 2 else { return nil }
        var fd = [Int8](repeating: 0, count: n), fm = [UInt8](repeating: 0, count: n)
        for i in 0..<n { fd[i] = Int8(bitPattern: b[p + i]) }
        for i in 0..<n {
            let k = Int(b[p + n + i])
            fm[i] = k < pal.count ? pal[k] : 0
            if fm[i] == 0 && fd[i] > 0 { fd[i] = cellOut }         // a material this build doesn't know: open
        }
        return FieldData(fd: fd, fm: fm)
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
        var b = generate(cx: cx, cz: cz)
        var mark = [UInt8](repeating: 0, count: b.count)
        var ents: [(IVec3, BlockEntity)] = [], mobs: [(String, V3)] = []
        if let st = structures {
            (ents, mobs) = mark.withUnsafeMutableBufferPointer { m in st.place(into: &b, cx: cx, cz: cz, mark: m.baseAddress) }
        }
        ents += World.orphanEntities(b, ChunkKey(x: cx, z: cz), have: ents)
        _ = PlantSupport.dropFloating(&b)
        let ground = FieldTerrain.split(&b, cx: cx, cz: cz, gen: self, built: mark)
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

    // The ground's density at a point (blocks, + inside): trilinear between the eight cell centres round it.
    func fieldDensity(at p: V3) -> Float {
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
        fieldSphere(ctr, radius: opened ? 0.72 : 0.62, carve: opened, material: nil, keepCell: IVec3(x, y, z))
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
        let reach = Int(ceil(r + 1.5))
        let cxI = Int(floor(ctr.x)), cyI = Int(floor(ctr.y)), czI = Int(floor(ctr.z))
        var touched: [(Chunk, Int)] = []
        for y in max(0, cyI - reach)...min(CH - 1, cyI + reach) {
            for z in (czI - reach)...(czI + reach) {
                for x in (cxI - reach)...(cxI + reach) {
                    guard let c = chunkAt(x, z), c.blocks.isField else { continue }
                    let p = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                    let dist = simd_length(p - ctr)
                    let i = Chunk.index(mod(x, CS), y, mod(z, CS))
                    let d0 = FieldTerrain.f(c.blocks.density(i))
                    let d1 = carve ? min(d0, dist - r) : max(d0, r - dist)
                    var q = FieldTerrain.q(d1)
                    let was = d0 > 0
                    if carve && was && Blocks.hardness[Int(FieldMat.blocks[Int(c.blocks.material(i))])] < 0 { continue }   // (bedrock)
                    if keepSolid && was != (q > 0) { q = was ? 1 : -1 }
                    if q == c.blocks.density(i) { continue }
                    let now = q > 0
                    if let k = keepCell, k.x == x && k.y == y && k.z == z && was != now { continue }   // (setBlock decided it)
                    if was != now {
                        if now && c.blocks.raw(i) != AIR { continue }      // a fill never swallows a built block
                        let m = material ?? fieldNeighbourMaterial(x, y, z)
                        c.blocks.setDensity(i, now ? max(q, 1) : min(q, -1), material: now ? m : nil)
                        flipped.append(IVec3(x, y, z))
                        c.modified = true
                        c.recomputeHeight(mod(x, CS), mod(z, CS))
                    } else {
                        c.blocks.setDensity(i, q, material: nil)
                        c.modified = true
                    }
                    let sy = y >> 4
                    if !touched.contains(where: { $0.0 === c && $0.1 == sy }) { touched.append((c, sy)) }
                }
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
        if remesh { for (n, s) in all where !deferRemesh { remeshSync(n, s) } }
        fieldStamp &+= 1
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
                if d > 0 { return y - 0.05 * d / (d - prev) }
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
                if f % 3 == 0, g.player.onGround, !Blocks.collide[Int(w.block(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.y - 0.3)), Int(floor(g.player.pos.z))))] || w.fieldNear(g.player.pos),
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
        return (fieldCell(p), p, inT)
    }

    // The ground cell for a point on the field's surface.
    func fieldCell(_ p: V3) -> IVec3 {
        let bx = Int(floor(p.x)), by = Int(floor(p.y)), bz = Int(floor(p.z))
        func ground(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard y >= 0 && y < CH, let c = chunkAt(x, z) else { return false }
            return c.blocks.ground(Chunk.index(mod(x, CS), y, mod(z, CS)))
        }
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
        fieldTerrain = true
        if let save {
            try? FileManager.default.createDirectory(at: save.dir, withIntermediateDirectories: true)
            try? "natural terrain is a density field (PG1 rewrite, Oct 14)\n".write(to: save.dir.appendingPathComponent("terrain-field.txt"),
                                                                                     atomically: true, encoding: .utf8)
        }
    }
}
