import Foundation
import simd

// Eased step-ups (Quest playtest 2026-10-09 pm item 1: "horse up hills is choppy, every block step jolts the view").
// Physics stays exact: World.moveBody lifts a body onto a step in one tick. What is drawn (the camera, the mob, the
// rider) carries a visual offset `dy` that takes up the snap and springs back to 0 (critically damped, so the eased
// rise starts and ends with zero speed: no jolt in either velocity or acceleration). Step-downs are eased the same way.
// Falls, jumps and teleports (more than `maxStep`) are real motion and pass straight through.
enum ViewStep {
    static let omega: Float = 18            // spring rate: a 1-block step peaks at omega/e = 6.6 blocks/s, ~95 % in 0.25 s
    static let minStep: Float = 0.04        // smaller per-tick jumps are ordinary motion
    static let maxStep: Float = 1.3         // larger ones are teleports / falls and snap

    // Advances a critically damped offset (o, v) toward 0 over dt (exact solution: stable at any dt).
    static func decay(_ o: inout Float, _ v: inout Float, _ dt: Float) {
        if o == 0 && v == 0 { return }
        let w = omega
        let e: Float = expf(-w * dt)
        let c: Float = v + w * o
        let no: Float = (o + c * dt) * e
        let nv: Float = (v - w * c * dt) * e
        o = no; v = nv
        if abs(o) < 0.001 && abs(v) < 0.01 { o = 0; v = 0 }
    }

    // Climbing a long, steep staircase fast the lag stays under 2 v / omega; past maxLag only the overflow snaps.
    static let maxLag: Float = 1.6
    @inline(__always) static func clamp(_ o: inout Float) { o = max(-maxLag, min(maxLag, o)) }

    // A body moved `d` vertically in one tick that physics calls a step (on the ground before and after): absorb it.
    @inline(__always) static func absorbs(_ d: Float) -> Bool { abs(d) > minStep && abs(d) <= maxStep }
}

extension Mob {
    // After the mob's update (MobManager.update): a grounded jump in height is a step; the drawn model eases it.
    func easeStep(fromY y0: Float, wasGround: Bool, _ dt: Float) {
        let d = pos.y - y0
        ViewStep.decay(&viewDY, &viewDV, dt)
        if wasGround && onGround && ViewStep.absorbs(d) { viewDY -= d }
        ViewStep.clamp(&viewDY)
    }
}

extension Player {
    /// The eye the camera draws from: the true eye plus the eased step offset.
    var viewEye: V3 { eye + V3(0, viewDY, 0) }
}

extension Game {
    // End of every tick: the player's eased step offset. Riding an animal it is the mount's (the camera, the rider
    // and the mount's model move together); on a ship's frame only the part of the move the ship's own velocity
    // doesn't explain (a wheeled vehicle climbing onto a block, a deck step) is eased; on foot, grounded steps.
    func updateViewStep(_ dt: Float) {
        let p = player
        let y = p.pos.y
        defer { p.viewLastY = y; p.viewLastGround = p.onGround }
        if let m = riding {
            p.viewDY = m.viewDY; p.viewDV = m.viewDV
            return
        }
        ViewStep.decay(&p.viewDY, &p.viewDV, dt)
        guard let ly = p.viewLastY, !p.flying else { return }
        var d = y - ly
        if let s = world.ships.aboard ?? world.ships.pilot {
            d -= s.velocity(at: p.pos).y * dt
            if !(p.onGround || (s.grounded && !s.wheels.isEmpty)) { return }
        } else if !(p.onGround && p.viewLastGround) {
            return
        }
        if ViewStep.absorbs(d) { p.viewDY -= d }
        ViewStep.clamp(&p.viewDY)
    }
}
