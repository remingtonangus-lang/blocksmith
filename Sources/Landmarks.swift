import Foundation
import simd

// Big landmarks (Future ideas #9): rare regional landforms big enough to navigate by.
// Volcanoes: one chance per 1280-block cell (about one in six cells, on land away from the coast): a cone 150-210
// blocks in radius rising 110-170 above the surrounding ground, ridged flanks, a crater with a lava lake, and lava
// channels running down three flanks. They are shaped in the terrain's node lattice (after rivers and lakes), so
// column heights, the 3D density fill, groundY, the map and the biome all agree. Generation fills the crater lake and
// sinks the channels into the slope (WorldGen.generate); the lava sources are static until something touches them,
// so flows stay bounded. Far away, a coarse impostor keeps the cone and its plume on the horizon (LandmarkRender).

struct Volcano {
    var x: Float = 0, z: Float = 0
    var r: Float = 0          // foot radius
    var base: Float = 0       // surrounding ground (display height)
    var peak: Float = 0       // rim height above base
    var crater: Float = 0     // crater radius
    var depth: Float = 0      // crater depth below the rim
    var arms: SIMD3<Float> = .zero   // lava channel headings (radians)
    var exists = false
    static let none = Volcano()
    var rim: Float { base + peak }
    var lavaLevel: Float { rim - depth + 7 }
}

extension Terrain {
    static let volcanoCell = 1280

    // The volcano of a cell, if any (deterministic, cached).
    func volcano(cell cx: Int, _ cz: Int) -> Volcano {
        volcanoCache.get(cx, cz) {
            let c = Terrain.volcanoCell
            let h0 = hashf(cx, 911, cz, s32 ^ 0x701CA)
            guard h0 < 0.17 else { return .none }
            let m = Float(260)
            let x = Float(cx * c) + m + hashf(cx, 912, cz, s32 ^ 0x701CB) * (Float(c) - 2 * m)
            let z = Float(cz * c) + m + hashf(cx, 913, cz, s32 ^ 0x701CC) * (Float(c) - 2 * m)
            let mac = macroLerp(Int(x), Int(z))
            let ground = detail(x, z, mac)
            // On land, away from the coast and the highest ranges (a cone on a 200-block massif would top the world).
            guard ground > SEA_D + 3, ground < SEA_D + 70, mac.c > 0.04 else { return .none }
            var v = Volcano()
            v.x = x; v.z = z
            v.r = 150 + hashf(cx, 914, cz, s32 ^ 0x701CD) * 60
            v.base = ground
            let room: Float = Float(CH - YOFF - 24) - ground
            v.peak = min(room, 110 + hashf(cx, 915, cz, s32 ^ 0x701CE) * 60)
            v.crater = v.r * (0.13 + 0.04 * hashf(cx, 916, cz, s32 ^ 0x701CF))
            v.depth = 22 + hashf(cx, 917, cz, s32 ^ 0x701D0) * 10
            let a0 = hashf(cx, 918, cz, s32 ^ 0x701D1) * 2 * Float.pi
            v.arms = SIMD3<Float>(a0, a0 + 2.2 + hashf(cx, 919, cz, s32) * 0.6, a0 + 4.1 + hashf(cx, 920, cz, s32) * 0.5)
            v.exists = true
            return v
        }
    }

    // Volcanoes whose footprint may reach (x, z).
    func volcanoes(near x: Float, _ z: Float, reach: Float = 260) -> [Volcano] {
        let c = Float(Terrain.volcanoCell)
        let cx0 = Int(floorf((x - reach) / c)), cx1 = Int(floorf((x + reach) / c))
        let cz0 = Int(floorf((z - reach) / c)), cz1 = Int(floorf((z + reach) / c))
        var out: [Volcano] = []
        for cz in cz0...cz1 { for cx in cx0...cx1 {
            let v = volcano(cell: cx, cz)
            if v.exists { out.append(v) }
        } }
        return out
    }

    // Shapes a lattice node inside a volcano's footprint (called after rivers and lakes are carved).
    func applyVolcanoes(_ n: inout Node, _ fx: Float, _ fz: Float) {
        // The (at most four) cells whose volcano could reach this node; no allocation per node.
        let c = Float(Terrain.volcanoCell), reach: Float = 260
        let cx0 = Int(floorf((fx - reach) / c)), cx1 = Int(floorf((fx + reach) / c))
        let cz0 = Int(floorf((fz - reach) / c)), cz1 = Int(floorf((fz + reach) / c))
        for cz in cz0...cz1 { for cx in cx0...cx1 {
            let v = volcano(cell: cx, cz)
            guard v.exists else { continue }
            shapeVolcano(&n, fx, fz, v)
        } }
    }

    private func shapeVolcano(_ n: inout Node, _ fx: Float, _ fz: Float, _ v: Volcano) {
        do {
            let dx = fx - v.x, dz = fz - v.z
            let d = (dx * dx + dz * dz).squareRoot()
            guard d < v.r else { return }
            let t = d / v.r, tc = v.crater / v.r
            let ang = atan2f(dz, dx)
            var cone: Float
            if d > v.crater {
                // Concave flanks (steep near the rim, spreading at the foot) with radial ridges and gullies.
                let u = (1 - t) / (1 - tc)
                let ridge: Float = (sinf(ang * 11 + 2 * sinf(ang * 3)) * 0.6 + sinf(ang * 23) * 0.4) * 4 * (1 - t) * t * 4
                cone = v.base + v.peak * powf(u, 1.55) + ridge
            } else {
                // Crater: a bowl under the rim with a flat floor.
                let q = d / v.crater
                cone = v.rim - v.depth * (1 - Terrain.smooth(0.55, 1.0, q)) - 3 * Terrain.smooth(0.85, 1.0, q) + 3
            }
            let w = Terrain.smooth(1.0, 0.72, t)           // blend into the surrounding ground at the foot
            let raised = max(n.h, cone)
            n.h = n.h + (raised - n.h) * w
            if w > 0.25 {
                // No rivers or lakes on the cone (they were routed before it rose).
                n.wl = SEA_D; n.rv = 99; n.dry = 0; n.delta = 0
            }
            n.vol = max(n.vol, w)
            if d < v.crater * 0.92 { n.lava = max(n.lava, v.lavaLevel) }
            // Lava channels down three flanks, from the rim to two thirds of the way down.
            if d > v.crater && d < v.r * 0.68 {
                for a in [v.arms.x, v.arms.y, v.arms.z] {
                    var da = ang - a
                    while da > .pi { da -= 2 * .pi }
                    while da < -.pi { da += 2 * .pi }
                    let lateral = abs(sinf(da)) * d
                    // Channels meander a little and narrow downhill.
                    let wobble = sinf(d * 0.045 + a * 3) * 6
                    if cosf(da) > 0.5 && abs(lateral - abs(wobble) * 0.3) < 3.2 - t * 1.5 {
                        n.h -= 1.2
                        n.flow = 1
                    }
                }
            }
        }
    }

    // The nearest volcano centre to a point (harness --feature volcano, landmark impostors).
    func nearestVolcano(_ x: Float, _ z: Float, cells: Int = 4) -> Volcano? {
        let c = Terrain.volcanoCell
        let cx0 = Int(floorf(x / Float(c))), cz0 = Int(floorf(z / Float(c)))
        var best: Volcano?
        var bd = Float.infinity
        for dz in -cells...cells { for dx in -cells...cells {
            let v = volcano(cell: cx0 + dx, cz0 + dz)
            guard v.exists else { continue }
            let d = simd_length(V2(v.x - x, v.z - z))
            if d < bd { bd = d; best = v }
        } }
        return best
    }
}
