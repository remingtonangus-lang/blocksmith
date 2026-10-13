import Foundation
import simd

// Realistic world, layer 2 (docs/design/realistic-world.md 2.2-2.3): procedural fracture, no pre-made damage stages.
// What comes off is cut on the spot from the material: the bite a tool actually touched, or a whole block split by a 3D
// Voronoi diagram into convex pieces, a new pattern every hit. Pieces keep the source box's outer faces, tagged with the
// block face they came from so they show exactly that part of its texture, and get inner faces where they broke.
// Pure value geometry with no world access: it runs on the mesh workers, each worker with its own Workspace.
enum Fracture {
    // MARK: Pieces

    // Face tag of fresh broken material (drawn darker); 0...5 are the source box's own faces, +X -X +Y -Y +Z -Z.
    static let inner: UInt8 = 6

    // Rigid-body data for unit density: mass = volume * density, inertia * density.
    struct MassProps {
        var volume: Float = 0                         // blocks^3
        var centroid = SIMD3<Float>(repeating: 0)     // piece-local frame (origin + centroid in the caller's frame)
        var inertia = simd_float3x3()                 // about the centroid, along the caller's axes
    }

    // A convex piece. Vertices stay where the material was (local to `origin`), so texture coordinates come from the
    // original position; the mesh and the body are centred on mass.centroid.
    struct Poly {
        var origin: SIMD3<Float>          // caller-frame point the local coordinates start from (the source box's min)
        var verts: [SIMD3<Float>]
        var faceStart: [UInt16]           // face f's loop is loop[faceStart[f] ..< faceStart[f + 1]], CCW from outside
        var loop: [UInt16]
        var planes: [SIMD4<Float>]        // per face: unit outward normal and offset w (inside where n.v <= w), local
        var tags: [UInt8]                 // per face: 0...5 source box face, Fracture.inner for a cut face
        var mass: MassProps

        var faceCount: Int { tags.count }
        var edgeCount: Int { loop.count / 2 }
        var center: SIMD3<Float> { origin + mass.centroid }     // where the piece's body starts, caller's frame

        // The whole box as one piece (all six faces outer).
        static func box(min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> Poly {
            let s = pointwiseMax(hi - lo, SIMD3(repeating: 1e-6))
            var v = [SIMD3<Float>](repeating: .zero, count: 8)
            for i in 0..<8 { v[i] = SIMD3(i & 1 != 0 ? s.x : 0, i & 2 != 0 ? s.y : 0, i & 4 != 0 ? s.z : 0) }
            let ix = s.x * s.x, iy = s.y * s.y, iz = s.z * s.z, vol = s.x * s.y * s.z
            let inertia = simd_float3x3(diagonal: SIMD3(iy + iz, ix + iz, ix + iy) * (vol / 12))
            return Poly(origin: lo, verts: v, faceStart: [0, 4, 8, 12, 16, 20, 24], loop: Fracture.boxLoop,
                        planes: [SIMD4(1, 0, 0, s.x), SIMD4(-1, 0, 0, 0), SIMD4(0, 1, 0, s.y), SIMD4(0, -1, 0, 0),
                                 SIMD4(0, 0, 1, s.z), SIMD4(0, 0, -1, 0)],
                        tags: [0, 1, 2, 3, 4, 5], mass: MassProps(volume: vol, centroid: s * 0.5, inertia: inertia))
        }
    }

    // Box corners are i = x + 2y + 4z; loops per face +X -X +Y -Y +Z -Z, CCW seen from outside.
    fileprivate static let boxLoop: [UInt16] = [1, 3, 7, 5, 0, 4, 6, 2, 2, 6, 7, 3, 0, 1, 5, 4, 4, 5, 7, 6, 0, 2, 3, 1]

    // Per-thread scratch: fixed-capacity work polyhedra and cut tables, so fracturing allocates only the pieces it
    // returns. Not thread-safe: one per worker.
    final class Workspace {
        let maxVerts: Int, maxFaces: Int, maxLoop: Int
        var minVolume: Float = 2e-6       // pieces below this (blocks^3) are dropped, not merged
        var minWidth: Float = 0.004       // ... and pieces thinner than this along any face normal (slivers)
        // Counters for tests and tuning.
        fileprivate(set) var cutRetries = 0, cutFailures = 0, droppedPieces = 0
        fileprivate(set) var droppedVolume: Float = 0
        func resetCounters() { cutRetries = 0; cutFailures = 0; droppedPieces = 0; droppedVolume = 0 }

        fileprivate var r: WP, a: WP, b: WP
        fileprivate let k: Scratch
        fileprivate let seeds: UnsafeMutablePointer<SIMD3<Float>>
        fileprivate let order: UnsafeMutablePointer<Int32>
        fileprivate let d2: UnsafeMutablePointer<Float>
        fileprivate let planes: UnsafeMutablePointer<SIMD4<Float>>
        fileprivate static let maxSeeds = 32, maxPlanes = 32

        // Capacities bound one piece (a Voronoi cell of a box has ~10-30 faces); indices are UInt16.
        init(maxVerts: Int = 512, maxFaces: Int = 192, maxLoop: Int = 3072) {
            let mv = min(max(maxVerts, 16), 65535), mf = min(max(maxFaces, 16), 65535), ml = min(max(maxLoop, 64), 65535)
            self.maxVerts = mv; self.maxFaces = mf; self.maxLoop = ml
            r = WP(mv, mf, ml); a = WP(mv, mf, ml); b = WP(mv, mf, ml)
            k = Scratch(mv, mf, ml)
            seeds = .allocate(capacity: Workspace.maxSeeds)
            order = .allocate(capacity: Workspace.maxSeeds)
            d2 = .allocate(capacity: Workspace.maxSeeds)
            planes = .allocate(capacity: Workspace.maxPlanes)
        }
        deinit {
            r.free(); a.free(); b.free(); k.free()
            seeds.deallocate(); order.deallocate(); d2.deallocate(); planes.deallocate()
        }
    }

    // MARK: Shatter

    // Breaks the box (caller's frame, block-local coordinates keep Float precise) into about `count` (1...32) convex
    // Voronoi pieces: seeds crowd round `impact` (small pieces there, big ones far away; `crowding` 0 = even ... 1 =
    // strong, a bullet more than a blast) and drift a little along the blow `direction` (may be zero). Deterministic
    // per seed. Appends to `pieces`; returns how many it appended.
    @discardableResult
    static func shatter(min lo: SIMD3<Float>, max hi: SIMD3<Float>, impact: SIMD3<Float>, direction: SIMD3<Float>,
                        count: Int, seed: UInt32, crowding: Float = 0.7, workspace ws: Workspace,
                        into pieces: inout [Poly]) -> Int {
        let size = pointwiseMax(hi - lo, SIMD3(repeating: 1e-4))
        var r = ws.r
        loadBox(&r, size)
        return split(region: r, volume: size.x * size.y * size.z, origin: lo, impact: impact - lo,
                     direction: direction, count: count, seed: seed, crowding: crowding, ws: ws, into: &pieces)
    }

    // The same for a piece that breaks again (a blast hitting debris): pieces keep its frame and outer faces.
    @discardableResult
    static func shatter(_ piece: Poly, impact: SIMD3<Float>, direction: SIMD3<Float>, count: Int, seed: UInt32,
                        crowding: Float = 0.7, workspace ws: Workspace, into pieces: inout [Poly]) -> Int {
        var r = ws.r
        guard load(piece, &r, ws.k) else { return 0 }
        return split(region: r, volume: piece.mass.volume, origin: piece.origin, impact: impact - piece.origin,
                     direction: direction, count: count, seed: seed, crowding: crowding, ws: ws, into: &pieces)
    }

    fileprivate static func split(region r: WP, volume: Float, origin: SIMD3<Float>, impact: SIMD3<Float>,
                                  direction: SIMD3<Float>, count: Int, seed: UInt32, crowding: Float, ws: Workspace,
                                  into pieces: inout [Poly]) -> Int {
        let (lo, hi) = bounds(r)
        let eps = epsilon(hi - lo)
        let focus = pointwiseMin(pointwiseMax(impact, lo), hi)
        let far = pointwiseMax(focus - lo, hi - focus)
        let reach = length3(far)
        var drift = SIMD3<Float>(repeating: 0)
        let dl = length3(direction)
        if dl > 1e-6 && dl.isFinite { drift = direction * (0.14 * reach / dl) }
        var rng = Rand(seed, 0x5A17)
        let n = max(1, min(Workspace.maxSeeds, count))
        let placed = n < 2 ? 0 : placeSeeds(r, lo: lo, hi: hi, volume: volume, count: n, focus: focus, reach: reach,
                                             bias: min(max(crowding, 0), 1), drift: drift, rng: &rng,
                                             out: ws.seeds)
        if placed < 2 {
            guard let p = finish(r, origin, ws) else { return 0 }
            pieces.append(p)
            return 1
        }
        return voronoi(r, ws.a, ws.b, seeds: placed, origin: origin, eps: eps, ws: ws, into: &pieces)
    }

    // MARK: Bite

    // The volume a tool actually touches ("the pickaxe mines only what it touches"): the box (caller's frame) cut by a
    // rough ellipsoid centred on `contact` (on the box surface), flattened along the outward `normal`, `radius`
    // 0.15...0.6 blocks; then split into 2-4 chips. Appends the chips; returns the bitten volume (what the block loses,
    // also when it is too small to throw chips) and the number of chips appended.
    @discardableResult
    static func bite(min lo: SIMD3<Float>, max hi: SIMD3<Float>, contact: SIMD3<Float>, normal: SIMD3<Float>,
                     radius: Float, seed: UInt32, workspace ws: Workspace,
                     into chips: inout [Poly]) -> (volume: Float, chips: Int) {
        let size = pointwiseMax(hi - lo, SIMD3(repeating: 1e-4))
        let c = pointwiseMin(pointwiseMax(contact - lo, SIMD3(repeating: 0)), size)
        let n = outwardNormal(normal, c, size)
        var rng = Rand(seed, 0xB17E)
        let np = makeBitePlanes(c, n, radius, &rng, ws.planes)
        var cur = ws.r, tmp = ws.a
        loadBox(&cur, size)
        let eps = epsilon(size)
        for i in 0..<np {
            let p = ws.planes[i]
            switch cutRobust(cur, &tmp, SIMD3(p.x, p.y, p.z), p.w, inner, eps, ws) {
            case .cut: swap(&cur, &tmp)
            case .empty: return (0, 0)
            default: break
            }
        }
        let m = massCore(cur.v, cur.nv, cur.fs, cur.nf, cur.li)
        guard m.volume >= ws.minVolume else { return (max(0, m.volume), 0) }
        let (blo, bhi) = bounds(cur)
        // Bigger bites crack into more chips; a crumb stays whole.
        var want = 2 + Int(rng.next() % 3)
        if m.volume < 40 * ws.minVolume { want = 1 }
        let placed = want < 2 ? 0 : placeSeeds(cur, lo: blo, hi: bhi, volume: m.volume, count: want,
                                               focus: m.centroid, reach: 1, bias: 0, drift: .zero, rng: &rng,
                                               out: ws.seeds)
        if placed < 2 {
            guard let p = finish(cur, lo, ws) else { return (m.volume, 0) }
            chips.append(p)
            return (m.volume, 1)
        }
        let made = voronoi(cur, tmp, ws.b, seeds: placed, origin: lo, eps: eps, ws: ws, into: &chips)
        return (m.volume, made)
    }

    // The bite's cutting planes in the caller's frame (inside where n.x <= w): the same rough flattened ellipsoid that
    // bite() removes for this seed, so the mesher can carve the crater that matches the chips that flew off. Pass the
    // outward normal (bite() flips an inward one) and a contact on the box.
    static func bitePlanes(contact: SIMD3<Float>, normal: SIMD3<Float>, radius: Float, seed: UInt32,
                           into planes: inout [SIMD4<Float>]) {
        var rng = Rand(seed, 0xB17E)
        let buf = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: Workspace.maxPlanes)
        defer { buf.deallocate() }
        let nl = length3(normal)
        let n = nl > 1e-6 ? normal / nl : SIMD3<Float>(0, 1, 0)
        let np = makeBitePlanes(contact, n, radius, &rng, buf)
        planes.removeAll(keepingCapacity: true)
        for i in 0..<np { planes.append(buf[i]) }
    }

    // How far a point inside the bite can move along d before it leaves it: the crater floor under a face vertex when
    // d is the inward normal. 0 when the point is outside.
    static func biteDepth(_ planes: [SIMD4<Float>], from p: SIMD3<Float>, along d: SIMD3<Float>) -> Float {
        var t = Float.greatestFiniteMagnitude
        for pl in planes {
            let n = SIMD3(pl.x, pl.y, pl.z)
            let gap = pl.w - dot3(n, p)
            if gap < 0 { return 0 }
            let nd = dot3(n, d)
            if nd > 1e-9 { t = min(t, gap / nd) }
        }
        return t == .greatestFiniteMagnitude ? 0 : t
    }

    // MARK: Clip

    // Cuts a piece by a plane in the caller's frame (keeps n.x <= w; n need not be unit) and caps the cut with a face
    // tagged `tag`. Returns the piece unchanged when the plane misses it (or would only shave a hair, under 4e-5 of
    // its size, off it), nil when nothing (or only a crumb or sliver) is left.
    static func clip(_ p: Poly, plane: SIMD4<Float>, tag: UInt8 = inner, workspace ws: Workspace) -> Poly? {
        var n = SIMD3(plane.x, plane.y, plane.z)
        let nl = length3(n)
        guard nl > 1e-12, nl.isFinite else { return p }
        n /= nl
        let w = plane.w / nl - dot3(n, p.origin)
        var src = ws.r, dst = ws.a
        guard load(p, &src, ws.k) else { return p }
        let (lo, hi) = bounds(src)
        switch cutRobust(src, &dst, n, w, tag, epsilon(hi - lo), ws) {
        case .unchanged, .failed: return p
        case .empty: return nil
        case .cut: return finish(dst, p.origin, ws)
        }
    }

    // MARK: Mass

    // Volume, centroid and inertia (about the centroid, unit density) by exact integration over tetrahedra.
    static func massProperties(_ p: Poly) -> MassProps {
        guard !p.verts.isEmpty, !p.loop.isEmpty else { return MassProps() }
        return p.verts.withUnsafeBufferPointer { v in
            p.faceStart.withUnsafeBufferPointer { fs in
                p.loop.withUnsafeBufferPointer { li in
                    massCore(v.baseAddress!, v.count, fs.baseAddress!, p.faceCount, li.baseAddress!)
                }
            }
        }
    }

    // Principal moments (ascending) and the rotation whose columns are their axes (right-handed): the body frame in
    // which the inertia tensor is diagonal. Jacobi sweeps on the symmetric 3x3.
    static func principal(_ m: MassProps) -> (moments: SIMD3<Float>, axes: simd_float3x3) {
        let c = m.inertia.columns
        var a = SIMD16<Double>(repeating: 0), v = SIMD16<Double>(repeating: 0)
        for j in 0..<3 {
            let col = j == 0 ? c.0 : (j == 1 ? c.1 : c.2)
            for i in 0..<3 { a[i * 3 + j] = Double(col[i]) }
            v[j * 3 + j] = 1
        }
        let scale = abs(a[0]) + abs(a[4]) + abs(a[8]) + 1e-30
        for _ in 0..<16 {
            let off = a[1] * a[1] + a[2] * a[2] + a[5] * a[5]
            if off < 1e-26 * scale * scale { break }
            for pair in 0..<3 {
                let p = pair == 2 ? 1 : 0, q = pair == 0 ? 1 : 2
                let apq = a[p * 3 + q]
                if abs(apq) < 1e-30 { continue }
                let theta = (a[q * 3 + q] - a[p * 3 + p]) / (2 * apq)
                let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
                let cs = 1 / (t * t + 1).squareRoot(), sn = t * cs
                for r in 0..<3 {      // a = J^T a J, applied as columns then rows
                    let arp = a[r * 3 + p], arq = a[r * 3 + q]
                    a[r * 3 + p] = cs * arp - sn * arq; a[r * 3 + q] = sn * arp + cs * arq
                }
                for r in 0..<3 {
                    let apr = a[p * 3 + r], aqr = a[q * 3 + r]
                    a[p * 3 + r] = cs * apr - sn * aqr; a[q * 3 + r] = sn * apr + cs * aqr
                }
                for r in 0..<3 {
                    let vrp = v[r * 3 + p], vrq = v[r * 3 + q]
                    v[r * 3 + p] = cs * vrp - sn * vrq; v[r * 3 + q] = sn * vrp + cs * vrq
                }
            }
        }
        var i0 = 0, i1 = 1, i2 = 2             // ascending moments
        if a[i0 * 4] > a[i1 * 4] { swap(&i0, &i1) }
        if a[i1 * 4] > a[i2 * 4] { swap(&i1, &i2) }
        if a[i0 * 4] > a[i1 * 4] { swap(&i0, &i1) }
        func axis(_ j: Int) -> SIMD3<Float> { SIMD3(Float(v[j]), Float(v[3 + j]), Float(v[6 + j])) }
        let x = axis(i0), y = axis(i1)
        var z = axis(i2)
        if dot3(cross3(x, y), z) < 0 { z = -z }
        let moments = SIMD3(Float(a[i0 * 4]), Float(a[i1 * 4]), Float(a[i2 * 4]))
        return (moments, simd_float3x3(columns: (x, y, z)))
    }

    // MARK: Mesh

    // One vertex of a piece's mesh. Position is relative to the piece centroid (the body's origin); uv is the block
    // texture coordinate (0...1 within a block) projected from where the material was, with the block mesher's
    // mapping for the face's dominant axis, so outer faces show exactly the part of the texture they came from.
    struct MeshVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
        var tag: UInt8            // 0...5 outer (that block face's texture), Fracture.inner: broken face, drawn darker
    }

    static func quadCount(_ p: Poly) -> Int {
        var q = 0
        for f in 0..<p.faceCount { q += (Int(p.faceStart[f + 1]) - Int(p.faceStart[f]) - 1) / 2 }
        return q
    }

    // Appends the piece as quads (4 vertices each, CCW from outside, a triangle repeats its last vertex) for the
    // entity pass's shared quad index buffer. Reuse `out` (removeAll(keepingCapacity:)) to keep it allocation-free.
    @discardableResult
    static func emitQuads(_ p: Poly, into out: inout [MeshVertex]) -> Int {
        let frac = p.origin - p.origin.rounded(.down)
        let c = p.mass.centroid
        var quads = 0
        for f in 0..<p.faceCount {
            let pl = p.planes[f]
            let n = SIMD3(pl.x, pl.y, pl.z)
            let tag = p.tags[f]
            let axis = tag < 6 ? Int(tag) : dominantFace(n)
            let s0 = Int(p.faceStart[f]), s1 = Int(p.faceStart[f + 1])
            let v0 = p.verts[Int(p.loop[s0])]
            let m0 = MeshVertex(position: v0 - c, normal: n, uv: blockUV(axis, frac + v0), tag: tag)
            var e = s0 + 1
            while e + 1 < s1 {
                out.append(m0)
                for j in 0..<3 {
                    let ej = min(e + j, s1 - 1)
                    let v = p.verts[Int(p.loop[ej])]
                    out.append(MeshVertex(position: v - c, normal: n, uv: blockUV(axis, frac + v), tag: tag))
                }
                e += 2; quads += 1
            }
        }
        return quads
    }

    // The block mesher's face UVs (Mesher.faceUV) in blocks, for block-local q.
    @inline(__always) static func blockUV(_ face: Int, _ q: SIMD3<Float>) -> SIMD2<Float> {
        switch face {
        case 0: return SIMD2(1 - q.z, 1 - q.y)
        case 1: return SIMD2(q.z, 1 - q.y)
        case 2: return SIMD2(q.x, q.z)
        case 3: return SIMD2(q.x, 1 - q.z)
        case 4: return SIMD2(q.x, 1 - q.y)
        default: return SIMD2(1 - q.x, 1 - q.y)
        }
    }

    @inline(__always) static func dominantFace(_ n: SIMD3<Float>) -> Int {
        let ax = n.x.magnitude, ay = n.y.magnitude, az = n.z.magnitude
        if ax >= ay && ax >= az { return n.x >= 0 ? 0 : 1 }
        if ay >= az { return n.y >= 0 ? 2 : 3 }
        return n.z >= 0 ? 4 : 5
    }

    // MARK: Checks

    // nil when the piece is a closed convex polyhedron (every edge used once each way, V - E + F = 2, every vertex on
    // the inner side of every face plane, faces planar and CCW from outside, unit normals, no NaN), else what is wrong.
    static func validate(_ p: Poly, tolerance tol: Float = 1e-4) -> String? {
        let nf = p.faceCount
        guard nf >= 4, p.verts.count >= 4, p.faceStart.count == nf + 1, p.planes.count == nf,
              Int(p.faceStart[nf]) == p.loop.count else { return "malformed arrays" }
        for v in p.verts where !(v.x.isFinite && v.y.isFinite && v.z.isFinite) { return "NaN vertex" }
        var edges = Set<UInt32>()
        for f in 0..<nf {
            let s0 = Int(p.faceStart[f]), s1 = Int(p.faceStart[f + 1])
            if s1 - s0 < 3 { return "face \(f) has \(s1 - s0) vertices" }
            let pl = p.planes[f]
            let n = SIMD3(pl.x, pl.y, pl.z)
            if !(abs(length3(n) - 1) < 1e-3) { return "face \(f) normal not unit" }
            var newell = SIMD3<Float>(repeating: 0)
            let v0 = p.verts[Int(p.loop[s0])]
            for e in s0..<s1 {
                let a = p.loop[e], b = p.loop[e + 1 < s1 ? e + 1 : s0]
                if Int(a) >= p.verts.count { return "index out of range" }
                if !edges.insert(UInt32(a) << 16 | UInt32(b)).inserted { return "edge \(a)->\(b) used twice" }
                let va = p.verts[Int(a)], vb = p.verts[Int(b)]
                newell += cross3(va - v0, vb - v0)
                if abs(dot3(n, va) - pl.w) > tol { return "face \(f) not planar (\(dot3(n, va) - pl.w))" }
            }
            if dot3(newell, n) <= 0 { return "face \(f) not CCW from outside" }
            for v in p.verts where dot3(n, v) - pl.w > tol { return "not convex (face \(f): \(dot3(n, v) - pl.w))" }
        }
        for e in edges where !edges.contains((e & 0xFFFF) << 16 | e >> 16) { return "open edge" }
        let euler = p.verts.count - edges.count / 2 + nf
        if euler != 2 { return "Euler V-E+F = \(euler)" }
        return nil
    }

    // MARK: Internals: work polyhedra

    // A polyhedron in workspace memory (fixed capacity, no ARC): the hot cut loop runs on these.
    fileprivate struct WP {
        let v: UnsafeMutablePointer<SIMD3<Float>>
        let fs: UnsafeMutablePointer<UInt16>
        let pl: UnsafeMutablePointer<SIMD4<Float>>
        let tg: UnsafeMutablePointer<UInt8>
        let li: UnsafeMutablePointer<UInt16>
        var nv = 0, nf = 0
        init(_ mv: Int, _ mf: Int, _ ml: Int) {
            v = .allocate(capacity: mv); fs = .allocate(capacity: mf + 1); pl = .allocate(capacity: mf)
            tg = .allocate(capacity: mf); li = .allocate(capacity: ml)
            fs[0] = 0
        }
        func free() { v.deallocate(); fs.deallocate(); pl.deallocate(); tg.deallocate(); li.deallocate() }
    }

    fileprivate struct Scratch {
        let dist: UnsafeMutablePointer<Float>       // per source vertex: signed distance to the plane
        let side: UnsafeMutablePointer<Int8>        // -1 inside, 0 on (welded), 1 outside
        let remap: UnsafeMutablePointer<Int32>      // source -> kept vertex
        let on: UnsafeMutablePointer<UInt8>         // per kept vertex: lies on the cut plane
        let next: UnsafeMutablePointer<Int32>       // cap loop successor, -1 between cuts
        let uf: UnsafeMutablePointer<Int32>         // weld: union-find parent per kept vertex
        let xa: UnsafeMutablePointer<Int32>, xb: UnsafeMutablePointer<Int32>, xi: UnsafeMutablePointer<Int32>
        let ef: UnsafeMutablePointer<Int32>, et: UnsafeMutablePointer<Int32>   // on-plane edges of kept faces
        let maxV: Int, maxF: Int, maxL: Int
        init(_ mv: Int, _ mf: Int, _ ml: Int) {
            maxV = mv; maxF = mf; maxL = ml
            dist = .allocate(capacity: mv); side = .allocate(capacity: mv); remap = .allocate(capacity: mv)
            on = .allocate(capacity: mv); next = .allocate(capacity: mv); uf = .allocate(capacity: mv)
            next.initialize(repeating: -1, count: mv)
            xa = .allocate(capacity: ml); xb = .allocate(capacity: ml); xi = .allocate(capacity: ml)
            ef = .allocate(capacity: ml); et = .allocate(capacity: ml)
        }
        func free() {
            dist.deallocate(); side.deallocate(); remap.deallocate(); on.deallocate(); next.deallocate(); uf.deallocate()
            xa.deallocate(); xb.deallocate(); xi.deallocate(); ef.deallocate(); et.deallocate()
        }
    }

    fileprivate enum Cut { case unchanged, cut, empty, failed }

    // Keeps the part of s with n.v <= w in d, capped by a face (n, w). Vertices within eps of the plane are welded onto
    // it (they stay, never split an edge), a cut that would only shave a few eps off is skipped, and edges the cut
    // leaves shorter than a few eps collapse, so near-coplanar or near-vertex planes make no sliver faces, needle edges
    // or duplicate points. The cap loop is chained from the on-plane edges of the kept faces whose twin face went away,
    // so the result is a closed manifold by construction; anything else (exact degeneracies) reports .failed.
    fileprivate static func cut(_ s: WP, _ d: inout WP, _ n: SIMD3<Float>, _ w: Float, _ tag: UInt8,
                                _ eps: Float, _ k: Scratch) -> Cut {
        let nv = s.nv
        var nIn = 0, nOut = 0
        var deepest: Float = 0
        for i in 0..<nv {
            let di = dot3(n, s.v[i]) - w
            k.dist[i] = di
            if di > eps { k.side[i] = 1; nOut += 1; deepest = max(deepest, di) }
            else if di < -eps { k.side[i] = -1; nIn += 1 } else { k.side[i] = 0 }
        }
        if nOut == 0 || deepest <= 4 * eps { return .unchanged }
        if nIn == 0 { return .empty }
        var dv = 0
        for i in 0..<nv where k.side[i] <= 0 {
            d.v[dv] = s.v[i]; k.on[dv] = k.side[i] == 0 ? 1 : 0
            k.remap[i] = Int32(dv); dv += 1
        }
        var nx = 0, nf = 0, nl = 0, ne = 0
        d.fs[0] = 0
        for f in 0..<s.nf {
            let a0 = Int(s.fs[f]), a1 = Int(s.fs[f + 1])
            if nl + (a1 - a0) + 2 > k.maxL || nf + 2 > k.maxF { return .failed }
            let start = nl
            var allOn = true
            for e in a0..<a1 {
                let ia = Int(s.li[e]), ib = Int(s.li[e + 1 < a1 ? e + 1 : a0])
                let sa = k.side[ia], sb = k.side[ib]
                if sa <= 0 {
                    d.li[nl] = UInt16(truncatingIfNeeded: k.remap[ia]); nl += 1
                    if sa < 0 { allOn = false }
                }
                if sa * sb < 0 {
                    // The edge crosses: both faces on it share one new vertex.
                    let lo = Int32(min(ia, ib)), hi = Int32(max(ia, ib))
                    var x: Int32 = -1
                    var q = 0
                    while q < nx { if k.xa[q] == lo && k.xb[q] == hi { x = k.xi[q]; break }; q += 1 }
                    if x < 0 {
                        if dv >= k.maxV { return .failed }
                        let iin = sa < 0 ? ia : ib, iout = sa < 0 ? ib : ia
                        let di = k.dist[iin], t = di / (di - k.dist[iout])
                        let pin = s.v[iin]
                        d.v[dv] = pin + (s.v[iout] - pin) * t
                        k.on[dv] = 1
                        x = Int32(dv); dv += 1
                        k.xa[nx] = lo; k.xb[nx] = hi; k.xi[nx] = x; nx += 1
                    }
                    d.li[nl] = UInt16(truncatingIfNeeded: x); nl += 1
                }
            }
            // A face left with under 3 corners is gone; one lying in the cut plane folds into the cap.
            if nl - start < 3 || allOn { nl = start; continue }
            d.pl[nf] = s.pl[f]; d.tg[nf] = s.tg[f]
            for e in start..<nl {
                let ia = d.li[e], ib = d.li[e + 1 < nl ? e + 1 : start]
                if k.on[Int(ia)] != 0 && k.on[Int(ib)] != 0 { k.ef[ne] = Int32(ia); k.et[ne] = Int32(ib); ne += 1 }
            }
            nf += 1; d.fs[nf] = UInt16(nl)
        }
        // Cap: on-plane edges a->b whose twin b->a is gone bound it, run the other way (b then a).
        var ok = true, ncap = 0
        for i in 0..<ne {
            let a = k.ef[i]
            if a < 0 { continue }
            let b = k.et[i]
            var j = i + 1, twin = false
            while j < ne { if k.ef[j] == b && k.et[j] == a { k.ef[j] = -1; twin = true; break }; j += 1 }
            if twin { k.ef[i] = -1; continue }
            if k.next[Int(b)] >= 0 { ok = false } else { k.next[Int(b)] = a; ncap += 1 }
        }
        if ok && ncap >= 3 && nl + ncap <= k.maxL {
            var first: Int32 = -1
            for i in 0..<ne where k.ef[i] >= 0 { first = k.et[i]; break }
            var cur = first, steps = 0
            while true {
                d.li[nl] = UInt16(truncatingIfNeeded: cur); nl += 1; steps += 1
                cur = k.next[Int(cur)]
                if cur == first || cur < 0 || steps >= ncap { break }
            }
            ok = cur == first && steps == ncap
        } else {
            ok = false
        }
        for i in 0..<ne { k.next[Int(k.et[i])] = -1 }
        if !ok { return .failed }
        d.pl[nf] = SIMD4(n.x, n.y, n.z, w); d.tg[nf] = tag; nf += 1; d.fs[nf] = UInt16(nl)
        // Weld: an edge touching the cut shorter than 6 eps (the plane passed just past a corner) collapses into its
        // older end, so faces stay planar within 6 eps; faces left with under 3 corners go.
        let weld2 = 36 * eps * eps
        var short = false
        for f in 0..<nf where !short {
            let s0 = Int(d.fs[f]), s1 = Int(d.fs[f + 1])
            for e in s0..<s1 {
                let a = Int(d.li[e]), b = Int(d.li[e + 1 < s1 ? e + 1 : s0])
                if (k.on[a] | k.on[b]) != 0 {
                    let dd = d.v[a] - d.v[b]
                    if dot3(dd, dd) < weld2 { short = true; break }
                }
            }
        }
        if short {
            nl = weldShort(&d, nf: &nf, dv: dv, weld2: weld2, k)
        }
        // Drop vertices no face uses any more (an on-plane corner whose faces all folded into the cap).
        for i in 0..<dv { k.on[i] = 0 }
        for e in 0..<nl { k.on[Int(d.li[e])] = 1 }
        var used = 0
        for i in 0..<dv where k.on[i] != 0 { used += 1 }
        if used != dv {
            var m = 0
            for i in 0..<dv where k.on[i] != 0 { d.v[m] = d.v[i]; k.remap[i] = Int32(m); m += 1 }
            for e in 0..<nl { d.li[e] = UInt16(truncatingIfNeeded: k.remap[Int(d.li[e])]) }
            dv = m
        }
        d.nv = dv; d.nf = nf
        if nl & 1 != 0 || dv - nl / 2 + nf != 2 { return .failed }
        return .cut
    }

    // Collapses the short cut edges found by cut() (union-find, root = lowest index = oldest vertex, which keeps its
    // position), rewrites the loops without repeats and drops faces under 3 corners. Returns the new loop length.
    fileprivate static func weldShort(_ d: inout WP, nf: inout Int, dv: Int, weld2: Float, _ k: Scratch) -> Int {
        func find(_ x: Int) -> Int {
            var x = x
            while Int(k.uf[x]) != x { k.uf[x] = k.uf[Int(k.uf[x])]; x = Int(k.uf[x]) }
            return x
        }
        for i in 0..<dv { k.uf[i] = Int32(i) }
        for f in 0..<nf {
            let s0 = Int(d.fs[f]), s1 = Int(d.fs[f + 1])
            for e in s0..<s1 {
                let a = Int(d.li[e]), b = Int(d.li[e + 1 < s1 ? e + 1 : s0])
                if a < b && (k.on[a] | k.on[b]) != 0 {
                    let dd = d.v[a] - d.v[b]
                    if dot3(dd, dd) < weld2 {
                        let ra = find(a), rb = find(b)
                        if ra < rb { k.uf[rb] = Int32(ra) } else if rb < ra { k.uf[ra] = Int32(rb) }
                    }
                }
            }
        }
        var wl = 0, wf = 0, s0 = 0
        for f in 0..<nf {
            let s1 = Int(d.fs[f + 1])            // read before the compacted fs overwrites it
            let start = wl
            var prev = -1
            for e in s0..<s1 {
                let r = find(Int(d.li[e]))
                if r != prev { d.li[wl] = UInt16(truncatingIfNeeded: r); wl += 1; prev = r }
            }
            while wl - start > 1 && d.li[wl - 1] == d.li[start] { wl -= 1 }
            if wl - start < 3 {
                wl = start
            } else {
                d.pl[wf] = d.pl[f]; d.tg[wf] = d.tg[f]; wf += 1; d.fs[wf] = UInt16(wl)
            }
            s0 = s1
        }
        nf = wf
        return wl
    }

    // A cut that hit an exact degeneracy is retried with the plane moved a hair (3 eps, far below what shows or what
    // the volume check sees); if it still fails the plane is skipped and counted.
    fileprivate static func cutRobust(_ s: WP, _ d: inout WP, _ n: SIMD3<Float>, _ w: Float, _ tag: UInt8,
                                      _ eps: Float, _ ws: Workspace) -> Cut {
        let r = cut(s, &d, n, w, tag, eps, ws.k)
        if r != .failed { return r }
        ws.cutRetries += 1
        let r2 = cut(s, &d, n, w + 3 * eps, tag, eps, ws.k)
        if r2 != .failed { return r2 }
        let r3 = cut(s, &d, n, w - 3 * eps, tag, eps, ws.k)
        if r3 != .failed { return r3 }
        ws.cutFailures += 1
        return .failed
    }

    // Each seed's cell: the region cut by the bisector planes with the other seeds, nearest first. A seed farther than
    // twice the cell's farthest corner can't touch the cell, nor can any seed after it, so the loop stops there.
    fileprivate static func voronoi(_ region: WP, _ a0: WP, _ b0: WP, seeds ns: Int, origin: SIMD3<Float>, eps: Float,
                                    ws: Workspace, into out: inout [Poly]) -> Int {
        let sd = ws.seeds, order = ws.order, d2 = ws.d2
        var a = a0, b = b0, made = 0
        for i in 0..<ns {
            let si = sd[i]
            var cnt = 0
            for j in 0..<ns where j != i {
                let dj = sd[j] - si
                let dd = dot3(dj, dj)
                var p = cnt
                while p > 0 && d2[Int(order[p - 1])] > dd { order[p] = order[p - 1]; p -= 1 }
                order[p] = Int32(j); d2[j] = dd; cnt += 1
            }
            copy(region, &a)
            var maxR2 = maxDist2(a, si), alive = true
            for oi in 0..<cnt {
                let j = Int(order[oi])
                let dd = d2[j]
                if dd >= 4 * maxR2 { break }
                if dd <= 1e-12 { continue }
                let sj = sd[j]
                let nrm = (sj - si) / dd.squareRoot()
                let w = dot3(nrm, (si + sj) * 0.5)
                let r = cutRobust(a, &b, nrm, w, inner, eps, ws)
                if r == .cut { swap(&a, &b); maxR2 = maxDist2(a, si) } else if r == .empty { alive = false; break }
            }
            if alive, let p = finish(a, origin, ws) { out.append(p); made += 1 }
        }
        return made
    }

    // Seeds inside the region, a margin away from every face and spaced apart (by random sequential addition), so
    // every cell holds a ball round its seed and no cell is a sliver. `bias` pulls candidates toward `focus` and packs
    // them tighter there (small pieces at the impact, big ones far away); `drift` pushes them along the blow.
    fileprivate static func placeSeeds(_ r: WP, lo: SIMD3<Float>, hi: SIMD3<Float>, volume: Float, count: Int,
                                       focus: SIMD3<Float>, reach: Float, bias: Float, drift: SIMD3<Float>,
                                       rng: inout Rand, out: UnsafeMutablePointer<SIMD3<Float>>) -> Int {
        let ext = hi - lo
        let minExt = min(ext.x, min(ext.y, ext.z))
        let spacing = Float(cbrt(Double(max(volume, 1e-12)) / Double(count)))
        var sep = 0.62 * spacing
        var margin = min(0.2 * spacing, 0.18 * minExt)
        let inv = 1 / max(reach, 1e-6)
        let relax = 12 * count
        var placed = 0, tries = 0
        while placed < count && tries < 96 * count {
            tries += 1
            if tries % relax == 0 { sep *= 0.8; margin *= 0.8 }
            let u = lo + ext * SIMD3(rng.unit(), rng.unit(), rng.unit())
            let du = u - focus
            let pull = 1 - bias + bias * min(1, length3(du) * inv)
            let q = focus + du * pull + drift * rng.unit()
            var ok = true
            for f in 0..<r.nf {
                let pl = r.pl[f]
                if dot3(SIMD3(pl.x, pl.y, pl.z), q) - pl.w > -margin { ok = false; break }
            }
            if !ok { continue }
            let near = min(1, length3(q - focus) * inv)
            let s = sep * (1 - 0.6 * bias + 1.2 * bias * near)
            let s2 = s * s
            for j in 0..<placed {
                let dq = out[j] - q
                if dot3(dq, dq) < s2 { ok = false; break }
            }
            if ok { out[placed] = q; placed += 1 }
        }
        return placed
    }

    // Rough flattened ellipsoid round c: tangent planes on a jittered golden-angle spiral over the inner side (13-18
    // planes, offsets jittered so no two bites look alike) plus a loose lid on the outer side that only keeps the
    // region bounded. Plane count stays <= Workspace.maxPlanes.
    fileprivate static func makeBitePlanes(_ c: SIMD3<Float>, _ n: SIMD3<Float>, _ radius: Float, _ rng: inout Rand,
                                           _ out: UnsafeMutablePointer<SIMD4<Float>>) -> Int {
        let r = min(max(radius, 0.04), 1.5)
        let ax = r * (0.92 + 0.22 * rng.unit()), ay = r * (0.78 + 0.22 * rng.unit())
        let az = r * (0.40 + 0.20 * rng.unit())
        let helper: SIMD3<Float> = n.x.magnitude < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let t1 = normalize3(cross3(n, helper)), t2 = cross3(n, t1)
        var cp: Float = 1, sp: Float = 0
        for _ in 0..<8 {       // random start angle without trig: a random point in the unit disc
            let x = 2 * rng.unit() - 1, y = 2 * rng.unit() - 1
            let l2 = x * x + y * y
            if l2 > 0.01 && l2 <= 1 { let l = l2.squareRoot(); cp = x / l; sp = y / l; break }
        }
        let cg: Float = -0.737368878, sg: Float = 0.675490294        // golden angle
        let count = 13 + Int(rng.next() % 6)
        var m = 0
        func add(_ z: Float, _ cphi: Float, _ sphi: Float, _ jitter: Float) {
            let rho = max(0, 1 - z * z).squareRoot()
            let e1 = rho * cphi, e2 = rho * sphi
            let dir = t1 * e1 + t2 * e2 + n * z
            let h1 = ax * e1, h2 = ay * e2, h3 = az * z
            let h = (h1 * h1 + h2 * h2 + h3 * h3).squareRoot()
            out[m] = SIMD4(dir.x, dir.y, dir.z, dot3(dir, c) + h * jitter); m += 1
        }
        for i in 0..<count {
            let zt: Float = 0.32 - 1.32 * (Float(i) + 0.5 + 0.3 * (rng.unit() - 0.5)) / Float(count)
            add(max(-1, min(0.35, zt)), cp, sp, 0.9 + 0.2 * rng.unit())
            let j = 0.3 * (rng.unit() - 0.5)
            let c2 = cp * cg - sp * sg, s2 = sp * cg + cp * sg
            let c3 = c2 - s2 * j, s3 = s2 + c2 * j
            let l = (c3 * c3 + s3 * s3).squareRoot()
            cp = c3 / l; sp = s3 / l
        }
        add(1, 1, 0, 1.3)
        add(0.6, 1, 0, 1.3); add(0.6, -0.5, 0.866025, 1.3); add(0.6, -0.5, -0.866025, 1.3)
        return m
    }

    // An outward unit normal for a bite on the box: the given one (flipped if it points in), else the nearest face's.
    fileprivate static func outwardNormal(_ normal: SIMD3<Float>, _ c: SIMD3<Float>, _ size: SIMD3<Float>) -> SIMD3<Float> {
        let l = length3(normal)
        if l > 1e-6 && l.isFinite {
            let n = normal / l
            return dot3(n, c - size * 0.5) < 0 ? -n : n
        }
        var best: Float = .greatestFiniteMagnitude, face = 2
        let gaps = [c.x, size.x - c.x, c.y, size.y - c.y, c.z, size.z - c.z]
        let faces = [1, 0, 3, 2, 5, 4]
        for i in 0..<6 where gaps[i] < best { best = gaps[i]; face = faces[i] }
        var n = SIMD3<Float>(repeating: 0)
        n[face / 2] = face & 1 == 0 ? 1 : -1
        return n
    }

    // MARK: Internals: helpers

    fileprivate static func loadBox(_ d: inout WP, _ s: SIMD3<Float>) {
        for i in 0..<8 { d.v[i] = SIMD3(i & 1 != 0 ? s.x : 0, i & 2 != 0 ? s.y : 0, i & 4 != 0 ? s.z : 0) }
        boxLoop.withUnsafeBufferPointer { d.li.update(from: $0.baseAddress!, count: 24) }
        for f in 0...6 { d.fs[f] = UInt16(f * 4) }
        d.pl[0] = SIMD4(1, 0, 0, s.x); d.pl[1] = SIMD4(-1, 0, 0, 0); d.pl[2] = SIMD4(0, 1, 0, s.y)
        d.pl[3] = SIMD4(0, -1, 0, 0); d.pl[4] = SIMD4(0, 0, 1, s.z); d.pl[5] = SIMD4(0, 0, -1, 0)
        for f in 0..<6 { d.tg[f] = UInt8(f) }
        d.nv = 8; d.nf = 6
    }

    fileprivate static func load(_ p: Poly, _ d: inout WP, _ k: Scratch) -> Bool {
        let nf = p.faceCount
        guard p.verts.count >= 4, nf >= 4, p.verts.count <= k.maxV, nf + 1 <= k.maxF, p.loop.count <= k.maxL,
              p.faceStart.count == nf + 1, p.planes.count == nf else { return false }
        p.verts.withUnsafeBufferPointer { d.v.update(from: $0.baseAddress!, count: $0.count) }
        p.faceStart.withUnsafeBufferPointer { d.fs.update(from: $0.baseAddress!, count: $0.count) }
        p.loop.withUnsafeBufferPointer { d.li.update(from: $0.baseAddress!, count: $0.count) }
        p.planes.withUnsafeBufferPointer { d.pl.update(from: $0.baseAddress!, count: $0.count) }
        p.tags.withUnsafeBufferPointer { d.tg.update(from: $0.baseAddress!, count: $0.count) }
        d.nv = p.verts.count; d.nf = nf
        return true
    }

    @inline(__always) fileprivate static func copy(_ s: WP, _ d: inout WP) {
        d.v.update(from: s.v, count: s.nv)
        d.fs.update(from: s.fs, count: s.nf + 1)
        d.pl.update(from: s.pl, count: s.nf)
        d.tg.update(from: s.tg, count: s.nf)
        d.li.update(from: s.li, count: Int(s.fs[s.nf]))
        d.nv = s.nv; d.nf = s.nf
    }

    // A finished work polyhedron becomes a piece, unless it is a crumb or a sliver (dropped, its volume just goes).
    fileprivate static func finish(_ p: WP, _ origin: SIMD3<Float>, _ ws: Workspace) -> Poly? {
        let m = massCore(p.v, p.nv, p.fs, p.nf, p.li)
        if !(m.volume >= ws.minVolume) || width(p) < ws.minWidth {
            ws.droppedPieces += 1; ws.droppedVolume += max(0, m.volume)
            return nil
        }
        return Poly(origin: origin, verts: Array(UnsafeBufferPointer(start: p.v, count: p.nv)),
                    faceStart: Array(UnsafeBufferPointer(start: p.fs, count: p.nf + 1)),
                    loop: Array(UnsafeBufferPointer(start: p.li, count: Int(p.fs[p.nf]))),
                    planes: Array(UnsafeBufferPointer(start: p.pl, count: p.nf)),
                    tags: Array(UnsafeBufferPointer(start: p.tg, count: p.nf)), mass: m)
    }

    // Thinnest extent measured from each face inward: catches slabs and needles.
    fileprivate static func width(_ p: WP) -> Float {
        var best = Float.greatestFiniteMagnitude
        for f in 0..<p.nf {
            let pl = p.pl[f]
            let n = SIMD3(pl.x, pl.y, pl.z)
            var deep: Float = 0
            for i in 0..<p.nv { deep = max(deep, pl.w - dot3(n, p.v[i])) }
            best = min(best, deep)
        }
        return best
    }

    // Exact mass properties: tetrahedra from the vertex average to each face's fan triangles, in Double.
    // Tet (0, a, b, c): volume det/6, second moment det/120 * (aa' + bb' + cc' + ss'), s = a + b + c.
    fileprivate static func massCore(_ v: UnsafePointer<SIMD3<Float>>, _ nv: Int, _ fs: UnsafePointer<UInt16>,
                                     _ nf: Int, _ li: UnsafePointer<UInt16>) -> MassProps {
        guard nv >= 4, nf >= 4 else { return MassProps() }
        var c = SIMD3<Float>(repeating: 0)
        for i in 0..<nv { c += v[i] }
        c /= Float(nv)
        var v6 = 0.0
        var m1 = SIMD3<Double>(repeating: 0)
        var sq = SIMD3<Double>(repeating: 0)        // xx yy zz
        var sx = SIMD3<Double>(repeating: 0)        // xy xz yz
        for f in 0..<nf {
            let s0 = Int(fs[f]), s1 = Int(fs[f + 1])
            let a = dvec(v[Int(li[s0])] - c)
            var b = dvec(v[Int(li[s0 + 1])] - c)
            var e = s0 + 2
            while e < s1 {
                let cc = dvec(v[Int(li[e])] - c)
                let det = dotd(a, crossd(b, cc))
                let s = a + b + cc
                v6 += det
                m1 += s * det
                let q: SIMD3<Double> = a * a + b * b + cc * cc + s * s
                let p1 = SIMD3<Double>(a.x, a.x, a.y) * SIMD3<Double>(a.y, a.z, a.z)
                let p2 = SIMD3<Double>(b.x, b.x, b.y) * SIMD3<Double>(b.y, b.z, b.z)
                let p3 = SIMD3<Double>(cc.x, cc.x, cc.y) * SIMD3<Double>(cc.y, cc.z, cc.z)
                let p4 = SIMD3<Double>(s.x, s.x, s.y) * SIMD3<Double>(s.y, s.z, s.z)
                sq += q * det
                sx += (p1 + p2 + p3 + p4) * det
                b = cc; e += 1
            }
        }
        let vol = v6 / 6
        guard vol > 0 else { return MassProps(volume: Float(vol), centroid: c, inertia: simd_float3x3()) }
        let g = m1 / (4 * v6)
        let cq = sq / 120 - g * g * vol                                  // second moments about the centroid
        let gx = SIMD3<Double>(g.x, g.x, g.y) * SIMD3<Double>(g.y, g.z, g.z)
        let cx = sx / 120 - gx * vol
        let ixx = Float(cq.y + cq.z), iyy = Float(cq.x + cq.z), izz = Float(cq.x + cq.y)
        let ixy = Float(-cx.x), ixz = Float(-cx.y), iyz = Float(-cx.z)
        let inertia = simd_float3x3(columns: (SIMD3(ixx, ixy, ixz), SIMD3(ixy, iyy, iyz), SIMD3(ixz, iyz, izz)))
        let centroid = c + SIMD3<Float>(Float(g.x), Float(g.y), Float(g.z))
        return MassProps(volume: Float(vol), centroid: centroid, inertia: inertia)
    }

    fileprivate static func bounds(_ p: WP) -> (SIMD3<Float>, SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for i in 0..<p.nv { lo = pointwiseMin(lo, p.v[i]); hi = pointwiseMax(hi, p.v[i]) }
        return (lo, hi)
    }

    // Welding distance: ~100 Float ulps of the region's size (local coordinates start at 0).
    @inline(__always) fileprivate static func epsilon(_ ext: SIMD3<Float>) -> Float {
        1e-5 * max(ext.x, max(ext.y, ext.z)) + 1e-7
    }

    @inline(__always) fileprivate static func maxDist2(_ p: WP, _ c: SIMD3<Float>) -> Float {
        var m: Float = 0
        for i in 0..<p.nv { let d = p.v[i] - c; m = max(m, dot3(d, d)) }
        return m
    }

    // Own vector helpers: identical on Apple simd and the Linux/Android shim.
    @inline(__always) fileprivate static func dot3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    @inline(__always) fileprivate static func cross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    @inline(__always) fileprivate static func length3(_ a: SIMD3<Float>) -> Float { dot3(a, a).squareRoot() }
    @inline(__always) fileprivate static func normalize3(_ a: SIMD3<Float>) -> SIMD3<Float> { a / length3(a) }
    @inline(__always) fileprivate static func dvec(_ a: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3(Double(a.x), Double(a.y), Double(a.z))
    }
    @inline(__always) fileprivate static func dotd(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    @inline(__always) fileprivate static func crossd(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    // splitmix64: cheap, well mixed, identical on every platform.
    fileprivate struct Rand {
        var s: UInt64
        init(_ seed: UInt32, _ salt: UInt64) { s = (UInt64(seed) << 20) ^ (salt &* 0x9E3779B97F4A7C15) }
        mutating func next() -> UInt32 {
            s &+= 0x9E3779B97F4A7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return UInt32(truncatingIfNeeded: (z ^ (z >> 31)) >> 32)
        }
        mutating func unit() -> Float { Float(next() >> 8) * (1.0 / 16777216.0) }
    }
}
