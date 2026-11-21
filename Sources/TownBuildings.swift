import Foundation

// Town shops as buildings (Village.layout puts them on the main streets nearest the square). Each is a house with a
// tall false front over the street, an awning, a sign naming the shop, a counter across the room with the keeper
// behind it ("villager:shop_<kind>", Townsfolk.setup) and a bed in the back corner, plus fittings that say what the
// shop is. The saloon is bigger: a long bar, tables and stools, a piano corner. No job-site blocks inside (barrels,
// smokers, looms, brewing stands...), so nobody else in town takes a shop's fittings for their trade.

extension Village {
    // General store and saloon first, the other six in an order that depends on the town.
    static func shopOrder(_ rng: inout SRng) -> [ShopKind] {
        var rest: [ShopKind] = [.blacksmith, .butcher, .doctor, .gunsmith, .tailor, .stable]
        for i in stride(from: rest.count - 1, to: 0, by: -1) { rest.swapAt(i, rng.int(i + 1)) }
        return [.general, .saloon] + rest
    }

    static func blk(_ n: String, _ fallback: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : fallback }

    static func shopLot(_ w: inout StructWriter, _ b: LB, _ m0: Mats, _ k: ShopKind) {
        let l = b.l
        let m = varied(m0, l)
        let saloon = k == .saloon
        let wallH = saloon ? (m.roofFlat ? 8 : 6) : 5
        house(&w, b, m0, wallH: wallH)
        falseFront(&w, b, m, wallH: wallH, band: blk(bandColor(k) + "_terracotta", m.log))
        // Awning over the doorway (frontier towns: a covered boardwalk the width of the front), the sign above the door.
        let porchH = min(wallH, 6)
        if l.frontier { boardwalk(&w, b, m, wallH: porchH) }
        else { for u in thru(max(0, l.w / 2 - 2), min(l.w - 1, l.w / 2 + 2)) { b.set(&w, u, porchH - 1, -1, m.slab) } }
        sign(&w, b, u: l.w / 2, dy: 2, v: -1, lines: ["", k.name, "", ""])
        // R20: the general store's exchange, with its rate, by the door (Exchange: every counter has the row inside).
        if k == .general { sign(&w, b, u: 1, dy: 1, v: -1, lines: Exchange.signLines) }
        // T16: the saloon advertises its rooms upstairs and actually has guest rooms over the bar.
        if saloon { sign(&w, b, u: 1, dy: 1, v: -1, lines: ["ROOMS UPSTAIRS", "Room: $3.00", "Bath: $1.00", "Ask barkeep"]) }
        shopInside(&w, b, m, k, saloon: saloon)
        if saloon { saloonUpstairs(&w, b, m, wallH: wallH) }
    }

    // T16: guest rooms over the saloon (stairs along the open left wall u = 1, three private rooms along the front).
    static func saloonUpstairs(_ w: inout StructWriter, _ b: LB, _ m: Mats, wallH: Int) {
        let l = b.l
        guard l.w >= 13 && l.d >= 9 else { return }
        if !m.roofFlat {
            for u in 0..<l.w { b.set(&w, u, wallH, l.d - 1, (u == 0 || u == l.w - 1) ? m.log : m.wall) }
        }
        b.fill(&w, 1, 4, 1, l.w - 2, 4, l.d - 2, m.floor)
        for step in 0..<4 {
            let sv = 2 + step
            for fy in 0..<step { b.set(&w, 1, fy, sv, m.planks) }
            b.set(&w, 1, step, sv, b.stair(m.stairs, high: 0))
        }
        for sv in 2...5 {
            b.set(&w, 1, 4, sv, AIR); b.set(&w, 1, 5, sv, AIR); b.set(&w, 1, 6, sv, AIR)
        }
        for sv in 2...4 { b.set(&w, 2, 5, sv, m.fence) }
        let lantern = blk("lantern", AIR), pane = blk("glass_pane", m.planks)
        let sideTbl = b.furniture(m, "side_table") ?? m.planks
        b.fill(&w, 3, 5, 4, l.w - 2, 7, 4, m.planks)
        b.fill(&w, 6, 5, 1, 6, 7, 4, m.planks)
        b.fill(&w, 10, 5, 1, 10, 7, 4, m.planks)
        for (du, bu, tu) in [(4, 3, 5), (8, 7, 9), (12, l.w - 2, 11)] {
            b.set(&w, du, 5, 4, m.door + BlockID(dir(l, 0)))
            b.set(&w, du, 6, 4, m.door + BlockID(dir(l, 0) + 8))
            b.set(&w, du, 6, 0, pane)
            bed(&w, b, m, u: bu, v: 1, dy: 5)
            b.set(&w, tu, 5, 1, sideTbl); b.set(&w, tu, 6, 1, lantern)
        }
        b.set(&w, 3, 6, 5, b.wallTorch(facing: 0))
        b.set(&w, 11, 6, 5, b.wallTorch(facing: 0))
        b.set(&w, 6, 5, l.d - 2, b.seat(m, "bench", back: 0))
        b.set(&w, 8, 5, l.d - 2, b.seat(m, "bench", back: 0))
    }

    // T16: a dedicated two-story village inn (accommodations building) where you can pay the keeper behind the front desk
    // for a room for the night ($3) or a hot bath ($1) (Hotel.swift). Built in every frontier settlement (hamlet through
    // city) so even small villages without a saloon have a clearly signed place to sleep and rest.
    static func innLot(_ w: inout StructWriter, _ b: LB, _ m0: Mats) {
        let l = b.l
        let m = varied(m0, l)
        let wallH = 8
        house(&w, b, m0, wallH: wallH)
        falseFront(&w, b, m, wallH: wallH, band: blk("blue_terracotta", m.log))
        let pane = blk("glass_pane", m.wall)
        for v in 0..<l.d { for u in 0..<l.w {
            let edgeU = u == 0 || u == l.w - 1, edgeV = v == 0 || v == l.d - 1
            guard edgeU || edgeV, !(edgeU && edgeV) else { continue }
            if (edgeV && u % 2 == 0) || (edgeU && v % 2 == 0) { b.set(&w, u, 6, v, pane) }
        } }
        // Porch/awning at ground-floor height (wallH: 5 -> roof at dy = 4, flush with the 2nd floor deck and below dy = 6 windows).
        if l.frontier { boardwalk(&w, b, m, wallH: 5) }
        else { for u in thru(max(0, l.w / 2 - 2), min(l.w - 1, l.w / 2 + 2)) { b.set(&w, u, 4, -1, m.slab) } }
        sign(&w, b, u: l.w / 2, dy: 2, v: -1, lines: ["", "Inn", "Rooms & Baths", ""])
        if l.w >= 6 { sign(&w, b, u: 1, dy: 1, v: -1, lines: ["INN & ROOMS", "Room: $3.00", "Bath: $1.00", "Ask inside"]) }

        let lantern = blk("lantern", AIR)
        let counter = blk("stripped_\(Blocks.key(m.log).replacingOccurrences(of: "stripped_", with: ""))", m.planks)
        let sideTbl = b.furniture(m, "side_table") ?? m.planks
        var rng = SRng(l.seed &+ 0x1AA0)

        b.fill(&w, 1, 4, 1, l.w - 2, 4, l.d - 2, m.floor)

        if l.w >= 7 && l.d >= 6 {
            let cv = l.d - 3
            let cEnd = max(2, l.w - 4)
            for u in 1...cEnd { b.set(&w, u, 0, cv, counter) }
            b.set(&w, min(l.w / 2, cEnd), 1, cv, lantern)
            let till = world(l, 1, l.d - 2)
            w.chest(till.0, l.y, till.1, loot: "shop_register", seed: rng.next(), facing: dir(l, 1))
            let ku = min(max(2, l.w / 2), cEnd)
            let (kx, kz) = world(l, ku, cv + 1)
            w.mob("villager:shop_saloon", V3(Float(kx) + 0.5, Float(l.y), Float(kz) + 0.5))

            let stool = b.seat(m, "stool")
            let round = b.furniture(m, "round_table") ?? b.furniture(m, "table") ?? m.fence
            if l.w >= 9 && cv >= 4 {
                b.set(&w, 2, 0, 2, round)
                b.set(&w, 1, 0, 2, stool); b.set(&w, 3, 0, 2, stool)
            } else if cv >= 3 {
                b.set(&w, 1, 0, 1, round)
                b.set(&w, 2, 0, 1, stool)
            }
            b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
            b.set(&w, l.w - 2, 2, 1, b.wallTorch(facing: 3))
            b.set(&w, 2, 2, l.d - 2, b.wallTorch(facing: 1))

            let su = l.w - 2
            for step in 0..<4 {
                let sv = 1 + step
                for fy in 0..<step { b.set(&w, su, fy, sv, m.planks) }
                b.set(&w, su, step, sv, b.stair(m.stairs, high: 0))
            }
            for sv in 1...4 {
                b.set(&w, su, 4, sv, AIR); b.set(&w, su, 5, sv, AIR); b.set(&w, su, 6, sv, AIR)
            }
            for sv in 1...3 { b.set(&w, su - 1, 5, sv, m.fence) }

            if l.w >= 9 && l.d >= 7 {
                let hallWall = l.d - 3
                let mid = (l.w - 3) / 2
                b.fill(&w, 1, 5, hallWall, l.w - 4, 7, hallWall, m.planks)
                b.fill(&w, mid, 5, 1, mid, 7, hallWall, m.planks)
                let d1 = max(1, mid - 1)
                b.set(&w, d1, 5, hallWall, m.door + BlockID(dir(l, 0)))
                b.set(&w, d1, 6, hallWall, m.door + BlockID(dir(l, 0) + 8))
                bed(&w, b, m, u: 1, v: 1, dy: 5)
                b.set(&w, 1, 5, 3, sideTbl); b.set(&w, 1, 6, 3, lantern)
                let d2 = min(l.w - 4, mid + 1)
                b.set(&w, d2, 5, hallWall, m.door + BlockID(dir(l, 0)))
                b.set(&w, d2, 6, hallWall, m.door + BlockID(dir(l, 0) + 8))
                bed(&w, b, m, u: l.w - 4, v: 1, dy: 5)
                b.set(&w, l.w - 4, 5, 3, sideTbl); b.set(&w, l.w - 4, 6, 3, lantern)
                b.set(&w, 1, 6, l.d - 2, b.wallTorch(facing: 1))
                let rtu = (l.w - 3) % 2 == 1 ? l.w - 3 : l.w - 4
                b.set(&w, rtu, 6, l.d - 2, b.wallTorch(facing: 1))
            } else {
                bed(&w, b, m, u: 1, v: 1, dy: 5)
                bed(&w, b, m, u: 3, v: 1, dy: 5)
                b.set(&w, 2, 5, 1, sideTbl); b.set(&w, 2, 6, 1, lantern)
                b.set(&w, 1, 6, l.d - 2, b.wallTorch(facing: 1))
            }
        } else {
            b.set(&w, 1, 0, 2, counter); b.set(&w, 2, 0, 2, counter)
            b.set(&w, 1, 1, 2, lantern)
            let till = world(l, 1, l.d - 2)
            w.chest(till.0, l.y, till.1, loot: "shop_register", seed: rng.next(), facing: dir(l, 1))
            let (kx, kz) = world(l, 2, l.d - 2)
            w.mob("villager:shop_saloon", V3(Float(kx) + 0.5, Float(l.y), Float(kz) + 0.5))
            b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
            let lad = blk("ladder", AIR)
            if lad != AIR {
                b.set(&w, l.w - 2, 4, 1, AIR)
                for dy in 0...4 { b.set(&w, l.w - 2, dy, 1, lad + BlockID(dir(l, 3))) }
            }
            bed(&w, b, m, u: 1, v: 1, dy: 5)
            b.set(&w, 2, 5, l.d - 2, sideTbl); b.set(&w, 2, 6, l.d - 2, lantern)
            b.set(&w, 1, 6, l.d - 2, b.wallTorch(facing: 1))
        }
    }

    // False front: the street wall carried up past the roof ridge (ridge = wallH + (d + 1) / 2, house's gable) and over
    // the eaves at the sides, capped with a slab line, with a coloured band; the eave in front of it is cut away so the
    // facade reads as one flat face from the street. Returns the top row.
    @discardableResult
    static func falseFront(_ w: inout StructWriter, _ b: LB, _ m: Mats, wallH: Int, band: BlockID) -> Int {
        let l = b.l
        let top = wallH + (l.d + 1) / 2 + 1
        for u in -1...l.w {
            for dy in wallH..<top { b.set(&w, u, dy, 0, m.planks) }
            b.set(&w, u, top, 0, m.slab)
            b.set(&w, u, wallH, -1, AIR)
        }
        // The facade's side wings (u -1 and w) stand on log posts down to the ground; they hung over air before
        // (structcheck village floating 9 after the towns merge).
        for u in [-1, l.w] {
            let (x, z) = world(l, u, 0)
            w.pillarDown(x, l.y + wallH - 1, z, m.log, minY: l.y - 40)
        }
        // A coloured band across the front, the shop's colour.
        for u in 0..<l.w { b.set(&w, u, top - 2, 0, band) }
        return top
    }

    static func shopInside(_ w: inout StructWriter, _ b: LB, _ m: Mats, _ k: ShopKind, saloon: Bool) {
        let l = b.l
        // Inside: the counter, the keeper behind it, the bed in the back corner, light.
        let cv = l.d - 4                                   // counter row: the keeper behind it (cv + 1), fittings at the back (d - 2)
        let counter = blk("stripped_\(Blocks.key(m.log).replacingOccurrences(of: "stripped_", with: ""))", m.planks)
        for u in 1...(l.w - 3) { b.set(&w, u, 0, cv, counter) }
        b.set(&w, l.w / 2 - 1, 1, cv, blk("lantern", AIR))
        bed(&w, b, m, u: 1, v: cv + 1)
        b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
        b.set(&w, l.w - 2, 2, 1, b.wallTorch(facing: 3))
        fittings(&w, b, m, k, cv: cv)
        // The till: a strongbox behind the counter, beside the bed's head, reached from behind the counter (Oct 11
        // playtest P24: towns had nothing worth stealing). Taking from it is theft like any town container (TownLaw).
        let till = world(l, 2, l.d - 2)
        var rng = SRng(l.seed &+ 0x7111)
        w.chest(till.0, l.y, till.1, loot: k == .general ? "shop_register_general" : "shop_register", seed: rng.next(), facing: dir(l, 1))
        let (x, z) = world(l, l.w / 2, cv + 1)
        w.mob("villager:shop_\(k.rawValue)", V3(Float(x) + 0.5, Float(l.y), Float(z) + 0.5))
        // A townsperson or two about the place (customers by day, sleeping in town at night).
        // P149: a saloon has patrons at its tables (three, plus one at the bar).
        if saloon { for (u, v) in [(2, 3), (l.w - 3, 3), (4, 6), (l.w / 2 + 1, cv - 1)] { villager(&w, b, u: u, v: v) } }
    }

    static func bandColor(_ k: ShopKind) -> String {
        switch k {
        case .general: return "green"
        case .gunsmith: return "black"
        case .butcher: return "red"
        case .doctor: return "white"
        case .stable: return "brown"
        case .tailor: return "purple"
        case .blacksmith: return "gray"
        case .saloon: return "orange"
        }
    }

    // What each shop has behind and around the counter.
    static func fittings(_ w: inout StructWriter, _ b: LB, _ m: Mats, _ k: ShopKind, cv: Int) {
        let l = b.l
        let back = l.d - 2
        let g = { (n: String) in blk(n, m.planks) }
        switch k {
        case .general:
            for u in 3...(l.w - 2) { b.set(&w, u, 0, back, g("bookshelf")); b.set(&w, u, 1, back, u % 2 == 0 ? g("hay_block") : g("crafting_table")) }
            b.set(&w, l.w - 2, 0, 1, g("pumpkin")); b.set(&w, l.w - 3, 0, 1, g("melon"))
        case .gunsmith:
            for u in 3...(l.w - 2) { b.set(&w, u, 1, back, g("iron_bars")); b.set(&w, u, 0, back, g("dark_oak_planks")) }
            b.set(&w, l.w - 2, 0, 1, g("target"))
        case .butcher:
            for u in 3...(l.w - 2) { b.set(&w, u, 0, back, g("smooth_stone")); b.set(&w, u, 2, back, g("iron_chain")) }
            b.set(&w, 3, 1, back, g("furnace") + BlockID(dir(l, 1)))
        case .doctor:
            for u in 3...(l.w - 2) { b.set(&w, u, 0, back, g("bookshelf")); b.set(&w, u, 1, back, g("white_wool")) }
            b.set(&w, l.w / 2, 3, 0, g("red_wool"))                      // a red cross on the front
            b.set(&w, l.w / 2 - 1, 3, 0, g("white_wool")); b.set(&w, l.w / 2 + 1, 3, 0, g("white_wool"))
            b.set(&w, l.w - 2, 0, 1, g("white_wool")); b.set(&w, l.w - 2, 1, 1, g("white_carpet"))   // an examining couch
        case .stable:
            for u in 3...(l.w - 2) { b.set(&w, u, 0, back, g("hay_block")); b.set(&w, u, 1, back, u % 2 == 0 ? g("hay_block") : AIR) }
            b.set(&w, l.w - 2, 0, 1, g("hay_block")); b.set(&w, l.w - 2, 1, 1, g("hay_block"))
        case .tailor:
            let wools = ["red_wool", "blue_wool", "yellow_wool", "green_wool", "white_wool", "black_wool"]
            for u in 3...(l.w - 2) { b.set(&w, u, 0, back, g(wools[u % wools.count])); b.set(&w, u, 1, back, g(wools[(u + 3) % wools.count])) }
            b.set(&w, l.w - 2, 0, 1, g("white_carpet"))
        case .blacksmith:
            b.set(&w, 3, 0, back, g("furnace") + BlockID(dir(l, 1))); b.set(&w, 4, 0, back, g("furnace") + BlockID(dir(l, 1)))
            b.set(&w, l.w - 2, 0, back, g("anvil")); b.set(&w, 5, 0, back, g("cobblestone")); b.set(&w, 5, 1, back, g("cobblestone"))
            b.set(&w, l.w - 2, 0, 1, g("iron_block"))
        case .saloon:
            // A long bar is the counter; tables (a fence post and a plate) with stools in the front room; a piano.
            let table = blk(Blocks.key(m.fence), m.planks), top = blk("oak_pressure_plate", AIR)
            let stool = b.seat(m, "stool")                     // P370 (b): a real stool (was a slab)
            let round = b.furniture(m, "round_table")            // (Nov 14 evening: a round table; was a post and a plate)
            for (u, v) in [(3, 2), (l.w - 4, 2), (3, 5), (l.w - 4, 5), (l.w / 2, 3)] where v < cv - 1 {
                if let r = round { b.set(&w, u, 0, v, r) } else { b.set(&w, u, 0, v, table); b.set(&w, u, 1, v, top) }
                b.set(&w, u - 1, 0, v, stool); b.set(&w, u + 1, 0, v, stool)
            }
            for u in 2...(l.w - 3) where u % 2 == 0 { b.set(&w, u, 1, back, g("glass")) }
            b.set(&w, l.w - 2, 0, 1, g("jukebox")); b.set(&w, l.w - 2, 0, 2, g("dark_oak_planks"))
            b.set(&w, l.w / 2, 3, 1, blk("lantern", AIR))
        }
    }

    // A wall sign with text on the local spot, facing the street side (toward -v).
    static func sign(_ w: inout StructWriter, _ b: LB, u: Int, dy: Int, v: Int, lines: [String]) {
        let base = blk("spruce_sign", blk("oak_sign", AIR))
        guard base != AIR else { return }
        let (x, z) = world(b.l, u, v)
        let y = b.l.y + dy
        guard w.inside(x, y, z) else { return }
        w.set(x, y, z, base + BlockID(4 + dir(b.l, 1)))
        let be = BlockEntity(.sign)
        be.lines = lines
        w.entities.append((IVec3(x, y, z), be))
    }
}
