import Foundation
import simd

// Ledger 361 (Nov 18, Remington: "build our own compression models for far distance that balances detail with
// simplicity"): the woods past the loaded chunks, one low-poly stand-in per real tree. The tree pass (TreePlacer.place)
// is a pure function of position: a 3-block lattice, one hash per cell, the column's biome and a glade noise. `site`
// asks the same questions without the chunk, so a stand-in stands where the chunk will grow that tree, of that kind:
// walking toward a far wood, each stand-in is replaced by its own tree at the loaded edge. (The chunk's last word, the
// soil under the trunk, a building's footprint, a railway beside it, is not asked: a few stand-ins have no tree.)
//
// A conifer is a four-sided pyramid, a broadleaf a tapered box, each over a crossed trunk near the loaded edge; with
// distance the wood thins to one stand-in in four, drawn wider, so a far wood keeps its cover with a quarter of the
// quads. They are quads in the far ring's own vertex list (FarRing.build), lit and fogged by its shader: no texture,
// no extra draw call. Trees are kept per 128-block cell between builds (touched only by the one build running).
final class FarForest {
    static let reach: Float = 560                  // blocks from the ring's centre
    static let cell = 128
    static let maxQuads = 48_000                   // of the ring's draw (SceneRenderer.maxQuads is 131,072)

    struct Tree {
        var x: Int32, z: Int32
        var y: Float                               // the ground's top
        var h: Float, r: Float                     // height over the ground, the crown's half width
        var base: Float                            // where the crown begins, as a share of h
        var cone: Bool
        var leaf: V3, top: V3, bark: V3
        var hv: UInt32
        var snowy = false
    }

    let seed: UInt64
    private var cells: [Int64: [Tree]] = [:]
    init(seed: UInt64) { self.seed = seed }

    // (height, crown half width, crown start, cone, leaf tint or 0 for the biome's own)
    static func shape(_ k: TreeKind) -> (h: Float, r: Float, base: Float, cone: Bool, leaf: UInt32)? {
        switch k {
        case .oak, .swampOak: return (6.5, 2.6, 0.45, false, 0)
        case .smallOak: return (5, 2.1, 0.4, false, 0)
        case .fancyOak: return (11, 4, 0.45, false, 0)
        case .ancientOak: return (19, 7, 0.4, false, 0)
        case .birch: return (7.5, 2.4, 0.45, false, 0x80A755)
        case .tallBirch: return (11.5, 2.4, 0.6, false, 0x80A755)
        case .spruce: return (9.5, 2.7, 0.2, true, 0x619961)
        case .pine: return (10.5, 2.3, 0.5, true, 0x619961)
        case .megaSpruce: return (23, 4.6, 0.25, true, 0x619961)
        case .megaPine: return (23, 4, 0.6, true, 0x619961)
        case .jungle: return (9.5, 2.6, 0.55, false, 0)
        case .megaJungle: return (25, 5.5, 0.7, false, 0)
        case .acacia: return (7.5, 3.6, 0.72, false, 0)
        case .darkOak: return (8.5, 4, 0.45, false, 0)
        case .mangrove: return (8.5, 3, 0.5, false, 0)
        case .cherry: return (7.5, 3.6, 0.45, false, 0xE7A8C7)
        case .paleOak: return (8.5, 4, 0.45, false, 0xA3ABA0)
        case .saltpalm: return (8.5, 2.6, 0.78, false, 0)
        default: return nil                        // shrubs, stumps, snags, fallen trunks, ice spikes
        }
    }

    // The tree the chunk's tree pass would grow from lattice cell (gx, gz), if any: TreePlacer.place's own steps.
    static func site(_ gen: WorldGen, _ gx: Int, _ gz: Int) -> Tree? {
        let hv = hash3(gx, 0, gz, gen.s32 ^ 0x7EE5)
        let roll = Float((hv >> 4) & 0xFFFF) / 65536
        if roll > 0.7 { return nil }
        let tx = gx * 3 + Int(hv % 3), tz = gz * 3 + Int((hv >> 2) % 3)
        let k = gen.terrain.column(tx, tz)
        guard k.rv > 1.2 else { return nil }
        let dT = (hashf(tx, 2, tz, gen.s32 ^ 0x7EE8) - 0.5) * 0.16
        let dW = (hashf(tx, 3, tz, gen.s32 ^ 0x7EE9) - 0.5) * 0.18
        let dith = gen.terrain.biome(k, k.h, dT: dT, dW: dW)
        let base = gen.terrain.biome(k, k.h)
        let biome = dith.isDry == base.isDry ? dith : base
        let glade = gen.flora.noise2(Float(tx) / 70 + 300, Float(tz) / 70)
        let r2 = roll / max(0.3, 0.8 + 0.9 * glade)
        let pick = hashf(tx, 1, tz, gen.s32 ^ 0x7EE6)
        let gy = YOFF + Int(k.h)
        guard let kind = TreePlacer.choose(biome, r2, pick, gy), let sh = shape(kind) else { return nil }
        guard gy >= SEA, Int(k.h) >= Int(floorf(k.wl)), !(k.vol > 0.2 && k.lava > k.h) else { return nil }
        func rgb(_ v: UInt32) -> V3 { V3(Float((v >> 16) & 255), Float((v >> 8) & 255), Float(v & 255)) / 255 }
        // Leaf art is darker than its tint (FarRing.canopy); each tree a little lighter or darker than the next.
        let vary: Float = 0.9 + 0.2 * Float((hv >> 24) & 0xFF) / 255
        let leaf = rgb(sh.leaf != 0 ? sh.leaf : biome.info.foliage) * ((sh.cone ? 0.5 : 0.6) * vary)
        var top = leaf * 1.12
        let t = gen.terrain.temperature(k, k.h + 1)
        let cold = k.lava <= 0 && k.flow <= 0.3 && k.vol <= 0.3 && (t < -0.25 || (biome.snows(at: gy + 1) && t < -0.15))
        if cold { top = simd_mix(leaf, FarRing.snow, V3(repeating: 0.85)) }
        let pale = kind == .birch || kind == .tallBirch || kind == .paleOak
        let bark: V3 = pale ? V3(0.74, 0.74, 0.7) * 0.8 : V3(0.36, 0.27, 0.18) * 0.8
        let size: Float = 0.9 + 0.2 * Float((hv >> 12) & 0xFF) / 255
        return Tree(x: Int32(tx), z: Int32(tz), y: Float(YOFF) + floorf(k.h) + 1, h: sh.h * size, r: sh.r, base: sh.base,
                    cone: sh.cone, leaf: leaf, top: top, bark: bark, hv: hv, snowy: cold)
    }

    private func trees(_ gen: WorldGen, _ kx: Int, _ kz: Int) -> [Tree] {
        let key = (Int64(kx) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: kz)))
        if let t = cells[key] { return t }
        if cells.count > 400 { cells.removeAll(keepingCapacity: true) }
        var out: [Tree] = []
        let c = FarForest.cell
        // (Lattice cell g holds the trees of blocks 3g ... 3g + 2.)
        for gz in floorDiv(kz * c + 2, 3)...floorDiv(kz * c + c - 1, 3) {
            for gx in floorDiv(kx * c + 2, 3)...floorDiv(kx * c + c - 1, 3) {
                if let t = FarForest.site(gen, gx, gz) { out.append(t) }
            }
        }
        cells[key] = out
        return out
    }

    // The stand-ins between `from` and `reach` blocks of the centre, as quads relative to it. All of them to 140 blocks
    // past the loaded edge, then fewer and wider: one in four from 260 blocks past it on. Trunks and snow caps only in
    // the first 80 blocks. A wood too thick for `maxQuads` thins further past the full band (never cut off part way).
    func emit(_ gen: WorldGen, cx: Int, cz: Int, rin: Float, from: Float, into out: inout [SimpleVert]) {
        let c = FarForest.cell
        let R = Int(FarForest.reach)
        let up: Float = 512 + 512 * 1024
        func nq(_ nx: Float, _ nz: Float) -> Float { ((nx * 0.5 + 0.5) * 1023).rounded() + ((nz * 0.5 + 0.5) * 1023).rounded() * 1024 }
        let dirs: [(Float, Float)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let full: Float = rin + 140, thin: Float = rin + 260, fine: Float = rin + 80
        func keepAt(_ d: Float) -> Float { 1 - 0.75 * min(1, max(0, (d - full) / (thin - full))) }
        func cost(_ t: Tree, _ d: Float) -> Int { (t.cone ? (d < fine && t.snowy ? 8 : 4) : 5) + (d < fine ? 2 : 0) }
        let clear = FarTrack.clear(gen, cx: cx, cz: cz)
        var lists: [[Tree]] = []
        var nearCost = 0, farCost = 0
        for kz in floorDiv(cz - R, c)...floorDiv(cz + R, c) {
            for kx in floorDiv(cx - R, c)...floorDiv(cx + R, c) {
                var l = trees(gen, kx, kz)
                if !clear.isEmpty { l.removeAll { clear.contains(FarTrack.key(Int($0.x) >> 2, Int($0.z) >> 2)) } }
                for t in l {
                    let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
                    let d: Float = (x * x + z * z).squareRoot()
                    if d < from || d > FarForest.reach { continue }
                    let keep = keepAt(d)
                    if Float((t.hv >> 20) & 0xFF) / 256 >= keep { continue }
                    if d < full { nearCost += cost(t, d) } else { farCost += cost(t, d) }
                }
                lists.append(l)
            }
        }
        let room = Float(max(0, FarForest.maxQuads - nearCost))
        let squeeze: Float = farCost > 0 ? min(1, max(0.15, room / Float(farCost))) : 1
        lastSqueeze = squeeze
        var quads = 0
        out.reserveCapacity(out.count + 4 * min(FarForest.maxQuads + 4096, nearCost + farCost))
        for l in lists {
            for t in l {
                let x = Float(Int(t.x) - cx) + 0.5, z = Float(Int(t.z) - cz) + 0.5
                let d: Float = (x * x + z * z).squareRoot()
                if d < from || d > FarForest.reach { continue }
                let keep: Float = keepAt(d) * (d < full ? 1 : squeeze)
                if Float((t.hv >> 20) & 0xFF) / 256 >= keep { continue }
                if quads >= FarForest.maxQuads + 4096 { return }
                let wide: Float = min(2.4, 1 / keep.squareRoot())
                let near = d < fine
                let r = t.r * wide
                // (Past the trunks the crown comes most of the way down.)
                let y0: Float = t.y + t.h * (near ? t.base : t.base * 0.4), y1: Float = t.y + t.h
                let lo = V4(t.leaf * 0.7, 0), hi = V4(t.leaf, 0), cap = V4(t.top, 0)
                // A snowy conifer near the loaded edge is two tiers: green boughs, then a white cap.
                let capped = t.cone && near && t.snowy
                let ym: Float = y0 + (y1 - y0) * 0.6
                let rt: Float = t.cone ? (capped ? r * 0.4 : 0) : r * 0.62
                let tc = !t.cone || capped ? hi : (t.snowy ? V4(simd_mix(t.leaf, t.top, V3(repeating: 0.5)), 0) : cap)
                let ys: Float = capped ? ym : y1
                for (dx, dz) in dirs {
                    // The side facing (dx, dz): from corner a to corner b along it, up to the top's edge (a point on
                    // a cone).
                    let px = -dz, pz = dx
                    let ax = x + dx * r - px * r, az = z + dz * r - pz * r
                    let bx = x + dx * r + px * r, bz = z + dz * r + pz * r
                    let tax = x + dx * rt - px * rt, taz = z + dz * rt - pz * rt
                    let tbx = x + dx * rt + px * rt, tbz = z + dz * rt + pz * rt
                    let q = nq(dx * 0.75, dz * 0.75)
                    out.append(SimpleVert(pos: V4(ax, y0, az, q), color: lo)); out.append(SimpleVert(pos: V4(bx, y0, bz, q), color: lo))
                    out.append(SimpleVert(pos: V4(tbx, ys, tbz, q), color: tc)); out.append(SimpleVert(pos: V4(tax, ys, taz, q), color: tc))
                    if capped {
                        out.append(SimpleVert(pos: V4(tax, ym, taz, q), color: cap)); out.append(SimpleVert(pos: V4(tbx, ym, tbz, q), color: cap))
                        out.append(SimpleVert(pos: V4(x, y1, z, q), color: cap)); out.append(SimpleVert(pos: V4(x, y1, z, q), color: cap))
                    }
                }
                quads += capped ? 8 : 4
                if !t.cone {
                    out.append(SimpleVert(pos: V4(x - rt, y1, z - rt, up), color: cap)); out.append(SimpleVert(pos: V4(x + rt, y1, z - rt, up), color: cap))
                    out.append(SimpleVert(pos: V4(x + rt, y1, z + rt, up), color: cap)); out.append(SimpleVert(pos: V4(x - rt, y1, z + rt, up), color: cap))
                    quads += 1
                }
                if near {
                    let w: Float = t.h > 15 ? 0.9 : 0.45
                    let bc = V4(t.bark, 0)
                    let yb: Float = t.y - 3
                    let qx = nq(0.6, 0), qz = nq(0, 0.6)
                    out.append(SimpleVert(pos: V4(x - w, yb, z, qz), color: bc)); out.append(SimpleVert(pos: V4(x + w, yb, z, qz), color: bc))
                    out.append(SimpleVert(pos: V4(x + w, y0, z, qz), color: bc)); out.append(SimpleVert(pos: V4(x - w, y0, z, qz), color: bc))
                    out.append(SimpleVert(pos: V4(x, yb, z - w, qx), color: bc)); out.append(SimpleVert(pos: V4(x, yb, z + w, qx), color: bc))
                    out.append(SimpleVert(pos: V4(x, y0, z + w, qx), color: bc)); out.append(SimpleVert(pos: V4(x, y0, z - w, qx), color: bc))
                    quads += 2
                }
            }
        }
        lastQuads = quads
    }
    private(set) var lastQuads = 0
    var lastTrack = 0                              // (FarTrack's quads in the same build)
    private(set) var lastSqueeze: Float = 1
}
