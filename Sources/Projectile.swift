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
    var tip: ItemID = 0            // tipped arrow (potion effects on hit)
    var flame = false              // Flame enchantment: sets targets on fire
    var punch = 0                  // Punch enchantment: extra knockback
    var pickup = true              // Infinity arrows can't be picked up
    var pierce = 0                 // Piercing: mobs it may pass through
    var hitMobs: [ObjectIdentifier] = []
    var trident: ItemStack?        // a thrown trident (keeps its enchantments / wear)
    var returning = false          // Loyalty: flying back to the player
    init(_ p: V3, _ v: V3, fromPlayer: Bool, damage: Float) { pos = p; vel = v; self.fromPlayer = fromPlayer; self.damage = damage }
}

// What a Fireball object actually is: fire charges, wither skulls, or thrown items.
enum Thrown { case fire, witherSkull, blueSkull, snowball, egg, pearl }

// Ghast (big, explosive) and blaze (small, incendiary) fireballs: straight flight, can be punched back.
final class Fireball {
    var pos: V3
    var vel: V3
    let big: Bool
    var byPlayer: Bool
    var age: Float = 0
    var dead = false
    var dragon = false             // ender dragon fireball: leaves a cloud of acid instead of exploding
    var potion: ItemID = 0         // thrown splash / lingering potion or bottle o' enchanting (item)
    var kind: Thrown = .fire
    weak var shooter: Mob?
    init(_ p: V3, _ v: V3, big: Bool, byPlayer: Bool) { pos = p; vel = v; self.big = big; self.byPlayer = byPlayer }
}

final class ProjectileManager {
    var arrows: [Arrow] = []
    var fireballs: [Fireball] = []

    func fireball(from p: V3, dir: V3, big: Bool, byPlayer: Bool, dragon: Bool = false, potion: ItemID = 0) {
        let f = Fireball(p, dir * (potion > 0 ? 12 : (big ? 18 : 22)), big: big, byPlayer: byPlayer)
        f.dragon = dragon
        f.potion = potion
        fireballs.append(f)
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
            if f.potion > 0 || f.kind == .snowball || f.kind == .egg || f.kind == .pearl { f.vel.y -= 20 * dt; f.vel *= expf(-0.2 * dt) }
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
            if let h = g.mobs.raycast(f.pos, dir, maxDist: len), h.1 < hitT, h.0 !== f.shooter, !(f.kind == .snowball && h.0.kind == .snowGolem),
               f.byPlayer || (h.0.kind != .blaze && h.0.kind != .ghast && h.0.kind != .enderDragon && h.0.kind != .endCrystal && !(f.kind != .fire && h.0.kind == .wither)) {
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
                if f.potion > 0 {
                    g.potionImpact(f.potion, at: at, direct: hitMob, hitPlayer: hitPlayer)
                    continue
                }
                if f.kind != .fire {
                    g.thrownImpact(f, at: at, mob: hitMob, player: hitPlayer, block: blockHit)
                    continue
                }
                if hitPlayer {
                    g.hurtPlayer(f.big ? 6 : 5, from: f.pos, cause: f.big ? "was fireballed by Ghast" : "was fireballed by Blaze", type: .projectile)
                    if !f.big { g.onFire = max(g.onFire, 5) }
                } else if let m = hitMob {
                    m.hit(from: f.pos, damage: f.big && f.byPlayer && m.kind == .ghast ? 1000 : (f.big ? 6 : 5), knockback: 0.5)
                    if f.byPlayer { m.killedByPlayer = true }
                    if !f.big && !m.spec.fireImmune { m.fire = max(m.fire, 5) }
                }
                if f.dragon {
                    g.clouds.append(AcidCloud(pos: at, radius: 3, time: 8))
                } else if f.big {
                    Explosion.explode(at: at, power: 1, game: g, fire: true)
                } else if let b = blockHit {
                    w.placeFire(b.hit + b.normal)
                }
                continue
            }
            f.pos += step
            if (f.kind == .fire || f.kind == .witherSkull || f.kind == .blueSkull) && Float.random(in: 0..<1) < dt * 30 { g.particles.smoke(at: f.pos) }
        }
        fireballs.removeAll { $0.dead }
    }

    @discardableResult
    func shoot(from p: V3, dir: V3, speed: Float, fromPlayer: Bool, damage: Float) -> Arrow {
        let spread: Float = fromPlayer ? 0.0075 : 0.03
        let d = simd_normalize(dir + V3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * spread)
        let a = Arrow(p, d * speed, fromPlayer: fromPlayer, damage: damage)
        arrows.append(a)
        return a
    }

    func update(_ dt: Float, game g: Game) {
        let w = g.world
        updateFireballs(dt, game: g)
        for a in arrows {
            a.age += dt
            if a.returning, let t = a.trident {
                // Loyalty: fly back and drop into the inventory.
                let to = g.player.eye - a.pos
                let d = simd_length(to)
                let sp = 10 + 5 * Float(Enchant.level(.loyalty, t))
                a.vel = to / max(d, 0.01) * sp
                a.pos += a.vel * dt
                if d < 1.2 {
                    a.dead = true
                    if g.survival { let rest = g.inventory.add(t); if !rest.isEmpty { g.dropItem(rest) } }
                    g.sfx(.pickup, 0.5)
                }
                continue
            }
            if a.stuck {
                if let t = a.trident {
                    if Enchant.level(.loyalty, t) > 0 && a.age > 0.5 { a.returning = true; a.stuck = false; continue }
                    if simd_length(a.pos - (g.player.pos + V3(0, 0.9, 0))) < 1.4 {
                        a.dead = true
                        if g.survival { let rest = g.inventory.add(t); if !rest.isEmpty { g.dropItem(rest) } }
                        g.sfx(.pickup, 0.4)
                    }
                    continue
                }
                if a.age > 60 { a.dead = true }
                // Player picks up their own stuck arrows.
                if a.fromPlayer && simd_length(a.pos - (g.player.pos + V3(0, 0.9, 0))) < 1.4 {
                    if !a.pickup { a.dead = true; continue }
                    let rest = g.inventory.add(ItemStack(a.tip != 0 ? a.tip : Items.id("arrow"), 1))
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
                if let h = g.mobs.raycast(a.pos, dir, maxDist: len), !a.hitMobs.contains(ObjectIdentifier(h.0)) { hitT = h.1; hitMob = h.0 }
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
                    if let t = a.trident { dmg = 8 + Int(Enchant.damageBonus(t, against: m)) }
                    m.hit(from: a.pos, damage: dmg, knockback: 0.6 + 0.6 * Float(a.punch))
                    if a.trident != nil { g.tridentHit(a, mob: m) }
                    if a.fromPlayer { m.killedByPlayer = true; m.provoke(g) }
                    if a.flame && !m.spec.fireImmune { m.fire = max(m.fire, 5) }
                    if a.tip != 0 { g.arrowEffects(a.tip, onPlayer: false, mob: m) }
                    g.sfx(.arrowHit, 0.7, at: a.pos)
                } else if hitPlayer {
                    g.hurtPlayer(dmg, from: a.pos, cause: "was shot by Skeleton", type: .projectile)
                    if a.tip != 0 { g.arrowEffects(a.tip, onPlayer: true, mob: nil) }
                }
                if let m = hitMob, a.pierce > 0 {
                    a.pierce -= 1
                    a.hitMobs.append(ObjectIdentifier(m))
                    a.pos += step
                } else if a.trident != nil {
                    // Tridents bounce off and drop.
                    a.vel = V3(-a.vel.x * 0.05, 2, -a.vel.z * 0.05)
                    if let m = hitMob { a.hitMobs.append(ObjectIdentifier(m)) }
                } else {
                    a.dead = true
                }
            } else if blockT <= len {
                a.pos += dir * max(0, blockT - 0.05)
                a.stuck = true
                a.age = 0
                g.sfx(.arrowHit, 0.5, at: a.pos)
                if a.trident != nil { g.tridentHit(a, mob: nil); a.returning = false }
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
            if f.kind != .fire {
                let layer: Int
                switch f.kind {
                case .snowball: layer = Items.texLayer(Items.id("snowball")) ?? fl
                case .egg: layer = Items.texLayer(Items.id("egg")) ?? fl
                case .pearl: layer = Items.texLayer(Items.id("ender_pearl")) ?? fl
                default: layer = Int(Tex.id(f.kind == .blueSkull ? "skull_skeleton_face" : "skull_wither_face"))
                }
                let tint = f.kind == .blueSkull ? V3(0.6, 0.8, 1.4) : V3(1, 1, 1)
                wr.sprite(center: c, half: f.kind == .witherSkull || f.kind == .blueSkull ? 0.25 : 0.15, right: side, up: up, layer: layer, light: 1, tint: tint)
                continue
            }
            if f.potion > 0 {
                wr.sprite(center: c, half: 0.2, right: side, up: up, layer: Items.texLayer(f.potion) ?? fl, light: 1, tint: V3(1, 1, 1))
                if case let (ol, col)? = Items.overlayLayer(f.potion) {
                    let t = TextureGen.hex(col)
                    wr.sprite(center: c + toEye * 0.01, half: 0.2, right: side, up: up, layer: ol, light: 1, tint: V3(t.x, t.y, t.z))
                }
                continue
            }
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
            let isTrident = a.trident != nil
            let half: Float = isTrident ? 0.8 : 0.35
            let lay = isTrident ? (Items.texLayer(Items.id("trident")) ?? layer) : layer
            for n in [side, up] {
                let tip = c + d * half, tail = c - d * half
                wr.quad([tail - n * 0.1, tip - n * 0.1, tip + n * 0.1, tail + n * 0.1],
                        [V2(0.1, 0.9), V2(0.9, 0.1), V2(0.95, 0.2), V2(0.2, 0.95)], lay, V4(light, light, light, 1))
            }
        }
    }
}
