import Foundation
import ImageIO
import UniformTypeIdentifiers

// Harness: `Blocksmith --atlas snaps/atlas` writes every procedural texture layer as grid pages
// (atlas_0.png, atlas_1.png...), 24 x 20 tiles of 48 px on a grey background, and prints
// "page row col name" lines so a tile can be traced back to its painter.
func dumpAtlas(_ prefix: String) -> Int32 {
    let data = TextureGen.base(size: TextureGen.S)
    let names = Tex.names
    let S = TextureGen.S, cols = 24, rows = 20, scale = 3, gap = 2
    let cell = S * scale + gap
    let perPage = cols * rows
    let W = cols * cell + gap, H = rows * cell + gap
    var page = 0
    var first = 0
    while first < names.count {
        var px = [UInt8](repeating: 0, count: W * H * 4)
        for i in 0..<(W * H) { px[i * 4] = 40; px[i * 4 + 1] = 40; px[i * 4 + 2] = 44; px[i * 4 + 3] = 255 }
        for k in 0..<min(perPage, names.count - first) {
            let layer = first + k
            let r = k / cols, c = k % cols
            print("atlas \(page) r\(r) c\(c) \(names[layer])")
            let ox = gap + c * cell, oy = gap + r * cell
            for y in 0..<(S * scale) {
                for x in 0..<(S * scale) {
                    let sx = x / scale, sy = y / scale
                    let si = ((layer * S + sy) * S + sx) * 4
                    let a = Float(data[si + 3]) / 255
                    // Transparent texels over a light/dark checker so holes are visible.
                    let bg: Float = ((x / 6 + y / 6) % 2 == 0) ? 150 : 110
                    let di = ((oy + y) * W + ox + x) * 4
                    px[di] = UInt8(Float(data[si + 2]) * a + bg * (1 - a))       // BGRA
                    px[di + 1] = UInt8(Float(data[si + 1]) * a + bg * (1 - a))
                    px[di + 2] = UInt8(Float(data[si]) * a + bg * (1 - a))
                }
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let path = "\(prefix)_\(page).png"
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let img = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: cs, bitmapInfo: info,
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { print("atlas: PNG encode failed"); return 1 }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        page += 1
        first += perPage
    }
    print("atlas: \(names.count) layers on \(page) pages")
    return 0
}

// Harness: `Blocksmith --hdatlas snaps/hdatlas.png [--names a,b,c]` writes tiles at the GPU texture resolution
// (TextureGen.size) for review: the HD materials, then upscaled painters for comparison. 8 columns, labels in
// the log ("hdatlas row col name").
func dumpHDAtlas(_ path: String) -> Int32 {
    let n = TextureGen.size
    let data = TextureGen.base(size: n)
    let names = Tex.names
    let extra: [String] = ["spruce_log", "spruce_log_top", "birch_log_top", "jungle_planks", "acacia_planks", "dark_oak_log",
                           "birch_leaves", "spruce_leaves", "terracotta", "white_wool", "red_wool", "blue_concrete",
                           "lime_concrete_powder", "orange_terracotta", "crimson_stem", "warped_planks",
                           "glass", "water", "lava", "netherrack", "end_stone", "furnace_front",
                           "crafting_table_front", "barrel_side", "pumpkin_side", "glowstone", "crimson_nylium", "poppy"]
    let all: [String] = HDTex.table.keys.sorted() + extra
    var want: [String] = arg("--names").map { $0.split(separator: ",").map(String.init) } ?? all
    want = want.filter { names.contains($0) }
    let cols = 8, gap = 4
    let rows = (want.count + cols - 1) / cols
    let W = cols * (n + gap) + gap, H = rows * (n + gap) + gap
    var px = [UInt8](repeating: 30, count: W * H * 4)
    for i in 0..<(W * H) { px[i * 4 + 3] = 255 }
    for (k, name) in want.enumerated() {
        guard let layer = names.firstIndex(of: name) else { continue }
        let r = k / cols, c = k % cols
        print("hdatlas r\(r) c\(c) \(name)")
        let ox = gap + c * (n + gap), oy = gap + r * (n + gap)
        for y in 0..<n { for x in 0..<n {
            let si = ((layer * n + y) * n + x) * 4
            let a = Float(data[si + 3]) / 255
            let bg: Float = ((x / 8 + y / 8) % 2 == 0) ? 70 : 100
            let o = ((oy + y) * W + ox + x) * 4
            for ch in 0..<3 { px[o + ch] = UInt8(Float(data[si + ch]) * a + bg * (1 - a)) }
        } }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(px) as CFData),
          let img = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: cs,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return 1 }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("hdatlas: \(want.count) layers at \(n) px -> \(path)")
    return 0
}
