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
        let wallH = saloon ? 6 : 5
        house(&w, b, m0, wallH: wallH)
        // False front: the street wall carried up past the roof ridge (ridge = wallH + (d + 1) / 2, house's gable) and
        // over the eaves at the sides, capped with a slab line; the eave in front of it is cut away so the facade reads
        // as one flat face from the street.
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
        let band = blk(bandColor(k) + "_terracotta", m.log)
        for u in 0..<l.w { b.set(&w, u, top - 2, 0, band) }
        // Awning over the doorway, the sign above the door.
        for u in max(0, l.w / 2 - 2)...min(l.w - 1, l.w / 2 + 2) { b.set(&w, u, wallH - 1, -1, m.slab) }
        sign(&w, b, u: l.w / 2, dy: 2, v: -1, lines: ["", k.name, "", ""])
        // Inside: the counter, the keeper behind it, the bed in the back corner, light.
        let cv = l.d - 4                                   // counter row: the keeper behind it (cv + 1), fittings at the back (d - 2)
        let counter = blk("stripped_\(Blocks.key(m.log).replacingOccurrences(of: "stripped_", with: ""))", m.planks)
        for u in 1...(l.w - 3) { b.set(&w, u, 0, cv, counter) }
        b.set(&w, l.w / 2 - 1, 1, cv, blk("lantern", AIR))
        bed(&w, b, m, u: 1, v: cv + 1)
        b.set(&w, 1, 2, 1, b.wallTorch(facing: 2))
        b.set(&w, l.w - 2, 2, 1, b.wallTorch(facing: 3))
        fittings(&w, b, m, k, cv: cv)
        let (x, z) = world(l, l.w / 2, cv + 1)
        w.mob("villager:shop_\(k.rawValue)", V3(Float(x) + 0.5, Float(l.y), Float(z) + 0.5))
        // A townsperson or two about the place (customers by day, sleeping in town at night).
        if saloon { villager(&w, b, u: l.w / 2, v: 3) }      // between the two tables
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
            let stool = blk("\(Blocks.key(m.slab))", m.planks)
            for (u, v) in [(3, 2), (l.w - 4, 2)] where v < cv {
                b.set(&w, u, 0, v, table); b.set(&w, u, 1, v, top)
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
