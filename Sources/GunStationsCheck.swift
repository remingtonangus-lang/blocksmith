import Foundation
import simd

// P512: questcheck --gunstations: every gun of the capital hulls has its station (a console with a chair at it) in the
// hull near its mount; aboard a Stormwarden frigate he commands, his companions each sit at a gun's station, ride there
// as the frigate moves, and their guns fire on a raider while he drives; anyone left over rides by the bridge.
enum GunStationsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let p0 = g.player.pos
        let was = (g.survival, g.player.flying, g.paused, g.health, g.mobs.mobs)
        defer {
            if ships.pilot != nil { g.leaveHelm() }
            ships.pilot = nil; ships.aboard = nil
            VehicleGunners.seats = []
            (g.survival, g.player.flying, g.paused, g.health, g.mobs.mobs) = was
            g.alive = true; g.player.pos = p0; g.player.vel = .zero
        }
        g.paused = false
        ships.encounters = true; ships.spawnEncounters = false
        defer { ships.spawnEncounters = true }
        var frigate: Ship?
        for (k, kind) in ["frigate", "capfrigate", "crawler"].enumerated() {
            let n0 = ships.list.count
            let home = IVec3(Int(floor(p0.x)) + 500 * (k + 1), 0, Int(floor(p0.z)) + 300)
            _ = w.loadSync(center: V3(Float(home.x), p0.y, Float(home.z)), radius: 4)
            ships.spawnCapital(kind, home: home, yaw: 0, region: nil, sync: true)
            guard let s = ships.list.dropFirst(n0).first(where: { $0.role == kind && $0.parent == nil }) else {
                check(false, "gunstations: the \(kind) spawns"); continue
            }
            let guns = ships.turrets(of: s).filter { !$0.cannons.isEmpty }
            let held = guns.filter { VehicleGunners.station($0, on: s) != nil }.count
            check(!guns.isEmpty && held * 10 >= guns.count * 9,
                  "gunstations: the \(s.name) has a station (console and chair) for \(held) of its \(guns.count) guns")
            if kind == "frigate" { frigate = s } else { ships.remove(s); ships.capState.removeValue(forKey: s.id) }
        }
        guard let s = frigate, let stand = g.helmStand(s) else { check(false, "gunstations: a frigate to command"); return }
        defer { ships.remove(s); ships.capState.removeValue(forKey: s.id) }
        g.survival = true; g.alive = true; g.health = 20
        g.player.flying = false
        g.player.pos = s.toWorld(stand)
        g.takeCommand(s)
        guard ships.pilot === s else { check(false, "gunstations: he takes command of the frigate"); return }
        // Four hands aboard by the bridge.
        g.mobs.mobs.removeAll { $0.hired || $0.villager != nil || $0.kind.hostile }
        var hands: [Mob] = []
        for k in 0..<4 {
            let m = Mob(.villager, at: s.toWorld(stand) + V3(Float(k % 2) * 1.5 - 0.75, 0, Float(k / 2) * 1.5 + 1))
            m.home = m.pos
            Townsfolk.setup(m, tag: "", game: g); g.mobs.mobs.append(m)
            hands.append(g.enlist(m))
        }
        let st0 = VehicleGunners.stations
        func run(_ frames: Int, each: () -> Void = {}) {
            for _ in 0..<frames {
                g.player.pos = s.toWorld(stand); g.player.vel = .zero
                g.health = 20; g.alive = true
                g.tick(1.0 / 60)
                each()
            }
        }
        run(60)
        let seated = hands.filter { VehicleGunners.seated($0) && !VehicleGunners.riding($0) }
        var off: Float = 0
        for m in seated {
            guard let st = VehicleGunners.seats.first(where: { $0.mob === m }) else { continue }
            off = max(off, simd_length(s.toWorld(st.local) - m.pos))
        }
        check(seated.count == 4 && VehicleGunners.stations - st0 == 4 && off < 0.3 && seated.allSatisfy { $0.deck === s },
              String(format: "gunstations: aboard the frigate he commands, %d of 4 hands sit at gun stations (at most %.2f off their chairs)", seated.count, off))
        // A raider out for him off the bow: the hands' guns fire on it while he drives on.
        // (beside the hull's middle, on a stone pad in the air: the crews' foe is sought round the hull's centre)
        let rp = s.pos + simd_normalize(s.dirToWorld(V3(1, 0, 0)) * V3(1, 0, 1)) * 45
        let rx = Int(floor(rp.x)), ry = Int(floor(rp.y)), rz = Int(floor(rp.z))
        _ = w.loadSync(center: rp, radius: 1)
        for dz in -1...1 { for dx in -1...1 { w.setBlock(rx + dx, ry - 1, rz + dz, STONE) } }
        defer { for dz in -1...1 { for dx in -1...1 { w.setBlock(rx + dx, ry - 1, rz + dz, AIR) } } }
        let raider = Mob(.zombie, at: V3(Float(rx) + 0.5, Float(ry), Float(rz) + 0.5))
        raider.aggro = true
        g.mobs.mobs.append(raider)
        let v0 = ShipManager.crewVolleys
        var drift: Float = 0
        run(360) {
            raider.health = 20; raider.aggro = true
            for m in seated { if let st = VehicleGunners.seats.first(where: { $0.mob === m }) { drift = max(drift, simd_length(s.toWorld(st.local) - m.pos)) } }
        }
        let volleys = ShipManager.crewVolleys - v0
        check(volleys > 0 && drift < 0.5, String(format: "gunstations: the hands at the stations fire %d volleys at a raider while he holds the helm, staying at their chairs (%.2f)", volleys, drift))
        g.mobs.mobs.removeAll { $0 === raider }
    }
}
