import Foundation
import simd

// D42: aim the Field Tank's turret from the helm. At the helm of a wheeled vehicle with a turret (the Field Tank, or one
// you built round a helm) the gun is laid on whatever you look at, not on the view's pitch: the turret swings onto the
// point under your sight (ground, a wall or another vehicle, out to 220 blocks), the barrel comes up to the elevation
// that drops a shell there, and attack fires at that elevation. The helm's HUD line gives the range and says when the
// turret has come round onto it ("laid") or is still traversing.
enum TankSight {
    static let reach: Float = 220
    static var aim: V3?                          // the sight's point (nil: no sight to lay)
    static var elev: Float = 0                   // the first turret's elevation for that point
    static var laid = false                      // every turret bears on it
}

extension Game {
    // pilotTick, after the turrets followed the view.
    func tankSightTick(_ s: Ship) {
        let ships = world.ships
        let tur = ships.turrets(of: s).filter { !$0.cannons.isEmpty }
        guard !s.wheels.isEmpty, !tur.isEmpty else { TankSight.aim = nil; return }
        let o = player.eye, d = player.look
        var t = TankSight.reach
        if let h = world.raycast(o, d, maxDist: t) {
            let c = V3(Float(h.hit.x), Float(h.hit.y), Float(h.hit.z)) + 0.5
            t = min(t, simd_length(c - o))
        }
        for other in ships.list where other.root !== s {
            if let r = other.raycast(o, d, maxDist: t, world: world), r.t < t { t = r.t }
        }
        let p = o + d * t
        TankSight.aim = p
        var laid = true
        for (i, tu) in tur.enumerated() {
            tu.aimAt = p
            let muzzle = tu.toWorld(tu.pivot)
            let v = p - muzzle
            let horiz = simd_length(V2(v.x, v.z))
            let e: Float = horiz < 4 ? max(-0.2, min(0.6, player.pitch + 0.05)) : max(-0.2, min(0.6, ShipManager.elevation(horiz, v.y)))
            tu.gunPitch = e
            if i == 0 { TankSight.elev = e; s.gunPitch = e }
            let tf = tu.dirToWorld(V3(0, 0, -1))
            let a = simd_normalize(V2(tf.x, tf.z) + V2(1e-5, 0)), b = simd_normalize(V2(v.x, v.z) + V2(1e-5, 0))
            if horiz >= 4 && acosf(max(-1, min(1, simd_dot(a, b)))) > 0.04 { laid = false }
        }
        TankSight.laid = laid
    }

    // shipInteract: the elevation the pilot's guns fire at.
    func pilotGunPitch(_ s: Ship) -> Float {
        !s.wheels.isEmpty && TankSight.aim != nil ? TankSight.elev : player.pitch + 0.05
    }

    // shipHUDLine: the sight's range and whether the gun is laid.
    func tankSightHUD(_ s: Ship) -> String? {
        guard !s.wheels.isEmpty, let p = TankSight.aim else { return nil }
        return String(format: "  sight %.0f m %@", simd_length(p - player.eye), TankSight.laid ? "laid" : "traversing")
    }
}
