import Foundation
import Metal
import simd

// Collision test for every block shape (--collisiontest [--strict]): each distinct collision shape (one state per
// box set) is placed on a stone floor high in the sky and a player-sized body (0.6 x 1.8) is
//   dropped onto it from 2.6 blocks: it must land at the block's collision top under its feet (drop_mismatch)
//   and never overlap it (penetration);
//   walked into it from the side with the game's step-up (0.6): a top of 0.6 or less must be stepped onto
//   (no_step_up), a higher one must stop the body (walk_through).
// Box sanity: collision boxes inside the cell (fences/walls up to 1.5 high) and a selection box for every block
// that collides (bad_boxes).
enum CollisionTest {
    static func run(device: MTLDevice) -> Int32 {
        let world = World(seed: 12345, device: device, save: nil)
        world.loadBlocks(cx0: -1, cz0: -1, cx1: 1, cz1: 1)
        let by = CH - 40
        let P = IVec3(8, by, 8)
        // Floor and clear space.
        for z in 2...14 { for x in 2...14 {
            _ = world.setBlockAsync(x, by - 1, z, STONE)
            for y in by...(by + 6) { _ = world.setBlockAsync(x, y, z, AIR) }
        } }
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        var lines: [String] = []
        var tested = 0
        func flag(_ c: String, _ d: String) {
            counts[c, default: 0] += 1
            if counts[c]! <= 10 { lines.append("- **\(c)** \(d)") }
        }
        for i in 1..<Blocks.count {
            let b = BlockID(i)
            guard Blocks.collide[i], Blocks.fluidKind[i] == 0 else { continue }
            let key = Blocks.key(b)
            // One state per distinct shape.
            let sig: String = Blocks.fullCollide[i] ? "full" : Blocks.collBoxes[i].map { "\($0.minV)\($0.maxV)" }.joined() + "c\(Blocks.connectKind[i])"
            if !seen.insert(sig).inserted { continue }
            tested += 1
            _ = world.setBlockAsync(P.x, P.y, P.z, b)
            var boxes: [(V3, V3)] = []
            world.collisionBoxes(P.x, P.y, P.z, &boxes)
            // Box sanity.
            for (lo, hi) in boxes {
                let o = V3(Float(P.x), Float(P.y), Float(P.z))
                let l: V3 = lo - o
                let h: V3 = hi - o
                let below: Bool = l.x < -0.01 || l.z < -0.01 || l.y < -0.01
                let above: Bool = h.x > 1.01 || h.z > 1.01 || h.y > 1.51
                let empty: Bool = h.x <= l.x || h.y <= l.y || h.z <= l.z
                if below || above || empty {
                    flag("bad_boxes", "\(key): collision box \(l) - \(h)")
                }
            }
            if world.selectionBoxes(b).isEmpty { flag("bad_boxes", "\(key): collides but has no selection box") }
            // Expected landing: the highest box top under the body's footprint (centre 8.5, 8.5, half 0.3).
            var expTop: Float = 0
            for (lo, hi) in boxes where lo.x < 8.8 && hi.x > 8.2 && lo.z < 8.8 && hi.z > 8.2 { expTop = max(expTop, hi.y - Float(by)) }
            // Drop.
            var pos = V3(8.5, Float(by) + 2.6, 8.5)
            var vy: Float = 0
            var overlap = false
            for _ in 0..<150 {
                vy -= 32 / 60
                let hit = world.moveBody(&pos, halfW: 0.3, height: 1.8, V3(0, vy / 60, 0), step: 0, onGround: false)
                if hit.y { vy = 0 }
                if world.collides(V3(pos.x - 0.29, pos.y + 0.01, pos.z - 0.29), V3(pos.x + 0.29, pos.y + 1.79, pos.z + 0.29)) { overlap = true }
            }
            let landed: Float = pos.y - Float(by)
            if abs(landed - expTop) > 0.02 && expTop <= 1.5 { flag("drop_mismatch", String(format: "%@: landed at +%.3f, collision top under the feet +%.3f", key, landed, expTop)) }
            if overlap { flag("penetration", "\(key): the dropped body overlapped the block") }
            // Walk in from the west at 3 blocks/s with step-up.
            var lane: Float = 0
            for (lo, hi) in boxes where lo.z < 8.8 && hi.z > 8.2 { lane = max(lane, hi.y - Float(by)) }
            pos = V3(6.6, Float(by), 8.5)
            vy = 0
            var onGround = true
            var through = false
            var maxY: Float = pos.y
            for _ in 0..<60 {
                vy -= 32 / 60
                let hit = world.moveBody(&pos, halfW: 0.3, height: 1.8, V3(3.0 / 60, vy / 60, 0), step: 0.6, onGround: onGround)
                if hit.y { if vy < 0 { onGround = true }; vy = 0 } else { onGround = false }
                maxY = max(maxY, pos.y)
                if world.collides(V3(pos.x - 0.29, pos.y + 0.01, pos.z - 0.29), V3(pos.x + 0.29, pos.y + 1.79, pos.z + 0.29)) { through = true }
            }
            if lane > 0 && lane <= 0.6 && pos.x < 8.5 { flag("no_step_up", String(format: "%@: top +%.2f but the walker stopped at x %.2f", key, lane, pos.x - 8)) }
            // Through: the body ended entirely past the block's boxes in its lane (thin panels stop it short of x 8.5).
            var laneMaxX: Float = 0
            for (lo, hi) in boxes where lo.z < 8.8 && hi.z > 8.2 { laneMaxX = max(laneMaxX, hi.x) }
            // Stairs are meant to be climbed from their low side.
            if lane > 0.65 && pos.x - 0.3 >= laneMaxX - 0.001 && laneMaxX > 0 && Blocks.shape[i] != "stairs" {
                let bs: String = boxes.map { b -> String in String(format: "[%.2f %.2f %.2f - %.2f %.2f %.2f]", b.0.x - 8, b.0.y - Float(by), b.0.z - 8, b.1.x - 8, b.1.y - Float(by), b.1.z - 8) }.joined(separator: " ")
                flag("walk_through", String(format: "%@: top +%.2f, walker ended at x %.2f y %.2f (max y %.2f); boxes ", key, lane, pos.x - 8, pos.y - Float(by), maxY - Float(by)) + bs)
            }
            if through { flag("penetration", "\(key): the walking body overlapped the block") }
            _ = world.setBlockAsync(P.x, P.y, P.z, AIR)
        }
        let cs = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let summary = "collisiontest: \(tested) shapes; \(cs.isEmpty ? "no issues" : cs)"
        try? (["# Collision test", "", summary, ""] + lines).joined(separator: "\n").write(toFile: arg("--out") ?? "snaps/collisiontest.md", atomically: true, encoding: .utf8)
        print(summary)
        return CommandLine.arguments.contains("--strict") && !counts.isEmpty ? 2 : 0
    }
}
