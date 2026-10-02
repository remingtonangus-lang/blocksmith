import Foundation
import Metal
import simd

// World-gen sanity (--gencheck [--seeds a,b] [--areas N] [--out FILE] [--strict]): generates real chunks
// (terrain + features + structures) in N 6x6-chunk areas per seed and scans the inner 4x4 chunks for classes of
// generation bugs:
//   floating_block    a full solid block (not leaves) with nothing solid on any side
//   unsupported       sand / gravel / other falling blocks over air (they drop the moment anything updates)
//   plant_soil        a plant on a block it can't grow on (flowers on stone, cacti off sand, crops off farmland...)
//   plant_floating    a plant with air under it
//   leak              a water or lava source next to air at its own level with no wall (spills when touched)
//   trunk_floating    a log with air directly under it and no log/leaves/ground below within 2 (cut trees)
//   ore_in_air        an ore block with air on five or more sides
//   leaves_orphan     leaves with no log within 6 blocks (they decay in play)
// Prints counts per class and writes examples with positions (snapshot command included) to the report.
enum GenCheck {
    struct Hit { let cls: String; let seed: UInt64; let p: IVec3; let detail: String }

    static let hanging: Set<String> = ["vine", "cave_vines", "cave_vines_plant", "weeping_vines", "weeping_vines_plant", "twisting_vines",
                                       "twisting_vines_plant", "hanging_roots", "spore_blossom", "glow_lichen", "sculk_vein", "pale_hanging_moss",
                                       "pointed_dripstone", "chorus_flower", "chorus_plant", "resin_clump", "cobweb", "lily_pad", "kelp", "seagrass",
                                       "tall_seagrass", "sea_pickle", "nether_portal", "end_portal", "light"]
    static let dirtLike: Set<String> = ["grass_block", "dirt", "coarse_dirt", "podzol", "rooted_dirt", "moss_block", "mud", "muddy_mangrove_roots",
                                        "farmland", "farmland_moist", "snowy_grass_block", "pale_moss_block", "mycelium", "dirt_path"]

    // Which soils a plant accepts (nil = any solid top).
    static func soils(_ plant: String) -> Set<String>? {
        if plant == "cactus" { return ["sand", "red_sand", "cactus", "suspicious_sand"] }
        if plant == "dead_bush" || plant.hasSuffix("dry_grass") || plant == "cactus_flower" {
            return dirtLike.union(["sand", "red_sand", "terracotta", "cactus"]).union(Set(BlockRegistry.colors.map { "\($0.0)_terracotta" }))
        }
        if plant == "sugar_cane" { return dirtLike.union(["sand", "red_sand", "sugar_cane"]) }
        if ["wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "torchflower_crop", "pitcher_crop"].contains(plant) {
            return ["farmland", "farmland_moist"]
        }
        if plant.hasPrefix("crimson_") || plant.hasPrefix("warped_") || plant == "nether_sprouts" {
            return ["crimson_nylium", "warped_nylium", "soul_soil", "netherrack", "soul_sand", "warped_wart_block", "nether_wart_block"]
        }
        if plant == "nether_wart" { return ["soul_sand"] }
        if plant.hasSuffix("_mushroom") || plant.hasSuffix("_fungus") { return nil }
        if plant == "bamboo" || plant == "bamboo_sapling" { return dirtLike.union(["sand", "red_sand", "gravel", "bamboo", "bamboo_sapling"]) }
        if plant == "sweet_berry_bush" || plant.hasSuffix("_sapling") || plant.hasSuffix("_tulip") || plant.hasSuffix("grass") || plant.hasSuffix("fern")
            || ["dandelion", "poppy", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "blue_orchid", "sunflower",
                "lilac", "rose_bush", "peony", "pink_petals", "wildflowers", "bush", "firefly_bush", "leaf_litter", "torchflower", "azalea",
                "flowering_azalea", "open_eyeblossom", "closed_eyeblossom", "wither_rose"].contains(plant) {
            return dirtLike
        }
        return nil
    }

    static func run(device: MTLDevice) -> Int32 {
        let seeds: [UInt64] = (arg("--seeds") ?? "12345,777,424242").split(separator: ",").compactMap { UInt64($0) }
        let areas = Int(arg("--areas") ?? "") ?? 6
        let t0 = CFAbsoluteTimeGetCurrent()
        var hits: [Hit] = []
        var counts: [String: Int] = [:]
        var scanned = 0
        let logIDs: Set<BlockID> = {
            var s = Set<BlockID>()
            for i in 0..<Blocks.count {
                let k = Blocks.key(Blocks.groupBase[i])
                if k.hasSuffix("_log") || k.hasSuffix("_stem") || k.hasSuffix("_wood") || k.hasSuffix("_hyphae") || k == "mangrove_roots" { s.insert(BlockID(i)) }
            }
            return s
        }()
        func isLeaves(_ b: BlockID) -> Bool { Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("_leaves") }
        for seed in seeds {
            let world = World(seed: seed, device: device, save: nil)
            var rng = SRng(seed ^ 0x6E6C)
            for a in 0..<areas {
                // Areas spread out from the origin (2 near spawn, the rest up to ~3000 blocks away).
                let r: Float = a < 2 ? Float(a * 64) : Float(400 + rng.int(2600))
                let ang: Float = rng.float() * 2 * .pi
                let cx0 = floorDiv(Int(r * cosf(ang)), CS), cz0 = floorDiv(Int(r * sinf(ang)), CS)
                world.loadBlocks(cx0: cx0 - 1, cz0: cz0 - 1, cx1: cx0 + 4, cz1: cz0 + 4)
                func add(_ c: String, _ p: IVec3, _ d: String) {
                    counts[c, default: 0] += 1
                    if hits.filter({ $0.cls == c }).count < 8 { hits.append(Hit(cls: c, seed: seed, p: p, detail: d)) }
                }
                for cz in cz0...(cz0 + 3) { for cx in cx0...(cx0 + 3) {
                    scanned += 1
                    for z in 0..<CS { for x in 0..<CS {
                        let wx = cx * CS + x, wz = cz * CS + z
                        let top = min(CH - 2, world.topY(wx, wz) + 1)
                        var y = 2
                        while y <= top {
                            let b = world.block(wx, y, wz)
                            if b == AIR { y += 1; continue }
                            let bi = Int(b)
                            let k = Blocks.key(Blocks.groupBase[bi])
                            let below = world.block(wx, y - 1, wz)
                            let bk = Blocks.key(Blocks.groupBase[Int(below)])
                            let p = IVec3(wx, y, wz)
                            if Blocks.render[bi] == RenderType.cross.rawValue && !hanging.contains(k) && Blocks.fluidKind[bi] == 0 {
                                if below == AIR { add("plant_floating", p, "\(k) over air") }
                                else if let ok = soils(k), !ok.contains(bk), bk != k, !(Blocks.key(below).contains(k)) {
                                    add("plant_soil", p, "\(k) on \(bk)")
                                }
                            } else if World.fallingIDs[bi] && (below == AIR || (Blocks.fluidKind[Int(below)] == 0 && !Blocks.collide[Int(below)] && Blocks.replaceable[Int(below)])) {
                                add("unsupported", p, "\(k) over \(bk)")
                            } else if Blocks.fluidKind[bi] != 0 && Blocks.fluidLevel[bi] == 0 {
                                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where world.block(wx + dx, y, wz + dz) == AIR {
                                    add("leak", p, "\(Blocks.fluidKind[bi] == 1 ? "water" : "lava") source beside air"); break
                                }
                            } else if logIDs.contains(b) && below == AIR {
                                let b2 = world.block(wx, y - 2, wz)
                                if b2 == AIR && !isLeaves(world.block(wx, y + 1, wz)) { add("trunk_floating", p, "\(k) over open air") }
                            } else if Blocks.fullCollide[bi] && !isLeaves(b) {
                                var solidN = 0, airN = 0
                                for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                                    let n = world.block(wx + dx, y + dy, wz + dz)
                                    if Blocks.collide[Int(n)] || Blocks.fluidKind[Int(n)] != 0 { solidN += 1 }
                                    if n == AIR { airN += 1 }
                                }
                                if solidN == 0 { add(k.hasSuffix("_ore") ? "ore_in_air" : "floating_block", p, "\(k) with nothing solid around it") }
                                else if k.hasSuffix("_ore") && airN >= 5 { add("ore_in_air", p, "\(k) with \(airN) open sides") }
                            } else if isLeaves(b) && hash3(wx, y, wz, 0x1EAF) % 9 == 0 {
                                // Sampled: leaves with no log within 6 (they would decay).
                                var found = false
                                search: for dy in -6...6 { for dz in -6...6 { for dx in -6...6 where abs(dx) + abs(dy) + abs(dz) <= 6 {
                                    if logIDs.contains(world.block(wx + dx, y + dy, wz + dz)) { found = true; break search }
                                } } }
                                if !found { add("leaves_orphan", p, "\(k) with no log within 6") }
                            }
                            y += 1
                        }
                    } }
                } }
                world.unloadAll()
                world.blockEntities.removeAll()
                world.pendingMobs.removeAll()
            }
        }
        var md = ["# World-gen check", ""]
        let cs = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let summary = String(format: "gencheck: %ld chunks over %ld seeds: %@ (%.1f s)", scanned, seeds.count, cs.isEmpty ? "no issues" : cs, CFAbsoluteTimeGetCurrent() - t0)
        md.append(summary); md.append("")
        for h in hits {
            let y = h.p.y - YOFF
            let snap: String = "`--snapshot snaps/g.png --seed \(h.seed) --x \(h.p.x) --z \(h.p.z) --up 2 --pitch -40`"
            let head: String = "- **\(h.cls)** seed \(h.seed) at \(h.p.x) \(y) \(h.p.z): "
            md.append(head + h.detail + "  " + snap)
        }
        try? (md.joined(separator: "\n") + "\n").write(toFile: arg("--out") ?? "snaps/gencheck.md", atomically: true, encoding: .utf8)
        print(summary)
        return CommandLine.arguments.contains("--strict") && !counts.isEmpty ? 2 : 0
    }
}
