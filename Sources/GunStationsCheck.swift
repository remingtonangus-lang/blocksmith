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
            let held = guns.filter { VehicleGunners.station($0, on: s, ships) != nil }.count
            for t in guns where VehicleGunners.station(t, on: s, ships) == nil {
                let r = IVec3(Int(floor(t.mountLocal.x)), Int(floor(t.mountLocal.y)) - 1, Int(floor(t.mountLocal.z)))
                print("gunstations: \(s.name) gun at ring \(r.x),\(r.y),\(r.z) (hull \(s.grid.sx)x\(s.grid.sy)x\(s.grid.sz)) has no station")
            }
            do {
                print("gunstations: \(s.name) stations (chair, console): " + guns.compactMap { VehicleGunners.station($0, on: s, ships) }
                    .map { "\($0.chair.x),\($0.chair.y),\($0.chair.z) / \($0.console.x),\($0.console.y),\($0.console.z)" }.joined(separator: "; "))
            }
            check(!guns.isEmpty && held == guns.count,
                  "gunstations: the \(s.name) has a station (console and chair) for \(held) of its \(guns.count) guns (\(ships.turrets(of: s).count) mounts)")
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
        Capital.crashLog = []
        var ran = 0, lostHelm = false
        func run(_ frames: Int, each: () -> Void = {}) {
            for _ in 0..<frames {
                g.player.pos = s.toWorld(stand); g.player.vel = .zero
                g.health = 20; g.alive = true
                g.tick(1.0 / 60)
                ran += 1
                // (why a run went wrong: the hull's motion, its crashes, the helm lost)
                if ran % 30 == 1 || (!Capital.crashLog.isEmpty) || (ships.pilot !== s && !lostHelm) {
                    print(String(format: "gunstations: frame %d: frigate at %.1f,%.1f,%.1f, speed %.2f, turn %.3f,%.3f,%.3f rad/s, asleep %@, pilot %@", ran,
                                 s.pos.x, s.pos.y, s.pos.z, simd_length(s.vel), s.angVel.x, s.angVel.y, s.angVel.z, s.asleep ? "yes" : "no",
                                 ships.pilot === s ? "him" : "none") + (Capital.crashLog.isEmpty ? "" : "; " + Capital.crashLog.joined(separator: ", ")))
                    Capital.crashLog = []
                    if ships.pilot !== s { lostHelm = true }
                }
                each()
            }
        }
        run(60)
        for (i, m) in hands.enumerated() {
            print(String(format: "gunstations: hand %d: seated %@, riding %@, on deck %@, %.1f off the hull, health %.0f, hired %@", i,
                         VehicleGunners.seated(m) ? "yes" : "no", VehicleGunners.riding(m) ? "yes" : "no", m.deck === s ? "yes" : "no",
                         ships.boundsDistance(s, m.pos), Float(m.health), m.hired ? "yes" : "no"))
        }
        print("gunstations: he drives \(ships.pilot === s ? "it" : "nothing"), his: \(ships.isYours(s)), free guns with stations \(ships.turrets(of: s).filter { !$0.cannons.isEmpty && !VehicleGunners.manned($0) && VehicleGunners.station($0, on: s, ships) != nil }.count), seats \(VehicleGunners.seats.count)")
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
        // (clear of her side: the Stormwarden is 113 wide, and a pad 45 off her middle sat inside her beam, where she drove
        // into it)
        let rp = s.pos + simd_normalize(s.dirToWorld(V3(1, 0, 0)) * V3(1, 0, 1)) * (Float(s.grid.sx) / 2 + 10)
        let rx = Int(floor(rp.x)), ry = Int(floor(rp.y)), rz = Int(floor(rp.z))
        _ = w.loadSync(center: rp, radius: 1)
        for dz in -1...1 { for dx in -1...1 { w.setBlock(rx + dx, ry - 1, rz + dz, STONE) } }
        defer { for dz in -1...1 { for dx in -1...1 { w.setBlock(rx + dx, ry - 1, rz + dz, AIR) } } }
        let raider = Mob(.zombie, at: V3(Float(rx) + 0.5, Float(ry), Float(rz) + 0.5))
        raider.aggro = true
        g.mobs.mobs.append(raider)
        let v0 = ShipManager.crewVolleys
        var drift: Float = 0
        var hp = seated.map { $0.health }, frame = 0
        var last = seated.map { $0.pos }
        let onHit0 = Mob.onHit
        Mob.onHit = { m, src, dmg in
            guard let i = seated.firstIndex(where: { $0 === m }), dmg > 30 else { return }
            print(String(format: "gunstations: hand %d hit for %d from %.1f off it at frame %d", i, dmg, simd_length(src - m.pos), frame))
            for l in Thread.callStackSymbols.prefix(10) { print("gunstations:    " + l) }
        }
        defer { Mob.onHit = onHit0 }
        run(360) {
            frame += 1
            for (i, m) in seated.enumerated() where simd_length(m.pos - last[i]) > 4 {
                print(String(format: "gunstations: hand %d jumped %.1f at frame %d (%.1f,%.1f,%.1f -> %.1f,%.1f,%.1f; seat %@, deck %@, health %d)", i,
                             simd_length(m.pos - last[i]), frame, last[i].x, last[i].y, last[i].z, m.pos.x, m.pos.y, m.pos.z,
                             VehicleGunners.seats.contains { $0.mob === m } ? "yes" : "no", m.deck === s ? "frigate" : (m.deck == nil ? "none" : "other"), m.health))
            }
            last = seated.map { $0.pos }
            for (i, m) in seated.enumerated() where m.health < hp[i] {
                print(String(format: "gunstations: hand %d hurt %d at frame %d (%.1f off its chair; shells about %d; raider %.0f off)", i, hp[i] - m.health, frame,
                             VehicleGunners.seats.first(where: { $0.mob === m }).map { simd_length(s.toWorld($0.local) - m.pos) } ?? -1,
                             ships.shells.count, simd_length(raider.pos - m.pos)))
                hp[i] = m.health
            }
            raider.health = 20; raider.aggro = true
            for (i, m) in seated.enumerated() {
                guard let st = VehicleGunners.seats.first(where: { $0.mob === m }) else {
                    if drift < 99 { print("gunstations: hand \(i) left its seat (health \(m.health), hired \(m.hired))") }
                    drift = 99; continue
                }
                let off = simd_length(s.toWorld(st.local) - m.pos)
                if off > 0.5 && drift <= 0.5 {
                    print(String(format: "gunstations: hand %d %.2f off its chair (ship moving %.2f m/s, on deck %@, station %@)", i, off,
                                 simd_length(s.vel), m.deck === s ? "yes" : "no", st.station ? "yes" : "no"))
                }
                drift = max(drift, off)
            }
        }
        let volleys = ShipManager.crewVolleys - v0
        check(volleys > 0 && drift < 0.5, String(format: "gunstations: the hands at the stations fire %d volleys at a raider while he holds the helm, staying at their chairs (%.2f)", volleys, drift))
        g.mobs.mobs.removeAll { $0 === raider }
    }
}
