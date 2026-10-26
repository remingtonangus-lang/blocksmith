import Foundation
import simd

// P449's check (questcheck --gunflight): his field gun's shell lands quickly (a low shot inside 1.5 s) and a shot laid
// high bursts in the end, in the air if it must (it vanished after 6 s with no burst).
enum GunFlightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        func fly(_ pitch: Float?) -> (Float, Float, Bool) {
            let from = g.player.eye + V3(0, 2, 0)
            var dir = V3(0, sinf(pitch ?? 0), -cosf(pitch ?? 0))
            if pitch == nil {                                   // laid on the ground 64 blocks ahead
                let x = Int(floor(from.x)), z = Int(floor(from.z)) - 64
                dir = simd_normalize(V3(Float(x) + 0.5, Float(g.world.topY(x, z) + 1), Float(z) + 0.5) - from)
            }
            var s = Slug(pos: from, vel: dir * AshSeat.gunSpeed, kind: .shell, damage: 0, fromPlayer: true,
                         shooter: nil, by: "Player", life: 6, gravity: AshSeat.gunGravity)
            s.power = AshSeat.gunPower
            s.breaks = true
            let d0 = Armory.detonations
            let n0 = g.arms.slugs.count
            g.arms.spawn(s)
            var t: Float = 0
            var last = from
            while t < 8 && g.arms.slugs.count > n0 {
                if let q = g.arms.slugs.last { last = q.pos }
                g.arms.update(1.0 / 72, g); t += 1.0 / 72
            }
            return (t, simd_length(V2(last.x - from.x, last.z - from.z)), Armory.detonations > d0)
        }
        let (tLow, dLow, bLow) = fly(nil)
        check(bLow && tLow < 1.5, String(format: "gunflight: a shot laid on the ground 64 blocks off bursts %.0f blocks out after %.2f s (the shell flew at 46 b/s before, 100 now)", dLow, tLow))
        let (tHigh, dHigh, bHigh) = fly(1.15)
        check(bHigh && tHigh < 6.2, String(format: "gunflight: a shot laid high bursts after %.1f s, %.0f blocks out", tHigh, dHigh))
    }
}
