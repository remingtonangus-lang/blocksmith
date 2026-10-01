import Foundation
import simd

// Rounds in flight (bullets, rockets, deck-gun shells, grenades), energy beams, and the player's gun
// state (magazine reload, aiming, recoil, spread bloom). Everything lives in flat arrays of structs.

enum SlugKind: UInt8 { case bullet, rocket, shell, grenade }

struct Slug {
    var pos: V3
    var vel: V3
    var kind: SlugKind
    var damage: Float
    var fromPlayer: Bool
    var shooter: ObjectIdentifier?
    var by: String                // death message attacker
    var life: Float
    var gravity: Float
    var power: Float = 0          // explosive rounds
    var traveled: Float = 0
    var dead = false
}

struct Beam {
    var a: V3
    var b: V3
    var life: Float
    var color: V4
    var width: Float
}

final class Armory {
    var slugs: [Slug] = []
    var beams: [Beam] = []
    // Player gun state.
    var cooldown: Float = 0
    var reload: Float = 0          // seconds left on a reload (0 = none)
    var reloadGun = -1
    var aim: Float = 0             // 0 hip ... 1 aimed down the sights
    var kick: Float = 0            // visual recoil 1 -> 0
    var recoilDebt: Float = 0      // pitch the view settles back by after firing
    var bloom: Float = 0           // extra spread from sustained fire
    var sinceShot: Float = 10
    var hitMarker: Float = 0
    var heldGun = -1
    var heldSlot = -1
    var placeCheck: Float = 0
    var lastNoise: Double = -10
    var shotsFired = 0             // harness counters
    var hits = 0

    func spawn(_ s: Slug) { if slugs.count < 600 { slugs.append(s) } }

    // The first mob along a segment (skipping the shooter, and soldiers' own side for their rounds).
    static func mobHit(_ g: Game, _ o: V3, _ d: V3, _ len: Float, shooter: ObjectIdentifier?, friendly: Bool) -> (Mob, Float)? {
        var best: (Mob, Float)?
        for m in g.mobs.mobs where m.health > 0 && m !== g.riding {
            if let sh = shooter, ObjectIdentifier(m) == sh { continue }
            if friendly && m.kind.steelhold { continue }
            if let t = m.rayHit(o, d, maxDist: len), t < (best?.1 ?? .greatestFiniteMagnitude) { best = (m, t) }
        }
        return best
    }

    // Exact distance to the first block along a segment, with the block and face normal.
    // Rounds pass through plants and other blocks without collision.
    static func blockHit(_ w: World, _ o: V3, _ d: V3, _ len: Float) -> (Float, IVec3, IVec3)? {
        var start: Float = 0
        for _ in 0..<8 {
            let from = o + d * start
            guard let b = w.raycast(from, d, maxDist: len - start) else { return nil }
            let id = w.block(b.hit.x, b.hit.y, b.hit.z)
            let c = V3(Float(b.hit.x), Float(b.hit.y), Float(b.hit.z))
            var t = Float.greatestFiniteMagnitude
            for (mn, mx) in w.selectionBoxes(id) {
                if let h = World.rayBox(from, d, c + mn, c + mx) { t = min(t, h.0) }
            }
            if t == .greatestFiniteMagnitude { t = min(len - start, simd_length(c + V3(0.5, 0.5, 0.5) - from)) }
            if !Blocks.collide[Int(id)] {
                start += t + 0.3
                if start >= len { return nil }
                continue
            }
            return start + t <= len ? (start + t, b.hit, b.normal) : nil
        }
        return nil
    }

    static func playerHit(_ g: Game, _ o: V3, _ d: V3, _ len: Float, pad: Float = 0) -> Float? {
        guard g.survival && g.alive else { return nil }
        let pp = g.player.pos
        let h = g.player.eye.y - pp.y + 0.2
        guard let r = World.rayBox(o, d, V3(pp.x - 0.3 - pad, pp.y - pad, pp.z - 0.3 - pad), V3(pp.x + 0.3 + pad, pp.y + h + pad, pp.z + 0.3 + pad)), r.0 <= len else { return nil }
        return r.0
    }

    func update(_ dt: Float, _ g: Game) {
        let w = g.world
        for i in slugs.indices {
            var s = slugs[i]
            s.life -= dt
            if s.life <= 0 {
                if s.kind == .grenade || s.kind == .rocket { detonate(s, at: s.pos, g) }
                s.dead = true; slugs[i] = s; continue
            }
            s.vel.y -= s.gravity * dt
            if s.kind == .grenade { s.vel *= expf(-0.4 * dt) }
            let step = s.vel * dt
            let len = simd_length(step)
            if len < 1e-5 { slugs[i] = s; continue }
            let dir = step / len
            var hitT = Float.greatestFiniteMagnitude
            var mob: Mob?
            var player = false
            if s.kind != .grenade {
                if !s.fromPlayer, let t = Armory.playerHit(g, s.pos, dir, len, pad: s.kind == .bullet ? 0 : 0.2) { hitT = t; player = true }
                if let h = Armory.mobHit(g, s.pos, dir, len, shooter: s.shooter, friendly: !s.fromPlayer), h.1 < hitT { hitT = h.1; mob = h.0; player = false }
            }
            let block = Armory.blockHit(w, s.pos, dir, len)
            if let b = block, b.0 < hitT {
                let at = s.pos + dir * max(0, b.0 - 0.05)
                if s.kind == .grenade {
                    // Bounce off whatever it hit, losing most of its speed.
                    let n = V3(Float(b.2.x), Float(b.2.y), Float(b.2.z))
                    s.pos = at
                    s.vel = (s.vel - n * (2 * simd_dot(s.vel, n))) * 0.4
                    if simd_length(s.vel) > 2 { g.sfx(.click, 0.5, at: at) }
                    slugs[i] = s
                    continue
                }
                s.dead = true
                slugs[i] = s
                impactBlock(s, at: at, block: b.1, normal: b.2, g)
                continue
            }
            if hitT <= len {
                let at = s.pos + dir * hitT
                s.dead = true
                slugs[i] = s
                if let m = mob { impactMob(s, m, at: at, dir: dir, g) } else if player { impactPlayer(s, at: at, dir: dir, g) }
                continue
            }
            s.pos += step
            s.traveled += len
            if s.kind == .rocket || s.kind == .shell {
                if Float.random(in: 0..<1) < dt * 40 { g.particles.smoke(at: s.pos - dir * 0.4, dark: s.kind == .shell) }
                if s.kind == .rocket && Float.random(in: 0..<1) < dt * 30 { g.particles.flame(at: s.pos - dir * 0.3) }
            }
            if s.pos.y < -80 { s.dead = true }
            slugs[i] = s
        }
        slugs.removeAll { $0.dead }
        for i in beams.indices { beams[i].life -= dt }
        beams.removeAll { $0.life <= 0 }
    }

    private func impactBlock(_ s: Slug, at: V3, block b: IVec3, normal n: IVec3, _ g: Game) {
        if s.kind == .rocket || s.kind == .shell { detonate(s, at: at, g); return }
        let w = g.world
        let id = w.block(b.x, b.y, b.z)
        // Player rounds shatter glass; everything kicks up a little dust and a spark.
        let key = Blocks.key(Blocks.groupBase[Int(id)])
        if s.fromPlayer && (key.hasSuffix("glass") || key.hasSuffix("glass_pane")) && !key.hasPrefix("tinted") && !key.hasPrefix("armored") {
            w.setBlock(b.x, b.y, b.z, AIR)
            g.sfx(.glassBreak, 0.8, at: at)
            g.particles.blockBreak(id, at: b)
            return
        }
        g.particles.dust(id, at: at + V3(Float(n.x), Float(n.y), Float(n.z)) * 0.05, count: 3, spread: 0.05)
        g.particles.add(Particle(pos: at, vel: V3(Float(n.x), Float(n.y) + 1, Float(n.z)) * 2, life: 0.12, maxLife: 0.12, layer: Int(Tex.id("smoke")),
                                 uv0: V2(0, 0), uvSize: 1, size: 0.06, gravity: 0, color: V3(1.4, 1.1, 0.5), collide: false, glow: true))
        if Float.random(in: 0..<1) < 0.3 { g.sfx(.gun(8), 0.35, at: at) }
    }

    private func impactMob(_ s: Slug, _ m: Mob, at: V3, dir: V3, _ g: Game) {
        if s.kind == .rocket || s.kind == .shell { detonate(s, at: at - dir * 0.3, g); return }
        if m.kind == .enderman && s.fromPlayer { m.teleport(g.world); return }
        var dmg = s.damage
        // Head shots: the top fifth of an upright mob takes half again.
        let head = (at.y - m.pos.y) > m.height * 0.78 && m.height > 1.2
        if head { dmg *= 1.5 }
        // Bosses shrug off most of a gun round (keeps the wyrm, the Blight and the deep stalker real fights).
        if m.kind == .enderDragon || m.kind == .wither || m.kind == .warden || m.kind == .elderGuardian { dmg *= 0.35 }
        let whole = floorf(dmg)
        let n = Int(whole) + (Float.random(in: 0..<1) < dmg - whole ? 1 : 0)
        m.hit(from: at - dir * 2, damage: max(1, n), knockback: s.kind == .bullet ? 0.25 : 0.5)
        g.particles.add(Particle(pos: at, vel: -dir * 1.5 + V3(0, 1, 0), life: 0.25, maxLife: 0.25, layer: Int(Tex.id("smoke")),
                                 uv0: V2(0, 0), uvSize: 1, size: 0.07, gravity: 6, color: V3(0.55, 0.08, 0.08), collide: false))
        if s.fromPlayer {
            m.killedByPlayer = true
            m.lootingLevel = 0
            m.provoke(g)
            hitMarker = head ? 0.3 : 0.18
            hits += 1
            if head { g.particles.crit(at: at) }
            g.sfx(.arrowHit, 0.5, at: at)
        }
    }

    private func impactPlayer(_ s: Slug, at: V3, dir: V3, _ g: Game) {
        if s.kind == .rocket || s.kind == .shell { detonate(s, at: at - dir * 0.3, g); return }
        let whole = floorf(s.damage)
        let n = Int(whole) + (Float.random(in: 0..<1) < s.damage - whole ? 1 : 0)
        g.bulletHit = true
        g.hurtPlayer(max(1, n), from: at - dir * 3, cause: "was shot by \(s.by)", knockback: 0.25, type: .projectile)
        g.bulletHit = false
    }

    func detonate(_ s: Slug, at: V3, _ g: Game) {
        if s.fromPlayer {
            for m in g.mobs.mobs where simd_length(m.pos - at) < s.power * 2 + 1 { m.killedByPlayer = true }
        }
        let shooter = s.shooter.flatMap { id in g.mobs.mobs.first { ObjectIdentifier($0) == id } }
        Explosion.explode(at: at, power: s.power, game: g, fire: false, except: shooter, breakBlocks: s.fromPlayer && s.kind == .rocket)
    }

    // Hitscan energy beam (arc lance): damages and ignites the first thing it meets.
    func beam(_ g: Game, from o: V3, dir: V3, range: Float, damage: Float, fromPlayer: Bool, shooter: Mob?, by: String) {
        var end = range
        if let b = Armory.blockHit(g.world, o, dir, range) { end = b.0 }
        var mob: Mob?
        var player = false
        if let h = Armory.mobHit(g, o, dir, end, shooter: shooter.map { ObjectIdentifier($0) }, friendly: !fromPlayer) { end = h.1; mob = h.0 }
        if !fromPlayer, let t = Armory.playerHit(g, o, dir, end) { end = t; player = true; mob = nil }
        let hit = o + dir * end
        beams.append(Beam(a: o, b: hit, life: 0.18, color: V4(0.9, 2.2, 2.6, 1), width: 0.09))
        if let m = mob {
            let boss = m.kind == .enderDragon || m.kind == .wither || m.kind == .warden || m.kind == .elderGuardian
            m.hit(from: o, damage: Int(damage * (boss ? 0.35 : 1)), knockback: 0.4)
            if !m.spec.fireImmune { m.fire = max(m.fire, 3) }
            if fromPlayer { m.killedByPlayer = true; m.provoke(g); hitMarker = 0.18; hits += 1 }
        } else if player {
            g.hurtPlayer(Int(damage), from: o, cause: "was vaporised by \(by)", knockback: 0.4, type: .projectile)
            if g.survival { g.onFire = max(g.onFire, 2) }
        }
        for _ in 0..<5 {
            g.particles.add(Particle(pos: hit, vel: V3(Float.random(in: -2...2), Float.random(in: 0...3), Float.random(in: -2...2)), life: 0.3, maxLife: 0.3,
                                     layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.05, gravity: 4, color: V3(0.7, 1.8, 2.2), collide: false, glow: true))
        }
    }

    // MARK: Rendering

    // A camera-facing glowing strip between two world points.
    static func streak(_ wr: inout EntityWriter, _ eye: V3, _ a: V3, _ b: V3, _ width: Float, _ col: V4) {
        let ra = a - eye, rb = b - eye
        let d = rb - ra
        let l = simd_length(d)
        guard l > 0.001 else { return }
        let mid = (ra + rb) * 0.5
        var side = simd_cross(d / l, simd_normalize(mid + V3(0, 1e-4, 0)))
        let sl = simd_length(side)
        side = sl > 1e-4 ? side / sl * width : V3(width, 0, 0)
        wr.quad([ra - side, rb - side, rb + side, ra + side], [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)], Int(Tex.id("smoke")), col)
    }

    func write(_ wr: inout EntityWriter, eye: V3) {
        let smoke = Int(Tex.id("smoke"))
        func streak(_ a: V3, _ b: V3, _ width: Float, _ col: V4) { Armory.streak(&wr, eye, a, b, width, col) }
        let rocketLayer = Items.has("rocket_ammo") ? (Items.texLayer(Items.id("rocket_ammo")) ?? smoke) : smoke
        for s in slugs {
            let sp = simd_length(s.vel)
            let d = sp > 0.01 ? s.vel / sp : V3(0, -1, 0)
            switch s.kind {
            case .bullet:
                let tail = min(s.traveled, min(2.5, sp * 0.02))
                if tail > 0.05 { streak(s.pos - d * tail, s.pos, 0.022, V4(2.6, 2.1, 1.1, 1)) }
            case .rocket:
                let side = simd_length(simd_cross(d, V3(0, 1, 0))) > 0.01 ? simd_normalize(simd_cross(d, V3(0, 1, 0))) : V3(1, 0, 0)
                let up = simd_cross(side, d)
                let c = s.pos - eye
                for n in [side, up] {
                    wr.quad([c - d * 0.4 - n * 0.12, c + d * 0.4 - n * 0.12, c + d * 0.4 + n * 0.12, c - d * 0.4 + n * 0.12],
                            [V2(0.1, 0.9), V2(0.9, 0.1), V2(0.95, 0.2), V2(0.2, 0.95)], rocketLayer, V4(1, 1, 1, 1))
                }
                streak(s.pos - d * 1.2, s.pos - d * 0.4, 0.08, V4(2.4, 1.3, 0.4, 1))
            case .shell, .grenade:
                let c = s.pos - eye
                let toEye = simd_normalize(-c)
                let side = simd_normalize(simd_cross(toEye, V3(0, 1, 0)) + V3(1e-4, 0, 0))
                let up = simd_cross(side, toEye)
                let big = s.kind == .shell
                wr.sprite(center: c, half: big ? 0.22 : 0.12, right: side, up: up, layer: smoke, light: 1,
                          tint: big ? V3(0.25, 0.22, 0.2) : V3(0.22, 0.3, 0.16))
                if big { streak(s.pos - d * 2, s.pos, 0.07, V4(2.0, 1.2, 0.5, 0.8)) }
            }
        }
        for b in beams {
            let k = min(1, b.life / 0.18)
            streak(b.a, b.b, b.width * k, b.color)
            streak(b.a, b.b, b.width * 0.35 * k, V4(3, 3, 3, 1))
        }
    }
}

extension MobKind {
    // The Steelhold garrison (their rounds pass through each other).
    var steelhold: Bool {
        self == .soldierRecruit || self == .soldierTrooper || self == .soldierMarksman || self == .soldierIronclad || self == .deckGun
    }
}

extension Game {
    var heldGun: Int? { Guns.index(held.item) }

    // Ammo of a kind in the inventory (creative: unlimited).
    func ammoCount(_ name: String) -> Int {
        guard survival else { return 999 }
        let id = Items.id(name)
        var n = 0
        for i in 0..<inventory.main.count where inventory.main[i].item == id { n += inventory.main[i].count }
        if inventory.offhand[0].item == id { n += inventory.offhand[0].count }
        return n
    }

    func takeAmmo(_ name: String, _ count: Int) {
        guard survival else { return }
        let id = Items.id(name)
        var left = count
        if inventory.offhand[0].item == id {
            var s = inventory.offhand[0]
            let k = min(left, s.count); s.count -= k; left -= k
            inventory.offhand[0] = s
        }
        for i in 0..<inventory.main.count where left > 0 && inventory.main[i].item == id {
            var s = inventory.main[i]
            let k = min(left, s.count); s.count -= k; left -= k
            inventory.main[i] = s
        }
    }

    @discardableResult
    func startReload(_ gi: Int) -> Bool {
        let gs = Guns.all[gi]
        guard held.tag < gs.mag, ammoCount(gs.ammo) > 0, arms.reload <= 0 else { return false }
        arms.reload = gs.reload
        arms.reloadGun = gi
        arms.aim = 0
        sfx(.gun(6), 0.8)
        return true
    }

    // Called from interact before the attack code: true when a gun is held (the click is the gun's).
    func gunInteract(_ p: PadSnapshot, _ q: PadSnapshot, fire: Bool, firePressed: Bool, aim: Bool, dt: Float) -> Bool {
        let a = arms
        guard let gi = heldGun else {
            a.reload = 0; a.aim = 0; a.heldGun = -1
            return false
        }
        let gs = Guns.all[gi]
        if a.heldGun != gi || a.heldSlot != selected {
            a.heldGun = gi; a.heldSlot = selected
            a.reload = 0
            a.cooldown = max(a.cooldown, 0.3)
        }
        a.cooldown -= dt
        let aiming = aim && a.reload <= 0 && !player.sprinting
        a.aim += ((aiming ? 1 : 0) - a.aim) * min(1, dt * 12)
        if a.reload > 0 {
            a.reload -= dt
            if a.reload <= 0 {
                var h = held
                let n = min(gs.mag - h.tag, ammoCount(gs.ammo))
                takeAmmo(gs.ammo, n)
                h.tag += n
                inventory.held = h
                a.cooldown = 0.15
            }
            return true
        }
        if input.tapped(15) || (p.x && !q.x) { startReload(gi); return true }     // R key (keycode 15) or pad X
        let trigger = gs.auto ? fire : firePressed
        guard trigger else { return true }
        if held.tag <= 0 {
            // Empty: pulling the trigger reloads (or clicks dry without ammunition).
            if !startReload(gi) && firePressed {
                sfx(.gun(7), 0.8)
                onToast?("No \(Items.def(Items.id(gs.ammo)).display)")
            }
            return true
        }
        guard a.cooldown <= 0 else { return true }
        fireHeldGun(gi)
        return true
    }

    func fireHeldGun(_ gi: Int) {
        let gs = Guns.all[gi]
        let a = arms
        let look = player.look
        let spread = gs.spread + (gs.aimSpread - gs.spread) * a.aim + a.bloom
        let muzzle = player.eye + look * 0.3
        switch gs.shot {
        case .bullet:
            for _ in 0..<gs.pellets {
                let d = Guns.scatter(look, spread)
                a.spawn(Slug(pos: muzzle, vel: d * gs.speed, kind: .bullet, damage: gs.damage, fromPlayer: true, shooter: nil, by: "Player",
                             life: gs.range / gs.speed, gravity: 1.5))
            }
        case .rocket:
            let d = Guns.scatter(look, spread)
            var s = Slug(pos: muzzle + d * 0.4, vel: d * gs.speed, kind: .rocket, damage: 0, fromPlayer: true, shooter: nil, by: "Player",
                         life: gs.range / gs.speed, gravity: 0.6)
            s.power = Guns.rocketPower
            a.spawn(s)
        case .beam:
            a.beam(self, from: muzzle, dir: Guns.scatter(look, spread), range: gs.range, damage: gs.damage, fromPlayer: true, shooter: nil, by: "Player")
        }
        var h = held
        h.tag -= 1
        inventory.held = h
        damageHeld(1)
        let k = gs.recoil * (1 - 0.45 * a.aim)
        player.pitch = min(1.55, player.pitch + k)
        player.yaw += Float.random(in: -0.4...0.4) * k
        a.recoilDebt += k * 0.65
        a.kick = 1
        a.bloom = min(gs.spread * 0.8, a.bloom + gs.spread * 0.18)
        a.cooldown = gs.interval
        a.sinceShot = 0
        a.shotsFired += 1
        sfx(.gun(gs.sound), 1)
        // Gunfire carries: Steelhold soldiers within 32 blocks come to investigate.
        if survival && clock - a.lastNoise > 0.5 {
            a.lastNoise = clock
            for m in mobs.mobs where m.kind.steelhold && m.health > 0 && simd_length(m.pos - player.pos) < 32 {
                let b = m.soldierBrain
                if !m.aggro { m.aggro = true; b.react = max(b.react, 0.8) }
                if !b.sees { b.lastSeen = player.pos; b.seenAgo = min(b.seenAgo, 1) }
            }
        }
        let right = V3(cosf(player.yaw), 0, -sinf(player.yaw))
        let flash = player.eye + look * 0.9 + right * 0.2 * (1 - a.aim) - V3(0, 0.12, 0)
        particles.add(Particle(pos: flash, vel: look * 0.5, life: 0.05, maxLife: 0.05, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                               size: gs.shot == .beam ? 0.12 : 0.16, gravity: 0, color: gs.shot == .beam ? V3(0.8, 2, 2.4) : V3(2.4, 1.7, 0.6),
                               collide: false, glow: true))
        if gs.shot == .rocket { for _ in 0..<6 { particles.smoke(at: player.eye - look * 0.6 + right * 0.2, dark: false) } }
    }

    // Per-frame: rounds in flight, recoil recovery, timers.
    func armsTick(_ dt: Float) {
        let a = arms
        a.update(dt, self)
        a.kick = max(0, a.kick - dt * 7)
        a.bloom *= expf(-5 * dt)
        a.sinceShot += dt
        a.hitMarker = max(0, a.hitMarker - dt)
        if a.sinceShot > 0.12 && a.recoilDebt > 0 {
            let r = min(a.recoilDebt, dt * 0.5)
            player.pitch -= r
            a.recoilDebt -= r
        }
        if heldGun == nil { a.recoilDebt = 0 }
        // Once a second: inside a Steelhold fortress?
        a.placeCheck -= dt
        if a.placeCheck <= 0 {
            a.placeCheck = 1
            let p = player.pos
            if dim.dim == .overworld, world.gen.structures?.structure(at: Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)), kind: "military_base") != nil {
                achieve("steelhold")
            }
        }
    }

    // FOV scale while aiming a gun.
    var gunFovScale: Float {
        guard let gi = heldGun else { return 1 }
        return 1 - (1 - Guns.all[gi].zoom) * arms.aim
    }

    // Ammo readout for the HUD: "12 / 64", red when empty, "Reloading" meanwhile.
    var gunHUD: (text: String, color: V4)? {
        guard let gi = heldGun else { return nil }
        let gs = Guns.all[gi]
        if arms.reload > 0 { return ("Reloading...", V4(1, 0.85, 0.4, 1)) }
        let reserve = survival ? "\(ammoCount(gs.ammo))" : "--"
        let n = held.tag
        return ("\(n) / \(reserve)", n == 0 ? V4(1, 0.35, 0.3, 1) : V4(1, 1, 1, 1))
    }

    // Current cone of fire for the crosshair (nil without a gun).
    var gunSpread: Float? {
        guard let gi = heldGun else { return nil }
        let gs = Guns.all[gi]
        return gs.spread + (gs.aimSpread - gs.spread) * arms.aim + arms.bloom
    }

    var sniperScoped: Bool { heldGun == Guns.sniper && arms.aim > 0.85 }

    func writeArms(_ wr: inout EntityWriter, eye: V3) {
        arms.write(&wr, eye: eye)
        writeSoldierLasers(&wr, eye: eye)
        writeCaptainBanners(&wr, eye: eye)
    }

    // Raid and patrol captains wear the omen banner on their head (reference look).
    func writeCaptainBanners(_ wr: inout EntityWriter, eye: V3) {
        let layers = Banners.ominous
        let white = Banners.colors.firstIndex(of: "white") ?? 0
        for k in [MobKind.pillager, .vindicator, .evoker, .illusioner] {
            for m in mobs.of(k) where m.captain && m.health > 0 && simd_length(m.pos - eye) < 64 {
                let l = world.lightAt(Int(floor(m.pos.x)), Int(floor(m.pos.y + 1)), Int(floor(m.pos.z)))
                let light = max(0.15, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
                let right = V3(cosf(m.yaw), 0, -sinf(m.yaw))
                let top = m.pos + V3(0, m.height + 0.55, 0) - m.forward * 0.28 - eye
                wr.bannerCloth(topLeft: top - right * 0.28, right: right * 0.56, down: V3(0, -1.0, 0), base: white, layers: layers, light: light)
            }
        }
    }
}
