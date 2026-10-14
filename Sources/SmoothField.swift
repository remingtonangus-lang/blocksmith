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
extension WorldGen {
    // The terrain density at one world block (the stone fill's value; SmoothField's per-section path, unbatched).
    func terrainDensity(_ x: Int, _ y: Int, _ z: Int) -> Float {
        let y = max(0, min(CH - 1, y))
        let gx = floorDiv(x, 4), gz = floorDiv(z, 4), gy = min(CH / 8 - 1, y >> 3)
        let fx = Float(x & 3) / 4, fz = Float(z & 3) / 4, fy = Float(y - gy * 8) / 8
        func n(_ ax: Int, _ ay: Int, _ az: Int) -> Float { density(colInfo(ax * 4, az * 4), ax * 4, ay * 8, az * 4) }
        let c000 = n(gx, gy, gz), c100 = n(gx + 1, gy, gz), c010 = n(gx, gy + 1, gz), c110 = n(gx + 1, gy + 1, gz)
        let c001 = n(gx, gy, gz + 1), c101 = n(gx + 1, gy, gz + 1), c011 = n(gx, gy + 1, gz + 1), c111 = n(gx + 1, gy + 1, gz + 1)
        let x00 = c000 + (c100 - c000) * fx, x10 = c010 + (c110 - c010) * fx
        let x01 = c001 + (c101 - c001) * fx, x11 = c011 + (c111 - c011) * fx
        let y0 = x00 + (x10 - x00) * fy, y1 = x01 + (x11 - x01) * fy
        return y0 + (y1 - y0) * fz
    }
}

extension World {
    // P142: how far the drawn smooth ground at a standing spot is above (+) or below (-) the feet (PG2: which stand on
    // the block top, or lower on the drawn top where the ground dips: World.groundTop): the field's surface height in the four columns round the spot (block centres, as the mesher samples them),
    // blended by position (World.drawnTop: the field's crossing with the dug and placed ground's edits; built blocks
    // count as their block top). 0 outside smooth field worlds or off natural ground.
    func smoothGroundOffset(_ pos: V3) -> Float {
        var key = Int.min, h = SIMD4<Float>(repeating: 0)
        return smoothGroundOffset(pos, key: &key, heights: &h)
    }

    // The same with the 4 column heights cached by the caller (mobs): recomputed only when the cell changes.
    func smoothGroundOffset(_ pos: V3, key: inout Int, heights h: inout SIMD4<Float>) -> Float {
        guard SmoothTerrain.enabled && SmoothTerrain.fromField, let g = gen as? WorldGen else { return 0 }
        let fy = Int(floor(pos.y - 0.01))
        let fb = Int(block(Int(floor(pos.x)), fy, Int(floor(pos.z))))
        guard SmoothTerrain.natural[fb] || (!Blocks.collide[fb] && SmoothTerrain.natural[Int(block(Int(floor(pos.x)), fy - 1, Int(floor(pos.z))))])
        else { return 0 }
        let bx = floor(pos.x - 0.5), bz = floor(pos.z - 0.5)
        let tx = pos.x - 0.5 - bx, tz = pos.z - 0.5 - bz
        let ck = (Int(bx) & 0xFFFFF) | ((Int(bz) & 0xFFFFF) << 20) | ((fy & 0x3FF) << 40) | ((fieldStamp & 0x1FFF) << 50)
        if ck != key { key = ck; for k in 0..<4 {
            let x = Int(bx) + (k & 1), z = Int(bz) + (k >> 1)
            var top = Float(fy + 1)
            for y in (fy - 1)...(fy + 1) where Blocks.opaque[Int(block(x, y, z))] && !Blocks.opaque[Int(block(x, y + 1, z))] {
                top = drawnTop(g, x, y, z)
            }
            h[k] = top
        } }
        let s = (h[0] * (1 - tx) + h[1] * tx) * (1 - tz) + (h[2] * (1 - tx) + h[3] * tx) * tz
        return max(-0.6, min(0.6, s - pos.y))     // (PG2: from the feet, which stand on the column's drawn top)
    }
}

struct SmoothSite {
    let gen: WorldGen
    let cx: Int, cz: Int
    var edits = FieldEditSet()              // PG1: the terrain field's edits round the chunk (TerrainField.swift)
}

final class SmoothField {
    static let N = MeshScratch.smN0                 // sample box edge (the smooth mesher's solid-flag box)
    static let NN = N * N
    static let NNN = N * N * N
    // Sample box origin (world x, internal y, world z of sample 0).
    // (Unchecked: the field is per thread, and the dynamic exclusivity checks on these were a third of its cost.)
    @exclusivity(unchecked) private(set) var ox = 0
    @exclusivity(unchecked) private(set) var oy = 0
    @exclusivity(unchecked) private(set) var oz = 0
    @exclusivity(unchecked) private(set) var gen: WorldGen?

    // Block samples: terrain density (> 0 solid) and the three carve fields (> 0 carved). NaN = not yet computed.
    private let sT = UnsafeMutablePointer<Float>.allocate(capacity: SmoothField.NNN)
    private let sK = UnsafeMutablePointer<Float>.allocate(capacity: SmoothField.NNN * 3)
    private let spagT = UnsafeMutablePointer<Float>.allocate(capacity: SmoothField.NN)       // per column

    // Terrain lattice nodes round the box, the whole height (kept while the next section is in the same chunk: a mesh
    // job meshes a chunk's sections one after another, and their boxes overlap): x/z every 4 blocks, y every 8.
    private static let TX = N / 4 + 3, TY = CH / 8 + 2
    private let tNode = UnsafeMutablePointer<Float>.allocate(capacity: TX * TX * TY)
    private let tCol = UnsafeMutablePointer<WorldGen.Col>.allocate(capacity: TX * TX)
    private let tColSet = UnsafeMutablePointer<Bool>.allocate(capacity: TX * TX)
    @exclusivity(unchecked) private var tgx0 = 0
    @exclusivity(unchecked) private var tgz0 = 0
    // Cave lattice nodes: every 4 blocks on all axes, five noises.
    private static let KX = N / 4 + 3, KY = CH / 4 + 2
    private let kNode = UnsafeMutablePointer<Float>.allocate(capacity: KX * KX * KY * 5)
    // PG1: field edits per sample (FieldEdit bounds; FieldEdit.none where there are none).
    private let sE = UnsafeMutablePointer<UInt16>.allocate(capacity: SmoothField.NNN)
    @exclusivity(unchecked) private(set) var hasEdits = false

    deinit {
        sE.deallocate()
        sT.deallocate(); sK.deallocate(); spagT.deallocate()
        tNode.deallocate(); tCol.deallocate(); tColSet.deallocate(); kNode.deallocate()
    }

    // Starts a section: sample (ix, iy, iz) is world block (x0 + ix, y0 + iy, z0 + iz).
    func prepare(_ g: WorldGen, x0: Int, y0: Int, z0: Int, edits: FieldEditSet = FieldEditSet()) {
        let nan = Float.nan
        if g !== gen || x0 != ox || z0 != oz {
            spagT.initialize(repeating: nan, count: SmoothField.NN)
            tgx0 = floorDiv(x0, 4); tgz0 = floorDiv(z0, 4)
            tNode.initialize(repeating: nan, count: SmoothField.TX * SmoothField.TX * SmoothField.TY)
            tColSet.initialize(repeating: false, count: SmoothField.TX * SmoothField.TX)
            kNode.initialize(repeating: nan, count: SmoothField.KX * SmoothField.KX * SmoothField.KY * 5)
        }
        gen = g
        ox = x0; oy = y0; oz = z0
        sT.initialize(repeating: nan, count: SmoothField.NNN)
        sK.initialize(repeating: nan, count: SmoothField.NNN * 3)
        hasEdits = false
        if !edits.isEmpty {
            let N = SmoothField.N
            sE.initialize(repeating: FieldEdit.none, count: SmoothField.NNN)
            for ch in edits.chunks {
                let bx = ch.cx * CS - x0, bz = ch.cz * CS - z0
                guard bx > -CS && bx < N && bz > -CS && bz < N else { continue }
                for (k, v) in ch.edits {
                    let i = Int(k)
                    let ix = bx + (i & 15), iz = bz + ((i >> 4) & 15), iy = (i >> 8) - y0
                    guard ix >= 0 && ix < N && iz >= 0 && iz < N && iy >= 0 && iy < N else { continue }
                    sE[ix + iz * N + iy * SmoothField.NN] = v
                    hasEdits = true
                }
            }
        }
    }

    // MARK: PG1 field edits

    @inline(__always) func edited(_ i: Int) -> Bool { hasEdits && sE[i] != FieldEdit.none }

    // The generator's distance to the surface at sample i in blocks (+ in the ground): every field's value over the
    // length of its gradient (central differences), the closest surface of the terrain and the three cave fields.
    func genDistance(_ i: Int) -> Float {
        let y = oy + i / SmoothField.NN
        if y < 3 { return 4 }
        var d = fieldDist(0, i)
        if y >= 6 { for k in 1...3 { d = min(d, fieldDist(k, i)) } }
        return max(-4, min(4, d))
    }

    private func fieldDist(_ which: Int, _ i: Int) -> Float {
        let N = SmoothField.N, NN = SmoothField.NN
        let v = value(which, i)
        let ix = i % N, iz = (i / N) % N, iy = i / NN
        func diff(_ step: Int, _ c: Int) -> Float {
            if c > 0 && c < N - 1 { return (value(which, i + step) - value(which, i - step)) * 0.5 }
            return c == 0 ? value(which, i + step) - v : v - value(which, i - step)
        }
        let gx = diff(1, ix), gy = diff(NN, iy), gz = diff(N, iz)
        let l = (gx * gx + gy * gy + gz * gz).squareRoot()
        return v / max(l, 1e-4)
    }

    // The field at sample i with its edits (blocks, + in the ground).
    @inline(__always) func distance(_ i: Int) -> Float {
        let d = genDistance(i)
        return edited(i) ? FieldEdit.apply(d, sE[i]) : d
    }

    // Inside the world's height range (the field says nothing outside it).
    @inline(__always) func inWorld(_ i: Int) -> Bool {
        let y = oy + i / SmoothField.NN
        return y >= 0 && y < CH
    }

    // MARK: Terrain density

    private static let latNY = CH / 8 + 1           // WorldGen.Lattice.ny

    @inline(__always) private func tNodeAt(_ gx: Int, _ gy: Int, _ gz: Int) -> Float {
        let ix = gx - tgx0, iz = gz - tgz0, iy = gy
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
        let x = ox + ix, y = max(0, min(CH - 1, oy + iy)), z = oz + iz      // (callers stay in the world; clamped for safety)
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
        let ix = gx - tgx0, iz = gz - tgz0, iy = gy
        let k = (((ix * SmoothField.KX + iz) * SmoothField.KY) + iy) * 5 + f
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
        let x = ox + ix, y = max(0, min(CH - 1, oy + iy)), z = oz + iz
        let yd = y - YOFF
        let r: Float
        switch k {
        case 0:
            // The cheese noise stays under 1, and fades 1/90 a block above 30: nothing carves above about 93.
            if yd > 95 { r = -1; break }
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
        if edited(i) { return distance(i) > 0 }
        let y = oy + i / SmoothField.NN
        if y < 3 { return true }                       // the hot rock floor is always solid
        if terrain(i) <= 0 { return false }
        if y < 6 { return true }
        return !(carve(0, i) > 0 || carve(1, i) > 0 || carve(2, i) > 0)
    }

    // Where the surface crosses the edge from solid sample a to open sample b (0 at a, 1 at b), and which field made it
    // (0 terrain, 1...3 a cave field); nil if no field crosses there (a rule of the generator, not a field).
    func crossing(_ a: Int, _ b: Int) -> (Float, Int)? {
        // PG1: next to an edit the crossing comes from the edited distances (field 4).
        if edited(a) || edited(b) {
            let da = max(0.02, distance(a)), db = min(-0.02, distance(b))
            return (max(0, min(1, da / (da - db))), 4)
        }
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
        which == 0 ? terrain(i) : (which == 4 ? distance(i) : -carve(which - 1, i))
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
