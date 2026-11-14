import Foundation
import simd

// Ledger 134 (Remington, Nov 14 11:53-11:54 and 12:30: "a branch turned into something else", "one trunk became four",
// "branches became vertical logs", "old issues, wasn't fixed... all the blocks morphed into a different type of block,
// and then it fell"; before that Oct 15, Oct 24, Nov 12, Nov 13). A standing tree's wood is drawn by ShapeTrunks: one
// tapered trunk measured over its whole height, limbs as thin tubes from joint to joint, a foot. A felled tree was drawn
// by Game.writeFelled: every log cell its own cylinder along the block's axis, with a ring cap at each end. A limb (logs
// stepping up and out, each an upright block) became a stack of short upright posts, a four-log trunk four posts, and
// the trunk lost its taper: the tree changed shape on the frame it came loose.
//
// The body now keeps the shape it stood with. When a tree comes loose, before its logs leave the world, the sections it
// stood in are drawn once more on the edit lane with every other log taken as air (trunkSkip) and the logs under it (the
// stump, the cut) as ghosts (grown, not drawn: the taper and girth stay the tree's own, and the body's foot shows a cut
// end). The trunks' quads of those drawings, each given to the body's log nearest it, are the body's shape: drawn with
// the body's pose every frame, lit where it lies. A log chopped out of the lying trunk takes its quads with it and the
// logs beside it show a ring; a piece split off takes its part of the shape along. A body with no shape (the snapshot
// could not be made, or a tree saved before this) is drawn as before. BS_OLDFELLSHAPE=1: as before.
extension Felling {
    static let oldFellShape = ProcessInfo.processInfo.environment["BS_OLDFELLSHAPE"] == "1"

    struct ShapeQuad {
        var p0: V3, p1: V3, p2: V3, p3: V3           // ship grid coordinates
        var n: V3
        var u0: V2, u1: V2, u2: V2, u3: V2
        var layer: Int32
        var cell: Int32                              // index into Shape.cells
    }
    struct ShapeCap { var c: V3, n: V3, r: Float, layer: Int32, cell: Int32 }

    final class Shape {
        var owner: ObjectIdentifier                  // (ship ids start again in every world)
        var cells: [IVec3] = []                      // the body's log cells (ship grid) that own quads
        var blocks: [BlockID] = []                   // the log that stood in each
        var quads: [ShapeQuad] = []
        var live: [Bool] = []
        var caps: [ShapeCap] = []
        var count = -1                               // the body's block count `live` and `caps` were made for
        var light: [SIMD2<Int32>] = []               // (per cell, this frame)
        init(owner: ObjectIdentifier) { self.owner = owner }
    }

    // What a snapshot needs from the world, taken on the main thread before the logs go.
    struct ShapeSnap {
        var secs: [(n9: [BlockStore], h9: [[Int16]], cx: Int, cz: Int, sy: Int, site: SmoothSite?)]
        var skip: Set<IVec3>
        var ghosts: TreeGhosts.Map
        var logs: [IVec3: BlockID]
    }

    static var shapes: [Int: Shape] = [:]            // by ship id (main thread)
    static var shapePending: [Int: ObjectIdentifier] = [:]   // bodies whose shape is being made (main thread)
    private static let shapeLock = NSLock()
    private static var shapeDone: [(ship: Int, shape: Shape?)] = []
    static var shapesMade = 0, shapesFailed = 0, shapeQuads = 0      // (harness)
    static var shapeWorstMs = 0.0

    // Before the logs leave the world. Nil where no shape can be made (the body is then drawn as before).
    static func shapeSnap(_ w: World, logs: Set<IVec3>, cut: IVec3?) -> ShapeSnap? {
        guard roundTrunks, !oldFellShape, !logs.isEmpty, logs.count <= 600 else { return nil }
        let trunkT = ShapeTrunks.isTrunk
        var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        var keys = Set<IVec3>()
        var blocks: [IVec3: BlockID] = [:]
        for c in logs {
            guard c.y >= 0 && c.y < CH else { return nil }
            lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
            keys.insert(IVec3(floorDiv(c.x, CS), c.y >> 4, floorDiv(c.z, CS)))
            blocks[c] = w.block(c.x, c.y, c.z)
        }
        guard keys.count <= 24 else { return nil }
        var hoods: [ChunkKey: ([BlockStore], [[Int16]], SmoothSite?)] = [:]
        var secs: [(n9: [BlockStore], h9: [[Int16]], cx: Int, cz: Int, sy: Int, site: SmoothSite?)] = []
        var ghosts = TreeGhosts.Map()
        for k in keys {
            let ck = ChunkKey(x: k.x, z: k.z)
            if hoods[ck] == nil {
                guard let ch = w.chunks[ck], let nb = w.neighbourhood(ch) else { return nil }
                hoods[ck] = (nb.0, nb.1, w.smoothSite(ch))
                if let near = w.treeGhosts.near(k.x, k.z) { ghosts.merge(near) { a, _ in a } }
            }
            let h = hoods[ck]!
            secs.append((h.0, h.1, k.x, k.z, k.y, h.2))
        }
        // Every other log near it is air to the drawing (a neighbour's bough, the stump); the logs straight under the
        // body are ghosts as well, so the trunk is measured from the foot it stood on.
        var skip = Set<IVec3>()
        let m = 3
        for y in max(0, lo.y - m)...min(CH - 1, hi.y + m) { for z in (lo.z - m)...(hi.z + m) { for x in (lo.x - m)...(hi.x + m) {
            let c = IVec3(x, y, z)
            if blocks[c] == nil && trunkT[Int(w.block(x, y, z))] { skip.insert(c) }
        } } }
        for (c, b0) in blocks where blocks[IVec3(c.x, c.y - 1, c.z)] == nil {
            var y = c.y - 1
            while y >= 0 && y > c.y - 64 {
                let q = IVec3(c.x, y, c.z)
                let b = w.block(q.x, q.y, q.z)
                if trunkT[Int(b)] { ghosts[q] = UInt32(b) | TreeGhosts.crownBit; skip.insert(q) }
                else if q == cut || ghosts[q] != nil { if ghosts[q] == nil { ghosts[q] = UInt32(b0) | TreeGhosts.crownBit } }
                else { break }
                y -= 1
            }
        }
        return ShapeSnap(secs: secs, skip: skip, ghosts: ghosts, logs: blocks)
    }

    // The body is made: its shape is drawn on the edit lane. `origin`: the world cell of the body's grid cell 0 0 0.
    static func shapeStart(_ snap: ShapeSnap?, ship s: Ship, origin: IVec3, world w: World) {
        guard let snap else { return }
        let id = s.id, owner = ObjectIdentifier(w)
        shapePending[id] = owner
        World.quickQueue.async {
            let t0 = CFAbsoluteTimeGetCurrent()
            let shape = Felling.shapeBuild(snap, origin: origin, owner: owner)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            shapeLock.lock()
            shapeDone.append((id, shape))
            if ms > shapeWorstMs { shapeWorstMs = ms }
            shapeLock.unlock()
        }
    }

    // Main thread, every frame (fellingTick): the shapes the lane finished.
    static func shapeCollect(_ w: World) {
        guard !shapePending.isEmpty else { return }
        shapeLock.lock()
        let done = shapeDone
        shapeDone.removeAll()
        shapeLock.unlock()
        for (id, shape) in done {
            guard let owner = shapePending.removeValue(forKey: id) else { continue }
            if let shape, shape.owner == owner, !shape.quads.isEmpty { shapes[id] = shape; shapesMade += 1; shapeQuads += shape.quads.count }
            else { shapesFailed += 1 }
        }
        // (bodies gone, or another world's)
        let me = ObjectIdentifier(w)
        if shapes.count > 64 || shapes.contains(where: { $0.value.owner != me }) {
            let live = Set(w.ships.list.map { $0.id })
            shapes = shapes.filter { $0.value.owner == me && live.contains($0.key) }
        }
        shapePending = shapePending.filter { $0.value == me }
    }

    @inline(__always) private static func unhalf(_ h: UInt32) -> Float {
        let s: Float = (h & 0x8000) != 0 ? -1 : 1
        let e = Int((h >> 10) & 31), m = Float(h & 0x3FF)
        if e == 0 { return s * m / 1024 * Float(sign: .plus, exponent: -14, significand: 1) }
        if e == 31 { return 0 }
        return s * (1 + m / 1024) * Float(sign: .plus, exponent: e - 15, significand: 1)
    }

    // Worker: the sections drawn with only this tree's wood, their trunk quads given to the body's logs.
    static func shapeBuild(_ snap: ShapeSnap, origin: IVec3, owner: ObjectIdentifier) -> Shape? {
        let shape = Shape(owner: owner)
        var index: [IVec3: Int32] = [:]
        let o = V3(Float(origin.x), Float(origin.y), Float(origin.z))
        for sec in snap.secs {
            let m = Mesher.buildSection(sec.n9, sec.h9, sy: sec.sy, lod: 0, ghosts: snap.ghosts, site: sec.site, chunk: (sec.cx, sec.cz),
                                        adaptive: false, trunkSkip: snap.skip)
            let from = Int(m.trunkWords.x), to = min(Int(m.trunkWords.y), m.detail.count)
            guard to > from else { continue }
            let base = V3(Float(sec.cx * CS), Float(sec.sy * 16), Float(sec.cz * CS))
            var k = from
            while k + 16 <= to {
                var ps = [V3](repeating: .zero, count: 4), uvs = [V2](repeating: .zero, count: 4)
                var n = V3(0, 0, 0), layer: Int32 = 0
                for v in 0..<4 {
                    let w0 = m.detail[k + v * 4], w1 = m.detail[k + v * 4 + 1], w2 = m.detail[k + v * 4 + 2], w3 = m.detail[k + v * 4 + 3]
                    let x = Float(Int16(truncatingIfNeeded: w0 & 0xFFFF)) / 256, y = Float(Int16(truncatingIfNeeded: w0 >> 16)) / 256
                    let z = Float(Int16(truncatingIfNeeded: w1 & 0xFFFF)) / 256
                    ps[v] = base + V3(x, y, z)
                    n += V3(Float(Int8(truncatingIfNeeded: (w1 >> 16) & 0xFF)), Float(Int8(truncatingIfNeeded: (w1 >> 24) & 0xFF)), Float(Int8(truncatingIfNeeded: w2 & 0xFF)))
                    layer = Int32((w2 >> 20) & 2047)
                    uvs[v] = V2(unhalf(w3 & 0xFFFF), unhalf(w3 >> 16))
                }
                k += 16
                // Whose quad: the body's log holding its middle, else the nearest of the logs round that cell.
                let mid = (ps[0] + ps[1] + ps[2] + ps[3]) * 0.25
                let c = IVec3(Int(floor(mid.x)), Int(floor(mid.y)), Int(floor(mid.z)))
                var best: IVec3? = snap.logs[c] != nil ? c : nil
                if best == nil {
                    var bd = Float(2.6)                          // (within about a block and a half)
                    for dy in -1...1 { for dz in -1...1 { for dx in -1...1 {
                        let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                        guard snap.logs[q] != nil else { continue }
                        let d = simd_length_squared(V3(Float(q.x) + 0.5, Float(q.y) + 0.5, Float(q.z) + 0.5) - mid)
                        if d < bd { bd = d; best = q }
                    } } }
                }
                guard let cell = best else { continue }
                let local = IVec3(cell.x - origin.x, cell.y - origin.y, cell.z - origin.z)
                var ci = index[local] ?? -1
                if ci < 0 { ci = Int32(shape.cells.count); index[local] = ci; shape.cells.append(local); shape.blocks.append(snap.logs[cell]!) }
                let l = simd_length(n)
                shape.quads.append(ShapeQuad(p0: ps[0] - o, p1: ps[1] - o, p2: ps[2] - o, p3: ps[3] - o, n: l > 0 ? n / l : V3(0, 1, 0),
                                             u0: uvs[0], u1: uvs[1], u2: uvs[2], u3: uvs[3], layer: layer, cell: ci))
            }
        }
        return shape.quads.isEmpty ? nil : shape
    }

    // A piece split off a felled body (ShipCombat): its part of the shape, its grid cell c the parent's c + lo.
    static func inheritShape(_ from: Ship, _ to: Ship, offset lo: IVec3) {
        guard let sh = shapes[from.id] else { return }
        let part = Shape(owner: sh.owner)
        let d = V3(Float(lo.x), Float(lo.y), Float(lo.z))
        part.cells = sh.cells.map { IVec3($0.x - lo.x, $0.y - lo.y, $0.z - lo.z) }
        part.blocks = sh.blocks
        part.quads = sh.quads.map { q in
            var r = q
            r.p0 = q.p0 - d; r.p1 = q.p1 - d; r.p2 = q.p2 - d; r.p3 = q.p3 - d
            return r
        }
        shapes[to.id] = part
        sh.count = -1                                // (the parent's own cells changed too)
    }

    // Which cells are still there, and a ring where a log now ends at one that went.
    fileprivate static func refresh(_ sh: Shape, _ s: Ship) {
        let g = s.grid
        let trunkT = ShapeTrunks.isTrunk, texT = Blocks.tex
        sh.live = sh.cells.map { trunkT[Int(g.get($0.x, $0.y, $0.z))] }
        sh.caps.removeAll()
        sh.count = s.blockCount
        guard sh.live.contains(false) else { return }
        var at: [IVec3: Int] = [:]
        for (i, c) in sh.cells.enumerated() { at[c] = i }
        for (i, c) in sh.cells.enumerated() where sh.live[i] {
            for dir in World.allDirs {
                guard let j = at[c + dir], !sh.live[j] else { continue }
                let dv = V3(Float(dir.x), Float(dir.y), Float(dir.z))
                let mid = V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5
                // (the log's girth there: how far its quads stand from the line through the two cells)
                var sum: Float = 0, n: Float = 0
                for q in sh.quads where Int(q.cell) == i {
                    for p in [q.p0, q.p1, q.p2, q.p3] {
                        let r = p - mid
                        sum += simd_length(r - dv * simd_dot(r, dv)); n += 1
                    }
                }
                guard n > 0 else { continue }
                let b = Int(sh.blocks[i]), ax = Int(ShapeTrunks.axisOf[b])
                sh.caps.append(ShapeCap(c: mid + dv * 0.5, n: dv, r: min(0.5, sum / n), layer: Int32(texT[b * 6 + ax * 2]), cell: Int32(i)))
            }
        }
    }
}

extension Game {
    // The body's standing shape, drawn with its pose. False where it has none (drawn as cylinders, writeFelled).
    func writeFellShape(_ wr: inout EntityWriter, _ s: Ship, eye: V3, sun: V3) -> Bool {
        guard !Felling.oldFellShape, let sh = Felling.shapes[s.id], sh.owner == ObjectIdentifier(world) else { return false }
        if sh.count != s.blockCount { Felling.refresh(sh, s) }
        let X = s.rot.act(V3(1, 0, 0)), Y = s.rot.act(V3(0, 1, 0)), Z = s.rot.act(V3(0, 0, 1))
        let base = s.pos - eye
        let com = s.com
        @inline(__always) func w(_ p: V3) -> V3 { let l = p - com; return base + X * l.x + Y * l.y + Z * l.z }
        // The light where each log lies (a log half in the ground has its centre in a dark cell: the cell over it too).
        if sh.light.count != sh.cells.count { sh.light = [SIMD2<Int32>](repeating: SIMD2<Int32>(15, 0), count: sh.cells.count) }
        for (i, c) in sh.cells.enumerated() where sh.live[i] {
            let wc = s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
            let lx = Int(floor(wc.x)), ly = Int(floor(wc.y)), lz = Int(floor(wc.z))
            let l = world.lightAt(lx, ly, lz), lu = world.lightAt(lx, ly + 1, lz)
            sh.light[i] = SIMD2<Int32>(Int32(max(l.sky, lu.sky)), Int32(max(l.block, lu.block)))
        }
        let day = daylight
        for q in sh.quads where sh.live[Int(q.cell)] {
            let n = X * q.n.x + Y * q.n.y + Z * q.n.z
            let l = sh.light[Int(q.cell)]
            let c = Felling.shade(n, sky: Int(l.x), block: Int(l.y), day: day, sun: sun)
            wr.quad4(w(q.p0), w(q.p1), w(q.p2), w(q.p3), q.u0, q.u1, q.u2, q.u3, Int(q.layer), V4(c.x, c.y, c.z, 1))
        }
        let sides = 9
        for cap in sh.caps where sh.live[Int(cap.cell)] {
            let n = X * cap.n.x + Y * cap.n.y + Z * cap.n.z
            let l = sh.light[Int(cap.cell)]
            let c = Felling.shade(n, sky: Int(l.x), block: Int(l.y), day: day, sun: sun)
            let col = V4(c.x, c.y, c.z, 1)
            let u = abs(cap.n.y) > 0.5 ? V3(1, 0, 0) : V3(0, 1, 0), v = simd_cross(cap.n, u)
            for k in 0..<sides {
                let t0 = Float(k) / Float(sides) * 2 * .pi, t1 = Float(k + 1) / Float(sides) * 2 * .pi
                let o0 = u * cosf(t0) + v * sinf(t0), o1 = u * cosf(t1) + v * sinf(t1)
                let c0 = V2(0.5, 0.5), p0 = V2(0.5 + 0.5 * cosf(t0), 0.5 + 0.5 * sinf(t0)), p1 = V2(0.5 + 0.5 * cosf(t1), 0.5 + 0.5 * sinf(t1))
                wr.quad4(w(cap.c), w(cap.c + o0 * cap.r), w(cap.c + o1 * cap.r), w(cap.c), c0, p0, p1, c0, Int(cap.layer), col)
            }
        }
        return true
    }
}
