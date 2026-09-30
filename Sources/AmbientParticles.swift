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
            case "torch": t[id] = Emitter.torch.rawValue
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
            let x = bx + Int.random(in: -16...15), y = by + Int.random(in: -16...15), z = bz + Int.random(in: -16...15)
            let b = world.block(x, y, z)
            let kind = em[Int(b)]
            if kind == 0 { continue }
            let o = V3(Float(x), Float(y), Float(z))
            switch Emitter(rawValue: kind) ?? .none {
            case .torch, .soulTorch:
                // Flame and smoke at the top of the torch stick (standing or on a wall).
                var top = o + V3(0.5, 0.7, 0.5)
                if let box = world.selectionBoxes(b).first { top = o + V3((box.0.x + box.1.x) / 2, box.1.y + 0.05, (box.0.z + box.1.z) / 2) }
                particles.smoke(at: top + V3(0, 0.05, 0), dark: true)
                let soul = kind == Emitter.soulTorch.rawValue
                particles.add(Particle(pos: top, vel: V3(0, Float.random(in: 0.02...0.08), 0), life: Float.random(in: 0.25...0.5), maxLife: 0.5,
                                       layer: smokeL, uv0: .zero, uvSize: 1, size: Float.random(in: 0.035...0.06), gravity: 0,
                                       color: soul ? V3(0.45, 0.9, 1.0) : V3(1.0, 0.72, 0.3), collide: false, glow: true))
            case .campfire:
                // Lazy smoke column: big soft puffs that rise for several seconds.
                for _ in 0..<2 {
                    let g = Float.random(in: 0.55...0.72)
                    particles.add(Particle(pos: o + V3(Float.random(in: 0.3...0.7), 0.6, Float.random(in: 0.3...0.7)),
                                           vel: V3(Float.random(in: -0.08...0.08), Float.random(in: 1.0...1.6), Float.random(in: -0.08...0.08)),
                                           life: Float.random(in: 3...5), maxLife: 5, layer: smokeL, uv0: .zero, uvSize: 1,
                                           size: Float.random(in: 0.22...0.38), gravity: 0, color: V3(g, g, g), collide: false))
                }
            case .lava:
                // Occasional sparks from open lava surfaces.
                if world.block(x, y + 1, z) != AIR || Float.random(in: 0..<1) > 0.08 { continue }
                let s = o + V3(Float.random(in: 0.2...0.8), 0.95, Float.random(in: 0.2...0.8))
                particles.add(Particle(pos: s, vel: V3(Float.random(in: -0.8...0.8), Float.random(in: 2.5...4), Float.random(in: -0.8...0.8)),
                                       life: Float.random(in: 0.8...1.4), maxLife: 1.4, layer: smokeL, uv0: .zero, uvSize: 1,
                                       size: Float.random(in: 0.04...0.07), gravity: 9, color: V3(1.0, 0.55, 0.15), collide: true, glow: true))
                particles.smoke(at: s + V3(0, 0.1, 0), dark: true)
            case .fire:
                if Float.random(in: 0..<1) < 0.6 { particles.smoke(at: o + V3(Float.random(in: 0...1), 0.9, Float.random(in: 0...1)), dark: true) }
            case .none: break
            }
        }
    }
}
