import Foundation
import simd

// People in the Capital's cities (CapitalCity.swift): the towns' shops, money and townsfolk (Shops.swift,
// Townsfolk.swift) in the white garden city. The four lots nearest the civic centre are a market: two storefronts
// each (all eight shops of a town: general store and saloon on the lot nearest the fountain), Capital white with a
// glazed front, an awning, the shop's colour across the fascia, its sign, a counter with the keeper behind it and a
// bed at the back. About half the other buildings are flats: beds along the back wall and a resident for each
// ("villager:citizen@x,y,z", the office desk they work at). Citizens keep a city day: to an office in a nearby lot in
// work hours, lunch at the saloon, the square's bell in the afternoon, the saloon in the evening, home to bed. They
// carry nothing: the Capital's soldiers keep the streets, citizens run from monsters. The city has a name (on a sign
// at the fountain), and its people say they are from it.

enum CapitalTown {
    static let storeW = 10, storeD = 8, perFlat = 3

    static let cityNames = ["Meridian", "Concord", "Halcyon", "Argent", "Solace", "Lumen", "Belmont", "Highmere", "Vantage",
                            "Clearwater", "Westholm", "Alder Crown", "Fairhaven", "Silverlake", "Calder", "Ostrava Hill"]

    static func cityName(_ x: Int, _ z: Int, seed: UInt64) -> String {
        Townsfolk.pick(cityNames, Townsfolk.mix(x, z, seed ^ 0xC17A))
    }

    // The market: the four lots nearest the centre (civic centre excluded), two shops each; flats and offices.
    static func assignShops(_ plan: CapitalCity.Plan) {
        let N = CapitalCity.N
        var near: [(Int, Int, Int)] = []
        for j in -N..<N { for i in -N..<N where plan.has(i, j) && !(i == 0 && j == 0) {
            let fi = Float(i) + 0.5, fj = Float(j) + 0.5
            near.append((Int((fi * fi + fj * fj) * 100), j, i))
        } }
        near.sort { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        var rng = SRng(plan.seed ^ 0x5409 | 1)
        let order = Village.shopOrder(&rng)
        for (n, e) in near.prefix(4).enumerated() {
            let k = plan.idx(e.2, e.1)
            plan.kind[k] = 4
            plan.shops[k] = [order[2 * n], order[2 * n + 1]]
        }
        // At least eight buildings (a city that drew mostly squares and gardens had one block of flats and three
        // citizens: CapitalTownTests seed 424242): the plazas and gardens farthest out become buildings.
        var spare: [(Int, Int, Int)] = []
        for j in -N..<N { for i in -N..<N where plan.has(i, j) && (plan.kind[plan.idx(i, j)] == 1 || plan.kind[plan.idx(i, j)] == 2) {
            spare.append((-(i * i + j * j), j, i))
        } }
        spare.sort { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        var count = plan.kind.indices.filter { plan.level[$0] != Int.min && plan.kind[$0] == 0 }.count
        for e in spare where count < 8 { plan.kind[plan.idx(e.2, e.1)] = 0; count += 1 }
        // Flats and offices in a checkerboard of building lots; a flat with no office within two lots becomes one
        // (nobody walks across the whole city to work).
        var buildings: [(Int, Int)] = []
        for j in -N..<N { for i in -N..<N where plan.has(i, j) && plan.kind[plan.idx(i, j)] == 0 { buildings.append((i, j)) } }
        for (i, j) in buildings { plan.flat[plan.idx(i, j)] = (i + j) & 1 == 0 }
        for (i, j) in buildings where plan.flat[plan.idx(i, j)] {
            let office = buildings.contains { !plan.flat[plan.idx($0.0, $0.1)] && max(abs($0.0 - i), abs($0.1 - j)) <= 2 }
            if !office { plan.flat[plan.idx(i, j)] = false }
        }
    }

    // Building lots that are flats (the rest are offices).
    static func isResidence(_ plan: CapitalCity.Plan, _ i: Int, _ j: Int) -> Bool {
        plan.has(i, j) && plan.kind[plan.idx(i, j)] == 0 && plan.flat[plan.idx(i, j)]
    }

    // The office desks people from lot (i, j) work at: the nearest office building (up to two lots away), every other
    // resident the second nearest when it is next door too. (Two lots diagonally and 11 blocks up was a 95-block walk
    // that took longer than the morning: CapitalTownTests seed 424242.)
    static func desk(_ plan: CapitalCity.Plan, _ i: Int, _ j: Int, _ n: Int) -> IVec3? {
        let N = CapitalCity.N
        var offices: [(Int, Int, Int)] = []
        for oj in -N..<N { for oi in -N..<N where plan.has(oi, oj) && plan.kind[plan.idx(oi, oj)] == 0 && !isResidence(plan, oi, oj) {
            guard max(abs(oi - i), abs(oj - j)) <= 2 else { continue }
            let rise = abs(plan.lv(oi, oj)! - (plan.lv(i, j) ?? 0))
            offices.append((((oi - i) * (oi - i) + (oj - j) * (oj - j)) * 8 + rise, oj, oi))
        } }
        guard !offices.isEmpty else { return nil }
        offices.sort { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        let pick = n % 2 == 1 && offices.count > 1 && offices[1].0 <= 2 * 8 + 4 ? offices[1] : offices[0]
        let oi = pick.2, oj = pick.1
        let x0 = plan.ox + (oi + N) * CapitalCity.lot, z0 = plan.oz + (oj + N) * CapitalCity.lot
        var rng = SRng(CapitalCity.lotSeed(plan.seed, oi, oj) | 1)
        let fp = CapitalCity.footprint(x0, z0, &rng)
        // A row clear of the reception desk (bz0 + 3), the bench (bz1 - 2) and the ladder: bz0 + 5.
        return IVec3(fp.bx0 + 2 + (n * 3) % max(1, fp.bw - 4), plan.lv(oi, oj)! + 1, fp.bz0 + 5)
    }

    // The office desks themselves (CapitalCity.building, offices): a desk the clerk faces across the row south of
    // each spot desk() hands out, with a lamp on some.
    static func desks(_ w: inout StructWriter, _ fp: CapitalCity.Footprint, _ L: Int) {
        let desk = Blocks.has("capital_stone_trim") ? Blocks.id("capital_stone_trim") : STONE
        var x = fp.bx0 + 2
        while x <= fp.bx0 + 2 + max(0, fp.bw - 5) {
            if w.inside(x, L + 1, fp.bz0 + 6) && w.get(x, L + 1, fp.bz0 + 6) == AIR { w.set(x, L + 1, fp.bz0 + 6, desk) } else { x += 3; continue }   // not on the bench
            if (x - fp.bx0) % 2 == 0, Blocks.has("lantern") { w.set(x, L + 2, fp.bz0 + 6, Blocks.id("lantern")) }
            x += 3
        }
    }

    // Flats: up to three beds along the back wall (head to the wall), a resident standing in front of each.
    static func residents(_ w: inout StructWriter, _ plan: CapitalCity.Plan, _ i: Int, _ j: Int, _ fp: CapitalCity.Footprint, _ L: Int) {
        let bz1 = fp.bz0 + fp.bd - 1, bx1 = fp.bx0 + fp.bw - 1
        let colors = ["white_bed", "light_blue_bed", "light_gray_bed", "cyan_bed"]
        var n = 0
        for x in stride(from: fp.bx0 + 3, through: bx1 - 3, by: 4) where n < perFlat {
            let c = colors[Int(Townsfolk.mix(x, bz1, plan.seed) % 4)]
            guard Blocks.has(c), Blocks.has(c + "_head") else { continue }
            w.set(x, L + 1, bz1 - 2, Blocks.id(c))                // facing 0: head toward +Z, against the back wall
            w.set(x, L + 1, bz1 - 1, Blocks.id(c + "_head"))
            w.set(x + 1, L + 1, bz1 - 1, Blocks.has("birch_planks") ? Blocks.id("birch_planks") : STONE)   // a night stand
            if Blocks.has("lantern") { w.set(x + 1, L + 2, bz1 - 1, Blocks.id("lantern")) }
            var tag = "villager:citizen"
            if let d = desk(plan, i, j, n) { tag += "@\(d.x),\(d.y),\(d.z)" }
            w.mob(tag, V3(Float(x) + 0.5, Float(L + 1), Float(bz1 - 4) + 0.5))
            n += 1
        }
    }

    // A market lot: two storefronts facing the north walkway (clear of the entrance ramps), a café yard behind.
    static func market(_ w: inout StructWriter, _ plan: CapitalCity.Plan, _ i: Int, _ j: Int, _ x0: Int, _ z0: Int, _ L: Int, _ rng: inout SRng) {
        let st = CapitalCity.street
        for (n, k) in plan.shops[plan.idx(i, j)].enumerated() {
            storefront(&w, x0 + st + 1 + n * 14, z0 + st + 3, L, k, seed: CapitalCity.lotSeed(plan.seed, i, j) &+ UInt64(n))
        }
        for u in [9, 13, 25] where rng.chance(0.8) { CapitalCity.seating(&w, x0 + u, L, z0 + 24, &rng) }
        for u in [8, 29] { CapitalCity.planterTree(&w, x0 + u, L - 1, z0 + 29, &rng) }
        // A soldier between the storefronts, past the entrance ramp (v 6-11).
        if rng.chance(0.6) { w.mob(CapitalCity.watch[rng.int(CapitalCity.watch.count)], V3(Float(x0 + 19) + 0.5, Float(L + 1), Float(z0 + st + 6) + 0.5)) }
    }

    // One shop: walls 6 high, the front glazed at street level with a 3-wide opening, the sign over it, an awning,
    // the shop's colour along the fascia; inside the town shop's counter, keeper, bed and fittings (TownBuildings).
    static func storefront(_ w: inout StructWriter, _ sx: Int, _ sz: Int, _ L: Int, _ k: ShopKind, seed: UInt64) {
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let white = g("capital_stone", g("white_concrete")), grey = g("capital_stone_trim", g("light_gray_concrete"))
        let window = g("capital_window", GLASS), light = g("light_panel", g("glowstone")), pave = g("capital_paving", grey)
        let roofSlab = g("capital_stone_slab", white)
        let W = storeW, D = storeD, H = 6
        let l = Village.Lot(kind: k == .saloon ? .saloon : .shop, ax: sx, az: sz, face: 0, w: W, d: D, y: L + 1, seed: seed, job: "")
        let b = Village.LB(l: l)
        let m = Village.Mats(planks: white, log: grey, wall: white, floor: pave, foundation: grey, stairs: g("capital_stone_stairs", white),
                             slab: roofSlab, fence: g("birch_fence", white), door: AIR, path: pave, roofFlat: true, bed: Blocks.has("white_bed") ? "white_bed" : "red_bed")
        let band = Village.blk(Village.bandColor(k) + "_terracotta", grey)
        for v in 0..<D { for u in 0..<W {
            b.set(&w, u, -1, v, pave)
            let wall = u == 0 || u == W - 1 || v == 0 || v == D - 1
            for dy in 0..<H {
                guard wall else { b.set(&w, u, dy, v, AIR); continue }
                let corner = (u == 0 || u == W - 1) && (v == 0 || v == D - 1)
                var blk = white
                if corner {
                } else if v == 0 {
                    if dy <= 2 { blk = abs(u - W / 2) > 1 ? window : (dy <= 1 ? AIR : white) }  // the shop window, the way in, the sign's wall
                    if dy == H - 1 { blk = band }
                } else {
                    let along = v == D - 1 ? u : v
                    if (dy == 1 || dy == 2) && along % 3 != 0 { blk = window }
                    if dy == H - 1 { blk = grey }
                }
                b.set(&w, u, dy, v, blk)
            }
            b.set(&w, u, H, v, white)                                              // the roof
            if !wall && u % 4 == 2 && v % 3 == 1 { b.set(&w, u, H - 1, v, light) }
        } }
        for v in -1...D { for u in -1...W where u == -1 || u == W || v == -1 || v == D { b.set(&w, u, H, v, roofSlab) } }   // the overhang
        for u in 0..<W { b.set(&w, u, 3, -1, roofSlab) }                           // the awning
        for dy in 0...2 { for u in (W / 2 - 1)...(W / 2 + 1) { b.set(&w, u, dy, -1, AIR) } }
        // The counter, the keeper behind it, the bed, what the shop sells.
        let cv = D - 4
        for u in 1...(W - 3) { b.set(&w, u, 0, cv, grey) }
        b.set(&w, W / 2 - 1, 1, cv, Village.blk("lantern", AIR))
        Village.bed(&w, b, m, u: 1, v: cv + 1)
        Village.fittings(&w, b, m, k, cv: cv)
        if k == .doctor {                                                          // the red cross above the awning
            for u in (W / 2 - 1)...(W / 2 + 1) { b.set(&w, u, 3, 0, white) }
            b.set(&w, W / 2, 4, 0, g("red_wool")); b.set(&w, W / 2 - 1, 4, 0, g("white_wool")); b.set(&w, W / 2 + 1, 4, 0, g("white_wool"))
        }
        Village.sign(&w, b, u: W / 2, dy: 2, v: -1, lines: ["", k.name, "", ""])
        let (x, z) = Village.world(l, W / 2, cv + 1)
        w.mob("villager:shop_\(k.rawValue)", V3(Float(x) + 0.5, Float(L + 1), Float(z) + 0.5))
    }

    // A square's bell on a white post (where townsfolk meet in the afternoon); at the civic centre also the city's name
    // on the fountain's north rim.
    static func square(_ w: inout StructWriter, _ plan: CapitalCity.Plan, _ cx: Int, _ cz: Int, _ L: Int, civic: Bool) {
        let white = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        let (bx, bz) = civic ? (cx + 5, cz - 5) : (cx, cz - 4)
        w.set(bx, L + 1, bz, white)
        if Blocks.has("bell") { w.set(bx, L + 2, bz, Blocks.id("bell")) }
        guard civic, Blocks.has("oak_sign"), w.inside(cx, L + 1, cz - 5) else { return }
        w.set(cx, L + 1, cz - 5, Blocks.id("oak_sign") + 4)               // a wall sign facing north, on the rim
        let be = BlockEntity(.sign)
        let a = CapitalCity.N * CapitalCity.lot
        be.lines = ["Welcome to", cityName(plan.ox + a, plan.oz + a, seed: plan.seed), "Capital City", ""]
        w.entities.append((IVec3(cx, L + 1, cz - 5), be))
    }

    // The capital a place belongs to (its centre within 130 blocks), for Townsfolk.town.
    static func city(_ g: Game, x: Int, z: Int) -> String? {
        guard let sc = g.world.gen.structures, let s = sc.nearest("capital_city", x: x, z: z, maxRegions: 1),
              let plan = s.plan as? CapitalCity.Plan else { return nil }
        let a = CapitalCity.N * CapitalCity.lot, cx = plan.ox + a, cz = plan.oz + a
        guard abs(cx - x) < 130 && abs(cz - z) < 130 else { return nil }
        return cityName(cx, cz, seed: plan.seed)
    }
}
