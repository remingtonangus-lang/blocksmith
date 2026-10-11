import Foundation
import simd

// Animation layers drawn over every mob model (L1 look upgrade part 4, docs/status/look-upgrade.md). The models
// (Mob.swift parts, TownsfolkModel, ...) pose their limbs; on top of that, applied to the posed boxes:
// - the head turns toward what the mob watches (its prey, or the player close by for animals and townsfolk), within a
//   neck's reach, and a baby's head is drawn bigger;
// - each attack throws the body into a short lunge, a hit rocks it back;
// - at rest it breathes;
// - when it dies it tips over onto its side, reddens and goes in a puff, instead of vanishing on the spot.
// Platform-neutral: the Mac and the Quest draw through writeMobVertices.

// Which boxes are the head (box centre above `minY`, or in front of `maxZ`) and where its neck is (model pixels).
struct HeadJoint {
    var minY: Float = -.greatestFiniteMagnitude
    var maxZ: Float = .greatestFiniteMagnitude
    var pivot: V3
    func holds(_ p: Part) -> Bool {
        let c = (p.mn + p.mx) * 0.5
        return c.y > minY && c.z < maxZ
    }
}

// A whole-model transform: q -> a * q + b (model pixels), and the head's own (applied first, head boxes only).
struct MobPose {
    var a = matrix_identity_float3x3, b = V3.zero
    var joint: HeadJoint?
    var ha = matrix_identity_float3x3, hb = V3.zero
    var still: Bool { joint == nil && a == matrix_identity_float3x3 && b == .zero }
}

enum MobAnim {
    static let deathTime: Float = 1.0          // the fall, then the puff
    static let fallTime: Float = 0.45
    static let maxCorpses = 24

    static func headJoint(_ m: Mob) -> HeadJoint? {
        switch m.kind {
        case .zombie, .skeleton, .husk, .stray, .drowned, .pillager, .vindicator, .witch, .illusioner, .parched:
            return HeadJoint(minY: 24, pivot: V3(0, 24, 0))
        case .enderman: return HeadJoint(minY: 42, pivot: V3(0, 42, 0))
        case .villager: return HeadJoint(minY: 23.4, pivot: V3(0, 23.5, 0))
        case .cow: return HeadJoint(maxZ: -9, pivot: V3(0, 19, -9))
        case .sheep: return HeadJoint(maxZ: -7, pivot: V3(0, 18, -7))
        case .pig: return HeadJoint(maxZ: -7, pivot: V3(0, 12, -7))
        case .chicken: return HeadJoint(maxZ: -4, pivot: V3(0, 11, -4))
        default: return nil
        }
    }

    // Kinds that never tip over (machines, vehicles, the wyrm with its own death, boats and minecarts).
    static func falls(_ m: Mob) -> Bool {
        if m.spec.behavior == .vehicle || m.kind == .enderDragon || m.kind == .deckGun || m.kind == .endCrystal || m.kind == .armorStand { return false }
        switch m.kind {
        case .ashTank, .ashHalftrack, .ashArtillery, .ashTruck: return false
        default: return true
        }
    }

    static func rx(_ a: Float) -> simd_float3x3 { simd_float3x3(V3(1, 0, 0), V3(0, cosf(a), sinf(a)), V3(0, -sinf(a), cosf(a))) }
    static func ry(_ a: Float) -> simd_float3x3 { simd_float3x3(V3(cosf(a), 0, -sinf(a)), V3(0, 1, 0), V3(sinf(a), 0, cosf(a))) }
    static func rz(_ a: Float) -> simd_float3x3 { simd_float3x3(V3(cosf(a), sinf(a), 0), V3(-sinf(a), cosf(a), 0), V3(0, 0, 1)) }

    static func pose(_ m: Mob) -> MobPose {
        var p = MobPose()
        if m.lying || m.sitting || m.carcass { return p }                // a hunted body lies on its side (Hunting.swift)
        if m.deathT < 0, let j = headJoint(m) {
            let big: Float = m.baby ? 1.35 : 1
            p.ha = ry(m.headYaw) * rx(m.headPitch) * simd_float3x3(diagonal: V3(repeating: big))
            p.hb = j.pivot - p.ha * j.pivot
            if m.headYaw != 0 || m.headPitch != 0 || big != 1 { p.joint = j }
        }
        guard falls(m) else { return p }
        // Body: a lunge forward on an attack (front down), rocked back by a hit, a breath at rest.
        let strike = m.strikeT > 0 ? sinf(min(1, m.strikeT / 0.3) * .pi) : 0
        let rock = min(1, m.hurt / 0.3)
        let breathe = 1 + 0.018 * sinf(m.animT * 2.3) * (1 - min(1, m.walkAmount * 2)) * (m.deathT < 0 ? 1 : 0)
        var a = rx(-0.16 * strike + 0.12 * rock * (m.deathT < 0 ? 1 : 0)) * simd_float3x3(diagonal: V3(1, breathe, 1))
        var b = V3.zero
        if m.deathT >= 0 {
            // Tips over sideways about the outer edge of its footprint (to its right), easing in like a fall.
            let k = min(1, m.deathT / fallTime)
            let ang = -k * k * (.pi / 2) * (m.height < m.halfW * 2.5 ? 0.35 : 1)      // flat mobs roll only a little
            let edge = V3(m.halfW * 16 / max(0.25, m.sized ? 1 : m.scale), 0, 0)
            let r = rz(ang)
            a = r * a
            b = edge - r * edge
            let sink = max(0, m.deathT - 0.65) * 6                                       // settles into the ground
            b.y -= sink
        }
        p.a = a; p.b = b
        return p
    }
}

extension Mob {
    // Called from update (alive only): what it watches, the strike pulse, the breathing clock.
    func animTick(_ dt: Float, _ g: Game) {
        animT += dt
        if attackCooldown > lastCooldown + 0.3 { strikeT = 0.3 }        // an attack just reset the cooldown
        lastCooldown = attackCooldown
        strikeT = max(0, strikeT - dt)
        guard MobAnim.headJoint(self) != nil else { return }
        lookTimer -= dt
        if lookTimer <= 0 {
            lookTimer = 0.25
            let pe = g.player.eye
            let d = simd_length(pe - eye)
            if kind.hostile {
                lookAt = d < 16 && g.alive ? pe : nil
            } else if d < 6 && g.alive {
                // Animals and townsfolk glance at you now and then when you're close, and watch you when you hold food
                // (breeding) or stand right beside them.
                if lookAt == nil && Rand.float(in: 0..<1) < (d < 2.5 ? 0.6 : 0.12) { lookAt = pe }
                else if lookAt != nil && Rand.float(in: 0..<1) < 0.05 { lookAt = nil }
                if lookAt != nil { lookAt = pe }
            } else { lookAt = nil }
        }
        var ty: Float = 0, tp: Float = 0
        if let t = lookAt {
            let d = t - (pos + V3(0, height * 0.85, 0))
            let want = atan2f(-d.x, -d.z)
            var rel = want - yaw
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            if abs(rel) < 1.9 {                                       // behind it: it turns its body, not its neck
                ty = max(-1.1, min(1.1, rel))
                tp = max(-0.6, min(0.6, atan2f(d.y, hypotf(d.x, d.z))))
            }
        }
        let k = min(1, dt * 8)
        headYaw += (ty - headYaw) * k
        headPitch += (tp - headPitch) * k
        if abs(headYaw) < 1e-3 && ty == 0 { headYaw = 0 }
        if abs(headPitch) < 1e-3 && tp == 0 { headPitch = 0 }
    }
}

extension MobManager {
    func addCorpse(_ m: Mob, _ g: Game) {
        guard m.health > -1000, MobAnim.falls(m), m.deck == nil, m.deathT < 0 else { return }
        // A game animal you brought down already lies there as its body to skin (Hunting.died): no second fall.
        if Hunting.bodies.contains(where: { $0.mob.kind == m.kind && abs($0.mob.pos.x - m.pos.x) < 0.01 && abs($0.mob.pos.z - m.pos.z) < 0.01 }) { return }
        if corpses.count >= MobAnim.maxCorpses { corpses.removeFirst() }
        m.deathT = 0
        m.hurt = 0.3
        corpses.append(m)
    }

    func corpseTick(_ dt: Float, _ g: Game) {
        guard !corpses.isEmpty else { return }
        for c in corpses { c.deathT += dt }
        for c in corpses where c.deathT >= MobAnim.deathTime {
            let n = Int(4 + min(8, c.height * c.halfW * 8))
            for _ in 0..<n { g.particles.deathPuff(at: c.pos + V3(Rand.float(in: -c.halfW...c.halfW), Rand.float(in: 0...max(0.2, c.height * 0.5)), Rand.float(in: -c.halfW...c.halfW))) }
        }
        corpses.removeAll { $0.deathT >= MobAnim.deathTime }
    }
}
