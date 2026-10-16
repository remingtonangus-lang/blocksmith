import Foundation
import simd

// Boarding the Meridian frigate from the ground (done audit 25b6, G11: "no designed way to board the frigate 45 blocks
// up outside /vessel frigate"). A cargo winch hangs a line from the port hangar door (CapitalFrigate: the flank doors
// at x -9, y 9-13, z 100-112) to the ground. Stand at its foot and it hauls you up and in onto the hangar deck; the
// ladder at z 89 climbs to the bridge deck and the helm. While a player is near the line's foot the frigate heaves to
// (slows to a crawl) so the line can be caught, under fire if its crew are hostile. Checked by BoardingTests.
enum FrigateBoarding {
    static let anchorX: Float = 3.5          // grid x of the line (13 - 10 + 0.5: just outside the port door)
    static let anchorY: Float = 9.05         // the hangar deck's top (deck at y 8)
    static let anchorZ: Float = 106.5        // the door's middle
    static let inboard = V3(7.5, 9.05, 106.5)   // where the winch sets you down inside the hangar
    static let catchRadius: Float = 2.2      // horizontal reach of the line's foot (and anywhere up it)
    static let haulSpeed: Float = 9          // blocks per second up the line
    static let heaveRadius: Float = 34       // a player this close to the foot (horizontally) makes the frigate heave to
    static var hauled = 0                    // players hauled aboard (tests)
    static let puffLayer = Int(Tex.id("puff"))   // (looked up once: the line and the drive glow draw every frame)

    static func anchor(_ s: Ship) -> V3 { s.toWorld(V3(anchorX, anchorY, anchorZ)) }
}

extension ShipManager {
    // Per frame for every Meridian frigate (AI-flown or commandeered): the line, the haul, the heave-to.
    func boardingWinch(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        guard s.role == "capfrigate", !s.wrecked else { st.heaveTo = false; return }
        let top = FrigateBoarding.anchor(s)
        let pp = g.player.pos
        let flat = simd_length(V2(pp.x - top.x, pp.z - top.z))
        let onBoard = aboard?.root === s || pilot?.root === s
        st.heaveTo = !onBoard && flat < FrigateBoarding.heaveRadius && pp.y < top.y
        // The line: a dark cable from the door to the ground, drawn when the player is near enough to see it.
        let gx = Int(floor(top.x)), gz = Int(floor(top.z))
        let ground = Float(world.isLoaded(gx, gz) ? world.topY(gx, gz) + 1 : world.gen.column(gx, gz).height + 1)
        let length = max(0, top.y - ground)
        if simd_length(pp - top) < 140 && length > 0 {
            let layer = FrigateBoarding.puffLayer
            var y: Float = 0
            while y < length {
                g.particles.add(Particle(pos: top - V3(0, y, 0), vel: s.vel, life: dt * 1.5, maxLife: dt * 1.5, layer: layer, uv0: V2(0, 0),
                                         uvSize: 1, size: 0.22, gravity: 0, color: V3(0.16, 0.16, 0.15), collide: false))
                y += 1.2
            }
            // A lit hook at the foot so it reads from a distance at night.
            g.particles.add(Particle(pos: V3(top.x, ground + 0.4, top.z), vel: .zero, life: dt * 1.5, maxLife: dt * 1.5, layer: layer, uv0: V2(0, 0),
                                     uvSize: 1, size: 0.45, gravity: 0, color: V3(1.4, 0.9, 0.3), collide: false, glow: true))
            if !st.winchTold && flat < 60 {
                st.winchTold = true
                g.onToast?("The frigate's cargo winch lowers a line")
            }
        }
        // The haul: a player at the line (its foot or anywhere up it, below the door) rides it up and is set down inside.
        guard !onBoard, flat < FrigateBoarding.catchRadius, pp.y < top.y + 0.5, pp.y > ground - 2, g.riding == nil else { return }
        if pp.y >= top.y - 0.6 {
            g.player.pos = s.toWorld(FrigateBoarding.inboard)
            g.player.vel = s.velocity(at: g.player.pos)
            g.player.flying = false
            FrigateBoarding.hauled += 1
            g.sfx(.lanternHang, 1, at: g.player.pos)
            return
        }
        let pull = V3(top.x - pp.x, 0, top.z - pp.z) * 4
        g.player.vel = s.vel + pull + V3(0, FrigateBoarding.haulSpeed, 0)
        g.player.airPeak = g.player.pos.y                    // (held by the line: no fall damage counts)
    }
}
