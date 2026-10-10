import Foundation
import simd

// Horses that ride like a ranch horse in an open-world western (docs/status/horses.md): gaits with momentum and
// speed-limited turning, stamina, a bond that grows with riding and care, nerves (rearing at blasts and monsters), and
// sure footing (no running off cliffs or into lava). Applies to ridden horses, donkeys, mules and the undead horses;
// camels, pigs, magmastriders and llamas keep their own riding (Riding.swift).

enum Gait: Int, Comparable {
    case stand = 0, walk, trot, canter, gallop
    static func < (a: Gait, b: Gait) -> Bool { a.rawValue < b.rawValue }
    var name: String { ["standing", "walk", "trot", "canter", "gallop"][rawValue] }
}

// Per-horse riding state. Only the bond points are saved (MobSave "bxp"); the rest is moment to moment.
final class HorseState {
    var gait: Gait = .stand
    var speed: Float = 0             // b/s along the horse's heading (momentum)
    var stamina: Float = -1          // -1 = not yet set (full)
    var spent = false                // exhausted: no canter / gallop until it recovers to 25 %
    var bondXP: Float = 0
    var rideAccum: Float = 0         // blocks ridden toward the next bond point
    var rear: Float = 0              // s left of a rear (stops; may throw at the end)
    var rearThrow = false
    var spookCool: Float = 0
    var monsterScan: Float = 0
    var patCool: Float = 0, brushCool: Float = 0, feedCool: Float = 0
    var idle: Float = 0              // s the stick has been back in the middle (a spurred gait drops after 0.25 s)
    var refused: Float = 0           // s since the horse last refused a drop (toast once per refusal)
    var spurCount = 0                // spurs taken (HorseTests)
    var stumbles = 0
    var thrown = 0
}

enum HorseFeel {
    static let kinds: Set<MobKind> = [.horse, .donkey, .mule, .skeletonHorse, .zombieHorse]
    static let levelXP: [Float] = [0, 100, 300, 700]
    static let staminaMax: [Float] = [100, 115, 130, 150]
    static let drain: [Float] = [1, 0.9, 0.8, 0.7]
    static let regen: [Float] = [1, 1.15, 1.3, 1.5]
    static let throwChance: [Float] = [0.45, 0.2, 0.05, 0]
    static let accelBase: Float = 3, accelPerTop: Float = 0.4      // b/s^2 = 3 + 0.4 x top speed
    static let brake: Float = 12                                   // b/s^2 with the stick let go
    static let ease: Float = 6                                     // b/s^2 slowing to a lower gait
    static let refuseDrop = 4                                      // blocks: a drop this deep or more is refused
    static let crashSpeed: Float = 11                              // b/s into a wall: a stumble
    static var controlWas = false                                  // the keyboard sprint key last tick (spur = a fresh press)
    // Treats: stamina they give (also bond, at most every 10 s).
    static let treatStamina: [String: Float] = ["sugar": 15, "wheat": 10, "apple": 25, "carrot": 15, "golden_carrot": 50,
                                                "golden_apple": 100, "enchanted_golden_apple": 150, "hay_block": 60]
    static func level(_ xp: Float) -> Int { levelXP.lastIndex { xp >= $0 }.map { $0 + 1 } ?? 1 }
}

extension Mob {
    var gaited: Bool { HorseFeel.kinds.contains(kind) }
    var hs: HorseState {
        if let h = horse { return h }
        let h = HorseState(); horse = h; return h
    }
    var topSpeed: Float { kind == .donkey || kind == .mule ? 7.5 : horseSpeed }
    var bondLevel: Int { HorseFeel.level(horse?.bondXP ?? 0) }
    var staminaMax: Float { HorseFeel.staminaMax[bondLevel - 1] }
    var stamina: Float {
        get { let h = hs; if h.stamina < 0 { h.stamina = staminaMax }; return h.stamina }
        set { hs.stamina = simd_clamp(newValue, 0, staminaMax) }
    }
    // Saddlebags: a tamed horse at bond level 2 carries 9 slots (MountMenu, Boats.packContainer).
    var saddlebags: Bool { gaited && tamed && !chested && bondLevel >= 2 }

    func gaitSpeed(_ g: Gait) -> Float {
        let top = topSpeed
        switch g {
        case .stand: return 0
        case .walk: return simd_clamp(top * 0.25, 1.6, 2.6)
        case .trot: return top * 0.5
        case .canter: return top * 0.75
        case .gallop: return top
        }
    }

    func addBond(_ pts: Float, _ g: Game) {
        let h = hs
        let before = bondLevel
        h.bondXP = max(0, h.bondXP + pts)
        let now = bondLevel
        guard now > before else { return }
        let perk = ["", "", "saddlebags", "steadier nerves", "never throws you"][now]
        g.onToast?("Bond with your horse: level \(now) (\(perk))")
        g.particles.hearts(at: pos + V3(0, height, 0))
    }

    // Ridden, tamed, saddled: gait, turning, stamina, nerves and footing. Sets yaw and the horizontal velocity; the
    // caller (updateRidden) does gravity, the move and the rider. Returns the speed it asked for (b/s, for tests).
    func gaitStep(_ dt: Float, _ g: Game, _ inp: MoveInput) {
        let h = hs
        let lvl = bondLevel
        h.spookCool = max(0, h.spookCool - dt)
        h.patCool = max(0, h.patCool - dt); h.brushCool = max(0, h.brushCool - dt); h.feedCool = max(0, h.feedCool - dt)
        h.refused += dt
        let top = topSpeed
        let flat = V2(vel.x, vel.z)
        let now = simd_length(flat)
        // Turning: quick at a walk, wide arcs at a gallop.
        let steer = g.player.moveYaw ?? g.player.yaw
        var d = steer - yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let rate: Float = 4.5 - 2.9 * min(1, now / max(top, 1))
        yaw += simd_clamp(d, -rate * dt, rate * dt)
        // Gait from the stick and the spurs.
        let push = inp.forward
        if h.stamina < 0 { h.stamina = staminaMax }
        if h.spent && h.stamina > staminaMax * 0.25 { h.spent = false }
        var back = false
        if h.rear > 0 {
            h.gait = .stand
        } else if push > 0.3 {
            h.idle = 0
            let natural: Gait = push >= 0.75 ? .trot : .walk
            if inp.spur {
                h.spurCount += 1
                if h.spent {
                    // Spurring a spent horse: it rears and resents it.
                    rearUp(g, canThrow: false)
                    addBond(-3, g)
                    g.onToast?("Your horse is spent: let it walk to get its wind back")
                } else {
                    h.gait = min(.gallop, Gait(rawValue: max(h.gait, .trot).rawValue + 1) ?? .gallop)
                    stamina -= 4
                    if h.gait == .gallop { g.sfx(.mob(kind, .ambient), 0.7, at: pos) }
                }
            }
            if h.gait <= .trot { h.gait = natural }
            if h.spent && h.gait > .trot { h.gait = .trot }
        } else {
            h.idle += dt
            if push < -0.3 { back = true; h.gait = .stand }
            else if h.idle > 0.25 { h.gait = .stand }
        }
        var target: Float = back ? -1.2 * min(1, -push) : gaitSpeed(h.gait)
        if h.gait == .walk { target *= 0.4 + 0.6 * min(1, (push - 0.3) / 0.45) }
        if !saddled { target = 0 }
        // Stamina: drains at a canter or gallop, refills slower and walking.
        let frac = now / max(top, 1)
        let rateS: Float = frac > 0.85 ? -7 * HorseFeel.drain[lvl - 1]
            : (frac > 0.6 ? -2.5 * HorseFeel.drain[lvl - 1] : (12 - 12 * frac) * HorseFeel.regen[lvl - 1])
        stamina += rateS * dt
        if h.stamina <= 0 && !h.spent { h.spent = true; g.onToast?("Your horse is blown: ease off to a trot") }
        // Nerves: a hostile monster right beside the horse.
        h.monsterScan -= dt
        if h.monsterScan <= 0 {
            h.monsterScan = 0.5
            for m in g.mobs.mobs where m !== self && m.health > 0 && m.kind.hostile && m.kind.spec.behavior != .neutral {
                if simd_length_squared(m.pos - pos) < 9 { spook(g); break }
            }
        }
        if h.rear > 0 {
            h.rear -= dt
            if h.rear <= 0 { h.rear = 0; if h.rearThrow { throwRider(g) } }
        }
        // Sure footing: brake in time for a drop or lava ahead (not in the air, not swimming, not backing up).
        if onGround && target > 0 {
            let look = halfW + 1.2 + h.speed * h.speed / (2 * HorseFeel.brake)
            if let dh = hazardAhead(g.world, maxDist: look) {
                let room = max(0, dh - halfW - 0.35)
                let vmax = sqrtf(2 * HorseFeel.brake * room)
                if vmax < target {
                    target = room < 0.15 ? 0 : vmax
                    if h.speed > vmax { h.speed = vmax }
                    if h.refused > 3 && h.speed < 1.5 && push > 0.3 { g.onToast?("Your horse won't take that drop") }
                    h.refused = 0
                }
            }
        }
        // Momentum: build up, ease down, brake.
        if onGround || inWaterNow(g.world) {
            let accel = HorseFeel.accelBase + HorseFeel.accelPerTop * top
            let k: Float = target > h.speed ? accel : (target > 0.1 ? HorseFeel.ease : HorseFeel.brake)
            if h.rear > 0 { h.speed = max(0, h.speed - 14 * dt) }
            else { h.speed += simd_clamp(target - h.speed, -k * dt, k * dt) }
            if inWaterNow(g.world) { h.speed = min(h.speed, max(2, top * 0.35)) }
            vel.x = forward.x * h.speed
            vel.z = forward.z * h.speed
        }
    }

    func inWaterNow(_ w: World) -> Bool { Blocks.isLiquid(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))) }

    // After the move: crashes and riding bond.
    func gaitAfterMove(_ g: Game, moved: V3, hitWall: Bool, dt: Float) {
        let h = hs
        let along = simd_dot(V3(moved.x, 0, moved.z), forward) / max(dt, 1e-4)
        if hitWall && h.gait == .gallop && h.speed > HorseFeel.crashSpeed && h.speed - along > 5 && h.rear <= 0 {        // head-on, not a graze
            stumble(g)
        } else if hitWall {
            h.speed = max(0, min(h.speed, along))
        }
        if tamed && bond != 0 && bond == g.horseBond {
            h.rideAccum += simd_length(V2(moved.x, moved.z))
            if h.rideAccum >= 12 { h.rideAccum -= 12; addBond(1, g) }
        }
    }

    // The first spot ahead (distance from the horse's centre) where the ground drops `refuseDrop`+ blocks below the
    // ground before it, or is lava / fire. Walls end the search (collision handles them). Water is ground.
    func hazardAhead(_ w: World, maxDist: Float) -> Float? {
        var ground = Int(floor(pos.y + 0.01)) - 1
        var s: Float = halfW + 0.3
        let f = forward
        while s <= maxDist {
            let x = Int(floor(pos.x + f.x * s)), z = Int(floor(pos.z + f.z * s))
            var found: Int?
            var y = ground + 1
            while y >= ground - HorseFeel.refuseDrop + 1 {
                let b = w.block(x, y, z)
                let i = Int(b)
                if Blocks.fluidKind[i] == 2 || Blocks.contactDamage[i] > 0 { return s }
                if Blocks.collide[i] || Blocks.isLiquid(b) { found = y; break }
                y -= 1
            }
            guard let gy = found else { return s }
            if gy > ground + 1 { return nil }
            ground = gy
            s += 0.5
        }
        return nil
    }

    func rearUp(_ g: Game, canThrow: Bool) {
        let h = hs
        h.rear = 1.1
        h.gait = .stand
        h.rearThrow = canThrow && Rand.float(in: 0..<1) < HorseFeel.throwChance[bondLevel - 1]
        if onGround { vel.y = 3.2 }
        g.sfx(.mob(kind, .hurt), 0.9, at: pos)
    }

    // A fright (blast, cannon, someone else's gunshot, a monster beside it): rears, may throw a low-bond rider.
    func spook(_ g: Game) {
        let h = hs
        guard h.spookCool <= 0, h.rear <= 0 else { return }
        h.spookCool = 4
        rearUp(g, canThrow: true)
        g.onToast?(h.rearThrow ? "Your horse rears: \(Prompt.g(.use)) with an empty hand to calm it!" : "Your horse rears!")
    }

    func throwRider(_ g: Game) {
        hs.thrown += 1
        g.dismount()
        g.player.vel = -forward * 3 + V3(0, 4.5, 0)
        if g.survival { g.damage(2, "was thrown from a horse") }
        g.onToast?("Thrown! Pats, brushing and riding build your bond")
    }

    func stumble(_ g: Game) {
        let h = hs
        h.stumbles += 1
        let fast = h.speed
        h.speed = 0
        h.gait = .stand
        stamina -= 25
        health = max(1, health - 2)
        hurt = 0.4
        g.sfx(.mob(kind, .hurt), 1, at: pos)
        if bondLevel == 1 && fast > 12 { throwRider(g) } else { g.onToast?("Your horse stumbles") }
    }
}

extension Game {
    // Every loud noise (CapitalBases.baseNoise): blasts, cannons and gunshots that aren't the rider's own.
    func horseHears(at p: V3, kind: NoiseKind, power: Float) {
        guard let r = riding, r.gaited, r.tamed, r.health > 0 else { return }
        let d = simd_length(p - r.pos)
        switch kind {
        case .gunshot: if d < 12 && simd_length(p - player.pos) > 2.5 { r.spook(self) }
        case .explosion: if d < 6 + power * 3 { r.spook(self) }
        case .cannon: if d < 24 { r.spook(self) }
        }
    }

    // Use while riding a horse: an empty hand pats it, a brush grooms it, a treat feeds it. True when handled.
    func horseUse(_ m: Mob) -> Bool {
        guard m.gaited, m.tamed else { return false }
        let key = Items.key(held.item)
        if held.isEmpty { horsePat(m); return true }
        if key == "brush" { horseBrush(m); return true }
        if HorseFeel.treatStamina[key] != nil { return animalInteract(m) }
        return false
    }

    func horsePat(_ m: Mob) {
        let h = m.hs
        if h.rear > 0 && h.rearThrow { h.rearThrow = false; m.addBond(6, self); onToast?("You calm your horse") }
        if h.patCool <= 0 { h.patCool = 15; m.addBond(4, self) }
        particles.hearts(at: m.pos + V3(0, m.height, 0))
        sfx(.mob(m.kind, .ambient), 0.4, at: m.pos)
    }

    func horseBrush(_ m: Mob) {
        let h = m.hs
        guard h.brushCool <= 0 else { onToast?("Your horse is already groomed"); return }
        h.brushCool = 120
        m.addBond(15, self)
        m.health = min(max(m.spec.health, 30), m.health + 2)
        particles.hearts(at: m.pos + V3(0, m.height, 0))
        damageHeld(1)
        onToast?("You brush your horse")
    }

    // A treat for a tamed horse: stamina, and bond at most every 10 s. False when it needs nothing.
    func horseTreat(_ m: Mob, _ key: String) -> Bool {
        guard m.gaited, m.tamed, let s = HorseFeel.treatStamina[key] else { return false }
        let h = m.hs
        let hungry = m.stamina < m.staminaMax - 1 || h.feedCool <= 0
        guard hungry else { return false }
        m.stamina += s
        if m.stamina > m.staminaMax * 0.25 { h.spent = false }
        if h.feedCool <= 0 { h.feedCool = 10; m.addBond(3, self) }
        return true
    }
}
