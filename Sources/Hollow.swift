import Foundation
import simd

// Eyes of ender, the hollow gate, the dragon fight and the credits.

// A thrown seeker eye: rises and flies toward the nearest stronghold (at most 12 blocks), hovers,
// then drops as an item (80%) or shatters.
final class SeekerEye {
    var pos: V3
    let target: V3
    var age: Float = 0
    var dead = false
    init(_ p: V3, _ t: V3) { pos = p; target = t }
}

// Shellsentry bullet: slowly homes in on the player; a hit deals 4 and levitates for 10 s. Punching it
// destroys it.
final class SentryBolt {
    var pos: V3
    var vel: V3
    var age: Float = 0
    var dead = false
    init(_ p: V3, _ v: V3) { pos = p; vel = v }
}

// Lingering dragon breath: 6 damage per second to a player standing in it.
// Lingering potions leave the same kind of cloud carrying the potion's effects.
struct AcidCloud {
    var pos: V3; var radius: Float; var time: Float; var tick: Float = 0
    var potion: ItemID = 0
    var maxTime: Float = 0
}

let ENDER_EYE_FLIGHT: Float = 12

extension Game {
    var endGen: HollowGen? { world.gen as? HollowGen }

    // MARK: Eyes of ender

    // Right-click with an eye: fill a portal frame, or throw it toward the nearest stronghold.
    func useSeekerEye(on hit: (hit: IVec3, normal: IVec3)?) -> Bool {
        if let t = hit, Blocks.key(world.block(t.hit.x, t.hit.y, t.hit.z)) == "end_portal_frame" {
            world.setBlock(t.hit.x, t.hit.y, t.hit.z, Blocks.id("end_portal_frame") + 1)
            consumeHeld()
            sfx(.place(.stone), 1, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            if tryActivateEndPortal(near: t.hit) { sfx(.levelUp, 1) }
            return true
        }
        guard dim.dim == .overworld, let s = world.gen.structures?.nearest("stronghold", x: Int(player.pos.x), z: Int(player.pos.z)) else { return false }
        let target = V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5)
        eyes.append(SeekerEye(player.eye, target))
        consumeHeld()
        sfx(.bow, 0.6)
        return true
    }

    func updateEyes(_ dt: Float) {
        for e in eyes {
            e.age += dt
            var to = V2(e.target.x - e.pos.x, e.target.z - e.pos.z)
            let d = simd_length(to)
            if e.age < 1.6 && d > 0.5 {
                to /= d
                let speed: Float = 8
                e.pos.x += to.x * speed * dt
                e.pos.z += to.y * speed * dt
                e.pos.y += (e.age < 1 ? 3.5 : 0.5) * dt
            } else {
                e.pos.y += sinf(e.age * 8) * 0.2 * dt
            }
            if Float.random(in: 0..<1) < dt * 20 { particles.flame(at: e.pos) }
            if e.age > 2.6 {
                e.dead = true
                if Float.random(in: 0..<1) < 0.8 { drops.spawn(ItemStack(Items.id("ender_eye"), 1), at: e.pos, vel: V3(0, 0, 0), delay: 0.2) }
                else { sfx(.breakBlock(.glass), 0.8, at: e.pos); particles.explosion(at: e.pos, power: 0.3) }
            }
        }
        eyes.removeAll { $0.dead }
    }

    // A complete ring of 12 filled frames (a 5x5 square without corners) lights the 3x3 inside.
    func tryActivateEndPortal(near p: IVec3) -> Bool {
        let eye = Blocks.id("end_portal_frame") + 1
        for dz in -3...3 { for dx in -3...3 {
            let c = IVec3(p.x + dx, p.y, p.z + dz)
            var ok = true
            for i in -1...1 where ok {
                for q in [IVec3(c.x + i, c.y, c.z - 2), IVec3(c.x + i, c.y, c.z + 2), IVec3(c.x - 2, c.y, c.z + i), IVec3(c.x + 2, c.y, c.z + i)] {
                    if world.block(q.x, q.y, q.z) != eye { ok = false; break }
                }
            }
            guard ok else { continue }
            for z in -1...1 { for x in -1...1 { world.setBlockAsync(c.x + x, c.y, c.z + z, Blocks.id("end_portal")) } }
            world.setBlock(c.x, c.y, c.z, Blocks.id("end_portal"))
            return true
        } }
        return false
    }

    // MARK: Travel

    func endPortalTick() {
        let p = player.pos
        let feet = world.block(Int(floor(p.x)), Int(floor(p.y + 0.1)), Int(floor(p.z)))
        let key = Blocks.key(feet)
        // Rifts sit between bedrock caps, so any part of the body touching one counts (walking up to a far-island
        // return rift, or standing on a pillar next to a floating one); void pearls work too (MobsG.swift).
        if portalCooldown <= 0 && dim.dim == .end {
            for y in [p.y + 0.1, p.y + 0.9, p.y + 1.7] {
                for (dx, dz) in [(Float(0), Float(0)), (0.4, 0), (-0.4, 0), (0, 0.4), (0, -0.4)]
                where Blocks.key(world.block(Int(floor(p.x + dx)), Int(floor(y)), Int(floor(p.z + dz)))) == "end_gateway" {
                    portalCooldown = 3; gatewayTeleport(); return
                }
            }
        }
        guard key == "end_portal", portalCooldown <= 0 else { return }
        portalCooldown = 3
        if dim.dim == .end {
            // Exit portal: credits the first time, then home.
            if !seenCredits { credits = 0 } else { returnFromEnd() }
        } else {
            enterEnd()
        }
    }

    func enterEnd() {
        // The obsidian landing platform at 100, 48, 0 (5x5, cleared above), like the reference game.
        let py = YOFF + 48
        changeDimension(to: .end, at: V3(100.5, Float(py + 1), 0.5))
        for z in -2...2 { for x in -2...2 {
            world.setBlockAsync(100 + x, py, z, OBSIDIAN)
            for y in 1...3 { world.setBlockAsync(100 + x, py + y, z, AIR) }
        } }
        world.setBlock(100, py, 0, OBSIDIAN)
        player.pos = V3(100.5, Float(py + 1), 0.5)
        player.yaw = .pi / 2
        player.vel = .zero
        player.airPeak = player.pos.y
    }

    func returnFromEnd() {
        credits = nil
        seenCredits = true
        changeDimension(to: .overworld, at: spawnPoint)
        player.pos = spawnPoint
        player.vel = .zero
        player.airPeak = spawnPoint.y
    }

    // Hollow rifts. A rift on the central island throws the player out along its direction to the first outer
    // island past 1000 blocks and builds a return rift there (bedrock below and above, like the reference game's
    // exit gateways); a rift out there brings the player back to solid ground just inside the ring of rifts.
    func gatewayTeleport() {
        guard let g = endGen else { return }
        var dir = V2(player.pos.x, player.pos.z)
        let far = simd_length(dir) > 500
        dir = simd_length(dir) > 1 ? simd_normalize(dir) : V2(1, 0)
        if far {
            var dest: V3?
            for r in stride(from: 90, through: 12, by: -3) where dest == nil {
                let x = Int((dir.x * Float(r)).rounded(.down)), z = Int((dir.y * Float(r)).rounded(.down))
                if let top = g.surface(x, z) { dest = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5) }
            }
            let d = dest ?? V3(3.5, Float(fountainY + 1), 3.5)
            _ = world.loadSync(center: d, radius: 2)
            player.pos = V3(d.x, Float(world.topY(Int(floor(d.x)), Int(floor(d.z))) + 1), d.z)
            player.vel = .zero
            player.airPeak = player.pos.y
            sfx(.levelUp, 0.4)
            return
        }
        var r: Float = 1024
        var spot: V3?
        while r < 1400 && spot == nil {
            let x = Int(dir.x * r), z = Int(dir.y * r)
            for dz in stride(from: -16, through: 16, by: 4) { for dx in stride(from: -16, through: 16, by: 4) where spot == nil {
                if let top = g.surface(x + dx, z + dz) { spot = V3(Float(x + dx) + 0.5, Float(top + 1), Float(z + dz) + 0.5) }
            } }
            r += 16
        }
        let dest = spot ?? V3(dir.x * 1024, Float(YOFF + 70), dir.y * 1024)
        _ = world.loadSync(center: dest, radius: 2)
        let bx = Int(floor(dest.x)), bz = Int(floor(dest.z))
        if spot == nil {
            // No island found: a small hollow stone platform.
            for z in -2...2 { for x in -2...2 { world.setBlock(bx + x, Int(dest.y) - 1, bz + z, Blocks.id("end_stone")) } }
        }
        // Return rift two blocks toward the centre, standing on the island (step up onto its bedrock base).
        let rx = bx - Int((dir.x * 2).rounded()), rz = bz - Int((dir.y * 2).rounded())
        if !(max(0, Int(dest.y) - 3)...min(CH - 1, Int(dest.y) + 6)).contains(where: { Blocks.key(world.block(rx, $0, rz)) == "end_gateway" }) {
            let base = max(Int(dest.y), world.topY(rx, rz) + 1)
            if world.block(rx, base - 1, rz) == AIR { world.setBlock(rx, base - 1, rz, Blocks.id("end_stone")) }
            world.setBlock(rx, base, rz, BEDROCK)
            world.setBlock(rx, base + 1, rz, Blocks.id("end_gateway"))
            world.setBlock(rx, base + 2, rz, BEDROCK)
        }
        player.pos = V3(dest.x, Float(world.topY(bx, bz) + 1), dest.z)
        player.vel = .zero
        player.airPeak = player.pos.y
        achieve("gateway")
        sfx(.levelUp, 0.4)
    }

    // MARK: Wyrm egg

    // Hitting (survival) or using the egg makes it hop to a random open spot up to 15 blocks away and 7 up or
    // down, like the reference game; it's collected by pushing it or letting it fall onto a torch.
    func teleportEgg(_ p: IVec3) -> Bool {
        let egg = world.block(p.x, p.y, p.z)
        guard Blocks.key(egg) == "dragon_egg" else { return false }
        for _ in 0..<1000 {
            let q = IVec3(p.x + Int.random(in: -15...15), p.y + Int.random(in: -7...7), p.z + Int.random(in: -15...15))
            guard q.y > 0, q.y < CH - 1, world.isLoaded(q.x, q.z), world.block(q.x, q.y, q.z) == AIR else { continue }
            world.setBlock(p.x, p.y, p.z, AIR)
            world.setBlock(q.x, q.y, q.z, egg)
            particles.explosion(at: blockCenter(p), power: 0.3)
            sfx(.mobVoidwalker, 0.6, at: blockCenter(q))
            return true
        }
        return false
    }

    private func blockCenter(_ p: IVec3) -> V3 { V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) }

    // MARK: Dragon fight

    var fountainY: Int { endGen.map { $0.surface(0, 0) ?? (YOFF + 60) } ?? (YOFF + 60) }

    func endTick(_ dt: Float) {
        guard dim.dim == .end else { return }
        // The dragon is present until it has been killed (respawns if it was lost to unloading).
        if !dragonKilled && !mobs.mobs.contains(where: { $0.kind == .enderDragon })
            && !mobs.stored.values.contains(where: { $0.contains { $0.k == "ender_dragon" } }) {
            dragonSpawnTimer -= dt
            if dragonSpawnTimer <= 0 && world.isLoaded(0, 0) {
                dragonSpawnTimer = 5
                let d = Mob(.enderDragon, at: V3(0.5, Float(fountainY + 40), 0.5))
                d.persistent = true
                mobs.mobs.append(d)
            }
        }
        for b in bullets {
            b.age += dt
            let to = player.eye - V3(0, 0.4, 0) - b.pos
            let d = simd_length(to)
            if d > 0.01 { b.vel += (to / d * 4 - b.vel) * min(1, dt * 1.5) }
            b.pos += b.vel * dt
            if Float.random(in: 0..<1) < dt * 20 { particles.smoke(at: b.pos, dark: false) }
            if d < 0.7 {
                b.dead = true
                hurtPlayer(4, from: b.pos, cause: "was shot by Shellsentry", knockback: 0.3)
                applyEffect(.levitation, amp: 0, seconds: 10)
            } else if b.age > 12 || Blocks.collide[Int(world.block(Int(floor(b.pos.x)), Int(floor(b.pos.y)), Int(floor(b.pos.z))))] {
                b.dead = true
                particles.explosion(at: b.pos, power: 0.2)
            }
        }
        bullets.removeAll { $0.dead }
    }

    // Player punch on a sentry bolt destroys it.
    func punchBullet() -> Bool {
        for b in bullets {
            if let h = World.rayBox(player.eye, player.look, b.pos - V3(0.2, 0.2, 0.2), b.pos + V3(0.2, 0.2, 0.2)), h.0 < 4 {
                b.dead = true
                particles.explosion(at: b.pos, power: 0.2)
                return true
            }
        }
        return false
    }

    func dragonDied(_ d: Mob) {
        // Only the first wyrm gives 12000 XP and the egg; every kill opens a rift, so no rifts = never killed
        // (dragonKilled goes back to false while a respawned wyrm is alive).
        let first = !dragonKilled && gateways == 0
        dragonKilled = true
        achieve("kill_ender_dragon")
        addXP(first ? 12000 : 500)
        let fy = fountainY
        HollowGen.fountainBlocks(fy, active: true) { x, y, z, b in world.setBlockAsync(x, y, z, b) }
        if first { world.setBlockAsync(0, fy + 4, 0, Blocks.id("dragon_egg")) }
        world.setBlock(0, fy + 3, 0, BEDROCK)
        // A new hollow rift (up to 20) on the ring of radius 96 at y 75.
        if gateways < 20 {
            let a = 2 * Double.pi * Double((gateways * 7) % 20) / 20
            let gx = Int((96 * cos(a)).rounded()), gz = Int((96 * sin(a)).rounded()), gy = YOFF + 75
            world.setBlockAsync(gx, gy - 1, gz, BEDROCK)
            world.setBlockAsync(gx, gy + 1, gz, BEDROCK)
            world.setBlock(gx, gy, gz, Blocks.id("end_gateway"))
            gateways += 1
        }
        sfx(.explode, 1, at: d.pos)
        onToast?("The Hollow: exit portal open")
    }
}

extension Game {
    // Original credits text (not the reference game's poem).
    static let creditsLines: [String] = [
        "BLOCKSMITH", "", "", "The wyrm is gone. The island is quiet.", "",
        "You came from a world of grass and water,", "dug down through stone and deeprock,",
        "walked through fire in the Emberdeep,", "followed the eyes across the land,",
        "and crossed the dark to the Hollow.", "", "Every block you placed was a choice.",
        "Every tunnel, every tower, every farm", "was a small world of your own making.", "",
        "The portal home is open.", "The world you built is waiting.", "", "", "",
        "Made for Remington", "", "Game design, code, art and sound", "generated procedurally in Swift and Metal", "",
        "Thanks for playing.", "", "", "", "",
    ]
    static var creditsLength: Float { Float(creditsLines.count) * 1.4 + 12 }

    // Thrown eyes and the crystal healing beams.
    func writeEndEntities(_ wr: inout EntityWriter, eye: V3, right: V3, up: V3) {
        if let layer = Items.texLayer(Items.id("ender_eye")) {
            for e in eyes { wr.sprite(center: e.pos - eye, half: 0.15, right: right, up: up, layer: layer, light: 1) }
        }
        let white = Int(Tex.id("smoke"))
        for b in bullets {
            wr.sprite(center: b.pos - eye, half: 0.18, right: right, up: up, layer: white, light: 1, tint: V3(1.3, 1.25, 1.1))
        }
        for d in mobs.mobs where d.kind == .enderDragon {
            guard let c = d.healTarget else { continue }
            let a = c.pos + V3(0, 1.25, 0) - eye, b = d.pos + V3(0, 2.5, 0) - eye
            let dir = simd_normalize(b - a)
            var side = simd_cross(dir, simd_normalize(-(a + b) * 0.5))
            if simd_length(side) < 1e-3 { side = V3(1, 0, 0) }
            side = simd_normalize(side) * 0.12
            wr.quad([a - side, b - side, b + side, a + side], [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)],
                    white, V4(1.0, 0.5, 1.4, 1))
        }
    }
}

// MARK: Dragon + crystal behaviour

extension Mob {
    // Phases: 0 circling, 1 strafing (fireball), 2 charging, 3 landing, 4 perched, 5 taking off, 6 dying.
    func updateDragon(_ dt: Float, _ g: Game) {
        let w = g.world
        let fy = Float(g.fountainY)
        phaseTime += dt
        let player = g.player.pos
        let toPlayer = player - pos
        let dist = simd_length(toPlayer)
        // Crystals heal the dragon: +1 every 0.5 s from the nearest crystal within 32 blocks.
        healTarget = g.mobs.mobs.filter { $0.kind == .endCrystal && $0.health > 0 && simd_length($0.pos - pos) < 32 }
            .min { simd_length($0.pos - pos) < simd_length($1.pos - pos) }
        if healTarget != nil && phase != 6 {
            fireTick += dt
            if fireTick >= 0.5 { fireTick = 0; health = min(spec.health, health + 1) }
        }
        var goal = pos
        var speed: Float = 14
        switch phase {
        case 0:
            circleAngle += dt * 0.25
            goal = V3(cosf(circleAngle) * 55, fy + 22 + sinf(circleAngle * 2.3) * 8, sinf(circleAngle) * 55)
            if phaseTime > Float.random(in: 8...14) {
                phaseTime = 0
                let crystals = g.mobs.mobs.filter { $0.kind == .endCrystal && $0.health > 0 }.count
                let r = Int.random(in: 0..<(3 + crystals))
                let canFight = g.survival && g.alive && dist < 150
                if r == 0 { phase = 3 }
                else if canFight && r < 3 { phase = 1 }
                else if canFight && r < 5 { phase = 2 }
            }
        case 1:
            goal = player + V3(0, 18, 0) - simd_normalize(V3(toPlayer.x, 0, toPlayer.z) + V3(0.001, 0, 0)) * 30
            if (dist < 50 && phaseTime > 2) || phaseTime > 10 {
                let from = pos + forward * 5
                g.projectiles.fireball(from: from, dir: simd_normalize(g.player.eye - from), big: true, byPlayer: false, dragon: true)
                g.sfx(.fireball, 1.2, at: from)
                phase = 0; phaseTime = 0
            }
        case 2:
            goal = player + V3(0, 1, 0)
            speed = 20
            if dist < 5 {
                g.hurtPlayer(10, from: pos, cause: "was slain by Hollow Wyrm", knockback: 2.5, attacker: self)
                attackCooldown = 1
                phase = 0; phaseTime = 0
            }
            if phaseTime > 8 { phase = 0; phaseTime = 0 }
        case 3:
            goal = V3(0.5, fy + 4, 0.5)
            speed = 10
            if simd_length(goal - pos) < 3 { phase = 4; phaseTime = 0; vel = .zero; sitDamage = 0 }
        case 4:
            goal = V3(0.5, fy + 4, 0.5)
            speed = 0
            face(player)
            // Reference sitting sequence: scan + roar (3.25 s), then 10 s of breath on the ground in front of the
            // head (radius 5); four rounds, then take off. Lost interest (no player within 20 for 5 s) ends it early.
            let cycle: Float = 13.25
            let tIn = phaseTime.truncatingRemainder(dividingBy: cycle), tPrev = (phaseTime - dt).truncatingRemainder(dividingBy: cycle)
            if tPrev < 3.25 && tIn >= 3.25 && dist < 20 {
                let at = pos + forward * 6
                let gy = Float(w.topY(Int(floor(at.x)), Int(floor(at.z))) + 1)
                g.clouds.append(AcidCloud(pos: V3(at.x, min(gy, pos.y) + 0.05, at.z), radius: 5, time: 10))
                g.sfx(.mobWailer, 0.8, at: pos)
            }
            breakTimer = dist < 20 ? 0 : breakTimer + dt
            if phaseTime > cycle * 4 || breakTimer > 5 { phase = 5; phaseTime = 0; breakTimer = 0 }
        case 5:
            goal = V3(pos.x, fy + 30, pos.z)
            speed = 8
            if pos.y > fy + 26 { phase = 0; phaseTime = 0 }
        default:
            // Dying: rise slowly while bursting, then vanish.
            vel = V3(0, 1, 0)
            pos += vel * dt
            if Float.random(in: 0..<1) < dt * 10 {
                g.particles.explosion(at: pos + V3(Float.random(in: -4...4), Float.random(in: 0...4), Float.random(in: -4...4)), power: 0.8)
            }
            if phaseTime > 10 {
                health = -1000
                g.dragonDied(self)
            }
            return
        }
        let d = goal - pos
        let l = simd_length(d)
        if speed > 0 && l > 0.5 {
            let want = d / l * min(speed, l * 2)
            vel += (want - vel) * min(1, dt * 1.5)
            yaw = atan2f(-vel.x, -vel.z)
        } else {
            vel *= expf(-4 * dt)
        }
        // The dragon smashes through anything but obsidian, hollow stone, bedrock and iron bars.
        pos += vel * dt
        if phase != 4 && Int(phaseTime * 4) != Int((phaseTime - dt) * 4) {
            let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
            for dy in 0...3 { for dz in -2...2 { for dx in -2...2 {
                let b = w.block(c.x + dx, c.y + dy, c.z + dz)
                let k = Blocks.key(b)
                if b != AIR && !Blocks.isLiquid(b) && b != OBSIDIAN && b != BEDROCK && b != FIRE && k != "end_stone"
                    && k != "iron_bars" && k != "end_portal" && k != "end_gateway" && Blocks.hardness[Int(b)] >= 0 {
                    w.setBlockAsync(c.x + dx, c.y + dy, c.z + dz, AIR)
                }
            } } }
        }
        walkPhase += dt * (phase == 4 ? 1 : 3)
        // Wing buffet (not while perched): knock the player away when very close. The head bites for 10 on contact.
        let headAt = pos + forward * 5 + V3(0, 2, 0)
        if phase != 6 && attackCooldown <= 0 && hurt <= 0 {
            if simd_length(g.player.eye - headAt) < 2.2 {
                attackCooldown = 1
                g.hurtPlayer(10, from: headAt, cause: "was slain by Hollow Wyrm", knockback: 1, attacker: self)
            } else if dist < 6 && phase != 4 {
                attackCooldown = 1
                g.hurtPlayer(5, from: pos, cause: "was slain by Hollow Wyrm", knockback: 2, attacker: self)
            }
        }
    }

    func updateSentry(_ dt: Float, _ g: Game) {
        let target = g.player.eye
        let dist = simd_length(target - pos)
        let active = g.survival && g.alive && dist < 16 && g.world.canSee(pos + V3(0, 0.8, 0), target)
        // Peeks open now and then; stays open while attacking.
        let wantOpen: Float = active || aggro ? 1 : (sinf(walkPhase * 0.4) > 0.7 ? 0.5 : 0)
        peek += (wantOpen - peek) * min(1, dt * 3)
        walkPhase += dt
        face(target)
        if active && attackCooldown <= 0 {
            attackCooldown = Float.random(in: 1...5.5)
            let from = pos + V3(0, 1.3, 0)
            g.bullets.append(SentryBolt(from, simd_normalize(target - from) * 4))
            g.sfx(.fireball, 0.3, at: from)
        }
    }

    func updateCrystal(_ dt: Float, _ g: Game) {
        walkPhase += dt * 2
        if health <= 0 && health > -1000 {
            health = -1000
            // Destroying the crystal that is healing the dragon hurts it.
            for d in g.mobs.mobs where d.kind == .enderDragon && d.healTarget === self && d.phase != 6 {
                d.health -= 10
                d.hurt = 0.4
                if d.health <= 0 { d.health = 1; d.phase = 6; d.phaseTime = 0 }
            }
            Explosion.explode(at: pos + V3(0, 1, 0), power: 6, game: g)
        }
    }
}
