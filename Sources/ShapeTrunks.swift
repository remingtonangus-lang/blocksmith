import Foundation
import simd

// Realistic world (docs/design/realistic-world.md 1.4): round trunks and limbs grown from the log graph, for every
// trunk-class block (ShapeClass.trunk: logs, wood, stems, their stripped forms). Runs on the mesh workers inside
// Mesher.buildSection; draws into the section's detail stream (DetailMesh).
//
// From the logs in a window round the section:
//  - trunk columns: vertical runs of logs standing on the ground (or 3+ long). A column with leaves round its top is a
//    living tree: it tapers with height, leans a little (world-position noise), flares into roots where it meets the
//    ground and closes in a rounded cap under its crown. A column with no crown (a building's post, a stump) is timber:
//    straight, nearly the full block, flat cut ends showing the rings.
//  - 2x2 columns are one fat trunk round their shared centre.
//  - branches: logs joined to a living column through other logs (26-connected, breadth-first from the trunk): each is
//    a limb from its parent's centre to its own, thinner the further out it is, ending in a tapered tip. So branches
//    leave the trunk at an angle and fork, whatever shape the generator gave the tree.
//  - any other log (a log cabin wall, a fallen trunk, a pile): a round log along its own axis.
// Every number comes from the blocks within 10 of a log and from world-position noise, so two sections meeting at a
// joint compute the same ring there (no seams). Logs stay blocks for gameplay (chopping, collision, saves).
enum ShapeTrunks {
    static let axisOf: [UInt8] = (0..<Blocks.count).map { i in
        let k = Blocks.key(BlockID(i))
        return k.hasSuffix("[x]") ? 0 : (k.hasSuffix("[z]") ? 2 : 1)
    }
    static let isTrunk: [Bool] = ShapeClass.kind.map { $0 == .trunk }

    // Window: section-local -M ... 15 + M on each axis (inside the mesher's 48^3 region).
    static let M = 10
    static let W = 16 + 2 * M

    final class Scratch {
        let n = ShapeTrunks.W * ShapeTrunks.W * ShapeTrunks.W
        let rad: UnsafeMutablePointer<Float>      // radius per log cell (0: not a log)
        let par: UnsafeMutablePointer<Int32>      // parent cell index (-1 none)
        let dist: UnsafeMutablePointer<Int16>     // graph steps from a living column (-1 unreached)
        let col: UnsafeMutablePointer<UInt8>      // 1 living column cell, 2 timber column cell
        let kids: UnsafeMutablePointer<UInt8>     // children count
        let queue = GrowBuf<Int32>(4096)
        init() {
            rad = .allocate(capacity: n); par = .allocate(capacity: n); dist = .allocate(capacity: n)
            col = .allocate(capacity: n); kids = .allocate(capacity: n)
        }
        deinit { rad.deallocate(); par.deallocate(); dist.deallocate(); col.deallocate(); kids.deallocate() }
        static var current: Scratch {
            let d = Thread.current.threadDictionary
            if let s = d["blocksmith.trunkScratch"] as? Scratch { return s }
            let s = Scratch()
            d["blocksmith.trunkScratch"] = s
            return s
        }
    }

    @inline(__always) static func wi(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + M) + (z + M) * W + (y + M) * W * W }

    // Is there a trunk-class block in the owned 16^3?
    static func any(_ ctx: DetailContext) -> Bool {
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where isTrunk[Int(ctx.R[ctx.ri(x, y, z)])] { return true } } }
        return false
    }

    static func emit(_ ctx: DetailContext) {
        guard any(ctx) else { return }
        let s = Scratch.current
        let n = s.n
        s.rad.initialize(repeating: 0, count: n); s.par.initialize(repeating: -1, count: n)
        s.dist.initialize(repeating: -1, count: n); s.col.initialize(repeating: 0, count: n); s.kids.initialize(repeating: 0, count: n)
        let leafT = Mesher.leafT, opaqueT = Blocks.opaque, collideT = Blocks.collide
        @inline(__always) func log(_ x: Int, _ y: Int, _ z: Int) -> Bool { isTrunk[Int(ctx.block(x, y, z))] }

        // 1. Columns: vertical runs of logs standing on the ground, each measured over its whole height (full-height
        // reads, so every section that sees a run gives it the same foot, top, radius and taper).
        for z in -M..<(16 + M) { for x in -M..<(16 + M) {
            var y = -M
            while y < 16 + M {
                guard log(x, y, z), y == -M || !log(x, y - 1, z) else { y += 1; continue }
                var bot = y
                while bot > y - 64 && isTrunk[Int(ctx.column(x, bot - 1, z))] { bot -= 1 }
                var top = y
                while top < y + 64 && isTrunk[Int(ctx.column(x, top + 1, z))] { top += 1 }
                let H = top - bot + 1
                let under = Int(ctx.column(x, bot - 1, z))
                let grounded = !isTrunk[under] && !leafT[under] && (opaqueT[under] || collideT[under])
                let vertical = axisOf[Int(ctx.column(x, bot, z))] == 1
                var kind: UInt8 = 0
                if grounded {
                    // A living tree has leaves round the top of its column (or where its lean carries the crown).
                    var crown = false
                    if H >= 3 && vertical {
                        scan: for dy in -2...6 { for dz in -4...4 { for dx in -4...4 where leafT[Int(ctx.column(x + dx, top + dy, z + dz))] { crown = true; break scan } } }
                    }
                    if crown { kind = 1 }
                    else if H <= 2 && rootBeside(ctx, x, bot, z) { kind = 3 }     // a root beside a trunk's foot (upright or lying)
                    else if !vertical || H == 1 && lyingBeside(ctx, x, bot, z) { kind = 0 }   // a log lying on the ground
                    else { kind = 2 }                                               // a stump, a post
                    if kind != 0 {
                        let rb: Float = kind == 1 ? min(0.44, 0.25 + 0.016 * Float(min(H, 12))) : 0.45
                        for yy in max(y, -M)...min(top, 15 + M) {
                            let i = wi(x, yy, z)
                            s.col[i] = kind
                            let t = (Float(yy - bot) + 0.5) / Float(H)
                            s.rad[i] = kind == 1 ? rb * (1 - 0.45 * t) : (kind == 3 ? 0.3 : rb)
                            if kind == 1 { s.dist[i] = 0 }
                        }
                    }
                }
                y = top + 1
            }
        } }

        // 2. Branches: breadth-first from the living columns through touching logs (up to M steps).
        let q = s.queue
        q.count = 0
        for i in 0..<n where s.dist[i] == 0 { q.append(Int32(i)) }
        var head = 0
        while head < q.count {
            let i = Int(q.ptr[head]); head += 1
            let d = s.dist[i]
            if d >= Int16(M) { continue }
            let x = i % W - M, z = (i / W) % W - M, y = i / (W * W) - M
            for (dx, dy, dz) in ShapeTrunks.steps {
                let nx = x + dx, ny = y + dy, nz = z + dz
                guard nx >= -M && ny >= -M && nz >= -M && nx < 16 + M && ny < 16 + M && nz < 16 + M else { continue }
                let j = wi(nx, ny, nz)
                guard s.dist[j] < 0 && (s.col[j] == 0 || s.col[j] == 3) && log(nx, ny, nz) else { continue }
                // Breadth-first with face steps before edge and corner steps: a cell takes the nearest joint as its parent.
                s.dist[j] = d + 1
                s.par[j] = Int32(i)
                s.kids[i] &+= 1
                let pr = s.rad[i] > 0 ? s.rad[i] : 0.2
                s.rad[j] = max(0.07, s.col[j] == 3 ? pr * 0.7 : (d == 0 ? min(0.3, pr * 0.62) : pr * 0.8))
                q.append(Int32(j))
            }
        }

        // 3. Geometry for the owned logs.
        let sides = ctx.lod == 1 ? 6 : (ctx.lod == 2 ? 8 : 10)
        let limbSides = ctx.lod == 0 ? 7 : 5
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 {
            let b = ctx.R[ctx.ri(x, y, z)]
            guard isTrunk[Int(b)] else { continue }
            let base = Int(Blocks.groupBase[Int(b)])
            let bark = Int(Blocks.tex[base * 6]), rings = Int(Blocks.tex[base * 6 + 2])
            let i = wi(x, y, z)
            if s.col[i] == 1 || s.col[i] == 2 {
                column(ctx, s, x, y, z, bark: bark, rings: rings, sides: sides)
            } else if s.dist[i] > 0 && s.par[i] >= 0 {
                limb(ctx, s, i, x, y, z, bark: bark, rings: rings, sides: limbSides)
            } else {
                timber(ctx, x, y, z, axis: timberAxis(ctx, b, x, y, z), bark: bark, rings: rings, sides: sides)
            }
        } } }
    }

    // Neighbour steps, faces first, then edges, then corners (the breadth-first walk prefers the closest joint).
    static let steps: [(Int, Int, Int)] = {
        var r: [(Int, Int, Int)] = []
        for k in 1...3 { for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where abs(dx) + abs(dy) + abs(dz) == k { r.append((dx, dy, dz)) } } } }
        return r
    }()

    // A short log beside a trunk's foot (the generator's root flare): a log beside it at the same height whose column
    // stands 4+ tall.
    static func rootBeside(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            var h = 0
            while h < 4 && isTrunk[Int(ctx.column(x + dx, y + h, z + dz))] { h += 1 }
            if h >= 4 { return true }
        } }
        return false
    }
    // A single upright log with a log beside it at its height and none above or below: one block of a log lying on the
    // ground (the generators write fallen trunks in the upright state).
    static func lyingBeside(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where isTrunk[Int(ctx.column(x + dx, y, z + dz))] { return true }
        return false
    }
    // The axis a lone log lies along: its own axis state, or (upright state, nothing above or below) the way its
    // neighbours run.
    static func timberAxis(_ ctx: DetailContext, _ b: BlockID, _ x: Int, _ y: Int, _ z: Int) -> Int {
        let a = Int(axisOf[Int(b)])
        if a != 1 { return a }
        if isTrunk[Int(ctx.block(x, y + 1, z))] || isTrunk[Int(ctx.block(x, y - 1, z))] { return 1 }
        if isTrunk[Int(ctx.block(x + 1, y, z))] || isTrunk[Int(ctx.block(x - 1, y, z))] { return 0 }
        if isTrunk[Int(ctx.block(x, y, z + 1))] || isTrunk[Int(ctx.block(x, y, z - 1))] { return 2 }
        return 1
    }

    // MARK: Columns

    // The column's centre line at a height (section-local x, z of the cell's centre plus a lean that wanders with world
    // height): living trees only.
    @inline(__always) static func lean(_ ctx: DetailContext, _ cx: Float, _ cz: Float, _ y: Float, living: Bool) -> SIMD2<Float> {
        guard living else { return SIMD2(cx, cz) }
        let p = SIMD3<Float>(cx, y, cz)
        return SIMD2(cx + 0.07 * ctx.noise(p, 0.23, 0x1EA1), cz + 0.07 * ctx.noise(p, 0.23, 0x1EA2))
    }

    static func column(_ ctx: DetailContext, _ s: Scratch, _ x: Int, _ y: Int, _ z: Int, bark: Int, rings: Int, sides: Int) {
        let i = wi(x, y, z)
        let living = s.col[i] == 1
        // 2x2 trunks: one fat trunk round the cluster's centre, drawn by its lowest corner.
        var cx = Float(x) + 0.5, cz = Float(z) + 0.5, scale: Float = 1
        func colAt(_ a: Int, _ b: Int) -> Bool { a >= -M && b >= -M && a < 16 + M && b < 16 + M && s.col[wi(a, y, b)] != 0 }
        if living {
            for (ox, oz) in [(0, 0), (-1, 0), (0, -1), (-1, -1)] {
                let ax = x + ox, az = z + oz
                if colAt(ax, az) && colAt(ax + 1, az) && colAt(ax, az + 1) && colAt(ax + 1, az + 1) {
                    if ox != 0 || oz != 0 { return }              // another corner draws it
                    cx = Float(x) + 1; cz = Float(z) + 1; scale = 2.15
                    break
                }
            }
        }
        let r = s.rad[i] * scale
        let below = y - 1 >= -M ? s.col[wi(x, y - 1, z)] != 0 : true
        let above = y + 1 < 16 + M ? s.col[wi(x, y + 1, z)] != 0 : true
        let rBelow = below && y - 1 >= -M ? s.rad[wi(x, y - 1, z)] * scale : r
        let rAbove = above && y + 1 < 16 + M ? s.rad[wi(x, y + 1, z)] * scale : r
        let r0 = (r + rBelow) * 0.5, r1 = (r + rAbove) * 0.5
        let y0 = Float(y), y1 = Float(y + 1)
        var prof: [(Float, Float)] = []              // (height, radius) from the bottom up
        if !below && living {
            // Root flare into the ground (the smooth ground covers its foot).
            prof.append((y0 - 0.5, r * 2.0)); prof.append((y0 + 0.02, r * 1.6)); prof.append((y0 + 0.3, r * 1.25)); prof.append((y0 + 0.7, r * 1.04))
        } else {
            prof.append((y0, r0))
            if living { prof.append((y0 + 0.5, r)) }
        }
        if above {
            prof.append((y1, r1))
        } else if living {
            prof.append((y1 - 0.15, r * 0.8)); prof.append((y1 + 0.05, r * 0.45)); prof.append((y1 + 0.15, 0.02))
        } else {
            prof.append((y1, r0))
        }
        let roots = !below && living
        var prev: [SIMD3<Float>] = [], prevN: [SIMD3<Float>] = []
        for (k, (h, rr)) in prof.enumerated() {
            let c = lean(ctx, cx, cz, h, living: living)
            var ps: [SIMD3<Float>] = [], ns: [SIMD3<Float>] = []
            for a in 0...sides {
                let th = Float(a % sides) / Float(sides) * 2 * .pi
                let d = SIMD3<Float>(cosf(th), 0, sinf(th))
                var rad = rr
                let wpt = SIMD3<Float>(c.x, h, c.y) + d * rr
                rad *= 1 + (living ? 0.07 : 0.03) * ctx.noise(wpt, 2.1, 0xBA4C)
                if roots && k < 3 { rad *= 1 + 0.4 * max(0, cosf(th * 3 + ctx.hash(x, 0, z, 0x2007) * 6.28)) * (k == 0 ? 1 : (k == 1 ? 0.7 : 0.3)) }
                ps.append(SIMD3(c.x, h, c.y) + d * rad)
                ns.append(d)
            }
            if k > 0 {
                let (h0, rr0) = prof[k - 1]
                let slope = (rr0 - rr) / max(0.05, h - h0)
                for a in 0..<sides {
                    let u0 = Float(a) / Float(sides) * max(1, (2 * .pi * rr).rounded()), u1 = Float(a + 1) / Float(sides) * max(1, (2 * .pi * rr).rounded())
                    let n00 = simd_normalize(prevN[a] + SIMD3(0, slope, 0)), n01 = simd_normalize(prevN[a + 1] + SIMD3(0, slope, 0))
                    let n10 = simd_normalize(ns[a] + SIMD3(0, slope, 0)), n11 = simd_normalize(ns[a + 1] + SIMD3(0, slope, 0))
                    let top = h > y1 + 0.01 && !above
                    let lay = top && h - h0 < 0.12 && !living ? rings : bark
                    // Counter-clockwise from outside: bottom a, bottom a+1, top a+1, top a.
                    ctx.vertex(prev[a], n00, SIMD2(u0, -h0), layer: lay)
                    ctx.vertex(prev[a + 1], n01, SIMD2(u1, -h0), layer: lay)
                    ctx.vertex(ps[a + 1], n11, SIMD2(u1, -h), layer: lay)
                    ctx.vertex(ps[a], n10, SIMD2(u0, -h), layer: lay)
                }
            }
            prev = ps; prevN = ns
        }
        // A cut top (timber, a stump): a flat end showing the rings.
        if !above && !living {
            let c = SIMD2<Float>(cx, cz)
            cap(ctx, center: SIMD3(c.x, y1, c.y), pts: prev, normal: SIMD3(0, 1, 0), layer: rings)
        }
        if !below && !living {
            var ps: [SIMD3<Float>] = []
            for a in 0...sides {
                let th = Float(a % sides) / Float(sides) * 2 * .pi
                ps.append(SIMD3(cx + cosf(th) * r0, y0, cz + sinf(th) * r0))
            }
            cap(ctx, center: SIMD3(cx, y0, cz), pts: ps.reversed(), normal: SIMD3(0, -1, 0), layer: rings)
        }
    }

    // A flat end: a fan of triangles (degenerate quads) from the centre, rings texture projected across it.
    static func cap(_ ctx: DetailContext, center: SIMD3<Float>, pts: [SIMD3<Float>], normal: SIMD3<Float>, layer: Int) {
        // Texture: the end texture projected along the normal's axis, centred on the block.
        let ax = abs(normal.x) > 0.5 ? 0 : (abs(normal.y) > 0.5 ? 1 : 2)
        func uv(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let q = p - floor(center)
            switch ax { case 0: return SIMD2(q.z, -q.y); case 1: return SIMD2(q.x, q.z); default: return SIMD2(q.x, -q.y) }
        }
        for a in 0..<(pts.count - 1) {
            ctx.vertex(center, normal, uv(center), layer: layer)
            ctx.vertex(pts[a + 1], normal, uv(pts[a + 1]), layer: layer)
            ctx.vertex(pts[a], normal, uv(pts[a]), layer: layer)
            ctx.vertex(pts[a], normal, uv(pts[a]), layer: layer)
        }
    }

    // MARK: Limbs

    static func limb(_ ctx: DetailContext, _ s: Scratch, _ i: Int, _ x: Int, _ y: Int, _ z: Int, bark: Int, rings: Int, sides: Int) {
        let p = Int(s.par[i])
        let px = p % W - M, pz = (p / W) % W - M, py = p / (W * W) - M
        var a = SIMD3<Float>(Float(px) + 0.5, Float(py) + 0.5, Float(pz) + 0.5)
        if s.col[p] == 1 {
            let c = lean(ctx, a.x, a.z, a.y, living: true)
            a.x = c.x; a.z = c.y
        }
        let b = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        let ra = s.col[p] != 0 ? min(s.rad[p], s.rad[i] * 1.25) : s.rad[p]
        let rb = s.rad[i]
        tube(ctx, a, b, ra, rb, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i))
        // Knuckle where limbs meet, so joints read as wood growing on, not pipes meeting.
        if s.kids[i] > 0 { knob(ctx, b, rb * 1.05, bark: bark, sides: sides) }
        else if s.col[i] == 3 {
            // A root: it turns down into the ground.
            let d = simd_normalize(simd_normalize(b - a) + SIMD3(0, -1.3, 0))
            knob(ctx, b, rb * 1.02, bark: bark, sides: sides)
            tube(ctx, b, b + d * 0.75, rb, 0.04, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i) ^ 0x2007)
        } else {
            // A tip: the limb runs on past the block's centre and tapers off.
            let d = simd_normalize(b - a)
            tube(ctx, b, b + d * 0.38, rb, 0.02, bark: bark, sides: sides, salt: UInt32(truncatingIfNeeded: i) ^ 0x7177)
        }
    }

    // A tapered tube from a (radius ra) to b (radius rb), bark wrapped round it.
    static func tube(_ ctx: DetailContext, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ ra: Float, _ rb: Float, bark: Int, sides: Int, salt: UInt32) {
        let ax = b - a
        let len = simd_length(ax)
        guard len > 1e-3 else { return }
        let d = ax / len
        let ref = abs(d.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let e1 = simd_normalize(simd_cross(ref, d)), e2 = simd_cross(d, e1)
        let slope = (ra - rb) / len
        let U = max(1, (2 * .pi * max(ra, rb)).rounded())
        for k in 0..<sides {
            let t0 = Float(k) / Float(sides) * 2 * .pi, t1 = Float(k + 1) / Float(sides) * 2 * .pi
            let r0 = e1 * cosf(t0) + e2 * sinf(t0), r1 = e1 * cosf(t1) + e2 * sinf(t1)
            let n0 = simd_normalize(r0 + d * slope), n1 = simd_normalize(r1 + d * slope)
            let u0 = Float(k) / Float(sides) * U, u1 = Float(k + 1) / Float(sides) * U
            ctx.vertex(a + r0 * ra, n0, SIMD2(u0, 0), layer: Int(bark))
            ctx.vertex(a + r1 * ra, n1, SIMD2(u1, 0), layer: Int(bark))
            ctx.vertex(b + r1 * rb, n1, SIMD2(u1, -len), layer: Int(bark))
            ctx.vertex(b + r0 * rb, n0, SIMD2(u0, -len), layer: Int(bark))
        }
    }

    // A small rounded lump (an octahedron-ish ball) where limbs join.
    static func knob(_ ctx: DetailContext, _ c: SIMD3<Float>, _ r: Float, bark: Int, sides: Int) {
        let rows = 3
        for j in 0..<rows {
            let p0 = Float(j) / Float(rows) * .pi - .pi / 2, p1 = Float(j + 1) / Float(rows) * .pi - .pi / 2
            for k in 0..<sides {
                let t0 = Float(k) / Float(sides) * 2 * .pi, t1 = Float(k + 1) / Float(sides) * 2 * .pi
                func pt(_ ph: Float, _ th: Float) -> SIMD3<Float> { SIMD3(cosf(ph) * cosf(th), sinf(ph), cosf(ph) * sinf(th)) }
                let a = pt(p0, t0), b = pt(p0, t1), cc = pt(p1, t1), d = pt(p1, t0)
                ctx.vertex(c + a * r, a, SIMD2(Float(k) * 0.3, p0), layer: bark)
                ctx.vertex(c + b * r, b, SIMD2(Float(k + 1) * 0.3, p0), layer: bark)
                ctx.vertex(c + cc * r, cc, SIMD2(Float(k + 1) * 0.3, p1), layer: bark)
                ctx.vertex(c + d * r, d, SIMD2(Float(k) * 0.3, p1), layer: bark)
            }
        }
    }

    // MARK: Timber

    // A log on its own (a cabin wall, a fallen trunk, a pile): round along its axis, flat cut ends where the run stops.
    static func timber(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, axis: Int, bark: Int, rings: Int, sides: Int) {
        var o = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
        var d = SIMD3<Float>(0, 0, 0); d[axis] = 1
        let r: Float = 0.46
        o -= d * 0.5
        let a = o, b = o + d
        tube(ctx, a, b, r, r, bark: bark, sides: sides, salt: 0)
        var step = SIMD3<Int>(0, 0, 0); step[axis] = 1
        let next = ctx.block(x + step.x, y + step.y, z + step.z), prev = ctx.block(x - step.x, y - step.y, z - step.z)
        let e1v: SIMD3<Float> = axis == 1 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let e2v = simd_cross(d, e1v)
        func ring(_ c: SIMD3<Float>) -> [SIMD3<Float>] {
            (0...sides).map { k in let t = Float(k % sides) / Float(sides) * 2 * .pi; return c + (e1v * cosf(t) + e2v * sinf(t)) * r }
        }
        if !(isTrunk[Int(next)] && axisOf[Int(next)] == UInt8(axis)) { cap(ctx, center: b, pts: ring(b).reversed(), normal: d, layer: rings) }
        if !(isTrunk[Int(prev)] && axisOf[Int(prev)] == UInt8(axis)) { cap(ctx, center: a, pts: ring(a), normal: -d, layer: rings) }
    }
}
