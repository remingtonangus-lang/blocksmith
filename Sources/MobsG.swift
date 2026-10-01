import Foundation
import simd

// The Blight, golems built from blocks, outlaws (conjurer + vexes, siegebeast), zombie villagers and
// thrown items (snowballs, eggs, void pearls, blight skulls).

// Conjurer fangs: bite 0.5 s after appearing (6 damage, magic).
struct Fang { var pos: V3; var delay: Float; var life: Float = 1.1; var bit = false; weak var owner: Mob? }

extension Game {
    // MARK: Summoning

    // Blight: ghost sand/soil T with three blight skeleton skulls on top (either axis).
    func trySummonBlight(_ p: IVec3) {
        let skull = Blocks.id("wither_skeleton_skull")
        func isSkull(_ q: IVec3) -> Bool { Blocks.groupBase[Int(world.block(q.x, q.y, q.z))] == skull }
        func isSoul(_ q: IVec3) -> Bool { let k = Blocks.key(world.block(q.x, q.y, q.z)); return k == "soul_sand" || k == "soul_soil" }
        func clear(_ q: IVec3) -> Bool { let b = world.block(q.x, q.y, q.z); return b == AIR || Blocks.replaceable[Int(b)] }
        for axis in [IVec3(1, 0, 0), IVec3(0, 0, 1)] {
            for o in -2...0 {
                let s = (0..<3).map { k in p + IVec3(axis.x * (o + k), 0, axis.z * (o + k)) }
                guard s.allSatisfy(isSkull), s.allSatisfy({ isSoul($0 - IVec3(0, 1, 0)) }) else { continue }
                let mid = s[1] - IVec3(0, 2, 0)
                guard isSoul(mid), clear(s[0] - IVec3(0, 2, 0)), clear(s[2] - IVec3(0, 2, 0)) else { continue }
                for q in s { world.setBlock(q.x, q.y, q.z, AIR); world.setBlock(q.x, q.y - 1, q.z, AIR) }
                world.setBlock(mid.x, mid.y, mid.z, AIR)
                let w = Mob(.wither, at: V3(Float(mid.x) + 0.5, Float(mid.y), Float(mid.z) + 0.5))
                w.phase = 1
                w.phaseTime = 11
                achieve("summon_wither")
                w.health = 100
                w.persistent = true
                mobs.mobs.append(w)
                sfx(.witherSpawn, 1.5, at: w.pos)
                onToast?("The Blight has awoken")
                return
            }
        }
    }

    // Iron golem: T of four iron blocks + carved pumpkin; snow golem: two snow blocks + pumpkin.
    func trySummonGolem(_ p: IVec3) {
        let below = IVec3(p.x, p.y - 1, p.z), below2 = IVec3(p.x, p.y - 2, p.z)
        func key(_ q: IVec3) -> String { Blocks.key(world.block(q.x, q.y, q.z)) }
        if key(below) == "snow_block" && key(below2) == "snow_block" {
            for q in [p, below, below2] { world.setBlock(q.x, q.y, q.z, AIR) }
            let g = Mob(.snowGolem, at: V3(Float(p.x) + 0.5, Float(below2.y), Float(p.z) + 0.5))
            g.persistent = true
            mobs.mobs.append(g)
            particles.explosion(at: g.pos + V3(0, 1, 0), power: 0.3)
            return
        }
        guard key(below) == "iron_block" && key(below2) == "iron_block" else { return }
        for axis in [IVec3(1, 0, 0), IVec3(0, 0, 1)] {
            let a = below + axis, b = below - axis
            guard key(a) == "iron_block" && key(b) == "iron_block" else { continue }
            for q in [p, below, below2, a, b] { world.setBlock(q.x, q.y, q.z, AIR) }
            let g = Mob(.ironGolem, at: V3(Float(p.x) + 0.5, Float(below2.y), Float(p.z) + 0.5))
            g.persistent = true
            g.playerBuilt = true
            achieve("iron_golem")
            mobs.mobs.append(g)
            particles.explosion(at: g.pos + V3(0, 1.5, 0), power: 0.4)
            return
        }
    }

    // MARK: Thrown items

    func throwItem(_ kind: Thrown) {
        var d = player.look
        d.y += 0.05
        let f = Fireball(player.eye + player.look * 0.3, simd_normalize(d) * 30, big: false, byPlayer: true)
        f.kind = kind
        projectiles.fireballs.append(f)
        sfx(.bow, 0.4)
        consumeHeld()
        swing = 1
    }

    func thrownImpact(_ f: Fireball, at: V3, mob: Mob?, player hitP: Bool, block: (hit: IVec3, normal: IVec3)?) {
        switch f.kind {
        case .snowball:
            if let m = mob { m.hit(from: f.pos, damage: m.kind == .blaze ? 3 : 0, knockback: 0.4); if f.byPlayer { m.provoke(self) } }
            if hitP { player.vel += simd_normalize(f.vel) * 1.5 }
            particles.blockBreak(Blocks.id("snow_block"), at: IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z))))
        case .egg:
            if let m = mob { m.hit(from: f.pos, damage: 0, knockback: 0.3) }
            // 1/8 chance of a chick, and 1/32 of those four.
            if Int.random(in: 0..<8) == 0 {
                let n = Int.random(in: 0..<32) == 0 ? 4 : 1
                for _ in 0..<n {
                    let c = Mob(.chicken, at: at + V3(0, 0.1, 0))
                    c.baby = true; c.scale = 0.5
                    mobs.mobs.append(c)
                }
            }
        case .pearl:
            // Teleport to the landing point; 5 damage (fall), 5% voidmite.
            if f.byPlayer {
                var t = at
                if let b = block { t = V3(Float(b.hit.x + b.normal.x), Float(b.hit.y + b.normal.y), Float(b.hit.z + b.normal.z)) + V3(0.5, 0, 0.5) }
                player.pos = t
                player.vel = .zero
                player.airPeak = t.y
                damage(5, "fell from a high place", bypassArmor: true, type: .fall)
                sfx(.mobVoidwalker, 0.6)
                if Int.random(in: 0..<20) == 0 { mobs.mobs.append(Mob(.endermite, at: t)) }
            }
        case .witherSkull, .blueSkull:
            if hitP {
                hurtPlayer(8, from: f.pos, cause: "was shot by a Blight Skull", knockback: 0.3, type: .projectile)
                applyEffect(.wither, amp: 1, seconds: 10)
            } else if let m = mob, m.kind != .wither {
                m.hit(from: f.pos, damage: 8, knockback: 0.3)
                m.applyEffect(.wither, amp: 1, seconds: 10, game: self)
                if m.health <= 0, let w = f.shooter, w.kind == .wither { w.health = min(w.spec.health, w.health + 5) }
            }
            Explosion.explode(at: at, power: 1, game: self, except: f.shooter)
        case .fire:
            break
        case .wind:
            if let m = mob { m.hit(from: f.pos, damage: 1, knockback: 0) }
            windBurst(at: at)
        }
    }

    // MARK: Conjurer fangs

    func fangTick(_ dt: Float) {
        guard !fangs.isEmpty else { return }
        for i in fangs.indices {
            fangs[i].delay -= dt
            if fangs[i].delay > 0 { continue }
            fangs[i].life -= dt
            if !fangs[i].bit {
                fangs[i].bit = true
                let c = fangs[i].pos
                sfx(.fangs, 0.6, at: c)
                if simd_length(V2(player.pos.x - c.x, player.pos.z - c.z)) < 0.9 && abs(player.pos.y - c.y) < 1.5 {
                    hurtPlayer(6, from: c, cause: "was slain by Conjurer", knockback: 0.2, type: .magic)
                }
                for m in mobs.mobs where m !== fangs[i].owner && !m.raider && m.kind != .evoker && m.kind != .vex
                    && simd_length(V2(m.pos.x - c.x, m.pos.z - c.z)) < 0.5 + m.halfW && abs(m.pos.y - c.y) < 1.5 {
                    m.hit(from: c, damage: 6, knockback: 0.1)
                }
            }
        }
        fangs.removeAll { $0.life <= 0 }
    }

    func writeFangs(_ wr: inout EntityWriter, eye: V3) {
        guard !fangs.isEmpty else { return }
        let layer = Int(Tex.id("smoke"))
        for f in fangs where f.delay <= 0 {
            let h = min(1, (1.1 - f.life) * 6) * min(1, f.life * 4)
            let c = f.pos - eye
            for k in 0..<2 {
                let a = Float(k) * .pi / 2 + 0.4
                let r = V3(cosf(a), 0, sinf(a)) * 0.35
                wr.quad([c - r, c + r, c + r + V3(0, 0.8 * h, 0), c - r + V3(0, 0.8 * h, 0)], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)],
                        layer, V4(0.55, 0.55, 0.5, 1))
            }
        }
    }
}

extension Mob {
    // MARK: Blight

    // Phase 1: charging (11 s, invulnerable, heals to full, then a power-7 blast). Phase 0: fighting.
    func updateBlight(_ dt: Float, _ g: Game) {
        let w = g.world
        hurt = max(0, hurt - dt)
        if phase == 1 {
            phaseTime -= dt
            health = min(300, health + Int(ceilf(dt * 20 * 0.9)))
            if phaseTime <= 0 {
                phase = 0
                health = 300
                Explosion.explode(at: pos + V3(0, 1.75, 0), power: 7, game: g, except: self)
                g.sfx(.witherSpawn, 1.5, at: pos)
            }
            return
        }
        // Regenerates 1 HP a second.
        fireTick += dt
        if fireTick >= 1 { fireTick = 0; health = min(300, health + 1) }
        // Target: the player, else any living non-undead mob.
        var target: V3?
        let player = g.player.pos
        if g.survival && g.alive && simd_length(player - pos) < 48 { target = g.player.eye - V3(0, 0.4, 0) }
        if target == nil, let m = g.mobs.mobs.first(where: { !$0.undead && $0.kind != .wither && $0.health > 0 && simd_length($0.pos - pos) < 32 && $0.kind.spec.behavior != .vehicle }) {
            target = m.pos + V3(0, m.height * 0.6, 0)
        }
        let armored = health <= 150
        var goal = pos
        if let t = target {
            face(t)
            // Hover above the target (lower when armored).
            let hdir = V2(t.x - pos.x, t.z - pos.z)
            let hd = simd_length(hdir)
            let want: Float = armored ? 1 : 5
            goal = V3(pos.x, t.y + want, pos.z)
            if hd > 9 { goal.x += hdir.x / hd * 3; goal.z += hdir.y / hd * 3 }
            // Heads: the middle one fires at the target every 2 s; the side heads at random targets.
            attackCooldown -= dt
            if attackCooldown <= 0 {
                attackCooldown = armored ? 1.2 : 2
                shootSkull(at: t, g, blue: Float.random(in: 0..<1) < 0.001)
                if Float.random(in: 0..<1) < 0.5, let other = g.mobs.mobs.filter({ !$0.undead && $0.kind != .wither && simd_length($0.pos - pos) < 20 }).randomElement() {
                    shootSkull(at: other.pos + V3(0, other.height / 2, 0), g, blue: false, side: true)
                }
            }
        } else {
            circleAngle += dt * 0.3
            goal = pos + V3(cosf(circleAngle), 0, sinf(circleAngle)) * 4
        }
        let d = goal - pos
        let l = simd_length(d)
        if l > 0.2 { vel += (d / l * min(spec.speed, l * 2) - vel) * min(1, dt * 1.5) } else { vel *= expf(-3 * dt) }
        // Breaks blocks it touches after being hurt (the reference "block break counter").
        if breakTimer > 0 {
            breakTimer -= dt
            if breakTimer <= 0 {
                var broke = false
                let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
                for dy in 0...3 { for dz in -1...1 { for dx in -1...1 {
                    let q = c + IVec3(dx, dy, dz)
                    let b = w.block(q.x, q.y, q.z)
                    if b != AIR && !Blocks.isLiquid(b) && Blocks.hardness[Int(b)] >= 0 && Blocks.key(b) != "bedrock" && Blocks.key(b) != "end_portal_frame" {
                        w.setBlockAsync(q.x, q.y, q.z, AIR); broke = true
                    }
                } } }
                if broke { g.sfx(.explode, 0.5, at: pos) }
            }
        }
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: false)
        if hit.x { vel.x = 0; breakTimer = max(breakTimer, 0.01) }
        if hit.z { vel.z = 0; breakTimer = max(breakTimer, 0.01) }
        if hit.y { vel.y = 0 }
        walkPhase += dt * 2
        if Float.random(in: 0..<1) < dt * 8 { g.particles.smoke(at: pos + V3(Float.random(in: -0.6...0.6), Float.random(in: 1...3.5), Float.random(in: -0.6...0.6))) }
    }

    func shootSkull(at t: V3, _ g: Game, blue: Bool, side: Bool = false) {
        let from = pos + V3(0, 3.1, 0) + (side ? V3(cosf(yaw), 0, -sinf(yaw)) * (Bool.random() ? 1.3 : -1.3) : .zero)
        let f = Fireball(from, simd_normalize(t - from) * (blue ? 8 : 16), big: false, byPlayer: false)
        f.kind = blue ? .blueSkull : .witherSkull
        f.shooter = self
        g.projectiles.fireballs.append(f)
        g.sfx(.witherShoot, 0.8, at: from)
    }

    // MARK: Hexling

    // Flies through walls straight at the target; dies after 30-119 s.
    func updateVex(_ dt: Float, _ g: Game) {
        hurt = max(0, hurt - dt)
        attackCooldown -= dt
        age += dt
        if age > lifeSpan { health -= 1; hurt = 0.2; age -= 1 }
        var tgt: V3?
        if g.survival && g.alive && simd_length(g.player.pos - pos) < 32 { tgt = g.player.eye - V3(0, 0.6, 0) }
        if tgt == nil, let v = g.mobs.mobs.first(where: { ($0.kind == .villager || $0.kind == .ironGolem) && simd_length($0.pos - pos) < 24 }) {
            tgt = v.pos + V3(0, v.height * 0.5, 0)
        }
        if let t = tgt {
            face(t)
            let d = t - pos
            let l = simd_length(d)
            if attackCooldown <= 0 && l < 1.2 {
                attackCooldown = 1
                if simd_length(g.player.eye - V3(0, 0.6, 0) - t) < 0.01 { g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Hexling", attacker: self) }
                else if let v = g.mobs.mobs.first(where: { simd_length($0.pos + V3(0, $0.height * 0.5, 0) - t) < 0.01 }) { v.hit(from: pos, damage: spec.attack) }
            }
            vel += (d / max(l, 0.01) * spec.speed - vel) * min(1, dt * 3)
        } else {
            if aiTimer <= 0 { aiTimer = 2; flyTarget = pos + V3(Float.random(in: -6...6), Float.random(in: -2...3), Float.random(in: -6...6)) }
            aiTimer -= dt
            if let f = flyTarget { let d = f - pos; vel += (d * 0.5 - vel) * min(1, dt * 2) }
        }
        pos += vel * dt          // no collision: vexes pass through blocks
        walkPhase += dt * 12
    }

    // MARK: Conjurer

    // Keeps its distance; summons 3 vexes (every 17 s) or fangs (lines at range, circles up close).
    func aiEvoker(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        spellTimer -= dt
        guard let t = raidTarget(g) ?? (canTarget && dist < 16 ? g.player.pos : nil) else {
            // Idle conjurers turn blue sheep within 16 blocks red (reference).
            if spellTimer <= 0, let sh = g.mobs.of(.sheep).first(where: { $0.woolColor == "blue" && simd_length($0.pos - pos) < 16 }) {
                spellTimer = 5
                sh.woolColor = "red"
                g.sfx(.evokerCast, 0.8, at: pos)
            }
            wander(); return moving ? spec.speed * 0.5 : 0
        }
        face(t)
        let d = simd_length(t - pos)
        if spellTimer <= 0 {
            let vexes = g.mobs.mobs.filter { $0.kind == .vex && $0.owner != nil && simd_length($0.pos - pos) < 16 }.count
            if vexCooldown <= 0 && vexes < 8 {
                vexCooldown = 17
                spellTimer = 5
                for _ in 0..<3 {
                    let v = Mob(.vex, at: pos + V3(Float.random(in: -1...1), 1, Float.random(in: -1...1)))
                    v.lifeSpan = Float.random(in: 30...119)
                    v.owner = true
                    v.raider = raider
                    g.mobs.mobs.append(v)
                }
                g.sfx(.evokerCast, 1, at: pos)
            } else {
                spellTimer = 5
                g.sfx(.evokerCast, 0.8, at: pos)
                let ground = pos.y
                if d < 3 {
                    for i in 0..<5 {
                        let a = Float(i) * 2 * .pi / 5
                        g.fangs.append(Fang(pos: pos + V3(cosf(a) * 1.5, 0, sinf(a) * 1.5), delay: 0, owner: self))
                    }
                    for i in 0..<8 {
                        let a = Float(i) * 2 * .pi / 8 + 0.4
                        g.fangs.append(Fang(pos: pos + V3(cosf(a) * 2.5, 0, sinf(a) * 2.5), delay: 0.15, owner: self))
                    }
                } else {
                    let dir = simd_normalize(V3(t.x - pos.x, 0, t.z - pos.z))
                    for i in 0..<16 {
                        let q = pos + dir * Float(i + 1) * 1.25
                        g.fangs.append(Fang(pos: V3(q.x, ground, q.z), delay: Float(i) * 0.05, owner: self))
                    }
                }
            }
        }
        vexCooldown -= dt
        return d < 6 ? -spec.speed * 0.6 : (d > 10 ? spec.speed : 0)
    }

    // MARK: Siegebeast

    // Charges, bites (12) with big knockback, tramples leaves and crops, roars after being stunned.
    func aiRavager(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let w = g.world
        // Break leaves and crops in the way.
        let front = pos + forward * (halfW + 0.5)
        for dy in 0...2 {
            let q = IVec3(Int(floor(front.x)), Int(floor(pos.y)) + dy, Int(floor(front.z)))
            let b = w.block(q.x, q.y, q.z)
            let k = Blocks.key(Blocks.groupBase[Int(b)])
            if k.hasSuffix("_leaves") || ["wheat", "carrots", "potatoes", "beetroots"].contains(k) { w.setBlockAsync(q.x, q.y, q.z, AIR) }
        }
        if stun > 0 {
            stun -= dt
            if stun <= 0 {
                // Roar: knock everything back and hurt it.
                g.sfx(.mobRavager, 1.5, at: pos)
                if simd_length(g.player.pos - pos) < 4 { g.hurtPlayer(6, from: pos, cause: "was slain by Siegebeast", knockback: 2) }
                for m in g.mobs.mobs where m !== self && !m.raider && simd_length(m.pos - pos) < 4 { m.hit(from: pos, damage: 6, knockback: 2) }
            }
            return 0
        }
        let t = raidTarget(g) ?? (canTarget ? g.player.pos : nil)
        guard let tp = t else { wander(); return moving ? spec.speed * 0.5 : 0 }
        face(tp)
        let d = simd_length(V2(tp.x - pos.x, tp.z - pos.z))
        if d < halfW + 1.6 && attackCooldown <= 0 {
            attackCooldown = 2
            if simd_length(tp - g.player.pos) < 0.01 {
                g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Siegebeast", knockback: 2.5, attacker: self)
                if g.blocking { stun = 2 }
            } else if let m = g.mobs.mobs.first(where: { simd_length($0.pos - tp) < 0.01 }) {
                m.hit(from: pos, damage: spec.attack, knockback: 2.5)
            }
        }
        return spec.speed
    }

    // MARK: Snow golem

    func aiSnowGolem(_ dt: Float, _ g: Game, inWater: Bool) -> Float {
        let w = g.world
        let b = w.gen.column(Int(floor(pos.x)), Int(floor(pos.z))).biome
        // Melts in warm biomes, water and rain-free deserts; leaves a snow trail in cold ones.
        if inWater || b == .desert || b.isBadlands || w.dim == .nether || b == .savanna || b == .jungle {
            fireTick += dt
            if fireTick >= 1 { fireTick = 0; health -= 1; hurt = 0.2 }
        } else if onGround {
            let q = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
            if w.block(q.x, q.y, q.z) == AIR && Blocks.opaque[Int(w.block(q.x, q.y - 1, q.z))] && Blocks.has("snow") { w.setBlockAsync(q.x, q.y, q.z, Blocks.id("snow")) }
        }
        if let t = g.mobs.mobs.first(where: { $0.kind.hostile && $0.kind != .creeper && $0.health > 0 && simd_length($0.pos - pos) < 10 }) {
            face(t.pos)
            attackCooldown -= 0
            if attackCooldown <= 0 {
                attackCooldown = 1
                var d = t.pos + V3(0, t.height * 0.5, 0) - eye
                d.y += simd_length(V2(d.x, d.z)) * 0.12
                let f = Fireball(eye + forward * 0.4, simd_normalize(d) * 22, big: false, byPlayer: false)
                f.kind = .snowball
                f.shooter = self
                g.projectiles.fireballs.append(f)
            }
            return 0
        }
        wander()
        return moving ? spec.speed * 0.5 : 0
    }

    // Raiders attack villagers, golems and wandering traders before anything else.
    func raidTarget(_ g: Game) -> V3? {
        guard raider || kind == .ravager || kind == .evoker || kind == .vindicator || kind == .pillager else { return nil }
        if let v = g.mobs.mobs.filter({ ($0.kind == .villager || $0.kind == .ironGolem) && $0.health > 0 && simd_length($0.pos - pos) < (raider ? 32 : 12) })
            .min(by: { simd_length($0.pos - pos) < simd_length($1.pos - pos) }) {
            return v.pos
        }
        return nil
    }
}

// MARK: Models

func extraParts(_ m: Mob, swing: Float) -> [Part] {
    switch m.kind {
    case .wither:
        let bone = m.phase == 1 ? V3(0.35, 0.45, 0.75) : V3(0.16, 0.16, 0.17)
        let armor = m.health <= 150 && m.phase == 0
        let c = armor ? V3(0.3, 0.35, 0.5) : bone
        let tail = sinf(m.walkPhase) * 0.2
        return [
            Part(mn: V3(-1.5, 6, -1.5), mx: V3(1.5, 18, 1.5), pivot: V3(0, 18, 0), rotX: tail + 0.3, color: c, pattern: 5),
            box(-1.5, 18, -1.5, 3, 22, 3, c, 5),
            box(-5, 32, -3, 10, 2, 6, c, 5), box(-5, 28, -3, 10, 2, 6, c, 5), box(-5, 24, -3, 10, 2, 6, c, 5),
            box(-10, 40, -2, 20, 3, 4, c, 5),
            box(-4, 43, -4, 8, 8, 8, c, 5),
            box(-13, 38, -3, 6, 6, 6, c, 5), box(7, 38, -3, 6, 6, 6, c, 5),
            box(-3, 47, -4.2, 2, 2, 0.3, V3(0.9, 0.9, 0.95)), box(1, 47, -4.2, 2, 2, 0.3, V3(0.9, 0.9, 0.95)),
            box(-12, 41.5, -3.2, 1.5, 1.5, 0.3, V3(0.9, 0.9, 0.95)), box(-9.5, 41.5, -3.2, 1.5, 1.5, 0.3, V3(0.9, 0.9, 0.95)),
            box(8, 41.5, -3.2, 1.5, 1.5, 0.3, V3(0.9, 0.9, 0.95)), box(10.5, 41.5, -3.2, 1.5, 1.5, 0.3, V3(0.9, 0.9, 0.95)),
        ]
    case .snowGolem:
        let snow = V3(0.95, 0.97, 1), stick = V3(0.42, 0.3, 0.17)
        let arm = sinf(m.walkPhase) * 0.3
        return [
            box(-6, 0, -6, 12, 12, 12, snow, 2),
            box(-5, 11, -5, 10, 10, 10, snow, 2),
            box(-4, 21, -4, 8, 8, 8, m.variant == 1 ? snow : V3(0.9, 0.55, 0.12), m.variant == 1 ? 2 : 4),
            box(-2.5, 24.5, -4.2, 1.5, 1.5, 0.3, V3(0.2, 0.12, 0.05)), box(1, 24.5, -4.2, 1.5, 1.5, 0.3, V3(0.2, 0.12, 0.05)),
            box(-2, 22.5, -4.2, 4, 1, 0.3, V3(0.2, 0.12, 0.05)),
            Part(mn: V3(-13, 17, -0.5), mx: V3(-5, 18, 0.5), pivot: V3(-5, 17.5, 0), rotZ: -0.4 + arm, color: stick),
            Part(mn: V3(5, 17, -0.5), mx: V3(13, 18, 0.5), pivot: V3(5, 17.5, 0), rotZ: 0.4 - arm, color: stick),
        ]
    case .evoker, .zombieVillager:
        let ev = m.kind == .evoker
        let robe = ev ? V3(0.16, 0.16, 0.2) : V3(0.35, 0.3, 0.22), skin = ev ? V3(0.55, 0.57, 0.58) : V3(0.36, 0.55, 0.3)
        let casting = ev && m.spellTimer > 4
        let armA: Float = casting ? -2.6 : (ev ? 0 : -1.45)
        var p = [
            Part(mn: V3(-4, 0, -3), mx: V3(-0.01, 12, 3), pivot: V3(-2, 12, 0), rotX: swing, color: robe, pattern: 4),
            Part(mn: V3(0.01, 0, -3), mx: V3(4, 12, 3), pivot: V3(2, 12, 0), rotX: -swing, color: robe, pattern: 4),
            box(-4, 12, -3, 8, 12, 6, robe, 4),
            box(-4, 24, -4, 8, 10, 8, skin, 4),
            box(-1, 26, -6, 2, 4, 2, skin * 0.9),
            box(-4, 30, -4.2, 8, 1, 0.3, V3(0.2, 0.2, 0.2)),
            box(-2.5, 28.5, -4.3, 1.2, 1.2, 0.2, ev ? V3(0.2, 0.2, 0.2) : V3(0.8, 0.1, 0.1)), box(1.3, 28.5, -4.3, 1.2, 1.2, 0.2, ev ? V3(0.2, 0.2, 0.2) : V3(0.8, 0.1, 0.1)),
        ]
        if ev {
            p.append(box(-4.2, 4, -3.3, 8.4, 20, 0.3, V3(0.75, 0.6, 0.2), 4))     // gold trim
            p.append(Part(mn: V3(-6, 12, -2), mx: V3(-4, 24, 2), pivot: V3(-5, 23, 0), rotX: armA, rotZ: casting ? -0.3 : 0, color: robe, pattern: 4))
            p.append(Part(mn: V3(4, 12, -2), mx: V3(6, 24, 2), pivot: V3(5, 23, 0), rotX: armA, rotZ: casting ? 0.3 : 0, color: robe, pattern: 4))
        } else {
            p.append(Part(mn: V3(-6, 12, -2), mx: V3(-4, 24, 2), pivot: V3(-5, 23, 0), rotX: armA, color: skin, pattern: 4))
            p.append(Part(mn: V3(4, 12, -2), mx: V3(6, 24, 2), pivot: V3(5, 23, 0), rotX: armA, color: skin, pattern: 4))
        }
        return p
    case .vex:
        let body = V3(0.62, 0.68, 0.78)
        let flap = sinf(m.walkPhase) * 0.6
        return [
            box(-2, 3, -1, 4, 5, 2, body, 4),
            box(-2.5, 8, -2.5, 5, 5, 5, body, 4),
            box(-1.8, 10, -2.6, 1, 1, 0.2, V3(0.1, 0.1, 0.1)), box(0.8, 10, -2.6, 1, 1, 0.2, V3(0.1, 0.1, 0.1)),
            Part(mn: V3(-8, 5, 1), mx: V3(-1, 11, 1.3), pivot: V3(-1, 8, 1), rotZ: flap, color: V3(0.85, 0.9, 0.98)),
            Part(mn: V3(1, 5, 1), mx: V3(8, 11, 1.3), pivot: V3(1, 8, 1), rotZ: -flap, color: V3(0.85, 0.9, 0.98)),
            box(-0.5, 7, -4, 1, 1, 3, V3(0.7, 0.7, 0.75)),                                   // sword
        ]
    case .ravager:
        let hide = V3(0.36, 0.34, 0.33), horn = V3(0.78, 0.76, 0.7)
        let bite: Float = m.attackCooldown > 1.7 ? 0.4 : 0
        return [
            box(-7, 14, -10, 14, 16, 22, hide, 4),
            Part(mn: V3(-5, 16, -20), mx: V3(5, 28, -10), pivot: V3(0, 22, -10), rotX: bite, color: hide, pattern: 4),
            box(-4, 14, -19, 8, 3, 8, V3(0.25, 0.22, 0.22)),
            box(-7, 26, -16, 2, 7, 2, horn), box(5, 26, -16, 2, 7, 2, horn),
            box(-3.5, 23, -20.2, 2, 2, 0.3, V3(0.95, 0.9, 0.3)), box(1.5, 23, -20.2, 2, 2, 0.3, V3(0.95, 0.9, 0.3)),
            Part(mn: V3(-7, 0, -8), mx: V3(-2, 14, -3), pivot: V3(-4.5, 14, -5.5), rotX: swing, color: hide, pattern: 4),
            Part(mn: V3(2, 0, -8), mx: V3(7, 14, -3), pivot: V3(4.5, 14, -5.5), rotX: -swing, color: hide, pattern: 4),
            Part(mn: V3(-7, 0, 5), mx: V3(-2, 14, 10), pivot: V3(-4.5, 14, 7.5), rotX: -swing, color: hide, pattern: 4),
            Part(mn: V3(2, 0, 5), mx: V3(7, 14, 10), pivot: V3(4.5, 14, 7.5), rotX: swing, color: hide, pattern: 4),
        ]
    default:
        return []
    }
}
