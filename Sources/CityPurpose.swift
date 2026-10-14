import Foundation
import simd

// H6: Capital city buildings with a readable purpose, and copper and power in the city. Every office block is one of
// four public buildings, named on a sign over its door and furnished for the job (the reception desk, the desks and the
// chest stay):
//   Clinic          white beds along the back wall, a brewing stand and a cauldron
//   Post Office     barrels of mail along the back wall, a lectern at the counter
//   Records Hall    bookshelves two high along the back wall, a lectern
//   Power Station   a bank of Copper Batteries under copper grates along the back wall, lit copper bulbs, copper
//                   lightning rods on the roof
// Which one is fixed by the building's corner (never a draw from the lot's generator, so the rest of a city that is
// still being generated lays out as before). The plazas' light posts carry a lit copper bulb over a Copper Battery.
enum CityPurpose: Int, CaseIterable {
    case clinic, postOffice, records, powerStation

    var name: String { ["Clinic", "Post Office", "Records Hall", "Power Station"][rawValue] }
    var motto: String { ["Care for every citizen", "Letters and parcels", "Deeds, maps and laws", "Light for the city"][rawValue] }

    static func of(_ fp: CapitalCity.Footprint) -> CityPurpose {
        var h = UInt64(bitPattern: Int64(fp.bx0 &* 73856093 ^ fp.bz0 &* 19349663)) &* 0x9E3779B97F4A7C15
        h ^= h >> 29
        return CityPurpose(rawValue: Int(h % 4)) ?? .records
    }

    static func furnish(_ w: inout StructWriter, _ fp: CapitalCity.Footprint, _ L: Int) {
        func g(_ n: String) -> BlockID? { Blocks.has(n) ? Blocks.id(n) : nil }
        let p = of(fp)
        let bx1 = fp.bx0 + fp.bw - 1, bz1 = fp.bz0 + fp.bd - 1, ex = (fp.bx0 + bx1) / 2
        func free(_ x: Int, _ y: Int, _ z: Int) -> Bool { w.inside(x, y, z) && w.get(x, y, z) == AIR }
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID?) { if let b, free(x, y, z) { w.set(x, y, z, b) } }
        // The name over the door, facing the walkway.
        if let s = g("dark_oak_sign") ?? g("oak_sign"), w.inside(ex, L + 4, fp.bz0 - 1) {
            w.set(ex, L + 4, fp.bz0 - 1, s + 4)
            let be = BlockEntity(.sign)
            be.lines = ["", p.name, p.motto, ""].map { ShopMenu.fit($0, 88) }
            w.entities.append((IVec3(ex, L + 4, fp.bz0 - 1), be))
        }
        let backZ = bz1 - 1
        let xs = Array(stride(from: fp.bx0 + 6, through: bx1 - 3, by: 1))
        switch p {
        case .clinic:
            for x in stride(from: fp.bx0 + 6, through: bx1 - 3, by: 3) {
                guard let bed = g("white_bed"), let head = g("white_bed_head"), free(x, L + 1, backZ - 1), free(x, L + 1, backZ) else { continue }
                w.set(x, L + 1, backZ - 1, bed); w.set(x, L + 1, backZ, head)
            }
            put(fp.bx0 + 2, L + 1, fp.bz0 + 2, g("brewing_stand"))
            put(fp.bx0 + 3, L + 1, fp.bz0 + 2, g("cauldron"))
        case .postOffice:
            for x in xs where (x - fp.bx0) % 3 != 2 { put(x, L + 1, backZ, g("barrel")); if x % 2 == 0 { put(x, L + 2, backZ, g("barrel")) } }
            put(ex + 2, L + 1, fp.bz0 + 3, g("lectern"))
        case .records:
            for x in xs { put(x, L + 1, backZ, g("bookshelf")); put(x, L + 2, backZ, g("bookshelf")) }
            put(ex + 2, L + 1, fp.bz0 + 3, g("lectern"))
        case .powerStation:
            for x in xs {
                put(x, L + 1, backZ, g("redstone_block"))
                put(x, L + 2, backZ, (x - fp.bx0) % 3 == 0 ? g("waxed_copper_bulb[lit]") : g("waxed_copper_grate"))
                put(x, L + 1, backZ - 1, (x - fp.bx0) % 3 == 0 ? g("waxed_cut_copper_slab") : nil)
            }
            // Lightning rods on the roof corners.
            for (x, z) in [(fp.bx0, fp.bz0), (bx1, fp.bz0), (fp.bx0, bz1), (bx1, bz1)] { put(x, L + 6, z, g("waxed_lightning_rod")) }
        }
    }

    // A plaza light post's lamp: a lit copper bulb over a Copper Battery (the light panel where copper is missing).
    static func lamp(_ w: inout StructWriter, _ x: Int, _ y: Int, _ z: Int, fallback: BlockID) {
        if Blocks.has("waxed_copper_bulb[lit]") && Blocks.has("redstone_block") {
            w.set(x, y - 1, z, Blocks.id("redstone_block"))
            w.set(x, y, z, Blocks.id("waxed_copper_bulb[lit]"))
        } else { w.set(x, y, z, fallback) }
    }
}
