import Foundation
import simd

// P382 check (questcheck --view OUT --field --scene groundthings [--groundcheck]): things laid on the field's ground in
// front of the eye, and how far each one's drawing is off the drawn ground under it (BS_DRAPE=0: as before P382).
extension GroundDrape {
    static let sceneThings: [String] = ["powered_rail", "powered_rail", "detector_rail", "white_carpet", "stone_pressure_plate", "torch",
                                        "oak_sign", "repeater", "lantern", "candle", "short_grass", "poppy"]

    // Two rows across the ground 5 and 8 blocks ahead of the eye (yaw): 14 copper wires (joined), then one of each of
    // sceneThings. Each goes into the cell over the drawn ground in its column (as the game places them now).
    static func placeScene(_ g: Game, yaw: Float) -> [(IVec3, String)] {
        let w = g.world
        let fwd = V3(-sinf(yaw), 0, -cosf(yaw)), side = V3(cosf(yaw), 0, -sinf(yaw))
        var out: [(IVec3, String)] = []
        var seen = Set<IVec3>()
        func put(_ p: V3, _ key: String) {
            let o = V3(p.x, g.player.eye.y + 8, p.z)
            guard let h = w.fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 64) else { return }
            let c = IVec3(Int(floor(h.at.x)), Int(floor(h.at.y + 0.5)), Int(floor(h.at.z)))
            guard !seen.contains(c), w.opaqueAt(c.x, c.y - 1, c.z), Blocks.replaceable[Int(w.materialAt(c.x, c.y, c.z))] else { return }
            seen.insert(c)
            w.setBlock(c.x, c.y, c.z, Blocks.id(key))
            out.append((c, key))
        }
        // (the eye 2.5 blocks over the ground where it stands, so the rows are in view looking down a little)
        if let h = w.fieldRaySegment(V3(g.player.pos.x, g.player.eye.y + 40, g.player.pos.z), V3(0, -1, 0), from: 0, to: 120) {
            g.player.pos.y = h.at.y + 1
        }
        let base = g.player.pos
        for k in 0..<14 { put(base + fwd * 5 + side * Float(k - 7), "redstone_wire") }
        for (k, key) in sceneThings.enumerated() { put(base + fwd * 8 + side * Float(k - 6), key) }
        return out
    }

    // For each placed thing: its drawing's vertices (the section's quads inside its cell, not the ground's) against the
    // drawn ground straight under each; the vertices within a quarter block of the ground are its foot.
    static func check(_ w: World, _ things: [(IVec3, String)]) -> String {
        struct Tally { var n = 0, lost = 0, buried = 0, floating = 0; var lo: Float = 9, hi: Float = -9, sum: Float = 0, feet = 0, rise: Float = 0 }
        var byKind: [String: Tally] = [:]
        var meshes: [IVec3: SectionMesh] = [:]
        let drape = GroundDrape()
        for (c, key) in things {
            let cx = floorDiv(c.x, CS), cz = floorDiv(c.z, CS), sy = c.y >> 4
            let sk = IVec3(cx, sy, cz)
            if meshes[sk] == nil, let ch = w.chunks[ChunkKey(x: cx, z: cz)], let nb = w.neighbourhood(ch) {
                meshes[sk] = Mesher.buildSection(nb.0, nb.1, sy: sy, site: w.smoothSite(ch), chunk: (cx, cz))
            }
            var t = byKind[key] ?? Tally()
            t.n += 1
            guard let m = meshes[sk] else { t.lost += 1; byKind[key] = t; continue }
            // (the ground of this section and of those -x, -z and below it, which draw the block rows on those sides)
            drape.clear()
            for (dx, dy, dz) in [(0, 0, 0), (-1, 0, 0), (0, 0, -1), (-1, 0, -1), (0, -1, 0), (-1, -1, 0), (0, -1, -1)] {
                let nk = IVec3(cx + dx, sy + dy, cz + dz)
                if meshes[nk] == nil, nk.y >= 0, let ch = w.chunks[ChunkKey(x: nk.x, z: nk.z)], let nb = w.neighbourhood(ch) {
                    meshes[nk] = Mesher.buildSection(nb.0, nb.1, sy: nk.y, site: w.smoothSite(ch), chunk: (nk.x, nk.z))
                }
                guard let gm = meshes[nk] else { continue }
                let off = SIMD3<Float>(Float(dx * 16), Float(dy * 16), Float(dz * 16))
                func gp(_ q: Int, _ k: Int) -> SIMD3<Float> {
                    let v = gm.opaque[q * 8 + k * 2]
                    return SIMD3<Float>(Float(v & 511), Float((v >> 9) & 511), Float((v >> 18) & 511)) / 16 + off
                }
                for q in 0..<min(gm.groundQuads, gm.opaque.count / 8) {
                    let a = gp(q, 0), b = gp(q, 1), c = gp(q, 2), d = gp(q, 3)
                    drape.add(a, b, c)
                    if d != c { drape.add(a, c, d) }
                }
            }
            let ox = Float(cx * CS), oy = Float(sy * 16), oz = Float(cz * CS)
            let lx = Float(c.x) - ox, ly = Float(c.y) - oy, lz = Float(c.z) - oz
            var found = false, lowest: Float = 9, lowP = SIMD3<Float>(0, 0, 0), lowG: Float = 0
            // (how much the ground rises across the cell: the thing is on a slope)
            var gl: Float = 99, gh: Float = -99
            for (ax, az) in [(0, 0), (1, 0), (0, 1), (1, 1)] as [(Float, Float)] {
                if let h = drape.height(lx + ax, lz + az, top: ly + 1.25, reach: 3) { gl = min(gl, h); gh = max(gh, h) }
            }
            if gh >= gl { t.rise = max(t.rise, gh - gl) }
            // (P387 (4): a thing in the first row over ground in the section below is drawn by that section, 16 up)
            var bufs: [([UInt32], Int, Float)] = [(m.opaque, m.groundQuads, 0), (m.trans, 0, 0)]
            if let mb = meshes[IVec3(cx, sy - 1, cz)] { bufs += [(mb.opaque, mb.groundQuads, -16), (mb.trans, 0, -16)] }
            for (buf, from, dy) in bufs {
                var q = from * 8
                while q + 8 <= buf.count {
                    var ps: [SIMD3<Float>] = []
                    for k in 0..<4 {
                        let v = buf[q + k * 2]
                        ps.append(SIMD3<Float>(Float(v & 511), Float((v >> 9) & 511) + dy * 16, Float((v >> 18) & 511)) / 16)
                    }
                    q += 8
                    let inside = ps.allSatisfy { $0.x >= lx - 0.01 && $0.x <= lx + 1.01 && $0.z >= lz - 0.01 && $0.z <= lz + 1.01
                        && $0.y >= ly - 1 && $0.y <= ly + 1.5 }
                    guard inside else { continue }
                    for p in ps {
                        guard let gh = drape.height(p.x, p.z, top: p.y + 0.5, reach: 3) else { continue }
                        let gap = p.y - gh
                        found = true
                        if gap < lowest { lowP = p; lowG = gh }
                        lowest = min(lowest, gap)
                        guard gap < 0.25 else { continue }
                        t.feet += 1; t.sum += gap; t.lo = min(t.lo, gap); t.hi = max(t.hi, gap)
                    }
                }
            }
            if !found { t.lost += 1 } else if lowest < -0.01 { t.buried += 1 } else if lowest > 0.13 { t.floating += 1 }
            if ProcessInfo.processInfo.environment["BS_DRAPE_DEBUG"] != nil {
                print(String(format: "  %@ at %d %d %d (section-local %.0f %.0f %.0f): lowest %.3f (vertex %.3f %.3f %.3f, ground %.3f), rise %.2f, below %@", key, c.x, c.y, c.z, lx, ly, lz,
                             lowest, lowP.x, lowP.y, lowP.z, lowG, gh - gl, Blocks.key(w.block(c.x, c.y - 1, c.z))))
            }
            byKind[key] = t
        }
        var lines = ["groundthings (P382, drape \(GroundDrape.enabled ? "on" : "off")): gap = drawing minus drawn ground under it, blocks"]
        for key in ["redstone_wire"] + sceneThings + byKind.keys.sorted() where byKind[key] != nil {
            let t = byKind[key]!
            byKind[key] = nil
            lines.append(String(format: "  %@: %d placed, %d lowest point under the ground, %d floating over 0.13, %d not found; foot gaps %.3f...%.3f (mean %.3f, %d points); steepest cell rise %.2f",
                                key, t.n, t.buried, t.floating, t.lost, t.feet > 0 ? t.lo : 0, t.feet > 0 ? t.hi : 0,
                                t.feet > 0 ? t.sum / Float(t.feet) : 0, t.feet, t.rise))
        }
        return lines.joined(separator: "\n")
    }
}
