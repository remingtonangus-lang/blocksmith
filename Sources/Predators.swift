import Foundation
import simd

// D14 frontier predators: the cougar, the rattlesnake and the alligator. They are wild animals, not monsters of the
// night: they keep to their country by day and night alike, and they hunt.
//   cougar       savanna, badlands, taiga and windswept hills. Stalks low and slow while you're 7-28 blocks off, then
//                pounces (a leap at you) and mauls; breaks off and slinks away below a third of its health.
//   rattlesnake  desert and badlands. Lies coiled; rattles when you come within 5 blocks; strikes inside 1.8 (a bite
//                and venom: poison 6 s). It never chases far; step back and it settles.
//   alligator    swamps and mangroves. Floats low by the bank; within 9 blocks and near water it surges at you (a
//                second and a half of speed) and bites hard, then drifts back to the water. Slow on dry land.
// Hides: cougar pelts and alligator hide make leather; rattlesnake skin is string (a band for a hat).
extension MobKind {
    var frontierPredator: Bool { self == .cougar || self == .rattlesnake || self == .alligator }
    var snakeLike: Bool { self == .rattlesnake || self == .emberAsp }          // P506: the Ember Asp lives as the rattlesnake

    var predatorSpec: Spec {
        switch self {
        case .cougar:
            return Spec(name: "Cougar", halfW: 0.4, height: 0.9, health: 22, speed: 3.6, behavior: .monster, attack: 5,
                        drops: [("leather", 1, 2), ("game_meat", 1, 2)], xp: 6, call: .mob(self, .ambient))
        case .emberAsp:                                            // P506 (HellWild.swift)
            return Spec(name: "Ember Asp", halfW: 0.3, height: 0.3, health: 8, speed: 1.6, behavior: .monster, attack: 3,
                        drops: [("blaze_powder", 0, 1), ("string", 0, 1)], xp: 4, call: .mob(self, .ambient), fireImmune: true)
        case .slagmaw:
            return Spec(name: "Slagmaw", halfW: 0.7, height: 0.6, health: 40, speed: 1.6, behavior: .monster, attack: 9,
                        drops: [("leather", 1, 2), ("magma_cream", 0, 2)], xp: 10, call: .mob(self, .ambient), fireImmune: true)
        case .rattlesnake:
            return Spec(name: "Rattlesnake", halfW: 0.3, height: 0.3, health: 6, speed: 1.4, behavior: .monster, attack: 2,
                        drops: [("string", 0, 2)], xp: 3, call: .mob(self, .ambient))
        default:
            return Spec(name: "Alligator", halfW: 0.6, height: 0.6, health: 34, speed: 1.6, behavior: .monster, attack: 8,
                        drops: [("leather", 1, 3), ("game_meat", 0, 2)], xp: 8, call: .mob(self, .ambient))
        }
    }
}

enum Predators {
    static var pounces = 0, strikes = 0, surges = 0              // (tests)
}

extension Mob {
    func predatorAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let target = g.player.pos
        let flat = V3(target.x - pos.x, 0, target.z - pos.z)
        let fd = max(0.01, simd_length(flat))
        func bite(_ cause: String, venom: Bool = false) {
            guard attackCooldown <= 0, dist < halfW + 1.3 else { return }
            attackCooldown = kind.snakeLike ? 1.6 : 1.1
            g.hurtPlayer(spec.attack, from: pos, cause: cause, attacker: self)
            // (P506: hell's bite burns instead of poisoning)
            if kind.hellWild { if !g.effects.has(.fireResistance) { g.onFire = max(g.onFire, venom ? 4 : 2) } }
            else if venom { g.applyEffect(.poison, amp: 0, seconds: 6) }
            g.sfx(.mob(kind, .hurt), 0.8, at: pos)
        }
        switch kind {
        case .cougar:
            if Float(health) < Float(spec.health) / 3 {
                face(pos - flat); return spec.speed                       // slinks away
            }
            guard canTarget, dist < 28 else { wander(); return moving ? 1.2 : 0 }
            face(target)
            if dist > 7 { return 1.5 }                                     // stalking
            if phase == 0 && onGround && dist > 2.2 && attackCooldown <= 0 {
                vel += flat / fd * 9 + V3(0, 6, 0)                        // the pounce
                phase = 1; aiTimer = 1.2
                Predators.pounces += 1
                g.sfx(.mob(kind, .ambient), 1, at: pos)
            }
            if phase == 1 { aiTimer -= dt; if aiTimer <= 0 || onGround && aiTimer < 0.8 { phase = 0 } }
            bite("was mauled by a Cougar")
            return dist > 1.4 ? spec.speed : 0
        case .rattlesnake, .emberAsp:
            guard canTarget, dist < 6 else { wander(); return moving ? 0.6 : 0 }
            face(target)
            if callTimer > 1.5 { callTimer = 1.2; g.sfx(.mob(kind, .ambient), 0.9, at: pos) }    // the rattle
            if dist < 1.8 + halfW && attackCooldown <= 0 {
                vel += flat / fd * 5
                bite(kind == .emberAsp ? "was burnt by an Ember Asp's bite" : "was bitten by a Rattlesnake", venom: true)
                Predators.strikes += 1
            }
            return 0
        default:
            let wet = Blocks.isLiquid(g.world.builtBlock(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z))))
            let nearWater = wet || waterNear(g.world)
            if phase == 1 {
                aiTimer -= dt
                if aiTimer <= 0 { phase = 0; attackCooldown = max(attackCooldown, 2) }
                face(target)
                bite(kind == .slagmaw ? "was dragged into the lava by a Slagmaw" : "was dragged under by an Alligator")
                return 5.2
            }
            guard canTarget, dist < 9, nearWater else { wander(); return moving ? (wet ? 2 : 0.8) : 0 }
            face(target)
            if attackCooldown <= 0 && dist > 1.5 {
                phase = 1; aiTimer = 1.5
                Predators.surges += 1
                g.sfx(.mob(kind, .ambient), 1, at: pos)
            }
            bite(kind == .slagmaw ? "was dragged into the lava by a Slagmaw" : "was dragged under by an Alligator")
            return wet ? 2.2 : 1.2
        }
    }

    func waterNear(_ w: World) -> Bool {
        let x = Int(floor(pos.x)), y = Int(floor(pos.y)), z = Int(floor(pos.z))
        for dz in stride(from: -3, through: 3, by: 3) { for dx in stride(from: -3, through: 3, by: 3) {
            if Blocks.isLiquid(w.builtBlock(x + dx, y - 1, z + dz)) || Blocks.isLiquid(w.builtBlock(x + dx, y, z + dz)) { return true }
        } }
        return false
    }
}

// Models (1/16 block, facing -z).
func predatorParts(_ m: Mob, swing: Float) -> [Part] {
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c)
    }
    let dark = V3(0.06, 0.05, 0.05)
    switch m.kind {
    case .cougar:
        let c = V3(0.72, 0.56, 0.36), belly = V3(0.88, 0.8, 0.66)
        let crouch: Float = m.phase == 0 && m.walkAmount > 0.1 && m.aggro ? -2 : 0
        var p: [Part] = [
            Part(mn: V3(-3.5, 7 + crouch, -9), mx: V3(3.5, 13 + crouch, 9), color: c, pattern: 12),
            box(-3, 6.5 + crouch, -6, 6, 1, 12, belly),
            box(-3, 10 + crouch, -15, 6, 5, 6, c, 12),                           // head
            box(-2, 10 + crouch, -17, 4, 2.5, 2, belly),                         // muzzle
            box(-0.6, 11.5 + crouch, -17.2, 1.2, 1, 0.3, dark),                  // nose
            box(-3, 15 + crouch, -12, 1.5, 1.5, 1, c), box(1.5, 15 + crouch, -12, 1.5, 1.5, 1, c),     // ears
            box(-2.2, 13 + crouch, -15.2, 1, 0.8, 0.3, V3(0.75, 0.7, 0.2)), box(1.2, 13 + crouch, -15.2, 1, 0.8, 0.3, V3(0.75, 0.7, 0.2)),
            Part(mn: V3(-0.8, 9 + crouch, 9), mx: V3(0.8, 10.5 + crouch, 22), pivot: V3(0, 10, 9), rotX: 0.35 + sinf(m.walkPhase) * 0.15, color: c),
            box(-1, 7.5 + crouch, 20.5, 2, 2, 2.5, dark),                        // tail tip
        ]
        p += [leg(-2.3, -6, 2.4, 7 + crouch, 1, c), leg(2.3, -6, 2.4, 7 + crouch, -1, c), leg(-2.3, 6, 2.6, 7 + crouch, -1, c), leg(2.3, 6, 2.6, 7 + crouch, 1, c)]
        return p
    case .rattlesnake:
        let c = V3(0.62, 0.52, 0.34), band = V3(0.32, 0.24, 0.16)
        var p: [Part] = []
        // A coil of segments, the head raised on the last, the rattle up at the back.
        for i in 0..<9 {
            let a = Float(i) * 0.7 + m.walkPhase * 0.3
            let r: Float = 5 - Float(i) * 0.3
            let x = cosf(a) * r, z = sinf(a) * r
            p.append(box(x - 1.3, 0, z - 1.3, 2.6, 2.2, 2.6, i % 2 == 0 ? c : band, 12))
        }
        let rear: Float = m.aggro ? 4 : 2
        p.append(box(-1.2, 2, -4, 2.4, rear + 1, 2.4, c, 12))                  // the raised neck
        p.append(box(-1.6, 2 + rear, -6.5, 3.2, 2, 4, c, 12))                  // head
        p.append(box(-1.1, 3 + rear, -6.8, 0.6, 0.6, 0.3, dark)); p.append(box(0.5, 3 + rear, -6.8, 0.6, 0.6, 0.3, dark))
        p.append(Part(mn: V3(3.2, 2, 3), mx: V3(4.4, 5.5, 4.2), pivot: V3(3.8, 2, 3.6), rotX: sinf(m.walkPhase * 9) * 0.2, color: V3(0.8, 0.72, 0.55)))
        return p
    default:
        let c = V3(0.22, 0.28, 0.16), belly = V3(0.55, 0.55, 0.38)
        let jaw: Float = m.phase == 1 ? 0.45 : 0.05
        var p: [Part] = [
            Part(mn: V3(-6, 3, -10), mx: V3(6, 8, 12), color: c, pattern: 12),
            box(-5.5, 2.5, -9, 11, 0.8, 20, belly),
            box(-4, 3.5, -20, 8, 4, 10, c, 12),                                   // snout
            Part(mn: V3(-3.8, 2.5, -20), mx: V3(3.8, 3.8, -10), pivot: V3(0, 3.5, -10), rotX: -jaw, color: belly),   // lower jaw
            box(-3.5, 7.5, -12, 2, 1.5, 2, c), box(1.5, 7.5, -12, 2, 1.5, 2, c),  // eye bumps
            box(-3.2, 8.2, -11.6, 1, 0.8, 0.3, V3(0.8, 0.7, 0.2)), box(2.2, 8.2, -11.6, 1, 0.8, 0.3, V3(0.8, 0.7, 0.2)),
            Part(mn: V3(-4, 3, 12), mx: V3(4, 7, 22), pivot: V3(0, 5, 12), rotX: 0, color: c, pattern: 12),
            Part(mn: V3(-2.5, 3, 21), mx: V3(2.5, 5.5, 32), pivot: V3(0, 4, 21), rotX: sinf(m.walkPhase) * 0.1, color: c, pattern: 12),
        ]
        for k in 0..<6 { p.append(box(-1, 8, -8 + Float(k) * 3.4, 2, 1, 1.6, c * 0.8)) }    // the ridge
        p += [leg(-6.5, -6, 3, 3.5, 1, c), leg(6.5, -6, 3, 3.5, -1, c), leg(-6.5, 8, 3, 3.5, -1, c), leg(6.5, 8, 3, 3.5, 1, c)]
        return p
    }
}
