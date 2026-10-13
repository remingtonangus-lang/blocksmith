import Foundation
import simd

// Polygon terrain from the ground up (P142, docs/objectives/polygon-ground-up.md): the world generator's own continuous
// fields, before they are quantized into blocks, for the smooth mesher (Mesher.smoothQuads).
//
// WorldGen decides every natural block from two kinds of field: the terrain density (a trilinear 4x8x4 lattice of
// height, cliff and overhang noise: solid where > 0) and three cave fields (cheese caverns, spaghetti tunnels, noodles,
// each a trilinear 4x4x4 lattice: carved where > 0). This class evaluates the same lattices, with the same node values
// and the same interpolation order, at any block, so the smooth surface runs through the field's real zero crossings at
// sub-block precision instead of round the blocks the field was rounded to. The block grid stays the truth: a sample
// whose block disagrees with the field (dug, placed, built over, a bank or pond the surface rules made) is "off field"
// and the mesher falls back to block faces there.
//
// Lazy: nodes and block samples are computed on first use (the mesher asks only round the surface), per mesh worker
// thread (MeshScratch.field), for one section's sample box of N^3 blocks.
struct SmoothSite {
    let gen: WorldGen
    let cx: Int, cz: Int
}

final class SmoothField {
    static let N = MeshScratch.smN0                 // sample box edge (the smooth mesher's solid-flag box)
    static let NN = N * N
    static let NNN = N * N * N
    // Sample box origin (world x, internal y, world z of sample 0).
    private(set) var ox = 0, oy = 0, oz = 0
    private(set) var gen: WorldGen?

    // Block samples: terrain density (> 0 solid) and the three carve fields (> 0 carved). NaN = not yet computed.
    private let sT = UnsafeMutablePointer<Float>.allocate(capacity: SmoothField.NNN)
    private let sK = UnsafeMutablePointer<Float>.allocate(capacity: SmoothField.NNN * 3)
    private let spagT = UnsafeMutablePointer<Float>.allocate(capacity: SmoothField.NN)       // per column

    // Terrain lattice nodes round the box: x/z every 4 blocks, y every 8.
    private static let TX = N / 4 + 3, TY = N / 8 + 3
    private let tNode = UnsafeMutablePointer<Float>.allocate(capacity: TX * TX * TY)
    private let tCol = UnsafeMutablePointer<WorldGen.Col>.allocate(capacity: TX * TX)
    private let tColSet = UnsafeMutablePointer<Bool>.allocate(capacity: TX * TX)
    private var tgx0 = 0, tgz0 = 0, tgy0 = 0
    // Cave lattice nodes: every 4 blocks on all axes, five noises.
    private static let KX = N / 4 + 3
    private let kNode = UnsafeMutablePointer<Float>.allocate(capacity: KX * KX * KX * 5)
    private var kgy0 = 0

    deinit {
        sT.deallocate(); sK.deallocate(); spagT.deallocate()
        tNode.deallocate(); tCol.deallocate(); tColSet.deallocate(); kNode.deallocate()
    }

    // Starts a section: sample (ix, iy, iz) is world block (x0 + ix, y0 + iy, z0 + iz).
    func prepare(_ g: WorldGen, x0: Int, y0: Int, z0: Int) {
        gen = g
        ox = x0; oy = y0; oz = z0
        let nan = Float.nan
        sT.initialize(repeating: nan, count: SmoothField.NNN)
        sK.initialize(repeating: nan, count: SmoothField.NNN * 3)
        spagT.initialize(repeating: nan, count: SmoothField.NN)
        tgx0 = floorDiv(x0, 4); tgz0 = floorDiv(z0, 4); tgy0 = max(0, y0 >> 3)
        tNode.initialize(repeating: nan, count: SmoothField.TX * SmoothField.TX * SmoothField.TY)
        tColSet.initialize(repeating: false, count: SmoothField.TX * SmoothField.TX)
        kgy0 = max(0, y0 >> 2)
        kNode.initialize(repeating: nan, count: SmoothField.KX * SmoothField.KX * SmoothField.KX * 5)
    }

    // Inside the world's height range (the field says nothing outside it).
    @inline(__always) func inWorld(_ i: Int) -> Bool {
        let y = oy + i / SmoothField.NN
        return y >= 0 && y < CH
    }

    // MARK: Terrain density

    private static let latNY = CH / 8 + 1           // WorldGen.Lattice.ny

    @inline(__always) private func tNodeAt(_ gx: Int, _ gy: Int, _ gz: Int) -> Float {
        let ix = gx - tgx0, iz = gz - tgz0, iy = gy - tgy0
        let k = (ix * SmoothField.TX + iz) * SmoothField.TY + iy
        let v = tNode[k]
        if !v.isNaN { return v }
        let g = gen!
        let ci = ix * SmoothField.TX + iz
        if !tColSet[ci] { tCol[ci] = g.colInfo(gx * 4, gz * 4); tColSet[ci] = true }
        let d = g.density(tCol[ci], gx * 4, gy * 8, gz * 4)
        tNode[k] = d
        return d
    }

    // Terrain density at sample i (the stone fill's own value: bit-identical interpolation order).
    func terrain(_ i: Int) -> Float {
        let v = sT[i]
        if !v.isNaN { return v }
        let ix = i % SmoothField.N, iz = (i / SmoothField.N) % SmoothField.N, iy = i / SmoothField.NN
        let x = ox + ix, y = oy + iy, z = oz + iz
        let gx = floorDiv(x, 4), gz = floorDiv(z, 4), gy = min(SmoothField.latNY - 2, y >> 3)
        let fx = Float(x & 3) / 4, fz = Float(z & 3) / 4, fy = Float(y - gy * 8) / 8
        let c000 = tNodeAt(gx, gy, gz), c100 = tNodeAt(gx + 1, gy, gz)
        let c010 = tNodeAt(gx, gy + 1, gz), c110 = tNodeAt(gx + 1, gy + 1, gz)
        let c001 = tNodeAt(gx, gy, gz + 1), c101 = tNodeAt(gx + 1, gy, gz + 1)
        let c011 = tNodeAt(gx, gy + 1, gz + 1), c111 = tNodeAt(gx + 1, gy + 1, gz + 1)
        let x00 = c000 + (c100 - c000) * fx, x10 = c010 + (c110 - c010) * fx
        let x01 = c001 + (c101 - c001) * fx, x11 = c011 + (c111 - c011) * fx
        let y0 = x00 + (x10 - x00) * fy, y1 = x01 + (x11 - x01) * fy
        let r = y0 + (y1 - y0) * fz
        sT[i] = r
        return r
    }

    // MARK: Caves

    private static let caveNY = CH / 4 + 1          // WorldGen.CaveLattice.ny

    // Cave noise f (0 cheese, 1-2 spaghetti, 3-4 noodles) at node (gx, gy, gz).
    @inline(__always) private func kNodeAt(_ f: Int, _ gx: Int, _ gy: Int, _ gz: Int) -> Float {
        let ix = gx - tgx0, iz = gz - tgz0, iy = gy - kgy0
        let k = (((ix * SmoothField.KX + iz) * SmoothField.KX) + iy) * 5 + f
        let v = kNode[k]
        if !v.isNaN { return v }
        let g = gen!
        let x = Float(gx * 4), z = Float(gz * 4), y = Float(gy * 4 - YOFF)
        let r: Float
        switch f {
        case 0: r = g.cheeseN.noise3(x / 70, y / 38, z / 70)
        case 1: r = g.spag1.noise3(x / 48, y / 32, z / 48)
        case 2: r = g.spag2.noise3(x / 48 + 50, y / 32, z / 48)
        case 3: r = g.noodle1.noise3(x / 22, y / 16, z / 22)
        default: r = g.noodle2.noise3(x / 22 + 30, y / 16, z / 22)
        }
        kNode[k] = r
        return r
    }

    // WorldGen.CaveLattice.sample at a world block.
    private func caveSample(_ f: Int, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let gx = floorDiv(x, 4), gz = floorDiv(z, 4), gy = min(SmoothField.caveNY - 2, y >> 2)
        let fx = Float(x & 3) / 4, fz = Float(z & 3) / 4, fy = Float(y & 3) / 4
        let a0 = kNodeAt(f, gx, gy, gz), a1 = kNodeAt(f, gx + 1, gy, gz)
        let b0 = kNodeAt(f, gx, gy + 1, gz), b1 = kNodeAt(f, gx + 1, gy + 1, gz)
        let c0 = kNodeAt(f, gx, gy, gz + 1), c1 = kNodeAt(f, gx + 1, gy, gz + 1)
        let d0 = kNodeAt(f, gx, gy + 1, gz + 1), d1 = kNodeAt(f, gx + 1, gy + 1, gz + 1)
        let a = a0 + (a1 - a0) * fx, b = b0 + (b1 - b0) * fx
        let c = c0 + (c1 - c0) * fx, d = d0 + (d1 - d0) * fx
        let e = a + (b - a) * fy, g = c + (d - c) * fy
        return e + (g - e) * fz
    }

    // Carve field k at sample i (> 0 carved): 0 cheese caverns, 1 spaghetti tunnels, 2 noodles (as WorldGen.carveCaves).
    func carve(_ k: Int, _ i: Int) -> Float {
        let v = sK[i * 3 + k]
        if !v.isNaN { return v }
        let ix = i % SmoothField.N, iz = (i / SmoothField.N) % SmoothField.N, iy = i / SmoothField.NN
        let x = ox + ix, y = oy + iy, z = oz + iz
        let yd = y - YOFF
        let r: Float
        switch k {
        case 0:
            r = caveSample(0, x, y, z) + (yd < 30 ? 0 : -Float(yd - 30) / 90) - 0.3
        case 1:
            let ci = ix + iz * SmoothField.N
            var t = spagT[ci]
            if t.isNaN { t = 0.05 + 0.025 * gen!.spagMod.noise2(Float(x) / 40, Float(z) / 40); spagT[ci] = t }
            r = t - max(abs(caveSample(1, x, y, z)), abs(caveSample(2, x, y, z)))
        default:
            r = yd < 40 ? 0.022 - max(abs(caveSample(3, x, y, z)), abs(caveSample(4, x, y, z))) : -1
        }
        sK[i * 3 + k] = r
        return r
    }

    // MARK: Combined

    // What the generator's fields alone make of sample i: solid ground or open (air, water, lava).
    func solid(_ i: Int) -> Bool {
        let y = oy + i / SmoothField.NN
        if y < 3 { return true }                       // the hot rock floor is always solid
        if terrain(i) <= 0 { return false }
        if y < 6 { return true }
        return !(carve(0, i) > 0 || carve(1, i) > 0 || carve(2, i) > 0)
    }

    // Where the surface crosses the edge from solid sample a to open sample b (0 at a, 1 at b), and which field made it
    // (0 terrain, 1...3 a cave field); nil if no field crosses there (a rule of the generator, not a field).
    func crossing(_ a: Int, _ b: Int) -> (Float, Int)? {
        var t: Float = 2, which = -1
        let ta = terrain(a), tb = terrain(b)
        if ta > 0 && tb <= 0 { t = ta / (ta - tb); which = 0 }
        let yb = oy + b / SmoothField.NN, ya = oy + a / SmoothField.NN
        if yb >= 6 && ya >= 6 {
            for k in 0..<3 {
                let ka = carve(k, a), kb = carve(k, b)
                if ka <= 0 && kb > 0 {
                    let tk = ka / (ka - kb)
                    if tk < t { t = tk; which = k + 1 }
                }
            }
        }
        return which < 0 ? nil : (max(0, min(1, t)), which)
    }

    // Field `which` as a solid-positive value at sample i (terrain as is, cave fields negated).
    @inline(__always) func value(_ which: Int, _ i: Int) -> Float {
        which == 0 ? terrain(i) : -carve(which - 1, i)
    }

    // Outward surface direction of field `which` over the 2x2x2 samples from c0 (minus its gradient), normalized.
    func outward(_ which: Int, _ c0: Int) -> SIMD3<Float> {
        let N = SmoothField.N, NN = SmoothField.NN
        var s = (Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0))
        s.0 = value(which, c0); s.1 = value(which, c0 + 1)
        s.2 = value(which, c0 + NN); s.3 = value(which, c0 + NN + 1)
        s.4 = value(which, c0 + N); s.5 = value(which, c0 + N + 1)
        s.6 = value(which, c0 + N + NN); s.7 = value(which, c0 + N + NN + 1)
        // corner bits: x 1, y 2, z 4 (the mesher's corner order)
        let gx = (s.1 - s.0) + (s.3 - s.2) + (s.5 - s.4) + (s.7 - s.6)
        let gy = (s.2 - s.0) + (s.3 - s.1) + (s.6 - s.4) + (s.7 - s.5)
        let gz = (s.4 - s.0) + (s.5 - s.1) + (s.6 - s.2) + (s.7 - s.3)
        let g = SIMD3<Float>(-gx, -gy, -gz)
        let l = simd_length(g)
        return l > 1e-9 ? g / l : SIMD3<Float>(0, 1, 0)
    }
}
