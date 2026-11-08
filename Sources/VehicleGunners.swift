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
// P512 (Nov 2 12:22: hired people "follow and ride the vehicle he drives"): a companion with no free gun to take climbs
// aboard as a rider, on a free standing spot of the hull nearest its helm, rides there as he drives, and fires their own
// gun from it at what is out for him (Mob.companionAI); they climb down as the gunners do.
enum VehicleGunners {
    struct Seat { weak var mob: Mob?; @WeakLink var turret: Ship? = nil; @WeakLink var vehicle: Ship? = nil; var local: V3; var rider = false
                  var station = false; var face = V3(0, 0, -1) }     // (P512: at the gun's station in the hull, facing its console)
    static var seats: [Seat] = []
    static let board: Float = 32
    static let stayNear: Float = 24
    static let volunteerReach: Float = 28
    static let sight: Float = 70                 // how far a gunner looks for what's out for him
    static var volunteers = 0                    // (harness)
    static var volunteered: [String: Int] = [:]  // town -> the day someone there last volunteered

    static func manned(_ t: Ship) -> Bool { seats.contains { !$0.rider && $0.turret === t && ($0.mob?.health ?? 0) > 0 } }
    static func seated(_ m: Mob) -> Bool { seats.contains { $0.mob === m } }
    static func riding(_ m: Mob) -> Bool { seats.contains { $0.mob === m && $0.rider } }
    static var riders = 0, stations = 0          // (harness: riders boarded, gunners sat at stations)
    static var boardWait: Float = 0

    // A seated gunner where the turret holds them now (true), or not seated (false).
    @discardableResult
    static func atStation(_ m: Mob) -> Bool { seats.contains { $0.mob === m && $0.station } }

    static func place(_ m: Mob) -> Bool {
        guard let st = seats.first(where: { $0.mob === m }), let v = st.vehicle, let t = st.rider || st.station ? v : st.turret else { return false }
        m.pos = t.toWorld(st.local)
        m.vel = v.velocity(at: m.pos)
        m.onGround = true
        m.deck = v
        let f = st.rider ? v.dirToWorld(v.fwd) : (st.station ? v.dirToWorld(st.face) : t.dirToWorld(V3(0, 0, -1)))
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

    // A rider's spot on the vehicle, in its own frame: the free standing cell nearest the helm (solid under it, two clear
    // over it, not the helm's own stand and not another's), else nil.
    static func riderSpot(_ v: Ship, taken: [V3]) -> V3? {
        let gr = v.grid, h = v.helm ?? IVec3(gr.sx / 2, 0, gr.sz / 2)
        let collide = Blocks.collide
        var best: V3?, bd = Float.infinity
        // (within 12 of the helm: a frigate's grid is millions of cells)
        let lo = IVec3(max(0, h.x - 12), max(0, h.y - 12), max(0, h.z - 12))
        let hi = IVec3(min(gr.sx - 1, h.x + 12), min(gr.sy - 2, h.y + 12), min(gr.sz - 1, h.z + 12))
        guard lo.x <= hi.x, lo.y <= hi.y, lo.z <= hi.z else { return nil }
        for y in lo.y...hi.y { for z in lo.z...hi.z { for x in lo.x...hi.x {
            guard collide[Int(gr.get(x, y, z))], !collide[Int(gr.get(x, y + 1, z))], !collide[Int(gr.get(x, y + 2, z))] else { continue }
            if Blocks.isLiquid(gr.get(x, y + 1, z)) { continue }
            let p = V3(Float(x) + 0.5, Float(y + 1) + 0.02, Float(z) + 0.5)
            let hc = V3(Float(h.x) + 0.5, Float(h.y) + 1, Float(h.z) + 0.5)
            let d = simd_length(p - hc)
            // (three blocks or more off the helm where there's room: right beside him, he stood in their line of fire
            // and they held every shot)
            let score = d < 3 ? d + 100 : d
            guard d > 1.2, !taken.contains(where: { simd_length($0 - p) < 1.2 }), score < bd else { continue }
            bd = score; best = p
        } } }
        return best
    }
}

extension Game {
    func vehicleGunnersTick(_ dt: Float) {
        let ships = world.ships
        // (P512: a capital hull he commands too: its crew sit at the guns' stations in the hull)
        let driving = ships.pilot.flatMap { ships.isYours($0) && !$0.wrecked && (!$0.kinematic || $0.captured) ? $0 : nil }
        if driving == nil && VehicleGunners.seats.isEmpty { return }
        // Who stays at the guns.
        var keep: [VehicleGunners.Seat] = []
        for st in VehicleGunners.seats {
            guard let m = st.mob, let v = st.vehicle, st.rider || st.turret != nil else { continue }
            let gunThere = st.rider || ships.list.contains { $0 === st.turret }
            let there = m.health > 0 && m.hired && !v.wrecked && gunThere && ships.list.contains { $0 === v }
            let near = ships.pilot === v || simd_length(player.pos - v.pos) < VehicleGunners.stayNear
            if there && near { keep.append(st); continue }
            m.deck = nil                                             // climbs down: back to following him
            if m.health > 0 { m.pos += V3(0, 0.2, 0) }
        }
        VehicleGunners.seats = keep
        // (each one put back on their spot now the hulls have moved this tick: placed before the ship's step, a crewman at
        // a frigate's station trailed it by a tick's travel, 0.4 blocks at its cruise)
        for st in keep { if let m = st.mob { VehicleGunners.place(m) } }
        guard let v = driving else { return }
        var free = ships.turrets(of: v).filter { !$0.cannons.isEmpty && !VehicleGunners.manned($0) }
        // P512: on a capital hull only the guns with a station in it (a crewman doesn't ride a frigate's turret roof).
        if v.kinematic { free = free.filter { VehicleGunners.station($0, on: v, ships) != nil } }
        let boardReach = VehicleGunners.board
        defer {
            // P512: the rest of his companions near it ride aboard.
            VehicleGunners.boardWait -= dt                                             // (twice a second: a hull's cells scanned)
            let tryNow = VehicleGunners.boardWait <= 0
            if tryNow { VehicleGunners.boardWait = 0.5 }
            for m in companions where tryNow && !VehicleGunners.seated(m) && ships.boundsDistance(v, m.pos) < boardReach {
                let taken = VehicleGunners.seats.filter { $0.rider && $0.vehicle === v }.map { $0.local }
                guard let spot = VehicleGunners.riderSpot(v, taken: taken) else { break }
                VehicleGunners.seats.append(VehicleGunners.Seat(mob: m, turret: nil, vehicle: v, local: spot, rider: true))
                VehicleGunners.riders += 1
                VehicleGunners.place(m)
                sfx(.step(.metal), 0.8, at: m.pos)
            }
        }
        guard !free.isEmpty else { return }
        func seat(_ m: Mob) {
            let t = free.removeFirst()
            if let stn = VehicleGunners.station(t, on: v, ships) {
                // P512: at the gun's station: in the chair, facing the console.
                let c = stn.chair, k = stn.console
                let top = ChairSeat.seatTop(Blocks.key(Blocks.groupBase[Int(v.grid.get(c.x, c.y, c.z))])) ?? 0.6
                VehicleGunners.seats.append(VehicleGunners.Seat(mob: m, turret: t, vehicle: v, local: V3(Float(c.x) + 0.5, Float(c.y) + top, Float(c.z) + 0.5),
                                                                station: true, face: V3(Float(k.x - c.x), 0, Float(k.z - c.z))))
                VehicleGunners.stations += 1
                VehicleGunners.place(m)
                sfx(.step(.metal), 0.8, at: m.pos)
                return
            }
            VehicleGunners.seats.append(VehicleGunners.Seat(mob: m, turret: t, vehicle: v, local: VehicleGunners.stand(t, on: v, world: world)))
            VehicleGunners.place(m)
            sfx(.step(.metal), 0.8, at: m.pos)
        }
        // His companions climb on.
        for m in companions where free.count > 0 && !VehicleGunners.seated(m) && ships.boundsDistance(v, m.pos) < boardReach { seat(m) }
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
