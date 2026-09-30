import Foundation
import simd

// Mobs: data-driven specs (size, health, speed, behaviour, drops) + cuboid models built on the CPU
// each frame. Numbers follow the reference game on Normal difficulty.

struct MobVert { var pos: V4; var color: V4; var local: V4 } // pos.w = pattern id, color.a = shade

enum Behavior { case passive, melee, ranged, creeper, spider, enderman, slime, neutral, piglin, ghast, blaze }

enum MobKind: Int, CaseIterable {
    case cow, sheep, chicken, pig, zombie, skeleton, creeper, spider, enderman, slime
    case zombifiedPiglin, piglin, ghast, blaze, magmaCube, witherSkeleton, hoglin, piglinBrute, strider

    struct Spec {
        var name: String
        var halfW: Float
        var height: Float
        var health: Int
        var speed: Float          // walk speed, blocks/s
        var behavior: Behavior
        var attack: Int = 0       // melee damage (half-hearts)
        var burnsInSun = false
        var drops: [(String, Int, Int)] = []
        var xp = 0
        var call: Snd
        var fireImmune = false
        var flying = false
    }

    var spec: Spec {
        switch self {
        case .cow: return Spec(name: "Cow", halfW: 0.45, height: 1.4, health: 10, speed: 1.0, behavior: .passive,
                               drops: [("beef", 1, 3), ("leather", 0, 2)], xp: 2, call: .mobCow)
        case .sheep: return Spec(name: "Sheep", halfW: 0.45, height: 1.3, health: 8, speed: 1.0, behavior: .passive,
                                 drops: [("mutton", 1, 2)], xp: 2, call: .mobSheep)
        case .chicken: return Spec(name: "Chicken", halfW: 0.2, height: 0.7, health: 4, speed: 1.0, behavior: .passive,
                                   drops: [("chicken", 1, 1), ("feather", 0, 2)], xp: 2, call: .mobChicken)
        case .pig: return Spec(name: "Pig", halfW: 0.45, height: 0.9, health: 10, speed: 1.0, behavior: .passive,
                               drops: [("porkchop", 1, 3)], xp: 2, call: .mobPig)
        case .zombie: return Spec(name: "Zombie", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .melee, attack: 3,
                                  burnsInSun: true, drops: [("rotten_flesh", 0, 2)], xp: 5, call: .mobZombie)
        case .skeleton: return Spec(name: "Skeleton", halfW: 0.3, height: 1.99, health: 20, speed: 2.5, behavior: .ranged,
                                    burnsInSun: true, drops: [("bone", 0, 2), ("arrow", 0, 2)], xp: 5, call: .mobSkeleton)
        case .creeper: return Spec(name: "Creeper", halfW: 0.3, height: 1.7, health: 20, speed: 2.5, behavior: .creeper,
                                   drops: [("gunpowder", 0, 2)], xp: 5, call: .creeperHiss)
        case .spider: return Spec(name: "Spider", halfW: 0.7, height: 0.9, health: 16, speed: 3.0, behavior: .spider, attack: 2,
                                  drops: [("string", 0, 2), ("spider_eye", 0, 1)], xp: 5, call: .mobSpider)
        case .enderman: return Spec(name: "Enderman", halfW: 0.3, height: 2.9, health: 40, speed: 3.0, behavior: .enderman, attack: 7,
                                    drops: [("ender_pearl", 0, 1)], xp: 5, call: .mobEnderman)
        case .slime: return Spec(name: "Slime", halfW: 0.26, height: 0.52, health: 1, speed: 2.0, behavior: .slime, attack: 0,
                                 drops: [("slime_ball", 0, 2)], xp: 1, call: .mobSlime)
        case .zombifiedPiglin: return Spec(name: "Zombified Piglin", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .neutral, attack: 8,
                                           drops: [("rotten_flesh", 0, 1), ("gold_nugget", 0, 1)], xp: 5, call: .mobZombPiglin, fireImmune: true)
        case .piglin: return Spec(name: "Piglin", halfW: 0.3, height: 1.95, health: 16, speed: 2.5, behavior: .piglin, attack: 8,
                                  drops: [], xp: 5, call: .mobPiglin)
        case .ghast: return Spec(name: "Ghast", halfW: 2, height: 4, health: 10, speed: 2.0, behavior: .ghast,
                                 drops: [("ghast_tear", 0, 1), ("gunpowder", 0, 2)], xp: 5, call: .mobGhast, fireImmune: true, flying: true)
        case .blaze: return Spec(name: "Blaze", halfW: 0.3, height: 1.8, health: 20, speed: 2.3, behavior: .blaze, attack: 6,
                                 drops: [], xp: 10, call: .mobBlaze, fireImmune: true, flying: true)
        case .magmaCube: return Spec(name: "Magma Cube", halfW: 0.26, height: 0.52, health: 1, speed: 2.4, behavior: .slime, attack: 0,
                                     drops: [], xp: 1, call: .mobSlime, fireImmune: true)
        case .hoglin: return Spec(name: "Hoglin", halfW: 0.7, height: 1.4, health: 40, speed: 2.2, behavior: .melee, attack: 6,
                                  drops: [("porkchop", 2, 4), ("leather", 0, 1)], xp: 5, call: .mobPig)
        case .piglinBrute: return Spec(name: "Piglin Brute", halfW: 0.3, height: 1.95, health: 50, speed: 2.4, behavior: .melee, attack: 13,
                                       drops: [], xp: 20, call: .mobPiglin)
        case .strider: return Spec(name: "Strider", halfW: 0.45, height: 1.7, health: 20, speed: 1.0, behavior: .passive,
                                   drops: [("string", 2, 5)], xp: 2, call: .mobPig, fireImmune: true)
        case .witherSkeleton: return Spec(name: "Wither Skeleton", halfW: 0.35, height: 2.4, health: 20, speed: 2.5, behavior: .melee, attack: 8,
                                          drops: [("coal", 0, 1), ("bone", 0, 2)], xp: 5, call: .mobSkeleton, fireImmune: true)
        }
    }
    var hostile: Bool { spec.behavior != .passive }
    var key: String { spec.name.lowercased().replacingOccurrences(of: " ", with: "_") }
    static func named(_ n: String) -> MobKind? { allCases.first { $0.key == n } }
    var call: Snd { spec.call }
    var name: String { spec.name }
}

final class Mob {
    let kind: MobKind
    let spec: MobKind.Spec
    var pos: V3
    var vel = V3(0, 0, 0)
    var yaw: Float
    var onGround = false
    var health: Int
    var scale: Float = 1            // babies 0.5
    var walkPhase: Float = 0
    var walkAmount: Float = 0
    var moving = false
    var aiTimer: Float
    var panic: Float = 0
    var hurt: Float = 0
    var callTimer: Float
    var attackCooldown: Float = 0
    var fuse: Float = 0             // creeper
    var fire: Float = 0             // seconds left burning
    var fireTick: Float = 0
    var aggro = false               // enderman / spider provoked
    var inLove: Float = 0
    var breedCooldown: Float = 0
    var age: Float = 0              // babies grow up at 1200 s
    var baby = false
    var sheared = false
    var woolColor = "white"
    var eggTimer = Float.random(in: 300...600)
    var killedByPlayer = false
    var slimeSize = 1

    var sized: Bool { kind == .slime || kind == .magmaCube }
    var halfW: Float { spec.halfW * (sized ? Float(slimeSize) : scale) }
    var height: Float { spec.height * (sized ? Float(slimeSize) : scale) }
    var admire: Float = 0           // piglin: seconds left inspecting a gold ingot before bartering
    var flyTarget: V3?              // ghast / blaze hover target
    var volley = 0                  // blaze: fireballs left in the current burst
    var persistent = false          // structure mobs never despawn at random

    init(_ kind: MobKind, at p: V3) {
        self.kind = kind
        spec = kind.spec
        pos = p
        yaw = Float.random(in: 0..<(2 * .pi))
        health = kind.spec.health
        aiTimer = Float.random(in: 0.5...3)
        callTimer = Float.random(in: 6...20)
        if kind == .sheep {
            let r = Float.random(in: 0..<1)
            woolColor = r < 0.81836 ? "white" : (r < 0.86836 ? "black" : (r < 0.91836 ? "gray" : (r < 0.96836 ? "light_gray" : (r < 0.99836 ? "brown" : "pink"))))
        }
    }

    func makeSlime(size: Int) {
        slimeSize = size
        health = size * size
    }

    // Anger this mob and every zombified piglin nearby at the player.
    func provoke(_ g: Game) {
        aggro = true
        if kind == .zombifiedPiglin {
            for o in g.mobs.mobs where o.kind == .zombifiedPiglin && simd_length(o.pos - pos) < 20 { o.aggro = true }
        }
    }

    var forward: V3 { V3(-sinf(yaw), 0, -cosf(yaw)) }
    var eye: V3 { pos + V3(0, height * 0.85, 0) }

    func intersects(_ b: IVec3) -> Bool {
        let bx = Float(b.x), by = Float(b.y), bz = Float(b.z)
        return pos.x + halfW > bx && pos.x - halfW < bx + 1 && pos.y + height > by && pos.y < by + 1
            && pos.z + halfW > bz && pos.z - halfW < bz + 1
    }

    private func solid(_ x: Float, _ y: Float, _ z: Float, _ w: World) -> Bool {
        Blocks.collide[Int(w.block(Int(floor(x)), Int(floor(y)), Int(floor(z))))]
    }

    func face(_ p: V3) {
        let d = V2(p.x - pos.x, p.z - pos.z)
        if simd_length(d) > 0.01 { yaw = atan2f(-d.x, -d.y) }
    }

    // MARK: Update

    func update(_ dt: Float, game g: Game) {
        let w = g.world
        guard w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) else { return }
        hurt = max(0, hurt - dt)
        panic = max(0, panic - dt)
        callTimer -= dt
        aiTimer -= dt
        attackCooldown -= dt
        inLove = max(0, inLove - dt)
        breedCooldown = max(0, breedCooldown - dt)
        if baby { age += dt; if age >= 1200 { baby = false; scale = 1 } }

        let feetBlock = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))
        let inWater = Blocks.isLiquid(feetBlock)

        // Undead burn in daylight under open sky.
        if spec.burnsInSun && !inWater && g.dim.dim.hasSky && g.daylight > 0.6 {
            let l = w.lightAt(Int(floor(pos.x)), Int(floor(pos.y + height)), Int(floor(pos.z)))
            if l.sky >= 15 { fire = max(fire, 8) }
        }
        if inWater && Blocks.fluidKind[Int(feetBlock)] == 1 { fire = 0 }
        if spec.fireImmune { fire = 0 }
        let contact = spec.fireImmune ? 0 : Blocks.contactDamage[Int(feetBlock)]
        if contact > 0 && kind != .slime {
            if Blocks.fluidKind[Int(feetBlock)] == 2 || feetBlock == FIRE { fire = max(fire, 8) }
            if attackCooldown < -0.5 { health -= Int(contact); hurt = 0.3; attackCooldown = 0 }
        }
        if fire > 0 {
            fire -= dt
            fireTick += dt
            if fireTick >= 1 { fireTick = 0; health -= 1; hurt = 0.3 }
        }

        let player = g.player.pos
        let toPlayer = player - pos
        let dist = simd_length(toPlayer)
        let canTarget = g.survival && g.alive && dist < 24
        var speed: Float = 0

        switch spec.behavior {
        case .passive:
            // Follow a player holding breeding food; seek a mate when in love.
            if let food = MobManager.breedFood[kind], dist < 8, food.contains(Items.key(g.held.item)), !baby {
                face(player); moving = dist > 2; speed = dist > 2 ? spec.speed : 0
            } else if inLove > 0, let mate = g.mobs.mobs.first(where: { $0 !== self && $0.kind == kind && $0.inLove > 0 && simd_length($0.pos - pos) < 8 }) {
                face(mate.pos)
                speed = simd_length(mate.pos - pos) > 1.2 ? spec.speed : 0
            } else {
                wander()
                speed = moving ? (panic > 0 ? (kind == .chicken ? 2.4 : 2.8) : spec.speed) : 0
            }
            if kind == .chicken && !baby {
                eggTimer -= dt
                if eggTimer <= 0 { eggTimer = Float.random(in: 300...600); g.drops.spawn(ItemStack(Items.id("egg"), 1), at: pos + V3(0, 0.3, 0)) }
            }
        case .neutral, .piglin:
            // Zombified piglins only fight back; piglins attack players not wearing gold armor.
            let goldWorn = g.inventory.armor.slots.contains { !$0.isEmpty && Items.key($0.item).hasPrefix("golden_") }
            let angry = aggro || (spec.behavior == .piglin && !goldWorn && dist < 12 && admire <= 0)
            if admire > 0 {
                admire -= dt
                speed = 0
                if admire <= 0 { g.barter(self) }
            } else if canTarget && angry {
                face(player)
                speed = spec.speed * 1.2
                if dist < halfW + 1.3 && abs(toPlayer.y) < 2 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by \(spec.name)")
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .ghast:
            // Drifts around; shoots an explosive fireball at a visible player within 64 blocks every 3 s.
            if flyTarget == nil || aiTimer <= 0 || simd_length(flyTarget! - pos) < 2 {
                aiTimer = Float.random(in: 3...7)
                flyTarget = pos + V3(Float.random(in: -16...16), Float.random(in: -8...8), Float.random(in: -16...16))
            }
            if canTargetFar(g, dist, 64) && w.canSee(eye, g.player.eye) {
                face(player)
                attackCooldown -= 0
                if attackCooldown <= 0 {
                    attackCooldown = 3
                    let from = pos + V3(0, height * 0.5, 0) + forward * 2.2
                    g.projectiles.fireball(from: from, dir: simd_normalize(g.player.eye - from), big: true, byPlayer: false)
                    g.sfx(.fireball, 1.2, at: from)
                }
            } else {
                let d = flyTarget! - pos
                yaw = atan2f(-d.x, -d.z)
            }
            speed = 0
            let d = flyTarget! - pos
            let l = simd_length(d)
            if l > 0.1 { vel += (d / l * spec.speed - vel) * min(1, dt * 1.5) }
        case .blaze:
            // Hovers a little above the player; bursts of three small fireballs.
            let hover = canTargetFar(g, dist, 48) ? player.y + 2.5 : pos.y + Float.random(in: -1...1)
            vel.y += ((hover - pos.y) * 1.5 - vel.y) * min(1, dt * 2)
            if canTargetFar(g, dist, 48) && w.canSee(eye, g.player.eye) {
                face(player)
                speed = dist > 6 ? spec.speed : 0
                if dist < 1.8 && attackCooldown <= 0 && volley == 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Blaze")
                } else if attackCooldown <= 0 {
                    if volley == 0 { volley = 3 }
                    let from = eye + forward * 0.5
                    var dir = simd_normalize(g.player.eye - V3(0, 0.4, 0) - from)
                    let spread = sqrtf(dist) * 0.02
                    dir = simd_normalize(dir + V3(Float.random(in: -spread...spread), 0, Float.random(in: -spread...spread)))
                    g.projectiles.fireball(from: from, dir: dir, big: false, byPlayer: false)
                    g.sfx(.fireball, 0.6, at: from)
                    volley -= 1
                    attackCooldown = volley > 0 ? 0.3 : 3
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0; volley = 0 }
            if Float.random(in: 0..<1) < dt * 6 { g.particles.smoke(at: pos + V3(Float.random(in: -0.4...0.4), Float.random(in: 0.2...1.4), Float.random(in: -0.4...0.4))) }
        case .melee, .spider:
            let l = w.lightAt(Int(floor(pos.x)), Int(floor(pos.y + 0.5)), Int(floor(pos.z)))
            let hostileNow = spec.behavior == .melee || aggro || Float(l.sky) * g.daylight < 4.8
            if canTarget && hostileNow {
                face(player)
                speed = spec.speed * (baby ? 1.5 : 1)
                let reach = halfW + 1.1
                if dist < reach + 0.2 && abs(toPlayer.y) < 2 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by \(spec.name)")
                    if kind == .witherSkeleton { g.witherTime = 10; g.witherTick = min(g.witherTick, 2) }
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .ranged:
            if canTarget && w.canSee(eye, g.player.eye) {
                face(player)
                speed = dist > 10 ? spec.speed : (dist < 5 ? -spec.speed * 0.6 : 0)
                if attackCooldown <= 0 && dist < 16 {
                    attackCooldown = Float.random(in: 1.5...2.5)
                    let target = g.player.eye - V3(0, 0.3, 0)
                    var d = target - eye
                    let horiz = simd_length(V2(d.x, d.z))
                    d.y += horiz * 0.2
                    g.projectiles.shoot(from: eye + forward * 0.3, dir: simd_normalize(d), speed: 32 + Float.random(in: -3...3), fromPlayer: false, damage: 2)
                    g.sfx(.bow, 0.7, at: pos)
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .creeper:
            if canTarget {
                face(player)
                if dist < 3 {
                    if fuse == 0 { g.sfx(.creeperHiss, 1, at: pos) }
                    fuse += dt
                    speed = 0
                } else {
                    fuse = max(0, fuse - dt)
                    speed = spec.speed
                }
                if fuse >= 1.5 {
                    Explosion.explode(at: pos + V3(0, 0.8, 0), power: 3, game: g)
                    health = -1000
                    return
                }
            } else { fuse = max(0, fuse - dt); wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .enderman:
            // Provoked by being looked at (in the face) or hit; teleports away from water.
            if !aggro && canTarget && dist < 64 {
                let head = pos + V3(0, height - 0.3, 0)
                let toHead = simd_normalize(head - g.player.eye)
                if simd_dot(g.player.look, toHead) > 0.99 && w.canSee(g.player.eye, head) { aggro = true; g.sfx(.mobEnderman, 1, at: pos) }
            }
            if inWater { teleport(w) }
            if aggro && canTarget {
                face(player)
                speed = spec.speed * 2
                if dist < 1.6 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Enderman")
                }
            } else { wander(); speed = moving ? spec.speed * 0.4 : 0 }
        case .slime:
            if onGround && aiTimer <= 0 {
                aiTimer = Float.random(in: 1...2)
                if canTarget { face(player) } else { yaw += Float.random(in: -1.5...1.5) }
                vel.y = kind == .magmaCube ? 7 + Float(slimeSize) * 0.8 : 7
                vel.x = forward.x * spec.speed * 1.5
                vel.z = forward.z * spec.speed * 1.5
                g.sfx(.mobSlime, 0.5, at: pos)
            }
            if canTarget && (slimeSize > 1 || kind == .magmaCube) && dist < halfW + 0.9 && attackCooldown <= 0 {
                attackCooldown = 1
                let dmg = kind == .magmaCube ? [0, 3, 4, 0, 6][min(4, slimeSize)] : (slimeSize == 4 ? 4 : 2)
                g.hurtPlayer(dmg, from: pos, cause: "was slain by \(spec.name)")
            }
        }

        // Passive mobs avoid drops and water while calmly wandering.
        if spec.behavior == .passive && speed > 0 && onGround && panic <= 0 {
            let a = pos + forward * (halfW + 0.45)
            let wet = Blocks.isLiquid(w.block(Int(floor(a.x)), Int(floor(pos.y - 0.5)), Int(floor(a.z))))
            let drop = !solid(a.x, pos.y - 0.5, a.z, w) && !solid(a.x, pos.y - 1.5, a.z, w) && !solid(a.x, pos.y - 2.5, a.z, w)
            if wet || drop { yaw += .pi * Float.random(in: 0.6...1.4); speed = 0; moving = false; aiTimer = Float.random(in: 1...3) }
        }

        if spec.flying {
            if kind == .blaze && speed != 0 {
                let target = forward * speed
                vel.x += (target.x - vel.x) * min(1, dt * 4)
                vel.z += (target.z - vel.z) * min(1, dt * 4)
            }
            if kind == .blaze && speed == 0 { vel.x *= expf(-3 * dt); vel.z *= expf(-3 * dt) }
            let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: false)
            if hit.x { vel.x = 0; flyTarget = nil }
            if hit.y { vel.y = 0; flyTarget = nil }
            if hit.z { vel.z = 0; flyTarget = nil }
            onGround = false
            walkPhase += dt * 3
            return
        }
        if spec.behavior != .slime || onGround {
            let target = forward * speed
            let k = 1 - expf(-(onGround ? 12 : 3) * dt)
            vel.x += (target.x - vel.x) * k
            vel.z += (target.z - vel.z) * k
        }
        if kind == .strider && Blocks.fluidKind[Int(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.3)), Int(floor(pos.z))))] == 2 {
            vel.y = 2          // striders stand on lava
        } else if inWater {
            vel.y += 18 * dt
            vel.y = min(vel.y, 1.6)
            vel.y *= expf(-2 * dt)
        } else {
            vel.y -= 28 * dt
            if kind == .chicken { vel.y = max(vel.y, -3.5) }
            vel.y = max(vel.y, -40)
        }

        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0.6, onGround: onGround)
        var landed = false, bumped = false
        if hit.y { if vel.y < 0 { landed = true }; vel.y = 0 }
        if hit.x { vel.x = 0; bumped = true }
        if hit.z { vel.z = 0; bumped = true }
        onGround = landed || (vel.y <= 0 && collides(pos - V3(0, 0.06, 0), w))
        if bumped && speed != 0 {
            if kind == .spider { vel.y = 3.5 }                            // climbs walls
            else if onGround && spec.behavior != .slime { vel.y = 7.4 }  // hop up one block
        }
        if pos.y < -10 { health = 0 }

        let hs = simd_length(V2(vel.x, vel.z))
        walkPhase += hs * dt * 5.5
        walkAmount += (min(1, hs / 1.2) - walkAmount) * min(1, dt * 8)
    }

    func collides(_ p: V3, _ w: World) -> Bool {
        let hw = halfW
        return w.collides(V3(p.x - hw, p.y, p.z - hw), V3(p.x + hw, p.y + height, p.z + hw))
    }

    private func canTargetFar(_ g: Game, _ dist: Float, _ range: Float) -> Bool {
        g.survival && g.alive && dist < range
    }

    private func wander() {
        if panic > 0 {
            moving = true
            if aiTimer <= 0 { yaw += Float.random(in: -1.2...1.2); aiTimer = 0.6 }
        } else if aiTimer <= 0 {
            moving.toggle()
            if moving { yaw += Float.random(in: -2...2); aiTimer = Float.random(in: 1.5...4) }
            else { aiTimer = Float.random(in: 2...7) }
        }
    }

    func teleport(_ w: World) {
        for _ in 0..<16 {
            let x = Int(floor(pos.x)) + Int.random(in: -16...16), z = Int(floor(pos.z)) + Int.random(in: -16...16)
            let top = w.topY(x, z)
            if top < 1 { continue }
            if Blocks.isLiquid(w.block(x, top, z)) { continue }
            pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
            vel = .zero
            return
        }
    }

    func hit(from src: V3, damage: Int, knockback: Float = 1) {
        health -= damage
        hurt = 0.4
        if spec.behavior == .passive { panic = 5; aiTimer = 0 }
        aggro = true
        admire = 0
        if spec.flying { vel += V3(0, 1, 0); return }
        if kind == .enderman && Float.random(in: 0..<1) < 0.5 { return }
        var away = pos - src
        away.y = 0
        let l = simd_length(away)
        away = l > 0.01 ? away / l : forward
        vel += away * 5.5 * knockback + V3(0, 5, 0) * min(1, knockback)
    }

    // Ray vs AABB; returns the entry distance.
    func rayHit(_ o: V3, _ d: V3, maxDist: Float) -> Float? {
        let mn = V3(pos.x - halfW, pos.y, pos.z - halfW)
        let mx = V3(pos.x + halfW, pos.y + height, pos.z + halfW)
        guard let h = World.rayBox(o, d, mn, mx), h.0 <= maxDist else { return nil }
        return h.0
    }
}

// MARK: Models

private struct Part {
    var mn: V3, mx: V3       // model-space box in pixels (1/16 block); model faces -Z
    var pivot: V3 = .zero
    var rotX: Float = 0
    var rotZ: Float = 0
    var color: V3
    var pattern: Float = 0   // 0 plain, 1 cow patches, 2 wool, 3 feathers, 4 mottled, 5 bone
}

private func box(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float = 0) -> Part {
    Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
}

private func parts(_ m: Mob) -> [Part] {
    let swing = sinf(m.walkPhase) * 0.7 * m.walkAmount
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3, _ pat: Float = 0) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c, pattern: pat)
    }
    let black = V3(0.06, 0.06, 0.06)
    func eyes(_ y: Float, _ z: Float, _ sep: Float, _ size: Float = 1.2, _ c: V3 = V3(0.06, 0.06, 0.06)) -> [Part] {
        [Part(mn: V3(-sep - size, y, z - 0.2), mx: V3(-sep, y + size, z), color: c),
         Part(mn: V3(sep, y, z - 0.2), mx: V3(sep + size, y + size, z), color: c)]
    }
    switch m.kind {
    case .cow:
        let hide = V3(0.36, 0.24, 0.16)
        return [
            Part(mn: V3(-6, 12, -9), mx: V3(6, 22, 9), color: hide, pattern: 1),
            Part(mn: V3(-4, 15, -15), mx: V3(4, 23, -9), pivot: V3(0, 19, -9), color: hide, pattern: 1),
            Part(mn: V3(-2.5, 15.5, -15.6), mx: V3(2.5, 18.5, -15), color: V3(0.82, 0.6, 0.55)),
            box(-5, 21, -13, 1, 3, 1, V3(0.85, 0.82, 0.72)), box(4, 21, -13, 1, 3, 1, V3(0.85, 0.82, 0.72)),
            leg(-3.5, -6, 4, 12, 1, hide, 1), leg(3.5, -6, 4, 12, -1, hide, 1),
            leg(-3.5, 6, 4, 12, -1, hide, 1), leg(3.5, 6, 4, 12, 1, hide, 1),
        ] + eyes(20, -15, 1.8)
    case .sheep:
        let wc = TextureGen.hex(BlockRegistry.colorHex[m.woolColor] ?? 0xE9ECEC)
        let wool = V3(wc.x, wc.y, wc.z), skin = V3(0.72, 0.62, 0.52)
        var p = [
            Part(mn: V3(-3, 15, -14), mx: V3(3, 21, -7), pivot: V3(0, 18, -7), color: skin),
            leg(-3, -5, 3.5, 12, 1, skin), leg(3, -5, 3.5, 12, -1, skin),
            leg(-3, 5, 3.5, 12, -1, skin), leg(3, 5, 3.5, 12, 1, skin),
        ] + eyes(18, -14, 1.2)
        if m.sheared { p.append(box(-4.5, 12, -7, 9, 8, 14, skin)) }
        else { p.append(box(-6, 11, -8, 12, 11, 16, wool, 2)); p.append(box(-3.5, 19.5, -12.5, 7, 2.5, 5.5, wool, 2)) }
        return p
    case .chicken:
        let white = V3(0.95, 0.94, 0.9), orange = V3(0.95, 0.6, 0.15)
        let flap: Float = m.onGround ? 0 : sinf(m.walkPhase * 6 + m.hurt * 30) * 0.9
        return [
            box(-3, 5, -4, 6, 6, 8, white, 3),
            Part(mn: V3(-2, 9, -7), mx: V3(2, 15, -4), pivot: V3(0, 11, -4), color: white, pattern: 3),
            box(-2, 11.5, -9, 4, 1.5, 2, orange),
            box(-1, 9.5, -8, 2, 2, 1, V3(0.85, 0.12, 0.1)),
            Part(mn: V3(-4, 6, -3), mx: V3(-3, 10, 3), pivot: V3(-3, 10, 0), rotZ: -flap, color: white, pattern: 3),
            Part(mn: V3(3, 6, -3), mx: V3(4, 10, 3), pivot: V3(3, 10, 0), rotZ: flap, color: white, pattern: 3),
            leg(-1.5, 0.5, 1, 5, 1, orange), leg(1.5, 0.5, 1, 5, -1, orange),
        ] + eyes(13, -7, 1.2, 1)
    case .pig:
        let pink = V3(0.94, 0.62, 0.6)
        return [
            box(-5, 6, -8, 10, 8, 16, pink, 4),
            Part(mn: V3(-4, 8, -15), mx: V3(4, 16, -7), pivot: V3(0, 12, -7), color: pink, pattern: 4),
            box(-2, 9, -16, 4, 3, 1, V3(0.98, 0.72, 0.7)),
            box(-1.2, 10, -16.2, 0.8, 1, 0.3, V3(0.4, 0.2, 0.2)), box(0.4, 10, -16.2, 0.8, 1, 0.3, V3(0.4, 0.2, 0.2)),
            leg(-3, -5, 4, 6, 1, pink), leg(3, -5, 4, 6, -1, pink), leg(-3, 5, 4, 6, -1, pink), leg(3, 5, 4, 6, 1, pink),
        ] + eyes(13, -15, 2)
    case .zombie, .skeleton, .enderman:
        let sk = m.kind == .skeleton, en = m.kind == .enderman
        let skin = sk ? V3(0.78, 0.78, 0.76) : (en ? V3(0.08, 0.06, 0.1) : V3(0.36, 0.55, 0.3))
        let shirt = sk || en ? skin : V3(0.15, 0.55, 0.58)
        let pants = sk || en ? skin : V3(0.25, 0.25, 0.55)
        let limb: Float = sk || en ? 2 : 4
        let legH: Float = en ? 30 : 12
        let armLen: Float = en ? 30 : 12
        let bodyY = legH
        let armFwd: Float = m.kind == .zombie || (en && m.aggro) ? -1.45 : 0
        let armAngle = armFwd + (armFwd == 0 ? swing : 0)
        let pat: Float = sk ? 5 : 4
        let armC = sk || en ? skin : shirt
        var p: [Part] = [
            Part(mn: V3(-limb - 0.01, 0, -limb / 2), mx: V3(-0.01, legH, limb / 2), pivot: V3(-limb / 2, legH, 0), rotX: swing, color: pants, pattern: pat),
            Part(mn: V3(0.01, 0, -limb / 2), mx: V3(limb + 0.01, legH, limb / 2), pivot: V3(limb / 2, legH, 0), rotX: -swing, color: pants, pattern: pat),
            box(-4, bodyY, -2, 8, 12, 4, shirt, pat),
            Part(mn: V3(-4 - limb, bodyY + 12 - armLen, -limb / 2), mx: V3(-4, bodyY + 12, limb / 2), pivot: V3(-4 - limb / 2, bodyY + 10, 0), rotX: armAngle, color: armC, pattern: pat),
            Part(mn: V3(4, bodyY + 12 - armLen, -limb / 2), mx: V3(4 + limb, bodyY + 12, limb / 2), pivot: V3(4 + limb / 2, bodyY + 10, 0), rotX: armFwd == 0 ? -armAngle : armAngle, color: armC, pattern: pat),
            box(-4, bodyY + 12, -4, 8, 8, 8, skin, pat),
        ]
        let hy = bodyY + 12
        if en {
            p += [box(-3, hy + 3.5, -4.2, 2.2, 1, 0.3, V3(0.85, 0.3, 0.95)), box(0.8, hy + 3.5, -4.2, 2.2, 1, 0.3, V3(0.85, 0.3, 0.95))]
        } else {
            p += eyes(hy + 3.5, -4, 1, 1.5, sk ? V3(0.15, 0.15, 0.15) : black)
            if sk { p.append(box(-2, hy + 1, -4.1, 4, 1, 0.2, V3(0.2, 0.2, 0.2))) }
        }
        return p
    case .creeper:
        let g = V3(0.35, 0.72, 0.3)
        let pulse: Float = m.fuse > 0 ? 1 + 0.15 * sinf(m.fuse * 30) : 1
        let white = m.fuse > 0 && Int(m.fuse * 8) % 2 == 0
        let c = white ? V3(1, 1, 1) : g
        let s = pulse
        return [
            box(-4 * s, 6, -2 * s, 8 * s, 12, 4 * s, c, 4),
            box(-4 * s, 18, -4 * s, 8 * s, 8, 8 * s, c, 4),
            box(-2.5, 22, -4.2 * s, 2, 2, 0.3, black), box(0.5, 22, -4.2 * s, 2, 2, 0.3, black),
            box(-1, 19, -4.2 * s, 2, 3, 0.3, black), box(-2, 19, -4.2 * s, 1, 2, 0.3, black), box(1, 19, -4.2 * s, 1, 2, 0.3, black),
            leg(-2, -4, 4, 6, 1, c, 4), leg(2, -4, 4, 6, -1, c, 4), leg(-2, 4, 4, 6, -1, c, 4), leg(2, 4, 4, 6, 1, c, 4),
        ]
    case .spider:
        let body = V3(0.2, 0.17, 0.15)
        var p: [Part] = [
            box(-5, 4, 0, 10, 8, 12, body, 4),
            box(-3, 5, -4, 6, 6, 4, body, 4),
            box(-4, 4, -12, 8, 8, 8, body, 4),
            box(-3, 8, -12.2, 1.5, 1.5, 0.3, V3(0.9, 0.1, 0.1)), box(1.5, 8, -12.2, 1.5, 1.5, 0.3, V3(0.9, 0.1, 0.1)),
            box(-1, 9.5, -12.2, 2, 1, 0.3, V3(0.9, 0.1, 0.1)),
        ]
        for i in 0..<4 {
            let z = -3 + Float(i) * 2
            let wiggle = sinf(m.walkPhase * 2 + Float(i)) * 0.3 * m.walkAmount
            p.append(Part(mn: V3(3, 7, z - 1), mx: V3(18, 9, z + 1), pivot: V3(3, 8, z), rotX: wiggle, rotZ: -0.5, color: body))
            p.append(Part(mn: V3(-18, 7, z - 1), mx: V3(-3, 9, z + 1), pivot: V3(-3, 8, z), rotX: -wiggle, rotZ: 0.5, color: body))
        }
        return p
    case .hoglin:
        let hide = V3(0.62, 0.42, 0.34), mane = V3(0.85, 0.65, 0.45)
        return [
            box(-8, 12, -12, 16, 14, 26, hide, 4),
            box(-2, 26, -12, 4, 4, 16, mane, 2),                                             // mane
            Part(mn: V3(-7, 9, -28), mx: V3(7, 21, -12), pivot: V3(0, 18, -12), rotX: 0.35, color: hide, pattern: 4),
            box(-8, 16, -27, 2, 7, 2, V3(0.95, 0.92, 0.82)), box(6, 16, -27, 2, 7, 2, V3(0.95, 0.92, 0.82)), // tusks
            box(-9, 21, -16, 2, 2, 5, hide), box(7, 21, -16, 2, 2, 5, hide),
            leg(-5, -8, 6, 12, 1, hide, 4), leg(5, -8, 6, 12, -1, hide, 4), leg(-5, 9, 6, 12, -1, hide, 4), leg(5, 9, 6, 12, 1, hide, 4),
        ] + eyes(18, -26, 3)
    case .strider:
        let red = V3(0.62, 0.16, 0.14)
        var p: [Part] = [
            box(-8, 16, -8, 16, 14, 16, red, 4),
            leg(-4, 0, 4, 16, 1, V3(0.45, 0.12, 0.1)), leg(4, 0, 4, 16, -1, V3(0.45, 0.12, 0.1)),
        ] + eyes(24, -8, 2, 2, V3(0.15, 0.05, 0.05))
        for i in 0..<6 {
            let x = -7 + Float(i) * 2.8
            p.append(Part(mn: V3(x, 30, -1), mx: V3(x + 1, 38, 1), pivot: V3(x, 30, 0), rotZ: sinf(m.walkPhase + Float(i)) * 0.3, color: V3(0.75, 0.6, 0.5)))
        }
        return p
    case .zombifiedPiglin, .piglin, .piglinBrute:
        let zp = m.kind == .zombifiedPiglin
        let skin = V3(0.93, 0.6, 0.55), rot = V3(0.45, 0.62, 0.35)
        let tunic = zp ? V3(0.55, 0.45, 0.35) : (m.kind == .piglinBrute ? V3(0.25, 0.22, 0.24) : V3(0.5, 0.33, 0.18))
        let arm = zp ? rot : skin
        let armFwd: Float = m.aggro || zp && m.aggro ? -1.3 : 0
        var p: [Part] = [
            Part(mn: V3(-4.01, 0, -2), mx: V3(-0.01, 12, 2), pivot: V3(-2, 12, 0), rotX: swing, color: V3(0.35, 0.25, 0.15), pattern: 4),
            Part(mn: V3(0.01, 0, -2), mx: V3(4.01, 12, 2), pivot: V3(2, 12, 0), rotX: -swing, color: V3(0.35, 0.25, 0.15), pattern: 4),
            box(-4, 12, -2, 8, 12, 4, tunic, 4),
            Part(mn: V3(-8, 12, -2), mx: V3(-4, 24, 2), pivot: V3(-6, 22, 0), rotX: armFwd + swing, color: arm, pattern: 4),
            Part(mn: V3(4, 12, -2), mx: V3(8, 24, 2), pivot: V3(6, 22, 0), rotX: armFwd - swing, color: skin, pattern: 4),
            box(-5, 24, -4, 10, 8, 8, zp ? V3(0.85, 0.55, 0.5) : skin, 4),
            box(-2, 25, -5, 4, 3, 1, V3(0.98, 0.7, 0.65)),
            box(-1.4, 26, -5.2, 0.8, 1, 0.3, V3(0.3, 0.15, 0.15)), box(0.6, 26, -5.2, 0.8, 1, 0.3, V3(0.3, 0.15, 0.15)),
            box(-6, 27, -1, 1, 4, 3, skin), box(5, 27, -1, 1, 4, 3, skin),        // ears
            box(-3, 23.5, -5.1, 1, 1.5, 0.3, V3(0.95, 0.9, 0.8)), box(2, 23.5, -5.1, 1, 1.5, 0.3, V3(0.95, 0.9, 0.8)), // tusks
            // Golden sword in the right hand.
            Part(mn: V3(5.5, 11, -12), mx: V3(6.5, 12.5, 0), pivot: V3(6, 22, 0), rotX: armFwd - swing, color: V3(0.98, 0.84, 0.3)),
        ] + eyes(29, -4, 1, 1.5, zp ? V3(0.8, 0.8, 0.3) : black)
        if zp { p.append(box(-5.1, 27, -3, 0.3, 3, 4, V3(0.8, 0.85, 0.8), 5)) }     // exposed skull patch
        return p
    case .ghast:
        // 16px cube scaled 4x, nine tentacles; the face opens its eyes and mouth while shooting.
        let white = V3(0.94, 0.94, 0.94), grey = V3(0.55, 0.55, 0.55)
        let firing = m.attackCooldown > 2.4
        var p: [Part] = [box(-32, 16, -32, 64, 64, 64, white, 4)]
        p += [box(-20, 52, -32.4, 12, firing ? 8 : 3, 0.3, firing ? V3(0.8, 0.1, 0.1) : grey),
              box(8, 52, -32.4, 12, firing ? 8 : 3, 0.3, firing ? V3(0.8, 0.1, 0.1) : grey),
              box(-12, 30, -32.4, 24, firing ? 12 : 4, 0.3, firing ? V3(0.15, 0.15, 0.15) : grey)]
        for i in 0..<9 {
            let tx = Float(i % 3 - 1) * 20, tz = Float(i / 3 - 1) * 20
            let len: Float = 28 + Float((i * 7) % 5) * 6
            let wig = sinf(m.walkPhase * 1.3 + Float(i)) * 0.25
            p.append(Part(mn: V3(tx - 4, 16 - len, tz - 4), mx: V3(tx + 4, 16, tz + 4), pivot: V3(tx, 16, tz), rotX: wig, color: white))
        }
        return p
    case .blaze:
        let yellow = V3(1.0, 0.78, 0.2), dark = V3(0.7, 0.4, 0.05)
        var p: [Part] = [box(-4, 20, -4, 8, 8, 8, yellow, 4)]
        p += eyes(24, -4, 1, 1.5, V3(0.15, 0.08, 0.02))
        let t = m.walkPhase * 0.9
        for i in 0..<12 {
            let ring = i / 4
            let a = t * (ring == 1 ? -1 : 1) + Float(i % 4) * .pi / 2 + Float(ring) * 0.4
            let r: Float = [9, 7, 5][ring]
            let y: Float = [14, 6, -2][ring] + 2 + sinf(t * 2 + Float(i)) * 1.2
            let x = cosf(a) * r, z = sinf(a) * r
            p.append(box(x - 1, y + 2, z - 1, 2, 8, 2, i % 2 == 0 ? yellow : dark, 4))
        }
        return p
    case .witherSkeleton:
        let c = V3(0.16, 0.16, 0.17)
        let s: Float = 1.2
        func sb(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ col: V3) -> Part { box(x * s, y * s, z * s, w * s, h * s, d * s, col, 5) }
        return [
            Part(mn: V3(-2.4, 0, -1.2), mx: V3(0, 14.4, 1.2), pivot: V3(-1.2, 14.4, 0), rotX: swing, color: c, pattern: 5),
            Part(mn: V3(0, 0, -1.2), mx: V3(2.4, 14.4, 1.2), pivot: V3(1.2, 14.4, 0), rotX: -swing, color: c, pattern: 5),
            sb(-4, 12, -2, 8, 12, 4, c),
            Part(mn: V3(-7.2, 14.4, -1.2), mx: V3(-4.8, 28.8, 1.2), pivot: V3(-6, 27, 0), rotX: m.aggro ? -1.4 : swing, color: c, pattern: 5),
            Part(mn: V3(4.8, 14.4, -1.2), mx: V3(7.2, 28.8, 1.2), pivot: V3(6, 27, 0), rotX: m.aggro ? -1.4 : -swing, color: c, pattern: 5),
            // Stone sword.
            Part(mn: V3(5.5, 13, -14), mx: V3(6.5, 14.5, 0), pivot: V3(6, 27, 0), rotX: m.aggro ? -1.4 : -swing, color: V3(0.5, 0.5, 0.5)),
            sb(-4, 24, -4, 8, 8, 8, c),
            sb(-2.5, 27.5, -4.1, 1.5, 1.5, 0.2, V3(0.02, 0.02, 0.02)), sb(1, 27.5, -4.1, 1.5, 1.5, 0.2, V3(0.02, 0.02, 0.02)),
        ]
    case .slime, .magmaCube:
        if m.kind == .magmaCube {
            let s = Float(m.slimeSize) * 8
            let stretch: Float = m.onGround ? 1 : 1.35
            var p: [Part] = []
            // Stacked slices that spread apart mid-jump; glowing core.
            for i in 0..<4 {
                let y0 = Float(i) * s / 4 * stretch
                p.append(box(-s / 2, y0, -s / 2, s, s / 4, s, i % 2 == 0 ? V3(0.35, 0.08, 0.05) : V3(0.5, 0.12, 0.05), 4))
            }
            p.append(box(-s * 0.3, s * 0.25, -s * 0.3, s * 0.6, s * 0.5 * stretch, s * 0.6, V3(1, 0.55, 0.1)))
            p += [box(-s * 0.32, s * 0.55 * stretch, -s / 2 - 0.1, s * 0.18, s * 0.12, 0.2, V3(1, 0.8, 0.2)),
                  box(s * 0.14, s * 0.55 * stretch, -s / 2 - 0.1, s * 0.18, s * 0.12, 0.2, V3(1, 0.8, 0.2))]
            return p
        }
        let s = Float(m.slimeSize) * 8
        let squash: Float = m.onGround ? 1 : 1.15
        return [
            box(-s / 2, 0, -s / 2, s, s * squash, s, V3(0.45, 0.8, 0.4), 2),
            box(-s * 0.3, s * 0.55, -s / 2 - 0.1, s * 0.15, s * 0.15, 0.2, V3(0.1, 0.2, 0.1)),
            box(s * 0.15, s * 0.55, -s / 2 - 0.1, s * 0.15, s * 0.15, 0.2, V3(0.1, 0.2, 0.1)),
        ]
    }
}

// Writes the mob triangles (camera-relative) into `out`; returns the vertex count written.
func writeMobVertices(_ mobs: [Mob], eye: V3, daylight: Float, world: World,
                      into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
    let CT = Mesher.cornerTable
    let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
    let order = [0, 1, 2, 0, 2, 3]
    var n = 0
    for m in mobs {
        let l = world.lightAt(Int(floor(m.pos.x)), Int(floor(m.pos.y + m.height * 0.5)), Int(floor(m.pos.z)))
        var bright = max(0.05, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
        bright = bright + (1 - bright) * world.dim.ambient
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        let base = m.pos - eye
        let tint = m.hurt > 0 ? V3(1, 0.45, 0.45) : (m.fire > 0 ? V3(1, 0.7, 0.4) : V3(1, 1, 1))
        let scale: Float = m.sized ? 1 : m.scale
        let glow = m.kind == .blaze || m.kind == .magmaCube || m.kind == .ghast
        let lit = glow ? max(bright, 0.85) : bright
        for p in parts(m) {
            if n + 36 > capacity { return n }
            let ca = cosf(p.rotX), sa = sinf(p.rotX)
            let cz = cosf(p.rotZ), sz = sinf(p.rotZ)
            let size = p.mx - p.mn
            for f in 0..<6 {
                for k in order {
                    let ci = (f * 4 + k) * 3
                    let lp = p.mn + size * V3(Float(CT[ci]), Float(CT[ci + 1]), Float(CT[ci + 2]))
                    var q = lp - p.pivot
                    q = V3(q.x, q.y * ca - q.z * sa, q.y * sa + q.z * ca)
                    q = V3(q.x * cz - q.y * sz, q.x * sz + q.y * cz, q.z) + p.pivot
                    q *= scale / 16
                    let r = V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z) + base
                    out[n] = MobVert(pos: V4(r, p.pattern), color: V4(p.color * tint, faceShade[f] * lit), local: V4(lp, 0))
                    n += 1
                }
            }
        }
    }
    return n
}

// MARK: Manager

final class MobManager {
    var mobs: [Mob] = []
    static let passiveCap = 16
    static let hostileCap = 35
    private var passiveTimer: Float = 2
    private var hostileTimer: Float = 1
    static let breedFood: [MobKind: [String]] = [
        .cow: ["wheat"], .sheep: ["wheat"], .pig: ["carrot", "potato", "beetroot"], .chicken: ["wheat_seeds", "beetroot_seeds"],
        .hoglin: ["crimson_fungus"], .strider: ["warped_fungus"],
    ]

    func update(_ dt: Float, game: Game) {
        let w = game.world
        let p = game.player.pos
        for m in mobs {
            m.update(dt, game: game)
            if m.callTimer <= 0 {
                m.callTimer = Float.random(in: 8...24)
                if m.kind != .creeper && m.kind != .magmaCube { game.sfx(m.kind.call, 0.6, at: m.pos + V3(0, m.height * 0.8, 0)) }
            }
        }
        // Breeding: two mobs of a kind in love next to each other make a baby.
        var babies: [Mob] = []
        for a in mobs where a.inLove > 0 {
            if let b = mobs.first(where: { $0 !== a && $0.kind == a.kind && $0.inLove > 0 && simd_length($0.pos - a.pos) < 1.5 }) {
                a.inLove = 0; b.inLove = 0
                a.breedCooldown = 300; b.breedCooldown = 300
                let baby = Mob(a.kind, at: (a.pos + b.pos) * 0.5)
                baby.baby = true
                baby.scale = 0.5
                babies.append(baby)
                game.addXP(Int.random(in: 1...7))
                game.particles.hearts(at: baby.pos + V3(0, 0.8, 0))
            }
        }
        mobs += babies
        // Deaths: loot + XP, slime splitting.
        var spawned: [Mob] = []
        for m in mobs where m.health <= 0 {
            if m.sized && m.slimeSize > 1 {
                for _ in 0..<Int.random(in: 2...4) {
                    let s = Mob(m.kind, at: m.pos + V3(Float.random(in: -0.4...0.4), 0.2, Float.random(in: -0.4...0.4)))
                    s.makeSlime(size: m.slimeSize / 2)
                    spawned.append(s)
                }
            }
            if m.health > -1000 { game.mobDied(m) }
        }
        let limit = Float((w.renderDistance + 1) * CS)
        mobs.removeAll { m in
            if m.health <= 0 { return true }
            let d = simd_length(V2(m.pos.x - p.x, m.pos.z - p.z))
            if abs(m.pos.x - p.x) > limit || abs(m.pos.z - p.z) > limit || !w.isLoaded(Int(floor(m.pos.x)), Int(floor(m.pos.z))) { return true }
            if m.kind.hostile && d > 128 { return true }
            if m.kind.hostile && !m.persistent && d > 32 && Float.random(in: 0..<1) < dt / 40 { return true }
            return false
        }
        mobs += spawned
        passiveTimer -= dt
        if passiveTimer <= 0 {
            passiveTimer = 2
            if mobs.filter({ !$0.kind.hostile }).count < MobManager.passiveCap { trySpawnPassive(game) }
        }
        hostileTimer -= dt
        if hostileTimer <= 0 {
            hostileTimer = 0.5
            if game.survival && mobs.filter({ $0.kind.hostile }).count < MobManager.hostileCap {
                for _ in 0..<3 { trySpawnHostile(game) }
            }
        }
    }

    // Surface y (feet) at a column if it's grass with two free blocks above, else nil.
    func grassSurface(_ w: World, _ x: Int, _ z: Int) -> Int? {
        var y = CH - 2
        while y > 1 && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.isLiquid(w.block(x, y, z)) { y -= 1 }
        guard w.block(x, y, z) == GRASS else { return nil }
        let a = w.block(x, y + 1, z), b = w.block(x, y + 2, z)
        guard !Blocks.collide[Int(a)] && !Blocks.collide[Int(b)] && !Blocks.isLiquid(a) else { return nil }
        return y + 1
    }

    func trySpawnPassive(_ game: Game) {
        let w = game.world
        let rd = min(w.renderDistance, 6)
        guard rd >= 3 else { return }
        let pcx = floorDiv(Int(floor(game.player.pos.x)), CS), pcz = floorDiv(Int(floor(game.player.pos.z)), CS)
        let dx = Int.random(in: -rd...rd), dz = Int.random(in: -rd...rd)
        if max(abs(dx), abs(dz)) < 2 { return }
        guard let c = w.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], c.meshedOnce else { return }
        let x = c.cx * CS + Int.random(in: 2..<(CS - 2)), z = c.cz * CS + Int.random(in: 2..<(CS - 2))
        guard grassSurface(w, x, z) != nil else { return }
        let kind: MobKind
        let r = Float.random(in: 0..<1)
        switch w.gen.column(x, z).biome {
        case .plains: kind = r < 0.35 ? .cow : (r < 0.65 ? .sheep : (r < 0.85 ? .pig : .chicken))
        case .forest: kind = r < 0.3 ? .chicken : (r < 0.55 ? .cow : (r < 0.8 ? .pig : .sheep))
        case .snowy, .mountains: kind = .sheep
        default: return
        }
        for _ in 0..<Int.random(in: 2...4) {
            let sx = x + Int.random(in: -2...2), sz = z + Int.random(in: -2...2)
            guard let y = grassSurface(w, sx, sz) else { continue }
            mobs.append(Mob(kind, at: V3(Float(sx) + 0.5, Float(y), Float(sz) + 0.5)))
        }
    }

    // Monster spawning: block light 0, combined light <= random(0...7), solid floor with 2 free
    // blocks, 24-64 blocks from the player.
    func trySpawnHostile(_ game: Game) {
        let w = game.world
        if w.dim == .nether { trySpawnNether(game); return }
        if w.dim == .end { return }
        let pp = game.player.pos
        let a = Float.random(in: 0..<(2 * .pi)), r = Float.random(in: 24...64)
        let x = Int(floor(pp.x + cosf(a) * r)), z = Int(floor(pp.z + sinf(a) * r))
        guard w.isLoaded(x, z) else { return }
        let top = w.topY(x, z)
        guard top > 2 else { return }
        var y = Int.random(in: 2...(top + 1))
        while y > 1 && !(Blocks.opaque[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.collide[Int(w.block(x, y + 1, z))]) { y -= 1 }
        if y <= 1 { return }
        if Blocks.isLiquid(w.block(x, y, z)) || w.block(x, y - 1, z) == BEDROCK { return }
        let l = w.lightAt(x, y, z)
        if l.block > 0 { return }
        if l.sky > Int.random(in: 0..<32) { return }
        let darken = Int((1 - (game.daylight - 0.12) / 0.88) * 11)
        let raw = max(l.block, l.sky - (11 - darken))
        if raw > Int.random(in: 0...7) { return }
        let spawnPos = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
        if simd_length(spawnPos - pp) < 24 { return }
        // Slime chunks (10% of chunks) spawn slimes below y=40.
        let slimeChunk = hash3(floorDiv(x, 16), 0, floorDiv(z, 16), 0x51113) % 10 == 0
        if slimeChunk && y - YOFF < 40 && Float.random(in: 0..<1) < 0.3 {
            let s = Mob(.slime, at: spawnPos)
            s.makeSlime(size: [1, 2, 4][Int.random(in: 0...2)])
            if !s.collides(spawnPos, w) { mobs.append(s) }
            return
        }
        let roll = Int.random(in: 0..<415)
        let kind: MobKind = roll < 95 ? .zombie : (roll < 195 ? .skeleton : (roll < 295 ? .creeper : (roll < 395 ? .spider : .enderman)))
        let m = Mob(kind, at: spawnPos)
        if kind == .zombie && Float.random(in: 0..<1) < 0.05 { m.baby = true; m.scale = 0.5 }
        if m.collides(spawnPos, w) { return }
        mobs.append(m)
    }

    // Nether spawning (no light requirement): per-biome weighted lists, overridden inside fortresses.
    func trySpawnNether(_ game: Game) {
        let w = game.world
        let pp = game.player.pos
        let a = Float.random(in: 0..<(2 * .pi)), r = Float.random(in: 24...64)
        let x = Int(floor(pp.x + cosf(a) * r)), z = Int(floor(pp.z + sinf(a) * r))
        guard w.isLoaded(x, z) else { return }
        // Striders: groups on the lava sea surface.
        let lavaY = YOFF + NetherGen.lavaLevel
        if Float.random(in: 0..<1) < 0.1 {
            if Blocks.fluidKind[Int(w.block(x, lavaY, z))] == 2 && w.block(x, lavaY + 1, z) == AIR && w.block(x, lavaY + 2, z) == AIR
                && mobs.filter({ $0.kind == .strider }).count < 8 {
                for i in 0..<Int.random(in: 1...2) { mobs.append(Mob(.strider, at: V3(Float(x + i) + 0.5, Float(lavaY + 1), Float(z) + 0.5))) }
            }
            return
        }
        var y = YOFF + Int.random(in: 1...126)
        // Walk down to a floor with two free blocks above it.
        while y > YOFF + 1 && !(Blocks.opaque[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))]
                                 && !Blocks.collide[Int(w.block(x, y + 1, z))]) { y -= 1 }
        if y <= YOFF + 1 || Blocks.isLiquid(w.block(x, y, z)) || w.block(x, y - 1, z) == BEDROCK { return }
        let spawnPos = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
        if simd_length(spawnPos - pp) < 24 { return }
        typealias Entry = (MobKind, Int, Int, Int)      // kind, weight, min group, max group
        var list: [Entry]
        if w.gen.structures?.structure(at: x, y, z, kind: "fortress") != nil && Blocks.key(w.block(x, y - 1, z)) == "nether_bricks" {
            list = [(.blaze, 10, 2, 3), (.zombifiedPiglin, 5, 4, 4), (.witherSkeleton, 8, 5, 5), (.skeleton, 2, 5, 5), (.magmaCube, 3, 4, 4)]
        } else {
            switch w.gen.column(x, z).biome {
            case .soulSandValley: list = [(.skeleton, 20, 5, 5), (.ghast, 50, 4, 4), (.enderman, 1, 4, 4)]
            case .basaltDeltas: list = [(.ghast, 40, 1, 1), (.magmaCube, 100, 2, 5)]
            case .crimsonForest: list = [(.zombifiedPiglin, 1, 2, 4), (.hoglin, 9, 3, 4), (.piglin, 5, 3, 4)]
            case .warpedForest: list = [(.enderman, 1, 4, 4)]
            default: list = [(.zombifiedPiglin, 100, 4, 4), (.ghast, 50, 4, 4), (.magmaCube, 2, 4, 4), (.enderman, 1, 4, 4), (.piglin, 15, 4, 4)]
            }
        }
        let total = list.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<total)
        var pick = list[0]
        for e in list { roll -= e.1; if roll < 0 { pick = e; break } }
        // Ghasts are rare per attempt (they need a big open space) — the reference game's spawn
        // attempts fail for them most of the time.
        if pick.0 == .ghast && Float.random(in: 0..<1) < 0.8 { return }
        let n = Int.random(in: pick.2...pick.3)
        for _ in 0..<n {
            let sx = x + Int.random(in: -3...3), sz = z + Int.random(in: -3...3)
            var sy = y + 2
            while sy > y - 4 && !Blocks.opaque[Int(w.block(sx, sy - 1, sz))] { sy -= 1 }
            let p = V3(Float(sx) + 0.5, Float(sy), Float(sz) + 0.5)
            let m = Mob(pick.0, at: pick.0 == .ghast ? p + V3(0, 3, 0) : p)
            if m.sized { m.makeSlime(size: [1, 2, 4][Int.random(in: 0...2)]) }
            if m.collides(m.pos, w) { continue }
            mobs.append(m)
            if mobs.count >= MobManager.hostileCap + 10 { return }
        }
    }

    // Nearest mob along a ray.
    func raycast(_ o: V3, _ d: V3, maxDist: Float) -> (Mob, Float)? {
        var best: (Mob, Float)?
        for m in mobs {
            if let t = m.rayHit(o, d, maxDist: maxDist), t < (best?.1 ?? .greatestFiniteMagnitude) { best = (m, t) }
        }
        return best
    }
}
