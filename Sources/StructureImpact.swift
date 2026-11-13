import Foundation
import simd

// Physics revamp, part 2 (Remington, Nov 12: "Add proper physics to everything"; his shelled citadel, Nov 12 18:28): what
// comes down breaks what it lands on. A piece of a collapsed structure (Game.topple's bodies, StructureCollapse) fell onto
// the posts and floors left under it and lay there, however heavy and from however high: the tower's top sat jammed on
// its own stubs. A falling body that hits built blocks hard now spends the energy of the blow on them: the blocks it
// lands on break, weakest first, each taking its material's toughness (its bond) out of the blow, until the blow is
// spent or `perStrike` blocks are gone. The body goes on down through the gap, and what the broken blocks held up is the
// load checks' and the whole-structure weighing's business again (the floors under a falling top go one after another).
// Natural ground is not built: it takes the blow (his question #716). Felled trees do not break buildings.
// BS_IMPACT=0: off (before/after).
enum StructureImpact {
    static let enabled = ProcessInfo.processInfo.environment["BS_IMPACT"] != "0"
    static var perStrike = Int(ProcessInfo.processInfo.environment["BS_IMPACTBLOCKS"] ?? "") ?? 40
    static var minSpeed: Float = 4                    // blocks a second: a piece set down gently breaks nothing
    static var toughness: Float = Float(ProcessInfo.processInfo.environment["BS_IMPACTTOUGH"] ?? "") ?? 1    // a block's bond times this
    static var cooldown: Float = 0.12                 // seconds between one body's blows
    // (harness and soak)
    static var strikes = 0, broken = 0, worstMs = 0.0
    // (dozens of pieces of one collapse land together: at most `perFrame` blows a frame, the others keep their speed's
    // worth for the next contact)
    static var thisFrame = 0, perFrame = 2

    // The body's weight (Structure's units: tenths of a tonne a block).
    static func weight(_ s: Ship) -> Float {
        var w: Float = 0
        for b in s.grid.blocks where b != AIR { w += Structure.table[Int(b)]?.weight ?? 5 }
        return w
    }

    // A blow: the body moved at `vIn` before the contact and lost `dv` of it. True when blocks broke.
    static func strike(_ g: Game, _ s: Ship, weight: Float, vIn: V3, dv: Float) -> Bool {
        let speed = simd_length(vIn)
        guard enabled, speed >= minSpeed, dv > 2.5, weight > 0, thisFrame < perFrame else { return false }
        thisFrame += 1
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { worstMs = max(worstMs, (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
        let w = g.world
        let dir = vIn / speed
        var energy = 0.5 * weight * dv * dv
        // What it lands on: the built blocks just past its surface, the way it was going.
        var seen = Set<IVec3>()
        var hit: [(IVec3, Float)] = []
        for h in s.hull {
            let p = s.toWorld(h) + dir * 0.8
            let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            guard seen.insert(c).inserted, let m = Structure.part(w, c.x, c.y, c.z) else { continue }
            let b = w.builtBlock(c.x, c.y, c.z)
            if Blocks.hardness[Int(b)] < 0 || Structure.helm[Int(b)] { continue }      // (unbreakable; a vessel's helm)
            hit.append((c, m.bond * toughness))
        }
        guard !hit.isEmpty else { return false }
        hit.sort { $0.1 < $1.1 }
        var n = 0
        w.editBatch {
            for (c, tough) in hit {
                guard n < perStrike, energy >= tough else { break }
                energy -= tough
                let b = w.builtBlock(c.x, c.y, c.z)
                if n < 10 { g.particles.blockBreak(b, at: c) }
                g.breakBlock(c, b, drop: false, quiet: true)
                n += 1
            }
        }
        guard n > 0 else { return false }
        strikes += 1; broken += n
        g.sfx(.shipCollideHard, min(2, 0.9 + dv / 6), at: s.pos)
        return true
    }
}
