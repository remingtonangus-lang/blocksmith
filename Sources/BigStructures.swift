import Foundation
import simd

// The large late-game structures, laid out procedurally with the reference game's placement rules:
// sea temples 32/5 in deep oceans, forest manors 80/20 in dark forests, buried citadels 24/8 in
// the murk depths (y −51), proving halls 34/12 underground (y −40…−20), ocean ruins 20/8, trail ruins
// 34/8, and fossils (1 in 64 desert / swamp chunks).
enum BigStructures {
    static func types(_ gen: WorldGen) -> [StructureType] {
        [monument(gen), mansion(gen), ancientCity(gen), trialChambers(gen), oceanRuins(gen), trailRuins(gen), fossil(gen)]
    }
    static func piece(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ f: @escaping (inout StructWriter) -> Void) -> Piece {
        Piece(min: IVec3(x0, y0, z0), max: IVec3(x1, y1, z1), build: f)
    }
    static func g(_ n: String) -> BlockID { Blocks.has(n) ? Blocks.id(n) : STONE }

    // MARK: Ocean monument

    static func monument(_ gen: WorldGen) -> StructureType {
        StructureType(name: "monument", spacing: 32, separation: 5, salt: 10387313, reach: 3) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let b = gen.column(x, z).biome
            guard b.isDeepOcean else { return nil }
            // The 58x58 footprint must be ocean all round.
            for (dx, dz) in [(-29, -29), (29, -29), (-29, 29), (29, 29)] where !gen.column(x + dx, z + dz).biome.isOcean { return nil }
            let y0 = SEA - 26
            return StructureStart(kind: "monument", pieces: [piece(x - 29, y0 - 4, z - 29, x + 29, SEA, z + 29) { w in buildMonument(&w, x, y0, z, seed) }],
                                  anchor: IVec3(x, y0 + 12, z - 8))
        }
    }

    static func buildMonument(_ w: inout StructWriter, _ cx: Int, _ y0: Int, _ cz: Int, _ seed: UInt64) {
        let pr = g("prismarine"), br = g("prismarine_bricks"), dk = g("dark_prismarine"), lamp = g("sea_lantern"), gold = g("gold_block")
        let sponge = g("wet_sponge")
        // Foundation pillars down to the sea floor.
        for z in stride(from: cz - 28, through: cz + 28, by: 4) { for x in stride(from: cx - 28, through: cx + 28, by: 4) { w.pillarDown(x, y0 - 1, z, br, minY: y0 - 30) } }
        // Main body: a hollow box of bricks with a dark tidestone roof band, filled with water inside.
        w.fill(cx - 28, y0, cz - 28, cx + 28, y0 + 8, cz + 28, br)
        w.fill(cx - 27, y0 + 1, cz - 27, cx + 27, y0 + 7, cz + 27, WATER)
        w.fill(cx - 28, y0 + 8, cz - 28, cx + 28, y0 + 8, cz + 28, dk)
        // Upper tier and the central tower.
        w.fill(cx - 20, y0 + 9, cz - 20, cx + 20, y0 + 15, cz + 20, pr)
        w.fill(cx - 19, y0 + 9, cz - 19, cx + 19, y0 + 14, cz + 19, WATER)
        w.fill(cx - 8, y0 + 16, cz - 8, cx + 8, y0 + 21, cz + 8, br)
        w.fill(cx - 7, y0 + 16, cz - 7, cx + 7, y0 + 20, cz + 7, WATER)
        // Entrance on the north side.
        w.fill(cx - 3, y0 + 1, cz - 28, cx + 3, y0 + 7, cz - 28, WATER)
        // Inner wing rooms (elder spikefishs in the two wings and the penthouse).
        for sx in [-1, 1] {
            let wx = cx + sx * 18
            w.fill(wx - 6, y0 + 1, cz - 6, wx + 6, y0 + 7, cz + 6, dk)
            w.fill(wx - 5, y0 + 2, cz - 5, wx + 5, y0 + 6, cz + 5, WATER)
            w.fill(wx - 1, y0 + 2, cz - 6, wx + 1, y0 + 4, cz - 6, WATER)
            w.mob("elder_guardian", V3(Float(wx) + 0.5, Float(y0 + 3), Float(cz) + 0.5))
        }
        w.mob("elder_guardian", V3(Float(cx) + 0.5, Float(y0 + 18), Float(cz) + 0.5))
        // Treasure room: 8 gold blocks in dark tidestone.
        w.fill(cx - 3, y0 + 1, cz + 8, cx + 3, y0 + 5, cz + 14, dk)
        w.fill(cx - 2, y0 + 2, cz + 9, cx + 2, y0 + 4, cz + 13, WATER)
        w.fill(cx - 1, y0 + 2, cz + 10, cx, y0 + 3, cz + 11, gold)
        // Pillars, tide lanterns, a sponge room.
        for z in stride(from: cz - 24, through: cz + 24, by: 8) { for x in stride(from: cx - 24, through: cx + 24, by: 8) where abs(x - cx) > 12 || abs(z - cz) > 12 {
            w.fill(x, y0 + 1, z, x, y0 + 7, z, pr)
            w.set(x, y0 + 4, z, lamp)
        } }
        var rng = SRng(seed)
        if rng.chance(0.7) {
            let sx = cx + (rng.chance(0.5) ? -10 : 10), sz = cz - 14
            w.fill(sx - 2, y0 + 2, sz - 2, sx + 2, y0 + 2, sz + 2, sponge)
            w.fill(sx - 2, y0 + 6, sz - 2, sx + 2, y0 + 6, sz + 2, sponge)
        }
        for k in 0..<6 {
            let gx = cx + Int(rng.float() * 40) - 20, gz = cz + Int(rng.float() * 40) - 20
            w.mob("guardian", V3(Float(gx) + 0.5, Float(y0 + 3 + k % 3), Float(gz) + 0.5))
        }
    }

    // MARK: Woodland mansion

    static func mansion(_ gen: WorldGen) -> StructureType {
        StructureType(name: "mansion", spacing: 80, separation: 20, salt: 10387319, reach: 3) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            guard gen.column(x, z).biome == .darkForest else { return nil }
            let y = gen.groundY(x, z)
            guard y > SEA else { return nil }
            return StructureStart(kind: "mansion", pieces: [piece(x - 23, y - 6, z - 23, x + 23, y + 48, z + 23) { w in buildMansion(&w, x, y + 1, z, seed) }],
                                  anchor: IVec3(x, y + 2, z - 26))
        }
    }

    static func buildMansion(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let cob = COBBLE, pl = g("dark_oak_planks"), log = g("dark_oak_log"), glass = g("glass_pane"), carpet = g("white_carpet")
        let stairs = g("cobblestone_stairs"), roof = g("dark_oak_stairs")
        // Cleared plot and cobblestone base.
        for z in (cz - 22)...(cz + 22) { for x in (cx - 22)...(cx + 22) { w.pillarDown(x, y - 1, z, cob, minY: y - 8) } }
        w.fill(cx - 22, y, cz - 22, cx + 22, y + 46, cz + 22, AIR)          // clears tree tops above the plot too
        w.fill(cx - 22, y - 1, cz - 22, cx + 22, y - 1, cz + 22, cob)
        // Three floors of 6 blocks.
        for f in 0..<3 {
            let fy = y + f * 6
            let r = f == 2 ? 16 : 20
            w.fill(cx - r, fy, cz - r, cx + r, fy + 5, cz + r, pl)
            w.fill(cx - r + 1, fy + 1, cz - r + 1, cx + r - 1, fy + 5, cz + r - 1, AIR)
            // Upper floors: carpet laid on the plank floor (it replaced the planks, so each floor was carpet over the
            // room below with no ceiling between them).
            if f > 0 { w.fill(cx - r + 1, fy + 1, cz - r + 1, cx + r - 1, fy + 1, cz + r - 1, carpet) }
            // Corner logs and windows.
            for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { w.fill(cx + sx * r, fy, cz + sz * r, cx + sx * r, fy + 5, cz + sz * r, log) }
            for k in stride(from: -r + 3, through: r - 3, by: 4) {
                for (x, z) in [(cx + k, cz - r), (cx + k, cz + r), (cx - r, cz + k), (cx + r, cz + k)] { w.fill(x, fy + 2, z, x, fy + 3, z, glass) }
            }
            // Room walls: a grid of 8x8 rooms with doorways.
            for k in stride(from: -r + 8, through: r - 8, by: 8) {
                w.fill(cx + k, fy + 1, cz - r + 1, cx + k, fy + 5, cz + r - 1, pl)
                w.fill(cx - r + 1, fy + 1, cz + k, cx + r - 1, fy + 5, cz + k, pl)
            }
            for k in stride(from: -r + 4, through: r - 4, by: 8) {
                for q in stride(from: -r + 8, through: r - 8, by: 8) {
                    w.fill(cx + q, fy + 1, cz + k, cx + q, fy + 2, cz + k, AIR)
                    w.fill(cx + k, fy + 1, cz + q, cx + k, fy + 2, cz + q, AIR)
                }
            }
            // Loot and residents.
            for _ in 0..<3 {
                let lx = cx + Int(rng.float() * Float(2 * r - 4)) - r + 2, lz = cz + Int(rng.float() * Float(2 * r - 4)) - r + 2
                w.chest(lx, fy + 1, lz, loot: "mansion", seed: rng.next(), facing: rng.int(4))
            }
            for _ in 0..<(f == 0 ? 4 : 3) {
                let mx = cx + Int(rng.float() * Float(2 * r - 6)) - r + 3, mz = cz + Int(rng.float() * Float(2 * r - 6)) - r + 3
                let my: Float = Float(fy + 1) + (f > 0 ? 0.07 : 0)                       // on the carpet
                w.mob(rng.chance(0.35) ? "evoker" : "vindicator", V3(Float(mx) + 0.5, my, Float(mz) + 0.5))
            }
            // Stairs up the middle.
            if f < 2 { for k in 0..<6 { w.set(cx + 2, fy + 1 + k, cz - 3 + k, stairs + 1); w.fill(cx + 2, fy + 2 + k, cz - 3 + k, cx + 2, fy + 5, cz - 3 + k, AIR) } }
        }
        // A roof over the second floor's outer ring: the top floor is narrower (16 against 20), so the ring between
        // them stood open to the sky (blind critic, run 362 mansion: an open channel round the stepped roof).
        for z in (cz - 20)...(cz + 20) { for x in (cx - 20)...(cx + 20) where max(abs(x - cx), abs(z - cz)) > 16 {
            w.set(x, y + 12, z, pl)
        } }
        // Stairwells re-cut after every floor is laid: the next floor's solid floor covered each stair's top, so the
        // upper floors were unreachable on foot (structcheck: 24 of 36 mansion POIs unreachable).
        for f in 0..<2 {
            let fy = y + f * 6
            for k in 0..<6 {
                w.fill(cx + 2, fy + 2 + k, cz - 3 + k, cx + 2, fy + 4 + k, cz - 3 + k, AIR)
                w.set(cx + 2, fy + 1 + k, cz - 3 + k, stairs + 1)
            }
        }
        // Fetchling cell and the roof.
        w.fill(cx - 3, y + 1, cz + 16, cx - 1, y + 3, cz + 18, g("iron_bars"))
        w.fill(cx - 2, y + 1, cz + 17, cx - 2, y + 2, cz + 17, AIR)
        w.mob("allay", V3(Float(cx) - 1.5, Float(y + 1), Float(cz) + 17.5))
        for k in 0...8 {
            let r = 17 - k * 2
            if r < 0 { break }
            w.fill(cx - r, y + 18 + k, cz - r, cx + r, y + 18 + k, cz + r, roof)
            if r > 1 { w.fill(cx - r + 1, y + 18 + k, cz - r + 1, cx + r - 1, y + 18 + k, cz + r - 1, pl) }
        }
        // Front door.
        w.fill(cx - 1, y + 1, cz - 20, cx + 1, y + 3, cz - 20, AIR)
    }

    // MARK: Ancient city

    static func ancientCity(_ gen: WorldGen) -> StructureType {
        StructureType(name: "ancient_city", spacing: 24, separation: 8, salt: 20083232, reach: 4) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            guard gen.climate(x, z).e < -0.6 else { return nil }             // murk depths erosion band
            let y = YOFF - 51
            return StructureStart(kind: "ancient_city", pieces: [piece(x - 44, y - 4, z - 44, x + 44, y + 24, z + 44) { w in buildAncientCity(&w, x, y, z, seed) }],
                                  anchor: IVec3(x, y + 1, z - 20))
        }
    }

    static func buildAncientCity(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let dsb = g("deepslate_bricks"), dst = g("deepslate_tiles"), pdsl = g("polished_deepslate"), cdsl = g("cobbled_deepslate")
        let rein = g("reinforced_deepslate"), sculk = g("sculk"), vein = g("sculk_vein"), sensor = g("sculk_sensor"), shrieker = g("sculk_shrieker")
        let soulL = g("soul_lantern"), candle = g("candle"), basalt = g("smooth_basalt"), wool = g("gray_wool"), lamp = g("soul_lantern")
        // Carve the cavern and lay the plaza.
        w.fill(cx - 44, y, cz - 44, cx + 44, y + 22, cz + 44, AIR)
        w.fill(cx - 44, y - 1, cz - 44, cx + 44, y - 1, cz + 44, dst)
        for z in stride(from: cz - 44, through: cz + 44, by: 1) { for x in stride(from: cx - 44, through: cx + 44, by: 1) {
            let h = hashf(x, y, z, 0xA0C1)
            if h < 0.35 { w.set(x, y - 1, z, sculk) } else if h < 0.42 { w.set(x, y, z, vein) }
            else if h > 0.995 { w.set(x, y, z, sensor) } else if h > 0.9925 { w.set(x, y, z, shrieker) }
        } }
        // Central "portal" frame of reinforced deeprock.
        w.fill(cx - 10, y, cz - 2, cx + 10, y + 3, cz + 2, pdsl)
        w.fill(cx - 10, y + 4, cz - 1, cx - 8, y + 18, cz + 1, rein)
        w.fill(cx + 8, y + 4, cz - 1, cx + 10, y + 18, cz + 1, rein)
        w.fill(cx - 10, y + 16, cz - 1, cx + 10, y + 18, cz + 1, rein)
        w.fill(cx - 7, y + 4, cz, cx + 7, y + 15, cz, AIR)
        // Streets and buildings around: towers, halls, murk-covered ruins. Built in passes (every shell, then every
        // interior and door, then the furniture): one building at a time let a later shell wall over an earlier
        // room or doorway (structcheck: ancient city chests sealed in 3 of 9 cities).
        struct Hall { let x: Int; let z: Int; let wdt: Int; let hgt: Int; let mat: BlockID }
        var halls: [Hall] = []
        for i in 0..<14 {
            let a = Float(i) / 14 * 2 * .pi + rng.float() * 0.3
            let d = 20 + rng.float() * 18
            let bx = cx + Int(cosf(a) * d), bz = cz + Int(sinf(a) * d)
            let wdt = 3 + rng.int(4), hgt = 4 + rng.int(9)
            halls.append(Hall(x: bx, z: bz, wdt: wdt, hgt: hgt, mat: rng.chance(0.5) ? dsb : cdsl))
        }
        for h in halls { w.fill(h.x - h.wdt, y, h.z - h.wdt, h.x + h.wdt, y + h.hgt, h.z + h.wdt, h.mat) }
        for h in halls {
            w.fill(h.x - h.wdt + 1, y, h.z - h.wdt + 1, h.x + h.wdt - 1, y + h.hgt - 1, h.z + h.wdt - 1, AIR)
            w.fill(h.x - 1, y, h.z - h.wdt - 3, h.x + 1, y + 2, h.z - h.wdt, AIR)
        }
        for h in halls {
            let bx = h.x, bz = h.z, wdt = h.wdt
            w.set(bx, y + h.hgt, bz, basalt)
            w.set(bx - wdt + 1, y, bz + wdt - 1, candle + 4)
            w.set(bx + wdt - 1, y + 2, bz - wdt + 1, lamp)
            if rng.chance(0.6) { w.chest(bx, y, bz + wdt - 1, loot: "ancient_city", seed: rng.next(), facing: 0) }
            if rng.chance(0.3) { w.fill(bx - wdt + 1, y, bz - wdt + 1, bx - wdt + 2, y, bz - wdt + 2, wool) }
        }
        for k in stride(from: -40, through: 40, by: 10) { w.set(cx + k, y + 1, cz - 6, soulL); w.set(cx + k, y + 1, cz + 6, soulL) }
    }

    // MARK: Trial chambers

    static func trialChambers(_ gen: WorldGen) -> StructureType {
        StructureType(name: "trial_chambers", spacing: 34, separation: 12, salt: 94251327, reach: 3) { seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            var rng = SRng(seed)
            let y = YOFF - 40 + rng.int(21)
            return StructureStart(kind: "trial_chambers", pieces: [piece(x - 30, y - 2, z - 30, x + 30, y + 16, z + 30) { w in buildTrialChambers(&w, x, y, z, seed) }],
                                  anchor: IVec3(x, y + 1, z))
        }
    }

    static func buildTrialChambers(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed)
        let tb = g("tuff_bricks"), pt = g("polished_tuff"), ct = g("chiseled_tuff"), cu = g("waxed_cut_copper"), grate = g("waxed_copper_grate")
        let bulb = Blocks.has("waxed_copper_bulb[lit]") ? Blocks.id("waxed_copper_bulb[lit]") : g("sea_lantern")
        let spawner = g("trial_spawner"), vault = g("vault"), pot = g("decorated_pot")
        // Central atrium plus four chambers linked by corridors.
        func room(_ x: Int, _ z: Int, _ r: Int, _ h: Int) {
            w.fill(x - r, y - 1, z - r, x + r, y + h, z + r, tb)
            w.fill(x - r + 1, y, z - r + 1, x + r - 1, y + h - 1, z + r - 1, AIR)
            w.fill(x - r + 1, y - 1, z - r + 1, x + r - 1, y - 1, z + r - 1, pt)
            for (dx, dz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { w.fill(x + dx * (r - 1), y, z + dz * (r - 1), x + dx * (r - 1), y + h - 1, z + dz * (r - 1), cu) }
            w.set(x, y + h - 1, z, bulb)
            // Wall bulbs above corridor height (corridors are cut up to y+3 later).
            for off in [-(r / 2), r / 2] {
                for (dx, dz) in [(-r, off), (r, off), (off, -r), (off, r)] { w.set(x + dx, y + 4, z + dz, bulb) }
            }
        }
        // Corridor shells first, then the rooms, then the corridors are cut 3 wide through the room walls: the shells
        // used to be filled through the finished atrium (walling it into quadrants) and the second pair re-blocked
        // the first at the central crossing (structcheck: every trial chamber POI unreachable).
        let spots = [(cx + 20, cz), (cx - 20, cz), (cx, cz + 20), (cx, cz - 20)]
        func span(_ s: (Int, Int)) -> (Int, Int, Int, Int) { (min(cx, s.0), max(cx, s.0), min(cz, s.1), max(cz, s.1)) }
        for s in spots {
            let (x0, x1, z0, z1) = span(s)
            w.fill(x0 - 2, y - 1, z0 - 2, x1 + 2, y + 3, z1 + 2, tb)
        }
        room(cx, cz, 9, 12)
        for s in spots { room(s.0, s.1, 6, 7) }
        for s in spots {
            let (x0, x1, z0, z1) = span(s)
            let wx: Int = z0 == z1 ? 0 : 1, wz: Int = x0 == x1 ? 0 : 1          // widen across the corridor only
            w.fill(x0 - wx, y, z0 - wz, x1 + wx, y + 2, z1 + wz, AIR)
        }
        w.fill(cx - 3, y + 10, cz - 3, cx + 3, y + 10, cz + 3, grate)
        for (i, s) in spots.enumerated() {
            // Trial spawners and a vault in each chamber.
            for k in 0..<2 {
                let sx = s.0 + (k == 0 ? -3 : 3), sz = s.1 + 2
                w.set(sx, y, sz, spawner)
                w.spawnerEntity(sx, y, sz, mob: ["zombie", "skeleton", "spider", "husk", "stray", "cave_spider", "slime", "silverfish", "breeze", "bogged"][(i * 2 + k + rng.int(10)) % 10])
            }
            w.set(s.0, y, s.1 - 4, vault)
            w.set(s.0 + 4, y, s.1 - 4, pot)
            w.set(s.0 - 4, y, s.1 - 4, ct)
            if rng.chance(0.5) { w.chest(s.0 - 4, y, s.1 + 4, loot: "trial_chambers_corridor", seed: rng.next(), facing: 0) }
        }
        w.set(cx, y, cz, spawner)
        w.spawnerEntity(cx, y, cz, mob: "breeze")
    }

    // MARK: Ocean ruins

    static func oceanRuins(_ gen: WorldGen) -> StructureType {
        StructureType(name: "ocean_ruin", spacing: 20, separation: 8, salt: 14357621, reach: 1) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let b = gen.column(x, z).biome
            guard b.isOcean else { return nil }
            let warm = b == .warmOcean || b == .lukewarmOcean || b == .deepLukewarmOcean
            let y = gen.groundY(x, z)
            guard y < SEA - 3 else { return nil }
            return StructureStart(kind: "ocean_ruin", pieces: [piece(x - 8, y - 2, z - 8, x + 8, y + 8, z + 8) { w in
                var rng = SRng(seed)
                let big = rng.chance(0.3)
                let mat = warm ? [g("sandstone"), g("cut_sandstone"), g("chiseled_sandstone")] : [g("stone_bricks"), g("mossy_stone_bricks"), g("cracked_stone_bricks")]
                let r = big ? 7 : 4
                for yy in y...(y + (big ? 6 : 4)) { for zz in (z - r)...(z + r) { for xx in (x - r)...(x + r) {
                    let edge = abs(xx - x) == r || abs(zz - z) == r || yy == y
                    let h = hashf(xx, yy, zz, 0x0CEA)
                    if edge && h < 0.7 { w.set(xx, yy, zz, mat[Int(h * 30) % 3]) }
                } } }
                w.chest(x, y + 1, z, loot: big ? "ocean_ruin_big" : "ocean_ruin_small", seed: rng.next(), facing: 0)
                if warm { w.set(x + 2, y + 1, z + 2, g("suspicious_sand")) } else { w.set(x + 2, y + 1, z + 2, g("suspicious_gravel")) }
                w.mob("drowned", V3(Float(x) + 2.5, Float(y + 1), Float(z) - 1.5))
            }], anchor: IVec3(x, y + 1, z - 10))
        }
    }

    // MARK: Trail ruins (buried; suspicious gravel)

    static func trailRuins(_ gen: WorldGen) -> StructureType {
        StructureType(name: "trail_ruins", spacing: 34, separation: 8, salt: 83469867, reach: 1) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let b = gen.column(x, z).biome
            guard [.taiga, .snowyTaiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .oldGrowthBirchForest, .jungle].contains(b) else { return nil }
            let y = gen.groundY(x, z) - 8
            return StructureStart(kind: "trail_ruins", pieces: [piece(x - 10, y - 2, z - 10, x + 10, y + 8, z + 10) { w in
                let colors = ["brown", "red", "yellow", "orange", "light_gray", "white", "blue"].map { g("\($0)_terracotta") }
                let mud = g("mud_bricks"), grav = g("suspicious_gravel")
                for zz in (z - 9)...(z + 9) { for xx in (x - 9)...(x + 9) {
                    let h = hashf(xx, y, zz, 0x7A11)
                    w.set(xx, y, zz, h < 0.3 ? mud : colors[Int(h * 70) % colors.count])
                    if (xx - x) % 6 == 0 || (zz - z) % 6 == 0 { w.fill(xx, y + 1, zz, xx, y + 1 + Int(h * 4), zz, h < 0.5 ? mud : colors[Int(h * 30) % colors.count]) }
                    if h > 0.93 { w.set(xx, y + 1, zz, grav) }
                } }
                _ = seed
            }], anchor: IVec3(x, y + 8, z))
        }
    }

    // MARK: Fossils

    static func fossil(_ gen: WorldGen) -> StructureType {
        StructureType(name: "fossil", spacing: 8, separation: 2, salt: 9481742, reach: 1) { [unowned gen] seed, cx, cz in
            let x = cx * CS + 8, z = cz * CS + 8
            let b = gen.column(x, z).biome
            guard b == .desert || b == .swamp || b == .mangroveSwamp else { return nil }
            var rng = SRng(seed)
            guard rng.chance(0.125) else { return nil }        // ~1 in 64 chunks overall
            let y = gen.groundY(x, z) - 15 - rng.int(10)
            return StructureStart(kind: "fossil", pieces: [piece(x - 6, y - 4, z - 6, x + 6, y + 6, z + 6) { w in
                let bone = g("bone_block"), coal = g("coal_ore")
                var r = SRng(seed &+ 1)
                let spine = 5 + r.int(4)
                for k in -spine...spine { w.set(x + k, y, z, bone) }
                for k in stride(from: -spine + 1, through: spine - 1, by: 2) {
                    let ribH = 2 + r.int(3)
                    for d in 1...ribH {
                        w.set(x + k, y + d, z - 1 - d / 2, r.chance(0.9) ? bone : coal)
                        w.set(x + k, y + d, z + 1 + d / 2, r.chance(0.9) ? bone : coal)
                    }
                }
                w.fill(x + spine, y, z - 1, x + spine + 2, y + 2, z + 1, bone)
            }], anchor: IVec3(x, y + 1, z))
        }
    }
}

extension StructWriter {
    // Block entity for a proving spawner (reuses the spawner entity with the mob kind).
    mutating func spawnerEntity(_ x: Int, _ y: Int, _ z: Int, mob: String) {
        guard inside(x, y, z) else { return }
        let be = BlockEntity(.spawner)
        be.mob = mob
        be.trial = true
        entities.append((IVec3(x, y, z), be))
    }
}
