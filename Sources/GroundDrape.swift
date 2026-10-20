import Foundation
import simd

// P382 (Remington, Oct 19: "things on the ground follow the drawn ground"): in a field world the ground is drawn as the
// field's surface, not as block tops, so anything drawn on a block floor (copper wire, rails, carpets, plates, torches,
// signs...) was half buried on one side of a slope and floating on the other, and cut off at the cell's edge. The mesher
// keeps the section's drawn ground triangles here (after the adaptive ground, so it is the ground as drawn), bucketed by
// column, and asks them for the ground's height under any point of the section: the circuit stays on its cell grid,
// its drawing lies on the surface.
final class GroundDrape {
    // BS_DRAPE=0: things drawn on their cell floors as before (before/after checks).
    static let enabled = ProcessInfo.processInfo.environment["BS_DRAPE"] != "0"
    static let debug = ProcessInfo.processInfo.environment["BS_DRAPE_DEBUG"] != nil
    static let lift: Float = 1.0 / 16                // how far a draped strip floats over the ground (never under it)
    static let step = 4                               // a draped strip is split every 4/16 block to follow the ground

    private static let N = 18                         // columns -1...16 (the section's ground reaches a little past it)
    private var tri: [Float] = []                     // 9 floats per triangle: section-local blocks
    private var cells = [[Int32]](repeating: [], count: GroundDrape.N * GroundDrape.N)
    private var used: [Int] = []
    private(set) var valid = false

    func clear() {
        for c in used { cells[c].removeAll(keepingCapacity: true) }
        used.removeAll(keepingCapacity: true)
        tri.removeAll(keepingCapacity: true)
        valid = false
    }

    // The ground quads in buf[from..<to] (words; 4 vertices of 2 words each, lone triangles as (a, b, c, c)). Only
    // triangles facing up count (corners run counter-clockwise seen from outside): ceilings over a thing aren't its floor.
    func build(_ buf: UnsafeMutablePointer<UInt32>, from g0: Int, to g1: Int) {
        clear()
        @inline(__always) func p(_ w: UInt32) -> SIMD3<Float> {
            SIMD3<Float>(Float(w & 511), Float((w >> 9) & 511), Float((w >> 18) & 511)) * (1.0 / 16)
        }
        var q = g0
        while q + 8 <= g1 {
            let a = p(buf[q]), b = p(buf[q + 2]), c = p(buf[q + 4]), d = p(buf[q + 6])
            add(a, b, c)
            if d != c { add(a, c, d) }
            q += 8
        }
        valid = !tri.isEmpty
    }

    func add(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let ny = (b.z - a.z) * (c.x - a.x) - (b.x - a.x) * (c.z - a.z)     // (the cross product's y)
        guard ny > 1e-5 else { return }
        valid = true
        let t = Int32(tri.count / 9)
        tri.append(a.x); tri.append(a.y); tri.append(a.z)       // (no array literal: no allocation per triangle)
        tri.append(b.x); tri.append(b.y); tri.append(b.z)
        tri.append(c.x); tri.append(c.y); tri.append(c.z)
        let x0 = max(-1, Int(floor(min(a.x, b.x, c.x)))), x1 = min(16, Int(floor(max(a.x, b.x, c.x))))
        let z0 = max(-1, Int(floor(min(a.z, b.z, c.z)))), z1 = min(16, Int(floor(max(a.z, b.z, c.z))))
        guard x0 <= x1 && z0 <= z1 else { return }
        for z in z0...z1 { for x in x0...x1 {
            let k = (x + 1) + (z + 1) * GroundDrape.N
            if cells[k].isEmpty { used.append(k) }
            cells[k].append(t)
        } }
    }

    // The drawn ground's height (section-local blocks) at (x, z): the highest triangle there at or under `top`, no lower
    // than `top - reach`; nil if the section draws no ground there.
    func height(_ x: Float, _ z: Float, top: Float, reach: Float = 2.5) -> Float? {
        guard valid else { return nil }
        let cx = max(-1, min(16, Int(floor(x)))), cz = max(-1, min(16, Int(floor(z))))
        var best: Float = -.greatestFiniteMagnitude
        tri.withUnsafeBufferPointer { t in
            for k in cells[(cx + 1) + (cz + 1) * GroundDrape.N] {
                let o = Int(k) * 9
                let ax = t[o], az = t[o + 2], bx = t[o + 3], bz = t[o + 5], qx = t[o + 6], qz = t[o + 8]
                let d = (bz - qz) * (ax - qx) + (qx - bx) * (az - qz)
                if abs(d) < 1e-9 { continue }
                let u = ((bz - qz) * (x - qx) + (qx - bx) * (z - qz)) / d
                let v = ((qz - az) * (x - qx) + (ax - qx) * (z - qz)) / d
                let w = 1 - u - v
                let e: Float = -1e-4
                guard u >= e && v >= e && w >= e else { continue }
                let y = u * t[o + 1] + v * t[o + 4] + w * t[o + 7]
                if y <= top && y >= top - reach && y > best { best = y }
            }
        }
        return best > -.greatestFiniteMagnitude ? best : nil
    }

    // As height, but where the section draws no ground (its -x and -z sides: the block row there is drawn by the
    // neighbour, which owns the quads round the shared lattice line) the nearest up-facing triangle within a block and
    // a quarter, its plane carried on to the point.
    func heightNear(_ x: Float, _ z: Float, top: Float, reach: Float = 2.5) -> Float? {
        if let h = height(x, z, top: top, reach: reach) { return h }
        guard valid else { return nil }
        let cx = Int(floor(x)), cz = Int(floor(z))
        var bestD: Float = 1.25 * 1.25, bestY: Float? = nil
        tri.withUnsafeBufferPointer { t in
            for bz in max(-1, cz - 1)...min(16, cz + 1) { for bx in max(-1, cx - 1)...min(16, cx + 1) {
                for k in cells[(bx + 1) + (bz + 1) * GroundDrape.N] {
                    let o = Int(k) * 9
                    // (seen from above: the squared distance to the triangle's nearest edge; adaptive ground triangles
                    // are big, so not to its middle)
                    @inline(__always) func edge(_ p: Int, _ q: Int) -> Float {
                        let ax = t[o + p], az = t[o + p + 2], ex = t[o + q] - ax, ez = t[o + q + 2] - az
                        let l = ex * ex + ez * ez
                        let s = l > 1e-9 ? max(0, min(1, ((x - ax) * ex + (z - az) * ez) / l)) : 0
                        let dx = ax + ex * s - x, dz = az + ez * s - z
                        return dx * dx + dz * dz
                    }
                    let d = min(edge(0, 3), edge(3, 6), edge(6, 0))
                    guard d < bestD else { continue }
                    let e1x = t[o + 3] - t[o], e1y = t[o + 4] - t[o + 1], e1z = t[o + 5] - t[o + 2]
                    let e2x = t[o + 6] - t[o], e2y = t[o + 7] - t[o + 1], e2z = t[o + 8] - t[o + 2]
                    let nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x
                    guard abs(ny) > 1e-6 else { continue }
                    let y = t[o + 1] - (nx * (x - t[o]) + nz * (z - t[o + 2])) / ny
                    guard y <= top && y >= top - reach else { continue }
                    bestD = d; bestY = y
                }
            } }
        }
        return bestY
    }

    // What a block standing on field ground does (per state): 0 stays on its cell floor, 1 rests on the ground whole,
    // lowered or raised by the ground's height under its middle (torches, standing signs, lanterns, candles, repeaters,
    // comparators, daylight sensors, skulls, pickles, eggs, banners), 2 lies on it bent to the ground's shape (anything
    // two sixteenths thick or less: carpets, pressure plates). Built pieces (slabs, stairs, doors, fences, chests...)
    // stay on the grid the player builds on.
    static let seat: [UInt8] = {
        let floorThings: Set<String> = ["torch", "sign", "lantern", "candle", "repeater", "comparator", "daylight", "skull",
                                        "pickle", "egg", "banner", "plate"]
        var out = [UInt8](repeating: 0, count: Blocks.render.count)
        for b in 0..<out.count where Blocks.render[b] == RenderType.model.rawValue {
            let bx = Blocks.boxes[b]
            guard !bx.isEmpty, bx.allSatisfy({ $0.leanX == 0 && $0.leanZ == 0 }) else { continue }
            var y0 = 16, y1 = 0, x0 = 16, x1 = 0, z0 = 16, z1 = 0
            for q in bx {
                y0 = min(y0, Int(q.y0)); y1 = max(y1, Int(q.y1))
                x0 = min(x0, Int(q.x0)); x1 = max(x1, Int(q.x1)); z0 = min(z0, Int(q.z0)); z1 = max(z1, Int(q.z1))
            }
            guard y0 == 0 && x1 - x0 >= 2 && z1 - z0 >= 2 else { continue }        // (on the floor; not a plate on a wall)
            if y1 <= 2 && Blocks.shape[b] != "rail" { out[b] = 2 } else if floorThings.contains(Blocks.shape[b]) { out[b] = 1 }
        }
        return out
    }()

    // The rest of a thing that GroundDrape.seat moves (1/16, section-local cell (lx, ly, lz)): its offset to the ground
    // under its middle, -12...12 and never under the section's floor; nil where there is no drawn ground under it.
    func seatOffset(_ lx: Int, _ ly: Int, _ lz: Int) -> Int? {
        guard let h = heightNear(Float(lx) + 0.5, Float(lz) + 0.5, top: Float(ly) + 1.25) else { return nil }
        return max(-ly * 16, max(-12, min(12, Int(((h - Float(ly)) * 16).rounded()))))
    }
}

extension World {
    // P382: the same offset at run time (blocks), for what is drawn beside the section mesh at a seated thing's cell (a
    // standing sign's text): the field's surface under the cell's middle, rounded as the mesher rounds it.
    func groundSeat(_ x: Int, _ y: Int, _ z: Int) -> Float {
        guard fieldTerrain && GroundDrape.enabled, GroundDrape.seat[Int(block(x, y, z))] != 0,
              SmoothTerrain.natural[Int(block(x, y - 1, z))] else { return 0 }
        let o = V3(Float(x) + 0.5, Float(y) + 1.25, Float(z) + 0.5)
        guard let h = fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 2.5) else { return 0 }
        return Float(max(-12, min(12, Int(((h.at.y - Float(y)) * 16).rounded())))) / 16
    }
}

extension Game {
    // P382: in a field world a thing laid on the ground goes into the cell over the point aimed at on the drawn surface
    // (the circuit's cell there), not the one past the face the ray's dominant axis named (on a slope, beside the hill).
    // Nil when the aim isn't at ground facing up, or that cell can't take it.
    func groundCell(_ t: (hit: IVec3, normal: IVec3), for b: BlockID) -> IVec3? {
        let rt = Blocks.render[Int(b)]
        guard rt == RenderType.wire.rawValue || rt == RenderType.rail.rawValue || rt == RenderType.cross.rawValue
                || GroundDrape.seat[Int(b)] != 0,
              let g = targetGround, g.cell == t.hit, g.normal.y >= 0.5 else { return nil }
        if GroundDrape.seat[Int(b)] == 1 && t.normal.y != 1 { return nil }     // (a torch or sign aimed sideways goes on a wall)
        let c = IVec3(Int(floor(g.at.x)), Int(floor(g.at.y + 0.5)), Int(floor(g.at.z)))
        guard Blocks.replaceable[Int(world.materialAt(c.x, c.y, c.z))], world.opaqueAt(c.x, c.y - 1, c.z) else { return nil }
        return c
    }
}
