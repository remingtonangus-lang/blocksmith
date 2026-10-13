import Foundation
import simd

// P192 (Oct 13: "power armor in the military bases... make it so it can shoot blasts from the hands, kind of like
// Iron Man does"): a player wearing the whole Hannibal plate (helmet, vest and greaves, taken off Hannibal troopers)
// fires a blast from the palm when the trigger is pulled with an empty hand and nothing within reach is targeted (a
// block in reach is still punched and mined). The blast is a bright energy beam (no block damage), out of the aiming
// hand on the headset. 0.9 s between blasts.
enum PowerSuit {
    static let cooldown: Double = 0.9
    static let damage: Float = 8
    static let range: Float = 40
    static var lastBlast: Double = -10

    static func worn(_ g: Game) -> Bool {
        let a = g.inventory.armor
        func k(_ i: Int) -> String { a[i].isEmpty ? "" : Items.key(a[i].item) }
        let set = Set([k(0), k(1), k(2), k(3)])
        return (0..<3).allSatisfy { set.contains(TroopClass.hannibal.item($0)) }
    }

    // Fires if ready; true when a blast went off.
    @discardableResult
    static func blast(_ g: Game) -> Bool {
        guard g.clock - lastBlast >= cooldown else { return true }        // (still the suit's trigger: no punch between)
        lastBlast = g.clock
        let d = simd_normalize(g.vrAim?.dir ?? g.player.look)
        let o = (g.vrAim?.origin ?? (g.player.eye + V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw)) * 0.3 - V3(0, 0.25, 0))) + d * 0.35
        g.arms.beam(g, from: o, dir: d, range: range, damage: damage, fromPlayer: true, shooter: nil, by: "Player")
        g.sfx(.fireworkBlast, 0.6, at: o)
        for _ in 0..<10 {
            g.particles.add(Particle(pos: o, vel: d * Rand.float(in: 2...6) + V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)),
                                     life: 0.2, maxLife: 0.2, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.1,
                                     gravity: 0, color: V3(0.6, 0.85, 1), collide: false, glow: true))
        }
        g.swing = 1
        return true
    }
}
