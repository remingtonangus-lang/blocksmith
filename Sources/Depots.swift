import Foundation
import simd

// P469 (Oct 26 18:35, "The fuel depot should be a replica of a GoldenEye mission site. Also, we need an ammo depot
// (should look like the weapons cache mission environment)"). The feel of a cold-war supply depot, built our own way
// (no other game's layout or names): a Greywall base whose speciality is a Fuel Depot or an Ammo Depot
// (BaseSpecialties.of its key) gets a fenced compound against its east or west wall, on ground no save had generated
// before (structure-guard-p469.txt):
//   fuel depot   a tank farm of three tall pale storage tanks in a concrete bund, a pipe rack over the road to a
//                loading gantry above a rail siding with three tank wagons, a pump house with the stores, fuel drums
//                on pallets, pumps by the road and floodlight masts
//   ammo depot   three earth-covered magazines with concrete headwalls and steel doors, crates of rounds inside, an
//                open shed and pallets of crates behind sandbags, a watchtower and a gate hut
// Both behind a chain-link fence topped with barbed wire, with a gate and a road out, and three guards of their own
// (who stand down when the base is taken: Game.depotGuardsStandDown). The speciality itself (the daily restock, the
// pumps) is the base's, as before.
enum Depots {
    static let kind = "greywall_depot"
    static let AW = 40, AD = 44                       // the compound: blocks out from the base's wall, and along it
    static let gap = 3                                // between the base's wall and the compound's fence
    static let guardHalf = 26                         // the guards' leash (half-size round the compound's middle)

    // Where a base's compound lies (x0...x1, z0...z1), if it has one.
    struct Site { let x0: Int, x1: Int, z0: Int, z1: Int, S: Int, side: Int, fuel: Bool, baseKey: String }
    static let shutter = "roller_shutter"

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: kind, spacing: Greywall.spacing, separation: Greywall.separation, salt: 77310557, reach: 10) { [unowned gen] seed, cx0, cz0 in
            guard let sc = gen.structures, let gt = sc.types.first(where: { $0.name == Greywall.kind }) else { return nil }
            let rx = floorDiv(cx0, Greywall.spacing), rz = floorDiv(cz0, Greywall.spacing)
            guard let base = sc.start(gt, regionX: rx, regionZ: rz), let site = site(gen, sc, base) else { return nil }
            let piece = Piece(min: IVec3(site.x0 - 8, site.S - 12, site.z0 - 8), max: IVec3(site.x1 + 8, site.S + 24, site.z1 + 12),
                              build: { w in build(&w, site, seed) })
            return StructureStart(kind: kind, pieces: [piece], anchor: IVec3((site.x0 + site.x1) / 2, site.S + 1, site.z1 + 2))
        }
    }

    static func site(_ gen: WorldGen, _ sc: StructureCache, _ base: StructureStart) -> Site? {
        let (cx, cz) = Greywall.centre(base)
        let key = "greywall:\(cx),\(cz)"
        let sp = BaseSpecialties.of(key)
        guard sp == .fuelDepot || sp == .ammoDepot else { return nil }
        guard sc.clear(cx: floorDiv(cx, CS), cz: floorDiv(cz, CS), reach: 8, guardSet: sc.legacyP469) else { return nil }
        let S = Greywall.yardY(base), H = Greywall.Tier.of(base).half
        let first = hashf(cx, cz, 4691, UInt32(truncatingIfNeeded: gen.seed)) < 0.5 ? 1 : -1
        for side in [first, -first] {
            let x0 = side > 0 ? cx + H + gap : cx - H - gap - AW, x1 = x0 + AW
            let z0 = cz - AD / 2, z1 = z0 + AD
            // Level enough ground (within six of the yard), no water, nothing else built there.
            var ok = true
            check: for z in stride(from: z0 - 4, through: z1 + 8, by: 6) { for x in stride(from: x0 - 4, through: x1 + 4, by: 6) {
                let c = gen.column(x, z)
                if c.biome.isOcean || c.biome == .river || c.biome == .frozenRiver || c.height <= SEA || abs(c.height - S) > 7 { ok = false; break check }
            } }
            guard ok else { continue }
            for k in ["village", "temple", "pillager_outpost", "mansion", "ruined_portal", "trail_ruins", "military_base",
                      "capital_city", "great_ruin", BorealStation.kind, "wild_camp", "mining_town"] {
                guard let o = sc.nearest(k, x: (x0 + x1) / 2, z: (z0 + z1) / 2, maxRegions: 1) else { continue }
                if o.max.x >= x0 - 10 && o.min.x <= x1 + 10 && o.max.z >= z0 - 10 && o.min.z <= z1 + 14 { ok = false; break }
            }
            guard ok else { continue }
            return Site(x0: x0, x1: x1, z0: z0, z1: z1, S: S, side: side, fuel: sp == .fuelDepot, baseKey: key)
        }
        return nil
    }

    // MARK: Build

    static func build(_ w: inout StructWriter, _ s: Site, _ seed: UInt64) {
        var rng = SRng(seed)
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let con = g("bunker_concrete"), dark = g("bunker_concrete_dark", con), steel = g("steel_plating")
        let hazard = g("hazard_plating", steel), grate = g("steel_grating", steel), rail = g("station_railing", g("iron_bars"))
        let fence = g("chain_link_fence", g("iron_bars")), wire = g("ash_wire", AIR), panel = g("light_panel")
        let lamp = g("corner_lamp", panel), door = g("bulkhead_door", g("iron_door")), crate = g("ammo_crate", steel)
        let drum = g("ash_drum", g("barrel")), box = g("ash_crate", crate), bags = g("ash_sandbags", g("gravel"))
        let ladder = g("ladder"), slab = g("bunker_concrete_slab", con), steelSlab = g("steel_plating_slab", steel)
        let fuel = g("fuel", AIR), shutterB = g(Depots.shutter, steel)
        let tank = g("depot_tank", g("white_concrete")), band = g("depot_tank_band", g("red_concrete")), tanker = g("depot_tanker", dark)
        let pipeX = g("depot_pipe_x", g("iron_bars")), pipeZ = g("depot_pipe_z", g("iron_bars")), pipeY = g("depot_pipe_y", g("iron_bars"))
        let pallet = g("spruce_slab", g("oak_slab")), pump = g("fuel_pump", steel), railB = g("rail", AIR)
        let yard = g("coarse_dirt", DIRT), road = GRAVEL, chain = g("chain", g("iron_bars"))
        let S = s.S
        // Local (a, b): a from the base's wall outward (0...AW), b along it from the north end (0...AD, the gate at AD).
        func X(_ a: Int) -> Int { s.side > 0 ? s.x0 + a : s.x1 - a }
        func Z(_ b: Int) -> Int { s.z0 + b }
        func put(_ a: Int, _ y: Int, _ b: Int, _ blk: BlockID) { w.set(X(a), S + y, Z(b), blk) }
        func fill(_ a0: Int, _ y0: Int, _ b0: Int, _ a1: Int, _ y1: Int, _ b1: Int, _ blk: BlockID) {
            let xa = min(X(a0), X(a1)), xb = max(X(a0), X(a1))
            w.fill(xa, S + y0, Z(min(b0, b1)), xb, S + y1, Z(max(b0, b1)), blk)
        }
        // Along a: the x axis, mirrored on the west side (a pipe or rail along a is along x either way). A ladder's
        // state hugs the wall it climbs (2: the wall at +x, 3: at -x).
        let wallLowerA = BlockID(s.side > 0 ? 3 : 2), wallHigherA = BlockID(s.side > 0 ? 2 : 3)

        // MARK: Ground: cleared, levelled, banked into the land round it
        let lx0 = max(s.x0 - 1, w.bx), lx1 = min(s.x1 + 1, w.bx + CS - 1), lz0 = max(s.z0 - 1, w.bz), lz1 = min(s.z1 + 1, w.bz + CS - 1)
        if lx0 <= lx1 && lz0 <= lz1 {
            for z in lz0...lz1 { for x in lx0...lx1 {
                w.fill(x, S + 1, z, x, S + 24, z, AIR)
                w.groundDown(x, S - 1, z, DIRT, minY: S - 30, reach: 30)
                w.setGround(x, S, z, yard)
            } }
        }
        w.bermRect(s.x0 - 1, s.z0 - 1, s.x1 + 1, s.z1 + 1, floor: S, reach: 6)
        // The road: in at the gate, up the middle, and out to the land (one block a step, like the base's gate road).
        let ra = 17, rb = 21
        for a in ra...rb { for b in 2...AD { put(a, 0, b, road) } }
        for a in (ra - 1)...(rb + 1) { for k in 1...10 {
            let x = X(a), z = s.z1 + k
            guard w.inside(x, S, z) else { continue }
            var top = S - 12
            for y in stride(from: S + 14, through: S - 12, by: -1) where Blocks.collide[Int(w.get(x, y, z))] && !CapitalBase.isLeaf(w.get(x, y, z)) {
                top = y; break
            }
            let h = S + max(-k, min(k, top - S))
            w.fill(x, h + 1, z, x, S + 16, z, AIR)
            w.groundDown(x, h - 1, z, DIRT, minY: h - 14)
            w.setGround(x, h, z, a >= ra && a <= rb ? road : DIRT)
        } }

        // MARK: Fence: chain link on concrete posts, barbed wire along the top, a gate onto the road
        for a in 0...AW { for b in 0...AD where a == 0 || a == AW || b == 0 || b == AD {
            if b == AD && a >= ra && a <= rb { continue }
            let post = (a + b) % 6 == 0 || (b == AD && (a == ra - 1 || a == rb + 1))
            for y in 1...3 { put(a, y, b, post ? con : fence) }
            if !post { put(a, 4, b, wire) } else { put(a, 4, b, slab) }
        } }
        for a in [ra - 1, rb + 1] { put(a, 4, AD, steel); put(a, 5, AD, lamp) }
        for a in ra...rb { put(a, 5, AD, hazard) }                    // the gate's steel lintel, hazard-striped
        // Floodlight masts at two corners.
        for (a, b) in [(2, 2), (AW - 2, AD - 6)] {
            for y in 1...9 { put(a, y, b, steel) }
            put(a, 10, b, panel); put(a + 1, 9, b, lamp); put(a - 1, 9, b, lamp)
        }

        // MARK: The fuel depot
        func fuelDepot() {
            // The bund: a low concrete wall round the tank farm, open to the road at each tank.
            for b in 2...42 { for a in 1...15 where a == 1 || a == 15 || b == 2 || b == 42 {
                if a == 15 && [8, 21, 34].contains(where: { abs($0 - b) <= 1 }) { continue }
                put(a, 1, b, dark)
            } }
            for a in 2...14 { for b in 3...41 { put(a, 0, b, con) } }
            // Three tall tanks, radius 5, eleven high: pale steel, a red band, a railed roof, a caged ladder.
            for (k, tb) in [8, 21, 34].enumerated() {
                let ta = 8, R: Float = 5.2, top = 11
                for b in (tb - 6)...(tb + 6) { for a in (ta - 6)...(ta + 6) {
                    let d = (Float(a - ta) * Float(a - ta) + Float(b - tb) * Float(b - tb)).squareRoot()
                    guard d <= R else { continue }
                    let shell = d > R - 1.15
                    for y in 1...top {
                        // P478: full to two below the roof with fuel (a bucket dips it through the hatch).
                        if shell { put(a, y, b, y == 8 ? band : tank) } else if y == top { put(a, y, b, tank) } else { put(a, y, b, y <= top - 2 ? fuel : AIR) }
                    }
                    if shell { put(a, top + 1, b, rail) }
                    if !shell && d < 1.2 { put(a, top + 1, b, k == 1 ? pipeY : steel) }       // a vent on the roof
                } }
                // The ladder up the face toward the road, and a hatch on top.
                for y in 1...top { put(ta + 6, y, tb, ladder + wallLowerA) }
                put(ta + 5, top + 1, tb, AIR)
                put(ta + 4, top, tb, AIR)                                   // (the hatch, open: P478)
                // A pipe out of the tank's foot to the road (beside the ladder), up over it on the rack.
                for a in (ta + 5)...16 { put(a, 2, tb + 2, pipeX) }
            }
            // The pipe rack: steel bents either side of the road, the pipes across at six up, on to the gantry.
            for tb in [10, 23, 36] {
                for y in 3...5 { put(16, y, tb, pipeY) }
                for a in 16...29 { put(a, 6, tb, pipeX) }
                for y in 1...5 { put(rb + 2, y, tb + 1, steel) }
                put(rb + 2, 6, tb + 1, steelSlab)
            }
            for b in 10...36 { put(29, 6, b, pipeZ) }                   // the header along the gantry
            // The rail siding along the far side, buffer stops at both ends, three tank wagons on it.
            let ta0 = 34
            for b in 3...41 { put(ta0, 1, b, railB); for a in (ta0 - 1)...(ta0 + 1) { put(a, 0, b, road) } }   // (on ballast: main-line track)
            for b in [2, 42] { put(ta0, 1, b, dark); put(ta0, 2, b, hazard) }
            for wb in [5, 15, 25] {
                let len = 8
                for b in wb..<(wb + len) {
                    let end = b == wb || b == wb + len - 1
                    if b == wb + 1 || b == wb + len - 2 { put(ta0 - 1, 2, b, dark); put(ta0 + 1, 2, b, dark) }     // bogies
                    put(ta0, 3, b, steel); put(ta0 - 1, 3, b, steelSlab); put(ta0 + 1, 3, b, steelSlab)
                    guard !end else { continue }
                    for a in (ta0 - 1)...(ta0 + 1) { put(a, 4, b, tanker); put(a, 6, b, tanker) }
                    for a in (ta0 - 2)...(ta0 + 2) { put(a, 5, b, tanker) }
                }
                put(ta0, 7, wb + len / 2, steel)                         // the dome
                put(ta0 + 3, 4, wb + len - 2, ladder + wallLowerA)
            }
            // The loading gantry: a steel tower by the siding, a deck over the wagons, hoses down to the domes.
            for b in 6...36 {
                for y in 1...8 where b % 6 == 0 { put(30, y, b, steel); put(38, y, b, steel) }
                for a in 30...38 { put(a, 9, b, grate) }
                put(30, 10, b, rail); put(38, 10, b, rail)
            }
            for y in 1...8 { put(31, y, 6, ladder + wallLowerA) }
            put(31, 9, 6, AIR)
            for wb in [5, 15, 25] { put(ta0, 9, wb + 4, steel); put(ta0, 8, wb + 4, chain) }
            for b in stride(from: 9, through: 33, by: 8) { put(34, 8, b, panel) }
            // Pumps by the road for his vehicles.
            for b in [27, 29] { put(rb + 1, 1, b, pump) }
            // Fuel drums on pallets.
            for (a0, b0) in [(23, 3), (23, 10)] {
                for a in a0...(a0 + 3) { for b in b0...(b0 + 3) {
                    put(a, 1, b, pallet)
                    if (a + b) % 5 != 0 { put(a, 2, b, drum); if a < a0 + 2 && b < b0 + 3 { put(a, 3, b, drum) } }
                } }
            }
            // The pump house: concrete, a steel roof, the stores inside.
            let ha0 = 22, ha1 = 28, hb0 = 37, hb1 = 43
            for a in ha0...ha1 { for b in hb0...hb1 {
                let wall = a == ha0 || a == ha1 || b == hb0 || b == hb1
                put(a, 0, b, con)
                for y in 1...4 { put(a, y, b, wall ? (y == 1 ? dark : con) : AIR) }
                put(a, 5, b, steelSlab)
            } }
            put(ha0, 1, 40, door + BlockID(2)); put(ha0, 2, 40, door + BlockID(2 + 8))
            for b in [39, 41] { put(ha1, 3, b, g("armored_glass", GLASS)) }
            put(25, 4, 40, panel)
            w.chest(X(ha1 - 1), S + 1, Z(hb0 + 1), loot: "depot_fuel", seed: rng.next(), facing: 0)
            w.chest(X(ha1 - 1), S + 1, Z(hb1 - 1), loot: "depot_fuel", seed: rng.next(), facing: 1)
            for b in (hb0 + 2)...(hb1 - 3) { put(ha1 - 1, 1, b, drum) }
            put(ha0 + 1, 1, hb0 + 1, pump)
        }

        // MARK: The ammo depot
        func ammoDepot() {
            // Three earth-covered magazines along the base's side of the road: an arched concrete vault, buried,
            // its headwall facing the road with a steel door.
            for mb in [8, 22, 36] {
                // The mound: seven up over the vault, falling a block a step to each side and to the back.
                for b in (mb - 7)...(mb + 7) { for a in 1...13 {
                    let side = max(0, abs(b - mb) - 4), back = max(0, 3 - a)
                    let h = 7 - side - back
                    guard h >= 1 else { continue }
                    for y in 1...h { put(a, y, b, y == h ? GRASS : DIRT) }
                } }
                // The vault: concrete shell, a round-topped room 7 wide and 10 deep inside.
                for b in (mb - 4)...(mb + 4) { for a in 2...13 {
                    let off = abs(b - mb)
                    let roof = off <= 2 ? 5 : (off == 3 ? 4 : 3)
                    for y in 0...(roof + 1) {
                        let inner = a <= 12 && a >= 3 && off <= 3 && y >= 1 && y <= roof - (off == 3 ? 1 : 0)
                        put(a, y, b, inner ? AIR : con)
                    }
                } }
                for b in (mb - 3)...(mb + 3) { for a in 3...12 { put(a, 0, b, abs(b - mb) == 0 ? hazard : g("bunker_floor", con)) } }
                // The headwall: proud of the mound, wing walls stepping down, a steel door, a lamp over it.
                for b in (mb - 6)...(mb + 6) {
                    let off = abs(b - mb)
                    let hh = off <= 4 ? 7 : 7 - (off - 4) * 2
                    for y in 1...hh { put(13, y, b, off <= 4 && y == hh ? slab : con) }
                    // (P507: a roller shutter three wide and three high, the headwall's man door was a steel door)
                    if off <= 1 { for y in 1...3 { put(13, y, b, shutterB) } }
                }
                for b in (mb - 1)...(mb + 1) { put(14, 0, b, con) }
                put(14, 5, mb, lamp); put(13, 4, mb - 2, hazard); put(13, 4, mb + 2, hazard)
                // Inside: crates of rounds down both walls, two chests at the back, a light in the crown.
                for a in 4...11 { for b in [mb - 3, mb + 3] {
                    put(a, 1, b, a % 3 == 0 ? box : crate)
                    if a % 2 == 0 { put(a, 2, b, crate) }
                } }
                w.chest(X(3), S + 1, Z(mb - 1), loot: "depot_ammo", seed: rng.next(), facing: s.side > 0 ? 3 : 2)
                w.chest(X(3), S + 1, Z(mb + 1), loot: "depot_ammo", seed: rng.next(), facing: s.side > 0 ? 3 : 2)
                put(7, 5, mb, panel); put(10, 5, mb, panel)
            }
            // The open shed: steel posts, a steel roof, pallets of crates under it.
            let sa0 = 24, sa1 = 36, sb0 = 26, sb1 = 38
            for a in sa0...sa1 { for b in sb0...sb1 {
                put(a, 0, b, con)
                if (a == sa0 || a == sa1) && (b - sb0) % 4 == 0 { for y in 1...4 { put(a, y, b, steel) } }
                put(a, 5, b, steelSlab)
            } }
            for a in stride(from: sa0 + 2, through: sa1 - 2, by: 3) { for b in stride(from: sb0 + 1, through: sb1 - 2, by: 4) {
                for da in 0...1 { for db in 0...2 {
                    put(a + da, 1, b + db, pallet)
                    put(a + da, 2, b + db, (da + db) % 2 == 0 ? crate : box)
                    if db < 2 { put(a + da, 3, b + db, crate) }
                } }
            } }
            put(30, 4, 32, panel)
            // Pallets of crates in the open, walled with sandbags.
            for (a0, b0) in [(24, 12), (31, 12)] {
                for a in (a0 - 1)...(a0 + 5) { for b in (b0 - 1)...(b0 + 8) where a == a0 - 1 || a == a0 + 5 || b == b0 - 1 || b == b0 + 8 {
                    if b == b0 + 8 && a == a0 + 2 { continue }
                    put(a, 1, b, bags); if (a + b) % 2 == 0 { put(a, 2, b, bags) }
                } }
                for a in a0...(a0 + 3) { for b in b0...(b0 + 6) {
                    put(a, 1, b, pallet)
                    if (a * 3 + b) % 4 != 0 { put(a, 2, b, crate); if (a + b) % 3 == 0 { put(a, 3, b, box) } }
                } }
            }
            // The watchtower: four steel legs, a sandbagged deck, a lamp, a ladder.
            let wa = 36, wb = 6
            for (da, db) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { for y in 1...7 { put(wa + da, y, wb + db, steel) } }
            for da in -2...2 { for db in -2...2 {
                put(wa + da, 8, wb + db, grate)
                if abs(da) == 2 || abs(db) == 2 { put(wa + da, 9, wb + db, bags) }
            } }
            for db in -1...1 { put(wa - 2, 9, wb + db, AIR) }
            for y in 1...8 { put(wa - 2, y, wb, ladder + wallHigherA) }
            put(wa - 2, 9, wb, AIR)
            for (da, db) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { put(wa + da, 10, wb + db, steel) }
            for da in -1...1 { for db in -1...1 { put(wa + da, 11, wb + db, steelSlab) } }
            put(wa, 10, wb, lamp)
            // The gate hut.
            let ga0 = 23, ga1 = 27, gb0 = 38, gb1 = 42
            for a in ga0...ga1 { for b in gb0...gb1 {
                let wall = a == ga0 || a == ga1 || b == gb0 || b == gb1
                put(a, 0, b, con)
                for y in 1...3 { put(a, y, b, wall ? (y == 2 && (a + b) % 2 == 1 ? g("armored_glass", GLASS) : con) : AIR) }
                put(a, 4, b, slab)
            } }
            put(ga0, 1, 40, door + BlockID(2)); put(ga0, 2, 40, door + BlockID(2 + 8))
            put(25, 3, 40, panel)
            w.chest(X(ga1 - 1), S + 1, Z(gb0 + 1), loot: "depot_ammo", seed: rng.next(), facing: 0)
        }

        if s.fuel { fuelDepot() } else { ammoDepot() }

        // MARK: Guards (their own leash: the compound)
        let mx = (s.x0 + s.x1) / 2, mz = (s.z0 + s.z1) / 2
        let tag = "~\(mx),\(mz),\(guardHalf)"
        func guardAt(_ k: String, _ a: Int, _ y: Int, _ b: Int) { w.mob("\(k)@grey\(tag)", V3(Float(X(a)) + 0.5, Float(S + y), Float(Z(b)) + 0.5)) }
        guardAt("soldier_trooper", ra - 1, 1, AD - 4)
        guardAt("soldier_trooper", rb + 1, 1, 18)
        if s.fuel { guardAt("soldier_marksman", 34, 10, 18) } else { guardAt("soldier_marksman", 36, 9, 6) }
    }

    // MARK: Loot (Greywall.loot reads these)

    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "depot_ammo": (4...7, [("greywall_rounds", 16, 48, 20), ("rifle_rounds", 12, 32, 14), ("shotgun_shells", 8, 24, 10),
                               ("heavy_rounds", 6, 16, 12), ("gunpowder", 4, 12, 10), ("tnt", 1, 4, 6), ("iron_ingot", 2, 8, 6)]),
        "depot_fuel": (3...5, [("fuel_can", 1, 3, 20), ("coal", 8, 24, 12), ("iron_ingot", 2, 6, 8), ("capital_ration", 2, 4, 8),
                               ("bucket", 1, 1, 4), ("gunpowder", 2, 6, 4)]),
    ]
}

// MARK: Ground round the compound

extension StructWriter {
    // P469: StructWriter.berm for a rectangle: columns outside (x0...x1, z0...z1), at ring distance d = 1...reach, are
    // banked up to floor - d with the ground they stand on.
    func bermRect(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, floor fy: Int, reach: Int) {
        for lz in 0..<CS { for lx in 0..<CS {
            let x = bx + lx, z = bz + lz
            let d = max(x0 - x, x - x1, z0 - z, z - z1)
            guard d >= 1 && d <= reach else { continue }
            let top = fy - d
            guard top > 2 && top < CH - 2 else { continue }
            var y = top, wet = 0
            while y > max(1, top - 40) {
                let b = blocks[Chunk.index(lx, y, lz)]
                if b == WATER { wet += 1 }
                else if b != AIR && !(Blocks.replaceable[Int(b)] && Blocks.fluidKind[Int(b)] == 0) { break }
                y -= 1
            }
            guard y < top, wet <= 3 else { continue }
            let g = blocks[Chunk.index(lx, y, lz)]
            guard Blocks.opaque[Int(g)] && Blocks.collide[Int(g)] && Blocks.fluidKind[Int(g)] == 0 else { continue }
            let sandy = g == SAND || g == SANDSTONE || wet > 0, snowy = !sandy && (g == SNOWY_GRASS || g == SNOW)
            guard sandy || snowy || g == GRASS || g == DIRT || g == STONE || g == COBBLE else { continue }
            let cap = sandy ? SAND : (snowy ? SNOWY_GRASS : GRASS), fill = sandy ? SAND : DIRT
            if g == GRASS || g == SNOWY_GRASS { blocks[Chunk.index(lx, y, lz)] = DIRT }
            for yy in (y + 1)...top { blocks[Chunk.index(lx, yy, lz)] = yy == top ? cap : fill }
        } }
    }
}

// MARK: Guards stand down

extension Game {
    // A base taken: its depot's own guards lay down their arms (they never held the keep, so the capture didn't wait
    // for them; nothing in the compound should keep shooting at the base's new owner).
    func depotGuardsStandDown(_ cx: Int, _ cz: Int, _ half: Int) {
        let reach = Float(half + Depots.gap + Depots.AW + 8)
        mobs.mobs.removeAll { m in
            m.faction == Faction.greywall.rawValue && m.kind != .deckGun && m.leash != nil
                && abs(m.pos.x - Float(cx)) < reach && abs(m.pos.z - Float(cz)) < Float(Depots.AD / 2 + 10)
                && max(abs(m.pos.x - Float(cx)), abs(m.pos.z - Float(cz))) > Float(half) + 2
        }
    }
}

// MARK: Blocks and looks

extension BlockRegistry {
    func registerDepotBlocks() {
        if !has("chain_link_fence") {
            var d = BlockDef("chain_link_fence", "Chain-Link Fence")
            d.tex = ["chain_link"]; d.render = .connect; d.connect = 2; d.layer = .cutout; d.opaque = false
            d.hardness = 4; d.tool = .pickaxe; d.sound = .metal; d.skyStop = false
            add(d)
        }
        for (n, label, tex) in [("depot_tank", "Storage Tank Plate", "depot_tank"), ("depot_tank_band", "Storage Tank Band", "depot_tank_band"),
                                ("depot_tanker", "Tank Wagon Plate", "depot_tanker")] where !has(n) {
            var d = BlockDef(n, label)
            d.tex = [tex]; d.hardness = 5; d.tool = .pickaxe; d.requiresTool = true; d.sound = .metal
            add(d)
        }
        // P507 (Nov 1 12:33:06 at an ammo depot's magazines: "There should be like garage doors here, 'cause that's what
        // it's like in [that] depot"): a steel roller shutter. Closed, a wall of slats; used, every shutter cell joined
        // to it rolls up into its housing at the top of the opening (Game.rollShutter), and down again.
        if !has(Depots.shutter) {
            var d = BlockDef(Depots.shutter, "Roller Shutter")
            d.tex = ["roller_shutter"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = true
            d.boxes = [Box(0, 0, 0, 16, 16, 16)]; d.hardness = 6; d.resistance = 12; d.tool = .pickaxe; d.requiresTool = true; d.sound = .metal
            d.group = Depots.shutter
            add(d)
            var o = d
            o.name = Depots.shutter + "[open]"; o.hidden = true; o.skyStop = false
            o.boxes = [Box(0, 13, 0, 16, 16, 16)]
            add(o)
        }
        // Pipes, along x, along z and upright: a galvanised pipe six sixteenths thick through the middle.
        for (n, b) in [("depot_pipe_x", Box(0, 5, 5, 16, 11, 11)), ("depot_pipe_z", Box(5, 5, 0, 11, 11, 16)), ("depot_pipe_y", Box(5, 0, 5, 11, 16, 11))] where !has(n) {
            var d = BlockDef(n, "Pipe")
            d.tex = ["depot_pipe"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            d.boxes = [b]; d.hardness = 3; d.tool = .pickaxe; d.sound = .metal
            add(d)
        }
    }
}

extension TextureGen {
    static func depotPainters(_ p: inout [String: Painter]) {
        // Chain link: a diamond mesh of galvanised wire, open between.
        p["chain_link"] = { x, y in
            if (x + y) % 4 == 0 || (x - y + 16) % 4 == 0 { return hex(0x9AA2A8, 0.9 + 0.12 * r(x, y, 4691)) }
            if y == 0 || y == 15 { return hex(0x7E868C) }
            return V4(0, 0, 0, 0)
        }
        // A storage tank's plate: pale painted steel, a weld seam at the top, a faint streak of weather down it.
        p["depot_tank"] = { x, y in
            if y == 15 { return hex(0xB8BCBE) }
            let streak: Float = x % 7 == 3 ? 0.95 : 1
            return hex(0xDADDDA, streak * (0.97 + 0.03 * r(x / 2, y / 3, 4692)))
        }
        // Its band: signal red with a white stripe.
        p["depot_tank_band"] = { x, y in
            if y >= 6 && y <= 9 { return hex(0xE8E8E2) }
            return hex(0xB3261E, 0.95 + 0.05 * r(x / 2, y, 4693))
        }
        // A tank wagon: black-grey steel, a weld seam, grime toward the bottom.
        p["depot_tanker"] = { x, y in
            if y == 0 { return hex(0x1E2124) }
            return hex(0x3A3F44, (0.94 + 0.05 * r(x / 3, y / 2, 4694)) * (1 - Float(y) * 0.008))
        }
        // A roller shutter's slats: ribbed grey steel, a dark seam every fourth row.
        p["roller_shutter"] = { x, y in
            if y % 4 == 3 { return hex(0x4A5056) }
            return hex(y % 4 == 0 ? 0x9AA2A8 : 0x80888E, 0.95 + 0.05 * r(x / 4, y, 4696))
        }
        p["depot_pipe"] = { x, y in
            if y % 8 == 0 { return hex(0x6F7880) }
            return hex(0xA4ACB2, 0.93 + 0.07 * r(x / 4, y, 4695))
        }
    }
}
