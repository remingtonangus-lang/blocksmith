import Foundation

// Surface structures on region grids with the reference game's spacing/separation:
// villages 34/8, temples 32/8 (desert pyramid, jungle temple, swamp hut or igloo by biome),
// marauder watchtowers 32/8 (20%, away from villages), ruined portals 40/15, shipwrecks 24/4,
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
                return StructureStart(kind: "desert_pyramid", pieces: [piece(x - 11, y - 16, z - 15, x + 11, y + 16, z + 11) { w in desertPyramid(&w, x, y, z, s) }],
                                      anchor: IVec3(x, y + 1, z - 17))
            case .jungle, .bambooJungle, .sparseJungle:
                return StructureStart(kind: "jungle_temple", pieces: [piece(x - 8, y - 6, z - 12, x + 8, y + 15, z + 9) { w in jungleTemple(&w, x, y, z, s) }],
                                      anchor: IVec3(x, y + 2, z - 13))
            case .swamp, .mangroveSwamp:
                return StructureStart(kind: "swamp_hut", pieces: [piece(x - 4, y - 8, z - 5, x + 4, y + 9, z + 5) { w in swampHut(&w, x, max(y, SEA) + 2, z, s) }],
                                      anchor: IVec3(x, max(y, SEA) + 3, z - 8))
            case .snowyPlains, .snowyTaiga, .snowySlopes:
                // Level ground only: on a mountainside the dome sank into the slope (eyes-on temple.png, run 370).
                var lo = y, hi = y
                for (dx, dz) in [(-4, 0), (4, 0), (0, -4), (0, 4)] { let g = gen.groundY(x + dx, z + dz); lo = min(lo, g); hi = max(hi, g) }
                guard hi - lo <= 2 else { return nil }
                return StructureStart(kind: "igloo", pieces: [piece(x - 4, y - 14, z - 6, x + 4, y + 6, z + 4) { w in igloo(&w, x, y + 1, z, s) }],
                                      anchor: IVec3(x, y + 2, z - 7))
            default: return nil
            }
        }
    }

    // Sun temple (desert): a walled hall under a stepped roof, two front towers with ladders to their parapets, a
    // pillared forecourt, a ring corridor with windows round the tall central hall (blue and orange floor pattern), and
    // the treasure chamber under the pattern (four chests in wall niches, a pressure-plate trap). Rebuilt for Remington's
    // playtest 2 ("went into a desert temple, needs rework"): the old one was a solid stepped cone over a 3-high room,
    // towers with no way up and a bare chamber.
    static func desertPyramid(_ w: inout StructWriter, _ cx: Int, _ gy: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let ss = SANDSTONE, cut = Blocks.id("cut_sandstone"), chis = Blocks.id("chiseled_sandstone"), smooth = Blocks.id("smooth_sandstone")
        let orange = Blocks.id("orange_terracotta"), blue = Blocks.has("blue_terracotta") ? Blocks.id("blue_terracotta") : Blocks.id("light_gray_terracotta")
        let ladder = Blocks.id("ladder"), slab = Blocks.has("sandstone_slab") ? Blocks.id("sandstone_slab") : cut
        let y = gy
        func B(_ dx: Int, _ dy: Int, _ dz: Int, _ b: BlockID) { w.set(cx + dx, y + dy, cz + dz, b) }
        func F(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ b: BlockID) {
            w.fill(cx + x0, y + y0, cz + z0, cx + x1, y + y1, cz + z1, b)
        }
        // Foundation, a clear volume (dunes), the floor.
        for dz in -14...10 { for dx in -10...10 { w.pillarDown(cx + dx, y - 1, cz + dz, ss, minY: y - 10) } }
        F(-10, 1, -14, 10, 15, 10, AIR)
        F(-10, 0, -14, 10, 0, 10, ss)
        F(-9, 0, -9, 9, 0, 9, smooth)
        F(-5, 0, -14, 5, 0, -11, smooth)

        // Main body: walls 5 high with a cut-sandstone base course and a terracotta band, then the stepped roof whose
        // inside steps up too (the hall is open to 10 blocks under the peak).
        for dy in 1...5 {
            for k in -10...10 {
                let band: Bool = dy == 4
                let b: BlockID = dy == 1 ? cut : (band ? (k % 2 == 0 ? orange : cut) : ss)
                B(k, dy, -10, b); B(k, dy, 10, b); B(-10, dy, k, b); B(10, dy, k, b)
            }
            for (sx, sz) in [(-10, -10), (10, -10), (-10, 10), (10, 10)] { B(sx, dy, sz, dy == 4 ? chis : cut) }
        }
        for dy in 6...12 {
            let h = 15 - dy
            F(-h, dy, -h, h, dy, h, ss)
            let ih = h - 2
            if ih >= 3 && dy <= 10 { F(-ih, dy, -ih, ih, dy, ih, AIR) }
            // A slab lip along each step's outer edge (the old cone was plain blocks).
            if h <= 9 {
                for k in -(h + 1)...(h + 1) { B(k, dy, -(h + 1), slab); B(k, dy, h + 1, slab); B(-(h + 1), dy, k, slab); B(h + 1, dy, k, slab) }
            }
        }
        // An oculus through the peak: daylight falls onto the floor pattern (the hall was pitch dark inside: run 402),
        // framed by a cut-sandstone curb.
        for (dx, dz) in [(-2, -2), (-2, 2), (2, -2), (2, 2), (0, -2), (0, 2), (-2, 0), (2, 0), (-1, -2), (1, -2), (-1, 2), (1, 2),
                         (-2, -1), (-2, 1), (2, -1), (2, 1)] { B(dx, 13, dz, cut) }
        F(-1, 11, -1, 1, 13, 1, AIR)

        // Inner hall (half-size 4) inside a ring corridor: cut-sandstone walls with a doorway on each side.
        for dy in 1...5 {
            for k in -5...5 { B(k, dy, -5, cut); B(k, dy, 5, cut); B(-5, dy, k, cut); B(5, dy, k, cut) }
        }
        for (dx, dz) in [(0, -5), (0, 5), (-5, 0), (5, 0)] {
            let ax = dz == 0 ? 0 : 1, az = dz == 0 ? 1 : 0
            for t in -1...1 { for dy in 1...3 { B(dx + ax * t, dy, dz + az * t, AIR) } }
            B(dx, 4, dz, chis)
        }
        // Corner pillars and the floor pattern: a blue centre stone (the way down) in an orange diamond.
        for (px, pz) in [(-4, -4), (4, -4), (-4, 4), (4, 4)] {
            for dy in 1...5 { B(px, dy, pz, dy == 3 ? chis : cut) }
        }
        for dz in -2...2 { for dx in -2...2 {
            let m = abs(dx) + abs(dz)
            if m == 2 || m == 1 { B(dx, 0, dz, orange) }
        } }
        for (dx, dz) in [(3, 0), (-3, 0), (0, 3), (0, -3)] { B(dx, 0, dz, blue) }
        B(0, 0, 0, blue)
        // Windows: light into the corridor from three sides.
        for k in [-6, 6] {
            for dy in 2...3 { B(-10, dy, k, AIR); B(10, dy, k, AIR); B(k, dy, 10, AIR) }
        }
        // Urns and dry plants in the corridor corners.
        let pot = Blocks.has("decorated_pot") ? Blocks.id("decorated_pot") : Blocks.id("flower_pot")
        for (dx, dz) in [(-9, -9), (9, -9), (-9, 9), (9, 9), (-8, 9), (8, 9)] { B(dx, 1, dz, pot) }

        // Entrance: a framed doorway with a terracotta pediment.
        F(-1, 1, -10, 1, 3, -10, AIR)
        for dy in 1...4 { B(-2, dy, -10, chis); B(2, dy, -10, chis) }
        F(-1, 4, -10, 1, 4, -10, cut)
        B(0, 5, -10, blue); B(-1, 5, -10, orange); B(1, 5, -10, orange)

        // Front towers (5x5, 13 high) with a ladder up the inside to a crenellated top, doors to the forecourt and
        // the corridor, terracotta rings and an eye on the front.
        for sx in [-1, 1] {
            let tx = sx * 8
            F(tx - 2, 1, -14, tx + 2, 12, -10, ss)
            F(tx - 1, 1, -13, tx + 1, 11, -11, AIR)
            for dy in [4, 8] {
                for k in -2...2 { B(tx + k, dy, -14, orange); B(tx + k, dy, -10, orange); B(tx - 2, dy, -12 + k, orange); B(tx + 2, dy, -12 + k, orange) }
            }
            B(tx, 9, -14, orange); B(tx - 1, 10, -14, orange); B(tx + 1, 10, -14, orange); B(tx, 11, -14, orange); B(tx, 10, -14, blue)
            F(tx - 2, 12, -14, tx + 2, 12, -10, cut)
            for k in -2...2 {
                if k % 2 == 0 { B(tx + k, 13, -14, cut); B(tx + k, 13, -10, cut); B(tx - 2, 13, -12 + k, cut); B(tx + 2, 13, -12 + k, cut) }
            }
            for (ex, ez) in [(-2, -14), (2, -14), (-2, -10), (2, -10)] { B(tx + ex, 13, ez, chis) }
            // Ladder on the back wall (z -10) from the floor through a hatch in the roof.
            let lx = tx + sx
            for dy in 1...12 { B(lx, dy, -11, ladder) }
            // Doors: forecourt side and into the corridor.
            for dy in 1...2 { B(tx - sx * 2, dy, -12, AIR); B(tx - sx, dy, -10, AIR) }
        }
        // Forecourt pillars.
        for px in [-5, 5] {
            for dy in 1...4 { B(px, dy, -14, dy == 4 ? chis : cut) }
            B(px, 5, -14, slab)
        }

        // Treasure chamber 12 below the blue stone: chests in wall niches, carved walls, the pressure-plate trap.
        let fy = y - 12
        w.fill(cx - 5, fy - 1, cz - 5, cx + 5, y - 1, cz + 5, ss)
        w.fill(cx - 3, fy, cz - 3, cx + 3, fy + 3, cz + 3, AIR)
        for k in -3...3 {
            for (bx, bz) in [(k, -4), (k, 4), (-4, k), (4, k)] {
                w.set(cx + bx, fy + 2, cz + bz, k % 2 == 0 ? orange : cut)
                w.set(cx + bx, fy + 1, cz + bz, abs(k) == 2 ? chis : cut)
            }
        }
        w.fill(cx - 3, fy - 1, cz - 3, cx + 3, fy - 1, cz + 3, cut)
        w.set(cx, fy - 1, cz, blue)
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { w.set(cx + dx, fy - 1, cz + dz, orange) }
        w.fill(cx, fy + 4, cz, cx, y - 1, cz, AIR)
        for (dx, dz, f) in [(0, -4, 1), (0, 4, 0), (-4, 0, 3), (4, 0, 2)] {
            w.set(cx + dx, fy + 1, cz + dz, AIR)
            w.chest(cx + dx, fy, cz + dz, loot: "desert_pyramid", seed: rng.next(), facing: f)
        }
        w.fill(cx - 1, fy - 2, cz - 1, cx + 1, fy - 2, cz + 1, TNT_ID)
        w.set(cx, fy, cz, Blocks.has("stone_pressure_plate") ? Blocks.id("stone_pressure_plate") : AIR)
    }

    // Jungle temple: three stepped tiers of mossy stonework with carved bands, corner pillars, a paved approach and
    // a crowned shrine on top; a pillared hall inside with stairs down to the lower chamber and up to the gallery,
    // windows, and vines over everything. (Reworked with the desert temple, Remington's playtest 2.)
    static func jungleTemple(_ w: inout StructWriter, _ cx: Int, _ gy: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let cob = COBBLE, mossy = Blocks.id("mossy_cobblestone"), chis = Blocks.id("chiseled_stone_bricks")
        let mbr = Blocks.has("mossy_stone_bricks") ? Blocks.id("mossy_stone_bricks") : mossy
        let cbr = Blocks.has("cracked_stone_bricks") ? Blocks.id("cracked_stone_bricks") : cob
        let vine = Blocks.id("vine")
        func mat(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            let h = hashf(x, y, z, 0x7E3)
            return h < 0.4 ? mossy : (h < 0.75 ? cob : (h < 0.9 ? mbr : cbr))
        }
        let y = gy
        for z in (cz - 11)...(cz + 7) { for x in (cx - 6)...(cx + 6) { w.pillarDown(x, y - 1, z, cob, minY: y - 20) } }      // 6 left a jungle slope under 3 columns (run 357)
        // Three tiers, each smaller, with a carved band near the top of each and chiseled corner pillars.
        for (tier, (rx, rz, h)) in [(6, 7, 4), (5, 6, 4), (3, 4, 4)].enumerated() {
            let by = y + tier * 4
            for yy in by...(by + h) { for z in (cz - rz)...(cz + rz) { for x in (cx - rx)...(cx + rx) {
                let edge = abs(x - cx) == rx || abs(z - cz) == rz || yy == by || yy == by + h
                var b = edge ? mat(x, yy, z) : AIR
                let wall: Bool = abs(x - cx) == rx || abs(z - cz) == rz
                if wall && yy == by + h - 1 && (x + z) % 2 == 0 { b = chis }
                if abs(x - cx) == rx && abs(z - cz) == rz && yy > by && yy < by + h { b = yy == by + 2 ? chis : mbr }
                w.set(x, yy, z, b)
            } } }
        }
        // Paved approach between two low pillars.
        for z in (cz - 11)...(cz - 8) { for x in (cx - 2)...(cx + 2) { w.set(x, y, z, mat(x, y, z)); for yy in (y + 1)...(y + 4) { w.set(x, yy, z, AIR) } } }
        for px in [cx - 3, cx + 3] {
            for yy in (y + 1)...(y + 2) { w.set(px, yy, cz - 11, mbr) }
            w.set(px, y + 3, cz - 11, chis)
        }
        // Entrance: a framed 3x3 doorway.
        w.fill(cx - 1, y + 1, cz - 7, cx + 1, y + 3, cz - 7, AIR)
        for yy in (y + 1)...(y + 3) { w.set(cx - 2, yy, cz - 7, chis); w.set(cx + 2, yy, cz - 7, chis) }
        for x in stride(from: cx - 4, through: cx + 4, by: 2) where abs(x - cx) > 2 { w.set(x, y + 3, cz - 7, chis) }
        // Shrine crown on the top tier.
        for (dx, dz) in [(-3, -4), (3, -4), (-3, 4), (3, 4)] { w.set(cx + dx, y + 13, cz + dz, chis) }
        w.fill(cx - 1, y + 13, cz - 1, cx + 1, y + 13, cz + 1, mbr)
        w.set(cx, y + 14, cz, chis)
        // Windows in the gallery (second tier).
        for dz in [-2, 2] { w.set(cx - 5, y + 6, cz + dz, AIR); w.set(cx + 5, y + 6, cz + dz, AIR) }
        // Hall pillars.
        for (dx, dz) in [(-5, 5), (5, 5), (5, -5), (-5, -5)] { for yy in (y + 1)...(y + 3) { w.set(cx + dx, yy, cz + dz, yy == y + 2 ? chis : mbr) } }
        // Stair down to the lower chamber with the chests.
        w.fill(cx - 5, y - 4, cz + 2, cx + 5, y - 1, cz + 6, cob)
        w.fill(cx - 4, y - 3, cz + 3, cx + 4, y - 2, cz + 5, AIR)
        for x in stride(from: cx - 3, through: cx + 3, by: 2) { w.set(x, y - 3, cz + 6, chis) }
        // Steps down to the chamber, one block each (a 4-block pit with no way back: structcheck, the chamber chest).
        for k in 0..<4 {
            let z = cz - 1 + k
            w.fill(cx + 3, y - k, z, cx + 3, y + 1, z, AIR)
            w.set(cx + 3, y - k - 1, z, mat(cx + 3, y - k - 1, z))
        }
        // Steps up to the second tier (its floor sealed it off: the upper chest was unreachable).
        for k in 0..<4 {
            let z = cz - 4 + k
            for yy in (y + 1)...(y + 1 + k) { w.set(cx - 3, yy, z, mat(cx - 3, yy, z)) }
            if k < 3 { w.fill(cx - 3, y + 2 + k, z, cx - 3, y + 5, z, AIR) }
        }
        w.chest(cx - 4, y - 3, cz + 4, loot: "jungle_temple", seed: rng.next(), facing: 3)
        w.chest(cx + 1, y + 5, cz + 5, loot: "jungle_temple", seed: rng.next(), facing: 0)
        // Vines: down the outside of every tier and in the hall.
        for (tier, (rx, rz)) in [(6, 7), (5, 6), (3, 4)].enumerated() {
            let top = y + tier * 4 + 3
            for k in -rx...rx {
                for (vx, vz) in [(cx + k, cz - rz - 1), (cx + k, cz + rz + 1)] where hashf(vx, top, vz, 0x71E) < 0.3 && abs(vx - cx) > 1 {
                    let len = 1 + Int(hashf(vx, top, vz, 0x71F) * 3)
                    for d in 0..<len { w.set(vx, top - d, vz, vine) }
                }
            }
            for k in -rz...rz {
                for (vx, vz) in [(cx - rx - 1, cz + k), (cx + rx + 1, cz + k)] where hashf(vx, top, vz, 0x720) < 0.3 {
                    let len = 1 + Int(hashf(vx, top, vz, 0x721) * 3)
                    for d in 0..<len { w.set(vx, top - d, vz, vine) }
                }
            }
        }
        w.set(cx - 3, y + 1, cz + 5, vine)
        w.set(cx + 4, y + 3, cz - 4, vine)
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
        // The floor's overhang is a porch: stilts at its corners, a fence rail round it (open at the door), windows.
        // (The bare overhang read as a tray: blind critic, run 395 temple2.)
        let fence = Blocks.id("oak_fence")
        for (dx, dz) in [(-3, -3), (3, -3), (-3, 4), (3, 4)] { w.pillarDown(cx + dx, y - 1, cz + dz, log, minY: y - 10) }
        for x in (cx - 3)...(cx + 3) where abs(x - cx) > 1 { w.set(x, y + 1, cz - 3, fence) }
        for z in (cz - 3)...(cz + 4) { w.set(cx - 3, y + 1, z, fence); w.set(cx + 3, y + 1, z, fence) }
        for x in (cx - 3)...(cx + 3) { w.set(x, y + 1, cz + 4, fence) }
        for z in [cz, cz + 1] { w.set(cx - 2, y + 2, z, fence); w.set(cx + 2, y + 2, z, fence) }
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
        // Close the crown: an inner (air) cell whose cell above isn't inner gets a snow cap (the shell above the inner
        // plus at dy 2 fell outside the 3.6 radius, leaving a cross-shaped hole in the roof: blind critic, run 395).
        func inner(_ dx: Int, _ dy: Int, _ dz: Int) -> Bool { sqrtf(Float(dx * dx + dz * dz) + Float(dy * dy) * 1.4) <= 2.6 }
        for dy in 0...4 { for dz in -3...3 { for dx in -3...3 where inner(dx, dy, dz) && !inner(dx, dy + 1, dz) {
            w.set(cx + dx, y + dy + 1, cz + dz, snow)
        } } }
        w.fill(cx - 2, y - 1, cz - 2, cx + 2, y - 1, cz + 2, snow)
        w.set(cx - 3, y + 1, cz, ice); w.set(cx + 3, y + 1, cz, ice)
        w.fill(cx, y, cz - 4, cx, y + 1, cz - 3, AIR)
        // The entrance tunnel and a step in front of it stand on snow down to the ground (on a slope the tunnel had no
        // floor, so the walk never got in: structcheck, both basement chests unreachable, run 358).
        for dz in -5...(-3) { w.pillarDown(cx, y - 1, cz + dz, snow, minY: y - 12) }
        w.fill(cx, y, cz - 5, cx, y + 1, cz - 5, AIR)
        w.fill(cx - 1, y, cz - 4, cx - 1, y + 2, cz - 4, snow); w.fill(cx + 1, y, cz - 4, cx + 1, y + 2, cz - 4, snow)
        w.set(cx, y + 2, cz - 4, snow)
        w.set(cx - 1, y, cz + 1, Blocks.id("white_bed") + 1); w.set(cx - 1, y, cz, Blocks.id("white_bed_head") + 1)
        w.set(cx + 1, y, cz + 1, Blocks.id("furnace"))
        w.set(cx + 2, y, cz, Blocks.id("crafting_table"))
        w.set(cx - 2, y + 1, cz - 1, TORCH + 4)                                // on the west snow wall (stood over air)
        // Half of igloos hide a basement: a ladder shaft to a stone-brick lab with a chest.
        if rng.chance(0.5) {
            let by = y - 11
            w.set(cx, y - 1, cz - 2, Blocks.id("oak_trapdoor") + 8)
            w.fill(cx - 3, by - 1, cz - 3, cx + 3, by + 4, cz + 3, Blocks.id("stone_bricks"))
            w.fill(cx - 2, by, cz - 2, cx + 2, by + 3, cz + 2, AIR)
            // The ladder after the room: laid first, the lab's ceiling covered the shaft (structcheck, run 368: both
            // basements' chest and cauldron unreachable).
            for yy in (by + 1)...(y - 2) { w.set(cx, yy, cz - 2, Blocks.id("ladder") + 1) }
            w.chest(cx + 2, by, cz + 2, loot: "igloo_chest", seed: rng.next(), facing: 0)
            w.set(cx + 2, by, cz, Blocks.id("cauldron"))
            // The villager's cell: the west column behind iron bars.
            w.fill(cx - 2, by, cz - 1, cx - 2, by + 2, cz - 1, Blocks.id("iron_bars"))
            w.fill(cx - 1, by, cz, cx - 1, by + 2, cz + 2, Blocks.id("iron_bars"))
            w.mob("villager", V3(Float(cx) - 1.5, Float(by), Float(cz) + 1.5))
        }
    }

    // MARK: Marauder outpost

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
            var pieces = [piece(x - 6, y - 8, z - 6, x + 6, y + 30, z + 6) { w in outpostTower(&w, x, y + 1, z, s) }]
            // The camp round the tower: a cage with a captive golem, tents, a log pile and archery targets, each on
            // ground within a few blocks of the tower's (skipped on steep or wet ground).
            let camp: [(Int, Int, Int)] = [(0, 11, -6), (1, -11, 6), (2, 9, 9), (3, -9, -8)]
            for (kind, dx, dz) in camp {
                let fx = x + dx, fz = z + dz
                // The 2D column height (groundY samples 3D density down the column: four of them per outpost start
                // doubled the bench's first-chunk start time, run 412-415).
                let fy = gen.column(fx, fz).height
                guard fy >= SEA && abs(fy - y) <= 4 else { continue }
                let fs = rng.next()
                pieces.append(piece(fx - 3, fy - 5, fz - 4, fx + 3, fy + 5, fz + 4) { w in outpostCamp(&w, kind, fx, fy + 1, fz, fs) })
            }
            return StructureStart(kind: "pillager_outpost", pieces: pieces, anchor: IVec3(x, y + 4, z - 16))
        }
    }

    // A four-storey watchtower: cobblestone plinth, birch walls on a dark oak frame with fence-slit windows, an open
    // lookout storey, an overhanging platform with the loot chest under a stepped dark oak roof.
    static func outpostTower(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let log = Blocks.id("dark_oak_log"), pl = Blocks.id("dark_oak_planks"), cob = COBBLE, fence = Blocks.id("dark_oak_fence")
        let wall = Blocks.id("birch_planks"), mossy = Blocks.has("mossy_cobblestone") ? Blocks.id("mossy_cobblestone") : COBBLE
        for z in (cz - 4)...(cz + 4) { for x in (cx - 4)...(cx + 4) { w.pillarDown(x, y - 1, z, cob, minY: y - 8) } }
        w.fill(cx - 4, y - 1, cz - 4, cx + 4, y - 1, cz + 4, cob)
        for fl in 0..<4 {
            let by = y + fl * 5
            for yy in by...(by + 4) { for z in (cz - 3)...(cz + 3) { for x in (cx - 3)...(cx + 3) {
                let corner = abs(x - cx) == 3 && abs(z - cz) == 3
                let edge = abs(x - cx) == 3 || abs(z - cz) == 3
                let mid = x == cx || z == cz
                if corner { w.set(x, yy, z, log) }
                else if yy == by { w.set(x, yy, z, pl) }
                else if !edge { w.set(x, yy, z, AIR) }
                else if fl == 3 { w.set(x, yy, z, yy == by + 1 ? fence : AIR) }            // open lookout, railed
                else if fl == 0 && yy <= by + 2 { w.set(x, yy, z, hashf(x, yy, z, 77) < 0.25 ? mossy : cob) }
                else if fl > 0 && mid && (yy == by + 2 || yy == by + 3) { w.set(x, yy, z, fence) }   // window slits
                else { w.set(x, yy, z, wall) }
            } } }
            for yy in by...(by + 4) { w.set(cx + 2, yy, cz + 2, Blocks.id("ladder") + 2) }
            w.mob("pillager", V3(Float(cx) + 0.5, Float(by + 1), Float(cz) + 0.5))
        }
        // Furnishing: a fletching table and a barrel of arrows below, bedrolls of hay above.
        if Blocks.has("fletching_table") { w.set(cx - 2, y + 1, cz + 2, Blocks.id("fletching_table")) }
        if Blocks.has("barrel") { w.set(cx - 2, y + 1, cz - 2, Blocks.id("barrel")) }
        w.set(cx - 2, y + 6, cz + 2, Blocks.id("hay_block")); w.set(cx - 2, y + 6, cz + 1, Blocks.id("hay_block"))
        // Platform, overhanging the walls by two, with a rail.
        let top = y + 20
        w.fill(cx - 5, top, cz - 5, cx + 5, top, cz + 5, pl)
        for x in (cx - 5)...(cx + 5) { w.set(x, top + 1, cz - 5, fence); w.set(x, top + 1, cz + 5, fence) }
        for z in (cz - 5)...(cz + 5) { w.set(cx - 5, top + 1, z, fence); w.set(cx + 5, top + 1, z, fence) }
        // Log beams under the overhang.
        for k in -4...4 where k % 4 == 0 {
            w.set(cx + k, top - 1, cz - 4, log); w.set(cx + k, top - 1, cz + 4, log)
            w.set(cx - 4, top - 1, cz + k, log); w.set(cx + 4, top - 1, cz + k, log)
        }
        // Roof on four posts: stairs stepping up to a plank cap.
        for (dx, dz) in [(-4, -4), (4, -4), (-4, 4), (4, 4)] { w.fill(cx + dx, top + 1, cz + dz, cx + dx, top + 3, cz + dz, log) }
        let stairs = Blocks.has("dark_oak_stairs")
        for k in 0..<4 {
            let hw = 5 - k, ry = top + 4 + k
            for i in -hw...hw {
                if stairs {
                    w.set(cx + i, ry, cz - hw, Blocks.id("dark_oak_stairs[south]")); w.set(cx + i, ry, cz + hw, Blocks.id("dark_oak_stairs"))
                    if abs(i) < hw { w.set(cx - hw, ry, cz + i, Blocks.id("dark_oak_stairs[east]")); w.set(cx + hw, ry, cz + i, Blocks.id("dark_oak_stairs[west]")) }
                } else {
                    w.set(cx + i, ry, cz - hw, pl); w.set(cx + i, ry, cz + hw, pl); w.set(cx - hw, ry, cz + i, pl); w.set(cx + hw, ry, cz + i, pl)
                }
            }
        }
        w.fill(cx - 1, top + 7, cz - 1, cx + 1, top + 7, cz + 1, pl)
        if Blocks.has("lantern") { w.set(cx, top + 6, cz, Blocks.id("lantern")) }
        // A way in and up: a doorway with a slab step on the ground floor, and the ladder continued through the roof
        // platform (the tower was sealed and the platform covered the shaft: structcheck, every outpost chest
        // unreachable).
        w.fill(cx, y + 1, cz - 3, cx, y + 2, cz - 3, AIR)
        let slab = Blocks.has("dark_oak_slab") ? Blocks.id("dark_oak_slab") : (Blocks.has("cobblestone_slab") ? Blocks.id("cobblestone_slab") : cob)
        w.set(cx, y, cz - 4, slab)
        w.set(cx + 2, top, cz + 2, Blocks.id("ladder") + 2)
        w.chest(cx - 2, top + 1, cz - 2, loot: "pillager_outpost", seed: rng.next(), facing: 1)
        w.mob("pillager", V3(Float(cx) + 0.5, Float(top + 1), Float(cz) + 0.5))
        w.mob("pillager", V3(Float(cx) + 2.5, Float(top + 1), Float(cz) - 1.5))
    }

    // Camp pieces round an outpost: 0 cage (captive golem), 1 tent, 2 log pile, 3 archery targets.
    static func outpostCamp(_ w: inout StructWriter, _ kind: Int, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        let pl = Blocks.id("dark_oak_planks"), fence = Blocks.id("dark_oak_fence"), log = Blocks.id("dark_oak_log")
        switch kind {
        case 0:
            for z in (cz - 2)...(cz + 2) { for x in (cx - 2)...(cx + 2) {
                w.pillarDown(x, y - 1, z, DIRT, minY: y - 5)
                let edge = abs(x - cx) == 2 || abs(z - cz) == 2
                for yy in y...(y + 2) { w.set(x, yy, z, edge ? fence : AIR) }
                w.set(x, y + 3, z, pl)
            } }
            w.mob("iron_golem", V3(Float(cx) + 0.5, Float(y), Float(cz) + 0.5))
        case 1:
            let wool = Blocks.id("white_wool")
            for z in (cz - 2)...(cz + 2) {
                for x in (cx - 2)...(cx + 2) { w.pillarDown(x, y - 1, z, DIRT, minY: y - 5); for yy in y...(y + 2) { w.set(x, yy, z, AIR) } }
                w.set(cx - 2, y, z, wool); w.set(cx + 2, y, z, wool)
                w.set(cx - 1, y + 1, z, wool); w.set(cx + 1, y + 1, z, wool)
                w.set(cx, y + 2, z, wool)
            }
            // Level aprons at both open ends (on a slope the ground outside stood a block over the tent floor:
            // structcheck, run 417).
            for z in [cz - 3, cz + 3] { for x in (cx - 1)...(cx + 1) {
                w.pillarDown(x, y - 1, z, DIRT, minY: y - 5)
                for yy in y...(y + 2) { w.set(x, yy, z, AIR) }
            } }
            // A dark ridge pole along the peak (the bare wool A-frame read as white steps: run 408 outpost). No end
            // posts: they stood in the one-block entrances (structcheck: every tent's table unreachable, run 410).
            let ridge = Blocks.has("dark_oak_log[z]") ? Blocks.id("dark_oak_log[z]") : log
            for z in (cz - 2)...(cz + 2) { w.set(cx, y + 3, z, ridge) }
            w.set(cx, y, cz + 1, Blocks.id("crafting_table"))
            w.set(cx + 1, y, cz - 1, Blocks.id("hay_block"))
        case 2:
            for z in (cz - 1)...(cz + 1) { for x in (cx - 2)...(cx + 2) { w.pillarDown(x, y - 1, z, DIRT, minY: y - 5) } }
            let along = Blocks.has("dark_oak_log[x]") ? Blocks.id("dark_oak_log[x]") : log
            for x in (cx - 2)...(cx + 2) { w.set(x, y, cz - 1, along); w.set(x, y, cz, along) }
            for x in (cx - 1)...(cx + 1) { w.set(x, y + 1, cz - 1, along) }
            w.set(cx - 1, y, cz + 1, Blocks.id("pumpkin")); w.set(cx + 1, y, cz + 1, Blocks.id("hay_block"))
            if hashf(cx, y, cz, UInt32(truncatingIfNeeded: seed)) < 0.5 { w.set(cx + 2, y, cz + 1, Blocks.id("pumpkin")) }
        default:
            let target = Blocks.has("target") ? Blocks.id("target") : Blocks.id("hay_block")
            for dx in [-2, 0, 2] {
                w.pillarDown(cx + dx, y - 1, cz, DIRT, minY: y - 5)
                w.set(cx + dx, y, cz, fence); w.set(cx + dx, y + 1, cz, target)
            }
        }
    }

    // MARK: Ruined portal

    static func ruinedPortal(_ gen: WorldGen) -> StructureType {
        StructureType(name: "ruined_portal", spacing: 40, separation: 15, salt: 34222645, reach: 1) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            if abs(x) < 64 && abs(z) < 64 { return nil }          // keep the spawn area clear
            let y = gen.groundY(x, z)
            guard y > YOFF + 10 else { return nil }
            // Only on ground that is roughly level across the footprint (no half-hanging frames).
            for (dx, dz) in [(-5, -3), (5, -3), (-5, 3), (5, 3)] where abs(gen.groundY(x + dx, z + dz) - y) > 3 { return nil }
            let s = seed
            let underwater = y < SEA
            return StructureStart(kind: "ruined_portal", pieces: [piece(x - 5, y - 3, z - 3, x + 5, y + 7, z + 3) { w in ruinedPortalBuild(&w, x, y, z, s, underwater) }],
                                  anchor: IVec3(x, y + 2, z - 8))
        }
    }

    static func ruinedPortalBuild(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64, _ wet: Bool) {
        var rng = SRng(seed)
        let obs = OBSIDIAN, cry = Blocks.id("crying_obsidian"), nr = Blocks.id("netherrack"), mag = Blocks.id("magma_block"), gold = Blocks.id("gold_block")
        // Emberdeep-corrupted ground patch.
        for dz in -3...3 { for dx in -5...5 where hashf(cx + dx, 0, cz + dz, UInt32(truncatingIfNeeded: seed)) < 0.65 {
            w.set(cx + dx, y, cz + dz, rng.chance(0.15) ? mag : nr)
        } }
        // Earth under the patch and frame down to the real ground, so nothing floats.
        for dz in -3...3 { for dx in -5...5 { w.pillarDown(cx + dx, y - 1, cz + dz, DIRT, minY: y - 10) } }
        // Broken 4x5 frame (interior 2x3): each side pillar is worn down from the top, and a lintel block
        // only stays where the pillar under its end is whole, so no piece hangs in the air.
        let leftH = 5 - rng.int(3), rightH = 5 - rng.int(3)
        func stone() -> BlockID { rng.chance(0.12) ? cry : obs }
        for j in 0..<leftH { w.set(cx - 1, y + 1 + j, cz, stone()) }
        for j in 0..<rightH { w.set(cx + 2, y + 1 + j, cz, stone()) }
        for i in 0...1 where rng.chance(0.8) { w.set(cx + i, y + 1, cz, stone()) }
        if leftH == 5 { w.set(cx, y + 5, cz, stone()); if rightH == 5 && rng.chance(0.7) { w.set(cx + 1, y + 5, cz, stone()) } }
        else if rightH == 5 { w.set(cx + 1, y + 5, cz, stone()) }
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
            return StructureStart(kind: "shipwreck", pieces: [piece(x - 15, y - 3, z - 8, x + 15, y + 16, z + 8) { w in shipwreckBuild(&w, x, y - 1, z, s) }],
                                  anchor: IVec3(x, max(y + 6, SEA + 2), z - 15))
        }
    }

    // A sunken sailing ship lying half buried in the seabed (y is its keel): a V-section hull of planks on a log keel,
    // a hold under a deck with hatches, a raised stern cabin, a forecastle and bowsprit, masts with yards. Broken
    // wrecks lose their bow above the hold, have holes in the planking and a snapped mast lying on deck.
    static func shipwreckBuild(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let wood = ["oak", "spruce", "dark_oak"][rng.int(3)]
        let pl = Blocks.id("\(wood)_planks"), fence = Blocks.id("\(wood)_fence")
        let log = Blocks.id("spruce_log")
        let logA = Blocks.has("spruce_log[x]") ? Blocks.id("spruce_log[x]") : log       // along the ship
        let logB = Blocks.has("spruce_log[z]") ? Blocks.id("spruce_log[z]") : log       // across it
        let broken = rng.chance(0.5)
        let dir = rng.chance(0.5) ? 1 : -1                                              // bow toward +x or -x
        func at(_ a: Int, _ h: Int, _ b: Int, _ id: BlockID) { w.set(cx + a * dir, y + h, cz + b, id) }
        func wet(_ h: Int) -> BlockID { WATER_IF_BELOW_SEA(y + h) }
        func beam(_ a: Int) -> Int {
            if a <= -9 { return 2 }
            if a <= 5 { return 3 }
            if a <= 8 { return 2 }
            return a <= 10 ? 1 : 0
        }
        func rail(_ a: Int) -> Int { a <= -8 ? 7 : (a >= 10 ? 6 : (a >= 8 ? 5 : 4)) }
        for a in -12...12 {
            let hw = beam(a), top = rail(a)
            let snapped = broken && a >= 6                              // the bow broke off above the hold
            for h in 0...top {
                if snapped && h > 2 { break }
                let hh = h == 0 ? 0 : (h == 1 ? max(0, hw - 1) : hw)
                for b in -hh...hh {
                    let end = a == -12 || hw == 0
                    let shell = h <= 1 || abs(b) == hh || end
                    if shell {
                        let hole = broken && h >= 2 && rng.chance(0.12)
                        at(a, h, b, h == 0 ? logA : (hole ? wet(h) : pl))
                    } else {
                        at(a, h, b, wet(h))
                    }
                }
            }
            if snapped { continue }
            // Decks: main deck at 4 midships (hatches over the hold), the cabin floor and its roof aft, the
            // forecastle forward. Rails along the main deck.
            if hw > 0 {
                for b in (-hw + 1)...(hw - 1) {
                    if a > -8 && a < 8 && !((a == 3 || a == -3) && abs(b) <= 1) { at(a, 4, b, pl) }
                    if a <= -8 { at(a, 4, b, pl); at(a, 7, b, pl); for h in 5...6 { at(a, h, b, wet(h)) } }
                    if a >= 8 && a <= 10 { at(a, 5, b, pl) }
                }
                if a > -8 && a < 8 { at(a, 5, -hw, fence); at(a, 5, hw, fence) }
            }
        }
        // Cabin door toward midships, stern windows, the rail round the poop deck.
        for b in -2...2 { at(-8, 5, b, pl); at(-8, 6, b, pl) }
        at(-8, 5, 0, wet(5)); at(-8, 6, 0, wet(6))
        at(-12, 6, -1, wet(6)); at(-12, 6, 1, wet(6))
        for a in -12...(-8) { at(a, 8, -beam(a), fence); at(a, 8, beam(a), fence) }
        if !broken {
            for k in 13...15 { at(k, 5, 0, logA) }                          // bowsprit
        }
        // Masts: the main mast with two yards, the mizzen aft. A broken wreck's main mast snapped at the deck and
        // lies along it.
        if broken {
            for h in 1...6 { at(1, h, 0, log) }
            for a in 2...6 { at(a, 5, 1, logA) }
        } else {
            for h in 1...13 { at(1, h, 0, log) }
            for b in -3...3 { at(1, 9, b, logB) }
            for b in -2...2 { at(1, 12, b, logB) }
            for h in 1...10 { at(-5, h, 0, log) }
            for b in -2...2 { at(-5, 8, b, logB) }
        }
        let supply = (cx - 6 * dir, y + 2, cz), treasure = (cx + (broken ? 4 : 6) * dir, y + 2, cz), map = (cx - 10 * dir, y + 5, cz)
        w.chest(supply.0, supply.1, supply.2, loot: "shipwreck_supply", seed: rng.next(), facing: 2)
        w.chest(treasure.0, treasure.1, treasure.2, loot: "shipwreck_treasure", seed: rng.next(), facing: 3)
        w.chest(map.0, map.1, map.2, loot: "shipwreck_map", seed: rng.next(), facing: 0)
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
        // `from`: the floor height where the segment joins its parent; the first blocks ramp from there to `y` one
        // block per step (a branch 2-4 blocks higher or lower joined with a wall or a pit: structcheck poi_unreachable).
        struct Seg {
            let x: Int; let y: Int; let z: Int; let dx: Int; let dz: Int; let len: Int; let from: Int
            // k = 0 is the parent's end cell itself: level with the parent there (with k + 1 an upward branch's floor
            // stood one up in the shared cell, where the parent's floor still holds the feet, so the next step was
            // two blocks: structcheck mineshaft poi_unreachable, issue gallery run 362).
            func floor(_ k: Int) -> Int { y == from ? y : from + (y > from ? 1 : -1) * min(k, abs(y - from)) }
        }
        var segs: [Seg] = []
        var frontier: [(Int, Int, Int, Int, Int, Int)] = []
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { frontier.append((ox + dx * 4, oy, oz + dz * 4, dx, dz, oy)) }
        var n = 0
        while let f = frontier.popLast(), n < 26 {
            n += 1
            let len = rng.range(8, 24)
            let s = Seg(x: f.0, y: f.1, z: f.2, dx: f.3, dz: f.4, len: len, from: f.5)
            if abs(s.x + s.dx * len - ox) > 72 || abs(s.z + s.dz * len - oz) > 72 { continue }
            segs.append(s)
            // Branch at the hollow and sometimes midway.
            let ex = s.x + s.dx * len, ez = s.z + s.dz * len
            let ny = s.y + (rng.chance(0.2) ? rng.range(-4, 4) : 0)
            if rng.chance(0.7) { frontier.insert((ex, ny, ez, s.dx, s.dz, s.y), at: 0) }
            if rng.chance(0.6) { frontier.insert((ex, s.y, ez, s.dz, s.dx, s.y), at: 0) }
            if rng.chance(0.5) { frontier.insert((ex, s.y, ez, -s.dz, -s.dx, s.y), at: 0) }
        }
        let wood = mesa ? Blocks.id("dark_oak_planks") : Blocks.id("oak_planks")
        let fence = mesa ? Blocks.id("dark_oak_fence") : Blocks.id("oak_fence")
        let seed = rng.next()
        var pieces: [Piece] = []
        pieces.append(piece(ox - 4, oy - 1, oz - 4, ox + 4, oy + 5, oz + 4) { w in
            w.fill(ox - 3, oy - 1, oz - 3, ox + 3, oy - 1, oz + 3, DIRT)
            w.fill(ox - 3, oy, oz - 3, ox + 3, oy + 4, oz + 3, AIR)
        })
        // Two passes: every corridor is carved before any support, rail or chest goes in (a support built with its
        // own corridor stood in the middle of a crossing corridor carved earlier, or a later corridor's carving left
        // half a support: structcheck, mineshaft chests behind fence posts). Pieces run in order in each chunk.
        func box(_ s: Seg) -> (IVec3, IVec3) {
            let ex = s.x + s.dx * s.len, ez = s.z + s.dz * s.len
            return (IVec3(min(s.x, ex) - 2, min(s.y, s.from) - 1, min(s.z, ez) - 2), IVec3(max(s.x, ex) + 2, max(s.y, s.from) + 4, max(s.z, ez) + 2))
        }
        // Every carved corridor cell, from the layout itself (reading blocks missed corridors in the next chunk, so a
        // support still stood across a crossing at chunk borders: structcheck, run 357).
        // Cells as packed integers: cheaper to hash than three-Int structs, and a layout is made for every 16-chunk region.
        @inline(__always) func ck(_ x: Int, _ y: Int, _ z: Int) -> Int { (x & 0xFFFFF) | ((z & 0xFFFFF) << 20) | ((y & 0x3FF) << 40) }
        // Built on first use by a piece, not with the layout: a layout is made for every 16-chunk region that a chunk
        // nearby asks about, mostly without any piece of it ever being built (bench gen: mineshaft starts were 42 ms of
        // 24 chunks, run 367). Locked: chunks generate on several threads.
        let cells = LazyValue { () -> (carved: Set<Int>, shared: Set<Int>) in
            var carved = Set<Int>()
            carved.reserveCapacity(4096)
            // Cells two or more corridors carve (crossings, also at different heights): no support post, beam or chest
            // there (structcheck issue gallery, run 362: a post of one corridor standing in another's lane before a chest).
            var owner: [Int: Int] = [:], sharedCells = Set<Int>()
            owner.reserveCapacity(4096)
            for (si, s) in segs.enumerated() {
                for k in 0...s.len {
                    let x = s.x + s.dx * k, z = s.z + s.dz * k, fy = s.floor(k)
                    for side in -1...1 {
                        let bx = x + (s.dz != 0 ? side : 0), bz = z + (s.dx != 0 ? side : 0)
                        for h in 0...2 {
                            let c = ck(bx, fy + h, bz)
                            carved.insert(c)
                            if let o = owner[c] { if o != si { sharedCells.insert(c) } } else { owner[c] = si }
                        }
                    }
                }
            }
            return (carved, sharedCells)
        }
        let rail = Blocks.id("rail"), cobweb = Blocks.id("cobweb")
        for s in segs {
            let (lo, hi) = box(s)
            pieces.append(piece(lo.x, lo.y, lo.z, hi.x, hi.y, hi.z) { w in
                let corridorCells = cells.value.carved
                for k in 0...s.len {
                    let x = s.x + s.dx * k, z = s.z + s.dz * k
                    let fy = s.floor(k)
                    for side in -1...1 {
                        let bx = x + (s.dz != 0 ? side : 0), bz = z + (s.dx != 0 ? side : 0)
                        for h in 0...2 where !Blocks.isLiquid(w.get(bx, fy + h, bz)) { w.set(bx, fy + h, bz, AIR) }
                        // No plank floor inside another corridor's open space: where corridors cross at different
                        // heights the upper one's floor hung across the lower one and blocked it (structcheck issue
                        // gallery, run 360: plank slabs filling a lane in front of a chest).
                        let under = ck(bx, fy - 1, bz)
                        let open: Bool = w.get(bx, fy - 1, bz) == AIR || Blocks.isLiquid(w.get(bx, fy - 1, bz))
                        if open && !corridorCells.contains(under) { w.set(bx, fy - 1, bz, wood) }
                        // Water against the corridor (an aquifer or a lake above) boarded off: it stood as a wall of
                        // source blocks beside the open lane (gencheck leak, seed 777 run 371).
                        let up = ck(bx, fy + 3, bz)
                        if Blocks.isLiquid(w.get(bx, fy + 3, bz)) && !corridorCells.contains(up) { w.set(bx, fy + 3, bz, wood) }
                        if side != 0 {
                            let ox = bx + (s.dz != 0 ? side : 0), oz = bz + (s.dx != 0 ? side : 0)
                            for h in 0...2 where Blocks.isLiquid(w.get(ox, fy + h, oz)) && !corridorCells.contains(ck(ox, fy + h, oz)) {
                                w.set(ox, fy + h, oz, wood)
                            }
                        }
                    }
                }
                // ...and past both ends of the corridor (water stood against the lane's end over the rails: gencheck leak
                // kinds, run 377).
                for (k, fy) in [(-1, s.floor(0)), (s.len + 1, s.floor(s.len))] {
                    let x = s.x + s.dx * k, z = s.z + s.dz * k
                    for side in -1...1 {
                        let bx = x + (s.dz != 0 ? side : 0), bz = z + (s.dx != 0 ? side : 0)
                        for h in 0...2 where Blocks.isLiquid(w.get(bx, fy + h, bz)) && !corridorCells.contains(ck(bx, fy + h, bz)) {
                            w.set(bx, fy + h, bz, wood)
                        }
                    }
                }
            })
        }
        for (i, s) in segs.enumerated() {
            let (lo, hi) = box(s)
            pieces.append(piece(lo.x, lo.y, lo.z, hi.x, hi.y, hi.z) { w in
                var r = SRng(seed &+ UInt64(i) &* 977)
                let (corridorCells, shared) = cells.value
                // A wall cell: not inside any corridor of this mineshaft.
                func wall(_ x: Int, _ y: Int, _ z: Int) -> Bool { !corridorCells.contains(ck(x, y, z)) }
                for k in 0...s.len {
                    let x = s.x + s.dx * k, z = s.z + s.dz * k
                    let fy = s.floor(k)
                    let (ax, az) = (s.dz != 0 ? 1 : 0, s.dx != 0 ? 1 : 0)
                    // Supports only between two walls (where another corridor crosses, a post would block it).
                    let walled = wall(x - 2 * ax, fy + 1, z - 2 * az) && wall(x + 2 * ax, fy + 1, z + 2 * az)
                    var crossed = false
                    for side in -1...1 { for h in 0...2 where shared.contains(ck(x + ax * side, fy + h, z + az * side)) { crossed = true } }
                    // A support also keeps a slice away from a crossing and from a change of floor height: its beam
                    // took the headroom of anyone stepping down into it, and a post beside a crossing at another
                    // height closed the step (structcheck maps: both remaining mineshaft chests, run 372).
                    var nearJoin = false
                    if k % 5 == 2 {
                        for j in [-1, 1] {
                            let kk = k + j
                            if kk < 0 || kk > s.len || s.floor(kk) != fy { nearJoin = true; continue }
                            let nx = x + s.dx * j, nz = z + s.dz * j
                            for side in -1...1 { for h in 0...2 where shared.contains(ck(nx + ax * side, fy + h, nz + az * side)) { nearJoin = true } }
                            if !wall(nx - 2 * ax, fy + 1, nz - 2 * az) || !wall(nx + 2 * ax, fy + 1, nz + 2 * az) { nearJoin = true }
                        }
                    }
                    if k % 5 == 2 && walled && !crossed && !nearJoin {
                        // Supports: two fence posts and a plank beam.
                        w.set(x - ax, fy, z - az, fence); w.set(x - ax, fy + 1, z - az, fence)
                        w.set(x + ax, fy, z + az, fence); w.set(x + ax, fy + 1, z + az, fence)
                        for side in -1...1 { w.set(x + ax * side, fy + 2, z + az * side, wood) }
                        // A torch hung on the near post (it stood in mid-tunnel under the beam).
                        if r.chance(0.3) { w.set(x, fy + 1, z, TORCH + BlockID(ax != 0 ? 4 : 2)) }
                    }
                    if r.chance(0.7) && k % 5 != 2 { w.set(x, fy, z, rail + (s.dx != 0 ? 1 : 0)) }
                    if r.chance(0.06) { w.set(x + ax, fy + 2, z + az, cobweb) }
                    // Not on a support's slice: the chest replaced the lower fence post (structcheck run 358: a chest under
                    // a post blocking the lane).
                    if r.chance(0.012) && walled && !crossed && k % 5 != 2 { w.chest(x - ax, fy, z - az, loot: "mineshaft", seed: r.next(), facing: 0) }
                    if r.chance(0.004) && !mesa { w.spawner(x, fy, z, mob: "cave_spider") }
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
