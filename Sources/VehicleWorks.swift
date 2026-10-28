import Foundation
import simd

// P54 (Oct 11 evening playtest, design prototype; docs/design/vehicles-p54.md): the Vehicle Works, a workshop block
// that builds a preset vehicle from a bill of parts. Use it with the parts in your inventory and a Field Tank rolls
// out beside it (P477: the Ashguard's tank in blocks: track links, a sunk helm, a long calibre gun), built on
// the ship system (Vessels blueprints), so it drives, takes hits and can be taken apart like any assembled vehicle.
// The other road (building a vehicle block by block round a helm) already works and stays: the Works is the quick,
// fixed design for a price; the helm is the slow, free one.
enum VehicleWorks {
    static let key = "vehicle_works"
    // The bill: a ludicrous amount of iron on top of the parts.
    // (P477: "96 iron ingots, two engines, eight wheels. I like that": the wheels go into its track links; its gun's barrels
    // are on the bill now.)
    static let bill: [(String, Int)] = [("iron_ingot", 96), ("ship_engine", 2), ("ship_wheel", 8), ("ship_turret_ring", 1),
                                        ("ship_cannon", 1), ("gun_barrel_medium", 5), ("gun_barrel_large", 1), ("ship_helm", 1)]
    static let footprint = IVec3(11, 8, 20)         // the clear space beside the Works (x, y, z): the hull, and the barrel past the bow (D43: room for the biggest preset)

    // Field Tank (P477: the Ashguard's tank in blocks, VehicleGuns.swift).
    static func fieldTank() -> Blueprint { VehiclePresets.fieldTank() }

    // What the player is short of (empty: they have it all, or play creative).
    static func missing(_ g: Game, _ list: [(String, Int)] = bill) -> [(String, Int)] {
        guard g.survival else { return [] }
        return list.compactMap { (k, n) in
            guard Items.has(k) else { return nil }
            let have = g.ammoCount(k)                  // (counts any item by key: inventory and off hand)
            return have < n ? (k, n - have) : nil
        }
    }

    // A bill as words: "96 Iron Ingot, 2 Engine, ...".
    static func listed(_ list: [(String, Int)]) -> String {
        list.map { "\($0.1) \(Items.def(Items.id($0.0)).display)" }.joined(separator: ", ")
    }

    // Use on the block: with more than the Field Tank's drawings learned, the Works asks which (D43, VehiclePresets);
    // with a vehicle of yours anywhere or one in its garage, it offers to garage, take out or recall it (D44,
    // VehicleDepot); otherwise it builds the tank.
    static func use(_ g: Game, _ p: IVec3) {
        // (P459: always the list now, so the bill is there to read before building, the Field Tank's too.)
        g.openMenu(VehicleWorksMenu(game: g, at: p))
    }

    // Build a preset on the side away from the player, if the parts are there and so is the room.
    @discardableResult
    static func build(_ g: Game, _ p: IVec3, _ v: VehiclePresets.Preset) -> Bool {
        let short = missing(g, v.bill)
        if !short.isEmpty {
            g.onToast?("Vehicle Works: a \(v.name) needs \(listed(short)) more")
            return false
        }
        guard let (c, yaw) = spot(g, p) else { return false }
        if g.survival { for (k, n) in v.bill where Items.has(k) { g.takeAmmo(k, n) } }
        let s = g.world.ships.spawn(v.blueprint(), at: c + V3(0, 3, 0), yaw: yaw, name: v.name, role: "")
        s.role = nil
        settle(s, on: c)
        s.initialBlocks = s.blockCount
        g.sfx(.engineStart, 1, at: c)
        g.onToast?("A \(v.name) rolls out of the Vehicle Works")
        return true
    }

    // The yard beside the Works on the side away from the player, and the heading away from it (nil, with a toast:
    // not clear).
    // P477 (Oct 27 19:22-19:23: "There's no room beside the works. There's plenty of room everywhere... I can't seem to
    // build it", then "It worked in another place"): only the side away from him was tried, at the Works' own level,
    // so a yard a block higher or lower, or anything on that one side, refused it. Now every side (away from him first,
    // then either hand, then his own side) at the Works' level or up to two blocks above or below it.
    static func spot(_ g: Game, _ p: IVec3) -> (V3, Float)? {
        let d = V2(Float(p.x) + 0.5 - g.player.pos.x, Float(p.z) + 0.5 - g.player.pos.z)
        let alongX0 = abs(d.x) > abs(d.y)
        let sgn0: Float = alongX0 ? (d.x >= 0 ? 1 : -1) : (d.y >= 0 ? 1 : -1)
        let gap = Float(footprint.z) / 2 + 1.5
        let sides: [(Bool, Float)] = [(alongX0, sgn0), (!alongX0, 1), (!alongX0, -1), (alongX0, -sgn0)]
        // (Ground right under the yard's middle first, then a block or two of drop.)
        for loose in [false, true] { for (alongX, sgn) in sides { for dy in [0, 1, -1, 2, -2] {
            let c = V3(Float(p.x) + 0.5, Float(p.y + dy), Float(p.z) + 0.5) + (alongX ? V3(sgn * gap, 0, 0) : V3(0, 0, sgn * gap))
            guard grounded(g.world, centre: c, loose: loose), clear(g.world, centre: c, alongX: alongX) else { continue }
            // Heading: the vehicle's front (-Z in the blueprint) points away from the Works.
            return (c, alongX ? (sgn > 0 ? -.pi / 2 : .pi / 2) : (sgn > 0 ? .pi : 0))
        } } }
        g.onToast?("Vehicle Works: no room")
        return nil
    }

    // Something to stand on under the yard's middle (right under it, or loose: within three), so a vehicle isn't set
    // out over a drop.
    static func grounded(_ w: World, centre c: V3, loose: Bool) -> Bool {
        let x = Int(floor(c.x)), z = Int(floor(c.z)), y = Int(floor(c.y))
        return ((loose ? y - 3 : y - 1)...(y - 1)).contains { w.solidAt(x, $0, z) }
    }

    // Sets a vehicle's wheels down on the yard at c.
    static func settle(_ s: Ship, on c: V3) {
        let lift = c.y + 0.6 - s.toWorld(V3(0, s.localMin.y, 0)).y
        s.pos.y += lift
        s.prevPos = s.pos
        s.updateBounds()
    }

    static func clear(_ w: World, centre c: V3, alongX: Bool) -> Bool {
        let hx = (alongX ? footprint.z : footprint.x) / 2, hz = (alongX ? footprint.x : footprint.z) / 2
        let x0 = Int(floor(c.x)), z0 = Int(floor(c.z)), y0 = Int(floor(c.y))
        for z in (z0 - hz)...(z0 + hz) { for x in (x0 - hx)...(x0 + hx) {
            guard w.isLoaded(x, z) else { return false }
            for y in y0..<(y0 + footprint.y) where w.solidAt(x, y, z) { return false }
        } }
        return true
    }
}

extension BlockRegistry {
    func registerVehicleWorks() {
        guard !has(VehicleWorks.key) else { return }
        var d = BlockDef(VehicleWorks.key, "Vehicle Works")
        d.tex = ["ship_engine_side", "ship_engine_side", "vehicle_works_top", "ship_metal", "ship_engine_side", "ship_engine_side"]
        d.hardness = 3.5; d.resistance = 6; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
        add(d)
    }
}

extension TextureGen {
    // A steel bench top: a riveted plate with a drawing pinned to it.
    static func vehicleWorksPainters(_ p: inout [String: Painter]) {
        p["vehicle_works_top"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x3E4348) }
            if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0xC9A23A) }
            if x >= 4 && x <= 11 && y >= 4 && y <= 11 {
                if x == 4 || x == 11 || y == 4 || y == 11 || (y == 8 && x > 5 && x < 10) { return hex(0x2F4E7A) }
                return hex(0xDCE4EC)
            }
            return hex(0x6E767E, 0.9 + 0.12 * r(x, y, 2690))
        }
    }
}
