import Foundation
import simd

// Held items as solid, extruded models (Oct 11 Quest playtest P17: five stacked sprites looked like five pieces stitched
// together and went see-through edge-on). Each layer's alpha is kept as a 16 x 16 mask when the textures upload (Quest
// SceneRenderer.uploadTextures); the model is the sprite on both faces plus a side wall along every edge of the opaque
// texels, each wall coloured by its texel, so the item is one closed shape from every angle.
enum ItemMasks {
    static let grid = 16
    private static var masks: [[UInt16]] = []         // per layer: 16 rows, bit x set when texel (x, row) is opaque
    private static let lock = NSLock()

    // RGBA8 layers `range` at `size` px (layer-major), as uploaded: each 16-grid cell is opaque when most of its texels are.
    static func record(_ rgba: UnsafeBufferPointer<UInt8>, size n: Int, layers range: Range<Int>) {
        let g = grid, k = max(1, n / g)
        var out: [[UInt16]] = []
        out.reserveCapacity(range.count)
        for l in 0..<range.count {
            let o = l * n * n * 4
            var rows = [UInt16](repeating: 0, count: g)
            for cy in 0..<g { for cx in 0..<g {
                var solid = 0
                for y in 0..<k { for x in 0..<k {
                    let px = min(n - 1, cx * k + x), py = min(n - 1, cy * k + y)
                    if rgba[o + (py * n + px) * 4 + 3] >= 128 { solid += 1 }
                } }
                if solid * 2 > k * k { rows[cy] |= UInt16(1) << UInt16(cx) }
            } }
            out.append(rows)
        }
        lock.lock()
        if masks.count < range.upperBound { masks += [[UInt16]](repeating: [], count: range.upperBound - masks.count) }
        for (i, m) in out.enumerated() { masks[range.lowerBound + i] = m }
        lock.unlock()
    }

    static func mask(_ layer: Int) -> [UInt16]? {
        lock.lock(); defer { lock.unlock() }
        return layer >= 0 && layer < masks.count && !masks[layer].isEmpty ? masks[layer] : nil
    }
}

extension EntityWriter {
    // An extruded item: the sprite (centre c, half size h along right r / up u) on both faces `thick` apart along n,
    // and a wall on every edge between an opaque texel and a clear one. Without a mask (textures not recorded): the
    // two faces only. Returns the quads written.
    @discardableResult
    mutating func extrudedItem(center c: V3, half h: Float, right r: V3, up u: V3, normal n: V3, thick: Float,
                               layer: Int, light: Float, sideShade: Float = 0.72) -> Int {
        let n0 = self.n
        let hn = n * (thick / 2)
        sprite(center: c + hn, half: h, right: r, up: u, layer: layer, light: light)
        sprite(center: c - hn, half: h, right: r, up: u, layer: layer, light: light * 0.9)
        guard let m = ItemMasks.mask(layer) else { return (self.n - n0) / 6 }
        let g = ItemMasks.grid, cell = 2 * h / Float(g)
        func solid(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < g && y < g && (m[y] >> UInt16(x)) & 1 == 1 }
        // Texel (x, y): x from the left, y from the top; its corner at (x, y) is c - r h + u h + r x cell - u y cell.
        func at(_ x: Int, _ y: Int) -> V3 { c + r * (Float(x) * cell - h) + u * (h - Float(y) * cell) }
        let col = V4(V3(repeating: light * sideShade), 1)
        for y in 0..<g { for x in 0..<g where solid(x, y) {
            let uv = V2((Float(x) + 0.5) / Float(g), (Float(y) + 0.5) / Float(g))
            func wall(_ a: V3, _ b: V3) { quad4(a - hn, b - hn, b + hn, a + hn, uv, uv, uv, uv, layer, col) }
            if !solid(x - 1, y) { wall(at(x, y), at(x, y + 1)) }
            if !solid(x + 1, y) { wall(at(x + 1, y + 1), at(x + 1, y)) }
            if !solid(x, y - 1) { wall(at(x + 1, y), at(x, y)) }
            if !solid(x, y + 1) { wall(at(x, y + 1), at(x + 1, y + 1)) }
        } }
        return (self.n - n0) / 6
    }
}
