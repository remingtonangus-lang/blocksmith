import Foundation
import simd

// P252 (Oct 14 11:59, "bases need flak guns; flak and naval guns should track and hit a flying player so flying over a
// base gets you shot down, with a short warning so it's fair"):
// - (a) Flak guns (deck_gun variant 13, tag "flak"): a long single barrel on a cross-shaped platform that elevates to
//   nearly vertical and lays fast enough to follow a helicopter. Capital citadels carry two on the hall's roof garden,
//   every Greywall garrison and up one on the keep roof.
// - (b) Against a flying target (an aircraft's cabin, an airship's deck, a jetpack, glider wings) every deck gun, flak
//   or naval, leads it by the intercept of the shell's speed and drop with the target's own velocity (its craft's when
//   aboard), and fuzes the shell to burst beside it: a proximity fuze (within 3.5 blocks) and a time fuze at the
//   intercept, so a near miss still bursts by the target. Each burst near a craft's hull adds to its flak damage
//   (Ship.flakHits): at 1 the engines are dead and it comes down.
// - (c) The warning: when a gun starts tracking a flying player a warning tone sounds by the player and a toast names
//   it; the gun's first two rounds are ranging shots, red tracers that burst a few blocks off; it fires for real from
//   the third on (a second and a half after the warning at the earliest).
enum AirDefence {
    static let flakSpeed: Float = 150             // a flak shell's muzzle speed (blocks a second)
    static let flakRange: Float = 150             // flak guns reach a flying target this far, provoked or not
    static let navalAirRange: Float = 110         // other deck guns, unprovoked
    static let prox: Float = 3.5                  // the proximity fuze
    static let power: Float = 1.7                 // a flak burst (no blocks broken)
    static let flakBite: Float = 3.2              // ... and its bite on a hull beside it (P504)
    static let rangingShots = 2
    static let warnDelay: Float = 1.5

    // Whether the player is flying: in a craft clear of the ground, under a jetpack's thrust or glider wings, or off
    // the ground well above it.
    static func airborne(_ g: Game) -> Bool {
        let p = g.player
        let w = g.world
        let ground = Float(w.topY(Int(floor(p.pos.x)), Int(floor(p.pos.z))) + 1)
        let high = p.pos.y - ground
        if let s = w.ships.aboard?.root ?? w.ships.pilot?.root {
            let flies = s.flight != nil || s.balloons > 0 || s.wings.count >= 4
            return flies && s.pos.y - ground > 4
        }
        if p.gliding || p.jetThrust { return high > 3 }
        return !p.onGround && high > 8 && !p.flying
    }

    // The target's velocity: its craft's at the player when aboard, else the player's own.
    static func targetVel(_ g: Game) -> V3 {
        if let s = g.world.ships.aboard?.root ?? g.world.ships.pilot?.root { return s.velocity(at: g.player.pos) }
        return g.player.vel
    }

    // Where to point a shell of `speed` and `gravity` from `o` to meet a target at `p` moving at `v` (constant), and
    // when they meet. A few fixed-point rounds of the flight time converge for any target slower than the shell.
    static func intercept(from o: V3, speed: Float, gravity: Float, target p: V3, vel v: V3) -> (dir: V3, t: Float) {
        var t = simd_length(p - o) / speed
        var aim = p - o
        for _ in 0..<5 {
            let at: V3 = p + v * t
            let drop: Float = 0.5 * gravity * t * t
            aim = at - o + V3(0, drop, 0)
            t = simd_length(aim) / speed
        }
        let l = simd_length(aim)
        return (l > 1e-4 ? aim / l : V3(0, 1, 0), t)
    }

    // A flak shell from a gun, fuzed for an air target `t` seconds out (ranging: a few blocks off it).
    static func shell(_ m: Mob, at muzzle: V3, dir: V3, speed: Float, fuse: Float, ranging: Bool) -> Slug {
        var s = Slug(pos: muzzle, vel: Guns.scatter(dir, ranging ? 0.03 : 0.004) * speed, kind: .shell, damage: 0, fromPlayer: false,
                     shooter: ObjectIdentifier(m), by: m.spec.name, life: 4, gravity: HeavyTurret.gravity)
        s.power = power
        s.breaks = false
        s.fuse = max(0.05, fuse + (ranging ? -0.12 : 0.04))
        s.prox = ranging ? 0 : prox
        s.tracer = true
        return s
    }

    // P499 (Remington, Oct 30 20:36, flying the Meridian Frigate past a citadel: "the capital's naval guns should be
    // doing a number on the ship, which I don't think they are"): a main battery's shell fired at a craft struck its
    // armour skin as a flak burst (power 2.4, no cap: plates of resistance 1200 took nothing, not even a chip). It
    // breaches a hull it strikes as a manned shell does (Armory.update: his own deck gun's blow, armour as breach);
    // it still breaks no ground where it bursts.
    static func mainBattery(_ s: inout Slug) {
        s.power = HeavyTurret.power
        s.breach = HeavyTurret.mannedBreach
    }

    // Each frame for a fuzed shell (Armory.update): the point on this step's path nearest the player when it comes
    // within the proximity fuze, or nil.
    static func proximity(_ s: Slug, _ dir: V3, _ len: Float, _ g: Game) -> V3? {
        guard s.prox > 0 else { return nil }
        let c = g.player.eye - V3(0, 0.6, 0)
        let along = max(0, min(len, simd_dot(c - s.pos, dir)))
        let near = s.pos + dir * along
        return simd_length(c - near) < s.prox ? near : nil
    }

    // A flak burst beside a craft: its flak damage climbs by how close it was (six close bursts bring one down), and
    // its crew hears it; a craft past 1 has lost its engines (ShipPhysics) and trails smoke.
    static var onBurst: ((V3) -> Void)?           // (questcheck --oct14-only P252)
    static func burst(at c: V3, _ g: Game) {
        onBurst?(c)
        for s in g.world.ships.list where s.parent == nil {
            let lo = s.worldMin, hi = s.worldMax
            let q = simd_clamp(c, lo, hi)
            let d = simd_length(c - q)
            guard d < 6 else { continue }
            let was = s.flakHits
            s.flakHits = min(2, s.flakHits + 0.2 * (1 - d / 6) + 0.02)
            // P504 (Nov 1 07:50:55, "the ship is still not taking damage from the flak guns. The flak guns should tear the
            // ship apart"): a burst by a hull bites the plate nearest it (its 1.7 blast died in the 3 blocks of air
            // between the fuze and the hull; armour stands as steel now, Explosion.capped): a hole of a few blocks.
            if s.kinematic || s.role != nil {
                let to = s.toWorld(s.com) - c, tl = simd_length(to)
                if tl > 0.01, let h = g.world.ships.segmentHit(c, to / tl, min(tl, 12), except: -1), h.1.root === s {
                    g.world.ships.blast(at: c + to / tl * max(0, h.0 - 0.3), power: flakBite * (1 - 0.04 * h.0), game: g)
                }
            }
            if was < 1 && s.flakHits >= 1 {
                if g.world.ships.pilot?.root === s || g.world.ships.aboard?.root === s { g.onToast?("Engines hit: going down") }
                g.sfx(.explode, 1.4, at: s.pos)
            }
        }
    }

    // A crippled craft's smoke trail (ShipManager.update, once a frame).
    static func smoke(_ s: Ship, _ dt: Float, _ g: Game) {
        guard s.flakHits > 0.4, Rand.float(in: 0..<1) < dt * (s.flakHits >= 1 ? 30 : 10) else { return }
        g.particles.smoke(at: s.toWorld(s.com) + V3(Rand.float(in: -1...1), 1, Rand.float(in: -1...1)), dark: true)
    }

    // The warning by the player as a gun begins tracking them in the air.
    static func warn(_ m: Mob, _ g: Game) {
        g.sfx(.gun(12), 1.6)
        g.sfx(.gun(10), 1.2, at: m.pos)
        if g.clock - lastToast > 8 {
            lastToast = g.clock
            g.onToast?(HeavyTurret.isFlak(m) ? "Flak gun tracking you" : "\(m.spec.name) tracking you")
        }
    }
    static var lastToast: Double = -100
}
