import Foundation
import simd

// P54 (Oct 11 evening playtest, design prototype; docs/design/vehicles-p54.md): the Vehicle Works, a workshop block
// that builds a preset vehicle from a bill of parts. Use it with the parts in your inventory and a Field Tank rolls
// out beside it: an iron hull on eight wheels, two engines, a helm at the back and a turret with a cannon, built on
// the ship system (Vessels blueprints), so it drives, takes hits and can be taken apart like any assembled vehicle.
// The other road (building a vehicle block by block round a helm) already works and stays: the Works is the quick,
// fixed design for a price; the helm is the slow, free one.
enum VehicleWorks {
    static let key = "vehicle_works"
    // The bill: a ludicrous amount of iron on top of the parts.
    static let bill: [(String, Int)] = [("iron_ingot", 96), ("ship_engine", 2), ("ship_wheel", 8), ("ship_turret_ring", 1),
                                        ("ship_cannon", 1), ("ship_helm", 1)]
    static let footprint = IVec3(11, 8, 20)         // the clear space beside the Works (x, y, z): the hull, and the barrel past the bow (D43: room for the biggest preset)

    // Field Tank, front toward -Z, wheels at y 0, centreline x 0.
    static func fieldTank() -> Blueprint {
        let b = Blueprint()
        for x in [-4, 4] { for zc in [2, 5, 8, 11] {
            for y in 0...2 { for z in (zc - 1)...(zc + 1) where (y - 1) * (y - 1) + (z - zc) * (z - zc) <= 1 { b.set(x, y, z, "ship_wheel") } }
        } }
        b.box(-3, 3, 1, 3, 0, 13, "iron_block", hollow: true)
        b.set(0, 2, 11, "ship_engine"); b.set(0, 2, 2, "ship_engine")
        for z in 0...13 { b.set(-3, 4, z, "iron_bars"); b.set(3, 4, z, "iron_bars") }
        for x in -2...2 { b.set(x, 4, 0, "iron_bars") }
        b.set(0, 4, 12, "ship_helm[south]")
        b.set(0, 4, 5, "ship_turret_ring")
        let t = Blueprint()
        t.box(-2, 2, 0, 2, -2, 2, "iron_block", hollow: true)
        for z in -7 ... -3 { t.set(0, 1, z, "iron_block") }
        t.set(0, 1, -8, "ship_cannon[south]")
        b.turrets.append((IVec3(0, 4, 5), t))
        return b
    }

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
    static func spot(_ g: Game, _ p: IVec3) -> (V3, Float)? {
        let d = V2(Float(p.x) + 0.5 - g.player.pos.x, Float(p.z) + 0.5 - g.player.pos.z)
        let alongX = abs(d.x) > abs(d.y)
        let sgn: Float = alongX ? (d.x >= 0 ? 1 : -1) : (d.y >= 0 ? 1 : -1)
        let gap = Float(footprint.z) / 2 + 1.5
        let c = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5) + (alongX ? V3(sgn * gap, 0, 0) : V3(0, 0, sgn * gap))
        guard clear(g.world, centre: c, alongX: alongX) else {
            g.onToast?("Vehicle Works: no room")
            return nil
        }
        // Heading: the vehicle's front (-Z in the blueprint) points away from the Works.
        return (c, alongX ? (sgn > 0 ? -.pi / 2 : .pi / 2) : (sgn > 0 ? .pi : 0))
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
