import Foundation
import simd

// questcheck --gunners (P478, VehicleGunners): his companion climbs onto his gun truck's gun when he takes the helm, and
// rides it there as he drives; with no good name no townsman volunteers, with one a townsman jumps up (one a town a day);
// the gunner lays the gun for its own shell and fires on what is out for him; on foot far off, they climb down.
enum GunnerCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        guard let preset = VehiclePresets.all.first(where: { $0.key == "gun_truck" }) else { check(false, "gunners: the Gun Truck preset"); return }
        let p0 = g.player.pos
        let at = V3(floor(p0.x) + 30.5, p0.y, floor(p0.z) + 0.5)
        _ = w.loadSync(center: at, radius: 6)
        let gy = Float(Capital.firmTop(w, Int(floor(at.x)), Int(floor(at.z))) + 1)
        let s = ships.spawn(preset.blueprint(), at: V3(at.x, gy + 4, at.z), yaw: 0, name: preset.name, role: "")
        s.role = nil
        VehicleWorks.settle(s, on: V3(at.x, gy, at.z))
        guard let stand = g.helmStand(s), let gun = ships.turrets(of: s).first(where: { !$0.cannons.isEmpty }) else {
            check(false, "gunners: the Gun Truck has a helm and a gun"); return
        }
        let mobs0 = g.mobs.mobs, honour0 = Honour.value, survival0 = g.survival
        defer {
            if ships.pilot === s { g.leaveHelm() }
            ships.remove(s); VehicleGunners.seats = []; VehicleGunners.volunteered = [:]
            g.mobs.mobs = mobs0; Honour.value = honour0; g.survival = survival0; g.player.pos = p0
        }
        g.mobs.mobs.removeAll { $0.villager != nil || $0.hired || $0.kind.hostile }
        g.survival = true; g.alive = true; g.health = 20
        let dt: Float = 1.0 / 60
        func townsman(_ dx: Float) -> Mob {
            let m = Mob(.villager, at: s.pos + V3(dx, 0, 6)); m.home = m.pos
            Townsfolk.setup(m, tag: "", game: g); g.mobs.mobs.append(m); return m
        }
        func helm() { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
        func run(_ frames: Int, _ mi: MoveInput = MoveInput(), each: () -> Void = {}) {
            for _ in 0..<frames {
                if ships.pilot === s { g.player.pos = s.toWorld(stand); _ = g.pilotTick(s, mi, dt) }
                ships.update(dt, game: g)
                if !ships.encounters { ships.gunCrewTick(dt, game: g) }
                g.vehicleGunnersTick(dt)
                for m in g.mobs.mobs where m.hired { _ = m.companionAI(dt, g) }
                each()
            }
        }

        // (1) His companion, 10 blocks off, climbs onto the gun when he takes the helm, and rides it as he drives.
        let hand = g.enlist(townsman(-10))
        helm()
        run(2)
        let onGun = VehicleGunners.manned(gun) && VehicleGunners.seated(hand)
        let standAt = VehicleGunners.seats.first?.local ?? .zero
        var drift: Float = 0
        var drive = MoveInput(); drive.forward = 1
        let z0 = s.pos
        run(150, drive) { drift = max(drift, simd_length(gun.toWorld(standAt) - hand.pos)) }
        let moved = simd_length(s.pos - z0)
        check(onGun && moved > 4 && drift < 0.3 && hand.deck === s,
              String(format: "gunners: his companion climbs onto the Gun Truck's gun (%@) and rides it %.1f blocks, at most %.2f off the gunner's place", onGun ? "yes" : "no", moved, drift))

        // (2) The gunner lays the gun for its own shell and fires on a raider 40 blocks off while he drives on.
        let raider = Mob(.zombie, at: s.pos + s.dirToWorld(V3(0, 0, -1)) * 40 + V3(0, 1, 0))
        raider.aggro = true
        g.mobs.mobs.append(raider)
        let v0 = ShipManager.crewVolleys, shells0 = ships.shells.count
        var bore: Float = 9
        run(240) {
            let f = gun.dirToWorld(V3(0, 0, -1)), d = raider.pos - gun.toWorld(gun.pivot)
            bore = min(bore, acosf(max(-1, min(1, simd_dot(simd_normalize(V2(f.x, f.z)), simd_normalize(V2(d.x, d.z)))))))
        }
        let fired = ShipManager.crewVolleys - v0
        let flat = ships.shells.dropFirst(min(shells0, ships.shells.count)).allSatisfy { $0.kind == 6 }
        check(fired > 0 && bore < 0.15 && flat, String(format: "gunners: the gunner swings the gun onto a raider (%.2f rad off) and fires %d volleys of the gun's own flat shell (%@)", bore, fired, flat ? "yes" : "no"))
        g.mobs.mobs.removeAll { $0 === raider }

        // (3) He leaves the helm and walks off: the gunner climbs down and follows him.
        g.leaveHelm()
        g.player.pos = s.pos + V3(40, 0, 0)
        run(2)
        let follows = hand.companionAI(dt, g) > 0
        check(!VehicleGunners.seated(hand) && follows,
              "gunners: on foot 40 blocks off, the gunner climbs down (\(VehicleGunners.seated(hand) ? "still on" : "down")) and comes after him (\(follows))")

        // (4) A volunteer: none for a man of no name; one for a Respected one, from the town by him; one a town a day.
        g.mobs.mobs.removeAll { $0 === hand }
        let a = townsman(4)
        Honour.value = 0
        helm(); run(2)
        let noneLow = VehicleGunners.volunteers
        g.leaveHelm(); run(1)
        Honour.value = 30
        helm(); run(2)
        let one = VehicleGunners.volunteers - noneLow
        let seatedOne = VehicleGunners.manned(gun) && !g.mobs.mobs.contains { $0 === a } && g.companions.count == 1
        // ... climbs down when he walks off, and nobody else from that town volunteers the same day.
        g.leaveHelm(); g.player.pos = s.pos + V3(40, 0, 0); run(2)
        g.mobs.mobs.removeAll { $0.hired }
        _ = townsman(-4)
        helm(); run(2)
        let again = VehicleGunners.volunteers - noneLow - one
        check(noneLow == 0 && one == 1 && seatedOne && again == 0,
              "gunners: no townsman volunteers at honour 0 (\(noneLow)); at Respected one jumps up on the gun (\(one), on it: \(seatedOne)); no second from that town the same day (\(again))")
    }
}
