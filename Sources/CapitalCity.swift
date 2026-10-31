import Foundation
import simd

// Capital cities (task 23): the Capital's civilian towns, an original look in the spirit Remington asked for (a calm,
// low, white garden city): long flat white buildings of one or two storeys with deep roof overhangs and window
// bands (no towers), grey paved plazas, trees in white planters, outdoor seating under umbrellas, and covered
// walkways that follow the ground between terraces. A city is a grid of up to 32 lots (32 blocks each, a 6-block
// walkway on two sides); every lot is a flat terrace at its own height (neighbours differ by at most 4), the
// walkways ramp between them in half-block steps, entrance ramps lead from the walkways onto the terraces.
// Lots: civic plaza with a fountain at the centre, buildings (entrance hall, offices, a café terrace), plazas
// (planters, benches, seating) and gardens (lawns, trees, hedges, crossing paths). Capital soldiers keep watch.
// Structure key "capital_city"; one candidate per 56 x 56-chunk region, on open temperate ground away from
// citadels and villages and clear of ground a saved world had already generated (StructureCache.legacy).

extension BlockRegistry {
    func registerCapitalCityBlocks() {
        if !has("capital_paving") {
            var d = BlockDef("capital_paving", "Capital Paving")
            d.tex = ["capital_paving"]; d.hardness = 2; d.resistance = 6; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
            add(d)
            family("capital_paving", "capital_paving", "Capital Paving", h: 2, tool: .pickaxe, req: true, snd: .stone, stairs: false, slab: true, fence: false, wall: false)
        }
        // P462 (Oct 25 16:31, his Capital City: "I want it to be more New Alexandria looking... Reminds me of Greek
        // architecture too much"): the glass curtain walls and the dark steel of the towers that replaced the white
        // colonnades.
        if !has("capital_steel") {
            var d = BlockDef("capital_steel", "Capital Steel")
            d.tex = ["capital_steel"]; d.hardness = 5; d.resistance = 12; d.tool = .pickaxe; d.requiresTool = true; d.sound = .metal
            add(d)
            family("capital_steel", "capital_steel", "Capital Steel", h: 5, tool: .pickaxe, req: true, snd: .metal, stairs: true, slab: true, fence: false, wall: false)
        }
        if !has("capital_curtain") {
            var d = BlockDef("capital_curtain", "Capital Curtain Glass")
            // P499 (Oct 30 20:00, "this has got to be glass, glass buildings, not whatever that blue is"; 20:02 "gray, dark
            // tinted windows"): drawn blended, as clear glass is (as a cutout its 60 % blue drew solid).
            d.tex = ["capital_curtain"]; d.opaque = false; d.layer = .translucent; d.cullSame = true; d.aoOcc = false
            d.hardness = 0.6; d.resistance = 2; d.sound = .glass
            add(d)
        }
    }
}

extension TextureGen {
    static func capitalCityPainters(_ p: inout [String: Painter]) {
        // Large grey pavers: two slabs per block, a fine darker joint, a faint speckle.
        p["capital_paving"] = { x, y in
            if y == 15 || x == 15 || (y == 7 && x < 15) { return hex(0x8A8F94) }
            return hex(0xA9AEB3, 0.96 + 0.03 * r(x / 4, y / 4 + (y > 7 ? 9 : 0), 2501) + 0.02 * r(x, y, 2502))
        }
        // Satin steel panels, blue-grey: a fine brushed grain, a light edge on top, a dark joint at the bottom.
        p["capital_steel"] = { x, y in
            if y == 0 { return hex(0x8D96A1) }
            if y == 15 { return hex(0x3A4048) }
            return hex(0x5C6672, 0.95 + 0.04 * r(0, y, 2511) + 0.02 * r(x / 2, y, 2512))
        }
        // Curtain glass: one even sheet of dark grey tinted glass, the faintest ripple and a soft diagonal sheen (no frame
        // inside it: the steel mullions and the white floor bands frame the panes).
        p["capital_curtain"] = { x, y in
            let k = 0.97 + 0.03 * r(x / 4, y / 4, 2513)
            let sheen: Float = abs(x - y) <= 1 && x > 3 && x < 12 ? 0.1 : 0
            return V4(0.2 * k + sheen, 0.22 * k + sheen, 0.24 * k + sheen, 0.55 + sheen)
        }
    }
}

enum CapitalCity {
    static let lot = 32, street = 6, N = 3              // lots -N..<N on both axes (192 blocks across)
    static let biomes: Set<Biome> = [.plains, .sunflowerPlains, .meadow, .forest, .flowerForest, .birchForest, .savanna, .taiga, .cherryGrove]

    // The city plan, shared by its pieces (one per lot).
    final class Plan {
        let ox: Int, oz: Int                             // world x, z of lot (-N, -N)'s corner
        var level = [Int](repeating: Int.min, count: 4 * N * N)   // terrace floor y per lot (Int.min: no lot)
        var kind = [UInt8](repeating: 0, count: 4 * N * N)        // 0 building, 1 plaza, 2 garden, 3 civic centre
        var covered = [Bool](repeating: false, count: 8 * N * N)  // walkway strips with a canopy: [lot * 2 + (0 west, 1 north)]
        var shops = [[ShopKind]](repeating: [], count: 4 * N * N) // market lots (kind 4): the two storefronts, west then east
        var flat = [Bool](repeating: false, count: 4 * N * N)     // building lots (kind 0) that are flats, not offices
        var seed: UInt64 = 0                                      // the world seed (lot seeds, CapitalTown)
        var size = 2                                              // G12: 0 small (16 lots), 1 medium (24), 2 large (32)
        var modern = false                                        // P462: glass and steel towers (ground no save had before it)
        init(ox: Int, oz: Int) { self.ox = ox; self.oz = oz }
        @inline(__always) func idx(_ i: Int, _ j: Int) -> Int { (j + N) * 2 * N + (i + N) }
        func has(_ i: Int, _ j: Int) -> Bool { i >= -N && i < N && j >= -N && j < N && level[idx(i, j)] != Int.min }
        func lv(_ i: Int, _ j: Int) -> Int? { has(i, j) ? level[idx(i, j)] : nil }
        // Walkway height (half blocks): the lot centre levels interpolated bilinearly (missing lots take the
        // nearest present corner), so the paths rise and fall with the terraces.
        func walkHalf(_ x: Int, _ z: Int) -> Int {
            let cu = Float(x - ox - street - 13) / Float(lot), cv = Float(z - oz - street - 13) / Float(lot)
            let i0 = Int(floorf(cu)) - N, j0 = Int(floorf(cv)) - N
            let tu = cu - floorf(cu), tv = cv - floorf(cv)
            var c: [Float?] = [lv(i0, j0).map(Float.init), lv(i0 + 1, j0).map(Float.init), lv(i0, j0 + 1).map(Float.init), lv(i0 + 1, j0 + 1).map(Float.init)]
            let any: Float = c.compactMap { $0 }.first ?? 0
            for k in 0..<4 where c[k] == nil { c[k] = any }
            let a: Float = c[0]! + (c[1]! - c[0]!) * tu
            let b: Float = c[2]! + (c[3]! - c[2]!) * tu
            let h: Float = a + (b - a) * tv
            return Int((h * 2).rounded())
        }
    }

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: "capital_city", spacing: 56, separation: 20, salt: 51829403, reach: 8) { [unowned gen] seed, cx0, cz0 in
            // The region's spot, then up to five more in its placement square (36 x 36 chunks, so the spacing holds).
            let rx = floorDiv(cx0, 56), rz = floorDiv(cz0, 56), s32 = UInt32(truncatingIfNeeded: seed)
            for k in 0...5 {
                let cx = k == 0 ? cx0 : rx * 56 + Int(hashf(rx, rz, 7300 + k, s32) * 35.99)
                let cz = k == 0 ? cz0 : rz * 56 + Int(hashf(rx, rz, 7400 + k, s32) * 35.99)
                if let s = CapitalCity.site(gen, seed, cx, cz) {
                    return WorldRules.capitalAllowed(gen, cx, cz) && WorldRules.capitalApart(gen, s, rx, rz, cx, cz) ? s : nil
                }
            }
            return nil
        }
    }

    static func site(_ gen: WorldGen, _ seed: UInt64, _ cx: Int, _ cz: Int) -> StructureStart? {
            guard let sc = gen.structures, sc.clear(cx: cx, cz: cz, reach: 9), let plan = planFor(gen, seed, cx, cz) else { return nil }
            plan.modern = sc.clear(cx: cx, cz: cz, reach: 9, guardSet: sc.legacyP462)
            let top = plan.modern ? 64 : 48
            var pieces: [Piece] = []
            for j in -N..<N { for i in -N..<N where plan.has(i, j) {
                let x0 = plan.ox + (i + N) * lot, z0 = plan.oz + (j + N) * lot
                let L = plan.lv(i, j)!
                let ex = plan.has(i + 1, j) ? 0 : street, ez = plan.has(i, j + 1) ? 0 : street
                let m = 6                                    // margin for clearing leaves of trees cut at the edge
                let pseed = lotSeed(seed, i, j)
                pieces.append(Piece(min: IVec3(x0 - m, L - 40, z0 - m), max: IVec3(x0 + lot - 1 + ex + m, L + top, z0 + lot - 1 + ez + m),
                                    build: { w in CapitalCity.buildLot(&w, plan, i, j, pseed) }))
            } }
            let L0 = plan.lv(0, 0)!
            let start = StructureStart(kind: "capital_city", pieces: pieces, anchor: IVec3(plan.ox + N * lot + street + 3, L0 + 1, plan.oz + N * lot + street + 3))
            start.plan = plan
            start.far = farBoxes(plan)
            return start
    }

    // P483: the city for the far land (LandmarkRender): every lot's terrace, and on a building lot the building as
    // buildLot raises it (the same lot seed: footprint first, then a tower's floors).
    static func farBoxes(_ plan: Plan) -> [(min: IVec3, max: IVec3, tone: FarTone)] {
        var out: [(min: IVec3, max: IVec3, tone: FarTone)] = []
        for j in -N..<N { for i in -N..<N where plan.has(i, j) {
            let x0 = plan.ox + (i + N) * lot, z0 = plan.oz + (j + N) * lot
            let L = plan.lv(i, j)!
            out.append((IVec3(x0 + street, L - 3, z0 + street), IVec3(x0 + lot - 1, L, z0 + lot - 1), .paving))
            guard plan.kind[plan.idx(i, j)] == 0 else { continue }
            var rng = SRng(lotSeed(plan.seed, i, j) | 1)
            let fp = footprint(x0, z0, &rng)
            let a = IVec3(fp.bx0, L + 1, fp.bz0)
            if plan.modern {
                let floors = CapitalTown.isResidence(plan, i, j) ? 3 + rng.int(3) : 4 + rng.int(6)
                out.append((a, IVec3(fp.bx0 + fp.bw - 1, L + floors * 5, fp.bz0 + fp.bd - 1), .glass))
            } else {
                out.append((a, IVec3(fp.bx0 + fp.bw - 1, L + fp.storeys * 5, fp.bz0 + fp.bd - 1), .white))
            }
        } }
        return out
    }

    // The city plan for a centre chunk corner (nil: the ground or the neighbours won't have a city there); kept on the
    // structure start (StructureStart.plan) for CapitalTown and its checks.
    static func planFor(_ gen: WorldGen, _ seed: UInt64, _ cx: Int, _ cz: Int) -> Plan? {
            guard let sc = gen.structures else { return nil }
            let x = cx * CS, z = cz * CS                 // the city centre (a chunk corner: lots line up with chunks)
            let c = gen.column(x, z)
            guard CapitalCity.biomes.contains(c.biome), c.height > SEA + 2 else { return nil }
            // Clear of citadels and villages.
            // R22: and off temples and outposts (their pieces under a lot), on ground no save has seen before R22.
            let fresh = sc.clear(cx: floorDiv(x, CS), cz: floorDiv(z, CS), reach: 10, guardSet: sc.legacyR22)
            for k in fresh ? ["military_base", "village", "temple", "pillager_outpost"] : ["military_base", "village"] {
                if let s = sc.nearest(k, x: x, z: z, maxRegions: 1) {
                    let d = simd_length(V2(Float((s.min.x + s.max.x) / 2 - x), Float((s.min.z + s.max.z) / 2 - z)))
                    if d < (k == "temple" || k == "pillager_outpost" ? 150 : 240) { return nil }
                }
            }
            let plan = Plan(ox: x - N * lot, oz: z - N * lot)
            // G12: each city draws its size (small 16 lots, medium 24, large 32) and its mix of lot uses from the pool
            // (an office quarter, a park city, squares), so no two read alike. Ground saved before G12 keeps the
            // old plan (every city large, the one mix).
            let varied = !WorldRules.capitalLegacy(gen, floorDiv(cx, 56), floorDiv(cz, 56))
            var mix = SRng(seed ^ 0x612C)
            let sizeRoll = mix.float()
            let size: Float = !varied ? 1.1 : (sizeRoll < 0.4 ? 0.5 : (sizeRoll < 0.75 ? 0.75 : 1.1))
            plan.size = size < 0.6 ? 0 : (size < 1 ? 1 : 2)
            let need = size < 0.6 ? 10 : (size < 1 ? 14 : 18)
            var terrain = [Int](repeating: 0, count: 4 * N * N)
            var count = 0
            for j in -N..<N { for i in -N..<N {
                let fi = Float(i) + 0.5, fj = Float(j) + 0.5
                guard fi * fi + fj * fj <= Float(N * N) * size else { continue }
                let lx = plan.ox + (i + N) * lot + street + 13, lz = plan.oz + (j + N) * lot + street + 13
                var hs: [Int] = []
                var wet = false
                for (dx, dz) in [(0, 0), (-10, -10), (10, -10), (-10, 10), (10, 10)] {
                    let col = gen.column(lx + dx, lz + dz)
                    hs.append(col.height)
                    if col.height <= SEA || col.biome.isOcean || col.biome == .river { wet = true }
                }
                guard !wet, (hs.max()! - hs.min()!) <= 12 else { continue }
                terrain[plan.idx(i, j)] = hs.sorted()[2]
                plan.level[plan.idx(i, j)] = hs.sorted()[2]
                count += 1
            } }
            guard count >= need, plan.has(0, 0), plan.has(-1, -1), plan.has(0, -1), plan.has(-1, 0) else { return nil }
            // Terraces: neighbours within 4 blocks of each other (relaxed toward each other); a lot pulled more than
            // 8 from its ground is dropped.
            for _ in 0..<12 {
                for j in -N..<N { for i in -N..<N {
                    guard let a = plan.lv(i, j) else { continue }
                    for (di, dj) in [(1, 0), (0, 1)] {
                        guard let b = plan.lv(i + di, j + dj), abs(a - b) > 4 else { continue }
                        let mid = (a + b) / 2
                        plan.level[plan.idx(i, j)] = a > b ? mid + 2 : mid - 2
                        plan.level[plan.idx(i + di, j + dj)] = a > b ? mid - 2 : mid + 2
                    }
                } }
            }
            for k in 0..<plan.level.count where plan.level[k] != Int.min && abs(plan.level[k] - terrain[k]) > 8 { plan.level[k] = Int.min }
            guard plan.has(0, 0) else { return nil }
            // A hole in the grid (steep or wet ground) with lots on three or four sides would stand as a pillar of
            // terrain between cut walkways: it becomes a garden at its neighbours' mean height.
            for j in -N..<N { for i in -N..<N where !plan.has(i, j) {
                let fi = Float(i) + 0.5, fj = Float(j) + 0.5
                guard fi * fi + fj * fj <= Float(N * N) * size else { continue }
                let ns = [plan.lv(i - 1, j), plan.lv(i + 1, j), plan.lv(i, j - 1), plan.lv(i, j + 1)].compactMap { $0 }
                if ns.count >= 3 { plan.level[plan.idx(i, j)] = ns.reduce(0, +) / ns.count; plan.kind[plan.idx(i, j)] = 2 }
            } }
            // Lot uses: the civic centre, then buildings, plazas and gardens at random; canopies on the two main
            // avenues and some side walks.
            var rng = SRng(seed ^ 0xC17)
            // The mix (G12): buildings 40-70 %, the rest squares or gardens in a city's own proportion, canopies on
            // 15-50 % of the side walks.
            let pBuild: Float = varied ? 0.4 + 0.3 * mix.float() : 0.55
            let pPlaza: Float = varied ? pBuild + (1 - pBuild) * (0.2 + 0.6 * mix.float()) : 0.8
            let pCanopy: Float = varied ? 0.15 + 0.35 * mix.float() : 0.35
            var lots = 0
            for j in -N..<N { for i in -N..<N where plan.has(i, j) {
                let k = plan.idx(i, j)
                lots += 1
                if i == 0 && j == 0 { plan.kind[k] = 3 }
                else if plan.kind[k] == 2 { }                 // a filled hole stays a garden
                else { let r = rng.float(); plan.kind[k] = r < pBuild ? 0 : (r < pPlaza ? 1 : 2) }
                plan.covered[k * 2] = i == 0 || rng.chance(pCanopy)
                plan.covered[k * 2 + 1] = j == 0 || rng.chance(pCanopy)
            } }
            guard lots >= need - 2 else { return nil }
            plan.seed = seed
            // The market lots round the civic centre, flats and offices (CapitalTown.swift); not for a city whose ground
            // was partly saved before they existed (StructureCache.legacyCapitalTowns).
            if sc.clear(cx: cx, cz: cz, reach: 9, guardSet: sc.legacyCapitalTowns) { CapitalTown.assignShops(plan) }
            return plan
    }

    static func lotSeed(_ seed: UInt64, _ i: Int, _ j: Int) -> UInt64 {
        seed &+ UInt64(bitPattern: Int64((i + 7) * 31 + j + 7)) &* 0x9E3779B97F4A7C15
    }

    // Soldier kinds that keep watch in the streets (mob keys unchanged, Soldiers.swift).
    static let watch = ["soldier_recruit", "soldier_trooper", "soldier_recruit", "soldier_marksman"]

    // One lot with its west and north walkways (and east/south ones on the city's edge).
    static func buildLot(_ w: inout StructWriter, _ plan: Plan, _ i: Int, _ j: Int, _ seed: UInt64) {
        var rng = SRng(seed | 1)
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let white = g("capital_stone", g("white_concrete")), grey = g("capital_stone_trim", g("light_gray_concrete"))
        let pave = g("capital_paving", grey), paveSlab = g("capital_paving_slab", g("smooth_stone_slab"))
        let roofSlab = g("capital_stone_slab", white), roofTop = g("capital_stone_slab[top]", white)
        let light = g("light_panel", g("glowstone"))
        // P462: a modern city's posts and canopy edges are dark steel, its covered walks a white canopy cantilevered
        // off a line of slim posts on the outer side only, ten apart (the white colonnades read as Greek).
        let modern = plan.modern
        let steel = g("capital_steel", grey), steelSlab = g("capital_steel_slab", roofSlab), steelTop = g("capital_steel_slab[top]", roofTop)
        let post = modern ? steel : white
        let x0 = plan.ox + (i + N) * lot, z0 = plan.oz + (j + N) * lot
        let L = plan.lv(i, j)!
        let k = plan.idx(i, j)
        let east = !plan.has(i + 1, j), south = !plan.has(i, j + 1)
        let x1 = x0 + lot - 1 + (east ? street : 0), z1 = z0 + lot - 1 + (south ? street : 0)
        // Work only over this chunk's part of the lot.
        let xa = max(x0, w.bx), xb = min(x1, w.bx + CS - 1), za = max(z0, w.bz), zb = min(z1, w.bz + CS - 1)

        // Leaves left floating outside the city by trees whose trunks the clearing took (the citadel's fix).
        if !plan.has(i - 1, j) || !plan.has(i, j - 1) || east || south {
            let ra = max(x0 - 6, w.bx), rb = min(x1 + 6, w.bx + CS - 1), qa = max(z0 - 6, w.bz), qb = min(z1 + 6, w.bz + CS - 1)
            if ra <= rb && qa <= qb {
                for z in qa...qb { for x in ra...rb where x < x0 || x > x1 || z < z0 || z > z1 {
                    for y in (L - 4)...(L + 40) where CapitalBase.isLeaf(w.get(x, y, z)) {
                        var held = false
                        search: for oy in -6...1 { for oz in -3...3 { for ox in -3...3 {
                            let q = (x + ox, y + oy, z + oz)
                            if !w.inside(q.0, q.1, q.2) || CapitalBase.isLog(w.get(q.0, q.1, q.2)) { held = true; break search }
                        } } }
                        if !held { w.set(x, y, z, AIR) }
                    }
                } }
            }
        }
        guard xa <= xb, za <= zb else { return }

        // Walkways (u or v < 6, or past the lot on the city's edge): paving at the interpolated height, half
        // steps as slabs, cut into the ground and filled under; canopies on covered strips.
        for z in za...zb { for x in xa...xb {
            let u = x - x0, v = z - z0
            let walkW = u < street || u >= lot, walkN = v < street || v >= lot
            guard walkW || walkN else { continue }
            let hh = plan.walkHalf(x, z)
            let base = hh >> 1, half = hh & 1 == 1
            w.fill(x, base + 1, z, x, base + 40, z, AIR)
            w.groundDown(x, base - 1, z, grey, minY: base - 30, reach: 30)     // P289: a plug over a cave
            w.set(x, base, z, pave)
            if half { w.set(x, base + 1, z, paveSlab) }
            // Canopy: the lot's west (and east edge) strip runs north-south, its north (and south edge) strip
            // east-west; each has its own flag; a corner cell takes a covered one.
            let cw = walkW && plan.covered[k * 2], cn = walkN && plan.covered[k * 2 + 1]
            let alongZ = walkW && (cw || !walkN)
            let cov = cw || cn
            guard cov else {
                // Open walks: lamp posts every 12 blocks on the outer line.
                let a = alongZ ? (u < street ? u : u - lot) : (v < street ? v : v - lot)
                let along = alongZ ? z : x
                if a == 0 && mod(along, 12) == 6 {
                    let f = base + 1                                  // (P462: on a half step it replaces the slab)
                    for y in f..<(f + 3) { w.set(x, y, z, post) }
                    w.set(x, f + 3, z, light)
                }
                continue
            }
            let a = alongZ ? (u < street ? u : u - lot) : (v < street ? v : v - lot)     // 0...5 across the strip
            let along = alongZ ? z : x
            let roofY = base + 5
            let pillar = modern ? a == 0 && mod(along, 10) == 0 : (a == 0 || a == street - 1) && mod(along, 5) == 0
            let rim = modern && (a == 0 || a == street - 1)
            if pillar && modern {
                for y in (base + 1)...(base + (half ? 5 : 4)) { w.set(x, y, z, steel) }
                if !half { w.set(x, roofY, z, steelSlab) }
            } else if rim {
                w.set(x, roofY, z, half ? steelTop : steelSlab)
            } else if pillar {
                // P462 (Oct 25 16:33, his Capital City: "The pillars are still floating"): on a half step the column
                // stood on the paving slab's top cell, half a block over the slab; it now replaces the slab and stands
                // on the paving under it.
                for y in (base + 1)...(base + (half ? 5 : 4)) { w.set(x, y, z, white) }
                if !half { w.set(x, roofY, z, roofSlab) }
            } else {
                w.set(x, roofY, z, half ? roofTop : roofSlab)
                if a == 2 && mod(along, 5) == 2 { w.set(x, roofY, z, light) }
            }
        } }

        // The terrace: flat floor at L (paving, or lawn for gardens), cut and filled; entrance ramps (4 wide in the
        // middle of each side) climb or descend from the walkway in half steps.
        let garden = plan.kind[k] == 2
        let tza = max(za, z0 + street), tzb = min(zb, z0 + lot - 1), txa = max(xa, x0 + street), txb = min(xb, x0 + lot - 1)
        if tza <= tzb && txa <= txb { for z in tza...tzb { for x in txa...txb {
            let u = x - x0, v = z - z0
            w.fill(x, L + 1, z, x, L + 40, z, AIR)
            // The terrace's outer ring is a white retaining edge (paved on top, also round gardens); inside, earth.
            let ring = u == street || v == street || u == lot - 1 || v == lot - 1
            w.groundDown(x, L - 1, z, ring ? white : (garden ? DIRT : grey), minY: L - 30, reach: 30)   // P289
            // Distance from each side's walkway and whether this cell is in that side's entrance.
            var hh = 2 * L
            let sides: [(Int, Bool, Int, Int)] = [(u - street, v >= 17 && v <= 20, x0 + street - 1, z), (v - street, u >= 17 && u <= 20, x, z0 + street - 1),
                                                  (lot - 1 - u, v >= 17 && v <= 20, x0 + lot, z), (lot - 1 - v, u >= 17 && u <= 20, x, z0 + lot)]
            for (d, inRamp, wx, wz) in sides where inRamp && d < 6 {
                let edge = plan.walkHalf(wx, wz)
                let toward = edge + (2 * L > edge ? 1 : -1) * (d + 1)
                let r = 2 * L > edge ? min(2 * L, toward) : max(2 * L, toward)
                if abs(r - 2 * L) > abs(hh - 2 * L) { hh = r }
            }
            let base = hh >> 1, half = hh & 1 == 1
            if base < L { w.fill(x, base + 1, z, x, L, z, AIR) }
            if base > L { w.fill(x, L, z, x, base - 1, z, grey) }
            w.set(x, base, z, garden && !ring && hh == 2 * L ? GRASS : pave)
            if half { w.set(x, base + 1, z, paveSlab) }
        } } }

        switch plan.kind[k] {
        case 0: building(&w, x0, z0, L, &rng, home: CapitalTown.isResidence(plan, i, j) ? (plan, i, j) : nil, modern: modern)
        case 1: plaza(&w, x0, z0, L, &rng, fountain: false, plan: plan)
        case 3: plaza(&w, x0, z0, L, &rng, fountain: true, plan: plan)
        case 4: CapitalTown.market(&w, plan, i, j, x0, z0, L, &rng)
        default: gardenLot(&w, x0, z0, L, &rng)
        }
    }

    // A tree with a round crown (oak or birch) in a white planter whose top sits on the terrace.
    static func planterTree(_ w: inout StructWriter, _ x: Int, _ y: Int, _ z: Int, _ rng: inout SRng, planter: Bool = true) {
        let white = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        let birch = rng.chance(0.5)
        let log = birch ? BIRCH_LOG : LOG, leaves = birch ? BIRCH_LEAVES : LEAVES
        if planter {
            for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 { w.set(x + dx, y + 1, z + dz, white) } }
        }
        w.set(x, y, z, DIRT)
        w.set(x, y + 1, z, GRASS)
        let h = 4 + rng.int(2)
        for t in 0..<h { w.set(x, y + 2 + t, z, log) }
        let cy = y + 1 + h
        for ly in (cy - 1)...(cy + 2) { for oz in -2...2 { for ox in -2...2 {
            let dy = ly - cy
            let r = ox * ox + oz * oz + dy * dy
            if r <= (dy > 0 ? 3 : 6) && !(ox == 0 && oz == 0 && ly <= cy) && w.get(x + ox, ly, z + oz) == AIR { w.set(x + ox, ly, z + oz, leaves) }
        } } }
    }

    // A café table: a slab on a fence post, two or four chairs (stairs facing it), an umbrella on some.
    static func seating(_ w: inout StructWriter, _ x: Int, _ y: Int, _ z: Int, _ rng: inout SRng) {
        let fence = Blocks.has("birch_fence") ? Blocks.id("birch_fence") : STONE
        let cloth = Blocks.has("white_carpet") ? Blocks.id("white_carpet") : STONE
        let chair = "capital_stone_stairs"
        w.set(x, y + 1, z, fence)                        // the table: a post with a white cloth top
        w.set(x, y + 2, z, cloth)
        for (dx, dz, dir) in [(1, 0, "west"), (-1, 0, "east"), (0, 1, "north"), (0, -1, "south")] where rng.chance(0.75) {
            let n = "\(chair)[\(dir)]"
            if Blocks.has(n) { w.set(x + dx, y + 1, z + dz, Blocks.id(n)) }
        }
        if rng.chance(0.6) {
            // Umbrella: a pole beside the table, a white canopy 3 up.
            let wool = Blocks.has("white_wool") ? Blocks.id("white_wool") : STONE
            let carpet = Blocks.has("white_carpet") ? Blocks.id("white_carpet") : wool
            let px = x + 1, pz = z + 1
            for t in 1...3 { w.set(px, y + t, pz, fence) }
            for oz in -1...1 { for ox in -1...1 { w.set(px + ox, y + 4, pz + oz, ox == 0 && oz == 0 ? wool : carpet) } }
        }
    }

    // A bench: two stairs side by side facing `dir`.
    static func bench(_ w: inout StructWriter, _ x: Int, _ y: Int, _ z: Int, alongX: Bool, dir: String) {
        let n = "capital_stone_stairs[\(dir)]"
        guard Blocks.has(n) else { return }
        for t in 0..<3 { w.set(x + (alongX ? t : 0), y + 1, z + (alongX ? 0 : t), Blocks.id(n)) }
    }

    // A long, low white building: one or two storeys (the upper one set back, a terrace on the lower roof), window
    // bands between white piers, a deep flat roof with an overhang and a grey fascia, an entrance on the walkway
    // side, lights, a chest, a ladder to the upper floor; a café terrace in front.
    // A building's footprint: the first draws of its lot's generator, so another lot can find it (CapitalTown sends
    // residents to work in the offices).
    struct Footprint { let bx0: Int, bz0: Int, bw: Int, bd: Int, storeys: Int }
    static func footprint(_ x0: Int, _ z0: Int, _ rng: inout SRng) -> Footprint {
        let bw = rng.range(16, 22), bd = rng.range(9, 13)
        let storeys = rng.chance(0.55) ? 2 : 1
        let bx0 = x0 + street + 3 + rng.int(23 - bw), bz0 = z0 + street + 9 + rng.int(max(1, 15 - bd))
        return Footprint(bx0: bx0, bz0: bz0, bw: bw, bd: bd, storeys: storeys)
    }

    // `home`: a block of flats (beds along the back wall, residents) instead of offices.
    static func building(_ w: inout StructWriter, _ x0: Int, _ z0: Int, _ L: Int, _ rng: inout SRng, home: (Plan, Int, Int)? = nil, modern: Bool = false) {
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let white = g("capital_stone", g("white_concrete")), grey = g("capital_stone_trim", g("light_gray_concrete"))
        let window = g("capital_window", GLASS), light = g("light_panel", g("glowstone")), pave = g("capital_paving", grey)
        let roofSlab = g("capital_stone_slab", white), ladder = g("ladder")
        let fp = footprint(x0, z0, &rng)
        let bw = fp.bw, storeys = fp.storeys, bx0 = fp.bx0, bz0 = fp.bz0
        let bx1 = bx0 + bw - 1, bz1 = bz0 + fp.bd - 1
        if modern {
            tower(&w, fp, L, &rng, home: home)
            terrace(&w, x0, z0, L, (bx0 + bx1) / 2, &rng)
            return
        }
        func box(_ ax: Int, _ az: Int, _ bx: Int, _ bz: Int, _ y0: Int) {
            let H = 5
            for z in az...bz { for x in ax...bx {
                let wall = x == ax || x == bx || z == az || z == bz
                for y in (y0 + 1)...(y0 + H - 1) {
                    if !wall { w.set(x, y, z, AIR); continue }
                    let corner = (x == ax || x == bx) && (z == az || z == bz)
                    let along = (z == az || z == bz) ? x - ax : z - az
                    let pier = corner || along % 4 == 0
                    let band = y >= y0 + 1 && y <= y0 + 3
                    w.set(x, y, z, !pier && band ? window : white)
                }
                w.set(x, y0, z, pave)
                w.set(x, y0 + H, z, white)                                   // roof / upper floor
                if !wall && (x - ax) % 4 == 2 && (z - az) % 4 == 2 { w.set(x, y0 + H - 1, z, light) }
            } }
            // Overhang: a slab rim one out round the roof, a grey fascia under the roof edge.
            for z in (az - 1)...(bz + 1) { for x in (ax - 1)...(bx + 1) where x == ax - 1 || x == bx + 1 || z == az - 1 || z == bz + 1 {
                w.set(x, y0 + H, z, roofSlab)
            } }
            for z in az...bz { for x in ax...bx where x == ax || x == bx || z == az || z == bz { w.set(x, y0 + H - 1, z, grey) } }
        }
        box(bx0, bz0, bx1, bz1, L)
        // Portico: the roof carried three blocks out over the entrance side on slim white columns.
        for z in (bz0 - 3)...(bz0 - 1) { for x in (bx0 - 1)...(bx1 + 1) { w.set(x, L + 5, z, roofSlab) } }
        // Each column stands on something: where the portico reaches past the terrace (over a ramp or the walkway's lower
        // ground) it is carried down to the ground (Oct 11 playtest P35: "a few pillars are off the ground").
        for x in stride(from: bx0, through: bx1, by: 4) {
            for y in (L + 1)...(L + 4) { w.set(x, y, bz0 - 3, white) }
            w.groundDown(x, L, bz0 - 3, white, minY: L - 30)
        }
        for x in (bx0 - 1)...(bx1 + 1) { w.set(x, L + 4, bz0 - 3, grey) }
        // Entrance: a 3-wide opening in the north (walkway) face, glass panels round it.
        let ex = (bx0 + bx1) / 2
        for x in (ex - 1)...(ex + 1) { for y in (L + 1)...(L + 3) { w.set(x, y, bz0, AIR) } }
        if let (plan, i, j) = home {
            // Flats: beds along the back wall, a resident for each, the chest in the corner.
            w.chest(bx1 - 1, L + 1, bz1 - 1, loot: "capital_city", seed: rng.next(), facing: 0)
            CapitalTown.residents(&w, plan, i, j, fp, L)
        } else {
            // Interior: a reception desk, benches, the chest.
            w.set(ex - 3, L + 1, bz0 + 3, white); w.set(ex - 2, L + 1, bz0 + 3, white); w.set(ex - 1, L + 1, bz0 + 3, white)
            w.chest(bx1 - 1, L + 1, bz1 - 1, loot: "capital_city", seed: rng.next(), facing: 0)
            bench(&w, bx0 + 2, L, bz1 - 2, alongX: true, dir: "south")
            CapitalTown.desks(&w, fp, L)
            CityPurpose.furnish(&w, fp, L)                           // H6 (CityPurpose.swift)
        }
        if storeys == 2 {
            // Upper storey set back two from the south and east sides; the lower roof around it is a terrace with
            // a low parapet; a ladder inside the north-west corner.
            let ux1 = bx1 - 3, uz1 = bz1 - 2
            box(bx0, bz0, ux1, uz1, L + 5)
            for z in bz0...bz1 { for x in bx0...bx1 where (x > ux1 || z > uz1) && (x == bx1 || z == bz1) { w.set(x, L + 6, z, roofSlab) } }
            for y in (L + 1)...(L + 5) { w.set(bx0 + 1, y, bz0 + 1, ladder + 3) }
            w.set(bx0 + 1, L + 5, bz0 + 1, ladder + 3)
            // Roof garden on the lower terrace corner.
            planterTree(&w, bx1 - 1, L + 4, bz1 - 1, &rng, planter: false)
            w.chest(ux1 - 1, L + 6, uz1 - 1, loot: "capital_city", seed: rng.next(), facing: 0)
        }
        terrace(&w, x0, z0, L, ex, &rng)
    }

    // Café terrace in front of the entrance, trees in planters at the corners of the lot.
    static func terrace(_ w: inout StructWriter, _ x0: Int, _ z0: Int, _ L: Int, _ ex: Int, _ rng: inout SRng) {
        let tz = z0 + street + 4
        for u in [9, 13, 25] where rng.chance(0.85) { seating(&w, x0 + u, L, tz, &rng) }     // clear of the ramp (u 17-20)
        for (dx, dz) in [(street + 2, lot - 2), (lot - 3, lot - 2)] where rng.chance(0.8) { planterTree(&w, x0 + dx, L - 1, z0 + dz, &rng) }
        if rng.chance(0.55) { w.mob(watch[rng.int(watch.count)], V3(Float(ex) + 0.5, Float(L + 1), Float(z0 + street + 2) + 0.5)) }
        // P499 (Oct 30 15:10, in a Capital city: "we need way more troops here... a total maybe 10, maybe 15 troops. Not
        // enough. It should be 50"): each building's entrance has a second sentry and most a third at the terrace's
        // corner (rolled apart from the lot's own draws, so a lot half made before keeps its look; troops are placed only
        // when their ground is first made).
        var more = Self.watchRng(x0, z0)
        w.mob(watch[more.int(watch.count)], V3(Float(ex) + 2.5, Float(L + 1), Float(z0 + street + 2) + 0.5))
        if more.chance(0.7) { w.mob(watch[more.int(watch.count)], V3(Float(x0 + street + 2) + 0.5, Float(L + 1), Float(z0 + street + 2) + 0.5)) }
    }
    static func watchRng(_ x0: Int, _ z0: Int) -> SRng {
        SRng(UInt64(bitPattern: Int64(x0) &* 73_856_093 ^ Int64(z0) &* 19_349_663) ^ 0xC17D_0050_5E17_0001 | 1)
    }

    // P462 (Oct 25 16:31, his Capital City: "I want it to be more New Alexandria looking... Reminds me of Greek
    // architecture too much"): on new ground a building lot holds a tower of glass and steel: offices 4-9 storeys
    // (20-45 blocks), flats 3-5, five blocks a storey. Curtain glass full height between slim steel mullions three
    // apart, white corners and a white band at every floor, white floors lit from the ceiling, a flat roof with a steel parapet (a lit
    // mast on the tall ones, a roof garden on the flats); no columns or portico: a steel canopy cantilevered over the
    // door. A spiral stair in a steel shaft climbs to the top floor: no ladders. The ground floor keeps its reception,
    // desks, beds and purpose as before.
    static var sampleTower: (IVec3, Int)?                  // (the first tower built: CapitalTownTests prints where)
    static let towerCore = 7                                // the stair core's walls from the east face in: bx1 - 6 ... bx1 - 2
    static func tower(_ w: inout StructWriter, _ fp: Footprint, _ L: Int, _ rng: inout SRng, home: (Plan, Int, Int)?) {
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let white = g("capital_stone", g("white_concrete")), grey = g("capital_stone_trim", g("light_gray_concrete"))
        let steel = g("capital_steel", grey), glass = g("capital_curtain", GLASS), light = g("light_panel", g("glowstone"))
        let pave = g("capital_paving", grey), steelSlab = g("capital_steel_slab", steel)
        let bx0 = fp.bx0, bz0 = fp.bz0, bx1 = fp.bx0 + fp.bw - 1, bz1 = fp.bz0 + fp.bd - 1
        let floors = home != nil ? 3 + rng.int(3) : 4 + rng.int(6)
        let H = 5, top = L + floors * H
        for z in bz0...bz1 { for x in bx0...bx1 {
            let wall = x == bx0 || x == bx1 || z == bz0 || z == bz1
            let corner = (x == bx0 || x == bx1) && (z == bz0 || z == bz1)
            let along = (z == bz0 || z == bz1) ? x - bx0 : z - bz0
            let mullion = along % 3 == 0
            w.set(x, L, z, pave)
            for f in 0..<floors {
                let y0 = L + f * H
                if f > 0 { w.set(x, y0, z, white) }                                // the floor, a white band round the face
                for y in (y0 + 1)...(y0 + H - 1) { w.set(x, y, z, !wall ? AIR : (corner ? white : mullion ? steel : glass)) }
                if !wall && (x - bx0) % 4 == 2 && (z - bz0) % 4 == 2 { w.set(x, y0 + H - 1, z, light) }
            }
            w.set(x, top, z, wall ? steel : white)                                  // the roof and its parapet
            if wall { w.set(x, top + 1, z, steelSlab) }
        } }
        // The door (3 wide in the north face) under a steel canopy, no columns.
        let ex = (bx0 + bx1) / 2
        for x in (ex - 1)...(ex + 1) { for y in (L + 1)...(L + 3) { w.set(x, y, bz0, AIR) } }
        for z in (bz0 - 3)...(bz0 - 1) { for x in (ex - 3)...(ex + 3) { w.set(x, L + 5, z, steelSlab) } }
        // The stair core: a spiral in a 3 x 3 shaft in the north-east corner (x cx-1...cx+1, z bz0+1...bz0+3) round a
        // steel newel, one step a cell and eight a turn (head room 7), walled in steel (x cx-2 and cx+2, z bz0+4; a
        // passage along the east wall), with a door off the step that comes level with each floor.
        let cx = bx1 - 4, cz = bz0 + 2, Yt = L + (floors - 1) * H
        if sampleTower == nil { sampleTower = (IVec3(cx, L, cz), floors) }
        let ring: [(Int, Int)] = [(-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0)]
        func step(_ d: (Int, Int)) -> BlockID {
            d.0 > 0 ? g("capital_stone_stairs[east]", white) : d.0 < 0 ? g("capital_stone_stairs[west]", white)
                : d.1 > 0 ? g("capital_stone_stairs[south]", white) : g("capital_stone_stairs[north]", g("capital_stone_stairs", white))
        }
        for y in (L + 1)..<top {
            for dz in -1...1 { for dx in -1...1 { w.set(cx + dx, y, cz + dz, dx == 0 && dz == 0 ? steel : AIR) } }
            for dz in -1...2 { w.set(cx - 2, y, cz + dz, steel); w.set(cx + 2, y, cz + dz, steel) }
            for dx in -1...1 { w.set(cx + dx, y, cz + 2, steel) }
        }
        for s in 0..<(Yt - L) {
            let a = ring[s % 8], b = ring[(s + 1) % 8]
            w.set(cx + a.0, L + 1 + s, cz + a.1, step((b.0 - a.0, b.1 - a.1)))
        }
        // Doors: on the ground floor in at the first step, then off the step level with each floor (the middle one on
        // the north side, against the face, goes out off the next step instead).
        func door(_ c: (Int, Int), _ y: Int) {
            let (dx, dz) = c.0 < 0 ? (-2, c.1) : c.0 > 0 ? (2, c.1) : (0, 2)
            for yy in y...(y + 2) { w.set(cx + dx, yy, cz + dz, AIR) }
        }
        door(ring[0], L + 1)
        for k in 1..<floors {
            let s = k * H - 1
            let c = ring[s % 8]
            if c.0 == 0 && c.1 < 0 { door(ring[(s + 1) % 8], L + k * H + 1) } else { door(c, L + k * H + 1) }
        }
        // Upper floors: rows of desks (offices), or nothing but the light (flats).
        if home == nil {
            for f in 1..<floors {
                let Y = L + f * H
                for x in stride(from: bx0 + 2, through: bx1 - towerCore - 1, by: 3) { for z in [bz0 + 3, bz1 - 2] where z > bz0 && z < bz1 {
                    if w.inside(x, Y + 1, z) && w.get(x, Y + 1, z) == AIR { w.set(x, Y + 1, z, grey) }
                } }
            }
        }
        // The roof: a lit mast on a tall office tower, a garden on the flats.
        if home == nil && floors >= 6 {
            for y in (top + 1)...(top + 7) { w.set(bx0 + 2, y, bz0 + 2, steel) }
            w.set(bx0 + 2, top + 8, bz0 + 2, light)
        } else if home != nil {
            planterTree(&w, bx0 + 3, top - 1, bz1 - 3, &rng, planter: false)
        }
        // The ground floor as before: flats or offices.
        if let (plan, i, j) = home {
            w.chest(bx1 - 1, L + 1, bz1 - 1, loot: "capital_city", seed: rng.next(), facing: 0)
            CapitalTown.residents(&w, plan, i, j, fp, L)
        } else {
            w.set(ex - 3, L + 1, bz0 + 3, white); w.set(ex - 2, L + 1, bz0 + 3, white); w.set(ex - 1, L + 1, bz0 + 3, white)
            w.chest(bx1 - 1, L + 1, bz1 - 1, loot: "capital_city", seed: rng.next(), facing: 0)
            bench(&w, bx0 + 2, L, bz1 - 2, alongX: true, dir: "south")
            CapitalTown.desks(&w, fp, L)
            CityPurpose.furnish(&w, fp, L)
        }
    }

    // A paved square: four trees in planters with benches, seating, light posts; the civic centre has a fountain
    // pool in the middle and two guards.
    static func plaza(_ w: inout StructWriter, _ x0: Int, _ z0: Int, _ L: Int, _ rng: inout SRng, fountain: Bool, plan: Plan? = nil) {
        let white = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        let post = plan?.modern == true && Blocks.has("capital_steel") ? Blocks.id("capital_steel") : white     // (P462)
        let light = Blocks.has("light_panel") ? Blocks.id("light_panel") : STONE
        let cx = x0 + street + 13, cz = z0 + street + 13
        for (dx, dz) in [(-8, -8), (8, -8), (-8, 8), (8, 8)] {
            for oz in -2...2 { for ox in -2...2 { w.set(cx + dx + ox, L, cz + dz + oz, GRASS) } }   // a lawn round each planter
            planterTree(&w, cx + dx, L - 1, cz + dz, &rng)
            bench(&w, cx + dx - 1, L, cz + dz + (dz < 0 ? 2 : -2), alongX: true, dir: dz < 0 ? "north" : "south")
        }
        if fountain {
            for dz in -4...4 { for dx in -4...4 {
                let edge = abs(dx) == 4 || abs(dz) == 4
                w.set(cx + dx, L, cz + dz, white)
                w.set(cx + dx, L + 1, cz + dz, edge ? white : WATER)
            } }
            for y in (L + 1)...(L + 3) { w.set(cx, y, cz, post) }
            w.set(cx, L + 4, cz, WATER)
            w.mob("soldier_trooper", V3(Float(cx - 6) + 0.5, Float(L + 1), Float(cz) + 0.5))
            w.mob("soldier_marksman", V3(Float(cx + 6) + 0.5, Float(L + 1), Float(cz) + 0.5))
            // (P499: the civic square's guard, four more)
            w.mob("soldier_officer", V3(Float(cx) + 0.5, Float(L + 1), Float(cz - 6) + 0.5))
            w.mob("soldier_trooper", V3(Float(cx) + 0.5, Float(L + 1), Float(cz + 6) + 0.5))
            w.mob("soldier_trooper", V3(Float(cx - 6) + 0.5, Float(L + 1), Float(cz - 6) + 0.5))
            w.mob("soldier_trooper", V3(Float(cx + 6) + 0.5, Float(L + 1), Float(cz + 6) + 0.5))
        } else {
            for t in 0..<3 where rng.chance(0.8) { seating(&w, cx - 6 + t * 6, L, cz + 5, &rng) }
            if rng.chance(0.7) { w.mob(watch[rng.int(watch.count)], V3(Float(cx) + 0.5, Float(L + 1), Float(cz + 3) + 0.5)) }
            var more = watchRng(x0, z0)                                          // (P499: a pair on every plaza)
            w.mob(watch[more.int(watch.count)], V3(Float(cx - 3) + 0.5, Float(L + 1), Float(cz - 3) + 0.5))
            w.mob(watch[more.int(watch.count)], V3(Float(cx + 3) + 0.5, Float(L + 1), Float(cz - 3) + 0.5))
        }
        if let plan { CapitalTown.square(&w, plan, cx, cz, L, civic: fountain) }   // the bell townsfolk meet at, the city's name
        for (dx, dz) in [(-11, -11), (11, -11), (-11, 11), (11, 11)] {      // light posts in the corners (off the ramps)
            for y in (L + 1)...(L + 3) { w.set(cx + dx, y, cz + dz, post) }
            CityPurpose.lamp(&w, cx + dx, L + 4, cz + dz, fallback: light)
        }
    }

    // A garden: lawn, a paved cross, trees, hedges along the paths, benches.
    static func gardenLot(_ w: inout StructWriter, _ x0: Int, _ z0: Int, _ L: Int, _ rng: inout SRng) {
        let pave = Blocks.has("capital_paving") ? Blocks.id("capital_paving") : STONE
        let hedge = Blocks.has("oak_leaves") ? Blocks.id("oak_leaves") : LEAVES
        let cx = x0 + street + 13, cz = z0 + street + 13
        for t in -13...12 { for s in -1...1 {
            w.set(cx + t, L, cz + s, pave); w.set(cx + s, L, cz + t, pave)
        } }
        for t in -12...11 where abs(t) > 3 && t % 5 != 0 {
            w.set(cx + t, L + 1, cz - 3, hedge); w.set(cx + t, L + 1, cz + 3, hedge)
        }
        for (qx, qz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            for _ in 0..<2 {
                let tx = cx + qx * rng.range(6, 10), tz = cz + qz * rng.range(6, 10)
                planterTree(&w, tx, L - 1, tz, &rng, planter: false)
            }
        }
        bench(&w, cx - 6, L, cz - 2, alongX: true, dir: "south")
        bench(&w, cx + 4, L, cz + 2, alongX: true, dir: "north")
    }
}
