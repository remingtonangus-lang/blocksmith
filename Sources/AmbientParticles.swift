import Foundation
import simd

// Ambient block particles (the reference game's "random display tick"): each frame a batch of random
// cells around the player is sampled and emitting blocks puff smoke and flames. Torches smoke and
// flicker, campfires send up a slow smoke column, lava spits glowing sparks, fire smokes.
enum Emitter: UInt8 { case none = 0, torch, soulTorch, campfire, lava, fire }

extension Game {
    static let emitters: [UInt8] = {
        var t = [UInt8](repeating: 0, count: Blocks.count)
        for id in 0..<Blocks.count {
            let k = Blocks.key(BlockID(id))
            let base = k.split(separator: "[").first.map(String.init) ?? k
            switch base {
            case "torch", "copper_torch": t[id] = Emitter.torch.rawValue
            case "soul_torch": t[id] = Emitter.soulTorch.rawValue
            case "campfire", "soul_campfire": if !k.hasSuffix("[off]") { t[id] = Emitter.campfire.rawValue }
            case "lava": t[id] = Emitter.lava.rawValue
            case "fire", "soul_fire": t[id] = Emitter.fire.rawValue
            default: break
            }
        }
        return t
    }()

    func ambientParticles(_ dt: Float) {
        if dt <= 0 || particles.list.count > ParticleManager.cap - 200 { return }
        let em = Game.emitters
        let p = player.pos
        let bx = Int(floor(p.x)), by = Int(floor(p.y)), bz = Int(floor(p.z))
        // ~700 samples per 20 Hz tick in a 32^3 box, like the reference (each emitter fires ~0.4x/s).
        let n = min(1200, Int(dt * 20 * 700))
        let smokeL = Int(Tex.id("smoke"))
        for _ in 0..<n {
            let x = bx + Rand.int(in: -16...15), y = by + Rand.int(in: -16...15), z = bz + Rand.int(in: -16...15)
            let b = world.block(x, y, z)
            let kind = em[Int(b)]
            if kind == 0 { continue }
            let o = V3(Float(x), Float(y), Float(z))
            switch Emitter(rawValue: kind) ?? .none {
            case .torch, .soulTorch:
                // Flame and smoke at the top of the torch stick (standing or on a wall).
                var top = o + V3(0.5, 0.7, 0.5)
                if let box = world.selectionBoxes(b).first { top = o + V3((box.0.x + box.1.x) / 2, box.1.y + 0.05, (box.0.z + box.1.z) / 2) }
                if let mb = Blocks.boxes[Int(b)].first, mb.leanX != 0 || mb.leanZ != 0 {     // a leaning wall torch's tip (P86)
                    top += V3(Float(mb.leanX) / 16, 0, Float(mb.leanZ) / 16)
                }
                particles.smoke(at: top + V3(0, 0.05, 0), dark: true)
                let soul = kind == Emitter.soulTorch.rawValue
                particles.add(Particle(pos: top, vel: V3(0, Rand.float(in: 0.02...0.08), 0), life: Rand.float(in: 0.25...0.5), maxLife: 0.5,
                                       layer: smokeL, uv0: .zero, uvSize: 1, size: Rand.float(in: 0.035...0.06), gravity: 0,
                                       color: soul ? V3(0.45, 0.9, 1.0) : V3(1.0, 0.72, 0.3), collide: false, glow: true))
            case .campfire:
                // Lazy smoke column: big soft puffs that rise for several seconds.
                for _ in 0..<2 {
                    let g = Rand.float(in: 0.55...0.72)
                    particles.add(Particle(pos: o + V3(Rand.float(in: 0.3...0.7), 0.6, Rand.float(in: 0.3...0.7)),
                                           vel: V3(Rand.float(in: -0.08...0.08), Rand.float(in: 1.0...1.6), Rand.float(in: -0.08...0.08)),
                                           life: Rand.float(in: 3...5), maxLife: 5, layer: smokeL, uv0: .zero, uvSize: 1,
                                           size: Rand.float(in: 0.22...0.38), gravity: 0, color: V3(g, g, g), collide: false))
                }
            case .lava:
                // Occasional sparks from open lava surfaces.
                if world.block(x, y + 1, z) != AIR || Rand.float(in: 0..<1) > 0.08 { continue }
                let s = o + V3(Rand.float(in: 0.2...0.8), 0.95, Rand.float(in: 0.2...0.8))
                particles.add(Particle(pos: s, vel: V3(Rand.float(in: -0.8...0.8), Rand.float(in: 2.5...4), Rand.float(in: -0.8...0.8)),
                                       life: Rand.float(in: 0.8...1.4), maxLife: 1.4, layer: smokeL, uv0: .zero, uvSize: 1,
                                       size: Rand.float(in: 0.04...0.07), gravity: 9, color: V3(1.0, 0.55, 0.15), collide: true, glow: true))
                particles.smoke(at: s + V3(0, 0.1, 0), dark: true)
            case .fire:
                if Rand.float(in: 0..<1) < 0.6 { particles.smoke(at: o + V3(Rand.float(in: 0...1), 0.9, Rand.float(in: 0...1)), dark: true) }
            case .none: break
            }
        }
    }
}

// Hell's atmosphere (the Emberdeep and the Deep's hell band): per-land haze (blended over nearby lands) and drifting
// motes (P292, hell's own lands: HellLands.swift): embers rising off the Cinder Plains, sparks off the charwood, violet
// motes in the Gloamwood, ash falling over the Ash Dunes and sulfur steam over the flats.
final class EmberAtmosphere {
    private var key = (Int.min, Int.min)
    private var fog = V3(0.2, 0.03, 0.03)

    static func color(_ b: Biome) -> V3 {
        switch b {
        case .crimsonForest: return V3(0.2, 0.075, 0.022)        // the Charwood Thicket: ember smoke
        case .warpedForest: return V3(0.085, 0.06, 0.16)         // the Gloamwood: violet dusk
        case .soulSandValley: return V3(0.21, 0.2, 0.18)         // the Ash Dunes: pale ash haze
        case .basaltDeltas: return V3(0.25, 0.22, 0.08)          // the Sulfur Flats: sulfur haze
        default: return V3(0.16, 0.085, 0.05)                    // the Cinder Plains: umber smoke
        }
    }

    // Fog colour at a position: a 3x3 blend of biome colours 12 blocks apart, cached per 4-block cell.
    func fog(at p: V3, gen: TerrainGenerator) -> V3 {
        let kx = Int(floor(p.x / 4)), kz = Int(floor(p.z / 4))
        if key == (kx, kz) { return fog }
        key = (kx, kz)
        var acc = V3(repeating: 0)
        for dz in -1...1 { for dx in -1...1 {
            acc += EmberAtmosphere.color(gen.column(kx * 4 + dx * 12, kz * 4 + dz * 12).biome)
        } }
        fog = acc / 9
        return fog
    }
}

extension Game {
    func emberMotes(_ dt: Float) {
        guard inHell, particles.list.count < ParticleManager.cap - 200 else { return }
        let p = player.pos
        let biome = world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome
        let rate: Float = biome == .soulSandValley ? 70 : (biome == .netherWastes ? 14 : 35)
        var n = Int(rate * dt)
        if Rand.float(in: 0..<1) < rate * dt - Float(n) { n += 1 }
        let smokeL = Int(Tex.id("smoke"))
        for _ in 0..<n {
            let o = p + V3(Rand.float(in: -12...12), Rand.float(in: -4...10), Rand.float(in: -12...12))
            if world.block(Int(floor(o.x)), Int(floor(o.y)), Int(floor(o.z))) != AIR { continue }
            var vel = V3(Rand.float(in: -0.15...0.15), 0, Rand.float(in: -0.15...0.15))
            var col = V3(1, 1, 1), glow = false, grav: Float = 0
            switch biome {
            case .crimsonForest: col = V3(1.0, 0.45, 0.12); vel.y = 0.3; glow = true
            case .warpedForest: col = V3(0.62, 0.48, 1.0); vel.y = 0.08; glow = true
            case .soulSandValley: col = V3(0.82, 0.8, 0.76); vel.y = -0.45; vel.x += 0.35; grav = 0.02
            case .basaltDeltas: col = V3(0.92, 0.88, 0.6); vel.y = 0.5
            default: col = V3(1.0, 0.55, 0.2); vel.y = 0.4; glow = true
            }
            particles.add(Particle(pos: o, vel: vel, life: Rand.float(in: 3...6), maxLife: 6, layer: smokeL, uv0: .zero, uvSize: 1,
                                   size: Rand.float(in: 0.025...0.045), gravity: grav, color: col, collide: false, glow: glow))
        }
    }
}
