import Foundation
import simd

// P508 (Nov 1 16:01-16:05, at a taken frigate's helm, shelling a Capital citadel far past the loaded land with the
// Tidebreaker: "we need to turn the actual building shapes... make it look like they compressed everything";
// "Not some placeholder block thing"; "Okay, I hope that destroyed the building"; "Make the citadel render. Entirely.
// You can make a compression of it, make the entire thing render. None of the land around it though, just the city
// all itself"). Past the loaded land a citadel stood as four grey boxes, and a hit on it showed nothing.
//
// Now the citadel is drawn from its own blocks: its builder (CapitalBase.build) is run off the frame thread into a
// scratch chunk at a time, only the blocks it built (not the ground round it) are kept, two blocks to a cell, and the
// cells' outer faces are merged into flat quads of one colour (a few thousand for the whole site). The blast spheres
// the citadel has taken and not rebuilt (BaseRecord.damage: a Tidebreaker strike's is 21 blocks across) are cut out
// of it, so the hole shows from the helm; and every slug's impact past the loaded land raises a dust column for half
// a minute, so a hit is seen at any range.
enum FarCitadel {
    static let cell = 2
    static let range: Float = 1800                 // past this the boxes (a 2-block cell is under a pixel)
    struct Quad { var p: V3; var du: V3; var dv: V3; var n: V3; var col: V3 }
    final class Model {
        let key: String
        let origin: IVec3
        let nx: Int, ny: Int, nz: Int
        let grid: [UInt16]                         // per cell: 0 empty, else its colour (5 bits a channel) + 1
        var quads: [Quad] = []
        var cutSig = 0                             // the damage list it was cut with
        init(key: String, origin: IVec3, nx: Int, ny: Int, nz: Int, grid: [UInt16]) {
            self.key = key; self.origin = origin; self.nx = nx; self.ny = ny; self.nz = nz; self.grid = grid
        }
    }
    private static let lock = NSLock()
    private static var models: [String: Model] = [:]
    private static var busy = false
    static var builds = 0                          // harness: models built and re-cut
    static var sync = false, buildMs = 0.0
    static var lastQuads = 0, lastDrawn = 0

    // The blast spheres a citadel has taken (x, y, z, radius) and a signature of them.
    static func damage(_ g: Game, key: String) -> [[Float]] { g.bases.records[key]?.damage ?? [] }
    static func sig(_ d: [[Float]]) -> Int {
        var h = d.count &* 7919
        for s in d { for v in s { h = h &* 31 &+ Int(v * 4) } }
        return h
    }

    // The model for a citadel start, or nil while it is being built (one at a time, off the frame thread).
    static func model(_ st: StructureStart, key: String, damage: [[Float]]) -> Model? {
        lock.lock()
        let m = models[key]
        let idle = !busy
        if idle && (m == nil || m!.cutSig != sig(damage)) { busy = true }
        lock.unlock()
        if idle && (m == nil || m!.cutSig != sig(damage)) {
            let piece = st.pieces[0]
            let job = {
                let base = m ?? voxelize(piece, key: key)
                let cut = Model(key: key, origin: base.origin, nx: base.nx, ny: base.ny, nz: base.nz, grid: base.grid)
                cut.quads = mesh(base, damage: damage)
                cut.cutSig = sig(damage)
                lock.lock()
                models[key] = cut
                if models.count > 6, let far = models.keys.first(where: { $0 != key }) { models[far] = nil }
                busy = false
                builds += 1
                lock.unlock()
            }
            if sync {                                    // (harness pictures: made before the frame)
                let t0 = CFAbsoluteTimeGetCurrent()
                job()
                buildMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                lock.lock(); let made = models[key]; lock.unlock()
                return made
            }
            DispatchQueue.global(qos: .utility).async(execute: job)
        }
        return m
    }

    // MARK: Building

    static let tones: [V3] = (0..<Blocks.count).map { tone(BlockID($0)) }
    static func tone(_ b: BlockID) -> V3 {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if k.contains("window") || k.contains("glass") { return V3(0.4, 0.5, 0.58) }
        if k.contains("trim") || k.contains("light_gray") { return V3(0.68, 0.7, 0.73) }
        if k.hasPrefix("capital_") || k.contains("white") || k.contains("quartz") { return V3(0.9, 0.91, 0.92) }
        if k.contains("leaves") { return V3(0.25, 0.42, 0.19) }
        if k.contains("grass_block") || k == "moss_block" { return V3(0.38, 0.56, 0.26) }
        if k.contains("iron") || k.contains("steel") || k.contains("console") || k.contains("crate") || k.contains("gun") { return V3(0.42, 0.44, 0.47) }
        let m = MapColors.base(b)
        return V3(Float((m >> 16) & 255), Float((m >> 8) & 255), Float(m & 255)) / 255 * 0.85
    }
    @inline(__always) static func pack(_ c: V3) -> UInt16 {
        let r = UInt16(max(0, min(31, c.x * 31 + 0.5))), g = UInt16(max(0, min(31, c.y * 31 + 0.5))), b = UInt16(max(0, min(31, c.z * 31 + 0.5)))
        return (r << 10 | g << 5 | b) + 1
    }
    @inline(__always) static func unpack(_ k: UInt16) -> V3 {
        let v = k - 1
        return V3(Float((v >> 10) & 31), Float((v >> 5) & 31), Float(v & 31)) / 31
    }

    // The citadel's own blocks, two to a cell: a cell holding two or more of its eight is solid, in their mean colour.
    // (The site's foot: from 6 under the plaza's base, where the podium's white starts; the ground it lays is left out.)
    static func voxelize(_ piece: Piece, key: String) -> Model {
        let F = cell
        let floorY = piece.min.y + 14
        let x0 = piece.min.x, z0 = piece.min.z, y1 = min(CH - 1, piece.max.y)
        let nx = (piece.max.x - x0 + F) / F, nz = (piece.max.z - z0 + F) / F, ny = max(1, (y1 - floorY + F) / F)
        var count = [UInt8](repeating: 0, count: nx * ny * nz)
        var sum = [V3](repeating: .zero, count: nx * ny * nz)
        var blocks = [BlockID](repeating: AIR, count: CS * CH * CS)
        var mark = [UInt8](repeating: 0, count: CS * CH * CS)
        let keep: [Bool] = (0..<Blocks.count).map { i in
            i != Int(AIR) && Blocks.fluidKind[i] == 0 && (Blocks.collide[i] || Blocks.opaque[i])
                && !SmoothTerrain.natural[i]           // (his 16:05: "None of the land around it though, just the city": no lawns or laid ground)
        }
        for cz in floorDiv(z0, CS)...floorDiv(piece.max.z, CS) { for cx in floorDiv(x0, CS)...floorDiv(piece.max.x, CS) {
            let bx = cx * CS, bz = cz * CS
            guard piece.overlaps(bx, bz) else { continue }
            for i in 0..<blocks.count { blocks[i] = AIR }
            for i in 0..<mark.count { mark[i] = 0 }
            blocks.withUnsafeMutableBufferPointer { b in mark.withUnsafeMutableBufferPointer { mk in
                var w = StructWriter(bx: bx, bz: bz, blocks: b.baseAddress!)
                w.mark = mk.baseAddress!
                piece.build(&w)
            } }
            for lz in 0..<CS { for lx in 0..<CS {
                let x = bx + lx, z = bz + lz
                guard x >= x0, x <= piece.max.x, z >= z0, z <= piece.max.z else { continue }
                for y in thru(max(0, floorY), y1) {
                    let i = Chunk.index(lx, y, lz)
                    let b = blocks[i]
                    guard mark[i] != 0, keep[Int(b)] else { continue }
                    let c = ((y - floorY) / F * nz + (z - z0) / F) * nx + (x - x0) / F
                    count[c] &+= 1
                    sum[c] += tones[Int(b)]
                }
            } }
        } }
        var grid = [UInt16](repeating: 0, count: nx * ny * nz)
        for c in 0..<grid.count where count[c] >= 2 { grid[c] = pack(sum[c] / Float(count[c])) }
        return Model(key: key, origin: IVec3(x0, floorY, z0), nx: nx, ny: ny, nz: nz, grid: grid)
    }

    // The cells' outer faces, merged into rectangles of one colour, with the blast spheres cut out.
    static func mesh(_ m: Model, damage: [[Float]]) -> [Quad] {
        let F = cell, Ff = Float(cell)
        var g = m.grid
        let o = V3(Float(m.origin.x), Float(m.origin.y), Float(m.origin.z))
        for s in damage where s.count >= 4 {
            let c = V3(s[0], s[1], s[2]), r = min(s[3], 16)
            let lo = (c - V3(repeating: r) - o) / Ff, hi = (c + V3(repeating: r) - o) / Ff
            let ya = max(0, Int(floor(lo.y))), yb = min(m.ny - 1, Int(ceil(hi.y)))
            let za = max(0, Int(floor(lo.z))), zb = min(m.nz - 1, Int(ceil(hi.z)))
            let xa = max(0, Int(floor(lo.x))), xb = min(m.nx - 1, Int(ceil(hi.x)))
            guard ya <= yb, za <= zb, xa <= xb else { continue }
            for y in ya...yb {
                for z in za...zb {
                    for x in xa...xb {
                        let p = o + (V3(Float(x), Float(y), Float(z)) + 0.5) * Ff
                        if simd_length_squared(p - c) <= r * r { g[(y * m.nz + z) * m.nx + x] = 0 }
                    }
                }
            }
        }
        let dims = SIMD3<Int>(m.nx, m.ny, m.nz)
        func at(_ q: SIMD3<Int>) -> UInt16 {
            guard q.x >= 0, q.y >= 0, q.z >= 0, q.x < m.nx, q.y < m.ny, q.z < m.nz else { return 0 }
            return g[(q.y * m.nz + q.z) * m.nx + q.x]
        }
        var out: [Quad] = []
        for a in 0..<3 {
            let u = (a + 1) % 3, v = (a + 2) % 3
            let du = dims[u], dv = dims[v]
            var mask = [UInt16](repeating: 0, count: du * dv)
            for sgn in [-1, 1] {
                var n = V3.zero; n[a] = Float(sgn)
                for i in 0..<dims[a] {
                    var q = SIMD3<Int>(0, 0, 0), q2 = SIMD3<Int>(0, 0, 0)
                    for k in 0..<dv { for j in 0..<du {
                        q[a] = i; q[u] = j; q[v] = k
                        q2[a] = i + sgn; q2[u] = j; q2[v] = k
                        let c = at(q)
                        mask[k * du + j] = c != 0 && at(q2) == 0 ? c : 0
                    } }
                    for k in 0..<dv {
                        var j = 0
                        while j < du {
                            let c = mask[k * du + j]
                            if c == 0 { j += 1; continue }
                            var w = 1
                            while j + w < du && mask[k * du + j + w] == c { w += 1 }
                            var h = 1
                            grow: while k + h < dv {
                                for t in 0..<w where mask[(k + h) * du + j + t] != c { break grow }
                                h += 1
                            }
                            for kk in 0..<h { for t in 0..<w { mask[(k + kk) * du + j + t] = 0 } }
                            var p = o
                            p[a] += Float((i + (sgn > 0 ? 1 : 0)) * F)
                            p[u] += Float(j * F); p[v] += Float(k * F)
                            var eu = V3.zero; eu[u] = Float(w * F)
                            var ev = V3.zero; ev[v] = Float(h * F)
                            out.append(Quad(p: p, du: eu, dv: ev, n: n, col: unpack(c)))
                            j += w
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: Drawing (LandmarkRender's citadel pass)

    // The model's faces turned to the eye, lit and hazed like the boxes they replace; faces over loaded land are left to
    // the real blocks there.
    static func draw(_ m: Model, eye: V3, loaded: Float, sun: V3, day: Float, nightK: Float, hdrK: Float, fog: V3, haze: Float,
                     at: (V3) -> V4, into out: inout [SimpleVert]) {
        lastQuads = m.quads.count
        var drawn = 0
        let fogH = fog * haze, keep = hdrK * (1 - haze)
        for q in m.quads {
            guard simd_dot(q.n, eye - q.p) > 0 else { continue }
            let mid = q.p + (q.du + q.dv) * 0.5
            if abs(mid.x - eye.x) < loaded && abs(mid.z - eye.z) < loaded { continue }
            let lit: Float = q.n.y > 0.5 ? (0.5 + 0.5 * day) * nightK : (0.38 + 0.62 * max(0, simd_dot(q.n, sun)) * day + 0.06) * nightK
            let k = V4(q.col * (lit * keep) + fogH, 1)
            let a = at(q.p), b = at(q.p + q.du), c = at(q.p + q.du + q.dv), d = at(q.p + q.dv)
            out.append(SimpleVert(pos: a, color: k)); out.append(SimpleVert(pos: b, color: k)); out.append(SimpleVert(pos: c, color: k))
            out.append(SimpleVert(pos: a, color: k)); out.append(SimpleVert(pos: c, color: k)); out.append(SimpleVert(pos: d, color: k))
            drawn += 1
        }
        lastDrawn = drawn
    }

    // MARK: Strike dust

    // A slug's impact (MainGun.mainGunImpact), kept 30 s: a column of dust and smoke over it past the loaded land.
    static var hits: [(V3, Double)] = []
    static let hitLife = 30.0
    static func noteHit(_ p: V3, clock: Double) {
        hits.append((p, clock))
        if hits.count > 8 { hits.removeFirst() }
    }

    static func dust(_ smoke: inout [SimpleVert], clock: Double, eye: V3, loaded: Float, fog: V3, day: Float, hdrK: Float,
                     at: (V3) -> V4) {
        hits.removeAll { clock - $0.1 > hitLife }
        for (p, t0) in hits {
            let dist = simd_length(V2(p.x - eye.x, p.z - eye.z))
            guard dist > loaded * 0.6 else { continue }
            let age = Float(clock - t0)
            let haze: Float = 0.2 + 0.5 * Terrain.smooth(loaded, 2400, dist)
            let toEye = simd_normalize(eye - p + V3(0, 1e-3, 0))
            let right = simd_normalize(simd_cross(V3(0, 1, 0), toEye) + V3(1e-4, 0, 0)), up = simd_cross(toEye, right)
            func puff(_ c: V3, _ r: Float, _ col: V4) {
                let mid = at(c), rim = V4(col.x, col.y, col.z, 0)
                var prev = at(c + right * r)
                for k in 1...8 {
                    let a = Float(k) / 8 * 2 * .pi
                    let q = at(c + (right * cosf(a) + up * sinf(a) * 0.85) * r)
                    smoke.append(SimpleVert(pos: mid, color: col)); smoke.append(SimpleVert(pos: prev, color: rim)); smoke.append(SimpleVert(pos: q, color: rim))
                    prev = q
                }
            }
            // The flash: a fireball for the first second.
            if age < 1.2 {
                let f = 1 - age / 1.2
                puff(p + V3(0, 6, 0), 10 + 14 * (1 - f), V4(V3(1.0, 0.62, 0.25) * hdrK * 1.4, 0.9 * f))
            }
            // The column: puffs rising to 70 blocks and spreading into a cap, thinning as it ages.
            let life = Float(hitLife)
            let fade: Float = Terrain.smooth(0, 2, age) * (1 - Terrain.smooth(life * 0.5, life, age))
            for j in 0..<14 {
                let f = Float(j) / 13
                let rise = min(age * 9, 70) * f
                let spread: Float = 5 + 9 * f + age * 0.25
                let sway = V3(sinf(Float(j) * 1.7 + age * 0.3), 0, cosf(Float(j) * 2.3 + age * 0.2)) * (2 + rise * 0.08)
                let g: Float = 0.32 + 0.18 * f
                let col = V3(g * 1.05, g, g * 0.92) * (0.25 + 0.75 * day) * hdrK
                let a: Float = 0.55 * fade * (1 - 0.4 * f)
                guard a > 0.02 else { continue }
                puff(p + V3(0, 4 + rise, 0) + sway, spread, V4(col * (1 - haze) + fog * haze, a))
            }
        }
    }
}
