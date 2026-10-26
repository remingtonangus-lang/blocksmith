import Foundation
import simd

// P461's fuel check (questcheck --fueldepot): Fuel Depots are one of the base specialities; a taken dropship run dry
// pours a Fuel Can from his pack and flies on; a can used beside it pours in a third of a tank; a Fuel Depot of his
// fills it (and a land vehicle of his) standing there.
enum FuelDepotCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "fueldepot: needs the overworld"); return }
        let depots = (0..<400).filter { BaseSpecialties.of("greywall:\($0),\($0 * 7)") == .fuelDepot }.count
        check(depots >= 25 && depots <= 75, "fueldepot: \(depots) of 400 bases are Fuel Depots (about one in eight)")
        guard Items.has(VehicleDepot.canKey) else { check(false, "fueldepot: the Fuel Can item exists"); return }
        let can = Items.id(VehicleDepot.canKey)
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 4)
        let n0 = w.ships.list.count
        let gx = Int(floor(home.x)), gz = Int(floor(home.z))
        let start = V3(home.x, Float(w.topY(gx, gz)) + 12, home.z - 30)
        w.ships.callDropship(faction: .steelhold, from: start, to: start + V3(0, 0, -60), game: g, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "dropship" && $0.parent == nil }),
              let st = w.ships.capState[s.id] else { check(false, "fueldepot: a Capital Dropship spawns"); return }
        defer {
            if w.ships.pilot === s { w.ships.pilot = nil }
            for t in w.ships.list where t === s || t.parent === s { w.ships.remove(t) }
            w.ships.capState.removeValue(forKey: s.id)
        }
        s.captured = true
        s.vel = .zero; s.angVel = .zero
        // Dry, flown, with two cans in his pack: one is poured in and it flies on.
        for i in 0..<36 where g.inventory.main[i].item == can { g.inventory.main[i] = .empty }
        g.inventory.main[20] = ItemStack(can, 2)
        st.fuel = 0.5
        w.ships.pilot = s
        for _ in 0..<60 {
            s.throttle = 1; s.climb = 0; s.steer = 0; s.strafe = 0; s.boost = false
            w.ships.update(1.0 / 60, game: g)
        }
        w.ships.pilot = nil
        s.throttle = 0
        let left = g.inventory.main[20].count
        check(left == 1 && st.fuel > ShipManager.canFuel - 5,
              String(format: "fueldepot: run dry at the helm it pours a Fuel Can from his pack (%d of 2 left, %.0f s of fuel)", left, st.fuel))
        // A can used beside it: a third of a tank more.
        st.fuel = 100
        let sel = g.inventory.selected
        g.inventory.main[sel] = ItemStack(can, 1)
        g.player.pos = s.toWorld(s.com)
        let used = VehicleDepot.useCan(g)
        check(used && abs(st.fuel - (100 + ShipManager.canFuel)) < 1 && g.inventory.main[sel].isEmpty == g.survival,
              String(format: "fueldepot: a Fuel Can used beside it pours in a third of a tank (%.0f s)", st.fuel))
        g.inventory.main[sel] = .empty
        // A Fuel Depot of his fills it, and a land vehicle of his, standing within its reach.
        st.fuel = 50
        let car = w.ships.spawn(AshCommandeer.sidecar(), at: s.pos + V3(14, 0, 0), yaw: 0, name: "Test Car", role: "")
        car.role = nil
        defer { w.ships.remove(car) }
        VehicleDepot.setLevel(car, 0.1)
        let f0 = BaseSpecialties.filled
        g.fillAtDepot(s.pos + V3(6, 0, 0))
        check(abs(st.fuel - CapitalState.dropFuel) < 1 && VehicleDepot.level(car) > 0.99 && BaseSpecialties.filled - f0 == 2,
              String(format: "fueldepot: a Fuel Depot fills the dropship (%.0f%%) and a car (%.0f%%) parked at it", st.fuel / CapitalState.dropFuel * 100, VehicleDepot.level(car) * 100))
        g.player.pos = home
    }
}
