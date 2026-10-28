import Foundation
import simd

// P478 (Remington, Oct 27 19:2x, his idea: "if you have high honour, if you make a gun truck, one of the villagers will
// jump on the gunner position and shoot for you"). His people at his guns while he drives:
//   boarding    when he takes the helm of a vehicle of his with a turret, each companion within 32 blocks climbs onto a
//               turret no one holds and stands behind its gun (riding it as it turns and the vehicle moves);
//   volunteers  with honour Respected or better (survival), a townsperson near him at the helm (one a town a day, while he
//               leads fewer than Companions.max) jumps up on a free gun of their own accord: a companion from then on,
//               for nothing;
//   the guns    a gunner's turret is theirs: laid for its own shell onto the nearest enemy vessel, hostile soldier, or
//               anything out for him (GunCrew.crewFoe), and fired when it bears; his sight keeps the turrets no one holds;
//   leaving     on foot more than 24 blocks from the vehicle, or with it wrecked, they climb down and follow him again.
enum VehicleGunners {
    struct Seat { weak var mob: Mob?; weak var turret: Ship?; weak var vehicle: Ship?; var local: V3 }
    static var seats: [Seat] = []
    static let board: Float = 32
    static let stayNear: Float = 24
    static let volunteerReach: Float = 28
    static let sight: Float = 70                 // how far a gunner looks for what's out for him
    static var volunteers = 0                    // (harness)
    static var volunteered: [String: Int] = [:]  // town -> the day someone there last volunteered

    static func manned(_ t: Ship) -> Bool { seats.contains { $0.turret === t && ($0.mob?.health ?? 0) > 0 } }
    static func seated(_ m: Mob) -> Bool { seats.contains { $0.mob === m } }

    // A seated gunner where the turret holds them now (true), or not seated (false).
    @discardableResult
    static func place(_ m: Mob) -> Bool {
        guard let st = seats.first(where: { $0.mob === m }), let t = st.turret, let v = st.vehicle else { return false }
        m.pos = t.toWorld(st.local)
        m.vel = v.velocity(at: m.pos)
        m.onGround = true
        m.deck = v
        let f = t.dirToWorld(V3(0, 0, -1))
        m.yaw = atan2f(-f.x, -f.z)
        m.headYaw = m.yaw
        return true
    }

    // Where a gunner stands on a turret, in its own frame: a block and a half behind the ring's middle, feet on the first
    // floor under that point (the turret's or the vehicle's).
    static func stand(_ t: Ship, on v: Ship, world w: World) -> V3 {
        let back = t.dirToWorld(V3(0, 0, 1))
        let flat = simd_normalize(V3(back.x, 0, back.z) + V3(1e-5, 0, 0))
        let top = t.toWorld(t.pivot) + flat * 1.5 + V3(0, 1.5, 0)
        var feet = t.toWorld(t.pivot).y
        var best: Float = 6
        for s in [t, v] {
            if let r = s.raycast(top, V3(0, -1, 0), maxDist: 6, world: w), r.t < best { best = r.t; feet = top.y - r.t }
        }
        return t.toLocal(V3(top.x, feet + 0.02, top.z))
    }
}

extension Game {
    func vehicleGunnersTick(_ dt: Float) {
        let ships = world.ships
        let driving = ships.pilot.flatMap { ships.isYours($0) && !$0.kinematic && !$0.wrecked ? $0 : nil }
        if driving == nil && VehicleGunners.seats.isEmpty { return }
        // Who stays at the guns.
        var keep: [VehicleGunners.Seat] = []
        for st in VehicleGunners.seats {
            guard let m = st.mob, let t = st.turret, let v = st.vehicle else { continue }
            let there = m.health > 0 && m.hired && !v.wrecked && ships.list.contains { $0 === t } && ships.list.contains { $0 === v }
            let near = ships.pilot === v || simd_length(player.pos - v.pos) < VehicleGunners.stayNear
            if there && near { keep.append(st); continue }
            m.deck = nil                                             // climbs down: back to following him
            if m.health > 0 { m.pos += V3(0, 0.2, 0) }
        }
        VehicleGunners.seats = keep
        guard let v = driving else { return }
        var free = ships.turrets(of: v).filter { !$0.cannons.isEmpty && !VehicleGunners.manned($0) }
        guard !free.isEmpty else { return }
        func seat(_ m: Mob) {
            let t = free.removeFirst()
            VehicleGunners.seats.append(VehicleGunners.Seat(mob: m, turret: t, vehicle: v, local: VehicleGunners.stand(t, on: v, world: world)))
            VehicleGunners.place(m)
            sfx(.step(.metal), 0.8, at: m.pos)
        }
        // His companions climb on.
        for m in companions where free.count > 0 && !VehicleGunners.seated(m) && simd_length(m.pos - v.pos) < VehicleGunners.board { seat(m) }
        // A volunteer from the town, for a man of good name.
        guard free.count > 0, survival, alive, Honour.value >= Honour.respected, companions.count < Companions.max else { return }
        let today = Int(time / DAY_LENGTH)
        var pick: Mob?, pd = VehicleGunners.volunteerReach
        for m in mobs.mobs where m.kind == .villager && m.health > 0 && !m.baby && !m.aggro {
            guard let vi = m.villager, vi.person != nil, vi.shop == nil, Companions.hireable.contains(vi.role ?? "") else { continue }
            let d = simd_length(m.pos - player.pos)
            guard d < pd, VehicleGunners.volunteered[TownLaw.town(of: m, self)] != today else { continue }
            pd = d; pick = m
        }
        guard let m = pick else { return }
        VehicleGunners.volunteered[TownLaw.town(of: m, self)] = today
        let c = enlist(m)
        VehicleGunners.volunteers += 1
        seat(c)
        sfx(.levelUp, 0.6, at: c.pos)
        onToast?("\(c.customName ?? "A townsman") jumps up on your gun.")
    }
}
