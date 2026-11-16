import Foundation
import simd

// Ledger 211 (Fable's D, Nov 16: "each of the six gets the ground kind its name asks for"): with the six together round
// one middle (ledger 202, in front of him where he starts) only the forest and the shore were on their own kind of
// ground; the rest stood on plain grass. Two parts:
// (a) the search takes the nearest middle where the kinds no build can make for itself (the boathouse's water, the
//     watchtower's hilltop, the cottage's slope) are the land's own, before any other;
// (b) a build whose ground is not its own kind once the six are placed has its site dressed as that kind: the stilt
//     cabin gets trees round it (grown as saplings grow), the gate's ground turns to stone, the lighthouse's to sand.
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
        for z in stride(from: pl.lo.z - 20, through: pl.hi.z + 20, by: 2) where !wet { for x in stride(from: pl.lo.x - 20, through: pl.hi.x + 20, by: 2) where water(w, x, z) { wet = true; break } }
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

extension Game {
    // (b): a dressable build not on its own ground has its site made so. Returns what was done, one entry a build.
    @discardableResult
    func dressBuildSites(_ plans: [BuildersGrounds.Placement], start: V3?) -> [String] {
        guard !BuildersGrounds.oldGround else { return [] }
        let w = world
        var done: [String] = []
        for pl in plans where BuildersGrounds.dressable.contains(pl.bp.ground) && !BuildersGrounds.own(w, pl).0 {
            switch pl.bp.ground {
            case "rocky", "beach":
                let keys = pl.bp.ground == "rocky" ? ["stone", "andesite", "stone", "cobblestone", "gravel", "stone"] : ["sand"]
                var n = 0
                for z in (pl.lo.z - 4)...(pl.hi.z + 4) { for x in (pl.lo.x - 4)...(pl.hi.x + 4) {
                    let y = BuildersGrounds.groundY(w, x, z)
                    if Blocks.isLiquid(w.block(x, y + 1, z)) { continue }
                    let k = keys[Int(hash3(x, 211, z, 0xB0D) % UInt32(keys.count))]
                    for d in 0..<3 where SmoothTerrain.natural[Int(w.block(x, y - d, z))] { _ = w.setBlockAsync(x, y - d, z, Blocks.id(k)); n += 1 }
                } }
                done.append("\(pl.bp.key): \(n) cells of \(pl.bp.ground == "rocky" ? "stone" : "sand")")
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
        return done
    }
}
