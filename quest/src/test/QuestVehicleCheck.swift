import Foundation
import simd
import Metal

// P449 (Oct 25 09:02-09:19, the Ash Vault's vehicles and the Stormwarden Frigate). Checks: the sidecar's wheels are one
// block each (not a plus of five drawn as five discs), a wheel built of several blocks is drawn as one tyre, the frigate
// is steered from its bridge (one helm, not a parked dropship's), a hull's armour plates come off on the side hit,
// a tank shoves through timber and glass (a truck only through glass), and tracks churn the ground they run on.
//   questcheck --vehiclecheck
enum QuestVehicleCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") vehiclecheck: \(what)"); if !ok { fails += 1 } }

        let w = World(seed: 4797859299361840175, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.player.pos = V3(-496.5, 72 + Float(YOFF), 6102.5)
        _ = w.loadSync(center: g.player.pos, radius: 3)
        g.tick(1.0 / 72)

        // The sidecar: three wheels, each one block, drawn as it is.
        let sc = w.ships.spawn(AshCommandeer.sidecar(), at: g.player.pos + V3(0, 40, 0), yaw: 0, name: AshCommandeer.sidecarName, role: "")
        let wheels = sc.wheelParts.map { "\($0.size.x)x\($0.size.y)x\($0.size.z)" }
        check(sc.wheelParts.count == 3 && sc.wheelParts.allSatisfy { $0.blocks.count == 1 && $0.round == nil },
              "the sidecar has three single-block wheels (\(wheels.joined(separator: ", ")))")
        check(sc.helm != nil, "the sidecar can be driven")
        w.ships.remove(sc)
        // A wheel of five blocks (the old plus) is one tyre.
        let bp = Blueprint()
        for y in 0...2 { for z in 0...2 where (y - 1) * (y - 1) + (z - 1) * (z - 1) <= 1 { bp.set(0, y, z, "ship_wheel") } }
        bp.set(1, 1, 1, "oak_planks"); bp.set(1, 2, 1, "ship_helm[south]")
        let pl = w.ships.spawn(bp, at: g.player.pos + V3(0, 40, 0), yaw: 0, name: "test", role: "")
        check(pl.wheelParts.count == 1 && pl.wheelParts[0].round != nil,
              "a wheel of five blocks is drawn as one tyre (\(pl.wheelParts.count) parts, round \(pl.wheelParts.first?.round.map { Blocks.key($0) } ?? "none"))")
        w.ships.remove(pl)

        // The Stormwarden Frigate: steered from one helm, on its bridge (over the hangar deck).
        let fr = Capital.makeShips(Capital.frigate(), ids: Array(9000..<9024), name: "Stormwarden Frigate", role: "warfrigate", faction: .stormwarden)[0]
        var helms: [IVec3] = []
        let gr = fr.grid
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx where ShipParts.kinds[Int(gr.get(x, y, z))] == .helm { helms.append(IVec3(x, y, z)) } } }
        let at = fr.helm.map { "\($0.x) \($0.y) \($0.z)" } ?? "none"
        check(helms.count == 1 && fr.helm == helms.first, "the frigate has one helm, the one it is steered from (\(helms.count) helms, steered at \(at) of \(gr.sx)x\(gr.sy)x\(gr.sz))")
        check((fr.helm?.y ?? 0) > 26 + 6, "the frigate's helm stands over the hangar deck (y \(fr.helm?.y ?? -1))")

        // Armour plates: the sector a hit lands on, and a plate coming off on the side hit.
        check(AshArmour.sector(angle: 0) == 0 && AshArmour.sector(angle: .pi / 3) == 1 && AshArmour.sector(angle: .pi) == 3
              && AshArmour.sector(angle: -.pi / 3) == 5 && AshArmour.sector(angle: 2 * .pi / 3) == 2, "plates by bearing: front, quarters, back")
        let tank = Mob(.ashTank, at: g.player.pos + V3(0, 0, -20))
        tank.yaw = 0                                                     // (facing -Z)
        let front = tank.pos + V3(0, 1, -8), back = tank.pos + V3(0, 1, 8)
        var hits = 0
        while tank.armourLost & 1 == 0 && hits < 40 { tank.hit(from: front, damage: 10, knockback: 0); hits += 1 }
        check(tank.armourLost == 1, "a tank's front plate comes off after \(hits) hits of 10 from the front, the others still on (lost \(tank.armourLost))")
        let h0 = tank.health
        tank.hit(from: back, damage: 10, knockback: 0)
        let onBack = h0 - tank.health
        let h1 = tank.health
        tank.hit(from: front, damage: 10, knockback: 0)
        let onBare = h1 - tank.health
        check(onBare > onBack, "a hit on the bare front does more than one on the back's plate (\(onBare) against \(onBack))")
        check(!AshArmour.shed.isEmpty, "the plate coming off is queued for its clang and sparks")
        AshArmour.shedEffects(g)
        var parts: [Part] = ashVehicleParts(tank)
        let bare = parts.filter { $0.pattern == 4 }.count
        tank.armourLost = 0
        parts = ashVehicleParts(tank)
        check(bare > parts.filter { $0.pattern == 4 }.count, "the bare side is drawn torn")

        // Ploughing: a wall of planks and glass in front of a moving tank goes; a truck only gets through the glass.
        func top(_ x: Int, _ z: Int) -> Int {
            var y = CH - 1
            while y > 1 && !w.groundAt(x, y, z) && w.builtBlock(x, y, z) == AIR { y -= 1 }
            return y
        }
        let tx = -470, tz = 6110
        var ty = 0
        for dx in -3...3 { for dz in -6...0 { ty = max(ty, top(tx + dx, tz + dz) + 1) } }
        func wall() {
            w.restoring = true
            for dx in -1...1 { for dy in 0..<3 { w.setBlock(tx + dx, ty + dy, tz - 4, Blocks.id(dy == 1 ? "glass" : "oak_planks")) } }
            w.restoring = false
        }
        func standing() -> (Int, Int) {                               // (the column in front of its middle)
            var planks = 0, glass = 0
            for dy in 0..<3 {
                let k = Blocks.key(Blocks.groupBase[Int(w.builtBlock(tx, ty + dy, tz - 4))])
                if k == "oak_planks" { planks += 1 } else if k == "glass" { glass += 1 }
            }
            return (planks, glass)
        }
        for kind in [MobKind.ashTank, .ashTruck] {
            wall()
            let m = Mob(kind, at: V3(Float(tx) + 0.5, Float(ty), Float(tz) + 0.5))
            m.yaw = 0
            m.pos.z = Float(tz - 4) + 0.5 + (kind == .ashTank ? 3.6 : 3.2)       // (the wall just past its nose)
            for _ in 0..<6 { _ = m.ashPlough(g, 4) }
            let (p, gl) = standing()
            if kind == .ashTank { check(p == 0 && gl == 0, "a tank drives through a wall of planks and glass (\(p) planks, \(gl) glass left in front of it, of 2 and 1)") }
            else { check(p == 2 && gl == 0, "a truck breaks the glass but not the planks (\(p) planks, \(gl) glass left)") }
        }
        let n0 = g.drops.items.count
        g.tick(1.0 / 72)
        check(g.drops.items.count == n0, "what a hull ploughs through leaves nothing to pick up")

        // Tracks: the grass under a tank's tracks turns to churned dirt.
        let gx = -480, gz = 6090
        let gy = top(gx, gz) + 1
        let mat = w.materialAt(gx, gy - 1, gz)
        let tk = Mob(.ashTank, at: V3(Float(gx) + 0.5, Float(gy), Float(gz) + 0.5))
        tk.yaw = 0; tk.onGround = true
        let t0 = AshSeat.tracked
        for _ in 0..<3 { tk.ashTracks(g, 4) }
        var coarse = 0
        for dx in -3...3 { for dz in -3...3 { for y in (gy - 3)...gy where Blocks.key(w.materialAt(gx + dx, y, gz + dz)) == "coarse_dirt" { coarse += 1 } } }   // (under a snow layer: a block lower)
        check(AshSeat.tracked > t0 && coarse > 0, "a tank's tracks churn the ground (\(Blocks.key(mat)) under it; \(AshSeat.tracked - t0) cells, \(coarse) coarse dirt round it)")
        check(FieldMat.index[Int(Blocks.id("coarse_dirt"))] != 0, "churned dirt stays part of a field world's ground")

        print(fails == 0 ? "vehiclecheck: all passed" : "vehiclecheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
