import Foundation
import simd

// Realistic world, layer 2 (docs/design/realistic-world.md 2.2): the craters tools, bullets and blasts leave. A bite is
// where something struck a block: the contact, the axis the blow came along and how big a bowl it took. Bites are a
// view of the damage (gameplay is the block's mining progress, as before): the mesher carves every surface that passes
// through a bite (the smooth ground, a cube's faces) into a rough bowl, so the pickaxe takes out what it touched, deeper
// with every blow, and a wall shot up keeps its bullet holes until the block changes.
struct Bite {
    var c: SIMD3<Float>          // contact, block-local (on the struck surface)
    var n: SIMD3<Float>          // unit axis out of the block along the blow (the bowl opens this way)
    var r: Float                 // rim radius (blocks)
    var d: Float                 // depth at the centre
    var seed: UInt32
}

enum Craters {
    // The section mesher's texture projection for face f (chunk.vert's projected UVs; Mesher.faceUV modulo 1), in blocks.
    @inline(__always) static func faceUV(_ f: Int, _ q: SIMD3<Float>) -> SIMD2<Float> {
        switch f {
        case 0: return SIMD2(-q.z, -q.y)
        case 1: return SIMD2(q.z, -q.y)
        case 2: return SIMD2(q.x, q.z)
        case 3: return SIMD2(q.x, -q.z)
        case 4: return SIMD2(q.x, -q.y)
        default: return SIMD2(-q.x, -q.y)
        }
    }
}

// The bites round one section, section-local, and the surface they carve.
struct CraterSet {
    private(set) var a: [SIMD3<Float>] = [], n: [SIMD3<Float>] = [], u: [SIMD3<Float>] = [], v: [SIMD3<Float>] = []
    private(set) var r: [Float] = [], d: [Float] = []
    private(set) var lobes: [SIMD4<Float>] = []         // rim roughness: 3- and 5-lobed wobble (amplitude, phase) x 2
    private(set) var salt: [UInt32] = []
    var regionIndex = Set<Int>()                         // the bitten blocks (Mesher region index)
    private var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    // P499 (Oct 30 20:31, 64 TNT in a Capital office: "it took too long for the damage to show up... a lot of blocks just
    // in some sort of half state"): every vertex, patch and quad of a section looked at every bite round it, and a blast
    // leaves hundreds (each block it shook gets one), so a section near one took about 200 ms to mesh (questcheck
    // --streamtest --tnt 4: 47 sections in 10 s, the workers busy for 13 s after the last blast while the pieces that
    // broke off were let go over the old walls). Each bite is now listed in the blocks its bowl can reach, and a lookup
    // reads only the bites listed where it is.
    private var cells: [Int32: [Int32]] = [:]
    private static let off = 6, span = 30                // section-local blocks -6...23 on each axis
    @inline(__always) private static func cell(_ x: Int, _ y: Int, _ z: Int) -> Int32? {
        let a = x + off, b = y + off, c = z + off
        guard a >= 0 && b >= 0 && c >= 0 && a < span && b < span && c < span else { return nil }
        return Int32(a + (b + c * span) * span)
    }
    // The bites listed in the blocks from mn to mx (each once).
    private func near(_ mn: SIMD3<Float>, _ mx: SIMD3<Float>) -> [Int32] {
        let x0 = Int(floorf(mn.x)), y0 = Int(floorf(mn.y)), z0 = Int(floorf(mn.z))
        let x1 = Int(floorf(mx.x)), y1 = Int(floorf(mx.y)), z1 = Int(floorf(mx.z))
        if x0 == x1 && y0 == y1 && z0 == z1 { return CraterSet.cell(x0, y0, z0).flatMap { cells[$0] } ?? [] }
        var out: [Int32] = []
        for z in z0...z1 { for y in y0...y1 { for x in x0...x1 {
            guard let k = CraterSet.cell(x, y, z), let l = cells[k] else { continue }
            for i in l where !out.contains(i) { out.append(i) }
        } } }
        return out
    }
    let wo: SIMD3<Float>                                 // world position of section-local 0 (noise)
    var isEmpty: Bool { a.isEmpty }

    // bites: (x, world y, z, bite) with x, z relative to the centre chunk's corner (World.biteList); y0: the section's
    // first internal y; region: the Mesher region index of a section-local block.
    init(_ bites: [(Int, Int, Int, Bite)], sy: Int, wo: SIMD3<Float>, region: (Int, Int, Int) -> Int?) {
        self.wo = wo
        let y0 = sy * 16
        for (x, wy, z, b) in bites {
            let base = SIMD3<Float>(Float(x), Float(wy - y0), Float(z))
            let c = base + b.c
            // Only bites whose bowl can reach this section's surfaces (its 0...16 cube and the dual cells round it).
            let reach = b.r * 1.4 + 1.5
            if c.x < -reach || c.y < -reach || c.z < -reach || c.x > 16 + reach || c.y > 16 + reach || c.z > 16 + reach { continue }
            let nn = simd_length(b.n) > 1e-4 ? simd_normalize(b.n) : SIMD3<Float>(0, 1, 0)
            let helper = abs(nn.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let uu = simd_normalize(simd_cross(helper, nn)), vv = simd_cross(nn, uu)
            a.append(c); n.append(nn); u.append(uu); v.append(vv); r.append(b.r); d.append(b.d); salt.append(b.seed)
            let h0 = Float(b.seed & 0xFF) / 255, h1 = Float((b.seed >> 8) & 0xFF) / 255
            let h2 = Float((b.seed >> 16) & 0xFF) / 255, h3 = Float((b.seed >> 24) & 0xFF) / 255
            lobes.append(SIMD4(0.1 + 0.12 * h0, h1 * 6.283, 0.05 + 0.08 * h2, h3 * 6.283))
            let e = SIMD3<Float>(repeating: b.r * 1.3 + 0.05)
            lo = simd_min(lo, c - e - nn * 0.9); hi = simd_max(hi, c + e + nn * 0.6)
            lo = simd_min(lo, c - e); hi = simd_max(hi, c + e)
            if let ri = region(x, wy - y0, z) { regionIndex.insert(ri) }
            // (Listed in every block its bowl can move a surface in: within 0.9 along its axis and 1.3 rims across.)
            let ext = SIMD3<Float>(repeating: b.r * 1.3 + 0.95)
            let cl = c - ext, ch = c + ext
            let idx = Int32(a.count - 1)
            for cz in Int(floorf(cl.z))...Int(floorf(ch.z)) { for cy in Int(floorf(cl.y))...Int(floorf(ch.y)) { for cx in Int(floorf(cl.x))...Int(floorf(ch.x)) {
                if let k = CraterSet.cell(cx, cy, cz) { cells[k, default: []].append(idx) }
            } } }
        }
    }

    // How far the surface at p moves (a vector into the material), summed over the bites it lies in.
    func displacement(_ p: SIMD3<Float>) -> SIMD3<Float> {
        if a.isEmpty || p.x < lo.x || p.y < lo.y || p.z < lo.z || p.x > hi.x || p.y > hi.y || p.z > hi.z { return .zero }
        guard let k = CraterSet.cell(Int(floorf(p.x)), Int(floorf(p.y)), Int(floorf(p.z))), let list = cells[k] else { return .zero }
        var out = SIMD3<Float>(0, 0, 0)
        for j in list {
            let i = Int(j)
            let w = p - a[i]
            let along = simd_dot(w, n[i])
            if along < -0.9 || along > 0.6 { continue }               // (not the far side of a thin wall)
            let pu = simd_dot(w, u[i]), pv = simd_dot(w, v[i])
            let s2 = pu * pu + pv * pv
            let rmax = r[i] * 1.3
            if s2 >= rmax * rmax { continue }
            let th = atan2f(pv, pu)
            let L = lobes[i]
            let re = r[i] * (1 + L.x * sinf(3 * th + L.y) + L.z * sinf(5 * th + L.w))
            let k2 = s2 / (re * re)
            if k2 >= 1 { continue }
            let q = 1 - k2
            // A bowl with a rough floor (world-stable noise, so neighbouring sections carve the same).
            let rough = 1 + 0.35 * DetailMesh.noise(p + wo, 7, salt[i])
            out -= n[i] * (d[i] * q * q.squareRoot() * rough)
        }
        let l = simd_length(out)
        return l > 0.8 ? out * (0.8 / l) : out
    }

    // Does a surface patch (its corners) come near a bite? (Cheap reject before subdividing it.)
    func touches(_ p: [SIMD3<Float>]) -> Bool {
        if a.isEmpty { return false }
        var mn = p[0], mx = p[0]
        for q in p { mn = simd_min(mn, q); mx = simd_max(mx, q) }
        if mx.x < lo.x || mx.y < lo.y || mx.z < lo.z || mn.x > hi.x || mn.y > hi.y || mn.z > hi.z { return false }
        let c = (p[0] + p[1] + p[2] + p[3]) * 0.25
        let half = simd_length(mx - mn) * 0.5
        for j in near(mn, mx) {
            let i = Int(j)
            let w = c - a[i]
            let along = simd_dot(w, n[i])
            if along < -0.9 - half || along > 0.6 + half { continue }
            let perp = w - n[i] * along
            if simd_length(perp) < r[i] * 1.3 + half { return true }
        }
        return false
    }

    // Grid lines across a quad (parameter 0...1 from corner 0 toward corner 1, and toward corner 3): `base` even steps
    // plus rings of lines round every bite that reaches the quad, so a bullet hole gets as many vertices across it as a
    // pickaxe's bowl, and a quad with no bite near it gets none.
    func ticks(_ p: [SIMD3<Float>], base: Int) -> (s: [Float], t: [Float]) {
        var ts: [Float] = [], tt: [Float] = []
        for k in 0...base { ts.append(Float(k) / Float(base)); tt.append(Float(k) / Float(base)) }
        let eu = p[1] - p[0], ev = p[3] - p[0]
        let lu = simd_length_squared(eu), lv = simd_length_squared(ev)
        guard lu > 1e-8 && lv > 1e-8 else { return (ts, tt) }
        let su = lu.squareRoot(), sv = lv.squareRoot()
        let rings: [Float] = [-1.2, -1, -0.8, -0.6, -0.4, -0.2, 0, 0.2, 0.4, 0.6, 0.8, 1, 1.2]
        var mn = p[0], mx = p[0]
        for q in p { mn = simd_min(mn, q); mx = simd_max(mx, q) }
        for j in near(mn, mx) {
            let i = Int(j)
            let w = a[i] - p[0]
            // (The bite's centre line meets the quad's plane: move the contact along its axis onto it.)
            let pn = simd_cross(eu, ev)
            let dn = simd_dot(n[i], pn)
            let c = abs(dn) > 1e-6 ? a[i] - n[i] * (simd_dot(w, pn) / dn) : a[i]
            let cs = simd_dot(c - p[0], eu) / lu, ct = simd_dot(c - p[0], ev) / lv
            let ru = r[i] * 1.3 / su, rv = r[i] * 1.3 / sv
            if cs + ru < 0 || cs - ru > 1 || ct + rv < 0 || ct - rv > 1 { continue }
            for k in rings {
                let x = cs + k * r[i] / su, y = ct + k * r[i] / sv
                if x > 0 && x < 1 { ts.append(x) }
                if y > 0 && y < 1 { tt.append(y) }
            }
        }
        func clean(_ v: [Float]) -> [Float] {
            var out: [Float] = []
            for x in v.sorted() where out.isEmpty || x - out.last! > 0.012 { out.append(x) }
            if out.last! < 1 { if 1 - out.last! < 0.012 { out[out.count - 1] = 1 } else { out.append(1) } }
            return out
        }
        return (clean(ts), clean(tt))
    }

    // One surface quad (corners 0...3 counter-clockwise from outside) subdivided along `grid` (ticks) and carved, into the
    // detail stream. Corners carry their own normal, layer, tint, light (sky | block << 4) and ao; inside a bowl the
    // surface shows `inner` (the struck block's own material) a little darker. `face`: the texture projection (chunk.vert's
    // faces 0-5).
    func carve(_ out: GrowBuf<UInt32>, _ p: [SIMD3<Float>], _ nrm: [SIMD3<Float>], layers: [Int], tints: [Int], light: [Int],
               ao: [Int], inner: (layer: Int, tint: Int), face f: Int, grid: (s: [Float], t: [Float])) {
        let S = grid.s, T = grid.t
        let W = S.count, H = T.count
        guard W >= 2 && H >= 2 else { return }
        var pos = [SIMD3<Float>](repeating: .zero, count: W * H), flat = pos, sn = pos
        var dep = [Float](repeating: 0, count: W * H)
        for j in 0..<H { for k in 0..<W {
            let s = S[k], t = T[j]
            let w0 = (1 - s) * (1 - t), w1 = s * (1 - t), w2 = s * t, w3 = (1 - s) * t
            let q = p[0] * w0 + p[1] * w1 + p[2] * w2 + p[3] * w3
            // (Edges move too: the bowl is one smooth field, so a neighbour carved with other grid lines still meets this
            // quad to well under a millimetre, and an uncarved neighbour is out of the bowl's reach.)
            let disp = displacement(q)
            pos[k + j * W] = q + disp; flat[k + j * W] = q
            dep[k + j * W] = simd_length(disp)
            let nn = nrm[0] * w0 + nrm[1] * w1 + nrm[2] * w2 + nrm[3] * w3
            sn[k + j * W] = simd_length(nn) > 1e-5 ? simd_normalize(nn) : SIMD3<Float>(0, 1, 0)
        } }
        // Normal: the corners' smooth normal, turned by however much the carving tilts the surface there.
        @inline(__always) func grad(_ P: [SIMD3<Float>], _ k: Int, _ j: Int) -> SIMD3<Float> {
            let du = P[min(W - 1, k + 1) + j * W] - P[max(0, k - 1) + j * W]
            let dv = P[k + min(H - 1, j + 1) * W] - P[k + max(0, j - 1) * W]
            return simd_cross(du, dv)
        }
        var vn = [SIMD3<Float>](repeating: .zero, count: W * H)
        var vl = [Int](repeating: 0, count: W * H), va = vl, vlay = vl, vt = vl
        for j in 0..<H { for k in 0..<W {
            let i = k + j * W
            var n = sn[i]
            var near = dep[i] > 1e-4
            if !near { for (dk, dj) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let kk = k + dk, jj = j + dj
                if kk >= 0 && jj >= 0 && kk < W && jj < H && dep[kk + jj * W] > 1e-4 { near = true; break }
            } }
            if near {
                let gd = grad(pos, k, j), gf = grad(flat, k, j)
                let ld = simd_length(gd), lf = simd_length(gf)
                if ld > 1e-7 && lf > 1e-7 {
                    var nd = gd / ld, nf = gf / lf
                    if simd_dot(nf, sn[i]) < 0 { nf = -nf; nd = -nd }
                    // Rotate the smooth normal by the turn from the flat patch's normal to the carved one.
                    let tilted = sn[i] + (nd - nf)
                    if simd_length(tilted) > 1e-4 { n = simd_normalize(tilted) }
                }
            }
            vn[i] = n
            let s = S[k], t = T[j]
            let w = [(1 - s) * (1 - t), s * (1 - t), s * t, (1 - s) * t]
            var sky: Float = 0, blk: Float = 0, aoF: Float = 0, best = 0
            for c in 0..<4 {
                sky += w[c] * Float(light[c] & 15); blk += w[c] * Float((light[c] >> 4) & 15); aoF += w[c] * Float(ao[c])
                if w[c] > w[best] { best = c }
            }
            let inside = dep[i] > 0.035
            vl[i] = Int(sky.rounded()) | Int(blk.rounded()) << 4
            // Deep in a bowl the walls round it shade the floor.
            va[i] = max(0, Int(aoF.rounded()) - (dep[i] > 0.05 ? 1 : 0) - (dep[i] > 0.2 ? 1 : 0))
            vlay[i] = inside ? inner.layer : layers[best]
            vt[i] = inside ? inner.tint : tints[best]
        } }
        for j in 0..<(H - 1) { for k in 0..<(W - 1) {
            let i00 = k + j * W, i10 = k + 1 + j * W, i11 = k + 1 + (j + 1) * W, i01 = k + (j + 1) * W
            // One material per small quad (flat-shaded layer): the corner nearest the bowl decides.
            let deepest = [i00, i10, i11, i01].max { dep[$0] < dep[$1] }!
            let lay = vlay[deepest], tn = vt[deepest]
            for o in [i00, i10, i11, i01] {
                DetailMesh.vertex(out, pos[o], vn[o], Craters.faceUV(f, pos[o]), layer: lay, tint: tn, ao: va[o], light: vl[o])
            }
        } }
    }
}
