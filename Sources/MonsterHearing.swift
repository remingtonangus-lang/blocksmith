import Foundation
import simd

// D15: monsters hear gunshots and investigate; night hordes that stalk and surround.
// Objectives:
//  - A gunshot (40 blocks), an explosion (56) or a cannon (72) is heard by every monster in range that isn't already
//    after the player: it walks to where the noise was (a few blocks of spread each, so a crowd fans out), looks
//    round there for a moment and goes back to its business; quieter guns (suppressed later, D9) can pass less power.
//  - Night hordes: about one survival night in three, out in the open, a horde of 5-9 of the night's monsters gathers
//    40-50 blocks off on one side, stalks in to a ring 12-16 blocks round the player, keeping its distance and circling
//    while the ring closes up, then rushes in together once most of it is in place (or after 40 s). It never forms
//    underground, in a town, on peaceful, or by day; monsters lost from it simply fight as usual.
extension Mob {
    // Investigating a heard noise: speed to walk at, or nil when there is nothing to look into.
    func investigateStep(_ dt: Float, _ g: Game) -> Float? {
        guard let p = heardAt else { return nil }
        heardTime -= dt
        if heardTime <= 0 { heardAt = nil; return nil }
        let d = V2(p.x - pos.x, p.z - pos.z)
        if simd_length(d) > 2.5 && !gaveUp(p) {
            face(p)
            return spec.speed * 0.85
        }
        // There: a look round, then back to wandering.
        if heardTime > 4 { heardTime = 4 }
        yaw += dt * 1.4
        return 0
    }
}

extension Game {
    // A noise monsters can hear (from baseNoise: gunshots, blasts, cannon).
    func monstersHear(at p: V3, kind: NoiseKind, power: Float) {
        guard world.dim != .end else { return }
        let r0: Float = kind == .gunshot ? 40 : (kind == .explosion ? 56 : 72)
        let r = r0 * simd_clamp(power, 0.25, 2)
        for m in mobs.mobs where m.health > 0 && m.kind.hostile && !m.tamed && !m.kind.steelhold && !m.kind.ash && m.posse == 0 {
            switch m.spec.behavior {
            case .melee, .spider, .ranged, .creeper: break
            default: continue
            }
            let d = simd_length(m.pos - p)
            guard d < r, d > 3 else { continue }
            // Already on the player: carries on.
            if simd_length(m.pos - player.pos) < 16 && world.canSee(m.eye, player.eye) { continue }
            let a = Rand.float(in: 0..<(2 * .pi)), s = Rand.float(in: 1...5)
            m.heardAt = p + V3(cosf(a) * s, 0, sinf(a) * s)
            m.heardTime = 25 + Rand.float(in: 0...10)
            MonsterHearing.heard += 1
        }
    }
}

enum MonsterHearing { static var heard = 0 }

// MARK: Night hordes

enum Horde {
    static var members: [Mob] = []
    static var night = -1                  // the night last rolled (game day)
    static var phase = 0                   // 0 none, 1 stalking, 2 rushing
    static var t: Float = 0
    static var side: Float = 0             // the bearing it came in from
    static var formed = 0                  // hordes formed (checks)

    static func tick(_ g: Game, _ dt: Float) {
        members.removeAll { m in m.health <= 0 || !g.mobs.mobs.contains { $0 === m } }
        if phase > 0 && members.isEmpty { phase = 0 }
        if phase > 0 {
            t += dt
            if g.daylight > 0.5 { release() }
            if phase == 1 {
                let p = g.player.pos
                let placed = members.filter { simd_length(V2($0.pos.x - p.x, $0.pos.z - p.z)) < 19 }.count
                if t > 40 || (members.count > 0 && placed * 4 >= members.count * 3) {
                    phase = 2
                    g.onToast?("They're closing in")
                }
            }
            return
        }
        guard g.survival, g.difficulty > 0, g.alive, g.world.dim == .overworld, g.daylight < 0.15 else { return }
        let day = Int(g.time / DAY_LENGTH)
        guard day != night else { return }
        // Rolled once a night, an hour of game time after dark has set in.
        night = day
        guard Rand.float(in: 0..<1) < 0.33 else { return }
        let pp = g.player.pos
        let ix = Int(floor(pp.x)), iy = Int(floor(pp.y + 1)), iz = Int(floor(pp.z))
        guard g.world.lightAt(ix, iy, iz).sky >= 12, !TownLaw.isTownSpot(g, IVec3(ix, iy, iz)) else { return }
        side = Rand.float(in: 0..<(2 * .pi))
        let n = Rand.int(in: 5...9)
        let kinds: [MobKind] = [.zombie, .zombie, .zombie, .skeleton, .spider]
        for k in 0..<n {
            let a = side + Rand.float(in: -0.5...0.5)
            let d = Rand.float(in: 40...50)
            let x = pp.x + cosf(a) * d, z = pp.z + sinf(a) * d
            let y = g.standY(x, z, from: pp.y + 12)
            guard abs(y - pp.y) < 20 else { continue }
            let kind = kinds[Rand.int(in: 0..<kinds.count)]
            let m = Mob(kind, at: V3(x, y, z))
            m.hordeSlot = k
            g.mobs.mobs.append(m)
            members.append(m)
        }
        guard !members.isEmpty else { return }
        phase = 1; t = 0; formed += 1
        g.onToast?("Something is moving out there in the dark")
    }

    static func release() {
        for m in members { m.hordeSlot = -1 }
        members.removeAll(); phase = 0
    }

    // A horde member's walk: nil when it should fight as usual.
    static func step(_ m: Mob, _ dt: Float, _ g: Game) -> Float? {
        guard phase == 1, members.contains(where: { $0 === m }) else { if phase == 0 { m.hordeSlot = -1 }; return nil }
        let p = g.player.pos
        let n = Float(max(members.count, 1))
        // Its place on the ring, turning slowly: stalking, never straight in.
        let a = side + .pi + Float(m.hordeSlot) / n * 2 * .pi + t * 0.08
        let r: Float = 14 + 2 * sinf(Float(m.hordeSlot) * 1.7)
        let goal = V3(p.x + cosf(a) * r, m.pos.y, p.z + sinf(a) * r)
        let d = simd_length(V2(goal.x - m.pos.x, goal.z - m.pos.z))
        if d < 1.5 { m.face(p); return 0 }
        m.face(goal)
        return m.spec.speed * (d > 10 ? 0.9 : 0.55)
    }
}
