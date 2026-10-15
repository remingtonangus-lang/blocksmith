import Foundation
import simd

// P291 (Oct 14 19:57-19:59; Oct 15 18:45, 19:00): dropping into hell. An Ember Charge blows the Wardstone floor and the
// player falls through it; they used to land in a pocket on top of the Deep's crust, dig on, and then drift down the
// hell band's 100+ block halls for half a minute ("the slow drift down is the worst part"), creative included.
//   (a) the drop sounds and looks like one: a roaring rush of air while falling fast (any long fall), embers streaming
//       up past you in hell, and a heavy ground-shaking impact with a ring of dust and sparks where you land;
//   (b) a fall through the blasted floor carries straight on: the shaft runs on through the crust and the hall's roof
//       above the nearest column whose floor is solid ground (never lava, a lava fall or magma), so you land there;
//   (c) arrival (no title card, NO TEXT): breaking out under the fire sky flares a hot glow and a burst of embers round
//       you with a low swelling roar, and a short fire resistance carries you over the landing;
//   (d) no slow drift (Oct 15 change): everyone falls at the normal speed and a landing in hell takes a tenth of the
//       usual fall damage (Game.survivalTick); creative falls like anyone else. The arrival loads only the nearest
//       chunks before the drop (no loading pause), the rest stream in on the way down.
struct HellDropState {
    var active = false
    var broke = false               // (c) out under the hall's roof
    var roof = 0                    // first open cell under the roof (internal y)
    var floor = 0                   // the landing block (internal y)
    var t: Float = 0
}

extension Game {
    static let hellDropReach = 32
    // Columns round the drop, nearest first.
    static let hellDropOffsets: [(Int, Int)] = {
        let r = Game.hellDropReach
        var o: [(Int, Int)] = []
        for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r { o.append((dx, dz)) } }
        return o.sorted { $0.0 * $0.0 + $0.1 * $0.1 < $1.0 * $1.0 + $1.1 * $1.1 }
    }()

    // (b) The nearest column (x, z) whose drop through the hell band ends on solid ground: its hall's first open cell
    // under the roof and the block it lands on. Small pockets in the roof are cut through on the way.
    func hellLanding(nearX x0: Int, z z0: Int) -> (x: Int, z: Int, roof: Int, floor: Int)? {
        for (dx, dz) in Game.hellDropOffsets {
            let x = x0 + dx, z = z0 + dz
            if let c = hellColumn(x, z) { return (x, z, c.roof, c.floor) }
        }
        return nil
    }

    @inline(__always) private func dropPassable(_ b: BlockID) -> Bool {
        !Blocks.collide[Int(b)] && Blocks.fluidKind[Int(b)] == 0
    }

    private func hellColumn(_ x: Int, _ z: Int) -> (roof: Int, floor: Int)? {
        guard world.chunkAt(x, z) != nil else { return nil }
        let base = DeepGen.hellBase
        var y = DeepGen.crustTop - 1
        while y > base {
            while y > base && !dropPassable(world.block(x, y, z)) { y -= 1 }        // the roof, or a ledge
            let top = y
            while y > base && dropPassable(world.block(x, y, z)) { y -= 1 }         // the open hall
            guard top - y >= 4 else { continue }                                     // a pocket: cut on through it
            return hellFloorSafe(x, y, z) ? (top, y) : nil
        }
        return nil
    }

    // Solid, not lava or magma, no fire on it and no lava running in beside where you stand.
    private func hellFloorSafe(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        let b = world.block(x, y, z)
        guard Blocks.collide[Int(b)], Blocks.fluidKind[Int(b)] == 0, b != Game.hellMagma else { return false }
        let up = world.block(x, y + 1, z)
        guard up != FIRE && up != Game.hellSoulFire else { return false }
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where Blocks.fluidKind[Int(world.block(x + dx, y + 1, z + dz))] != 0 { return false }
        return true
    }
    static let hellMagma = Blocks.id("magma_block")
    static let hellSoulFire = Blocks.id("soul_fire")

    // (b) Opens the shaft from the arrival cell down to the hall: 3x3 through the crust and the roof, any lava pocket
    // it passes walled off with emberslate so nothing pours down after you. Bulk edits: the meshes follow in a frame.
    func openHellShaft(_ x: Int, _ z: Int, roof: Int) {
        let top = CH - 2
        guard roof + 1 <= top else { return }
        for y in (roof + 1)...top {
            for dz in -2...2 { for dx in -2...2 {
                let b = world.block(x + dx, y, z + dz)
                let inner = abs(dx) <= 1 && abs(dz) <= 1
                if inner {
                    if b != AIR { world.setBlockAsync(x + dx, y, z + dz, AIR) }
                } else if Blocks.fluidKind[Int(b)] != 0 {
                    world.setBlockAsync(x + dx, y, z + dz, EMBERSLATE)
                }
            } }
        }
    }

    // Each tick while a drop is under way (from deepTick).
    func hellDropTick(_ dt: Float) {
        guard hellDrop.active else { return }
        guard dim.dim == .deep, alive, riding == nil, world.frame == nil else { hellDrop.active = false; return }
        hellDrop.t += dt
        let p = player.pos
        // (c) Out under the fire sky: a hot flare below, embers bursting round you, the hall's low roar.
        if !hellDrop.broke && p.y < Float(hellDrop.roof) + 0.5 {
            hellDrop.broke = true
            sfx(.hellArrival, 1.0)
            addFlash(at: p + V3(0, -8, 0), color: V3(5, 1.9, 0.6), radius: 44, life: 1.8)
            for _ in 0..<28 {
                let d = V3(Rand.float(in: -1...1), Rand.float(in: -0.6...0.4), Rand.float(in: -1...1)) * 3.2
                emberStreak(at: p + d, rise: Rand.float(in: 1.5...4))
            }
            applyEffect(.fireResistance, amp: 0, seconds: 12)
        }
        let landed = player.onGround && !player.flying
        if landed || player.inWater || player.inLava || player.flying || hellDrop.t > 30 {
            if landed && hellDrop.broke {
                // (a) The impact: a heavy boom, the ground shakes, dust and sparks thrown out in a ring.
                let under = world.block(Int(floor(p.x)), Int(floor(p.y - 0.2)), Int(floor(p.z)))
                sfx(.hellImpact, 1.0, at: p)
                addShake(0.7)
                addFlash(at: p + V3(0, 0.5, 0), color: V3(2.4, 1.0, 0.4), radius: 10, life: 0.5)
                if under != AIR { particles.dust(under, at: p, count: 44, spread: 1.8) }
                for k in 0..<16 {
                    let a = Float(k) / 16 * 2 * .pi
                    let d = V3(cosf(a), 0, sinf(a))
                    emberStreak(at: p + d * 0.6 + V3(0, 0.2, 0), rise: 0.8, out: d * Rand.float(in: 3...5))
                }
            }
            hellDrop.active = false
            return
        }
        // (a) The fall: embers hanging in the hot air below stream up past you (you fall through them).
        if hellDrop.broke && player.vel.y < -12 {
            for _ in 0..<2 {
                let d = V3(Rand.float(in: -2.4...2.4), Rand.float(in: -7 ... -3), Rand.float(in: -2.4...2.4))
                emberStreak(at: p + d, rise: Rand.float(in: 0.3...1.2))
            }
        }
    }

    // A glowing ember mote (blooms in Fancy).
    func emberStreak(at c: V3, rise: Float, out: V3 = .zero) {
        let g = Rand.float(in: 0.35...0.7)
        particles.add(Particle(pos: c, vel: out + V3(Rand.float(in: -0.3...0.3), rise, Rand.float(in: -0.3...0.3)),
                               life: Rand.float(in: 0.6...1.3), maxLife: 1.3, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                               size: Rand.float(in: 0.05...0.1), gravity: -0.6, color: V3(1, g, 0.15), collide: false, glow: true))
    }
}

// P291 (a, c): the drop's sounds, all synthesized (inspiration only).
enum HellDropAudio {
    static func render(_ g: inout Synth, _ s: Snd, p: Float) -> [Float] {
        switch s {
        case .fallRushLoop:
            // Air tearing past a falling body: a deep roaring wash, buffeting lows and a thin high whistle.
            let roar = g.wash(3.0, lp: 900 * p, hp: 60, wobble: 0.8, rate: 4, gain: 1.0)
            let buffet = g.wash(3.0, lp: 140, hp: 22, wobble: 1.4, rate: 7, gain: 1.1)
            let whistle = g.wash(3.0, lp: 4200, hp: 1400, wobble: 0.5, rate: 2.5, gain: 0.22)
            return Synth.loopify(Synth.mix(Synth.mix(roar, buffet), whistle), fade: 0.3)
        case .hellImpact:
            // Landing from a great height: a body-blow thud into a ground-shaking boom, stone cracking, grit settling.
            var o = g.rumble(2.6, f: 32 * p, attack: 0.003, decay: 0.9, gain: 3.0)
            o = Synth.mix(o, g.burst(0.5, lp: 520 * p, hp: 28, attack: 0.002, decay: 0.12, gain: 2.6))
            o = Synth.mix(o, g.material(.stone, pitch: 0.55 * p, scale: 1.6, gain: 0.8), at: g.frames(0.01))
            o = Synth.mix(o, g.grains(22, spread: 1.0, lp: 2600, hp: 250, decay: 0.014, gain: 0.5), at: g.frames(0.18))
            return Synth.echo(o, delay: 0.42, feedback: 0.3, mix: 0.3, tail: 0.8)
        default:
            // hellArrival: the hall opening under you: a low detuned swell sinking a step, a fifth over it, a rising
            // wash of heat and a far boom under the lot, rolling round the hall.
            let a = g.tone(4.2, f0: 58 * p, f1: 51 * p, wave: .saw, attack: 1.1, release: 1.6, vib: 0.01, vibRate: 0.4, gain: 0.32)
            let b = g.tone(4.2, f0: 58.6 * p, f1: 51.4 * p, wave: .saw, attack: 1.2, release: 1.6, vib: 0.012, vibRate: 0.3, gain: 0.28)
            let fifth = g.tone(3.6, f0: 87 * p, f1: 77 * p, wave: .sine, attack: 1.4, release: 1.4, gain: 0.3)
            var o = Synth.lowpass(Synth.mix(a, b), 560)
            o = Synth.mix(o, fifth, at: g.frames(0.3))
            o = Synth.mix(o, Synth.decayEnv(Synth.rampIn(g.wash(4.2, lp: 700, hp: 60, wobble: 1.2, rate: 1.2, gain: 1.0), 1.4), 2.2))
            o = Synth.mix(o, g.rumble(3.0, f: 30 * p, attack: 0.05, decay: 1.4, gain: 1.6), at: g.frames(0.2))
            return Synth.echo(o, delay: 0.8, feedback: 0.32, mix: 0.3, tail: 1.6)
        }
    }
}
