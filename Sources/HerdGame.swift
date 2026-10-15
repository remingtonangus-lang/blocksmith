import Foundation
import simd

// D45: deer, elk, bison herds and boar. Big game of the open country, each living the way its kind does:
//   deer   forests, taiga, meadows and the plains' edges, in twos to fours. Wary: you can't walk up on them (18 blocks,
//          8 sneaking) and when one bolts the whole group goes with it, white tails up.
//   elk    taiga, snowy taiga, groves, meadows and windswept hills, in small herds. Less flighty (14, 6 sneaking); a
//          bull you hurt turns and charges with his antlers before he runs.
//   bison  plains and savanna, in herds of four to eight that graze close together. They hardly mind you (7 blocks),
//          but hurt one and the herd stampedes off while its bulls charge.
//   boar   forests, dark forests and jungles, in sounders of two or three. Hot-tempered: come within 4 blocks or hurt
//          one and it charges and gores, then backs off and comes again.
// Herds keep together (a straggler more than 9 blocks from the herd's middle walks back). All four are game animals
// (Hunting.swift): pelts by quality, gamey meat, and a trophy (antlers, horns, tusks).
extension MobKind {
    var herdGame: Bool { self == .deer || self == .elk || self == .bison || self == .boar }

    var herdSpec: Spec {
        switch self {
        case .deer:
            return Spec(name: "Deer", halfW: 0.4, height: 1.4, health: 14, speed: 3.2, behavior: .animal,
                        drops: [("game_meat", 1, 3), ("leather", 0, 1)], xp: 3, call: .mob(self, .ambient))
        case .elk:
            return Spec(name: "Elk", halfW: 0.6, height: 1.9, health: 26, speed: 3.0, behavior: .animal, attack: 5,
                        drops: [("game_meat", 2, 4), ("leather", 1, 2)], xp: 5, call: .mob(self, .ambient))
        case .bison:
            return Spec(name: "Bison", halfW: 0.8, height: 1.8, health: 40, speed: 2.4, behavior: .animal, attack: 7,
                        drops: [("game_meat", 3, 5), ("leather", 1, 3)], xp: 6, call: .mob(self, .ambient))
        default:
            return Spec(name: "Boar", halfW: 0.45, height: 0.9, health: 16, speed: 2.6, behavior: .animal, attack: 4,
                        drops: [("porkchop", 1, 3), ("game_meat", 0, 1)], xp: 4, call: .mob(self, .ambient))
        }
    }
}

enum HerdGame {
    static var spooks = 0, charges = 0, gores = 0            // (harness)
    static func spookRange(_ k: MobKind) -> Float { k == .deer ? 18 : (k == .elk ? 14 : (k == .bison ? 7 : 0)) }
}

extension Mob {
    var bull: Bool { variant == 1 }

    // animalAI: the herd game's own ways (nil: not one of them).
    func herdAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float? {
        guard kind.herdGame else { return nil }
        if variant == 0 { variant = Rand.float(in: 0..<1) < (kind == .boar ? 0.5 : 0.3) ? 1 : 2 }
        let p = g.player.pos
        let flat = V3(p.x - pos.x, 0, p.z - pos.z)
        let fd = max(0.01, simd_length(flat))
        // A charge: head down at the player, a gore on contact, then off.
        if phase == 1 {
            fleeTime = 0
            aiTimer = max(aiTimer, 0.5)
            circleAngle -= dt
            face(p)
            moving = true
            if attackCooldown <= 0 && dist < halfW + 1.4 {
                attackCooldown = 1.2
                g.hurtPlayer(spec.attack, from: pos, cause: "was gored by a \(spec.name)", knockback: kind == .bison ? 1.2 : 0.7, attacker: self)
                HerdGame.gores += 1
                circleAngle = min(circleAngle, 0.4)
            }
            if circleAngle <= 0 || !canTarget {
                phase = 0; aggro = false
                fleeGoal = pos - flat / fd * 10; fleeTime = kind == .boar ? 2 : 4
            }
            return spec.speed * 1.5
        }
        let fights = kind == .boar || ((kind == .bison || kind == .elk) && bull)
        let provoked = aggro || wasHit
        if fights && canTarget && dist < 16 && fleeTime <= 0 && (provoked || (kind == .boar && dist < 4)) {
            phase = 1; circleAngle = 3; wasHit = false
            HerdGame.charges += 1
            g.sfx(.mob(kind, .ambient), 1, at: pos)
            if kind == .bison { spookHerd(g, from: p) }          // the rest stampede
            return spec.speed
        }
        // Spooked: a player too close, or a hit.
        let r = HerdGame.spookRange(kind) * (g.player.sneaking ? 0.45 : 1) * Tracking.scent(g, player: p, animal: pos)   // D46: the wind
            * (Tracking.isEating(self) ? 0.5 : 1)
        if (g.alive && dist < r) || (provoked && !fights) {
            aggro = false; wasHit = false
            spookHerd(g, from: p)
        }
        if fleeTime > 0, let goal = fleeGoal {
            fleeTime -= dt
            // P285 (Oct 14 19:41, "the deer sometimes run in circles"): a deer at 5 blocks a second reached its goal 16
            // blocks off in about 3 s and spent the rest of the bolt turning round the point (face() flipping it each
            // step). At the goal: still too close to the player, run on the same way; otherwise stop and look back.
            if simd_length(V2(goal.x - pos.x, goal.z - pos.z)) < 2.5 {
                let away: V3 = fd > 0.5 ? -flat / fd : V3(-sinf(yaw), 0, -cosf(yaw))
                if g.alive && dist < r * 1.2 {
                    fleeGoal = pos + away * 12
                } else {
                    fleeTime = 0; fleeGoal = nil; moving = false; aiTimer = Rand.float(in: 1.5...3.5)
                    face(p); faceGoal = nil
                    return 0
                }
            }
            face(fleeGoal ?? goal)
            moving = true
            return spec.speed * 1.6
        }
        if let sp = Tracking.baitStep(self, g, dt) { return sp }             // D46: bait
        // Keep with the herd.
        circleAngle -= dt
        if circleAngle <= 0 {
            circleAngle = Rand.float(in: 0.8...1.4)
            var c = V3(0, 0, 0), n: Float = 0
            for o in g.mobs.mobs where o.kind == kind && o.health > 0 && simd_length(o.pos - pos) < 24 { c += o.pos; n += 1 }
            if n > 1 { home = c / n }
        }
        if let c = home, simd_length(V2(c.x - pos.x, c.z - pos.z)) > 9 { face(c); moving = true; return spec.speed * 0.5 }
        wander()
        return moving ? spec.speed * 0.3 : 0
    }

    // This animal and its herd within 20 blocks run from `threat`.
    func spookHerd(_ g: Game, from threat: V3) {
        guard fleeTime < 0.5 else { return }
        var away = V3(pos.x - threat.x, 0, pos.z - threat.z)
        if simd_length(away) < 0.01 { away = V3(1, 0, 0) }
        away = simd_normalize(away)
        HerdGame.spooks += 1
        for o in g.mobs.mobs where o.kind == kind && o.health > 0 && o.phase != 1 && simd_length(o.pos - pos) < 20 && o.fleeTime < 0.5 {
            o.fleeGoal = o.pos + away * 16 + V3(Rand.float(in: -3...3), 0, Rand.float(in: -3...3))
            o.fleeTime = Rand.float(in: 3.5...5)
        }
        g.sfx(.mob(kind, .hurt), 0.6, at: pos)
    }
}

// Models (1/16 block, facing -z).
func herdParts(_ m: Mob, swing: Float) -> [Part] {
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c)
    }
    let dark = V3(0.06, 0.05, 0.05), hoof = V3(0.12, 0.1, 0.08), bone = V3(0.82, 0.76, 0.62)
    let run: Float = m.fleeTime > 0 ? 1.4 : 1
    switch m.kind {
    case .deer, .elk:
        let elk = m.kind == .elk
        let s: Float = elk ? 1.3 : 1
        let c = elk ? V3(0.52, 0.38, 0.24) : V3(0.66, 0.46, 0.28), belly = elk ? V3(0.72, 0.62, 0.46) : V3(0.9, 0.84, 0.72)
        let neck = elk ? V3(0.36, 0.26, 0.18) : c
        let lh = 12 * s
        var p: [Part] = [
            Part(mn: V3(-3.5 * s, lh, -8 * s), mx: V3(3.5 * s, lh + 7 * s, 9 * s), color: c, pattern: 12),
            box(-3 * s, lh - 0.5, -6 * s, 6 * s, 1, 13 * s, belly),
            Part(mn: V3(-2 * s, lh + 4 * s, -11 * s), mx: V3(2 * s, lh + 12 * s, -6 * s), pivot: V3(0, lh + 5 * s, -7 * s), rotX: -0.35, color: neck),   // neck
            box(-2.2 * s, lh + 10 * s, -15 * s, 4.4 * s, 4 * s, 6 * s, c, 12),                   // head
            box(-1.5 * s, lh + 10 * s, -17 * s, 3 * s, 2.5 * s, 2 * s, belly),                   // muzzle
            box(-0.6 * s, lh + 11.6 * s, -17.2 * s, 1.2 * s, 0.9, 0.3, dark),
            box(-3.6 * s, lh + 13 * s, -11 * s, 1.6 * s, 2.4 * s, 0.8, c), box(2 * s, lh + 13 * s, -11 * s, 1.6 * s, 2.4 * s, 0.8, c),   // ears
            box(-1.3 * s, lh + 4 * s + (m.fleeTime > 0 ? 2 : 0), 8.8 * s, 2.6 * s, 3 * s, 1.4, m.fleeTime > 0 ? V3(0.96, 0.95, 0.92) : c),   // tail
        ]
        if m.bull {
            // Antlers: a beam each side and tines up and forward.
            let a = bone * 0.9
            for side: Float in [-1, 1] {
                let bx = side * 1.5 * s
                p.append(box(bx - 0.5, lh + 14 * s, -12 * s, 1, 4 * s, 1, a))
                p.append(box(side < 0 ? bx - 3 * s : bx, lh + 17.5 * s, -12 * s, 3 * s, 1, 1, a))
                for k in 0..<(elk ? 3 : 2) {
                    let tx = bx + side * Float(k + 1) * 1.2 * s
                    p.append(box(tx - 0.5, lh + 17.5 * s, -12.5 * s - Float(k), 1, (elk ? 4 : 2.6) * s, 1, a))
                }
            }
        }
        let lw = 1.8 * s
        p += [leg(-2.2 * s, -6 * s, lw, lh, run, c), leg(2.2 * s, -6 * s, lw, lh, -run, c),
              leg(-2.2 * s, 7 * s, lw, lh, -run, c), leg(2.2 * s, 7 * s, lw, lh, run, c)]
        for (x, z) in [(-2.2, -6.0), (2.2, -6.0), (-2.2, 7.0), (2.2, 7.0)] as [(Float, Float)] {
            p.append(box(x * s - lw / 2, 0, z * s - lw / 2, lw, 1.5, lw, hoof))
        }
        return p
    case .bison:
        let c = V3(0.36, 0.25, 0.16), shag = V3(0.22, 0.15, 0.1)
        var p: [Part] = [
            Part(mn: V3(-6, 11, -4), mx: V3(6, 22, 12), color: c, pattern: 12),            // the hind body
            Part(mn: V3(-7, 9, -12), mx: V3(7, 26, -2), color: shag, pattern: 12),         // shoulders and hump, shaggy
            box(-4, 8, -19, 8, 10, 8, shag, 12),                                          // the low head
            box(-3, 7, -21, 6, 5, 3, V3(0.16, 0.11, 0.08)),                               // muzzle
            box(-2, 4, -16, 4, 4, 4, shag),                                               // beard
            box(-6.5, 16, -16, 2.5, 1.5, 1.5, bone), box(4, 16, -16, 2.5, 1.5, 1.5, bone),     // horns out
            box(-6.5, 17.5, -16, 1.5, 2, 1.5, bone), box(5, 17.5, -16, 1.5, 2, 1.5, bone),     // and up
            Part(mn: V3(-0.6, 15, 12), mx: V3(0.6, 21, 13), pivot: V3(0, 21, 12.5), rotX: 0.2 + sinf(m.walkPhase) * 0.2, color: shag),
        ]
        p += [leg(-4, -8, 3.4, 10, run, shag), leg(4, -8, 3.4, 10, -run, shag), leg(-4, 9, 3, 11, -run, c), leg(4, 9, 3, 11, run, c)]
        return p
    default:
        let c = V3(0.28, 0.22, 0.18), bristle = V3(0.18, 0.14, 0.12)
        let head: Float = m.phase == 1 ? -1.5 : 0
        var p: [Part] = [
            Part(mn: V3(-4, 5, -7), mx: V3(4, 12, 9), color: c, pattern: 12),
            box(-1.5, 12, -7, 3, 1.5, 12, bristle),                                       // the crest
            box(-3, 5 + head, -13, 6, 6, 6, c, 12),                                       // head
            box(-2, 5 + head, -15, 4, 3, 2, V3(0.42, 0.32, 0.3)),                         // snout
            box(-2.8, 6 + head, -15, 0.9, 2.6, 0.9, bone), box(1.9, 6 + head, -15, 0.9, 2.6, 0.9, bone),   // tusks
            box(-2.6, 11 + head, -10, 1.4, 1.6, 1, c), box(1.2, 11 + head, -10, 1.4, 1.6, 1, c),
            box(-0.4, 8, 9, 0.8, 3, 0.8, bristle),                                        // tail
        ]
        p += [leg(-2.5, -5, 2.2, 5, run, bristle), leg(2.5, -5, 2.2, 5, -run, bristle), leg(-2.5, 6, 2.2, 5, -run, bristle), leg(2.5, 6, 2.2, 5, run, bristle)]
        return p
    }
}
