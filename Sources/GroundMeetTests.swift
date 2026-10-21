import Foundation
import simd

// P387 check (questcheck --view OUT --field --scene meetground [--meetcheck]): stone, planks, a lamp and a chest placed
// on the ground in front of the eye (as the player places them: the cell over the drawn ground, then World.meetGround),
// and the largest gap between each one's floor and the drawn ground under its footprint (BS_MEET=0: as before P387).
// Then step (4): a wire, a card rail, a carpet, a torch and a lantern each put in a section's first row where the
// ground under it dips into the section below, checked as P382's things are (GroundDrape.check).
extension World {
    static let meetThings = ["stone", "oak_planks", "redstone_lamp", "chest"]

    // Two of each, 6 blocks ahead of the eye (yaw), two apart across the view.
    static func meetScene(_ g: Game, yaw: Float) -> [(IVec3, String)] {
        let w = g.world
        let fwd = V3(-sinf(yaw), 0, -cosf(yaw)), side = V3(cosf(yaw), 0, -sinf(yaw))
        if let h = w.fieldRaySegment(V3(g.player.pos.x, g.player.eye.y + 40, g.player.pos.z), V3(0, -1, 0), from: 0, to: 120) {
            g.player.pos.y = h.at.y + 1
        }
        var out: [(IVec3, String)] = []
        let base = g.player.pos
        for k in 0..<8 {
            let key = meetThings[k % 4]
            let p = base + fwd * (k < 4 ? 6 : 9) + side * Float((k % 4) * 2 - 3)
            guard let h = w.fieldRaySegment(V3(p.x, g.player.eye.y + 8, p.z), V3(0, -1, 0), from: 0, to: 64) else { continue }
            let c = IVec3(Int(floor(h.at.x)), Int(floor(h.at.y + 0.5)), Int(floor(h.at.z)))
            guard Blocks.replaceable[Int(w.materialAt(c.x, c.y, c.z))], w.opaqueAt(c.x, c.y - 1, c.z) else { continue }
            let id = Blocks.id(key)
            w.setBlock(c.x, c.y, c.z, id)
            if key == "chest" { w.blockEntities[c] = BlockEntity(.chest) }
            w.meetGround(c.x, c.y, c.z, id)
            out.append((c, key))
        }
        return out
    }

    static let lowRowThings = ["redstone_wire", "powered_rail", "white_carpet", "torch", "lantern"]

    // P387 (4): cells within 16 blocks of the eye in a section's first row (y a multiple of 16) over natural ground that
    // dips under the section's floor there by a tenth or more; one of lowRowThings in each of the first five.
    static func lowRowScene(_ g: Game) -> [(IVec3, String)] {
        let w = g.world
        var out: [(IVec3, String)] = []
        let bx = Int(floor(g.player.pos.x)), bz = Int(floor(g.player.pos.z))
        for r in 2...16 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            guard out.count < lowRowThings.count else { return out }
            let x = bx + dx, z = bz + dz
            guard let h = w.fieldRaySegment(V3(Float(x) + 0.5, g.player.eye.y + 12, Float(z) + 0.5), V3(0, -1, 0), from: 0, to: 64) else { continue }
            let c = IVec3(x, Int(floor(h.at.y + 0.5)), z)
            guard c.y & 15 == 0, h.at.y < Float(c.y) - 0.1, Blocks.replaceable[Int(w.materialAt(c.x, c.y, c.z))], w.opaqueAt(c.x, c.y - 1, c.z),
                  !out.contains(where: { abs($0.0.x - x) < 3 && abs($0.0.z - z) < 3 }) else { continue }
            let key = lowRowThings[out.count]
            w.setBlock(c.x, c.y, c.z, Blocks.id(key))
            out.append((c, key))
        } } }
        return out
    }

    // For each: the drawn ground just outside its footprint (5 points along each side, 0.03 out; under the block itself
    // the ground is hidden and not drawn), the largest drop from its floor to it there: the gap that shows under its
    // downhill side. Ground over the floor (the block sunk in) counts as none.
    static func meetCheck(_ w: World, _ things: [(IVec3, String)]) -> String {
        var lines = ["meetground (P387, \(World.meetGroundOn ? "on" : "off")): largest gap from a placed block's floor down to the drawn ground round its foot"]
        var worst: [String: Float] = [:]
        for (c, key) in things {
            // (stone placed in a field world is ground (P377 step 3's lump), drawn as ground: no floor to stand off it)
            if w.groundAt(c.x, c.y, c.z) { lines.append("  \(key) at \(c.x) \(c.y) \(c.z): ground (a placed natural block joins the ground)"); continue }
            var gap: Float = 0
            let fy = Float(c.y)
            for side in 0..<4 { for k in 0..<5 {
                let t = Float(k) * 0.25, o: Float = 0.03
                let px = Float(c.x) + (side == 0 ? -o : side == 1 ? 1 + o : t), pz = Float(c.z) + (side == 2 ? -o : side == 3 ? 1 + o : t)
                if let h = w.drawnGround(px, pz, lo: fy - 2, hi: fy + 1) {
                    gap = max(gap, fy - h)
                    if fy - h > 0.05, ProcessInfo.processInfo.environment["BS_MEET_DEBUG"] != nil {
                        print(String(format: "    gap %.3f at %.2f %.2f: drawn %.3f, field %@", fy - h, px, pz, h,
                                     w.fieldRaySegment(V3(px, fy + 1, pz), V3(0, -1, 0), from: 0, to: 4).map { String(format: "%.3f", $0.at.y) } ?? "nil"))
                    }
                } else {
                    gap = max(gap, 2)
                    if ProcessInfo.processInfo.environment["BS_MEET_DEBUG"] != nil {
                        let raw = w.drawnGround(px, pz, lo: fy - 4, hi: fy + 3, check: false)
                        let q = w.chunkAt(Int(floor(px)), Int(floor(pz)))?.sections[c.y >> 4].ground?.quads ?? -1
                        print(String(format: "    no ground at %.2f %.2f: raw %@ (density %.2f %.2f), section ground quads %d, field ray %@", px, pz,
                                     raw.map { String(format: "%.3f", $0) } ?? "nil", raw.map { w.fieldDensity(at: V3(px, $0 - 0.25, pz)) } ?? 0,
                                     raw.map { w.fieldDensity(at: V3(px, $0 - 0.5, pz)) } ?? 0, q,
                                     w.fieldRaySegment(V3(px, fy + 1, pz), V3(0, -1, 0), from: 0, to: 4).map { String(format: "%.3f", $0.at.y) } ?? "nil"))
                    }
                }
            } }
            worst[key] = max(worst[key] ?? 0, gap)
            lines.append(String(format: "  %@ at %d %d %d: gap %.3f", key, c.x, c.y, c.z, gap))
        }
        lines.append("  worst: " + meetThings.filter { $0 != "stone" }.map { String(format: "%@ %.3f", $0, worst[$0] ?? -1) }.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}
