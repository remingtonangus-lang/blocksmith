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
    static let footprint = IVec3(11, 7, 14)         // the clear space it needs beside the Works (x, y, z)

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
    static func missing(_ g: Game) -> [(String, Int)] {
        guard g.survival else { return [] }
        return bill.compactMap { (k, n) in
            guard Items.has(k) else { return nil }
            let have = g.ammoCount(k)                  // (counts any item by key: inventory and off hand)
            return have < n ? (k, n - have) : nil
        }
    }

    // Use on the block: build the tank on the side away from the player, if the parts are there and so is the room.
    static func use(_ g: Game, _ p: IVec3) {
        let short = missing(g)
        if !short.isEmpty {
            let list = short.prefix(3).map { "\($0.1) \(Items.def(Items.id($0.0)).display)" }.joined(separator: ", ")
            g.onToast?("Vehicle Works: a Field Tank needs \(list)\(short.count > 3 ? "..." : "") more")
            return
        }
        // The side of the Works facing away from the player, the tank's long axis pointing away too.
        let d = V2(Float(p.x) + 0.5 - g.player.pos.x, Float(p.z) + 0.5 - g.player.pos.z)
        let alongX = abs(d.x) > abs(d.y)
        let sgn: Float = alongX ? (d.x >= 0 ? 1 : -1) : (d.y >= 0 ? 1 : -1)
        let gap = Float(footprint.z) / 2 + 1.5
        let c = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5) + (alongX ? V3(sgn * gap, 0, 0) : V3(0, 0, sgn * gap))
        guard clear(g.world, centre: c, alongX: alongX) else {
            g.onToast?("Vehicle Works: clear a \(footprint.x) x \(footprint.z) yard beside it first")
            return
        }
        if g.survival { for (k, n) in bill where Items.has(k) { g.takeAmmo(k, n) } }
        // Heading: the tank's front (-Z in the blueprint) points away from the Works.
        let yaw: Float = alongX ? (sgn > 0 ? -.pi / 2 : .pi / 2) : (sgn > 0 ? .pi : 0)
        let s = g.world.ships.spawn(fieldTank(), at: c + V3(0, 3, 0), yaw: yaw, name: "Field Tank", role: "")
        s.role = nil
        let lift = c.y + 0.6 - s.toWorld(V3(0, s.localMin.y, 0)).y
        s.pos.y += lift
        s.prevPos = s.pos
        s.updateBounds()
        s.initialBlocks = s.blockCount
        g.sfx(.engineStart, 1, at: c)
        g.onToast?("A Field Tank rolls out of the Vehicle Works")
    }

    static func clear(_ w: World, centre c: V3, alongX: Bool) -> Bool {
        let hx = (alongX ? footprint.z : footprint.x) / 2, hz = (alongX ? footprint.x : footprint.z) / 2
        let x0 = Int(floor(c.x)), z0 = Int(floor(c.z)), y0 = Int(floor(c.y))
        for z in (z0 - hz)...(z0 + hz) { for x in (x0 - hx)...(x0 + hx) {
            guard w.isLoaded(x, z) else { return false }
            for y in y0..<(y0 + footprint.y) where Blocks.collide[Int(w.block(x, y, z))] { return false }
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
