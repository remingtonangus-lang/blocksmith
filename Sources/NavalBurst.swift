import Foundation
import simd

// Nov 14 (Remington: "we need some sick explosions from the naval guns so ensure that. There are a bit lack lister
// right now"; ledger 122). A naval shell (a ship's naval or heavy turret, a base's deck gun) burst as any grenade does:
// Explosion.explode's 21 small orange puffs and 42 grey ones for half a second, and a 0.45 s light. The Tidebreaker's
// strike had a look of its own (MainGun.mainGunFireball); the guns he meets and fires most had none. A naval shell's
// burst is now built in layers, all there on the frame of the blast (P465: no waiting for it to form):
//   a white-hot heart for a tenth of a second, a fireball graded from yellow at the heart to deep red at its edge that
//   rolls up and out, sparks flung far that arc down and bounce, a ring of dust racing out over the ground (white
//   spray and a column of water over the sea), pieces of what was struck thrown out of the hole, soot at the skirt and
//   a smoke column that stands for six seconds, a hard white flash and then a long orange light on everything round it.
// The cost is bounded: one burst is about 200 particles (the pool holds 2,000); with the pool past half full, or within a
// quarter second of the last one, a burst is thinned to half, past three quarters to its fireball and flash alone, and a burst beyond 140 blocks is half as well.
// BS_OLDNAVALBURST=1: the grenade's burst as before.
enum NavalBurst {
    static let old = ProcessInfo.processInfo.environment["BS_OLDNAVALBURST"] == "1"
    static let shipPower: Float = 3.5              // (GunSpec2.naval and .heavy; the autocannons stay small)
    static var bursts = 0                          // (harness)
    static var lastAt = -10.0
    static var recent = 0                          // bursts in a row less than a quarter second apart
    static var lastCount = 0                       // (harness: particles the last burst added)

    static func burst(at c: V3, power: Float, along: V3?, _ g: Game) {
        if old { return }
        bursts += 1
        let ps = g.particles
        let n0 = ps.list.count
        let away = simd_length(c - g.player.pos)
        var share: Float = away > 140 ? 0.5 : 1
        if n0 > ParticleManager.cap / 2 { share *= 0.5 }
        // (a quick-firing heavy gun, his frigate's held autocannon, a broadside landing in one frame: each burst within
        // a quarter second of the one before is thinner again: half, a third, a quarter... so eight shells at once
        // make under three bursts' worth)
        if g.clock - lastAt < 0.25 { recent += 1 } else { recent = 0 }
        share /= Float(1 + recent)
        lastAt = g.clock
        // (the fireball and flash alone when the pool is nearly full, past 300 blocks, or deep in a broadside)
        let lean = n0 > ParticleManager.cap * 3 / 4 || away > 300 || recent >= 6
        let puff = ParticleManager.puffLayer
        let size = max(0.8, min(1.5, power / 3.2))             // (a deck gun's 2.4 to a heavy turret's 4)
        let w = g.world
        let bx = Int(floor(c.x)), by = Int(floor(c.y)), bz = Int(floor(c.z))
        // What is under the burst, within three blocks: ground (dust, pieces), water (spray) or nothing (an air burst).
        var struck: BlockID = AIR, groundY: Float = c.y, wet = false, grounded = false
        for dy in 0...3 {
            let b = w.block(bx, by - dy, bz)
            if b == AIR { continue }
            struck = b; wet = Blocks.isLiquid(b); grounded = true
            groundY = Float(by - dy) + 1
            break
        }
        // The shot's line: the burst throws back along it (a shell striking a wall blows out toward the gun).
        var back = V3(0, 1, 0)
        if let a = along, simd_length(a) > 1e-3 { back = simd_normalize(V3(0, 1, 0) - simd_normalize(a) * 0.7) }

        // The heart: white-hot, gone in a tenth of a second.
        for _ in 0..<5 {
            let o = V3(Rand.float(in: -1...1), Rand.float(in: -0.2...1), Rand.float(in: -1...1)) * (0.8 * size)
            ps.add(Particle(pos: c + o, vel: o * 2, life: Rand.float(in: 0.08...0.16), maxLife: 0.16, layer: puff, uv0: V2(0, 0), uvSize: 1,
                            size: Rand.float(in: 2.2...3.4) * size, gravity: 0, color: V3(1, 0.97, 0.85), collide: false, glow: true))
        }
        // The fireball: yellow at the heart, deep red at the edge, rolling up and out.
        let balls = Int(44 * share)
        for _ in 0..<balls {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: -0.15...1), Rand.float(in: -1...1)))
            let out = Rand.float(in: 0...1)
            let hot = 1 - out
            let speed = Rand.float(in: 3...9) * size
            let v: V3 = d * speed + back * 2.5
            let col = V3(1, 0.26 + 0.64 * hot, 0.06 + 0.5 * hot * hot)
            ps.add(Particle(pos: c + d * (out * 2.2 * size), vel: v, life: Rand.float(in: 0.35...1.1), maxLife: 1.1, layer: puff,
                            uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 1.1...2.6) * size * (0.7 + 0.5 * out), gravity: -2.5,
                            color: col, collide: false, glow: true))
        }
        g.addFlash(at: c + V3(0, 1, 0), color: V3(9, 8.5, 7.5), radius: 30 + power * 6, life: 0.12)
        g.addFlash(at: c + V3(0, 1.5, 0), color: V3(6, 3.4, 1.4), radius: 18 + power * 5, life: 0.9)
        g.sfx(.explodeLarge, 0.85, at: c)
        if lean { lastCount = ps.list.count - n0; return }
        if grounded && !wet { g.sfx(.debrisRain, 0.6, at: c + V3(0, 1, 0)) }

        // Sparks: flung far, arcing down, bouncing where they land.
        let sparks = Int(40 * share)
        for _ in 0..<sparks {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: 0.1...1.4), Rand.float(in: -1...1)))
            let v: V3 = d * Rand.float(in: 10...26) + back * 4
            ps.add(Particle(pos: c + d * 0.6, vel: v, life: Rand.float(in: 0.7...1.6), maxLife: 1.6, layer: ParticleManager.smokeLayer,
                            uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.07...0.14), gravity: 16,
                            color: V3(2.6, Rand.float(in: 1.3...2.0), 0.5), collide: true, glow: true))
        }
        if grounded {
            let ring = Int(30 * share)
            let base = V3(c.x, groundY + 0.4, c.z)
            if wet {
                // Over water: a ring of white spray and a column thrown up out of the sea.
                for i in 0..<ring {
                    let a = Float(i) / Float(max(1, ring)) * 2 * .pi + Rand.float(in: -0.1...0.1)
                    let d = V3(cosf(a), 0, sinf(a))
                    let v: V3 = d * Rand.float(in: 6...12) + V3(0, Rand.float(in: 1...3), 0)
                    ps.add(Particle(pos: base + d * 1.5, vel: v, life: Rand.float(in: 0.6...1.2), maxLife: 1.2, layer: puff, uv0: V2(0, 0), uvSize: 1,
                                    size: Rand.float(in: 0.7...1.5), gravity: 3, color: V3(0.92, 0.95, 0.97), collide: false))
                }
                for _ in 0..<Int(26 * share) {
                    let o = V3(Rand.float(in: -1...1), 0, Rand.float(in: -1...1)) * 1.2
                    let v = V3(o.x * 1.5, Rand.float(in: 9...22), o.z * 1.5)
                    ps.add(Particle(pos: base + o, vel: v, life: Rand.float(in: 1.0...2.0), maxLife: 2.0, layer: puff, uv0: V2(0, 0), uvSize: 1,
                                    size: Rand.float(in: 0.6...1.4), gravity: 14, color: V3(0.9, 0.94, 0.97), collide: false))
                }
            } else {
                // Dust racing out over the ground, in the ground's own shade.
                for i in 0..<ring {
                    let a = Float(i) / Float(max(1, ring)) * 2 * .pi + Rand.float(in: -0.1...0.1)
                    let d = V3(cosf(a), 0, sinf(a))
                    let v: V3 = d * Rand.float(in: 7...13) * size + V3(0, Rand.float(in: 0.3...1.2), 0)
                    let gy = Rand.float(in: 0.5...0.62)
                    ps.add(Particle(pos: base + d * 1.2, vel: v, life: Rand.float(in: 0.8...1.5), maxLife: 1.5, layer: puff, uv0: V2(0, 0), uvSize: 1,
                                    size: Rand.float(in: 0.8...1.6) * size, gravity: -0.3, color: V3(gy * 1.08, gy, gy * 0.9), collide: false))
                }
                // Pieces of what was struck, thrown out of the hole.
                let layer = Int(Blocks.tex[Int(struck) * 6 + 2])
                let tinted = Blocks.tint[Int(struck)]
                let tint: V3 = tinted == 2 ? V3(0.47, 0.67, 0.18) : (tinted != 0 ? V3(0.57, 0.74, 0.35) : V3(0.85, 0.83, 0.8))
                for _ in 0..<Int(34 * share) {
                    let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: 0.5...1.8), Rand.float(in: -1...1)))
                    let v: V3 = d * Rand.float(in: 7...20) + back * 3
                    ps.add(Particle(pos: base + d * 0.8, vel: v, life: Rand.float(in: 1.6...3.0), maxLife: 3.0, layer: layer,
                                    uv0: V2(Rand.float(in: 0..<0.6), Rand.float(in: 0..<0.6)), uvSize: 0.4,
                                    size: Rand.float(in: 0.12...0.3), gravity: 18, color: tint, collide: true))
                }
            }
        }
        // Soot at the fireball's skirt, then the column that stands over the hole.
        for _ in 0..<Int(10 * share) {
            let a = Rand.float(in: 0..<(2 * .pi))
            let o = V3(cosf(a), Rand.float(in: 0...0.4), sinf(a)) * (2.4 * size)
            let gy = Rand.float(in: 0.2...0.3)
            ps.add(Particle(pos: c + o, vel: o * 0.9 + V3(0, Rand.float(in: 1...3), 0), life: Rand.float(in: 1.2...2.2), maxLife: 2.2, layer: puff,
                            uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 1.2...2.2) * size, gravity: -0.8, color: V3(gy * 1.1, gy, gy * 0.9), collide: false))
        }
        let column = Int(22 * share)
        for i in 0..<column {
            let up = Float(i) / Float(max(1, column))
            let o = V3(Rand.float(in: -1...1), 0, Rand.float(in: -1...1)) * (1.1 * size)
            let gy = Rand.float(in: 0.15...0.27)
            ps.add(Particle(pos: c + o + V3(0, 1.5 + up * 4, 0), vel: V3(o.x * 0.2, Rand.float(in: 1.5...4.5), o.z * 0.2),
                            life: Rand.float(in: 3.5...6), maxLife: 6, layer: puff, uv0: V2(0, 0), uvSize: 1,
                            size: Rand.float(in: 1.2...2.6) * size, gravity: 0.25, color: V3(gy, gy, gy), collide: false))
        }
        // Near enough, the ground shakes under him.
        let dist = simd_length(c - g.player.pos)
        if dist < 40 { g.addShake(0.35 * (1 - dist / 40) * size) }
        lastCount = ps.list.count - n0
    }

    // A naval gun firing (it was one small puff of smoke): a tongue of flame down the line of the shot, white at the
    // muzzle, a ring of flame blown out sideways round it, the powder smoke that rolls on after the shell and hangs,
    // and its light on the deck. `carry`: the gun's own speed, so the smoke of a ship under way starts with her.
    static var muzzles = 0
    static func muzzle(at m: V3, dir: V3, carry: V3, _ g: Game) {
        if old { return }
        muzzles += 1
        let ps = g.particles
        let thin = ps.list.count > ParticleManager.cap / 2 || simd_length(m - g.player.pos) > 140
        let puff = ParticleManager.puffLayer
        let ref: V3 = abs(dir.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
        let side = simd_normalize(simd_cross(dir, ref))
        let upv = simd_cross(side, dir)
        // The tongue: seven puffs down the shot's line, big and white at the muzzle, small and red at its tip.
        for i in 0..<7 {
            let k = Float(i) / 6
            let col = V3(1, 0.92 - 0.55 * k, 0.7 - 0.6 * k)
            ps.add(Particle(pos: m + dir * (0.6 + k * 5), vel: carry + dir * (6 + 10 * k), life: 0.09 + 0.1 * (1 - k), maxLife: 0.2, layer: puff,
                            uv0: V2(0, 0), uvSize: 1, size: 1.3 - 0.8 * k, gravity: 0, color: col, collide: false, glow: true))
        }
        // The ring blown out sideways at the muzzle.
        let ringN = thin ? 5 : 10
        for i in 0..<ringN {
            let a = Float(i) / Float(ringN) * 2 * .pi
            let d: V3 = side * cosf(a) + upv * sinf(a)
            ps.add(Particle(pos: m + dir * 0.5 + d * 0.4, vel: carry + d * Rand.float(in: 5...9) + dir * 2, life: Rand.float(in: 0.1...0.2), maxLife: 0.2,
                            layer: puff, uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.45...0.8), gravity: 0,
                            color: V3(1, Rand.float(in: 0.5...0.75), 0.2), collide: false, glow: true))
        }
        // Powder smoke rolling on after the shell, slowing and hanging.
        let smokeN = thin ? 6 : 14
        for _ in 0..<smokeN {
            let k = Rand.float(in: 0...1)
            let j = V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) * 0.6
            let gy = Rand.float(in: 0.55...0.75)
            ps.add(Particle(pos: m + dir * (0.8 + k * 4) + j, vel: carry * 0.5 + dir * Rand.float(in: 1...5) + j, life: Rand.float(in: 1.2...2.6), maxLife: 2.6,
                            layer: puff, uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.6...1.3), gravity: -0.4, color: V3(gy, gy, gy), collide: false))
        }
        g.addFlash(at: m + dir * 1.5, color: V3(7, 5, 2.4), radius: 22, life: 0.14)
    }
}
