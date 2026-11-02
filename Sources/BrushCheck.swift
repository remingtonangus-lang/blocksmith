import Foundation
import simd

// P511's brush check (in the full suite): his pace through a jungle thicket (Nov 2 08:22:41: "make it so the bush, the
// branches don't slow you down at all"). A line of bushes (a log on the ground under leaves), a limb laid on a leaf mass
// across his way at head height and a limb grown up from another: he walks through all of it at his open-ground pace.
// A tree's trunk standing on the ground still stops him.
enum BrushCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, p = g.player
        let pos0 = p.pos, fly0 = p.flying, yaw0 = p.yaw, my0 = p.moveYaw, ml0 = p.moveLook
        defer { p.pos = pos0; p.flying = fly0; p.yaw = yaw0; p.moveYaw = my0; p.moveLook = ml0; p.vel = .zero }
        guard Blocks.has("jungle_log"), Blocks.has("jungle_leaves") else { check(false, "brush: no jungle log or leaves"); return }
        let log = Blocks.id("jungle_log"), leaf = Blocks.id("jungle_leaves")
        let cx = Int(floor(pos0.x)) / 512 * 512 - 2600, cz = Int(floor(pos0.z)) / 512 * 512 + 2600
        _ = w.loadSync(center: V3(Float(cx), 0, Float(cz)), radius: 2)
        let y = w.topY(cx, cz) + 1
        // A flat, clear lane 30 long, 5 wide, 8 tall (stone under it).
        var saved: [(Int, Int, Int, BlockID)] = []
        func put(_ x: Int, _ yy: Int, _ z: Int, _ b: BlockID) { saved.append((x, yy, z, w.block(x, yy, z))); w.setBlock(x, yy, z, b) }
        for x in -4...26 { for z in -2...2 {
            put(cx + x, y - 1, cz + z, STONE)
            for dy in 0..<8 { put(cx + x, y + dy, cz + z, AIR) }
        } }
        defer { for (x, yy, z, b) in saved.reversed() { w.setBlock(x, yy, z, b) } }
        var slow: [String] = []                              // (where the pace dropped: x along the lane, speed, feet height, on ground)
        func walk() -> Float {
            p.flying = false; p.vel = .zero; p.yaw = -Float.pi / 2; p.moveYaw = nil; p.moveLook = nil     // facing +x
            p.pos = V3(Float(cx) - 3 + 0.5, Float(y), Float(cz) + 0.5)
            var inp = MoveInput(); inp.forward = 1
            for _ in 0..<20 { p.update(dt: 1.0 / 72, input: MoveInput(), world: w) }   // (settle on the ground)
            let start = p.pos
            slow = []
            for i in 0..<(72 * 9 / 2) {
                let x0 = p.pos.x
                p.update(dt: 1.0 / 72, input: inp, world: w)
                let v = (p.pos.x - x0) * 72
                if i > 36 && v < 3.6 && slow.count < 8 {
                    slow.append(String(format: "x%.1f %.1fb/s y%.2f%@", p.pos.x - Float(cx), v, p.pos.y - Float(y), p.onGround ? "" : " air"))
                }
            }
            return p.pos.x - start.x
        }
        let open = walk()
        // Bushes on the line: a log on the ground under leaves, leaves round it.
        for bx in [2, 7] {
            put(cx + bx, y, cz, log); put(cx + bx, y + 1, cz, leaf)
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { put(cx + bx + dx, y, cz + dz, leaf) }
        }
        // A limb on a leaf mass across the line at head height (its tree's trunk two blocks aside).
        for dy in 0..<5 { put(cx + 11, y + dy, cz + 2, log) }
        put(cx + 11, y, cz, leaf)
        put(cx + 11, y + 1, cz, log); put(cx + 11, y + 1, cz + 1, log)
        // A limb grown up from another, over air.
        put(cx + 14, y + 1, cz, log); put(cx + 14, y + 2, cz, log)
        let thick = walk()
        let thickSlow = slow.joined(separator: ", ")
        let soft = (w.softFoliage(Int(log), cx + 2, y, cz), w.softFoliage(Int(log), cx + 11, y + 1, cz),
                    w.softFoliage(Int(log), cx + 14, y + 2, cz), w.softFoliage(Int(log), cx + 11, y + 2, cz + 2))
        check(soft.0 && soft.1 && soft.2 && !soft.3,
              "brush: passed through: a bush's stem \(soft.0), a limb on leaves \(soft.1), a limb on a limb \(soft.2); a trunk on the ground stops him (\(!soft.3))")
        check(thick >= open * 0.95 && open > 15,
              String(format: "brush: four and a half seconds through two bushes and two limbs: %.1f blocks (open ground %.1f)", thick, open)
                + (thickSlow.isEmpty ? "" : "; slowed at \(thickSlow)"))
        // A trunk on the line stops him.
        for dy in 0..<5 { put(cx + 4, y + dy, cz, log) }
        let tree = walk()
        check(tree < 7.5, String(format: "brush: a trunk on the line stops him %.1f blocks on", tree))
    }
}
