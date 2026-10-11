import Foundation
import simd

// Horses, the gap pass (docs/status/cloud-gap-pass.md, area R; docs/status/horses.md "Gap pass"):
//   breeds    five breeds with their own speed, stamina, courage, jump and coats (HorseBreed); every horse has one.
//   names     your horse gets a name when it first bonds; the stable renames it from a list (no typing in VR).
//   taming    a calm-down minigame instead of a dice roll: the wild horse bucks in bursts; sit still through a buck,
//             pat it (use, empty hand) while it settles; steering or patting mid-buck frightens it. Sitting still alone
//             loses ground (each buck takes more than a quiet spell gives back): only pats timed to the quiet spells
//             fill the calm. Calm fills, it's yours; calm runs out, you're thrown.
//   fear      until bonded it fears predators (wolves, bears, big cats, monsters) as well as gunfire; level 3 shrugs
//             off predators, level 4 other people's gunfire.
//   injured   a horse of yours that would die goes down instead: five minutes to bring a Saddle Salve (stable,
//             doctor); left that long, it dies for good.
//   bond      every horse you have ridden remembers you (its own bond kept, its own id); the one you rode last comes
//             when called. Unlocks: tighter turning at each level, at level 3 a rear on command (spur standing
//             still), at level 4 a sliding stop (a gallop stops in half the distance).
//   left      a horse you get off waits where you left it: grazes and wanders a few blocks, never off after you.
//             Called, it paths to you (around walls and rivers, up to 160 blocks); stuck for 6 s, it is brought round
//             behind you out of sight.
//   hooves    hoof sounds by the ground underfoot: hard (stone), hollow (wood), soft (earth), loose (sand, gravel),
//             snow, water; their rhythm follows the gait.

enum HorseBreed: Int, CaseIterable {
    case mustang, sandrunner, mountainPony, draft, saddlebred

    var name: String {
        switch self {
        case .mustang: return "Plains Mustang"
        case .sandrunner: return "Sandrunner"
        case .mountainPony: return "Mountain Pony"
        case .draft: return "Draft Horse"
        case .saddlebred: return "Saddlebred"
        }
    }
    // Speed roll range (variant bits 4-7, 0...15: 4.8 + bits/15 x 11.2 b/s), stamina and jump multipliers, courage
    // (frights: chance to rear at all, and the throw chance multiplier), coats (Animals.horseParts: 0 chestnut,
    // 1 grey, 2 dark bay, 3 dun, 4 black).
    var speedBits: ClosedRange<Int> {
        switch self {
        case .mustang: return 9...14
        case .sandrunner: return 11...15
        case .mountainPony: return 3...8
        case .draft: return 0...5
        case .saddlebred: return 6...12
        }
    }
    var stamina: Float { [1.1, 1.25, 1.3, 1.5, 1.0][rawValue] }          // the saddlebred is the baseline (1, nerve 1)
    var courage: Float { [0.8, 0.45, 0.85, 0.95, 0.7][rawValue] }
    var jump: ClosedRange<Int> { [6...12, 9...15, 3...9, 0...5, 5...11][rawValue] }
    var coats: [Int] { [[0, 3], [1, 4], [3, 2], [2, 4], [0, 1, 2]][rawValue] }
    var price: Int { [3200, 4400, 2400, 2800, 3600][rawValue] }       // the stable's base price (cents)
    var blurb: String {
        switch self {
        case .mustang: return "Fast and hardy"
        case .sandrunner: return "Fastest, long wind, skittish"
        case .mountainPony: return "Slow, sure, tireless"
        case .draft: return "Slow, strong, fearless"
        case .saddlebred: return "Even-tempered all-rounder"
        }
    }
}

enum HorseLife {
    static let names = ["Biscuit", "Dusty", "Juniper", "Maverick", "Pepper", "Sage", "Comet", "Willow", "Rusty", "Clover", "Ember",
                        "Ghost", "Hazel", "Jasper", "Lark", "Mesa", "Nugget", "Outlaw", "Pinto", "Rowan", "Scout", "Thistle",
                        "Bramble", "Cinder", "Duke", "Flint", "Ginger", "Ranger", "Sundance", "Tumbleweed"]
    static let downTime: Float = 300                   // s an injured horse lasts without a reviver
    static let predators: Set<MobKind> = [.wolf, .polarBear, .ocelot]
    static var reviverKey = "saddle_salve"

    // A breed for a horse rolled at spawn (sets its speed, jump and coat bits to the breed's).
    static func roll(_ m: Mob, breed: HorseBreed? = nil) {
        let b = breed ?? HorseBreed.allCases.randomElement() ?? .mustang
        m.breed = b.rawValue
        let coat = b.coats[Rand.int(in: 0..<b.coats.count)]
        // The model's coat is variant % 5 (Animals.horseParts): the low bits are picked so the whole variant lands on it.
        let bits = (Rand.int(in: b.speedBits) << 4) | (Rand.int(in: b.jump) << 8)
        m.variant = bits | ((coat - bits % 5 + 5) % 5)
    }

    // Older horses (no breed saved): the breed whose speed range their speed falls in, nearest first (stable per horse).
    static func infer(_ m: Mob) -> HorseBreed {
        let bits = (m.variant >> 4) & 15
        return HorseBreed.allCases.min { a, b in
            func d(_ r: ClosedRange<Int>) -> Int { bits < r.lowerBound ? r.lowerBound - bits : (bits > r.upperBound ? bits - r.upperBound : 0) }
            return (d(a.speedBits), a.coats.contains(m.variant % 5) ? 0 : 1, a.rawValue) < (d(b.speedBits), b.coats.contains(m.variant % 5) ? 0 : 1, b.rawValue)
        } ?? .mustang
    }

    static func nextName(_ current: String?) -> String {
        guard let c = current, let i = names.firstIndex(of: c) else { return names[0] }
        return names[(i + 1) % names.count]
    }

    // Hoof sound class by the block underfoot: 0 hard, 1 hollow wood, 2 soft earth, 3 loose, 4 snow, 5 water.
    static func surface(_ b: BlockID) -> Int {
        if Blocks.isLiquid(b) { return 5 }
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if k.contains("snow") { return 4 }
        if k.contains("sandstone") { return 0 }
        if k.contains("sand") || k.contains("gravel") || k.contains("soul") { return 3 }
        if k.contains("planks") || k.contains("log") || k.contains("wood") || k.contains("slab") && k.contains("oak") || k.contains("bridge") { return 1 }
        if k.contains("grass") || k.contains("dirt") || k.contains("mud") || k.contains("moss") || k.contains("podzol") || k.contains("mycelium")
            || k.contains("farmland") || k.contains("path") || k.contains("clay") || k.contains("leaves") { return 2 }
        return 0
    }
    static let surfaceNames = ["stone", "wood", "earth", "sand", "snow", "water"]
}

extension Mob {
    var horseBreed: HorseBreed { breed >= 0 ? HorseBreed(rawValue: breed) ?? .mustang : HorseLife.infer(self) }
    var yours: Bool { bond != 0 && tamed }

    // MARK: Taming (the calm-down minigame), from updateRidden while an untamed horse carries the player.

    // Returns false when the rider was thrown.
    func tameStep(_ dt: Float, _ g: Game, _ inp: MoveInput) -> Bool {
        let h = hs
        if h.calm < 0 { h.calm = 20 + Float(min(temper, 60)) / 2; h.buckTime = 0.6; h.bucking = false }
        h.buckTime -= dt
        let still = abs(inp.forward) < 0.3 && abs(inp.strafe) < 0.3
        if h.bucking {
            // Mid-buck: a hop and a twist; sitting still ties it, fighting it frightens it.
            h.calm += (still ? -4 : -22) * dt
            if onGround && Rand.float(in: 0..<1) < dt * 3 { vel.y = 4.5; yaw += Rand.float(in: -0.6...0.6) }
            if h.buckTime <= 0 {
                h.bucking = false; h.buckTime = Rand.float(in: 1.4...2.2)
                if h.calm < 12 {
                    temper = min(100, temper + 5)
                    h.calm = -1
                    g.dismount(); vel.y = 4; g.sfx(.mob(kind, .hurt), 1, at: pos)
                    g.onToast?("Thrown! Sit still through the bucking and pat it when it settles")
                    HorseLife.thrownCount += 1
                    return false
                }
            }
        } else {
            h.calm += (still ? 1 : -2) * dt
            if h.buckTime <= 0 { h.bucking = true; h.buckTime = Rand.float(in: 0.8...1.3); g.sfx(.mob(kind, .hurt), 0.6, at: pos) }
        }
        h.calm = max(0, min(100, h.calm))           // (never below 0: -1 means "not taming")
        if h.calm >= 100 {
            owner = true; persistent = true; h.calm = -1
            g.particles.hearts(at: pos + V3(0, height, 0))
            g.onToast?("Tamed! Put a saddle on to ride it")
            HorseLife.tamedCount += 1
        }
        vel.x *= max(0, 1 - 6 * dt); vel.z *= max(0, 1 - 6 * dt)
        return true
    }

    // A pat during taming: settling, it calms a lot; mid-buck, it frightens it.
    func tamePat(_ g: Game) {
        let h = hs
        guard h.calm >= 0, h.patCool <= 0 else { return }
        h.patCool = 0.8
        if h.bucking { h.calm = max(0, h.calm - 10); g.sfx(.mob(kind, .hurt), 0.4, at: pos) }
        else { h.calm += 15; g.particles.hearts(at: pos + V3(0, height, 0)); g.sfx(.mob(kind, .ambient), 0.5, at: pos) }
    }

    // MARK: Fear of predators (gaitStep's scan): until bonded to level 3.

    // A monster right beside it frightens any horse; predators and monsters within 6 blocks one bonded below level 3.
    func predatorNear(_ g: Game) -> Bool {
        let wary = bondLevel < 3
        for m in g.mobs.mobs where m !== self && m.health > 0 {
            let d2 = simd_length_squared(m.pos - pos)
            guard d2 < 36 else { continue }
            let monster = m.kind.hostile && m.kind.spec.behavior != .neutral
            if monster && d2 < 9 { return true }
            if wary && (monster || HorseLife.predators.contains(m.kind) && !m.tamed) { return true }
        }
        return false
    }

    // MARK: Injured, not dead

    var canGoDown: Bool { gaited && yours && downed <= 0 && health > -1000 }

    func goDown(_ g: Game) {
        downed = HorseLife.downTime
        health = 1
        vel = .zero
        panic = 0
        if g.riding === self { g.dismount() }
        g.sfx(.mob(kind, .death), 0.8, at: pos)
        g.onToast?("\(customName ?? "Your horse") is down! A Saddle Salve within 5 minutes saves it")
        HorseLife.downs += 1
    }

    // Mob.update while down: lies still; time runs out, it dies for good.
    func downedTick(_ dt: Float, _ g: Game) {
        downed -= dt
        vel.x = 0; vel.z = 0
        // It still falls (downed mid-jump, on a ledge that went, in water: it sinks to the bottom).
        let w = g.world
        let x = Int(floor(pos.x)), z = Int(floor(pos.z))
        if !Blocks.collide[Int(w.block(x, Int(floor(pos.y - 0.05)), z))] && pos.y > 1 {
            vel.y = max(vel.y - 25 * dt, Blocks.isLiquid(w.block(x, Int(floor(pos.y)), z)) ? -2 : -40)
            pos.y += vel.y * dt
            if Blocks.collide[Int(w.block(x, Int(floor(pos.y)), z))] { pos.y = floor(pos.y) + 1; vel.y = 0 }
        } else { vel.y = 0 }
        if downed <= 0 {
            downed = 0
            health = 0
            if bond == g.horseBond { g.horseBond = 0 }
            bond = 0                                      // (no "goes down" again on the death sweep)
            g.onToast?("\(customName ?? "Your horse") is gone")
        }
    }

    func revive(_ g: Game) {
        downed = 0
        health = max(spec.health, 30) / 3
        hurt = 0
        g.particles.hearts(at: pos + V3(0, height, 0))
        g.sfx(.mob(kind, .ambient), 1, at: pos)
        g.onToast?("\(customName ?? "Your horse") is back on its feet")
        HorseLife.revived += 1
    }

    // MARK: Left alone

    // Unridden, a horse of yours that isn't called waits where you left it: grazes, and wanders a few blocks.
    func waitWhereLeft(_ dt: Float, _ g: Game) -> Float {
        // A predator near a young bond: it bolts (passive panic), then comes back to where it was left.
        if panic <= 0 && predatorNear(g) { panic = 3; HorseLife.bolted += 1 }
        let here = stayAt ?? pos
        if stayAt == nil { stayAt = pos }
        return stroll(around: here, 5, 0.35)
    }
}

extension HorseLife {
    static var tamedCount = 0, thrownCount = 0, downs = 0, revived = 0, greetings = 0, lastHoof = -1, bagReaches = 0, bolted = 0, broughtRound = 0
}

extension Game {
    // Bonding a horse: it becomes the one that comes when called. Other horses of yours keep their own bond and id
    // (they remember you); a new one gets a name.
    func makeCurrentHorse(_ m: Mob) {
        if m.bond == 0 { m.bond = Float(Rand.int(in: 1...16_000_000)) }
        horseBond = m.bond
        m.persistent = true
        m.stayAt = nil
        if m.customName == nil { m.customName = HorseLife.names[Rand.int(in: 0..<HorseLife.names.count)] }
        onToast?("\(m.customName ?? "This horse") is your horse now: \(Prompt.g(.fly)) calls it")
    }

    // A Saddle Salve used on a downed horse (any of yours, or one lying near): true when used.
    func useReviver(on m: Mob) -> Bool {
        guard m.downed > 0, Items.key(held.item) == HorseLife.reviverKey else { return false }
        consumeHeld()
        m.revive(self)
        return true
    }
}

// Hoof falls by the ground (Snd.hoof): a ringing clop on stone, a hollow knock on wood, a dull thud on earth, a crunch
// on sand and gravel, a soft squeak in snow, a splash in water.
extension HorseLife {
    static func hoof(_ g: inout Synth, surface s: Int, p: Float) -> [Float] {
        switch s {
        case 0:
            return Synth.mix(g.burst(0.06, lp: 3800 * p, hp: 300, attack: 0.0008, decay: 0.012, gain: 1.4),
                             g.modes(0.12, [(1150 * p, 0.5, 0.03), (2350 * p, 0.25, 0.02), (3500 * p, 0.12, 0.015)]))
        case 1:
            return Synth.mix(g.burst(0.07, lp: 2200 * p, hp: 120, attack: 0.001, decay: 0.016, gain: 1.3),
                             g.modes(0.18, [(210 * p, 0.6, 0.07), (470 * p, 0.35, 0.05), (900 * p, 0.12, 0.03)]))
        case 2:
            return Synth.mix(g.burst(0.09, lp: 650 * p, hp: 40, attack: 0.002, decay: 0.03, gain: 1.8),
                             g.grains(3, spread: 0.04, lp: 2500, hp: 600, decay: 0.006, gain: 0.25))
        case 3:
            return Synth.mix(g.burst(0.06, lp: 900 * p, hp: 60, attack: 0.002, decay: 0.02, gain: 1.1),
                             g.grains(14, spread: 0.07, lp: 6000, hp: 1400, decay: 0.004, gain: 0.45))
        case 4:
            return Synth.mix(g.burst(0.08, lp: 1200 * p, hp: 200, attack: 0.004, decay: 0.03, gain: 0.9),
                             g.grains(10, spread: 0.08, lp: 3200, hp: 900, decay: 0.008, gain: 0.4))
        default:
            return Synth.mix(g.burst(0.18, lp: 4200 * p, hp: 500, attack: 0.003, decay: 0.06, gain: 1.1),
                             g.grains(18, spread: 0.14, lp: 7000, hp: 1800, decay: 0.01, gain: 0.35))
        }
    }
}

// VR comfort while riding (QuestControls: the vignette; QuestOptions: Steady Saddle, ViewStep.swift).
enum RideComfort {
    // The comfort vignette on a horse: a little always, a bit more at a gallop, and most while it wheels round or
    // changes speed (a steady run in a straight line is comfortable; turning hard and pulling up are not).
    static func vignette(speed: Float, turnRate: Float, accel: Float) -> Float {
        let run: Float = 0.15 + min(0.2, max(0, speed - 4) / 40)
        return min(0.9, max(run, min(0.8, turnRate * 0.25), max(0, accel - 2) / 16))
    }
}

// The saddlebags in VR: a hand reaching down to the horse's flank, behind the saddle, and gripping opens them
// (QuestControls: the grip at the flank opens MountMenu instead of stepping the hotbar).
extension HorseLife {
    // `hand` in world coordinates; true when it is by either flank behind the rider, below the saddle's top.
    static func reachesSaddlebag(_ horse: Mob, hand: V3) -> Bool {
        let fwd = V3(-sinf(horse.yaw), 0, -cosf(horse.yaw))
        let right = V3(-fwd.z, 0, fwd.x)
        let d = hand - horse.pos
        let along = simd_dot(d, fwd), side = abs(simd_dot(d, right)), up = d.y
        return along > -0.95 && along < 0.15 && side > 0.25 && side < 1.0 && up > 0.45 && up < horse.height * 0.95
    }
}
