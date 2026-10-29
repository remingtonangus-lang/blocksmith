import Foundation
import simd

// D50: ride the train's roofs, climb between cars, and defend a train against a hold-up.
//   roofs    stand on any car's roof and it carries you (the cars' roofs are solid underfoot while the train runs).
//            Sneak and use a car to climb its end ladder onto the roof (from the ground or from your seat). Walk or
//            jump the couplings between cars; fall off at speed and the drop is yours.
//   hold-up  ride a line long enough and a gang may try it: robbers block the track ahead and the train brakes to a
//            stop with four of them on the line. Drop them all and the railway pays you $15 and your name goes up
//            (honour +3); leave them a minute and a quarter and they blow the strongbox and ride off with the
//            day's takings. Not on the Ash Vault's armoured lines, nor once a train has been robbed that day.
extension Trains {
    static let roofHeight: [Int: Float] = [loco: 2.1, coach: 2.05, express: 2.05, armouredLoco: 2.0, gunCar: 1.9]
    static let carHalfLength: Float = 1.75, carHalfWidth: Float = 0.95
    static let raidChancePerSecond: Float = 1.0 / 240
    static let raidTime: Float = 75
    static let raidReward = 1500
    static let robberName = "Train Robber"
    static var raidsBeaten = 0, raidsLost = 0, roofSnaps = 0       // (harness)
    static var roofShift = V2(0, 0)                                 // Q2: the cars' carry this frame (footsteps leave it out)
    static var roofAt: Double = -1e9                                // Q2: last frame the player stood on a roof

    // The car whose roof the player stands on (at the cars' poses `poses`, (pos, yaw)), that surface's height above the
    // car and whether it is the floor inside (P470 part 2: a real-size coach or troop car is walked through).
    static func roofUnder(_ g: Game, _ tr: Train, _ poses: [(V3, Float)]) -> (Int, Float, Bool)? {
        guard g.riding == nil, tr.cars.count == poses.count else { return nil }
        let p = g.player.pos
        for (k, (c, yaw)) in poses.enumerated() {
            let car = tr.cars[k]
            let fwd = V3(-sinf(yaw), 0, -cosf(yaw)), right = V3(cosf(yaw), 0, -sinf(yaw))
            let rel = p - c
            guard abs(simd_dot(rel, fwd)) < halfLength(car), abs(simd_dot(rel, right)) < halfWidth(car) else { continue }
            let h = roofTop(car)
            if p.y > c.y + h - 0.7 && p.y < c.y + h + 0.35 && g.player.vel.y <= 0.5 { return (k, h, false) }
            // Inside: stepping in off a platform (the floor is a step up), walking, jumping in the aisle.
            if let f = floorTop(car), p.y > c.y + f - (tr.blocksPerSec < 0.3 ? 1.3 : 0.7), p.y < c.y + f + 1.6 { return (k, f, true) }
        }
        return nil
    }

    // Trains.place, after the cars have moved: carry a roof rider along and hold them up on the roof.
    static func carryRoofRider(_ g: Game, _ tr: Train, before: [(V3, Float)]) {
        guard g.alive, let (k, h, inside) = roofUnder(g, tr, before) else { return }
        let car = tr.cars[k]
        let (c0, y0) = before[k]
        // The car's move, turn included (round a curve the rider swings with it).
        var dy = car.yaw - y0
        if dy > .pi { dy -= 2 * .pi } else if dy < -.pi { dy += 2 * .pi }
        let rel = g.player.pos - c0
        let cs = cosf(dy), sn = sinf(dy)
        let turned = V3(rel.x * cs + rel.z * sn, rel.y, -rel.x * sn + rel.z * cs)
        var np = car.pos + turned
        let floor = car.pos.y + h
        if inside {
            // In the aisle: carried along, kept between the walls while the train runs (the doors open at a stand).
            let right = V3(cosf(car.yaw), 0, -sinf(car.yaw)), w = halfWidth(car) - 0.45
            let across = simd_dot(np - car.pos, right)
            if tr.blocksPerSec > 0.3 && abs(across) > w { np -= right * (across - (across > 0 ? w : -w)) }
            np.y = max(floor, g.player.pos.y + car.pos.y - c0.y)
        } else { np.y = floor }
        roofShift += V2(np.x - g.player.pos.x, np.z - g.player.pos.z)
        roofAt = g.clock
        g.player.pos = np
        if np.y <= floor + 0.001 {
            if g.player.vel.y < 0 { g.player.vel.y = 0 }
            g.player.onGround = true
            g.player.airPeak = np.y
        }
        g.player.yaw += dy
        tr.roofAt = g.clock
        roofSnaps += 1
    }

    // Trains.use: sneak and use a car to climb onto its roof.
    static func climbRoof(_ g: Game, _ tr: Train, _ m: Mob) -> Bool {
        guard g.player.sneaking, !tr.wrecked else { return false }
        if g.riding != nil { g.dismount() }
        let top = m.pos.y + roofTop(m)
        g.player.pos = V3(m.pos.x, top, m.pos.z) - m.forward * 0.4
        g.player.vel = .zero
        g.player.onGround = true
        g.player.airPeak = top
        tr.roofAt = g.clock
        g.sfx(.step(.wood), 0.7, at: m.pos)
        g.onToast?("On the roof of the \(m.customName ?? "car"). Mind the drop")
        return true
    }

    // Whether the player is aboard: in a seat or on a roof in the last two seconds.
    static func aboard(_ g: Game, _ tr: Train) -> Bool {
        if let r = g.riding, tr.cars.contains(where: { $0 === r }) { return true }
        return g.clock - tr.roofAt < 2
    }

    // Trains.tick (once a second): start, run and settle a hold-up of the train you're aboard.
    static func raidTick(_ g: Game, _ tr: Train) {
        let day = Int(g.time / DAY_LENGTH)
        if !tr.raid.isEmpty {
            tr.raidT += 1
            let alive = tr.raid.filter { r in r.health > 0 && g.mobs.mobs.contains(where: { $0 === r }) }
            let far = lead(tr).map { simd_length($0.pos - g.player.pos) > 72 } ?? true
            if alive.isEmpty {
                tr.raid = []
                tr.heldBy = false; tr.stoppedFor = 0
                raidsBeaten += 1
                if g.survival {
                    g.money += raidReward
                    Honour.change(g, 3, "saw off the robbers on the \(tr.track.name)")
                }
                g.sfx(.levelUp, 0.7)
                whistle(g, tr)
                g.onToast?("The robbers are down. The railway pays you \(Money.format(raidReward)) for the \(tr.track.name)")
            } else if far || tr.raidT > raidTime || !g.alive {
                let gone = Set(alive.map { ObjectIdentifier($0) })
                g.mobs.mobs.removeAll { gone.contains(ObjectIdentifier($0)) }
                tr.raid = []
                tr.heldBy = false; tr.stoppedFor = 0
                if !far {
                    tr.robbedDay = day
                    raidsLost += 1
                    if let ex = tr.cars.first(where: { $0.variant == express }) ?? tr.cars.last { Explosion.explode(at: ex.pos + V3(0, 1, 0), power: 0.8, game: g, except: ex) }
                    g.onToast?("The robbers blow the strongbox and ride off with the takings")
                } else if g.alive {
                    tr.robbedDay = day                              // Q2: left behind, the train is still robbed
                    raidsLost += 1
                    g.onToast?("Behind you, the robbers clean out the \(tr.track.name) and ride off")
                }
            } else {
                tr.heldBy = true; tr.stoppedFor = 0
            }
            return
        }
        guard g.survival, g.difficulty > 0, !tr.track.armoured, tr.kind != .troop, !tr.wrecked, tr.robbedDay != day, tr.raidedDay != day,
              tr.cars.count >= 3, !tr.heldBy, aboard(g, tr), tr.track.at(tr.time).stop == nil else { return }
        guard Rand.float(in: 0..<1) < raidChancePerSecond else { return }
        tr.raidedDay = day
        tr.raidT = 0
        guard let lead = lead(tr) else { return }
        let ahead = lead.pos + lead.forward * (halfLength(lead) + 10)
        let side = V3(lead.forward.z, 0, -lead.forward.x)
        let s6: V3 = side * 6, f4: V3 = lead.forward * 4, f8: V3 = lead.forward * 8
        let spots: [V3] = [ahead + side * 2, ahead - side * 2, lead.pos + s6 - f4, lead.pos - s6 - f8]
        for (i, s) in spots.enumerated() {
            let m = Mob(i % 2 == 0 ? .pillager : .vindicator, at: g.world.freeSpawn(s))
            m.customName = robberName
            m.persistent = false
            m.aggro = true
            m.lockTime = 20
            m.posse = Contracts.banditPosse                     // Q2: they fight as a gang (GangTactics: cover, flanks)
            g.mobs.mobs.append(m)
            tr.raid.append(m)
        }
        tr.heldBy = true; tr.stoppedFor = 0
        whistle(g, tr)
        g.onToast?("Robbers on the line ahead! The train brakes")
    }
}
