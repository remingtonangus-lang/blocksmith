import Foundation
import simd

// Ledger 211 (Fable's D, Nov 16: "each of the six gets the ground kind its name asks for"): with the six together round
// one middle (ledger 202, in front of him where he starts) only the forest and the shore were on their own kind of
// ground; the rest stood on plain grass. Two parts:
// (a) the search takes the nearest middle where the kinds no build can make for itself (the boathouse's water, the
//     watchtower's hilltop, the cottage's slope) are the land's own, before any other;
// (b) a build whose ground is not its own kind once the six are placed has its site dressed as that kind: the stilt
//     cabin gets trees round it (grown as saplings grow), the gate's ground turns to rock, the lighthouse's to sand
//     (and its spot is the plain one nearest the boathouse's water), the watchtower gets a mound and the cottage a rise.
//     In a field world the field itself is shaped and repainted (World.raiseColumn, paintColumn), never built cubes.
// BS_OLDBUILDGROUND=1: neither (the search as ledger 202 left it, no dressing).
extension BuildersGrounds {
    static let oldGround = Env.all["BS_OLDBUILDGROUND"] == "1"
    static let dressable: Set<String> = ["forest", "rocky", "beach"]
    static let rockKeys: Set<String> = ["stone", "andesite", "granite", "diorite", "cobblestone", "gravel", "tuff", "deepslate",
                                        "calcite", "mossy_cobblestone", "cobbled_deepslate", "basalt", "smooth_basalt", "dripstone_block"]
    static let sandKeys: Set<String> = ["sand", "red_sand", "sandstone", "gravel"]

    // The ground under a placed build's footprint and round it (3 out): what it is, read from the world.
    struct GroundRead { var biome: String; var spread: Int; var rock: Int; var sand: Int; var n: Int; var trunks: Int; var waterNear: Bool; var lower: Int }
    static func read(_ w: World, _ pl: Placement) -> GroundRead {
        var hs: [Int] = [], rock = 0, sand = 0, n = 0
        for z in stride(from: pl.lo.z - 3, through: pl.hi.z + 3, by: 2) { for x in stride(from: pl.lo.x - 3, through: pl.hi.x + 3, by: 2) {
            let y = groundY(w, x, z)
            if Blocks.isLiquid(w.block(x, y + 1, z)) { continue }
            hs.append(y); n += 1
            let k = Blocks.key(Blocks.groupBase[Int(w.materialAt(x, y, z))])
            if rockKeys.contains(k) { rock += 1 }
            if sandKeys.contains(k) { sand += 1 }
        } }
        var trunks = 0
        for z in (pl.lo.z - 8)...(pl.hi.z + 8) { for x in (pl.lo.x - 8)...(pl.hi.x + 8) where x < pl.lo.x || x > pl.hi.x || z < pl.lo.z || z > pl.hi.z {
            let g = groundY(w, x, z)
            if ShapeClass.kind[Int(w.block(x, g + 1, z))] == .trunk && w.topY(x, z) > g + 4 { trunks += 1 }
        } }
        var wet = false
        for z in stride(from: pl.lo.z - 24, through: pl.hi.z + 24, by: 2) where !wet { for x in stride(from: pl.lo.x - 24, through: pl.hi.x + 24, by: 2) where water(w, x, z) { wet = true; break } }
        let mx = (pl.lo.x + pl.hi.x) / 2, mz = (pl.lo.z + pl.hi.z) / 2
        let lo = hs.min() ?? 0
        var lower = 0
        for (ox, oz) in [(-20, 0), (20, 0), (0, -20), (0, 20), (-15, -15), (15, 15), (-15, 15), (15, -15)] where groundY(w, mx + ox, mz + oz) <= lo - 3 { lower += 1 }
        let biome = "\(w.gen.column(mx, mz).biome)"
        return GroundRead(biome: biome, spread: (hs.max() ?? 0) - lo, rock: rock, sand: sand, n: max(1, n), trunks: trunks, waterNear: wet, lower: lower)
    }
    // Whether a placed build stands on the kind of ground its name asks for.
    static func own(_ w: World, _ pl: Placement) -> (Bool, GroundRead) {
        let r = read(w, pl)
        let ok: Bool
        switch pl.bp.ground {
        case "shore": ok = reads(w, pl.origin.x, pl.origin.z, "shore") || dockWater(w, pl)
        case "beach": ok = r.sand * 2 >= r.n && r.waterNear
        case "rocky": ok = r.rock * 2 >= r.n
        case "forest": ok = r.trunks >= 4
        case "hilltop": ok = r.lower >= 5
        case "slope": ok = r.spread >= 3 && r.spread <= 9
        default: ok = true
        }
        return (ok, r)
    }
    // (the boathouse placed: water under the south half of its box)
    static func dockWater(_ w: World, _ pl: Placement) -> Bool {
        var under = 0, n = 0
        for z in stride(from: (pl.lo.z + pl.hi.z) / 2 + 1, through: pl.hi.z, by: 1) { for x in stride(from: pl.lo.x, through: pl.hi.x, by: 2) { n += 1; if water(w, x, z) { under += 1 } } }
        return n > 0 && under * 2 >= n
    }
    static func line(_ pl: Placement, _ ok: Bool, _ r: GroundRead) -> String {
        "\(pl.bp.key) (\(pl.bp.ground)): \(r.biome), height spread \(r.spread), \(r.rock)/\(r.n) rock, \(r.sand)/\(r.n) sand, \(r.trunks) trunks round it, water near \(r.waterNear ? "yes" : "no"), \(r.lower) of 8 lower round it: \(ok ? "its own" : "NOT its own")"
    }
}

extension World {
    // Ledger 211 (b), field worlds: the ground is the field (World.groundAt), so a dressing writes the field, never a
    // built cube. One column's ground raised so its top cell is `top` (a flat face there): new ground `fill` with
    // `cap` on top, the old top it buries turned to `fill`; a built block or water in the way is never swallowed.
    // Returns the chunk touched and the rows changed, nil when nothing changed.
    func raiseColumn(_ x: Int, _ z: Int, to top: Int, fill: BlockID, cap: BlockID) -> (Chunk, Int, Int)? {
        guard fieldTerrain, top > 2, top < CH - 4, let c0 = chunkAt(x, z), c0.blocks.isField else { return nil }
        let c = editing(c0)
        let lx = mod(x, CS), lz = mod(z, CS)
        let mf = FieldMat.index[Int(fill)], mc = FieldMat.index[Int(cap)]
        guard mf != 0 && mc != 0 else { return nil }
        var old = min(CH - 1, top + 3)
        while old > 1 && !c.blocks.ground(Chunk.index(lx, old, lz)) { old -= 1 }
        guard old < top, !Blocks.isLiquid(c.blocks.raw(Chunk.index(lx, old + 1, lz))) else { return nil }
        var y0 = Int.max, y1 = Int.min
        for y in max(1, old - 1)...(top + 2) {
            let i = Chunk.index(lx, y, lz)
            let want = FieldTerrain.q(Float(top - y) + 0.5)
            let cur = c.blocks.density(i)
            if want <= cur {
                // (the old top, buried now: dirt under the new face)
                if cur > 0 && y < top && c.blocks.material(i) == mc { c.blocks.setDensity(i, cur, material: mf) } else { continue }
            } else {
                if cur <= 0 && want > 0 && c.blocks.raw(i) != AIR { continue }
                c.blocks.setDensity(i, want, material: want > 0 ? (y == top ? mc : mf) : nil)
            }
            y0 = min(y0, y); y1 = max(y1, y)
        }
        guard y0 <= y1 else { return nil }
        c.modified = true
        c.recomputeHeight(lx, lz)
        return (c, y0, y1)
    }
    // The material of the top `depth` ground cells of a column (the density kept). Returns the chunk and rows, or nil.
    func paintColumn(_ x: Int, _ z: Int, depth: Int, _ b: BlockID) -> (Chunk, Int, Int)? {
        guard fieldTerrain, let c0 = chunkAt(x, z), c0.blocks.isField else { return nil }
        let m = FieldMat.index[Int(b)]
        guard m != 0 else { return nil }
        let c = editing(c0)
        let lx = mod(x, CS), lz = mod(z, CS)
        var y = CH - 2
        while y > 1 && !c.blocks.ground(Chunk.index(lx, y, lz)) { y -= 1 }
        guard y > 1, !Blocks.isLiquid(c.blocks.raw(Chunk.index(lx, y + 1, lz))) else { return nil }
        for d in 0..<depth {
            let i = Chunk.index(lx, y - d, lz)
            guard c.blocks.ground(i) else { break }
            c.blocks.setDensity(i, c.blocks.density(i), material: m, follow: false)
        }
        c.modified = true
        return (c, y - depth + 1, y)
    }
    // The sections round changed rows meshed again (their own chunk's and the neighbours', a row either side).
    func remeshRows(_ touched: [(Chunk, Int, Int)]) {
        var seen = Set<Int64>()
        for (c, y0, y1) in touched {
            for dz in -1...1 { for dx in -1...1 {
                guard let n = chunks[ChunkKey(x: c.cx + dx, z: c.cz + dz)] else { continue }
                for s in max(0, (y0 - 1) >> 4)...min(NSEC - 1, (y1 + 1) >> 4) {
                    let k = Int64(n.cx) << 40 ^ Int64(n.cz) << 12 ^ Int64(s)
                    if seen.insert(k).inserted { n.sections[s].version += 1 }
                }
            } }
        }
        fieldStamp &+= 1
    }
}

extension Game {
    // (b): a build not on its own kind of ground once the six are placed has its site made so. The hilltop's and the
    // slope's ground is shaped first (a mound under the watchtower, a rise across the cottage's site), then every build
    // placed again on the ground as it now is; then the gate's ground turns to rock, the lighthouse's to sand, and the
    // stilt cabin gets trees round it. Returns what was done, one entry a build; `plans` comes back placed again.
    @discardableResult
    func dressBuildSites(_ plans: inout [BuildersGrounds.Placement], start: V3?) -> [String] {
        guard !BuildersGrounds.oldGround else { return [] }
        let w = world
        var done: [String] = []
        var touched: [(Chunk, Int, Int)] = []
        // The columns he starts on are left as they are (he would start inside the mound).
        func nearStart(_ x: Int, _ z: Int) -> Bool { start.map { simd_length(V2(Float(x) + 0.5 - $0.x, Float(z) + 0.5 - $0.z)) < 5 } ?? false }
        var shaped = false
        for pl in plans where (pl.bp.ground == "hilltop" || pl.bp.ground == "slope") && !BuildersGrounds.own(w, pl).0 {
            // The core: the build's box 3 out, raised to a face (flat on the hilltop, rising 5 away from him on the
            // slope); round it a skirt falling 2 in 3 to the ground as it was.
            let lo = IVec3(pl.lo.x - 3, 0, pl.lo.z - 3), hi = IVec3(pl.hi.x + 3, 0, pl.hi.z + 3)
            var base = Int.min
            for z in stride(from: lo.z, through: hi.z, by: 1) { for x in stride(from: lo.x, through: hi.x, by: 1) { base = max(base, BuildersGrounds.groundY(w, x, z)) } }
            let mx = (lo.x + hi.x) / 2, mz = (lo.z + hi.z) / 2
            var core: (Int, Int) -> Int
            if pl.bp.ground == "hilltop" {
                // (high enough that the ground 15 to 20 out round it is 4 or more below it)
                var ring = base
                for (ox, oz) in [(-20, 0), (20, 0), (0, -20), (0, 20), (-15, -15), (15, 15), (-15, 15), (15, -15)] { ring = max(ring, BuildersGrounds.groundY(w, mx + ox, mz + oz)) }
                let top = max(base + 2, ring + 4)
                core = { _, _ in top }
            } else {
                // (rising away from where he starts, along the axis that faces him most)
                let toHim = start.map { V2($0.x - Float(mx), $0.z - Float(mz)) } ?? V2(0, 1)
                let alongX = abs(toHim.x) > abs(toHim.y)
                let sign: Float = alongX ? (toHim.x > 0 ? -1 : 1) : (toHim.y > 0 ? -1 : 1)
                let span = Float(alongX ? hi.x - lo.x : hi.z - lo.z)
                core = { x, z in
                    let t = Float(alongX ? x - lo.x : z - lo.z) / max(1, span)
                    return base + Int((sign > 0 ? t : 1 - t) * 5 + 0.5)
                }
            }
            let skirt = 12
            var n = 0
            for z in (lo.z - skirt)...(hi.z + skirt) { for x in (lo.x - skirt)...(hi.x + skirt) where !nearStart(x, z) {
                let cx = min(max(x, lo.x), hi.x), cz = min(max(z, lo.z), hi.z)
                let d = simd_length(V2(Float(x - cx), Float(z - cz)))
                let t = core(cx, cz) - Int(d * 2 / 3)
                guard t > BuildersGrounds.groundY(w, x, z), !BuildersGrounds.water(w, x, z) else { continue }
                if let r = w.raiseColumn(x, z, to: t, fill: DIRT, cap: GRASS) { touched.append(r); n += 1 }
            } }
            shaped = true
            done.append("\(pl.bp.key): \(n) columns raised (\(pl.bp.ground == "hilltop" ? "a mound" : "a rise of 5"))")
        }
        if shaped {
            w.remeshRows(touched); touched = []
            plans = plans.map { BuildersGrounds.place($0.bp, on: w, at: IVec3($0.origin.x, 0, $0.origin.z)) }
        }
        for pl in plans where BuildersGrounds.dressable.contains(pl.bp.ground) && !BuildersGrounds.own(w, pl).0 {
            switch pl.bp.ground {
            case "rocky", "beach":
                let keys = pl.bp.ground == "rocky" ? ["stone", "andesite", "stone", "cobblestone", "gravel", "stone"] : ["sand"]
                var n = 0
                for z in (pl.lo.z - 4)...(pl.hi.z + 4) { for x in (pl.lo.x - 4)...(pl.hi.x + 4) {
                    let k = keys[Int(hash3(x, 211, z, 0xB0D) % UInt32(keys.count))]
                    if w.fieldTerrain {
                        if let r = w.paintColumn(x, z, depth: 3, Blocks.id(k)) { touched.append(r); n += 1 }
                        continue
                    }
                    let y = BuildersGrounds.groundY(w, x, z)
                    if Blocks.isLiquid(w.block(x, y + 1, z)) { continue }
                    for d in 0..<3 where SmoothTerrain.natural[Int(w.block(x, y - d, z))] { _ = w.setBlockAsync(x, y - d, z, Blocks.id(k)) }
                    n += 1
                } }
                done.append("\(pl.bp.key): \(n) columns of \(pl.bp.ground == "rocky" ? "rock" : "sand")")
            case "forest":
                // Trees round it, 5 to 8 out from its box, none on the side he looks from.
                let c = V2(Float(pl.lo.x + pl.hi.x) / 2, Float(pl.lo.z + pl.hi.z) / 2)
                let toHim = start.map { simd_normalize(V2($0.x, $0.z) - c) }
                var grown = 0
                for k in 0..<16 where grown < 7 {
                    let a = Float(k) * .pi / 8
                    let d = V2(sinf(a), cosf(a))
                    if let t = toHim, simd_dot(d, t) > 0.5 { continue }
                    let rx = Float(pl.hi.x - pl.lo.x) / 2 + Float(5 + k % 3), rz = Float(pl.hi.z - pl.lo.z) / 2 + Float(5 + k % 3)
                    let x = Int(floorf(c.x + d.x * rx)), z = Int(floorf(c.y + d.y * rz))
                    let y = BuildersGrounds.groundY(w, x, z)
                    if Blocks.isLiquid(w.block(x, y + 1, z)) || w.block(x, y + 1, z) != AIR { continue }
                    w.setBlock(x, y + 1, z, Blocks.id("oak_sapling"))
                    growTree(IVec3(x, y + 1, z), "oak_sapling")
                    if ShapeClass.kind[Int(w.block(x, y + 1, z))] == .trunk { grown += 1 }
                }
                done.append("\(pl.bp.key): \(grown) trees")
            default: break
            }
        }
        if !touched.isEmpty { w.remeshRows(touched) }
        return done
    }
}
