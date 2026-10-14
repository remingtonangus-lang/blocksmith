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

    // A saved built layer's natural cells (stamped in as it loaded, or saved by a build that kept them) go into the field.
    static func absorb(_ b: inout [BlockID], into f: inout FieldData) {
        let idx = FieldMat.index
        if f.fd.count < b.count {
            f.fd.append(contentsOf: repeatElement(outside, count: b.count - f.fd.count))
            f.fm.append(contentsOf: repeatElement(0, count: b.count - f.fm.count))
        }
        for i in 0..<b.count {
            let m = idx[Int(b[i])]
            guard m != 0 else { continue }
            b[i] = AIR
            f.fm[i] = m
            if f.fd[i] <= 0 { f.fd[i] = cellIn }
        }
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
    static func split(_ b: inout [BlockID], cx: Int, cz: Int, gen: TerrainGenerator) -> FieldData {
        let n = CSQ * CH
        var fd = [Int8](repeating: outside, count: n)
        var fm = [UInt8](repeating: 0, count: n)
        let idx = FieldMat.index
        var top = 0
        for i in 0..<n {
            let m = idx[Int(b[i])]
            if m != 0 { fm[i] = m; fd[i] = inside; b[i] = AIR; top = i }
        }
        let topY = min(CH - 1, top / CSQ + 1)
        let wg = gen as? WorldGen
        let F: SmoothField? = wg != nil ? SmoothField() : nil
        let N = SmoothField.N, NN = SmoothField.NN, SO = (N - 16) / 2
        @inline(__always) func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { fd[x + z * CS + y * CSQ] > 0 }
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
                    d = max(-1.5, min(1.5, F.genDistance(si)))
                } else {
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
    func fieldSphere(_ ctr: V3, radius r: Float, carve: Bool, material: UInt8?, keepCell: IVec3? = nil, remesh: Bool = false) -> [IVec3] {
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
                    let q = FieldTerrain.q(d1)
                    if q == c.blocks.density(i) { continue }
                    let was = d0 > 0, now = q > 0
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
}
