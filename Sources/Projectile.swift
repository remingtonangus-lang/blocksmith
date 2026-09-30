import Foundation
import simd

// Arrows (player bow and skeletons): gravity + drag, stick into blocks, hit mobs or the player.
final class Arrow {
    var pos: V3
    var vel: V3
    let fromPlayer: Bool
    let damage: Float
    var stuck = false
    var age: Float = 0
    var dead = false
    init(_ p: V3, _ v: V3, fromPlayer: Bool, damage: Float) { pos = p; vel = v; self.fromPlayer = fromPlayer; self.damage = damage }
}

// Ghast (big, explosive) and blaze (small, incendiary) fireballs: straight flight, can be punched back.
final class Fireball {
    var pos: V3
    var vel: V3
    let big: Bool
    var byPlayer: Bool
    var age: Float = 0
    var dead = false
    init(_ p: V3, _ v: V3, big: Bool, byPlayer: Bool) { pos = p; vel = v; self.big = big; self.byPlayer = byPlayer }
}

final class ProjectileManager {
    var arrows: [Arrow] = []
    var fireballs: [Fireball] = []

    func fireball(from p: V3, dir: V3, big: Bool, byPlayer: Bool) {
        fireballs.append(Fireball(p, dir * (big ? 18 : 22), big: big, byPlayer: byPlayer))
    }

    // Player punch: deflect the first fireball along the look ray.
    func deflect(from o: V3, look d: V3) -> Bool {
        for f in fireballs {
            let r: Float = f.big ? 0.6 : 0.3
            if World.rayBox(o, d, f.pos - V3(r, r, r), f.pos + V3(r, r, r)).map({ $0.0 < 4 }) ?? false {
                f.vel = d * simd_length(f.vel)
                f.byPlayer = true
                return true
            }
        }
        return false
    }

    private func updateFireballs(_ dt: Float, game g: Game) {
        let w = g.world
        for f in fireballs {
            f.age += dt
            if f.age > 10 { f.dead = true; continue }
            let step = f.vel * dt
            let len = simd_length(step)
            let dir = step / max(len, 1e-5)
            let r: Float = f.big ? 0.5 : 0.15
            var hitT = Float.greatestFiniteMagnitude
            var hitMob: Mob?
            var hitPlayer = false
            if !f.byPlayer {
                let pp = g.player.pos
                if let h = World.rayBox(f.pos, dir, V3(pp.x - 0.3 - r, pp.y - r, pp.z - 0.3 - r), V3(pp.x + 0.3 + r, pp.y + 1.8 + r, pp.z + 0.3 + r)), h.0 <= len {
                    hitT = h.0; hitPlayer = true
                }
            }
            if let h = g.mobs.raycast(f.pos, dir, maxDist: len), h.1 < hitT, f.byPlayer || (h.0.kind != .blaze && h.0.kind != .ghast) {
                hitT = h.1; hitMob = h.0; hitPlayer = false
            }
            var blockT = Float.greatestFiniteMagnitude
            var blockHit: (hit: IVec3, normal: IVec3)?
            if let b = w.raycast(f.pos, dir, maxDist: len) {
                let o = V3(Float(b.hit.x), Float(b.hit.y), Float(b.hit.z))
                for (mn, mx) in w.selectionBoxes(w.block(b.hit.x, b.hit.y, b.hit.z)) {
                    if let h = World.rayBox(f.pos, dir, o + mn, o + mx) { blockT = min(blockT, h.0) }
                }
                if blockT == .greatestFiniteMagnitude { blockT = len }
                blockHit = (b.hit, b.normal)
            }
            if min(hitT, blockT) <= len {
                let at = f.pos + dir * min(hitT, blockT)
                f.dead = true
                if hitPlayer {
                    g.hurtPlayer(f.big ? 6 : 5, from: f.pos, cause: f.big ? "was fireballed by Ghast" : "was fireballed by Blaze")
                    if !f.big { g.onFire = max(g.onFire, 5) }
                } else if let m = hitMob {
                    m.hit(from: f.pos, damage: f.big && f.byPlayer && m.kind == .ghast ? 1000 : (f.big ? 6 : 5), knockback: 0.5)
                    if f.byPlayer { m.killedByPlayer = true }
                    if !f.big && !m.spec.fireImmune { m.fire = max(m.fire, 5) }
                }
                if f.big {
                    Explosion.explode(at: at, power: 1, game: g, fire: true)
                } else if let b = blockHit {
                    w.placeFire(b.hit + b.normal)
                }
                continue
            }
            f.pos += step
            if Float.random(in: 0..<1) < dt * 30 { g.particles.smoke(at: f.pos) }
        }
        fireballs.removeAll { $0.dead }
    }

    func shoot(from p: V3, dir: V3, speed: Float, fromPlayer: Bool, damage: Float) {
        let spread: Float = fromPlayer ? 0.0075 : 0.03
        let d = simd_normalize(dir + V3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * spread)
        arrows.append(Arrow(p, d * speed, fromPlayer: fromPlayer, damage: damage))
    }

    func update(_ dt: Float, game g: Game) {
        let w = g.world
        updateFireballs(dt, game: g)
        for a in arrows {
            a.age += dt
            if a.stuck {
                if a.age > 60 { a.dead = true }
                // Player picks up their own stuck arrows.
                if a.fromPlayer && simd_length(a.pos - (g.player.pos + V3(0, 0.9, 0))) < 1.4 {
                    let rest = g.inventory.add(ItemStack(Items.id("arrow"), 1))
                    if rest.isEmpty || !g.survival { a.dead = true; g.sfx(.pickup, 0.4) }
                }
                continue
            }
            a.vel.y -= 20 * dt
            a.vel *= expf(-0.2 * dt)
            let step = a.vel * dt
            let len = simd_length(step)
            if len < 1e-5 { continue }
            let dir = step / len
            // Entities first (whatever is closer along this step wins).
            var hitT = Float.greatestFiniteMagnitude
            var hitMob: Mob?
            var hitPlayer = false
            if a.fromPlayer {
                if let h = g.mobs.raycast(a.pos, dir, maxDist: len) { hitT = h.1; hitMob = h.0 }
            } else {
                let pp = g.player.pos
                if let h = World.rayBox(a.pos, dir, V3(pp.x - 0.3, pp.y, pp.z - 0.3), V3(pp.x + 0.3, pp.y + 1.8, pp.z + 0.3)), h.0 <= len {
                    hitT = h.0; hitPlayer = true
                }
                if let h = g.mobs.raycast(a.pos, dir, maxDist: len), h.1 < hitT, h.1 > 0.3 { hitT = h.1; hitMob = h.0; hitPlayer = false }
            }
            var blockT = Float.greatestFiniteMagnitude
            if let b = w.raycast(a.pos, dir, maxDist: len) {
                let o = V3(Float(b.hit.x), Float(b.hit.y), Float(b.hit.z))
                for (mn, mx) in w.selectionBoxes(w.block(b.hit.x, b.hit.y, b.hit.z)) {
                    if let h = World.rayBox(a.pos, dir, o + mn, o + mx) { blockT = min(blockT, h.0) }
                }
                if blockT == .greatestFiniteMagnitude { blockT = len }
            }
            if hitT < blockT {
                let speedPerTick = simd_length(a.vel) / 20
                var dmg = Int(ceilf(speedPerTick * a.damage))
                if a.fromPlayer && Float.random(in: 0..<1) < 0.25 { dmg += Int.random(in: 0...(dmg / 2 + 1)) }
                if let m = hitMob {
                    m.hit(from: a.pos, damage: dmg, knockback: 0.6)
                    if a.fromPlayer { m.killedByPlayer = true; m.provoke(g) }
                    g.sfx(.arrowHit, 0.7, at: a.pos)
                } else if hitPlayer {
                    g.hurtPlayer(dmg, from: a.pos, cause: "was shot by Skeleton")
                }
                a.dead = true
            } else if blockT <= len {
                a.pos += dir * max(0, blockT - 0.05)
                a.stuck = true
                a.age = 0
                g.sfx(.arrowHit, 0.5, at: a.pos)
            } else {
                a.pos += step
            }
            if a.pos.y < -64 { a.dead = true }
        }
        arrows.removeAll { $0.dead }
    }

    func write(_ wr: inout EntityWriter, eye: V3, world: World, daylight: Float) {
        let fl = Items.texLayer(Items.id("fire_charge")) ?? 0
        for f in fireballs {
            let c = f.pos - eye
            let toEye = simd_normalize(-c)
            let side = simd_normalize(simd_cross(toEye, V3(0, 1, 0)) + V3(1e-4, 0, 0))
            let up = simd_cross(side, toEye)
            wr.sprite(center: c, half: f.big ? 0.5 : 0.16, right: side, up: up, layer: fl, light: 1, tint: V3(1.6, 1.1, 0.6))
        }
        let layer = Items.texLayer(Items.id("arrow")) ?? 0
        for a in arrows {
            let d = simd_length(a.vel) > 0.1 ? simd_normalize(a.vel) : V3(0, -1, 0)
            let side = simd_length(simd_cross(d, V3(0, 1, 0))) > 0.01 ? simd_normalize(simd_cross(d, V3(0, 1, 0))) : V3(1, 0, 0)
            let up = simd_cross(side, d)
            let c = a.pos - eye
            let l = world.lightAt(Int(floor(a.pos.x)), Int(floor(a.pos.y)), Int(floor(a.pos.z)))
            let light = max(0.1, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            // Two crossed quads along the flight direction; the sprite's diagonal is the shaft.
            let half: Float = 0.35
            for n in [side, up] {
                let tip = c + d * half, tail = c - d * half
                wr.quad([tail - n * 0.1, tip - n * 0.1, tip + n * 0.1, tail + n * 0.1],
                        [V2(0.1, 0.9), V2(0.9, 0.1), V2(0.95, 0.2), V2(0.2, 0.95)], layer, V4(light, light, light, 1))
            }
        }
    }
}
