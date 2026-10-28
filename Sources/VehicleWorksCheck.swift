import Foundation
import simd

// P477's check (questcheck --vehicleworks): every Vehicle Works preset is built of real blocks (no stand-in planks for a
// missing key) inside the Works' yard; the tanks ride on track links that never spin, their guns are cannons with
// calibre barrels firing a flat shell (the Field Tank's four times the old ball's punch), and the Scout Buggy outruns
// the old 16 b/s; with the yard on the far side blocked, or a block lower, the Works still finds room.
enum VehicleWorksCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos
        let base = IVec3(Int(floor(pos0.x)), min(CH - 30, Int(floor(pos0.y)) + 40), Int(floor(pos0.z)))
        // A long platform in the air: 13 wide, 260 long toward -Z.
        func platform(_ block: BlockID) {
            for z in (base.z - 250)...(base.z + 12) { for x in (base.x - 6)...(base.x + 6) {
                w.setBlockAsync(x, base.y - 1, z, block)
                for y in base.y...(base.y + 9) where !w.isAir(x, y, z) { w.setBlockAsync(x, y, z, AIR) }
            } }
        }
        _ = w.loadSync(center: V3(Float(base.x), Float(base.y), Float(base.z) - 120), radius: 10)
        platform(STONE)
        let planks = PLANKS
        for p in VehiclePresets.all {
            let bp = p.blueprint()
            var lo = IVec3(99, 99, 99), hi = IVec3(-99, -99, -99), plank = 0
            func take(_ c: IVec3, _ b: BlockID) {
                if b == planks { plank += 1 }
                lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
            }
            for (c, b) in bp.cells { take(c, b) }
            for (ring, t) in bp.turrets { for (c, b) in t.cells { take(ring + IVec3(0, 1, 0) + c, b) } }
            let size = hi - lo + IVec3(1, 1, 1)
            let fits = size.x <= VehicleWorks.footprint.x && size.y <= VehicleWorks.footprint.y && size.z <= VehicleWorks.footprint.z
            check(plank == 0 && fits, "\(p.name): all real blocks (\(plank) stand-in planks), \(size.x)x\(size.y)x\(size.z) inside the yard \(VehicleWorks.footprint.x)x\(VehicleWorks.footprint.y)x\(VehicleWorks.footprint.z)")

            let s = w.ships.spawn(bp, at: V3(Float(base.x) + 0.5, Float(base.y) + 4, Float(base.z) + 0.5), yaw: 0, name: p.name, role: "")
            s.role = nil
            VehicleWorks.settle(s, on: V3(Float(base.x) + 0.5, Float(base.y), Float(base.z) + 0.5))
            let tracks = s.grid.blocks.filter { ShipParts.track[Int($0)] }.count
            let spun = s.wheelParts.reduce(0) { $0 + $1.blocks.filter { $0 != AIR }.count }
            let turrets = w.ships.turrets(of: s)
            let cals = turrets.flatMap { $0.cannonCalibre }
            let tubes = turrets.flatMap { $0.cannonLength }
            // Fire everything level and look at the shells.
            let n0 = w.ships.shells.count
            for t in turrets { t.reload = 0 }
            w.ships.fire(s, pitch: 0, game: g)
            let shells = Array(w.ships.shells.dropFirst(n0))
            let flat = shells.allSatisfy { $0.kind == 6 && $0.gravity <= 3 && simd_length($0.vel) >= 110 }
            let punch = shells.map { $0.power }.max() ?? 0
            w.ships.shells.removeLast(shells.count)
            var line = "\(p.name): \(s.blockCount) blocks, \(s.engines) engines, \(tracks) track links (\(spun) wheel blocks drawn spinning), guns \(cals) tubes \(tubes), \(shells.count) shells " + String(format: "punch %.1f", punch)
            var ok = cals.allSatisfy { $0 > 0 } && cals.count == shells.count && flat
            switch p.key {
            case "field_tank": ok = ok && tracks == 44 && spun == 0 && cals == [2] && punch >= 10
            case "heavy_tank": ok = ok && tracks == 86 && spun == 0 && cals.sorted() == [1, 3] && punch >= 10
            case "siege_gun": ok = ok && tracks == 56 && spun == 0 && cals == [3] && tubes == [8]
            case "gun_truck": ok = ok && cals == [1] && spun == 6
            default: ok = shells.isEmpty && spun == 4
            }
            // A run along the platform, full throttle for 7 s.
            let z0 = s.pos.z
            s.autopilot = V3(1, 0, 0)
            var top: Float = 0
            for _ in 0..<(7 * 60) {
                w.ships.update(1.0 / 60, game: g)
                top = max(top, simd_length(V2(s.vel.x, s.vel.z)))
            }
            line += String(format: ", top speed %.1f b/s (%.0f blocks)", top, z0 - s.pos.z)
            if p.key == "scout_buggy" { ok = ok && top > 20 }
            else { ok = ok && top > 6 }
            check(ok, line)
            w.ships.remove(s)
        }

        // The yard: walled off away from him (-X) and to both sides, his own side (+X) a block lower: the Works still
        // finds a place there (it only tried the far side, at its own level).
        for z in (base.z - 250)...(base.z + 12) { for x in (base.x - 6)...(base.x + 6) where !w.isAir(x, base.y - 1, z) { w.setBlockAsync(x, base.y - 1, z, AIR) } }
        let wb = IVec3(base.x, base.y, base.z - 120)
        for z in (wb.z - 24)...(wb.z + 24) { for x in (wb.x - 24)...(wb.x + 24) {
            let floorY = x > wb.x + 1 ? wb.y - 2 : wb.y - 1
            w.setBlockAsync(x, floorY, z, STONE)
            for y in (floorY + 1)...(wb.y + 9) where !w.isAir(x, y, z) { w.setBlockAsync(x, y, z, AIR) }
            let wall = x < wb.x - 1 || (x <= wb.x + 1 && abs(z - wb.z) >= 2)
            if wall { for y in wb.y...(wb.y + 9) { w.setBlockAsync(x, y, z, STONE) } }
        } }
        w.setBlock(wb.x, wb.y, wb.z, Blocks.id(VehicleWorks.key))
        g.player.pos = V3(Float(wb.x) + 1.5, Float(wb.y), Float(wb.z) + 0.5)
        let spot = VehicleWorks.spot(g, wb)
        check(spot != nil && (spot?.0.x ?? 0) > Float(wb.x) + 5 && (spot?.0.y ?? 0) == Float(wb.y - 1),
              "yard: walled off away from him and to both sides, the Works sets out on his own side a block lower (" +
              (spot.map { String(format: "%.1f %.1f %.1f", $0.0.x - Float(wb.x), $0.0.y - Float(wb.y), $0.0.z - Float(wb.z)) } ?? "none") + ")")
        g.player.pos = pos0
    }
}
