import Foundation
import simd

// Play Together, part 2 (backlog C14: "shares horses, vehicles and robberies").
//   vessels   the host's ships, airships and vehicles within 240 blocks are sent whole (Ships.encode) when the guest
//             first sees them or their blocks change, then their pose 20 times a second. On the guest they are
//             mirrors that glide to the reported pose: the guest walks their decks and rides along (the deck carries
//             it as the host's does), and the host steers. Capital ships (generated, not saved) are not sent.
//   mounts    the guest saddles up on a mirrored horse (or camel, pig, strider) the usual way and rides it on its own
//             headset; the link moves the host's animal to match and its AI rests meanwhile (Mob.netRiddenUntil),
//             so the host sees the friend riding it and can't take the same saddle.
//   crime     the guest's theft, assault and gunfire in a town land on the host's town (TownLaw.offence / gunfire
//             run there with the guest's seat live): the same witnesses, heat, hostility and lawmen for both, so a
//             robbery is shared. Other uses of a mirrored mob (robbing a rider's satchel, a train strongbox, a
//             hostage, a companion) run on the host with the guest's held item, and what that gives lands in the
//             guest's inventory.
extension NetHost {
    func handleShared(_ g: Game, _ type: UInt8, _ r: inout NetIn) {
        switch type {
        case NetMsg.ride:
            let id = r.u32(), pos = r.v3(), yaw = r.f32()
            guard r.ok else { return }
            if id == 0 { ridden?.netRiddenUntil = -1e9; ridden = nil; return }
            guard let m = mob(id: id, g), m.health > 0 else { return }
            if ridden !== m { ridden?.netRiddenUntil = -1e9; ridden = m }
            if g.riding === m { g.dismount() }                       // (the host had climbed on in the same moment)
            m.netRiddenUntil = g.clock + 1
            m.pos = pos; m.yaw = yaw; m.vel = .zero
        case NetMsg.crime:
            let heat = r.f32(), p = r.v3(), speak = r.bool()
            guard r.ok, let s = g.coop.netSeat else { return }
            g.coop.withSeat(s, g) { TownLaw.offence(g, heat: heat, at: p, speak: speak) }
        case NetMsg.gunfire:
            let p = r.v3()
            guard r.ok, let s = g.coop.netSeat else { return }
            g.coop.withSeat(s, g) { TownLaw.gunfire(g, at: p) }
        case NetMsg.useMob:
            let id = r.u32()
            let stack = NetCoop.stack(r.bytes()) ?? .empty
            guard r.ok, let s = g.coop.netSeat else { return }
            var after = stack, note = ""
            if let m = mob(id: id, g), m.health > 0 {
                g.coop.withSeat(s, g) {
                    let menu0 = g.menu
                    g.inventory.held = stack
                    _ = g.useItemOnMob(m)
                    after = g.inventory.held
                    g.inventory.held = .empty
                    // A screen opened for the seat (trading, a mount's pack) has no one to look at it on the host.
                    if g.menu !== menu0, g.menu != nil {
                        g.closeMenu()
                        note = "Trade and pack screens open on the host's headset only for now"
                    }
                }
            }
            var o = NetOut()
            o.bytes(NetCoop.stackData(after)); o.str(note)
            link?.send(NetMsg.useResult, o.b)
        default: break
        }
    }

    // Vessels near the guest: whole when new or changed (at most once a second each), then poses.
    func sendShips(_ g: Game, _ l: NetLink) {
        let c = pose.pos
        var near: [Ship] = []
        for s in g.world.ships.list where !s.root.kinematic {
            let d = s.pos - c
            if d.x * d.x + d.z * d.z < 240 * 240 { near.append(s) }
        }
        let ids = Set(near.map { $0.id })
        for id in shipSent.keys where !ids.contains(id) {
            var o = NetOut(); o.i32(id)
            l.send(NetMsg.shipGone, o.b)
            shipSent[id] = nil
        }
        for s in near {
            let sig = s.blockCount &* 31 &+ s.wheelGen
            if let had = shipSent[s.id], had.sig == sig || g.clock - had.at < 1 { continue }
            guard l.queuedBytes < 8 << 20, let d = g.world.ships.encode([s]) else { continue }
            var o = NetOut(); o.i32(s.id); o.bytes([UInt8](d))
            l.send(NetMsg.shipFull, o.b)
            shipSent[s.id] = (sig, g.clock)
        }
        let sent = near.filter { shipSent[$0.id] != nil }
        guard !sent.isEmpty else { return }
        var o = NetOut()
        o.u16(UInt16(min(sent.count, 500)))
        for s in sent.prefix(500) {
            let q = s.rot.vector
            o.i32(s.id); o.v3(s.pos); o.f32(q.x); o.f32(q.y); o.f32(q.z); o.f32(q.w)
            o.v3(s.vel); o.v3(s.angVel); o.f32(s.turretYaw)
        }
        l.send(NetMsg.shipPoses, o.b)
    }
}

extension NetGuest {
    func applyShared(_ g: Game, _ type: UInt8, _ r: inout NetIn) {
        let ships = g.world.ships
        switch type {
        case NetMsg.shipFull:
            let id = Int(r.i32()), d = r.bytes()
            guard r.ok else { return }
            let keep = ships.aboard?.id == id ? g.player.pos : nil
            let local = keep.flatMap { _ in ships.aboard.map { $0.toLocal(g.player.pos) } }
            for s in ships.list where s.id == id { ships.remove(s, turrets: false) }
            ships.decode(Data(d))
            if let s = ships.list.first(where: { $0.id == id }) {
                if let t = shipTargets[id] { s.pos = t.pos; s.rot = t.rot }
                s.prevPos = s.pos; s.prevRot = s.rot
                s.updateBounds()
                if let l = local { g.player.pos = s.toWorld(l); ships.aboard = s }
            }
        case NetMsg.shipPoses:
            let n = Int(r.u16())
            for _ in 0..<n {
                let id = Int(r.i32()), pos = r.v3()
                let q = V4(r.f32(), r.f32(), r.f32(), r.f32())
                let vel = r.v3(), av = r.v3(), ty = r.f32()
                guard r.ok else { break }
                let rot = simd_length(q) > 0.5 ? simd_normalize(Quat(vector: q)) : Quat(angle: 0, axis: V3(0, 1, 0))
                shipTargets[id] = ShipTarget(pos: pos, rot: rot, vel: vel, angVel: av, turretYaw: ty, age: 0)
            }
        case NetMsg.shipGone:
            let id = Int(r.i32())
            for s in ships.list where s.id == id { ships.remove(s, turrets: false) }
            shipTargets[id] = nil
        case NetMsg.useResult:
            let after = NetCoop.stack(r.bytes()) ?? .empty
            let note = r.str()
            g.inventory.held = after
            if !note.isEmpty { g.onToast?(note) }
        default: break
        }
    }

    // Once a frame after the mobs: the vessels glide to their poses carrying whoever stands on them, the mount's
    // place goes to the host, and the helm stays the host's.
    func sharedTick(_ g: Game, _ dt: Float) {
        let ships = g.world.ships
        if ships.pilot != nil {
            ships.pilot = nil
            if !pilotWarned { pilotWarned = true; g.onToast?("The host steers this vessel: ride along on deck") }
        }
        if !ships.list.isEmpty {
            let aboard = ships.aboard
            let local = aboard.map { $0.toLocal(g.player.pos) }
            let yaw0 = aboard?.yaw ?? 0
            let k = min(1, dt * 10)
            for s in ships.list {
                guard var t = shipTargets[s.id] else { continue }
                t.age += dt
                shipTargets[s.id] = t
                let ahead = t.pos + t.vel * min(t.age, 0.25)          // between poses, keep going as it was
                s.prevPos = s.pos; s.prevRot = s.rot
                s.pos += (ahead - s.pos) * k
                if simd_length(ahead - s.pos) > 8 { s.pos = ahead }      // (far behind: jump)
                s.rot = simd_slerp(s.rot, t.rot, k)
                s.vel = t.vel; s.angVel = t.angVel; s.turretYaw = t.turretYaw
                s.updateBounds()
            }
            if let s = aboard, let l = local {
                g.player.pos = s.toWorld(l)
                g.player.yaw += s.yaw - yaw0
            }
            ships.riderStamp += 1
        }
        // The mount: where this headset has it.
        if let m = g.riding, let id = mirrorID(m) {
            var o = NetOut(); o.u32(id); o.v3(m.pos); o.f32(m.yaw)
            link.send(NetMsg.ride, o.b)
            ridingID = id
        } else if ridingID != 0 {
            var o = NetOut(); o.u32(0); o.v3(.zero); o.f32(0)
            link.send(NetMsg.ride, o.b)
            ridingID = 0
        }
    }

    func crime(heat: Float, at p: V3, speak: Bool) {
        var o = NetOut(); o.f32(heat); o.v3(p); o.bool(speak)
        link.send(NetMsg.crime, o.b)
    }
    func gunfire(at p: V3) {
        var o = NetOut(); o.v3(p)
        link.send(NetMsg.gunfire, o.b)
    }

    // Game.useItemOnMob on a mirror: mounts stay on this headset; anything else is done on the host.
    func use(_ g: Game, _ m: Mob) -> Bool {
        guard let id = mirrorID(m) else { return false }
        if MountMenu.saddleKinds.contains(m.kind) || m.horseLike || [MobKind.pig, .strider, .boat, .minecart, .camel].contains(m.kind) {
            return false
        }
        var o = NetOut(); o.u32(id); o.bytes(NetCoop.stackData(g.held))
        link.send(NetMsg.useMob, o.b)
        return true
    }
}
