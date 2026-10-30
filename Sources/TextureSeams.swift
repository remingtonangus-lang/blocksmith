import Foundation
import simd

// P493 (own idea, night lane Oct 30, a snowy peaks render): several imported textures were made tileable by shifting
// them half a tile, which left the old edges as a "+" seam through the middle of every block: snowfields looked
// quilted, ice and blue ice showed a line cross per block, concrete had crack marks at every block's middle. The seam
// rows (and columns) are blended over from a calm band of the same picture elsewhere in the tile: two blocks wide
// fully, fading out over eight more each side (at 128 px). Only the listed natural and flat materials are mended;
// planks, bricks, plating and other patterned art keep their real joins.
enum TextureSeams {
    static let colours = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan",
                          "purple", "blue", "brown", "green", "red", "black"]
    static let mended: Set<String> = {
        var s: Set<String> = ["snow", "snow_block", "ice", "blue_ice", "packed_ice", "terracotta", "calcite", "smooth_basalt",
                              "polished_blackstone", "lapis_block", "emberslate", "red_sandstone_top", "clay", "soul_sand",
                              "netherrack"]
        for c in colours { s.insert("\(c)_concrete"); s.insert("\(c)_terracotta") }
        return s
    }()

    static func mend(_ name: String, _ px: [V4], n: Int) -> [V4] {
        guard mended.contains(name), n >= 32, px.count == n * n else { return px }
        var a = px
        let h = n / 2, b = max(1, n / 64), f = max(2, n / 16)
        let rows = Array((h - b - f - 1)..<(h + b + f + 1))
        for axis in 0..<2 {
            // (axis 0: rows across the horizontal seam; axis 1: the same on columns)
            @inline(__always) func at(_ line: Int, _ k: Int) -> Int { axis == 0 ? line * n + k : k * n + line }
            // The calmest band to borrow from: least spread round each column's mean, away from the seam itself.
            var best = Float.greatestFiniteMagnitude, off = n / 4
            var o = n / 8
            while o <= n - n / 8 {
                let src = rows.map { ($0 + o) % n }
                if !src.contains(where: { abs($0 - h) < b + f + 2 }) {
                    var v: Float = 0
                    for k in 0..<n {
                        var m = V4(repeating: 0)
                        for r in src { m += a[at(r, k)] }
                        m /= Float(src.count)
                        for r in src { let d = a[at(r, k)] - m; v += d.x * d.x + d.y * d.y + d.z * d.z }
                    }
                    if v < best { best = v; off = o }
                }
                o += max(1, n / 32)
            }
            let before = a
            for line in rows {
                let d = abs(Float(line) + 0.5 - Float(h))
                let w: Float = d <= Float(b) ? 1 : max(0, 1 - (d - Float(b)) / Float(f))
                guard w > 0 else { continue }
                let s = (line + off) % n
                for k in 0..<n { a[at(line, k)] = before[at(line, k)] * (1 - w) + before[at(s, k)] * w }
            }
        }
        return a
    }
}
