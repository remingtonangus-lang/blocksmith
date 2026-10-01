import Foundation
import simd

// The Steelhold garrison: four soldier ranks of rising difficulty, and the heavy deck guns on the
// fortress corners.
//  Recruit  20 HP, light kit, rifle or chatter gun; short bursts from mid range, falls back when hurt.
//  Trooper  30 HP, plated; shotgun (rushes in) or rifle (strafes); lobs grenades at players in cover.
//  Marksman 26 HP; farsight rifle from long range with a red aiming laser before each shot; backs away.
//  Ironclad 60 HP, heavy armour, shrugs off knockback; skybreaker or arc lance; advances, enrages.
// They alert each other, chase the last place they saw the player, and reload between magazines.
// Deck guns traverse slowly, solve a ballistic arc, glow while charging, then fire twin shells.

final class SoldierBrain {
    var gun: Int
    var mag: Int
    var reload: Float = 0
    var burst = 0
    var shotTimer: Float = 0
    var react: Float = 1
    var aimTime: Float = 0
    var strafeTimer: Float = 0
    var strafeDir: Float = 1
    var lastSeen: V3?
    var seenAgo: Float = 99
    var sees = false
    var losTimer: Float = 0
    var grenadeCD: Float = Float.random(in: 4...10)
    var retreat: Float = 0
    var retreatCD: Float = 0
    var pitch: Float = 0            // deck gun barrel elevation / soldier aim elevation
    var charge: Float = 0
    var kick: Float = 0             // deck gun barrel recoil 1 -> 0
    var cover: V3?                  // a spot out of the player's sight to reload in
    var coverSearch: Float = 0
    var flank: V3?                  // where a flanking trooper / relocating marksman is heading
    var flankTimer: Float = Float.random(in: 2...5)
    init(gun: Int) { self.gun = gun; mag = gun >= 0 ? Guns.all[gun].mag : 0 }
}

enum Soldier {
    struct Rank {
        let near: Float, far: Float     // preferred distance band (overridden per gun below)
        let sight: Float
        let spread: Float               // aim error (radians)
        let burst: ClosedRange<Int>
        let gap: ClosedRange<Float>     // pause between bursts
        let react: Float                // delay before the first shot after spotting
        let strafe: Float               // 0...1 how much they sidestep
        let damage: Float               // multiplier on the gun's damage
        let armor: Int
        let toughness: Float
    }
    static let ranks: [Rank] = [
        Rank(near: 8, far: 14, sight: 26, spread: 0.07, burst: 3...5, gap: 1.0...1.8, react: 0.9, strafe: 0.3, damage: 0.8, armor: 4, toughness: 0),
        Rank(near: 7, far: 12, sight: 32, spread: 0.045, burst: 4...6, gap: 0.8...1.4, react: 0.7, strafe: 0.8, damage: 0.9, armor: 10, toughness: 2),
        Rank(near: 16, far: 40, sight: 60, spread: 0.012, burst: 1...1, gap: 1.6...2.4, react: 0.4, strafe: 0.2, damage: 0.75, armor: 8, toughness: 0),
        Rank(near: 8, far: 20, sight: 40, spread: 0.03, burst: 1...2, gap: 1.8...2.6, react: 0.8, strafe: 0, damage: 0.9, armor: 14, toughness: 4),
    ]

    static func rank(_ k: MobKind) -> Int? {
        switch k {
        case .soldierRecruit: return 0
        case .soldierTrooper: return 1
        case .soldierMarksman: return 2
        case .soldierIronclad: return 3
        default: return nil
        }
    }

    // Which gun a new soldier carries.
    static func pickGun(_ k: MobKind) -> Int {
        let r = Float.random(in: 0..<1)
        switch k {
        case .soldierRecruit: return r < 0.6 ? Guns.rifle : Guns.smg
        case .soldierTrooper: return r < 0.5 ? Guns.shotgun : Guns.rifle
        case .soldierMarksman: return r < 0.8 ? Guns.sniper : Guns.rifle
        default: return r < 0.5 ? Guns.launcher : Guns.arc
        }
    }

    // Preferred distance band for a gun (the rank's own for its main weapon).
    static func band(_ rank: Int, _ gun: Int) -> (Float, Float) {
        switch gun {
        case Guns.shotgun: return (2.5, 6)
        case Guns.smg: return (5, 10)
        case Guns.launcher: return (10, 26)
        case Guns.arc: return (6, 18)
        case Guns.rifle where rank == 2: return (12, 26)
        default: return (ranks[rank].near, ranks[rank].far)
        }
    }

    // Reference-style difficulty scaling of their damage against the player.
    static let difficultyTable: [Float] = [0, 0.5, 0.75, 1]
    static func difficultyScale(_ d: Int) -> Float { difficultyTable[max(0, min(3, d))] }
}

extension MobKind {
    var militarySpec: Spec {
        switch self {
        case .soldierRecruit:
            return Spec(name: "Steelhold Recruit", halfW: 0.3, height: 1.9, health: 20, speed: 3.0, behavior: .monster,
                        drops: [("rifle_rounds", 1, 4), ("iron_nugget", 0, 3)], xp: 8, call: .gun(11))
        case .soldierTrooper:
            return Spec(name: "Steelhold Trooper", halfW: 0.32, height: 1.95, health: 30, speed: 3.2, behavior: .monster,
                        drops: [("rifle_rounds", 0, 4), ("shotgun_shells", 0, 3), ("bread", 0, 1)], xp: 12, call: .gun(11))
        case .soldierMarksman:
            return Spec(name: "Steelhold Marksman", halfW: 0.3, height: 1.9, health: 26, speed: 2.8, behavior: .monster,
                        drops: [("heavy_rounds", 1, 3), ("iron_nugget", 0, 2)], xp: 14, call: .gun(11))
        case .soldierIronclad:
            return Spec(name: "Steelhold Ironclad", halfW: 0.42, height: 2.25, health: 60, speed: 2.0, behavior: .monster,
                        drops: [("iron_ingot", 1, 4), ("rocket_ammo", 0, 2), ("arc_cell", 0, 3)], xp: 30, call: .gun(11), fireImmune: true)
        default:
            return Spec(name: "Steelhold Deck Gun", halfW: 1.3, height: 2.0, health: 150, speed: 0, behavior: .monster,
                        drops: [("iron_ingot", 4, 9), ("gunpowder", 2, 6), ("rocket_ammo", 1, 3)], xp: 40, call: .gun(12), fireImmune: true)
        }
    }
}

extension Mob {
    var soldierBrain: SoldierBrain {
        if let b = brain { return b }
        let b = SoldierBrain(gun: kind == .deckGun ? -1 : (variant >= 0 && variant < Guns.all.count ? variant : Guns.rifle))
        brain = b
        return b
    }

    // Base armour of the garrison ranks (added to any worn pieces).
    var steelholdArmor: (Int, Float) {
        if kind == .deckGun { return (20, 8) }
        guard let r = Soldier.rank(kind) else { return (0, 0) }
        return (Soldier.ranks[r].armor, Soldier.ranks[r].toughness)
    }

    // Knockback taken (ironclads barely budge, deck guns not at all).
    var knockbackTaken: Float { kind == .soldierIronclad ? 0.15 : (kind == .deckGun ? 0 : 1) }

    // Wakes every soldier within `r` and tells them where the player was.
    func alertGarrison(_ g: Game, _ at: V3, radius r: Float = 24) {
        for m in g.mobs.mobs where m.kind.steelhold && m !== self && m.health > 0 && simd_length(m.pos - pos) < r {
            let b = m.soldierBrain
            if !m.aggro { m.aggro = true; b.react = max(b.react, 0.6) }
            if b.seenAgo > 1 { b.lastSeen = at; b.seenAgo = min(b.seenAgo, 2) }
            m.lockTime = max(m.lockTime, 20)
        }
    }

    // Called from monsterAI for the four ranks; returns the walk speed.
    func soldierAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        guard let r = Soldier.rank(kind) else { return 0 }
        let rank = Soldier.ranks[r]
        let b = soldierBrain
        let gs = Guns.all[b.gun]
        let w = g.world
        if home == nil { home = pos }
        b.shotTimer -= dt
        b.grenadeCD -= dt
        b.retreat -= dt
        b.retreatCD -= dt
        b.seenAgo += dt
        b.strafeTimer -= dt
        if b.reload > 0 {
            b.reload -= dt
            if b.reload <= 0 { b.mag = gs.mag }
        }
        // Line of sight, a few times a second.
        let target = g.player.eye - V3(0, 0.3, 0)
        b.losTimer -= dt
        if b.losTimer <= 0 {
            b.losTimer = 0.2 + Float.random(in: 0..<0.1)
            b.sees = canTarget && dist < rank.sight && w.canSee(eye, g.player.eye)
        }
        let sees = b.sees && canTarget
        if sees {
            // Noticed up close, in front, or once alerted.
            let toP = simd_normalize(V3(g.player.pos.x - pos.x, 0, g.player.pos.z - pos.z) + V3(1e-4, 0, 0))
            if !aggro && (dist < 10 || simd_dot(toP, forward) > 0.2 || hurt > 0) {
                aggro = true
                b.react = rank.react
                g.sfx(.soldier(r, .alert), 1.1, at: eye)
                if Float.random(in: 0..<1) < 0.5 { g.sfx(.gun(11), 0.6, at: eye) }
                alertGarrison(g, g.player.pos)
            }
            if aggro {
                if b.seenAgo > 3 { b.react = max(b.react, rank.react) }
                b.lastSeen = g.player.pos
                b.seenAgo = 0
            }
        }
        if hurt > 0.35 && !aggro { aggro = true; alertGarrison(g, g.player.pos) }
        guard aggro && canTarget else {
            b.aimTime = 0
            // Garrison duty: stroll near the post; marksmen keep watch.
            if r == 2 {
                if aiTimer <= 0 { aiTimer = Float.random(in: 2...5); yaw += Float.random(in: -1.2...1.2) }
                return 0
            }
            if let h = home, simd_length(V2(h.x - pos.x, h.z - pos.z)) > 10 { face(h); return spec.speed * 0.5 }
            wander()
            return moving ? spec.speed * 0.45 : 0
        }
        b.react -= dt
        b.coverSearch -= dt
        b.flankTimer -= dt
        if b.mag <= 0 && b.reload <= 0 {
            b.reload = gs.reload * (r == 3 ? 1.3 : 1)
            g.sfx(.gunReload(gs.sound), 0.6, at: eye)
            if Float.random(in: 0..<1) < 0.5 { g.sfx(.soldier(r, .reload), 0.9, at: eye) }
        }
        if b.reload <= 0 { b.cover = nil }
        let (near, far) = Soldier.band(r, b.gun)
        var speed: Float = 0
        // Recruits fall back when badly hurt; marksmen back off from anyone who gets close.
        if r == 0 && health < spec.health * 3 / 10 && b.retreatCD <= 0 { b.retreat = 4; b.retreatCD = 12 }
        if r == 2 && sees && dist < 9 && b.retreatCD <= 0 { b.retreat = 2.5; b.retreatCD = 5 }
        if b.retreat > 0 {
            face(pos * 2 - g.player.pos)
            return spec.speed * 1.15
        }
        // Reloading: duck out of sight first (ironclads don't bother).
        if b.reload > 0 && r != 3 {
            if b.cover == nil && b.coverSearch <= 0 && sees { b.cover = findCover(g, from: g.player.eye); b.coverSearch = 1 }
            if let c = b.cover {
                if simd_length(V2(c.x - pos.x, c.z - pos.z)) > 0.6 { face(c); return spec.speed * 1.1 }
                face(g.player.pos)
                return 0
            }
        }
        if sees {
            face(g.player.pos)
            let tp = g.player.eye - V3(0, 0.3, 0) - eye
            b.pitch += (max(-0.9, min(0.9, atan2f(tp.y, simd_length(V2(tp.x, tp.z))))) - b.pitch) * min(1, dt * 8)
            if b.reload > 0 {
                speed = dist < far ? -spec.speed * 0.7 : 0                       // give ground while reloading
            } else if let f = b.flank, b.flankTimer > 0 {
                // Flank / relocate while facing the target: walk the offset with forward + sideways steps.
                var d = f - pos
                d.y = 0
                let l = simd_length(d)
                if l < 1 { b.flank = nil } else {
                    let right = V3(cosf(yaw), 0, -sinf(yaw))
                    speed = simd_dot(d / l, forward) * spec.speed
                    strafe = simd_dot(d / l, right) * spec.speed
                }
            } else if dist > far {
                speed = spec.speed
            } else if dist < near {
                speed = -spec.speed * 0.8
            } else if rank.strafe > 0 {
                if b.strafeTimer <= 0 { b.strafeTimer = Float.random(in: 0.8...2.2); b.strafeDir = Float.random(in: 0..<1) < 0.5 ? -1 : 1 }
                strafe = b.strafeDir * spec.speed * 0.75 * rank.strafe
            }
            if b.gun == Guns.shotgun && dist > near { speed = spec.speed * 1.25 }   // shotgunners rush in
            if r == 3 && health < spec.health / 2 { speed = max(speed, spec.speed * 0.6) }
            // Rifle troopers swing round the target's side every few seconds.
            if r == 1 && b.gun != Guns.shotgun && b.flankTimer <= 0 && b.reload <= 0 {
                b.flankTimer = Float.random(in: 4...7)
                let toMe = simd_normalize(V3(pos.x - g.player.pos.x, 0, pos.z - g.player.pos.z) + V3(1e-4, 0, 0))
                let side = V3(-toMe.z, 0, toMe.x) * (Float.random(in: 0..<1) < 0.5 ? -1 : 1)
                b.flank = g.player.pos + simd_normalize(toMe + side * 1.4) * min(dist, (near + far) / 2)
                if Float.random(in: 0..<1) < 0.5 { g.sfx(.soldier(r, .attack), 0.9, at: eye) }      // "flanking!"
            }
            let shotsBefore = b.mag
            soldierFire(dt, g, b, gs, rank: r, dist: dist, target: target)
            // Marksmen move to a new spot after a shot now and then.
            if r == 2 && b.mag < shotsBefore && Float.random(in: 0..<1) < 0.5 {
                let right = V3(cosf(yaw), 0, -sinf(yaw))
                b.flank = pos + right * (Float.random(in: 0..<1) < 0.5 ? -5 : 5)
                b.flankTimer = 2.5
                if Float.random(in: 0..<1) < 0.3 { g.sfx(.soldier(r, .retreat), 0.8, at: eye) }     // "moving!"
            }
        } else {
            b.aimTime = 0
            // Suppressing fire: automatic guns keep shooting where the player ducked out of sight.
            if let ls = b.lastSeen, b.seenAgo < 2.5, b.gun == Guns.rifle || b.gun == Guns.smg || r == 3,
               b.reload <= 0, b.react <= 0, b.shotTimer <= 0, b.mag > 0, simd_length(ls - pos) < rank.sight {
                suppress(g, b, gs, at: ls + V3(0, 1.2, 0), rank: rank)
            }
            if let ls = b.lastSeen, b.seenAgo < 14 {
                // Troopers flush players out of cover with a grenade, everyone closes in on the last sighting.
                let d = simd_length(ls - pos)
                if r == 1 && b.grenadeCD <= 0 && b.seenAgo < 5 && d > 5 && d < 22 {
                    throwGrenade(g, at: ls)
                    b.grenadeCD = Float.random(in: 9...14)
                }
                face(ls)
                speed = d > 2 ? spec.speed : 0
                if d <= 2 { b.lastSeen = nil }
            } else {
                wander()
                speed = moving ? spec.speed * 0.5 : 0
            }
        }
        return speed
    }

    private func soldierFire(_ dt: Float, _ g: Game, _ b: SoldierBrain, _ gs: GunSpec, rank r: Int, dist: Float, target: V3) {
        guard b.reload <= 0, b.react <= 0, dist < Soldier.ranks[r].sight else { b.aimTime = 0; return }
        if b.mag <= 0 {
            b.reload = gs.reload * (r == 3 ? 1.3 : 1)
            g.sfx(.gunReload(gs.sound), 0.6, at: eye)
            if Float.random(in: 0..<1) < 0.4 { g.sfx(.soldier(r, .reload), 0.9, at: eye) }
            return
        }
        guard b.shotTimer <= 0 else { return }
        // Marksmen hold a laser on the target before every shot.
        if b.gun == Guns.sniper {
            b.aimTime += dt
            if b.aimTime < 1.1 { return }
            b.aimTime = 0
        }
        let rank = Soldier.ranks[r]
        let enraged = r == 3 && health < spec.health / 2
        let muzzle = eye + forward * 0.6 - V3(0, 0.15, 0)
        var aimAt = target
        let flight = gs.speed > 0 ? simd_length(target - muzzle) / gs.speed : 0
        aimAt += g.player.vel * flight * 0.8
        if b.gun == Guns.launcher { aimAt = g.player.pos + V3(0, 0.3, 0) + g.player.vel * flight * 0.6 }
        let dir = simd_normalize(aimAt - muzzle)
        // Soldiers' shotgun pellets hit softer (a point-blank volley shouldn't one-shot a full-health player).
        let scale = Soldier.difficultyScale(g.difficulty) * rank.damage * (gs.pellets > 1 ? 0.6 : 1)
        switch gs.shot {
        case .bullet:
            for _ in 0..<gs.pellets {
                let d = Guns.scatter(dir, rank.spread + gs.spread * 0.5)
                g.arms.spawn(Slug(pos: muzzle, vel: d * gs.speed, kind: .bullet, damage: gs.damage * scale, fromPlayer: false,
                                  shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 1.5))
            }
        case .rocket:
            var s = Slug(pos: muzzle + dir * 0.5, vel: Guns.scatter(dir, rank.spread) * gs.speed, kind: .rocket, damage: 0, fromPlayer: false,
                         shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 0.6)
            s.power = 1.8
            g.arms.spawn(s)
        case .beam:
            g.arms.beam(g, from: muzzle, dir: Guns.scatter(dir, rank.spread), range: gs.range, damage: gs.damage * scale, fromPlayer: false, shooter: self, by: spec.name)
        }
        g.sfx(.gun(gs.sound), 1, at: muzzle)
        g.particles.add(Particle(pos: muzzle + dir * 0.2, vel: dir * 0.5, life: 0.06, maxLife: 0.06, layer: Int(Tex.id("smoke")), uv0: V2(0, 0),
                                 uvSize: 1, size: 0.14, gravity: 0, color: gs.shot == .beam ? V3(0.8, 2, 2.4) : V3(2.4, 1.7, 0.6), collide: false, glow: true))
        b.mag -= 1
        if b.burst <= 0 { b.burst = Int.random(in: rank.burst) }
        b.burst -= 1
        let rate: Float = enraged ? 0.6 : 1
        b.shotTimer = b.burst > 0 ? gs.interval * 1.4 * rate : Float.random(in: rank.gap) * rate
    }

    // A short burst into the player's last position (wider spread; it pins them behind cover).
    private func suppress(_ g: Game, _ b: SoldierBrain, _ gs: GunSpec, at t: V3, rank: Soldier.Rank) {
        let muzzle = eye + forward * 0.6 - V3(0, 0.15, 0)
        let dir = simd_normalize(t - muzzle)
        let scale = Soldier.difficultyScale(g.difficulty) * rank.damage
        if gs.shot == .bullet {
            g.arms.spawn(Slug(pos: muzzle, vel: Guns.scatter(dir, rank.spread + 0.05) * gs.speed, kind: .bullet, damage: gs.damage * scale,
                              fromPlayer: false, shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 1.5))
            b.shotTimer = gs.interval * 2.5
        } else if gs.shot == .rocket {
            var s = Slug(pos: muzzle + dir * 0.5, vel: dir * gs.speed, kind: .rocket, damage: 0, fromPlayer: false,
                         shooter: ObjectIdentifier(self), by: spec.name, life: gs.range / gs.speed, gravity: 0.6)
            s.power = 1.8
            g.arms.spawn(s)
            b.shotTimer = 3
        } else {
            g.arms.beam(g, from: muzzle, dir: Guns.scatter(dir, 0.03), range: gs.range, damage: gs.damage * scale, fromPlayer: false, shooter: self, by: spec.name)
            b.shotTimer = 2.5
        }
        b.mag -= 1
        g.sfx(.gun(gs.sound), 1, at: muzzle)
    }

    // A nearby standing spot the player can't see (sampled in a ring of 2-6 blocks).
    private func findCover(_ g: Game, from threat: V3) -> V3? {
        let w = g.world
        var best: V3?
        var bd = Float.greatestFiniteMagnitude
        let y = Int(floor(pos.y + 0.1))
        for i in 0..<14 {
            let a = Float(i) / 14 * 2 * .pi
            let rr = Float.random(in: 2...6)
            let x = Int(floor(pos.x + cosf(a) * rr)), z = Int(floor(pos.z + sinf(a) * rr))
            for dy in [0, 1, -1] {
                let fy = y + dy
                guard Blocks.collide[Int(w.block(x, fy - 1, z))], !Blocks.collide[Int(w.block(x, fy, z))], !Blocks.collide[Int(w.block(x, fy + 1, z))] else { continue }
                let spot = V3(Float(x) + 0.5, Float(fy), Float(z) + 0.5)
                if !w.canSee(spot + V3(0, 1.5, 0), threat) {
                    let d = simd_length(spot - pos)
                    if d < bd { bd = d; best = spot }
                }
                break
            }
        }
        return best
    }

    private func throwGrenade(_ g: Game, at t: V3) {
        let from = eye + forward * 0.4
        var d = t - from
        let horiz = simd_length(V2(d.x, d.z))
        // Lob at 45 degrees: v^2 = g x / sin(2a) with a little height correction.
        let grav: Float = 20
        let v = sqrtf(grav * max(2, horiz + max(0, d.y) * 0.5))
        d.y = 0
        let flat = horiz > 0.01 ? d / horiz : forward
        var s = Slug(pos: from, vel: (flat + V3(0, 1, 0)) * (v * 0.7071), kind: .grenade, damage: 0, fromPlayer: false,
                     shooter: ObjectIdentifier(self), by: spec.name, life: 2.6, gravity: grav)
        s.power = 2
        g.arms.spawn(s)
        g.sfx(.soldier(Soldier.rank(kind) ?? 1, .grenade), 1.1, at: eye)
    }

    // MARK: Deck gun

    func updateDeckGun(_ dt: Float, _ g: Game) {
        if Turrets.shared.manned === self { vel = .zero; return }      // the player has it (VehicleControls.swift)
        let b = soldierBrain
        vel = .zero
        attackCooldown = max(attackCooldown, -1)
        if fire > 0 { fire -= dt }
        b.reload -= dt
        b.kick = max(0, b.kick - dt * 1.5)
        let pivot = pos + V3(0, 1.0, 0)
        let player = g.player.eye - V3(0, 0.6, 0)
        let to = player - pivot
        let dist = simd_length(to)
        let canTarget = g.survival && g.alive && dist < 80
        b.losTimer -= dt
        if b.losTimer <= 0 {
            b.losTimer = 0.4
            b.sees = canTarget && g.world.canSee(pivot + V3(0, 0.8, 0), g.player.eye)
        }
        if b.sees && canTarget {
            if !aggro { aggro = true; g.sfx(.gun(10), 1.5, at: pivot); alertGarrison(g, g.player.pos, radius: 40) }
            b.lastSeen = player
            b.seenAgo = 0
        } else {
            b.seenAgo += dt
        }
        guard let tgt = b.lastSeen, b.seenAgo < 3 else { b.charge = 0; return }
        // Ballistic solution (low arc) for shells at 55 b/s under 20 b/s^2, half-leading the target.
        let v: Float = 55, grav: Float = 20
        var aimP = tgt
        let flat0 = simd_length(V2(aimP.x - pivot.x, aimP.z - pivot.z))
        aimP += g.player.vel * (flat0 / v) * 0.5
        let dx = simd_length(V2(aimP.x - pivot.x, aimP.z - pivot.z)), dy = aimP.y - pivot.y
        let disc = v * v * v * v - grav * (grav * dx * dx + 2 * dy * v * v)
        var wantPitch: Float = 0.75
        if disc >= 0 && dx > 0.5 { wantPitch = atanf((v * v - sqrtf(disc)) / (grav * dx)) }
        wantPitch = max(-0.17, min(0.9, wantPitch))
        let wantYaw = atan2f(-(aimP.x - pivot.x), -(aimP.z - pivot.z))
        var dyaw = wantYaw - yaw
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }
        let turn: Float = 0.9 * dt
        yaw += max(-turn, min(turn, dyaw))
        b.pitch += max(-0.6 * dt, min(0.6 * dt, wantPitch - b.pitch))
        walkPhase += abs(max(-turn, min(turn, dyaw)))
        let aligned = abs(dyaw) < 0.05 && abs(wantPitch - b.pitch) < 0.03 && dx > 6
        if aligned && b.reload <= 0 {
            if b.charge == 0 { g.sfx(.gun(12), 1.2, at: pivot) }
            b.charge += dt
            if b.charge >= 1.2 {
                b.charge = 0
                b.reload = g.difficulty >= 3 ? 4.5 : 5.5
                let fwd = V3(-sinf(yaw) * cosf(b.pitch), sinf(b.pitch), -cosf(yaw) * cosf(b.pitch))
                let side = V3(cosf(yaw), 0, -sinf(yaw))
                for sx: Float in [-1, 1] {
                    let muzzle = pivot + fwd * 3.4 + side * (sx * 0.44)
                    var s = Slug(pos: muzzle, vel: Guns.scatter(fwd, 0.012) * v, kind: .shell, damage: 0, fromPlayer: false,
                                 shooter: ObjectIdentifier(self), by: spec.name, life: 6, gravity: grav)
                    s.power = 1.8
                    g.arms.spawn(s)
                    for _ in 0..<6 { g.particles.smoke(at: muzzle + fwd * Float.random(in: 0...1), dark: false) }
                    g.particles.add(Particle(pos: muzzle, vel: fwd, life: 0.08, maxLife: 0.08, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                             size: 0.5, gravity: 0, color: V3(2.6, 1.8, 0.7), collide: false, glow: true))
                }
                g.sfx(.gun(9), 2, at: pivot)
                b.kick = 1
            }
        } else if !aligned {
            b.charge = max(0, b.charge - dt * 2)
        }
    }
}

extension Game {
    // Guns and ammo from a fallen soldier; deck guns burst into smoke and scrap.
    func soldierDied(_ m: Mob) {
        guard m.kind.steelhold else { return }
        let at = m.pos + V3(0, 0.6, 0)
        if m.kind == .deckGun {
            particles.explosion(at: m.pos + V3(0, 1, 0), power: 3)
            sfx(.explode, 1.2, at: at)
            return
        }
        let b = m.soldierBrain
        guard b.gun >= 0, b.gun < Guns.all.count else { return }
        let gs = Guns.all[b.gun]
        let looting = m.killedByPlayer ? Float(m.lootingLevel) : 0
        if Items.has(gs.ammo) { drops.spawn(ItemStack(Items.id(gs.ammo), Int.random(in: gs.mag <= 6 ? 1...3 : 4...12)), at: at) }
        if m.killedByPlayer && Float.random(in: 0..<1) < 0.25 + 0.05 * looting && Items.has(gs.key) {
            var s = ItemStack(Items.id(gs.key), 1)
            s.damage = Int.random(in: gs.durability / 4...gs.durability * 3 / 4)
            s.tag = max(0, b.mag)
            drops.spawn(s, at: at)
        }
    }

    func writeSoldierLasers(_ wr: inout EntityWriter, eye: V3) {
        for m in mobs.of(.soldierMarksman) {
            guard let b = m.brain, b.aimTime > 0 else { continue }
            let k = min(1, b.aimTime / 1.1)
            let from = m.eye + m.forward * 0.6 - V3(0, 0.15, 0)
            Armory.streak(&wr, eye, from, player.eye - V3(0, 0.3, 0), 0.012 + 0.012 * k, V4(2.6, 0.15, 0.1, 0.5 + 0.5 * k))
        }
    }
}

// MARK: Models

func soldierParts(_ m: Mob, swing: Float) -> [Part] {
    let r = Soldier.rank(m.kind) ?? 0
    let skin = V3(0.78, 0.6, 0.47)
    let boots = V3(0.12, 0.11, 0.1)
    let aiming = m.aggro
    let aimPitch: Float = aiming ? (m.brain?.pitch ?? 0) : 0
    let armX: Float = aiming ? -1.45 - aimPitch : -0.9
    let gunTilt: Float = aiming ? aimPitch : -0.5
    let big: Float = r == 3 ? 1.12 : 1
    let cloth: V3, plate: V3, trim: V3
    switch r {
    case 0: cloth = V3(0.46, 0.5, 0.55); plate = V3(0.32, 0.35, 0.38); trim = V3(0.9, 0.55, 0.15)
    case 1: cloth = V3(0.3, 0.34, 0.22); plate = V3(0.36, 0.41, 0.26); trim = V3(0.15, 0.17, 0.12)
    case 2: cloth = V3(0.24, 0.27, 0.2); plate = V3(0.2, 0.22, 0.17); trim = V3(0.4, 0.36, 0.26)
    default: cloth = V3(0.17, 0.18, 0.2); plate = V3(0.24, 0.25, 0.28); trim = V3(0.88, 0.7, 0.12)
    }
    let camo: Float = r == 2 ? 4 : 0
    func s(_ p: Part) -> Part {
        guard big != 1 else { return p }
        return Part(mn: p.mn * big, mx: p.mx * big, pivot: p.pivot * big, rotX: p.rotX, rotZ: p.rotZ, color: p.color, pattern: p.pattern)
    }
    var p: [Part] = [
        Part(mn: V3(-4, 0, -2), mx: V3(0, 12, 2), pivot: V3(-2, 12, 0), rotX: swing, color: cloth, pattern: camo),
        Part(mn: V3(0, 0, -2), mx: V3(4, 12, 2), pivot: V3(2, 12, 0), rotX: -swing, color: cloth, pattern: camo),
        Part(mn: V3(-4.2, 0, -2.4), mx: V3(-0.1, 3, 2.2), pivot: V3(-2, 12, 0), rotX: swing, color: boots),
        Part(mn: V3(0.1, 0, -2.4), mx: V3(4.2, 3, 2.2), pivot: V3(2, 12, 0), rotX: -swing, color: boots),
        box(-4, 12, -2, 8, 12, 4, cloth, camo),
        box(-4.4, 14, -2.5, 8.8, 9, 5, plate, camo),                          // vest / chest plate
        box(-4, 24, -4, 8, 8, 8, skin),
        Part(mn: V3(-8, 12, -2), mx: V3(-4, 24, 2), pivot: V3(-6, 23, 0), rotX: armX, color: cloth, pattern: camo),
        Part(mn: V3(4, 12, -2), mx: V3(8, 24, 2), pivot: V3(6, 23, 0), rotX: armX, color: cloth, pattern: camo),
        Part(mn: V3(-8.2, 12, -2.2), mx: V3(-3.8, 14.5, 2.2), pivot: V3(-6, 23, 0), rotX: armX, color: boots),   // gloves
        Part(mn: V3(3.8, 12, -2.2), mx: V3(8.2, 14.5, 2.2), pivot: V3(6, 23, 0), rotX: armX, color: boots),
        box(-3, 13, 2, 6, 9, 3, plate * 0.85),                                 // backpack
    ]
    switch r {
    case 0:
        // Soft cap with a peak, shoulder rank stripe.
        p += [box(-4.3, 30, -4.3, 8.6, 3, 8.6, plate), box(-4.3, 30, -7, 8.6, 1, 3, plate * 0.8),
              box(-8.2, 21, -2.2, 4.4, 1, 4.4, trim), box(3.8, 21, -2.2, 4.4, 1, 4.4, trim),
              box(-2.5, 27, -4.1, 1.5, 1, 0.2, V3(0.1, 0.1, 0.1)), box(1, 27, -4.1, 1.5, 1, 0.2, V3(0.1, 0.1, 0.1))]
    case 1:
        // Plated helmet with a dark visor band, shoulder pads.
        p += [box(-4.6, 26, -4.6, 9.2, 6.8, 9.2, plate), box(-4.7, 27, -4.8, 9.4, 2.2, 0.4, V3(0.08, 0.1, 0.12)),
              box(-9, 20, -3, 5.2, 4, 6, plate), box(3.8, 20, -3, 5.2, 4, 6, plate), box(-4.6, 32.6, -1, 9.2, 0.8, 2, trim)]
    case 2:
        // Hood, scarf over the face and a glowing red monocle; a ragged cloak behind.
        p += [box(-4.5, 26, -4.5, 9, 6.8, 9, cloth, 4), box(-4.3, 24, -4.6, 8.6, 3, 0.6, trim),
              box(1, 28, -4.8, 2.2, 2.2, 0.6, V3(2.2, 0.2, 0.15)), box(-2.6, 28.5, -4.2, 1.5, 1, 0.2, V3(0.1, 0.1, 0.1)),
              box(-4.5, 4, 2.1, 9, 20, 0.8, cloth * 0.9, 4)]
    default:
        // Full helmet with a glowing visor slit, big pauldrons, twin power tanks.
        p += [box(-4.8, 24, -4.8, 9.6, 9, 9.6, plate), box(-3.6, 28, -5, 7.2, 1.4, 0.4, V3(2.1, 1.0, 0.3)),
              box(-10, 19, -3.5, 6, 5.5, 7, plate), box(4, 19, -3.5, 6, 5.5, 7, plate),
              box(-10, 23.5, -3.5, 6, 0.8, 7, trim), box(4, 23.5, -3.5, 6, 0.8, 7, trim),
              box(-3.5, 12, 4.4, 3, 10, 3, trim * 0.8), box(0.5, 12, 4.4, 3, 10, 3, trim * 0.8),
              box(-4.6, 6, -2.6, 9.2, 5, 5.2, plate), box(-4.4, 14, -3, 8.8, 0.8, 0.5, trim)]
    }
    p = p.map(s)
    // The gun, held two-handed in front (lowered while at ease).
    let gun = m.brain?.gun ?? m.variant
    let shoulder = V3(0, 22, 0) * big
    let o = V3(1.5, 20, -9) * big
    for var q in Guns.heldParts(max(0, min(Guns.all.count - 1, gun)), at: o, scale: 0.75 * big) {
        q.pivot = shoulder
        q.rotX = gunTilt
        p.append(q)
    }
    return p
}

func deckGunParts(_ m: Mob) -> [Part] {
    let steel = V3(0.3, 0.32, 0.35), dark = V3(0.14, 0.15, 0.17), hazard = V3(0.85, 0.68, 0.1)
    let pitch = m.brain?.pitch ?? 0
    let charge = m.brain?.charge ?? 0
    let kick = (m.brain?.kick ?? 0) * 7                 // barrels slide back after a salvo
    let eyeGlow = m.aggro ? V3(1.4 + charge, 0.2, 0.15) : V3(0.3, 0.1, 0.1)
    var p: [Part] = [
        box(-20, 0, -20, 40, 5, 40, dark),
        box(-21, 5, -21, 42, 1, 42, hazard),
        box(-16, 6, -14, 32, 16, 28, steel),
        box(-17, 7, -17, 34, 13, 3, steel * 0.9),
        box(-14, 22, -10, 28, 3, 20, steel * 0.85),
        box(-3, 18, -17.4, 6, 2, 0.4, eyeGlow),
        box(-22, 16, -4, 5, 3, 8, dark), box(17, 16, -4, 5, 3, 8, dark),
        box(-22.5, 16.5, -5, 1, 2, 1, V3(0.6, 0.9, 1.1)), box(21.5, 16.5, -5, 1, 2, 1, V3(0.6, 0.9, 1.1)),
    ]
    for x: Float in [-7, 7] {
        p.append(Part(mn: V3(x - 2.5, 11.5, -22), mx: V3(x + 2.5, 16.5, -14), pivot: V3(x, 14, -14), rotX: pitch, color: dark))
        p.append(Part(mn: V3(x - 1.6, 12.4, -62 + kick), mx: V3(x + 1.6, 15.6, -22 + kick), pivot: V3(x, 14, -14), rotX: pitch, color: steel * 0.8))
        p.append(Part(mn: V3(x - 2.3, 11.7, -66 + kick), mx: V3(x + 2.3, 16.3, -60 + kick), pivot: V3(x, 14, -14), rotX: pitch, color: dark))
        if charge > 0 {
            p.append(Part(mn: V3(x - 1, 13, -66.3), mx: V3(x + 1, 15, -65.9), pivot: V3(x, 14, -14), rotX: pitch, color: V3(1.5 + charge, 0.8, 0.2)))
        }
    }
    return p
}
