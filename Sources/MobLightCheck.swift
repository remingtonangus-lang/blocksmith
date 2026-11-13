import Foundation
import simd

// Nov 13, Carbon's black chickens (-1793 95 3355, "why are these chickens black?", black only for a moment): a small
// mob standing on smooth ground has its middle a third of a block up, and where the drawn ground sits a few tenths over
// its cell's floor that middle is inside the ground cell, whose own light is none. Every open ground column round the
// player: a middle put inside its top ground cell must be lit as the open cell over it is (Mob.lightFor).
enum MobLightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, p = g.player.pos
        var tried = 0, dark = 0, darkOld = 0, worst = ""
        for dz in stride(from: -24, through: 24, by: 3) { for dx in stride(from: -24, through: 24, by: 3) {
            let x = Int(floor(p.x)) + dx, z = Int(floor(p.z)) + dz
            guard let c = w.chunkAt(x, z) else { continue }
            let y = Int(c.height[mod(x, CS) + mod(z, CS) * CS])
            guard y > 0, y < CH - 2, Blocks.opaque[Int(w.block(x, y, z))], w.block(x, y + 1, z) == AIR else { continue }
            let open = w.lightAt(x, y + 1, z)
            guard open.sky == 15 else { continue }
            tried += 1
            let mid = V3(Float(x) + 0.5, Float(y) + 0.7, Float(z) + 0.5)       // (a chicken's middle, the ground 0.35 up its cell)
            let l = Mob.lightFor(w, at: mid, ragdoll: false)
            let raw = w.lightAt(x, y, z)
            if raw.sky + raw.block == 0 { darkOld += 1 }
            if l.sky < 15 { dark += 1; if worst.isEmpty { worst = "\(x) \(y) \(z): sky \(l.sky)" } }
        } }
        check(tried > 20 && dark == 0,
              "mob light: a mob's middle inside its ground cell is lit as the open cell over it (\(tried) columns, \(dark) dark\(worst.isEmpty ? "" : ", " + worst); the ground cell's own light was none in \(darkOld))")
    }
}
