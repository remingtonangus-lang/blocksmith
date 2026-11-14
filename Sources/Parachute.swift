import Foundation
import simd

// Nov 14 (Remington: "Add parachutes"). A Parachute (white wool over string and leather) is opened with a use in the
// air: he sinks at 4 blocks a second, drifts the way he faces (3 b/s, 6 with the stick forward, stopped held back),
// lands without a fall, and it folds away on the ground, in water or flying (Player.update). A use under the canopy
// cuts it away. Bailing out of a plane opens one by itself (ShipPlay.leaveHelm; it was an unseen slow fall). The
// canopy is drawn over him in the entity pass (Gadgets.writeLeads), seen looking up in the headset or in the chase view.
// BS_OLDPARACHUTE=1: no parachute from a bail-out (the slow fall, as before).
enum Parachute {
    static let old = ProcessInfo.processInfo.environment["BS_OLDPARACHUTE"] == "1"
    static let sink: Float = 4                   // blocks a second, falling under the canopy
    static let drift: Float = 3                  // blocks a second, the way he faces
    static var openedAt: Double = -100           // Game.clock when the last one opened (it blossoms over 0.5 s)
    static let rise: Float = 3.4                 // canopy middle over his feet
    static let radius: Float = 2.4
}

extension Game {
    // A use with a parachute in hand: in the air it opens (or, open, is cut away); on the ground it does nothing.
    func openParachute() -> Bool {
        let p = player
        if p.parachute { p.parachute = false; return true }
        guard !p.onGround, !p.flying, !p.gliding, !p.inWater, !p.inLava else { return false }
        deployParachute()
        return true
    }

    func deployParachute() {
        player.parachute = true
        player.airPeak = player.pos.y
        Parachute.openedAt = clock
        sfx(.armorEquip(0), 1.2, at: player.eye)
    }

    // The canopy: twelve gores in two colours on a shallow dome, its rim, and lines from the rim to his shoulders.
    func writeParachute(_ wr: inout EntityWriter, eye: V3) {
        guard player.parachute else { return }
        let white = Int(Tex.id("smoke"))
        let uv = [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)]
        let open = Float(min(1, max(0.15, (clock - Parachute.openedAt) / 0.5)))
        let feet = player.pos
        // It trails a little behind his drift.
        let hv = V3(player.vel.x, 0, player.vel.z)
        let mid: V3 = feet + V3(0, Parachute.rise * (0.6 + 0.4 * open), 0) - hv * 0.06
        let r = Parachute.radius * open
        let cell = (Int(floor(mid.x)), Int(floor(mid.y)), Int(floor(mid.z)))
        let l = world.lightAt(cell.0, cell.1, cell.2)
        let light = max(0.3, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
        let gores = 12
        let rings: [Float] = [0, 0.45, 0.85, 1.2]            // polar angle from the top
        func at(_ g: Int, _ ring: Int) -> V3 {
            let a = Float(g) / Float(gores) * 2 * .pi
            let t = rings[ring]
            return mid + V3(cosf(a) * sinf(t) * r, cosf(t) * r * 0.42, sinf(a) * sinf(t) * r)
        }
        let olive = V3(0.40, 0.43, 0.27), sand = V3(0.74, 0.69, 0.52)
        for g in 0..<gores {
            let base = g % 2 == 0 ? olive : sand
            for ring in 0..<(rings.count - 1) {
                let shade: Float = 1.0 - 0.12 * Float(ring)
                let c = V4(base * (shade * light), 1)
                wr.quad([at(g, ring) - eye, at(g + 1, ring) - eye, at(g + 1, ring + 1) - eye, at(g, ring + 1) - eye], uv, white, c)
            }
        }
        // Lines from every other gore's rim to his shoulders.
        let shoulders: V3 = feet + V3(0, player.height * 0.82, 0)
        let lineC = V4(V3(0.18, 0.17, 0.14) * light, 1)
        for g in stride(from: 0, to: gores, by: 2) {
            let a: V3 = at(g, rings.count - 1) - eye
            let b: V3 = shoulders - eye
            let cr: V3 = simd_cross(b - a, (a + b) * 0.5) + V3(1e-5, 0, 0)
            let side: V3 = simd_normalize(cr) * 0.025
            wr.quad([a - side, a + side, b + side, b - side], uv, white, lineC)
        }
    }
}
