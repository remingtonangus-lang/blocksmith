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

struct Canyon {
    var x0: Float = 0, z0: Float = 0, dx: Float = 1, dz: Float = 0, len: Float = 0
    var depth: Float = 0, wTop: Float = 0, wFloor: Float = 0
    var amp: Float = 0, wave: Float = 200, phase: Float = 0
    var f0: Float = 0, f1: Float = 0           // floor height at the start / end (display)
    var exists = false
    static let none = Canyon()
}

extension Terrain {
    static let volcanoCell = 1280
    static let canyonCell = 1536

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

    // MARK: Canyons
    // One chance in five per 1536-block cell: a meandering canyon 700-1100 blocks long, 55-90 deep, its walls stepped
    // in terraces of banded rock, a river along its floor running from the higher end to the lower; it tapers out at
    // both ends. Only ever cuts (never raises) the ground.

    func canyon(cell cx: Int, _ cz: Int) -> Canyon {
        canyonCache.get(cx, cz) {
            let c = Float(Terrain.canyonCell)
            guard hashf(cx, 931, cz, s32 ^ 0xCA41) < 0.2 else { return .none }
            var k = Canyon()
            let mx = Float(cx) * c + 400 + hashf(cx, 932, cz, s32 ^ 0xCA42) * (c - 800)
            let mz = Float(cz) * c + 400 + hashf(cx, 933, cz, s32 ^ 0xCA43) * (c - 800)
            let a = hashf(cx, 934, cz, s32 ^ 0xCA44) * Float.pi
            k.len = 700 + hashf(cx, 935, cz, s32 ^ 0xCA45) * 400
            k.dx = cosf(a); k.dz = sinf(a)
            k.x0 = mx - k.dx * k.len / 2; k.z0 = mz - k.dz * k.len / 2
            k.depth = 55 + hashf(cx, 936, cz, s32 ^ 0xCA46) * 35
            k.wTop = 38 + hashf(cx, 937, cz, s32 ^ 0xCA47) * 22
            k.wFloor = 6 + hashf(cx, 938, cz, s32 ^ 0xCA48) * 5
            k.amp = 30 + hashf(cx, 939, cz, s32 ^ 0xCA49) * 40
            k.wave = 160 + hashf(cx, 940, cz, s32 ^ 0xCA4A) * 120
            k.phase = hashf(cx, 941, cz, s32 ^ 0xCA4B) * 6.28
            // Land at both ends and in the middle, away from the coast; the floor runs downhill from the higher end.
            let ends: [(Float, Float)] = [(k.x0, k.z0), (mx, mz), (k.x0 + k.dx * k.len, k.z0 + k.dz * k.len)]
            var hs: [Float] = []
            for (x, z) in ends {
                let m = macroLerp(Int(x), Int(z))
                let h = detail(x, z, m)
                guard h > SEA_D + 12, m.c > 0.03 else { return .none }
                hs.append(h)
            }
            if hs[2] > hs[0] {                                     // start at the higher end
                k.x0 += k.dx * k.len; k.z0 += k.dz * k.len; k.dx = -k.dx; k.dz = -k.dz; hs.reverse()
            }
            k.f0 = max(SEA_D + 3, hs[0] - k.depth)
            k.f1 = max(SEA_D + 2, min(k.f0 - 4, hs[2] - k.depth))
            k.exists = true
            return k
        }
    }

    // Shapes a lattice node inside a canyon (called after rivers, before volcanoes).
    func applyCanyons(_ n: inout Node, _ fx: Float, _ fz: Float) {
        let c = Float(Terrain.canyonCell), reach: Float = 700
        let cx0 = Int(floorf((fx - reach) / c)), cx1 = Int(floorf((fx + reach) / c))
        let cz0 = Int(floorf((fz - reach) / c)), cz1 = Int(floorf((fz + reach) / c))
        for cz in cz0...cz1 { for cx in cx0...cx1 {
            let k = canyon(cell: cx, cz)
            guard k.exists else { continue }
            shapeCanyon(&n, fx, fz, k)
        } }
    }

    private func shapeCanyon(_ n: inout Node, _ fx: Float, _ fz: Float, _ k: Canyon) {
        // Quick reject: outside the canyon's bounding box.
        let pad = k.amp + k.wTop + 8
        let x1 = k.x0 + k.dx * k.len, z1 = k.z0 + k.dz * k.len
        guard fx > min(k.x0, x1) - pad, fx < max(k.x0, x1) + pad, fz > min(k.z0, z1) - pad, fz < max(k.z0, z1) + pad else { return }
        // Nearest point of the meandering centre line: coarse samples, then a finer pass round the best.
        func centre(_ s: Float) -> (Float, Float) {
            let off = k.amp * sinf(s / k.wave * 2 * .pi + k.phase) + k.amp * 0.35 * sinf(s / (k.wave * 0.37) + k.phase * 2)
            return (k.x0 + k.dx * s - k.dz * off, k.z0 + k.dz * s + k.dx * off)
        }
        var best: Float = .infinity, bs: Float = 0
        var s: Float = 0
        while s <= k.len {
            let (cx, cz) = centre(s)
            let d2 = (fx - cx) * (fx - cx) + (fz - cz) * (fz - cz)
            if d2 < best { best = d2; bs = s }
            s += 12
        }
        var s2 = max(0, bs - 12)
        while s2 <= min(k.len, bs + 12) {
            let (cx, cz) = centre(s2)
            let d2 = (fx - cx) * (fx - cx) + (fz - cz) * (fz - cz)
            if d2 < best { best = d2; bs = s2 }
            s2 += 2
        }
        let d = best.squareRoot()
        guard d < k.wTop else { return }
        let taper = Terrain.smooth(0, 160, bs) * Terrain.smooth(k.len, k.len - 160, bs)
        guard taper > 0.01 else { return }
        let floorLine = k.f0 + (k.f1 - k.f0) * bs / k.len
        let floorH = floorLine + k.depth * (1 - taper)
        // Terraced walls: five steps with steep risers between benches.
        var target = floorH
        if d > k.wFloor {
            let f = min(1, (d - k.wFloor) / (k.wTop - k.wFloor))
            let g = f * 5
            let step = floorf(g)
            let terr = (step + Terrain.smooth(0.55, 0.95, g - step)) / 5
            target = floorH + k.depth * taper * 1.15 * terr
        }
        if target < n.h {
            n.h = target
            n.cyn = max(n.cyn, Terrain.smooth(k.wTop, k.wTop * 0.6, d) * taper)
            if d < k.wFloor * 0.75 && taper > 0.5 {
                // The canyon river.
                n.wl = max(n.wl, floorH + 1.2)
                n.rv = min(n.rv, d / max(1, k.wFloor))
            } else if n.wl > n.h && n.rv > 1 {
                n.wl = SEA_D                                       // no stray lake water on the benches
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
