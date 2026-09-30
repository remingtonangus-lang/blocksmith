import Foundation

// Overworld structures on region grids with the reference game's spacing/separation:
// villages 34/8, temples 32/8 (desert pyramid, jungle temple, swamp hut or igloo by biome),
// pillager outposts 32/8 (20%, away from villages), ruined portals 40/15, shipwrecks 24/4,
// buried treasure (1 in 100 beach chunks), mineshafts (~0.4% of chunks), desert wells.
enum OverworldStructures {
    static func types(_ gen: WorldGen) -> [StructureType] {
        [Village.type(gen), temple(gen), outpost(gen), ruinedPortal(gen), shipwreck(gen), buriedTreasure(gen), mineshaft(gen), desertWell(gen)]
    }

    static func piece(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ f: @escaping (inout StructWriter) -> Void) -> Piece {
        Piece(min: IVec3(x0, y0, z0), max: IVec3(x1, y1, z1), build: f)
    }

    // MARK: Temples

    static func temple(_ gen: WorldGen) -> StructureType {
        StructureType(name: "temple", spacing: 32, separation: 8, salt: 14357617, reach: 2) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let biome = gen.column(x, z).biome
            let y = gen.groundY(x, z)
            guard y >= SEA - 1 else { return nil }
            var rng = SRng(seed)
            let s = rng.next()
            switch biome {
            case .desert:
                return StructureStart(kind: "desert_pyramid", pieces: [piece(x - 11, y - 16, z - 11, x + 11, y + 12, z + 11) { w in desertPyramid(&w, x, y, z, s) }],
                                      anchor: IVec3(x, y + 1, z - 14))
            case .jungle, .bambooJungle, .sparseJungle:
                return StructureStart(kind: "jungle_temple", pieces: [piece(x - 7, y - 6, z - 8, x + 7, y + 14, z + 8) { w in jungleTemple(&w, x, y, z, s) }],
                                      anchor: IVec3(x, y + 2, z - 12))
            case .swamp, .mangroveSwamp:
                return StructureStart(kind: "swamp_hut", pieces: [piece(x - 4, y - 8, z - 5, x + 4, y + 9, z + 5) { w in swampHut(&w, x, max(y, SEA) + 2, z, s) }],
                                      anchor: IVec3(x, max(y, SEA) + 3, z - 8))
            case .snowyPlains, .snowyTaiga, .snowySlopes:
                return StructureStart(kind: "igloo", pieces: [piece(x - 4, y - 14, z - 4, x + 4, y + 6, z + 4) { w in igloo(&w, x, y + 1, z, s) }],
                                      anchor: IVec3(x, y + 2, z - 7))
            default: return nil
            }
        }
    }

    static func desertPyramid(_ w: inout StructWriter, _ cx: Int, _ gy: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let ss = SANDSTONE, cut = Blocks.id("cut_sandstone"), chis = Blocks.id("chiseled_sandstone"), smooth = Blocks.id("smooth_sandstone")
        let orange = Blocks.id("orange_terracotta"), blue = Blocks.has("blue_terracotta") ? Blocks.id("blue_terracotta") : Blocks.id("light_gray_terracotta")
        let y = gy
        // Base and stepped pyramid (21x21).
        for z in (cz - 10)...(cz + 10) { for x in (cx - 10)...(cx + 10) { w.pillarDown(x, y - 1, z, ss, minY: y - 8) } }
        for k in 0...9 {
            w.fill(cx - 10 + k, y + k, cz - 10 + k, cx + 10 - k, y + k, cz + 10 - k, ss)
            if k < 9 { w.fill(cx - 9 + k, y + k, cz - 9 + k, cx + 9 - k, y + k, cz + 9 - k, k < 4 ? AIR : ss) }
        }
        w.fill(cx - 9, y, cz - 9, cx + 9, y, cz + 9, smooth)
        // Front towers.
        for sx in [-1, 1] {
            let tx = cx + sx * 8
            w.fill(tx - 2, y, cz - 10, tx + 2, y + 9, cz - 6, ss)
            w.fill(tx - 1, y + 1, cz - 9, tx + 1, y + 8, cz - 7, AIR)
            w.fill(tx - 2, y + 10, cz - 10, tx + 2, y + 10, cz - 6, cut)
            for k in 0..<3 { w.set(tx, y + 3 + k * 2, cz - 10, orange) }
        }
        // Entrance.
        w.fill(cx - 1, y + 1, cz - 10, cx + 1, y + 3, cz - 6, AIR)
        w.set(cx, y + 4, cz - 10, chis)
        // Floor pattern: blue centre with orange cross.
        w.set(cx, y, cz, blue)
        for d in 1...2 { for (dx, dz) in [(d, 0), (-d, 0), (0, d), (0, -d)] { w.set(cx + dx, y, cz + dz, orange) } }
        // Secret chamber under the pattern: 4 chests in wall niches, TNT trap under a pressure plate.
        let fy = y - 12
        w.fill(cx - 4, fy - 1, cz - 4, cx + 4, y - 1, cz + 4, ss)
        w.fill(cx - 3, fy, cz - 3, cx + 3, fy + 3, cz + 3, AIR)
        w.fill(cx, fy + 4, cz, cx, y - 1, cz, AIR)
        for (dx, dz, f) in [(0, -3, 1), (0, 3, 0), (-3, 0, 3), (3, 0, 2)] {
            w.chest(cx + dx, fy, cz + dz, loot: "desert_pyramid", seed: rng.next(), facing: f)
        }
        w.fill(cx - 1, fy - 2, cz - 1, cx + 1, fy - 2, cz + 1, TNT_ID)
        w.set(cx, fy, cz, Blocks.has("stone_pressure_plate") ? Blocks.id("stone_pressure_plate") : AIR)
    }

    static func jungleTemple(_ w: inout StructWriter, _ cx: Int, _ gy: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let cob = COBBLE, mossy = Blocks.id("mossy_cobblestone"), chis = Blocks.id("chiseled_stone_bricks")
        func mat(_ x: Int, _ y: Int, _ z: Int) -> BlockID { hashf(x, y, z, 0x7E3) < 0.45 ? mossy : cob }
        let y = gy
        for z in (cz - 7)...(cz + 7) { for x in (cx - 6)...(cx + 6) { w.pillarDown(x, y - 1, z, cob, minY: y - 6) } }
        // Three tiers, each smaller.
        for (tier, (rx, rz, h)) in [(6, 7, 4), (5, 6, 4), (3, 4, 4)].enumerated() {
            let by = y + tier * 4
            for yy in by...(by + h) { for z in (cz - rz)...(cz + rz) { for x in (cx - rx)...(cx + rx) {
                let edge = abs(x - cx) == rx || abs(z - cz) == rz || yy == by || yy == by + h
                w.set(x, yy, z, edge ? mat(x, yy, z) : AIR)
            } } }
        }
        w.fill(cx - 1, y + 1, cz - 7, cx + 1, y + 3, cz - 7, AIR)
        for x in stride(from: cx - 4, through: cx + 4, by: 2) { w.set(x, y + 3, cz - 7, chis) }
        // Stair down to the lower chamber with the chests.
        w.fill(cx - 5, y - 4, cz + 2, cx + 5, y - 1, cz + 6, cob)
        w.fill(cx - 4, y - 3, cz + 3, cx + 4, y - 2, cz + 5, AIR)
        w.fill(cx + 3, y - 3, cz - 1, cx + 3, y, cz + 2, AIR)
        w.chest(cx - 4, y - 3, cz + 4, loot: "jungle_temple", seed: rng.next(), facing: 3)
        w.chest(cx + 1, y + 5, cz + 5, loot: "jungle_temple", seed: rng.next(), facing: 0)
        w.set(cx - 3, y + 1, cz + 5, Blocks.id("vine"))
    }

    static func swampHut(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        let pl = Blocks.id("spruce_planks"), log = Blocks.id("oak_log"), st = Blocks.id("spruce_stairs")
        for (dx, dz) in [(-2, -2), (2, -2), (-2, 3), (2, 3)] { w.pillarDown(cx + dx, y - 1, cz + dz, log, minY: y - 10) }
        w.fill(cx - 3, y, cz - 3, cx + 3, y, cz + 4, pl)
        for yy in (y + 1)...(y + 3) { for z in (cz - 2)...(cz + 3) { for x in (cx - 2)...(cx + 2) {
            let edge = abs(x - cx) == 2 || z == cz - 2 || z == cz + 3
            w.set(x, yy, z, edge ? pl : AIR)
        } } }
        w.fill(cx - 1, y + 2, cz - 2, cx + 1, y + 2, cz - 2, Blocks.id("oak_fence"))
        w.fill(cx, y + 1, cz - 2, cx, y + 2, cz - 2, AIR)
        w.set(cx, y + 1, cz - 2, Blocks.id("spruce_door")); w.set(cx, y + 2, cz - 2, Blocks.id("spruce_door") + 8)
        for x in (cx - 3)...(cx + 3) { for z in (cz - 3)...(cz + 4) {
            let k = abs(x - cx)
            w.set(x, y + 4 + (3 - k) / 2, z, k == 0 ? pl : st + BlockID(x < cx ? 3 : 2))
        } }
        w.set(cx - 1, y + 1, cz + 2, Blocks.id("cauldron"))
        w.set(cx + 1, y + 1, cz + 2, Blocks.id("crafting_table"))
        w.set(cx + 1, y + 2, cz - 1, Blocks.id("flower_pot"))
        w.mob("witch", V3(Float(cx) + 0.5, Float(y + 1), Float(cz) + 0.5))
    }

    static func igloo(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let snow = SNOW, ice = Blocks.id("ice")
        for dy in 0...4 { for dz in -3...3 { for dx in -3...3 {
            let r = sqrtf(Float(dx * dx + dz * dz) + Float(dy * dy) * 1.4)
            if r > 3.6 { continue }
            w.set(cx + dx, y + dy, cz + dz, r > 2.6 ? snow : AIR)
        } } }
        w.fill(cx - 2, y - 1, cz - 2, cx + 2, y - 1, cz + 2, snow)
        w.set(cx - 3, y + 1, cz, ice); w.set(cx + 3, y + 1, cz, ice)
        w.fill(cx, y, cz - 4, cx, y + 1, cz - 3, AIR)
        w.fill(cx - 1, y, cz - 4, cx - 1, y + 2, cz - 4, snow); w.fill(cx + 1, y, cz - 4, cx + 1, y + 2, cz - 4, snow)
        w.set(cx, y + 2, cz - 4, snow)
        w.set(cx - 1, y, cz + 1, Blocks.id("white_bed") + 1); w.set(cx - 1, y, cz, Blocks.id("white_bed_head") + 1)
        w.set(cx + 1, y, cz + 1, Blocks.id("furnace"))
        w.set(cx + 2, y, cz, Blocks.id("crafting_table"))
        w.set(cx - 2, y + 1, cz - 1, TORCH)
        // Half of igloos hide a basement: a ladder shaft to a stone-brick lab with a chest.
        if rng.chance(0.5) {
            let by = y - 11
            w.set(cx, y - 1, cz - 2, Blocks.id("oak_trapdoor") + 8)
            for yy in (by + 1)...(y - 2) { w.set(cx, yy, cz - 2, Blocks.id("ladder") + 1) }
            w.fill(cx - 3, by - 1, cz - 3, cx + 3, by + 4, cz + 3, Blocks.id("stone_bricks"))
            w.fill(cx - 2, by, cz - 2, cx + 2, by + 3, cz + 2, AIR)
            w.set(cx, by + 3, cz - 2, Blocks.id("ladder") + 1)
            w.chest(cx + 2, by, cz + 2, loot: "igloo_chest", seed: rng.next(), facing: 0)
            w.set(cx - 2, by, cz + 2, Blocks.id("cauldron"))
            w.fill(cx - 2, by, cz - 1, cx - 2, by + 2, cz - 1, Blocks.id("iron_bars"))
            w.mob("villager", V3(Float(cx) - 1.5, Float(by), Float(cz) + 1.5))
        }
    }

    // MARK: Pillager outpost

    static func outpost(_ gen: WorldGen) -> StructureType {
        StructureType(name: "pillager_outpost", spacing: 32, separation: 8, salt: 165745296, reach: 2) { [unowned gen] seed, cx, cz in
            var rng = SRng(seed)
            guard rng.int(5) == 0 else { return nil }
            let x = cx * CS + 8, z = cz * CS + 8
            guard [.plains, .sunflowerPlains, .desert, .savanna, .taiga, .snowyPlains, .meadow, .grove, .snowySlopes, .jaggedPeaks, .frozenPeaks, .cherryGrove].contains(gen.column(x, z).biome) else { return nil }
            // Never within 10 chunks of a village.
            if let v = gen.structures?.nearest("village", x: x, z: z, maxRegions: 1), abs(v.anchor.x - x) < 160 && abs(v.anchor.z - z) < 160 { return nil }
            let y = gen.groundY(x, z)
            guard y >= SEA else { return nil }
            let s = rng.next()
            return StructureStart(kind: "pillager_outpost", pieces: [piece(x - 6, y - 8, z - 6, x + 6, y + 24, z + 6) { w in outpostTower(&w, x, y + 1, z, s) }],
                                  anchor: IVec3(x, y + 2, z - 12))
        }
    }

    static func outpostTower(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let log = Blocks.id("dark_oak_log"), pl = Blocks.id("dark_oak_planks"), cob = COBBLE, fence = Blocks.id("dark_oak_fence")
        for z in (cz - 4)...(cz + 4) { for x in (cx - 4)...(cx + 4) { w.pillarDown(x, y - 1, z, cob, minY: y - 8) } }
        w.fill(cx - 4, y - 1, cz - 4, cx + 4, y - 1, cz + 4, cob)
        for fl in 0..<4 {
            let by = y + fl * 5
            for yy in by...(by + 4) { for z in (cz - 3)...(cz + 3) { for x in (cx - 3)...(cx + 3) {
                let corner = abs(x - cx) == 3 && abs(z - cz) == 3
                let edge = abs(x - cx) == 3 || abs(z - cz) == 3
                if corner { w.set(x, yy, z, log) }
                else if yy == by { w.set(x, yy, z, pl) }
                else if edge { w.set(x, yy, z, yy == by + 2 && (x + z) % 2 == 0 ? fence : (fl == 3 ? AIR : pl)) }
                else { w.set(x, yy, z, AIR) }
            } } }
            for yy in by...(by + 4) { w.set(cx + 2, yy, cz + 2, Blocks.id("ladder") + 2) }
            w.set(cx + 2, by, cz + 2, Blocks.id("ladder") + 2)
            w.mob("pillager", V3(Float(cx) + 0.5, Float(by + 1), Float(cz) + 0.5))
        }
        let top = y + 20
        w.fill(cx - 4, top, cz - 4, cx + 4, top, cz + 4, pl)
        for x in (cx - 4)...(cx + 4) { w.set(x, top + 1, cz - 4, fence); w.set(x, top + 1, cz + 4, fence) }
        for z in (cz - 4)...(cz + 4) { w.set(cx - 4, top + 1, z, fence); w.set(cx + 4, top + 1, z, fence) }
        w.chest(cx - 2, top + 1, cz - 2, loot: "pillager_outpost", seed: rng.next(), facing: 1)
        w.mob("pillager", V3(Float(cx) + 0.5, Float(top + 1), Float(cz) + 0.5))
        w.mob("pillager", V3(Float(cx) + 2.5, Float(top + 1), Float(cz) - 1.5))
    }

    // MARK: Ruined portal

    static func ruinedPortal(_ gen: WorldGen) -> StructureType {
        StructureType(name: "ruined_portal", spacing: 40, separation: 15, salt: 34222645, reach: 1) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let y = gen.groundY(x, z)
            guard y > YOFF + 10 else { return nil }
            let s = seed
            let underwater = y < SEA
            return StructureStart(kind: "ruined_portal", pieces: [piece(x - 5, y - 3, z - 3, x + 5, y + 7, z + 3) { w in ruinedPortalBuild(&w, x, y, z, s, underwater) }],
                                  anchor: IVec3(x, y + 2, z - 8))
        }
    }

    static func ruinedPortalBuild(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64, _ wet: Bool) {
        var rng = SRng(seed)
        let obs = OBSIDIAN, cry = Blocks.id("crying_obsidian"), nr = Blocks.id("netherrack"), mag = Blocks.id("magma_block"), gold = Blocks.id("gold_block")
        // Nether-corrupted ground patch.
        for dz in -3...3 { for dx in -5...5 where hashf(cx + dx, 0, cz + dz, UInt32(truncatingIfNeeded: seed)) < 0.65 {
            w.set(cx + dx, y, cz + dz, rng.chance(0.15) ? mag : nr)
        } }
        // Broken 4x5 frame (interior 2x3), missing a few blocks.
        for i in -1...2 { for j in 0...4 {
            let edge = i == -1 || i == 2 || j == 0 || j == 4
            guard edge else { continue }
            if rng.chance(0.28) { continue }
            w.set(cx + i, y + 1 + j, cz, rng.chance(0.12) ? cry : obs)
        } }
        if rng.chance(0.3) { w.set(cx + 3, y + 1, cz + 1, gold) }
        w.chest(cx - 3, y + 1, cz + 1, loot: "ruined_portal", seed: rng.next(), facing: 1)
        _ = wet
    }

    // MARK: Shipwrecks, buried treasure

    static func shipwreck(_ gen: WorldGen) -> StructureType {
        StructureType(name: "shipwreck", spacing: 24, separation: 4, salt: 165745295, reach: 2) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let biome = gen.column(x, z).biome
            guard biome.isOcean || biome.isBeach else { return nil }
            let y = gen.groundY(x, z)
            let s = seed
            return StructureStart(kind: "shipwreck", pieces: [piece(x - 11, y - 2, z - 4, x + 11, y + 10, z + 4) { w in shipwreckBuild(&w, x, y + 1, z, s) }],
                                  anchor: IVec3(x, max(y + 4, SEA + 2), z - 10))
        }
    }

    static func shipwreckBuild(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let pl = rng.chance(0.5) ? Blocks.id("oak_planks") : Blocks.id("spruce_planks"), log = Blocks.id("spruce_log")
        let broken = rng.chance(0.5)
        for a in -10...10 {
            if broken && a > 4 && rng.chance(0.6) { continue }
            let taper = abs(a) > 7 ? abs(a) - 7 : 0
            let half = 3 - taper
            guard half >= 0 else { continue }
            for b in -half...half {
                w.set(cx + a, y, cz + b, pl)
                if abs(b) == half { for h in 1...2 where !(broken && rng.chance(0.3)) { w.set(cx + a, y + h, cz + b, pl) } }
                else { for h in 1...3 { w.set(cx + a, y + h, cz + b, WATER_IF_BELOW_SEA(y + h)) } }
            }
            if abs(a) <= 6 { w.set(cx + a, y + 3, cz, pl) }
        }
        if !broken { for h in 1...8 { w.set(cx - 1, y + h, cz, log) } }
        w.chest(cx - 7, y + 1, cz, loot: "shipwreck_supply", seed: rng.next(), facing: 2)
        w.chest(cx + 7, y + 1, cz, loot: "shipwreck_treasure", seed: rng.next(), facing: 3)
        w.chest(cx, y + 1, cz + 1, loot: "shipwreck_map", seed: rng.next(), facing: 0)
    }

    static func WATER_IF_BELOW_SEA(_ y: Int) -> BlockID { y <= SEA ? WATER : AIR }

    static func buriedTreasure(_ gen: WorldGen) -> StructureType {
        StructureType(name: "buried_treasure", spacing: 4, separation: 1, salt: 10387320, reach: 0) { [unowned gen] seed, cx, cz in
            var rng = SRng(seed)
            guard rng.int(100) < 6 else { return nil }             // ~1% of beach chunks overall
            let x = cx * CS + 9, z = cz * CS + 9
            guard gen.column(x, z).biome.isBeach else { return nil }
            let y = gen.groundY(x, z) - rng.range(1, 3)
            let s = rng.next()
            return StructureStart(kind: "buried_treasure", pieces: [piece(x, y, z, x, y, z) { w in w.chest(x, y, z, loot: "buried_treasure", seed: s) }],
                                  anchor: IVec3(x, y + 4, z))
        }
    }

    // MARK: Mineshafts

    static func mineshaft(_ gen: WorldGen) -> StructureType {
        StructureType(name: "mineshaft", spacing: 16, separation: 1, salt: 30084233, reach: 4) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let badlands = gen.column(x, z).biome.isBadlands
            var rng = SRng(seed)
            let y = badlands ? gen.groundY(x, z) - 4 : YOFF + rng.range(-40, 30)
            return mineshaftLayout(&rng, x, y, z, mesa: badlands)
        }
    }

    static func mineshaftLayout(_ rng: inout SRng, _ ox: Int, _ oy: Int, _ oz: Int, mesa: Bool) -> StructureStart {
        // Random corridor tree from a central room: corridors are 3 wide, 3 tall, 5-block support spacing.
        struct Seg { let x: Int; let y: Int; let z: Int; let dx: Int; let dz: Int; let len: Int }
        var segs: [Seg] = []
        var frontier: [(Int, Int, Int, Int, Int)] = []
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { frontier.append((ox + dx * 4, oy, oz + dz * 4, dx, dz)) }
        var n = 0
        while let f = frontier.popLast(), n < 26 {
            n += 1
            let len = rng.range(8, 24)
            let s = Seg(x: f.0, y: f.1, z: f.2, dx: f.3, dz: f.4, len: len)
            if abs(s.x + s.dx * len - ox) > 72 || abs(s.z + s.dz * len - oz) > 72 { continue }
            segs.append(s)
            // Branch at the end and sometimes midway.
            let ex = s.x + s.dx * len, ez = s.z + s.dz * len
            let ny = s.y + (rng.chance(0.2) ? rng.range(-4, 4) : 0)
            if rng.chance(0.7) { frontier.insert((ex, ny, ez, s.dx, s.dz), at: 0) }
            if rng.chance(0.6) { frontier.insert((ex, s.y, ez, s.dz, s.dx), at: 0) }
            if rng.chance(0.5) { frontier.insert((ex, s.y, ez, -s.dz, -s.dx), at: 0) }
        }
        let wood = mesa ? Blocks.id("dark_oak_planks") : Blocks.id("oak_planks")
        let fence = mesa ? Blocks.id("dark_oak_fence") : Blocks.id("oak_fence")
        let seed = rng.next()
        var pieces: [Piece] = []
        pieces.append(piece(ox - 4, oy - 1, oz - 4, ox + 4, oy + 5, oz + 4) { w in
            w.fill(ox - 3, oy - 1, oz - 3, ox + 3, oy - 1, oz + 3, DIRT)
            w.fill(ox - 3, oy, oz - 3, ox + 3, oy + 4, oz + 3, AIR)
        })
        for (i, s) in segs.enumerated() {
            let ex = s.x + s.dx * s.len, ez = s.z + s.dz * s.len
            pieces.append(piece(min(s.x, ex) - 2, s.y - 1, min(s.z, ez) - 2, max(s.x, ex) + 2, s.y + 4, max(s.z, ez) + 2) { w in
                var r = SRng(seed &+ UInt64(i) &* 977)
                for k in 0...s.len {
                    let x = s.x + s.dx * k, z = s.z + s.dz * k
                    for side in -1...1 {
                        let bx = x + (s.dz != 0 ? side : 0), bz = z + (s.dx != 0 ? side : 0)
                        for h in 0...2 where !Blocks.isLiquid(w.get(bx, s.y + h, bz)) { w.set(bx, s.y + h, bz, AIR) }
                        if w.get(bx, s.y - 1, bz) == AIR || Blocks.isLiquid(w.get(bx, s.y - 1, bz)) { w.set(bx, s.y - 1, bz, wood) }
                    }
                    if k % 5 == 2 {
                        // Supports: two fence posts and a plank beam.
                        let (ax, az) = (s.dz != 0 ? 1 : 0, s.dx != 0 ? 1 : 0)
                        w.set(x - ax, s.y, z - az, fence); w.set(x - ax, s.y + 1, z - az, fence)
                        w.set(x + ax, s.y, z + az, fence); w.set(x + ax, s.y + 1, z + az, fence)
                        for side in -1...1 { w.set(x + ax * side, s.y + 2, z + az * side, wood) }
                        if r.chance(0.3) { w.set(x, s.y + 1, z, TORCH) }
                    }
                    if Blocks.has("rail") && r.chance(0.7) && k % 5 != 2 { w.set(x, s.y, z, Blocks.id("rail")) }
                    if r.chance(0.06) { w.set(x + (s.dz != 0 ? 1 : 0), s.y + 2, z + (s.dx != 0 ? 1 : 0), Blocks.id("cobweb")) }
                    if r.chance(0.012) { w.chest(x + (s.dz != 0 ? -1 : 0), s.y, z + (s.dx != 0 ? -1 : 0), loot: "mineshaft", seed: r.next(), facing: 0) }
                    if r.chance(0.004) && !mesa { w.spawner(x, s.y, z, mob: "cave_spider") }
                }
            })
        }
        return StructureStart(kind: "mineshaft", pieces: pieces, anchor: IVec3(ox, oy, oz))
    }

    // MARK: Desert well

    static func desertWell(_ gen: WorldGen) -> StructureType {
        StructureType(name: "desert_well", spacing: 22, separation: 2, salt: 40306, reach: 0) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            guard gen.column(x, z).biome == .desert else { return nil }
            let y = gen.groundY(x, z)
            guard y > SEA else { return nil }
            return StructureStart(kind: "desert_well", pieces: [piece(x - 2, y - 2, z - 2, x + 2, y + 4, z + 2) { w in
                let ss = SANDSTONE, slab = Blocks.id("sandstone_slab")
                w.fill(x - 2, y - 1, z - 2, x + 2, y, z + 2, ss)
                w.set(x, y, z, WATER); w.set(x, y - 1, z, WATER)
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { w.set(x + dx, y + 1, z + dz, slab) }
                for (dx, dz) in [(1, 1), (-1, 1), (1, -1), (-1, -1)] { w.set(x + dx, y + 1, z + dz, ss); w.set(x + dx, y + 2, z + dz, ss) }
                w.fill(x - 1, y + 3, z - 1, x + 1, y + 3, z + 1, slab)
                w.set(x, y + 3, z, ss)
            }], anchor: IVec3(x + 4, y + 2, z + 4))
        }
    }
}

let TNT_ID = Blocks.id("tnt")
