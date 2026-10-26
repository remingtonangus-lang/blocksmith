import Foundation
import simd

// P449's check (questcheck --chasehull): at the frigate's helm the chase view sits outside the hull, behind its stern
// and over it (it sat inside the ship, 48 blocks back from the mid-ship bridge); a small hull keeps its old view.
enum ChaseHullCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        let pos0 = g.player.pos
        defer { w.ships.pilot = nil; w.ships.aboard = nil; g.player.pos = pos0 }
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 260), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let hc = s.helm else {
            check(false, "chasehull: the frigate spawns with a helm"); return
        }
        defer { w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id) }
        // The pilot's eye at the helm.
        g.player.pos = s.toWorld(V3(Float(hc.x) + 0.5, Float(hc.y) + 1, Float(hc.z) + 0.5))
        w.ships.pilot = s
        guard let o = g.chaseOffset else { check(false, "chasehull: no chase view at the frigate's helm"); return }
        let cam = s.toLocal(g.player.eye + o)
        let lo = s.localMin, hi = s.localMax
        let inside = cam.x > lo.x && cam.x < hi.x && cam.y > lo.y && cam.y < hi.y && cam.z > lo.z && cam.z < hi.z
        check(!inside && cam.z > hi.z && cam.y > hi.y,
              String(format: "chasehull: the frigate's chase view is outside its hull: %.0f behind the stern, %.0f over its top (%.0f from the eye)",
                     cam.z - hi.z, cam.y - hi.y, simd_length(o)))
        // A small hull (the sidecar) keeps the old chase view.
        w.ships.pilot = nil
        let sc = w.ships.spawn(AshCommandeer.sidecar(), at: home + V3(0, 3, -12), yaw: 0, name: AshCommandeer.sidecarName, role: "")
        defer { w.ships.remove(sc) }
        let ext = sc.localMax - sc.localMin
        check(g.hullChase(sc) == nil, String(format: "chasehull: a small hull (%.0f x %.0f) keeps its old chase view", ext.x, ext.z))
    }
}
