import simd

// All textures are procedurally painted 16x16 pixel art (original, no external assets).
enum TextureGen {
    static let S = 16

    static func base() -> [UInt8] {
        var data = [UInt8](repeating: 0, count: S * S * 4 * T.count)
        func put(_ layer: Int, _ f: (Int, Int) -> V4) {
            for y in 0..<S {
                for x in 0..<S {
                    let c = simd_clamp(f(x, y), V4(repeating: 0), V4(repeating: 1))
                    let i = ((layer * S + y) * S + x) * 4
                    data[i] = UInt8(c.x * 255)
                    data[i + 1] = UInt8(c.y * 255)
                    data[i + 2] = UInt8(c.z * 255)
                    data[i + 3] = UInt8(c.w * 255)
                }
            }
        }
        func r(_ x: Int, _ y: Int, _ salt: Int) -> Float { hashf(x, y, salt, 777) }
        func rgb(_ r: Float, _ g: Float, _ b: Float, _ k: Float, _ a: Float = 1) -> V4 { V4(r * k, g * k, b * k, a) }
        func stone(_ x: Int, _ y: Int) -> V4 {
            var v: Float = 0.47 + (r(x, y, 1) - 0.5) * 0.12
            if r(x / 2, y, 11) < 0.14 { v -= 0.07 }
            return V4(v, v, v, 1)
        }
        func dirt(_ x: Int, _ y: Int) -> V4 {
            let speck: Float = r(x, y, 31) < 0.1 ? 0.78 : 1
            return rgb(0.53, 0.38, 0.26, (0.82 + 0.3 * r(x, y, 3)) * speck)
        }
        func grass(_ x: Int, _ y: Int) -> V4 { rgb(0.4, 0.64, 0.25, 0.78 + 0.35 * r(x, y, 2)) }
        func snowC(_ x: Int, _ y: Int) -> V4 { rgb(0.95, 0.97, 1.0, 0.94 + 0.06 * r(x, y, 19)) }
        func edge(_ x: Int, _ base: Int) -> Int { base + (r(x, 0, 21) > 0.5 ? 1 : 0) + (r(x, 0, 22) > 0.8 ? 1 : 0) }

        put(T.stone, stone)
        put(T.grassTop, grass)
        put(T.grassSide) { x, y in y < edge(x, 3) ? grass(x, y) : dirt(x, y) }
        put(T.dirt, dirt)

        var pts: [V2] = []
        for k in 0..<8 { pts.append(V2(r(k, 0, 5) * 16, r(k, 1, 5) * 16)) }
        put(T.cobble) { x, y in
            let p = V2(Float(x) + 0.5, Float(y) + 0.5)
            var d1: Float = 1e9, d2: Float = 1e9, k1 = 0
            for (k, q) in pts.enumerated() {
                for oy in -1...1 {
                    for ox in -1...1 {
                        let d = simd_distance(p, q + V2(Float(ox * 16), Float(oy * 16)))
                        if d < d1 { d2 = d1; d1 = d; k1 = k } else if d < d2 { d2 = d }
                    }
                }
            }
            if d2 - d1 < 1.2 { return V4(0.26, 0.26, 0.26, 1) }
            let v: Float = 0.4 + r(k1, 9, 9) * 0.2 + (r(x, y, 10) - 0.5) * 0.08
            return V4(v, v, v, 1)
        }
        put(T.planks) { x, y in
            let row = y / 4
            let seam = (row * 7 + 3) % 16
            var k: Float = 0.88 + 0.12 * r(x / 4, y, 41) + (r(x, row, 42) - 0.5) * 0.08
            if y % 4 == 3 || x == seam { k = 0.62 }
            return rgb(0.66, 0.52, 0.32, k)
        }
        put(T.bedrock) { x, y in
            let v: Float = 0.12 + r(x, y, 6) * 0.42
            return V4(v, v, v, 1)
        }
        put(T.sand) { x, y in rgb(0.86, 0.81, 0.6, 0.92 + 0.12 * r(x, y, 7)) }
        put(T.gravel) { x, y in
            let n = r(x, y, 8)
            let v: Float = n < 0.33 ? 0.36 : (n < 0.66 ? 0.5 : 0.62)
            return V4(v, v * 0.97, v * 0.95, 1)
        }
        func bark(_ layer: Int, _ c: V3) {
            put(layer) { x, y in
                let stripe = (x + Int(r(0, y / 5, 9 + layer) * 2)) % 4 == 0
                return rgb(c.x, c.y, c.z, stripe ? 0.7 : 0.9 + 0.12 * r(x, y, 10 + layer))
            }
        }
        func rings(_ layer: Int, _ barkC: V3, _ wood: V3) {
            put(layer) { x, y in
                let dx = Float(x) - 7.5, dy = Float(y) - 7.5
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 6.9 { return rgb(barkC.x, barkC.y, barkC.z, 0.85) }
                let ring = Int(d * 1.1) % 2 == 0
                return rgb(wood.x, wood.y, wood.z, ring ? 1 : 0.86)
            }
        }
        func foliage(_ layer: Int, _ c: V3, holes: Float, _ salt: Int) {
            put(layer) { x, y in
                if r(x, y, salt) < holes { return V4(0, 0, 0, 0) }
                return rgb(c.x, c.y, c.z, 0.7 + 0.5 * r(x, y, salt + 1))
            }
        }
        bark(T.logSide, V3(0.42, 0.32, 0.2))
        rings(T.logTop, V3(0.42, 0.32, 0.2), V3(0.72, 0.58, 0.36))
        bark(T.spruceSide, V3(0.29, 0.21, 0.14))
        rings(T.spruceTop, V3(0.29, 0.21, 0.14), V3(0.6, 0.46, 0.3))
        rings(T.birchTop, V3(0.86, 0.85, 0.8), V3(0.8, 0.7, 0.52))
        put(T.birchSide) { x, y in
            // Pale bark with dark horizontal lenticels.
            let dash = y % 5 == 2 && r(x / 3, y, 26) < 0.55
            if dash || r(x, y, 27) < 0.05 { return rgb(0.2, 0.19, 0.17, 0.9 + 0.2 * r(x, y, 28)) }
            return rgb(0.88, 0.87, 0.83, 0.9 + 0.1 * r(x, y, 29))
        }
        foliage(T.leaves, V3(0.24, 0.5, 0.17), holes: 0.2, 12)
        foliage(T.birchLeaves, V3(0.4, 0.58, 0.24), holes: 0.22, 32)
        foliage(T.spruceLeaves, V3(0.15, 0.33, 0.2), holes: 0.12, 34)
        put(T.glass) { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return V4(0.75, 0.86, 0.92, 1) }
            if (x == y || x == y + 1) && x > 3 && x < 8 { return V4(0.95, 0.98, 1, 1) }
            return V4(0, 0, 0, 0)
        }
        put(T.water) { x, y in rgb(0.2, 0.36, 0.82, 0.85 + 0.2 * r(x / 2, y, 14), 0.72) }
        func ore(_ layer: Int, _ c: V3, _ salt: Int) {
            put(layer) { x, y in
                if r(x / 3, y / 3, salt) < 0.4 && r(x, y, salt + 1) < 0.7 {
                    let k: Float = 0.85 + 0.3 * r(x, y, salt + 2)
                    return V4(c.x * k, c.y * k, c.z * k, 1)
                }
                return stone(x, y)
            }
        }
        ore(T.coal, V3(0.1, 0.1, 0.1), 50)
        ore(T.iron, V3(0.82, 0.66, 0.52), 60)
        ore(T.gold, V3(0.98, 0.84, 0.22), 70)
        ore(T.diamond, V3(0.36, 0.92, 0.88), 80)
        put(T.brick) { x, y in
            let row = y / 4
            if y % 4 == 3 || x == (row % 2 == 0 ? 7 : 15) { return rgb(0.72, 0.7, 0.66, 0.9 + 0.1 * r(x, y, 16)) }
            return rgb(0.62, 0.29, 0.21, 0.85 + 0.3 * r(x, y, 15))
        }
        put(T.snow, snowC)
        put(T.snowSide) { x, y in y < edge(x, 2) ? snowC(x, y) : dirt(x, y) }
        put(T.cactusSide) { x, y in
            if r(x, y, 17) < 0.06 { return rgb(0.9, 0.9, 0.7, 1) }
            return rgb(0.18, 0.52, 0.2, x % 4 == 1 ? 0.72 : 0.92 + 0.1 * r(x, y, 18))
        }
        put(T.cactusTop) { x, y in
            let border = x == 0 || y == 0 || x == 15 || y == 15
            return rgb(0.3, 0.62, 0.28, border ? 0.7 : 0.95 + 0.08 * r(x, y, 20))
        }
        put(T.stoneBrick) { x, y in
            let row = y / 8
            if y % 8 == 7 || x == (row == 0 ? 15 : 7) { return V4(0.32, 0.32, 0.32, 1) }
            var v: Float = 0.5 + (r(x, y, 23) - 0.5) * 0.08
            if y % 8 == 0 { v = 0.6 }
            return V4(v, v, v, 1)
        }
        put(T.sandstoneSide) { x, y in
            var k: Float = 0.96 + 0.06 * r(x, y, 24)
            if y == 3 || y == 4 { k *= 0.86 }
            if y >= 13 { k *= 0.93 }
            return rgb(0.86, 0.79, 0.56, k)
        }
        put(T.sandstoneTop) { x, y in rgb(0.88, 0.82, 0.6, 0.95 + 0.07 * r(x, y, 25)) }
        return data
    }

    // Alpha-weighted box-filter mip chain (keeps leaves/glass from darkening at distance).
    static func mipChain() -> [[UInt8]] {
        var levels = [base()]
        var size = S
        let taps = [(0, 0), (1, 0), (0, 1), (1, 1)]
        while size > 1 {
            let prev = levels[levels.count - 1]
            let ns = size / 2
            var next = [UInt8](repeating: 0, count: ns * ns * 4 * T.count)
            for l in 0..<T.count {
                for y in 0..<ns {
                    for x in 0..<ns {
                        var acc = V3(repeating: 0)
                        var aSum: Float = 0
                        for (dx, dy) in taps {
                            let i = ((l * size + y * 2 + dy) * size + x * 2 + dx) * 4
                            let a = Float(prev[i + 3]) / 255
                            acc += V3(Float(prev[i]), Float(prev[i + 1]), Float(prev[i + 2])) * a
                            aSum += a
                        }
                        let o = ((l * ns + y) * ns + x) * 4
                        if aSum > 0 {
                            next[o] = UInt8(min(255, acc.x / aSum))
                            next[o + 1] = UInt8(min(255, acc.y / aSum))
                            next[o + 2] = UInt8(min(255, acc.z / aSum))
                        }
                        next[o + 3] = UInt8(min(255, aSum / 4 * 255))
                    }
                }
            }
            levels.append(next)
            size = ns
        }
        return levels
    }
}
