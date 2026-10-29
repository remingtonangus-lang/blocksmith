import Foundation
import simd

// Small camera-facing textured quads: block-break debris, explosion smoke, hearts, crits.
struct Particle {
    var pos: V3
    var vel: V3
    var life: Float
    var maxLife: Float
    var layer: Int
    var uv0: V2           // sub-rect of the texture (0...1)
    var uvSize: Float
    var size: Float
    var gravity: Float
    var color: V3
    var collide: Bool
    var glow = false
    var follow: Mob? = nil        // R11: carried along with this mob (a cut mark stays on the body it was cut into)
    var followAt = V3.zero
}

final class ParticleManager {
    var list: [Particle] = []
    static let cap = 2000
    // Brightness of glowing particles (flames, sparks, muzzle flashes, tracers): >1 in the HDR (Fancy)
    // renderer so they bloom, 1 in Fast. Set by the renderer each frame.
    static var glowBoost: Float = 1
    // Active light flashes (explosions, muzzle flashes...) so smoke near them is lit, set by the renderer.
    static var flashes: [LightFlash] = []

    func add(_ p: Particle) { if list.count < ParticleManager.cap { list.append(p) } }

    func blockBreak(_ b: BlockID, at p: IVec3) {
        let layer = Int(Blocks.tex[Int(b) * 6 + 2])
        let tint: V3 = Blocks.tint[Int(b)] == 2 ? V3(0.47, 0.67, 0.18) : (Blocks.tint[Int(b)] != 0 ? V3(0.57, 0.74, 0.35) : V3(1, 1, 1))
        for i in 0..<3 { for j in 0..<3 { for k in 0..<3 {
            let o = V3(Float(i) + 0.5, Float(j) + 0.5, Float(k) + 0.5) / 3
            let pos = V3(Float(p.x), Float(p.y), Float(p.z)) + o
            let v = (o - V3(0.5, 0.5, 0.5)) * 4 + V3(0, 1.5, 0)
            add(Particle(pos: pos, vel: v, life: Rand.float(in: 0.4...1.0), maxLife: 1, layer: layer,
                         uv0: V2(Rand.float(in: 0..<0.75), Rand.float(in: 0..<0.75)), uvSize: 0.25, size: 0.08,
                         gravity: 16, color: tint, collide: true))
        } } }
    }

    // Small block-textured bits around the feet (landing, sprinting).
    func dust(_ b: BlockID, at c: V3, count: Int, spread: Float) {
        let layer = Int(Blocks.tex[Int(b) * 6 + 2])
        let tint: V3 = Blocks.tint[Int(b)] == 2 ? V3(0.47, 0.67, 0.18) : (Blocks.tint[Int(b)] != 0 ? V3(0.57, 0.74, 0.35) : V3(1, 1, 1))
        for _ in 0..<count {
            let d = V3(Rand.float(in: -1...1), 0, Rand.float(in: -1...1)) * spread
            add(Particle(pos: c + d + V3(0, 0.05, 0), vel: V3(d.x * 3, Rand.float(in: 1...2.5), d.z * 3), life: Rand.float(in: 0.3...0.7), maxLife: 0.7,
                         layer: layer, uv0: V2(Rand.float(in: 0..<0.75), Rand.float(in: 0..<0.75)), uvSize: 0.25, size: 0.06,
                         gravity: 14, color: tint, collide: true))
        }
    }

    // Pieces breaking off a struck face (progressive block damage): chunky fragments of that face's texture thrown
    // out along its normal, tumbling down; face 0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z.
    func chipBits(_ b: BlockID, at c: V3, normal n: V3, face: Int, count: Int) {
        let layer = Int(Blocks.tex[Int(b) * 6 + max(0, min(5, face))])
        let tint: V3 = Blocks.tint[Int(b)] == 2 ? V3(0.47, 0.67, 0.18) : (Blocks.tint[Int(b)] != 0 ? V3(0.57, 0.74, 0.35) : V3(1, 1, 1))
        for _ in 0..<count {
            let side = V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) * 0.35
            let jitter: V3 = side - n * simd_dot(side, n)
            let v: V3 = n * Rand.float(in: 1.5...3.5) + jitter * 4 + V3(0, Rand.float(in: 1...2.5), 0)
            add(Particle(pos: c + jitter, vel: v, life: Rand.float(in: 0.6...1.4), maxLife: 1.4, layer: layer,
                         uv0: V2(Rand.float(in: 0..<0.7), Rand.float(in: 0..<0.7)), uvSize: 0.3, size: Rand.float(in: 0.08...0.14),
                         gravity: 18, color: tint, collide: true))
        }
    }

    func explosion(at c: V3, power: Float) {
        let smoke = Int(Tex.id("smoke"))
        // Fireball: short-lived glowing orange puffs at the core (bloom in Fancy).
        // P465 (Oct 25 19:35, firing a tank in the Ash Vault: "The explosions are still taking slightly too long to form.
        // Maybe half, a quarter second too long"): the puffs started as a small knot at the centre and took their 0.2-0.45 s
        // of flight to spread to the fireball's size. They now start already spread through it, bigger with the blast,
        // and swell a little from there: the fireball is all there on the frame of the blast.
        let big = max(0.6, min(1.6, power / 4))
        for _ in 0..<Int(power * 6) {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: -0.3...1), Rand.float(in: -1...1)))
            add(Particle(pos: c + d * Rand.float(in: 0...power * 0.55), vel: d * Rand.float(in: 0.6...1.6) + V3(0, 1.2, 0),
                         life: Rand.float(in: 0.22...0.45), maxLife: 0.45, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                         size: Rand.float(in: 0.45...0.95) * big, gravity: -2, color: V3(1.0, Rand.float(in: 0.45...0.75), 0.18),
                         collide: false, glow: true))
        }
        for _ in 0..<Int(power * 12) {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)))
            let g = Rand.float(in: 0.5...1)
            add(Particle(pos: c + d * Rand.float(in: 0...power * 0.6), vel: d * Rand.float(in: 1...4) + V3(0, 1, 0),
                         life: Rand.float(in: 0.6...1.6), maxLife: 1.6, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                         size: Rand.float(in: 0.3...0.8), gravity: -1, color: V3(g, g, g), collide: false))
        }
    }

    // The puff a dead mob goes out in (MobAnim): soft pale smoke rising and spreading.
    func deathPuff(at c: V3) {
        let g = Rand.float(in: 0.78...0.95)
        add(Particle(pos: c, vel: V3(Rand.float(in: -0.6...0.6), Rand.float(in: 0.4...1.1), Rand.float(in: -0.6...0.6)),
                     life: Rand.float(in: 0.5...0.9), maxLife: 0.9, layer: Int(Tex.id("puff")), uv0: V2(0, 0), uvSize: 1,
                     size: Rand.float(in: 0.18...0.32), gravity: -0.4, color: V3(g, g, g), collide: false))
    }

    func smoke(at c: V3, dark: Bool = true) {
        let g: Float = dark ? Rand.float(in: 0.15...0.3) : Rand.float(in: 0.6...0.8)
        add(Particle(pos: c, vel: V3(Rand.float(in: -0.2...0.2), Rand.float(in: 0.5...1.2), Rand.float(in: -0.2...0.2)),
                     life: Rand.float(in: 0.5...1.2), maxLife: 1.2, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                     size: Rand.float(in: 0.08...0.18), gravity: -0.5, color: V3(g, g, g), collide: false))
    }

    // A rising bubble (torpedo and depth-charge wakes, C8).
    func bubble(at c: V3) {
        add(Particle(pos: c, vel: V3(Rand.float(in: -0.2...0.2), Rand.float(in: 0.8...1.4), Rand.float(in: -0.2...0.2)),
                     life: Rand.float(in: 0.4...0.9), maxLife: 0.9, layer: Int(Tex.id("puff")), uv0: V2(0, 0), uvSize: 1,
                     size: Rand.float(in: 0.06...0.12), gravity: -0.6, color: V3(0.75, 0.88, 1), collide: false))
    }

    func flame(at c: V3) {
        add(Particle(pos: c, vel: V3(Rand.float(in: -0.1...0.1), Rand.float(in: 0.1...0.4), Rand.float(in: -0.1...0.1)),
                     life: Rand.float(in: 0.3...0.6), maxLife: 0.6, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                     size: Rand.float(in: 0.06...0.12), gravity: -0.3, color: V3(1, 0.62, 0.2), collide: false, glow: true))
    }

    func hearts(at c: V3) {
        let heart = Int(Tex.id("heart"))
        for _ in 0..<5 {
            add(Particle(pos: c + V3(Rand.float(in: -0.4...0.4), Rand.float(in: 0...0.4), Rand.float(in: -0.4...0.4)),
                         vel: V3(0, 1, 0), life: 1.2, maxLife: 1.2, layer: heart, uv0: V2(0, 0), uvSize: 1, size: 0.15,
                         gravity: 0, color: V3(1, 1, 1), collide: false))
        }
    }

    func crit(at c: V3) {
        let smoke = Int(Tex.id("smoke"))
        for _ in 0..<10 {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: 0...1), Rand.float(in: -1...1)))
            add(Particle(pos: c, vel: d * 4, life: 0.5, maxLife: 0.5, layer: smoke, uv0: V2(0, 0), uvSize: 1, size: 0.08,
                         gravity: 8, color: V3(0.9, 0.9, 0.6), collide: false))
        }
    }

    // Blade contact (Game.bladeFlash): a white-hot burst at the point of contact and fast short sparks thrown along the
    // swing, glowing (bloom in Fancy), over in a quarter second: brighter and quicker than the crit dust.
    func bladeSpark(at c: V3, along dir: V3, power: Float) {
        let smoke = Int(Tex.id("smoke"))
        add(Particle(pos: c, vel: .zero, life: 0.09, maxLife: 0.09, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                     size: 0.22 + 0.12 * power, gravity: 0, color: V3(1, 0.96, 0.82), collide: false, glow: true))
        let n = 6 + Int(power * 6)
        for _ in 0..<n {
            let r = V3(Rand.float(in: -1...1), Rand.float(in: -0.4...1), Rand.float(in: -1...1))
            let d = simd_normalize(dir * 1.4 + r + V3(0, 1e-4, 0))
            add(Particle(pos: c, vel: d * Rand.float(in: 4...8), life: Rand.float(in: 0.12...0.26), maxLife: 0.26, layer: smoke,
                         uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.03...0.05), gravity: 10,
                         color: V3(1, Rand.float(in: 0.75...0.95), 0.45), collide: false, glow: true))
        }
    }

    // The mark a blade leaves where it hit (VRMelee, Oct 11 playtest P16): a red streak along the swing across the
    // contact point, lingering a second, drawn a little toward the viewer so it sits on the mob's surface.
    func slashMark(at c: V3, along dir: V3, toward eye: V3, power: Float, on mob: Mob? = nil) {
        let smoke = Int(Tex.id("smoke"))
        let d = simd_normalize(dir + V3(0, 1e-4, 0)), out = simd_normalize(eye - c + V3(0, 1e-4, 0))
        let n = 9, len: Float = 0.3 + 0.25 * power
        for i in 0..<n {
            let t = Float(i) / Float(n - 1) - 0.5
            let w: Float = 1 - abs(t) * 1.2                     // thick in the middle, tapering to the ends
            // R11 (Oct 13: "the red hit mark should stay on the target"): it rides on the mob it was cut into, for 2.5 s.
            add(Particle(pos: c + d * (t * len) + out * 0.06, vel: V3(0, mob == nil ? -0.04 : 0, 0), life: mob == nil ? 1.1 : 2.5, maxLife: mob == nil ? 1.1 : 2.5,
                         layer: smoke, uv0: V2(0, 0), uvSize: 1, size: 0.05 + 0.04 * w, gravity: 0, color: V3(0.75, 0.04, 0.03), collide: false, glow: false,
                         follow: mob, followAt: mob?.pos ?? .zero))
        }
    }

    func update(_ dt: Float, _ w: World) {
        let ships = w.ships.any                    // (debris settles on ship decks too: P70)
        let field = w.fieldTerrain                 // (P377 step 2: on the drawn ground, not its cells)
        for i in list.indices {
            list[i].life -= dt
            list[i].vel.y -= list[i].gravity * dt
            var np = list[i].pos + list[i].vel * dt
            if let m = list[i].follow {
                if m.health <= 0 && m.deathT > 1 { list[i].follow = nil } else { np += m.pos - list[i].followAt; list[i].followAt = m.pos }
            }
            if list[i].collide && (Blocks.collide[Int(w.builtBlock(Int(floor(np.x)), Int(floor(np.y)), Int(floor(np.z))))] || (field && w.fieldDensity(at: np) > 0) || (ships && w.ships.solid(at: np))) {
                list[i].vel = V3(list[i].vel.x * 0.3, 0, list[i].vel.z * 0.3)
                np = list[i].pos
            }
            list[i].pos = np
        }
        list.removeAll { $0.life <= 0 }
    }

    func write(_ wr: inout EntityWriter, eye: V3, right: V3, up: V3, world: World, daylight: Float) {
        let amb = world.dim.ambient
        for p in list {
            let c = p.pos - eye
            let l = world.lightAt(Int(floor(p.pos.x)), Int(floor(p.pos.y)), Int(floor(p.pos.z)))
            // Same dimension ambient lift as terrain (Emberdeep ash would otherwise be black).
            let base = max(0.15, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            var light = p.glow ? ParticleManager.glowBoost : base + (1 - base) * amb
            if !p.glow {
                for f in ParticleManager.flashes {
                    let d = simd_length(f.pos - p.pos)
                    if d < f.radius {
                        let k = max(0, f.life / f.maxLife), a = 1 - d / f.radius
                        light += (f.color.x + f.color.y + f.color.z) / 3 * a * a * k * k * 0.6
                    }
                }
            }
            let s = p.size
            let r = right * s, u = up * s
            let a = p.uv0, b = p.uv0 + V2(p.uvSize, p.uvSize)
            wr.quad4(c - r - u, c + r - u, c + r + u, c - r + u, V2(a.x, b.y), V2(b.x, b.y), V2(b.x, a.y), V2(a.x, a.y),
                     p.layer, V4(p.color * light, 1))
        }
    }
}
