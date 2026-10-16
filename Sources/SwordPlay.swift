import Foundation
import simd

// P308 (Oct 15 12:15, with P272: "sword fighting is underdeveloped"). The melee loop on top of the VR wind-ups and
// parries (VRCombatFeel.swift), the guards (Guards.swift) and the Brand Order duel (HellMobs.swift):
//   the cut      a blade's damage follows how it struck: a clean cut across the blade's length deals it all, a blade
//                dragged along its length 55 %, a thrust tip-first 115 %; and a square blow into the body all, a graze
//                along it 70 % (times the speed and wind-up rules, VRMelee).
//   the block    a blade held across the line of a landing strike takes it: no damage, a clang and sparks where they
//                meet, a jolt in both hands, and the attacker is thrown back off balance a moment.
//   the stagger  a hard blow (a fast, full swing; a fully charged sword hit off the headset) into a mob winding up
//                breaks its strike off and rocks it back; a weak blow it shrugs off invites a quick counter.
//   enemies      melee foes strike high or low (block where the blow comes from), feint now and then (a wind-up broken
//                off and another straight after), and answer a guard that turned the player's blow or a weak blow with
//                a riposte: a short, fast wind-up. After a blocked or parried strike they step back to their spacing.
//   the feel     the blow sounds of what it struck (flesh thuds, armour rings, bone knocks), on top of the haptics and
//                the slash marks.
enum SwordPlay {
    static let blockReach: Float = 0.2          // the blade this close to the strike's line takes it
    static let riposteWind: Float = 0.22        // a counter's short wind-up
    static let riposteFor: Float = 1.2          // a counter stays ready this long
    static let interruptPow: Float = 1.15       // a blow this hard into a wind-up breaks it off
    static let weakPow: Float = 0.75            // ... this soft invites a counter
    static let feintShare: Float = 0.15
    static let lowShare: Float = 0.3
    static var blocks = 0, interrupts = 0, ripostes = 0, feints = 0     // (counters)
    static var blockFelt = 0                    // QuestControls feels each block in both hands

    // How the blade struck: blade direction (base to tip), the tip's motion and the direction into the body (unit).
    static func cut(blade: V3, motion: V3, into: V3) -> Float {
        let along = simd_dot(blade, motion)
        let edge: Float = along > 0.75 ? 1.15 : 1 - 0.45 * min(1, abs(along) / 0.75 * abs(along) / 0.75)
        let square = max(0, simd_dot(motion, into))
        return edge * (0.7 + 0.3 * square)
    }

    // The closest distance between segments p0-p1 and q0-q1.
    static func segDist(_ p0: V3, _ p1: V3, _ q0: V3, _ q1: V3) -> Float {
        let d1 = p1 - p0, d2 = q1 - q0, r = p0 - q0
        let a = simd_dot(d1, d1), e = simd_dot(d2, d2), f = simd_dot(d2, r)
        var s: Float = 0, t: Float = 0
        if a < 1e-8 && e < 1e-8 { return simd_length(r) }
        if a < 1e-8 { t = max(0, min(1, f / e)) } else {
            let c = simd_dot(d1, r)
            if e < 1e-8 { s = max(0, min(1, -c / a)) } else {
                let b = simd_dot(d1, d2), den = a * e - b * b
                s = den > 1e-8 ? max(0, min(1, (b * f - c * e) / den)) : 0
                t = (b * s + f) / e
                if t < 0 { t = 0; s = max(0, min(1, -c / a)) } else if t > 1 { t = 1; s = max(0, min(1, (b - c) / a)) }
            }
        }
        return simd_length((p0 + d1 * s) - (q0 + d2 * t))
    }
}

extension Game {
    // Where m's strike comes from and goes to: from its arms to his head (high) or his hips (low).
    func strikeLine(_ m: Mob) -> (V3, V3) {
        let head = (vrHead ?? player.eye) - V3(0, 0.2, 0)
        let to = m.strikeLow ? player.pos + V3(0, 0.75, 0) : head
        var flat = V3(to.x - m.pos.x, 0, to.z - m.pos.z)
        flat = simd_length(flat) > 1e-3 ? simd_normalize(flat) : V3(0, 0, 1)
        let from = m.pos + V3(0, m.height * (m.strikeLow ? 0.5 : 0.8), 0) + flat * m.halfW
        return (from, to)
    }

    // VR: the held blade across a landing strike's path takes it. True when it blocked.
    func bladeBlocks(_ m: Mob) -> Bool {
        guard let bl = vrBlade else { return false }
        let (s0, s1) = strikeLine(m)
        let sd = s1 - s0, sl = simd_length(sd)
        guard sl > 0.05 else { return false }
        let bd = bl.b - bl.a, blen = simd_length(bd)
        guard blen > 0.05, abs(simd_dot(bd / blen, sd / sl)) < 0.85 else { return false }        // across it, not along it
        guard SwordPlay.segDist(bl.a, bl.b, s0, s1) < SwordPlay.blockReach else { return false }
        // Held out toward the attacker (a sword hanging at the side doesn't block a low cut for free).
        let body = vrHead ?? player.eye
        let toMob = simd_normalize(V3(m.pos.x - body.x, 0, m.pos.z - body.z) + V3(1e-4, 0, 0))
        let mid = (bl.a + bl.b) * 0.5
        guard simd_dot(V3(mid.x - body.x, 0, mid.z - body.z), toMob) > 0.2 else { return false }
        SwordPlay.blocks += 1
        SwordPlay.blockFelt += 1
        let meet = (bl.a + bl.b) * 0.5
        sfx(.parryClang, 0.85, at: meet)
        particles.bladeSpark(at: meet, along: sd / sl, power: 1)
        let away = simd_normalize(V3(m.pos.x - player.pos.x, 0, m.pos.z - player.pos.z) + V3(1e-4, 0, 0))
        m.vel += away * 3 + V3(0, 1, 0)                 // thrown back to its spacing
        m.attackCooldown = max(m.attackCooldown, 0.9)
        m.hitStop = 0.08
        m.riposte = 0
        return true
    }

    // A wind-up's length, and its kind (high, low, a feint), as it starts.
    func startWindUp(_ m: Mob) {
        if m.riposte > 0 {
            m.windUp = SwordPlay.riposteWind
            m.riposte = 0
            m.feint = false
            SwordPlay.ripostes += 1
        } else {
            m.windUp = VRMelee.windUpTime
            m.feint = Rand.float(in: 0..<1) < SwordPlay.feintShare && m.health > 0 && m.kind.hostile
        }
        m.strikeLow = Rand.float(in: 0..<1) < SwordPlay.lowShare
    }

    // A landed melee blow from the player on m (Game.interact): a hard one breaks a wind-up off, a weak one invites a
    // counter.
    func swordBlowLanded(_ m: Mob, power: Float) {
        guard m.health > 0 else { return }
        if m.windUp > 0 && power >= SwordPlay.interruptPow {
            m.windUp = 0; m.windUpDone = false; m.feint = false
            m.attackCooldown = max(m.attackCooldown, 0.7)
            m.hitStop = max(m.hitStop, 0.12)
            SwordPlay.interrupts += 1
        } else if power < SwordPlay.weakPow && m.kind.hostile {
            m.riposte = SwordPlay.riposteFor
            m.attackCooldown = min(m.attackCooldown, 0.15)
        }
        // The blow's own sound (HitFeel): flesh thuds, armour rings, bone and stone knock.
        let at = m.pos + V3(0, m.height * 0.6, 0)
        switch HitFeel.of(m) {
        case .flesh: sfx(power > 1.3 ? .attackCrit : .attack, 0.5 + 0.3 * min(1, power), at: at)
        case .armour: sfx(.bulletImpact(.metal), 0.55, at: at)
        case .hard: sfx(.hit(.bone), 0.8, at: at)
        }
    }
}
