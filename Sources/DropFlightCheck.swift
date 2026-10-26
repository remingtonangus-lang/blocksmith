import Foundation
import simd

// P461's check (questcheck --dropflight): a taken Capital Dropship left in the air 30 blocks up comes down and rests
// on the ground; flown ahead with sprint held it reaches its overdrive speed and tears through a wall of leaves and
// planks in its way.
enum DropFlightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "dropflight: needs the overworld"); return }
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 5)
        let n0 = w.ships.list.count
        let gx = Int(floor(home.x)), gz = Int(floor(home.z))
        let start = V3(home.x, Float(w.topY(gx, gz)) + 30, home.z)
        w.ships.callDropship(faction: .steelhold, from: start, to: start + V3(0, 0, -60), game: g, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "dropship" && $0.parent == nil }) else {
            check(false, "dropflight: a Capital Dropship spawns"); return
        }
        defer {
            if w.ships.pilot === s { w.ships.pilot = nil }
            for t in w.ships.list where t === s || t.parent === s { w.ships.remove(t) }
            w.ships.capState.removeValue(forKey: s.id)
        }
        s.captured = true
        s.vel = .zero; s.angVel = .zero
        for _ in 0..<(60 * 14) { w.ships.update(1.0 / 60, game: g) }
        let cx = Int(floor(s.pos.x)), cz = Int(floor(s.pos.z))
        let rest = s.worldMin.y - Float(Capital.firmTop(w, cx, cz) + 1)
        check(abs(rest) < 0.6 && simd_length(s.vel) < 1,
              String(format: "dropflight: left 30 blocks up with nobody at the controls it comes down and rests (keel %.2f over the ground, %.1f m/s)", rest, simd_length(s.vel)))
        // A wall of leaves and planks 10 blocks ahead of the nose, as high as the hull.
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V3(fw.x, 0, fw.z) + V3(1e-5, 0, 0)), side = V3(-fh.z, 0, fh.x)
        let wallAt = s.pos + fh * 20
        var placed = 0
        for k in -6...6 { for dy in 0...6 {
            let p = wallAt + side * Float(k)
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y = Int(floor(s.worldMin.y)) + dy
            if w.block(x, y, z) == AIR { w.setBlock(x, y, z, Blocks.id(dy % 2 == 0 ? "oak_leaves" : "oak_planks")); placed += 1 }
        } }
        let crushed0 = ShipManager.crushed
        w.ships.pilot = s
        var top: Float = 0
        for _ in 0..<(60 * 3) {
            s.throttle = 1; s.boost = true; s.climb = 0; s.steer = 0; s.strafe = 0
            w.ships.update(1.0 / 60, game: g)
            top = max(top, simd_length(V2(s.vel.x, s.vel.z)))
        }
        w.ships.pilot = nil
        let crushed = ShipManager.crushed - crushed0
        check(top > 40 && crushed >= 10,
              String(format: "dropflight: flown ahead in overdrive it reaches %.0f m/s (28 without) and crushed %d of the %d leaf and plank blocks in its way", top, crushed, placed))
    }
}
