import AppKit
import simd

// Imported block textures (tools/teximport.py turns a large generated or CC0 image into a tileable 128 px PNG).
// A file Resources/Textures/<name>.png (bundled into the app by build.sh) replaces that layer's procedural
// material; `--texdir DIR` / BLOCKSMITH_TEXDIR puts a trial set first, and `--procedural` turns imports off, so the
// harness can render the same view both ways. Mips and the texture array are built from it like any other layer.
enum TextureImport {
    static let dirs: [String] = {
        if CommandLine.arguments.contains("--procedural") { return [] }
        var d: [String] = []
        if let t = arg("--texdir") ?? ProcessInfo.processInfo.environment["BLOCKSMITH_TEXDIR"] { d.append(t) }
        if let r = Bundle.main.resourcePath { d.append(r + "/Textures") }
        d.append("Resources/Textures")
        return d
    }()

    // The layer `name` at n x n (RGBA 0...1, straight alpha), box-filtered from the file, or nil if none.
    static func image(_ name: String, size n: Int) -> [V4]? {
        for d in dirs {
            let path = d + "/" + name + ".png"
            guard FileManager.default.fileExists(atPath: path), let data = FileManager.default.contents(atPath: path),
                  let cg = NSBitmapImageRep(data: data)?.cgImage else { continue }
            let w = cg.width, h = cg.height
            guard w > 0 && h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { continue }
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let ok: Bool = buf.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            if !ok { continue }
            var out = [V4](repeating: V4(0, 0, 0, 0), count: n * n)
            for y in 0..<n { for x in 0..<n {
                let x0 = x * w / n, x1 = max(x0 + 1, (x + 1) * w / n)
                let y0 = y * h / n, y1 = max(y0 + 1, (y + 1) * h / n)
                var acc = V4(0, 0, 0, 0)
                for sy in y0..<y1 { for sx in x0..<x1 {
                    let i = (sy * w + sx) * 4
                    acc += V4(Float(buf[i]), Float(buf[i + 1]), Float(buf[i + 2]), Float(buf[i + 3]))
                } }
                let c: V4 = acc / Float((x1 - x0) * (y1 - y0) * 255)
                // Premultiplied -> straight alpha.
                out[y * n + x] = c.w > 0.001 ? V4(c.x / c.w, c.y / c.w, c.z / c.w, c.w) : V4(0, 0, 0, 0)
            } }
            return out
        }
        return nil
    }
}
