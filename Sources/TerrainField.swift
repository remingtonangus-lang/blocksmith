import Foundation
import simd

// PG1 (Oct 13 22:05, "the polygon direction: no blocks underneath at all, a true smooth volumetric terrain that breaks
// apart"), part 1: the terrain is a signed distance field, and every change to the ground is a change to that field.
//
// The field: at every block centre, how far it is to the ground's surface in blocks (+ inside the ground, - outside).
// Untouched ground needs no storage: the world generator's own continuous fields (SmoothField: the terrain density and
// the three cave fields) give it, normalized by their gradient into a distance. What the player does to the ground is
// stored as edits on top, per cell, as two bounds on the distance in 1/32 block (Int8, +-3.97 blocks):
//   cap    the distance is at most this (a carve: digging, a blast, a round's dent pushes the surface in)
//   floor  the distance is at least this (a fill: placed ground pushes the surface out)
// so the field at a cell is clamp(generator distance, floor, cap). The mesher (SmoothTerrain.smoothQuads through
// SmoothField) takes every crossing next to an edit from these distances, so a dug pit, a crater or a bullet's dent
// is a smooth surface at sub-block precision, not a removed cube. Edits are saved beside each chunk (f.X.Z.lz).
//
// Blocks stay the material and the physics for now (PG2 moves collision onto the surface): a cell is solid exactly when
// its block is, and a carve that takes a cell's distance below zero removes its block (World.carve).
struct FieldEdit {
    static let none: UInt16 = 0x807F                      // cap 127 (no cap), floor -128 (no floor)
    static let scale: Float = 32                          // units per block
    @inline(__always) static func cap(_ e: UInt16) -> Int8 { Int8(truncatingIfNeeded: e & 0xFF) }
    @inline(__always) static func floor(_ e: UInt16) -> Int8 { Int8(truncatingIfNeeded: e >> 8) }
    @inline(__always) static func pack(cap: Int8, floor: Int8) -> UInt16 {
        UInt16(UInt8(bitPattern: cap)) | UInt16(UInt8(bitPattern: floor)) << 8
    }
    @inline(__always) static func q(_ d: Float) -> Int8 { Int8(max(-127, min(126, (d * scale).rounded()))) }
    // The field at a cell from the generator's distance `d` and the cell's edit.
    @inline(__always) static func apply(_ d: Float, _ e: UInt16) -> Float {
        let c = Float(cap(e)) / scale, f = Float(floor(e)) / scale
        var v = d
        if cap(e) != 127 { v = min(v, c) }
        if floor(e) != -128 { v = max(v, f) }
        return v
    }
}

// The edits a mesh job needs (its chunk and the eight round it), copied when the job is made: value semantics, so the
// frame thread can keep editing while a worker meshes.
struct FieldEditSet {
    var chunks: [(cx: Int, cz: Int, edits: [Int32: UInt16])] = []
    var isEmpty: Bool { chunks.isEmpty }
}

extension World {
    // Worlds whose generator has continuous fields (the overworld) keep field edits.
    var keepsField: Bool { gen is WorldGen }

    // Distance bounds at cell p (world block), merged into what is there.
    func fieldBound(_ p: IVec3, cap: Float? = nil, floor: Float? = nil) {
        guard p.y >= 0 && p.y < CH, let c = chunkAt(p.x, p.z) else { return }
        let i = Int32(Chunk.index(mod(p.x, CS), p.y, mod(p.z, CS)))
        let e0 = c.fieldEdits[i] ?? FieldEdit.none
        var cp = FieldEdit.cap(e0), fl = FieldEdit.floor(e0)
        if let v = cap { cp = min(cp, FieldEdit.q(v)) }
        if let v = floor { fl = max(fl, FieldEdit.q(v)) }
        if fl != -128 && cp != 127 && fl > cp { if cap != nil { fl = cp } else { cp = fl } }   // the newer bound wins
        let e = FieldEdit.pack(cap: cp, floor: fl)
        guard e != e0 else { return }
        c.fieldEdits[i] = e
        c.fieldDirty = true
        fieldStamp &+= 1
    }

    // Clears the bounds at p (a block that changes back to what the generator made keeps the surface the field had).
    func fieldReset(_ p: IVec3, solid: Bool) {
        guard p.y >= 0 && p.y < CH, let c = chunkAt(p.x, p.z) else { return }
        let i = Int32(Chunk.index(mod(p.x, CS), p.y, mod(p.z, CS)))
        if c.fieldEdits.removeValue(forKey: i) != nil { c.fieldDirty = true }
        fieldBound(p, cap: solid ? nil : -0.5, floor: solid ? 0.5 : nil)
    }

    // setBlock's hook: a natural cell that opened (dug, blasted, washed away) or ground that was placed reshapes the field
    // round it: the cell itself sits half a block past the surface and its neighbours are bounded by their distance to
    // the cell's cube, so a single mined block leaves a block-sized rounded hollow and a placed one a rounded lump.
    func fieldBlockChanged(_ x: Int, _ y: Int, _ z: Int, _ old: BlockID, _ new: BlockID) {
        guard keepsField, old != new else { return }
        let wasSolid = Blocks.opaque[Int(old)], isSolid = Blocks.opaque[Int(new)]
        guard wasSolid != isSolid else { return }
        let natOld = SmoothTerrain.natural[Int(old)], natNew = SmoothTerrain.natural[Int(new)]
        guard natOld || natNew else { return }
        let p = IVec3(x, y, z)
        if wasSolid {
            fieldReset(p, solid: false)
            for dz in -1...1 { for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                let q = IVec3(x + dx, y + dy, z + dz)
                guard q.y >= 0 && q.y < CH, Blocks.opaque[Int(block(q.x, q.y, q.z))] else { continue }
                let o = Float(abs(dx) + abs(dy) + abs(dz))
                fieldBound(q, cap: o == 1 ? 0.5 : (o == 2 ? 0.71 : 0.87))
            } } }
        } else {
            fieldReset(p, solid: true)
            for dz in -1...1 { for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                let q = IVec3(x + dx, y + dy, z + dz)
                guard q.y >= 0 && q.y < CH, !Blocks.opaque[Int(block(q.x, q.y, q.z))] else { continue }
                let o = Float(abs(dx) + abs(dy) + abs(dz))
                fieldBound(q, floor: o == 1 ? -0.5 : (o == 2 ? -0.71 : -0.87))
            } } }
        }
    }

    enum CarveMode {
        case dig       // the sphere is gone: natural cells whose centre it takes are removed (`remove` decides drops)
        case shape     // only the surface moves: blocks stay, the field round them is bounded (a blast's crater walls)
        case dent      // shape, but shallow: a round's or a shell splinter's mark
    }

    // PG1: carves a ball of radius r at c out of the terrain field. Natural ground only: built blocks keep their shape
    // (their surface pins). In .dig mode `remove` is called for every natural cell inside the ball before it goes (drops,
    // debris) and the cell is set to air. Returns how many cells were removed.
    @discardableResult
    func carve(at c: V3, radius r: Float, mode: CarveMode, remove: ((IVec3, BlockID) -> Void)? = nil) -> Int {
        guard keepsField, r > 0.05 else { return 0 }
        let reach = r + 1.5
        let lo = IVec3(Int(floor(c.x - reach)), max(0, Int(floor(c.y - reach))), Int(floor(c.z - reach)))
        let hi = IVec3(Int(floor(c.x + reach)), min(CH - 1, Int(floor(c.y + reach))), Int(floor(c.z + reach)))
        guard lo.y <= hi.y else { return 0 }
        let natT = SmoothTerrain.natural, opaqueT = Blocks.opaque
        var gone: [(IVec3, BlockID)] = []
        var caps: [(IVec3, Float)] = []
        for y in lo.y...hi.y { for z in lo.z...hi.z { for x in lo.x...hi.x {
            let q = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
            var s = simd_length(q - c) - r
            if mode == .dent { s = max(s, -0.4) * 0.6 }
            guard s < 1.2 else { continue }
            let b = block(x, y, z)
            let solid = opaqueT[Int(b)]
            if solid && !natT[Int(b)] { continue }
            let p = IVec3(x, y, z)
            if solid {
                if mode == .dig && s < 0 && Blocks.hardness[Int(b)] >= 0 { gone.append((p, b)); caps.append((p, s)); continue }
                caps.append((p, max(0.06, s)))
            } else if s < 0 {
                caps.append((p, s))
            }
        } } }
        for (p, b) in gone {
            remove?(p, b)
            setBlockAsync(p.x, p.y, p.z, AIR)
        }
        for (p, v) in caps { fieldBound(p, cap: v) }
        if !caps.isEmpty { fieldTouched(lo, hi) }
        return gone.count
    }

    // The field edit at a cell (FieldEdit.none where there is none).
    @inline(__always) func fieldEdit(_ x: Int, _ y: Int, _ z: Int) -> UInt16 {
        guard y >= 0 && y < CH, let c = chunkAt(x, z), !c.fieldEdits.isEmpty else { return FieldEdit.none }
        return c.fieldEdits[Int32(Chunk.index(mod(x, CS), y, mod(z, CS)))] ?? FieldEdit.none
    }

    // PG2: the drawn surface over a column whose top solid cell is y (y + 1 open), as the smooth mesher draws it: the
    // generator's crossing between the two cells (half a block either side of the block top where the field made no
    // surface there: dug, built over), with the field edits of both cells applied. Built blocks keep their block top.
    // The one height the view, mobs, items and debris stand on (smoothGroundOffset, WorldGround).
    func drawnTop(_ g: WorldGen, _ x: Int, _ y: Int, _ z: Int) -> Float {
        guard SmoothTerrain.natural[Int(block(x, y, z))] else { return Float(y + 1) }
        var a: Float = 0.5, b: Float = -0.5
        let da = g.terrainDensity(x, y, z), db = g.terrainDensity(x, y + 1, z)
        if da > 0 && db <= 0 { let t = da / (da - db); a = t; b = t - 1 }
        let ea = fieldEdit(x, y, z), eb = fieldEdit(x, y + 1, z)
        if ea != FieldEdit.none { a = FieldEdit.apply(a, ea) }
        if eb != FieldEdit.none { b = FieldEdit.apply(b, eb) }
        a = max(a, 0.02); b = min(b, -0.02)
        return Float(y) + 0.5 + a / (a - b)
    }

    // PG2: the drawn underside of a natural cell y over open air (y - 1 open): an overhang's or a dug roof's surface, as
    // drawnTop from below. The block bottom where the field made no surface there and nothing was carved.
    func drawnBottom(_ g: WorldGen, _ x: Int, _ y: Int, _ z: Int) -> Float {
        guard SmoothTerrain.natural[Int(block(x, y, z))] else { return Float(y) }
        var a: Float = 0.5, b: Float = -0.5
        let da = g.terrainDensity(x, y, z), db = g.terrainDensity(x, y - 1, z)
        if da > 0 && db <= 0 { let t = -db / (da - db); a = 1 - t; b = -t }
        let ea = fieldEdit(x, y, z), eb = fieldEdit(x, y - 1, z)
        if ea != FieldEdit.none { a = FieldEdit.apply(a, ea) }
        if eb != FieldEdit.none { b = FieldEdit.apply(b, eb) }
        a = max(a, 0.02); b = min(b, -0.02)
        return Float(y) - 0.5 - b / (a - b)
    }

    // PG2: the collision top of natural cell (x, y, z) under open air: its drawn surface (drawnTop) where that is below
    // the block top (never above: a body already standing at the block top would be inside a raised box, which sweeps
    // ignore; ground drawn higher stays a view offset, smoothGroundOffset), at most half a block down. Cached (field changes bump fieldStamp).
    func groundTop(_ g: WorldGen, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let key = (x & 0xFFFFF) | ((z & 0xFFFFF) << 20) | ((y & 0x3FF) << 40) | ((fieldStamp & 0x1FFF) << 50)
        let slot = Int(UInt(bitPattern: key &* -0x61C8864680B583EB) >> 52)
        if groundTopKey[slot] == key { return groundTopVal[slot] }
        let t = max(Float(y) + 0.5, min(Float(y) + 1, drawnTop(g, x, y, z)))
        groundTopKey[slot] = key; groundTopVal[slot] = t
        return t
    }

    // PG2: the collision bottom of natural cell (x, y, z) over open air (cave roofs, overhangs, dug ceilings): its drawn
    // underside where that is above the block bottom (only ever more headroom), at most 0.45 up. Cached like groundTop.
    func ceilingBottom(_ g: WorldGen, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let key = (x & 0xFFFFF) | ((z & 0xFFFFF) << 20) | (((y | 512) & 0x3FF) << 40) | ((fieldStamp & 0x1FFF) << 50)
        let slot = Int(UInt(bitPattern: key &* -0x61C8864680B583EB) >> 52)
        if groundTopKey[slot] == key { return groundTopVal[slot] }
        let t = min(Float(y) + 0.45, max(Float(y), drawnBottom(g, x, y, z)))
        groundTopKey[slot] = key; groundTopVal[slot] = t
        return t
    }

    // The edits a mesh job of chunk c needs.
    func fieldEditSet(_ c: Chunk) -> FieldEditSet {
        var s = FieldEditSet()
        for dz in -1...1 { for dx in -1...1 {
            guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)], !n.fieldEdits.isEmpty else { continue }
            s.chunks.append((n.cx, n.cz, n.fieldEdits))
        } }
        return s
    }

    // Bumps every loaded section whose surface a field change over [lo, hi] (world blocks) can move (a dual vertex reads
    // the cells one past its own, and relaxation one more), remeshing in the background.
    func fieldTouched(_ lo: IVec3, _ hi: IVec3) {
        let x0 = floorDiv(lo.x - 2, CS), x1 = floorDiv(hi.x + 2, CS), z0 = floorDiv(lo.z - 2, CS), z1 = floorDiv(hi.z + 2, CS)
        let s0 = max(0, (lo.y - 2) >> 4), s1 = min(NSEC - 1, (hi.y + 2) >> 4)
        guard s0 <= s1 else { return }
        for cz in z0...z1 { for cx in x0...x1 {
            guard let c = chunks[ChunkKey(x: cx, z: cz)] else { continue }
            for sy in s0...s1 { c.sections[sy].version += 1 }
        } }
    }
}

extension SaveManager {
    func fieldURL(_ k: ChunkKey) -> URL { chunkDir.appendingPathComponent("f.\(k.x).\(k.z).lz") }

    // Edits handed to the save queue and not on disk yet (a chunk that unloads and comes straight back reads these).
    private static let pendingLock = NSLock()
    private static var pending: [String: (id: Int, edits: [Int32: UInt16])] = [:]
    private static var pendingID = 0
    private static let fieldQueue = DispatchQueue(label: "blocksmith.field-save", qos: .utility)

    // Field file: lzfse( u32 count, then per edit u32 cell index, u16 bounds ). Thread-safe (world worker threads).
    func loadFieldEdits(_ k: ChunkKey) -> [Int32: UInt16] {
        let path = fieldURL(k).path
        SaveManager.pendingLock.lock()
        let queued = SaveManager.pending[path]?.edits
        SaveManager.pendingLock.unlock()
        if let q = queued { return q }
        guard let d = try? Data(contentsOf: fieldURL(k)),
              let raw = try? (d as NSData).decompressed(using: .lzfse) as Data else { return [:] }
        let b = [UInt8](raw)
        guard b.count >= 4 else { return [:] }
        let n = Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
        guard b.count == 4 + n * 6 else { return [:] }
        var out: [Int32: UInt16] = [:]
        out.reserveCapacity(n)
        var p = 4
        for _ in 0..<n {
            let i = Int32(b[p]) | Int32(b[p + 1]) << 8 | Int32(b[p + 2]) << 16 | Int32(b[p + 3]) << 24
            let e = UInt16(b[p + 4]) | UInt16(b[p + 5]) << 8
            if i >= 0 && Int(i) < CSQ * CH { out[i] = e }
            p += 6
        }
        return out
    }

    func saveFieldEdits(_ k: ChunkKey, _ e: [Int32: UInt16]) {
        let url = fieldURL(k), path = url.path
        SaveManager.pendingLock.lock()
        SaveManager.pendingID += 1
        let id = SaveManager.pendingID
        SaveManager.pending[path] = (id, e)
        SaveManager.pendingLock.unlock()
        SaveManager.fieldQueue.async {
            defer {
                SaveManager.pendingLock.lock()
                if SaveManager.pending[path]?.id == id { SaveManager.pending[path] = nil }
                SaveManager.pendingLock.unlock()
            }
            if e.isEmpty { try? FileManager.default.removeItem(at: url); return }
            var d = Data(capacity: 4 + e.count * 6)
            let n = UInt32(e.count)
            d.append(contentsOf: [UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255), UInt8(n >> 24)])
            for (i, v) in e.sorted(by: { $0.key < $1.key }) {
                let u = UInt32(bitPattern: i)
                d.append(contentsOf: [UInt8(u & 255), UInt8((u >> 8) & 255), UInt8((u >> 16) & 255), UInt8(u >> 24),
                                      UInt8(v & 255), UInt8(v >> 8)])
            }
            guard let c = try? (d as NSData).compressed(using: .lzfse) as Data else { return }
            SaveIO.store(c, to: url)
        }
    }
}
