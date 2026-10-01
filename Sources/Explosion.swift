import Foundation
import simd

// Explosions like the reference game: 16x16x16 rays from the centre lose strength by each block's
// blast resistance; blocks the rays get through are destroyed (dropping with chance 1/power);
// entities take damage scaled by distance and exposure and are knocked back.
enum Explosion {
    static func explode(at c: V3, power: Float, game g: Game, fire: Bool = false, except: Mob? = nil, breakBlocks: Bool = true) {
        let w = g.world
        w.ships.blast(at: c, power: power, game: g)          // ship blocks (ShipCombat.swift)
        var destroyed = Set<IVec3>()
        for i in 0..<16 { for j in 0..<16 { for k in 0..<16 {
            if !(i == 0 || i == 15 || j == 0 || j == 15 || k == 0 || k == 15) { continue }
            var d = V3(Float(i) / 15 * 2 - 1, Float(j) / 15 * 2 - 1, Float(k) / 15 * 2 - 1)
            d = simd_normalize(d)
            var intensity = power * (0.7 + Float.random(in: 0..<0.6))
            var p = c
            while intensity > 0 {
                let b = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                let id = w.block(b.x, b.y, b.z)
                if id != AIR {
                    let fluid = Blocks.isLiquid(id)
                    let res = fluid ? 100 : Blocks.resistance[Int(id)]
                    intensity -= (res + 0.3) * 0.3
                    if intensity > 0 && !fluid && b.y >= 0 && b.y < CH && breakBlocks { destroyed.insert(b) }
                }
                p += d * 0.3
                intensity -= 0.225
            }
        } } }
        var tnt: [IVec3] = []
        let tntID = Blocks.id("tnt")
        for b in destroyed {
            let id = w.block(b.x, b.y, b.z)
            if id == tntID { tnt.append(b); w.setBlockAsync(b.x, b.y, b.z, AIR); continue }
            if Float.random(in: 0..<1) < 1 / power {
                for s in Mining.drops(id, ItemStack(Items.id("netherite_pickaxe"), 1)) {
                    g.drops.spawn(s, at: V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5))
                }
            }
            if let be = w.blockEntities.removeValue(forKey: b) {
                for s in be.container.slots where !s.isEmpty { g.drops.spawn(s, at: V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5)) }
            }
            w.setBlockAsync(b.x, b.y, b.z, AIR)
        }
        for b in destroyed { w.scheduleFluid(around: b) }
        for b in tnt { g.tnts.prime(at: b, fuse: Float.random(in: 0.5...1.5)) }

        // Entities.
        let radius = power * 2
        func impact(_ p: V3, _ height: Float) -> (Float, V3)? {
            let center = p + V3(0, height * 0.5, 0)
            let d = simd_length(center - c)
            if d > radius { return nil }
            let exposure: Float = w.canSee(c, center) ? 1 : (w.canSee(c, p + V3(0, height, 0)) ? 0.5 : 0)
            let k = (1 - d / radius) * exposure
            let dir = d > 0.01 ? (center - c) / d : V3(0, 1, 0)
            return (k, dir)
        }
        if let im = impact(g.player.pos, 1.8), im.0 > 0 {
            let (k, dir) = im
            let dmg = Int(((k * k + k) / 2 * 7 * radius + 1).rounded())
            g.hurtPlayer(dmg, from: c, cause: "blew up", knockback: 0, type: .explosion)
            g.player.vel += dir * k * 12
        }
        for m in g.mobs.mobs where m !== except {
            if let im = impact(m.pos, m.height), im.0 > 0 {
                let (k, dir) = im
                m.hit(from: c, damage: Int(((k * k + k) / 2 * 7 * radius + 1).rounded()), knockback: 0)
                m.vel += dir * k * 12
            }
        }
        for it in g.drops.items {
            if let im = impact(it.pos, 0.25), im.0 > 0 {
                let (k, dir) = im
                if Float.random(in: 0..<1) < k * 0.5 { it.stack = .empty } else { it.vel += dir * k * 10 }
            }
        }
        // Grenade-sized blasts crack, TNT-sized ones boom, big ones (charged hissers, shells, beds) shake the ground.
        g.sfx(power < 2.5 ? .explodeSmall : (power >= 5 ? .explodeLarge : .explode), 1, at: c)
        if power >= 3 && breakBlocks { g.sfx(.debrisRain, 0.7, at: c + V3(0, 1, 0)) }
        g.particles.explosion(at: c, power: power)
        g.addFlash(at: c + V3(0, 0.5, 0), color: V3(6, 3.6, 1.6) * min(2, power / 3), radius: 6 + power * 2.5, life: 0.45)
    }
}

// Primed TNT: falls, flashes, explodes (power 4) after its fuse.
final class PrimedTNT {
    var pos: V3
    var vel = V3(0, 3, 0)
    var fuse: Float
    var hissed = false
    init(_ p: V3, fuse: Float) { pos = p; self.fuse = fuse }
}

final class TNTManager {
    var list: [PrimedTNT] = []

    func prime(at b: IVec3, fuse: Float = 4) {
        let t = PrimedTNT(V3(Float(b.x) + 0.5, Float(b.y), Float(b.z) + 0.5), fuse: fuse)
        t.vel = V3(Float.random(in: -0.4...0.4), 4, Float.random(in: -0.4...0.4))
        list.append(t)
    }

    func update(_ dt: Float, game g: Game) {
        var boom: [V3] = []
        for t in list {
            if !t.hissed { t.hissed = true; g.sfx(.tntFuse, 1, at: t.pos + V3(0, 0.5, 0)) }
            t.fuse -= dt
            t.vel.y -= 16 * dt
            t.vel.x *= expf(-2 * dt); t.vel.z *= expf(-2 * dt)
            let hit = g.world.moveBody(&t.pos, halfW: 0.49, height: 0.98, t.vel * dt, step: 0, onGround: false)
            if hit.y { t.vel.y = 0 }
            if hit.x { t.vel.x = 0 }
            if hit.z { t.vel.z = 0 }
            if t.fuse <= 0 { boom.append(t.pos + V3(0, 0.49, 0)) }
        }
        list.removeAll { $0.fuse <= 0 }
        for p in boom { Explosion.explode(at: p, power: 4, game: g) }
    }

    func write(_ wr: inout EntityWriter, eye: V3, world: World, daylight: Float) {
        let tnt = Blocks.id("tnt")
        for t in list {
            let flash = Int(t.fuse * 5) % 2 == 0
            let s: Float = t.fuse < 0.5 ? 1 + (0.5 - t.fuse) * 0.3 : 1
            let l = world.lightAt(Int(floor(t.pos.x)), Int(floor(t.pos.y + 0.5)), Int(floor(t.pos.z)))
            let light = flash ? 1.6 : max(0.1, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            wr.cube(center: t.pos + V3(0, 0.5, 0) - eye, half: 0.5 * s, yaw: 0, block: tnt, light: light)
        }
    }
}
