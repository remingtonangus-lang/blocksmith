import Foundation
import simd

// P384 (Remington, Oct 20: sub-pixel far copies for everything that isn't ground): past GroundMerge.farDistance
// (~180 blocks) a Quest 3 pixel (P375: about 25 a degree, 0.000698 radians) spans 180 x 0.000698 = 0.126 block, so a
// copy within 1/8 block of the full mesh differs from it by under a pixel there; at 360 blocks a pixel is 1/4 block,
// but view 24 ends at 384 blocks, so a second, coarser copy would serve only the outer 24 blocks of the view (a sixth of
// the far ring's area) at the cost of a third copy in memory: one far copy at 1/8 for everything past 180.
// The renderer's far switch (SceneRenderer: P375, per frame from the exact distance, nothing remeshed as the eye moves)
// draws, past that distance:
//   - the opaque stream's far copy in place of its leading quads: the ground (AdaptiveGround's far copy), the bevelled
//     faces of built blocks drawn plain (their 1/16 chamfers are half a pixel there) and merged where their corners
//     match, and the leaf blobs' far shell (one solid shell, the outer one that makes the canopy's outline, drawn per
//     position like the ground and simplified to the far bound) in place of their two cutout shells;
//   - the detail stream's far copy (trunks, limbs, round shapes, spikes, rails, struck cubes, free pieces): its solid
//     quads simplified by AdaptiveGround's collapse to the far bound measured both ways, with the vertices that a
//     shape's generator draws at one place with near-equal normals (a trunk's block-by-block rings) joined first.
// Built blocks are not merged across light steps: one level of skylight is 4-11% brightness (10-27 of 255 on a white
// texel) and one occlusion step 19-31%, so no step is under one level of 255 at any distance (no fog in clear air);
// faces merge only where their corners match, as near.
extension AdaptiveGround {
    // How far a far detail vertex's shading may drift: the normal (difference of unit vectors; the shading is lit per
    // vertex from it, 0.15 is about 6% brightness at most) and the texture position (in blocks: 0.1 is 1.6 texels, half
    // a pixel at 180 blocks).
    static var detailNormalTol: Double = Double(ProcessInfo.processInfo.environment["BS_FAR_NORMAL"] ?? "") ?? 0.15
    static var detailUVTol: Double = Double(ProcessInfo.processInfo.environment["BS_FAR_UV"] ?? "") ?? 0.1
    // Normals closer than this join a shape's vertices drawn at one place (with the same texture position and the rest).
    static var detailWeldTol: Float = 0.12

    @inline(__always) static func halfToFloat(_ h: UInt32) -> Float {
        let s = (h >> 15) & 1, e = Int((h >> 10) & 31), m = h & 1023
        let v: Float
        if e == 0 { v = Float(m) / 1024 / 16384 } else if e == 31 { v = .infinity } else { v = (1 + Float(m) / 1024) * powf(2, Float(e - 15)) }
        return s == 1 ? -v : v
    }

    struct DetailGuard: CollapseGuard {
        let attr: [UInt32]                    // w2 >> 8: tint, ao, sky, block, layer, cut
        let nrm: [SIMD3<Double>], uv: [SIMD2<Double>]
        let seams = true
        let lTol = AdaptiveGround.lightTol + 1e-9, oTol = AdaptiveGround.aoTol + 1e-9
        let nTol = AdaptiveGround.detailNormalTol, uTol = AdaptiveGround.detailUVTol
        // (one material a shape's part: layer, tint and cutout must match to join)
        @inline(__always) func mat(_ i: Int) -> UInt32 { attr[i] & 0x00FF_F003 }
        @inline(__always) func same(_ a: Int, _ b: Int) -> Bool { mat(a) == mat(b) }
        @inline(__always) func sky(_ i: Int) -> Double { Double((attr[i] >> 4) & 15) }
        @inline(__always) func blk(_ i: Int) -> Double { Double((attr[i] >> 8) & 15) }
        @inline(__always) func occ(_ i: Int) -> Double { Double((attr[i] >> 2) & 3) }
        func holds(_ qi: Int, _ t: SIMD3<Int32>, _ w: SIMD3<Double>) -> Bool {
            let a = Int(t[0]), b = Int(t[1]), c = Int(t[2])
            let m = mat(qi)
            if mat(a) != m || mat(b) != m || mat(c) != m { return false }
            let ls: Double = w[0] * sky(a) + w[1] * sky(b) + w[2] * sky(c)
            if abs(ls - sky(qi)) > lTol { return false }
            let lb: Double = w[0] * blk(a) + w[1] * blk(b) + w[2] * blk(c)
            if abs(lb - blk(qi)) > lTol { return false }
            let lo: Double = w[0] * occ(a) + w[1] * occ(b) + w[2] * occ(c)
            if abs(lo - occ(qi)) > oTol { return false }
            let n: SIMD3<Double> = nrm[a] * w[0] + nrm[b] * w[1] + nrm[c] * w[2]
            if simd_length(n - nrm[qi]) > nTol { return false }
            let u: SIMD2<Double> = uv[a] * w[0] + uv[b] * w[1] + uv[c] * w[2]
            return simd_length(u - uv[qi]) <= uTol
        }
    }

    // The detail quads in buf[from..<buf.count] (DetailMesh: 4 words a vertex, 16 a quad) simplified to `tol` in
    // place. Returns the quads removed.
    @discardableResult
    static func simplifyDetail(_ buf: GrowBuf<UInt32>, from: Int, tol: Float) -> Int {
        let nq = (buf.count - from) / DetailMesh.wordsPerQuad
        guard nq >= 4 else { return 0 }
        let p = buf.ptr + from
        // Vertices by their words without the normal; those of one key whose normals are within detailWeldTol are one.
        struct Key: Hashable { let a: UInt32, b: UInt32, c: UInt32, d: UInt32 }
        var index: [Key: [Int32]] = [:]
        index.reserveCapacity(nq * 2)
        var words: [SIMD4<UInt32>] = [], pos: [SIMD3<Double>] = [], nsum: [SIMD3<Float>] = [], first: [SIMD3<Float>] = []
        var attr: [UInt32] = [], uv: [SIMD2<Double>] = []
        var welded = [Bool]()
        @inline(__always) func s8(_ v: UInt32) -> Float { Float(Int8(bitPattern: UInt8(v & 255))) / 127 }
        @inline(__always) func s16(_ v: UInt32) -> Double { Double(Int16(bitPattern: UInt16(v & 0xFFFF))) / 256 }
        func vid(_ o: Int) -> Int32 {
            let w0 = p[o], w1 = p[o + 1], w2 = p[o + 2], w3 = p[o + 3]
            let n = SIMD3<Float>(s8(w1 >> 16), s8(w1 >> 24), s8(w2))
            let k = Key(a: w0, b: w1 & 0xFFFF, c: w2 >> 8, d: w3)
            if let list = index[k] {
                for i in list where simd_length(first[Int(i)] - n) <= detailWeldTol {
                    if first[Int(i)] != n { welded[Int(i)] = true }
                    nsum[Int(i)] += n
                    return i
                }
            }
            let i = Int32(words.count)
            index[k, default: []].append(i)
            words.append(SIMD4(w0, w1, w2, w3))
            pos.append(SIMD3(s16(w0), s16(w0 >> 16), s16(w1)))
            first.append(n); nsum.append(n); welded.append(false)
            attr.append(w2 >> 8)
            uv.append(SIMD2(Double(halfToFloat(w3 & 0xFFFF)), Double(halfToFloat(w3 >> 16))))
            return i
        }
        var tris: [SIMD3<Int32>] = []
        tris.reserveCapacity(nq * 2)
        for q in 0..<nq {
            var v = SIMD4<Int32>(repeating: 0)
            for k in 0..<4 { v[k] = vid(q * 16 + k * 4) }
            if v[0] != v[1] && v[1] != v[2] && v[0] != v[2] { tris.append(SIMD3(v[0], v[1], v[2])) }
            if v[0] != v[2] && v[2] != v[3] && v[0] != v[3] { tris.append(SIMD3(v[0], v[2], v[3])) }
        }
        // A joined vertex is drawn with its members' mean normal.
        var nrm = [SIMD3<Double>](repeating: .zero, count: words.count)
        for i in 0..<words.count {
            var n = nsum[i]
            if welded[i] {
                n = simd_length(n) > 1e-6 ? simd_normalize(n) : first[i]
                let w1 = (words[i][1] & 0xFFFF) | DetailMesh.snorm8(n.x) << 16 | DetailMesh.snorm8(n.y) << 24
                let w2 = (words[i][2] & ~UInt32(255)) | DetailMesh.snorm8(n.z)
                words[i][1] = w1; words[i][2] = w2
            } else {
                n = first[i]
            }
            nrm[i] = SIMD3<Double>(n)
        }
        let live = collapse(pos: pos, grid: pos, tris: tris, tol: tol, guard: DetailGuard(attr: attr, nrm: nrm, uv: uv))
        let out = pairQuads(live)
        guard out.count < nq else { return 0 }
        var w = 0
        for q in out { for k in 0..<4 { let v = words[Int(q[k])]; p[w] = v[0]; p[w + 1] = v[1]; p[w + 2] = v[2]; p[w + 3] = v[3]; w += 4 } }
        buf.count = from + w
        return nq - out.count
    }
}
