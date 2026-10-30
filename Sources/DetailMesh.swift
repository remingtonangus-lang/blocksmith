import Foundation
import simd

// Realistic world (docs/design/realistic-world.md 1.2): the second per-section vertex stream for round shapes (trunks,
// limbs, gourds, organic primitives, craters). The section vertex (Mesher, 2 x UInt32) holds 1/16-block positions and
// a 7x7-level normal that only works with position-projected textures; these shapes need smooth normals and textures
// that wrap round them, so they are drawn from 16-byte vertices:
//   w0: x Int16 (1/256 block, section-local) | y Int16 << 16
//   w1: z Int16 | nx snorm8 << 16 | ny snorm8 << 24
//   w2: nz snorm8 | tint(2) << 8 | ao(2) << 10 | sky(4) << 12 | block(4) << 16 | layer(11) << 20 | cut(1) << 31
//   w3: u half | v half << 16                    (texture repeats: bark wraps round a trunk)
// Quads of 4 vertices (corners counter-clockwise seen from outside) drawn with the shared quad index buffer; a triangle
// is a quad with its last corner repeated. Quest: quest/shaders/chunk_detail.vert. The Mac doesn't draw them
// (Mesher.detailMeshes is off there, so its sections keep the cubes).
enum DetailMesh {
    static let wordsPerVertex = 4
    static let wordsPerQuad = 16

    // IEEE half from a float (round to nearest; texture coordinates stay well inside the half range).
    @inline(__always) static func half(_ f: Float) -> UInt32 {
        let b = f.bitPattern
        let sign = (b >> 16) & 0x8000
        var e = Int((b >> 23) & 0xFF) - 127 + 15
        var m = b & 0x7FFFFF
        if e <= 0 {
            if e < -10 { return sign }
            m |= 0x800000
            let shift = UInt32(14 - e)
            var h = m >> shift
            if (m >> (shift - 1)) & 1 != 0 { h += 1 }
            return sign | h
        }
        if e >= 31 { return sign | 0x7C00 }
        m += 0x1000                                  // round
        if m & 0x800000 != 0 { m = 0; e += 1; if e >= 31 { return sign | 0x7C00 } }
        return sign | (UInt32(e) << 10) | (m >> 13)
    }
    @inline(__always) static func snorm8(_ f: Float) -> UInt32 { UInt32(UInt8(bitPattern: Int8(max(-127, min(127, (f * 127).rounded()))))) }
    @inline(__always) static func pos16(_ f: Float) -> UInt32 { UInt32(UInt16(bitPattern: Int16(max(-32767, min(32767, (f * 256).rounded()))))) }

    // World-stable value noise in -1...1 at a world point (lattice 1 block / `scale`).
    static func noise(_ w: SIMD3<Float>, _ scale: Float, _ salt: UInt32) -> Float {
        let q = w * scale
        let f = floor(q), t = q - f
        let s = t * t * (3 - 2 * t)
        let ix = Int(f.x), iy = Int(f.y), iz = Int(f.z)
        @inline(__always) func h(_ dx: Int, _ dy: Int, _ dz: Int) -> Float { hashf(ix + dx, iy + dy, iz + dz, salt) * 2 - 1 }
        let x00 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * s.x, x10 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * s.x
        let x01 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * s.x, x11 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * s.x
        let y0 = x00 + (x10 - x00) * s.y, y1 = x01 + (x11 - x01) * s.y
        return y0 + (y1 - y0) * s.z
    }

    // Appends one vertex. p: section-local position in blocks; n: unit normal; light: sky | block << 4.
    @inline(__always) static func vertex(_ out: GrowBuf<UInt32>, _ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>,
                                         layer: Int, tint: Int = 0, ao: Int = 3, light: Int, cut: Bool = false) {
        out.append(pos16(p.x) | pos16(p.y) << 16)
        out.append(pos16(p.z) | snorm8(n.x) << 16 | snorm8(n.y) << 24)
        out.append(snorm8(n.z) | UInt32(tint & 3) << 8 | UInt32(ao & 3) << 10 | UInt32(light & 15) << 12
                   | UInt32((light >> 4) & 15) << 16 | UInt32(layer & 2047) << 20 | (cut ? 1 << 31 : 0))
        out.append(half(uv.x) | half(uv.y) << 16)
    }
}

// One shape's vertices for a section, with the context every generator needs: light and occlusion read from the
// mesher's region round the section, world-stable noise and the drawn smooth ground (for roots and resting shapes).
struct DetailContext {
    let out: GrowBuf<UInt32>                  // solid quads
    let cutOut: GrowBuf<UInt32>               // alpha-tested quads (drawn after the solid ones)
    let R: UnsafeMutablePointer<BlockID>      // the mesher's 48^3 region (index x + z*48 + y*2304, section at 16,16,16)
    let sky: UnsafeMutablePointer<UInt8>, blk: UnsafeMutablePointer<UInt8>
    let wx0: Int, wy0: Int, wz0: Int          // world block of the section's local 0 (internal y: wy0 = sy * 16)
    let lod: Int                              // 0 near, 2 mid, 1 far (fewer sides)
    let sc: MeshScratch
    let srcs: [[BlockID]]                     // the 3x3 chunks' full-height columns (Mesher.buildSection's n9 data)
    let sy: Int
    // P297 (a): field worlds: the 3x3 chunks' stores, so a full-height read sees the ground the field holds (the built
    // layer alone is air there: no trunk ever stood on anything, so no tree was read as a tree).
    var field: [BlockStore]? = nil
    // P389: cells a struck object draws (world coordinates): air to the round-shape generators.
    var skipCells: Set<IVec3>? = nil
    @inline(__always) func skipped(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard let s = skipCells else { return false }
        return s.contains(IVec3(wx0 + x, wy0 + y, wz0 + z))
    }

    // A block anywhere in the 3x3 chunks (section-local x, z in -16..<32), any height: for shapes taller than the region
    // (a 25-block trunk measured from its foot). Below the world: bedrock; above the stored part: air.
    @inline(__always) func column(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if skipCells != nil && skipped(x, y, z) { return AIR }
        let cx = (x + 16) >> 4, cz = (z + 16) >> 4
        guard cx >= 0 && cz >= 0 && cx < 3 && cz < 3 else { return AIR }
        let wy = sy * 16 + y
        if wy < 0 { return BEDROCK }
        if wy >= CH { return AIR }
        let src = srcs[cx + cz * 3]
        let i = ((x + 16) & 15) + ((z + 16) & 15) * CS + wy * CSQ
        let b = i < src.count ? src[i] : AIR
        guard b == AIR, let field else { return b }
        let st = field[cx + cz * 3]
        return st.ground(i) ? FieldMat.blocks[Int(st.material(i))] : AIR
    }

    // P297 (a): the drawn ground's height (section-local y) round the top of block (x, y, z), section-local: the smooth
    // surface's vertices at its four top corners (Mesher.smoothGroundTop), the first row of them found going down from
    // there `reach` blocks (their mean), or with `lowest` the lowest of all of them in that reach (the downhill side of a
    // slope). Nil where the section has no smooth ground there (block worlds, built ground, out of range).
    func groundTop(_ x: Int, _ y: Int, _ z: Int, reach: Int = 3, lowest: Bool = false) -> Float? {
        guard sc.smValid else { return nil }
        let KO = SmoothTerrain.maxRelax, K = 17 + 2 * KO, KK = K * K
        var lo: Float = .greatestFiniteMagnitude
        for gy in stride(from: y, through: y - reach, by: -1) {
            let cy = gy + KO
            guard cy >= 0 && cy < K else { continue }
            var sum: Float = 0, n: Float = 0
            for dz in -1...0 { for dx in -1...0 {
                let cx = x + dx + KO, cz = z + dz + KO
                guard cx >= 0 && cx < K && cz >= 0 && cz < K else { continue }
                let vi = cx + cz * K + cy * KK
                if sc.smL[vi] >= 0 { let v = sc.smV[vi * 3 + 1]; sum += v; n += 1; lo = min(lo, v) }
            } }
            if n > 0 && !lowest { return sum / n }
        }
        return lo < .greatestFiniteMagnitude ? lo : nil
    }

    @inline(__always) func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + Mesher.C0) + (z + Mesher.C0) * Mesher.RW + (y + Mesher.C0) * Mesher.RL }
    @inline(__always) func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        let rx = x + Mesher.C0, ry = y + Mesher.C0, rz = z + Mesher.C0
        guard rx >= 0 && ry >= 0 && rz >= 0 && rx < Mesher.RW && ry < Mesher.RH && rz < Mesher.RW else { return AIR }
        if skipCells != nil && skipped(x, y, z) { return AIR }
        return R[ri(x, y, z)]
    }
    // Packed sky | block << 4 at a section-local point: the brightest open cell among the 8 round it (so a shape lit
    // from one side isn't dimmed by the solid block it is drawn inside).
    func light(_ p: SIMD3<Float>) -> Int {
        let bx = Int(floor(p.x - 0.5)), by = Int(floor(p.y - 0.5)), bz = Int(floor(p.z - 0.5))
        var bs = 0, bb = 0, any = false
        let lo = Blocks.lightOpaque, op = Blocks.opaque
        for c in 0..<8 {
            let x = bx + (c & 1), y = by + ((c >> 1) & 1), z = bz + (c >> 2)
            let rx = x + Mesher.C0, ry = y + Mesher.C0, rz = z + Mesher.C0
            guard rx >= 0 && ry >= 0 && rz >= 0 && rx < Mesher.RW && ry < Mesher.RH && rz < Mesher.RW else { continue }
            let i = ri(x, y, z)
            if lo[Int(R[i])] && op[Int(R[i])] { continue }
            any = true
            bs = max(bs, Int(sky[i])); bb = max(bb, Int(blk[i]))
        }
        if !any {
            let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
            let rx = x + Mesher.C0, ry = y + Mesher.C0, rz = z + Mesher.C0
            if rx >= 0 && ry >= 0 && rz >= 0 && rx < Mesher.RW && ry < Mesher.RH && rz < Mesher.RW {
                let i = ri(x, y, z); bs = max(0, Int(sky[i]) - 1); bb = Int(blk[i])
            }
        }
        return bs | bb << 4
    }
    // Ambient occlusion 0 (dark) ... 3 (open): how many of the 3x3x3 blocks round a point are solid.
    func ao(_ p: SIMD3<Float>) -> Int {
        let bx = Int(floor(p.x)), by = Int(floor(p.y)), bz = Int(floor(p.z))
        var n = 0
        let aoT = Blocks.aoOcc
        for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where aoT[Int(block(bx + dx, by + dy, bz + dz))] { n += 1 } } }
        return n <= 9 ? 3 : (n <= 13 ? 2 : (n <= 18 ? 1 : 0))
    }
    // World-stable value noise in -1...1 (lattice 1 block / `scale`), the same in every section that asks.
    func noise(_ p: SIMD3<Float>, _ scale: Float, _ salt: UInt32) -> Float {
        DetailMesh.noise(p + SIMD3<Float>(Float(wx0), Float(wy0), Float(wz0)), scale, salt)
    }
    // World-stable hash of a block (0...1).
    func hash(_ x: Int, _ y: Int, _ z: Int, _ salt: UInt32) -> Float { hashf(wx0 + x, wy0 + y, wz0 + z, salt) }

    @inline(__always) func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>, layer: Int, tint: Int = 0, ao: Int? = nil,
                                  light: Int? = nil, cut: Bool = false) {
        DetailMesh.vertex(cut ? cutOut : out, p, n, uv, layer: layer, tint: tint, ao: ao ?? self.ao(p + n * 0.3),
                          light: light ?? self.light(p + n * 0.3), cut: cut)
    }
}
