import Foundation

// Visual oracles on every rendered snapshot (Renderer.renderToPNG): per frame, the share of magenta-checker
// pixels (a texture without a painter), near-black and blown-out pixels, the luma spread (a blank / one-colour
// frame), and a coarse hash (two different views rendering the same image means a camera or streaming failure).
// With --flicker the frame is rendered again with the camera nudged by 1/1000 block: pixels that change a lot
// between two practically identical views are z-fighting (coplanar faces). One line per frame goes to
// snaps/imagecheck.log; tools/imagecheck.py aggregates and flags them on CI.
enum ImageCheck {
    static var enabled = true
    static var flicker = CommandLine.arguments.contains("--flicker")

    struct Stats { var magenta: Double; var black: Double; var white: Double; var lumaStd: Double; var hash: UInt64 }

    static func stats(_ px: [UInt8], _ w: Int, _ h: Int) -> Stats {
        var mag = 0, blk = 0, wht = 0
        var sum = 0.0, sum2 = 0.0
        var hash: UInt64 = 1469598103934665603
        let n = w * h
        var i = 0
        while i < n {
            let b = Int(px[i * 4]), g = Int(px[i * 4 + 1]), r = Int(px[i * 4 + 2])
            if r > 180 && b > 180 && g < 70 { mag += 1 }
            let y = (r * 54 + g * 183 + b * 19) >> 8
            if y < 6 { blk += 1 }
            if y > 250 { wht += 1 }
            let yd = Double(y)
            sum += yd; sum2 += yd * yd
            i += 1
        }
        // Coarse hash over a 32x20 grid of 4-bit luma.
        for gy in 0..<20 { for gx in 0..<32 {
            let x = gx * w / 32 + w / 64, yy = gy * h / 20 + h / 40
            let o = (yy * w + x) * 4
            let y = (Int(px[o + 2]) * 54 + Int(px[o + 1]) * 183 + Int(px[o]) * 19) >> 12
            hash = (hash ^ UInt64(y)) &* 1099511628211
        } }
        let mean = sum / Double(n)
        let sd = max(0, sum2 / Double(n) - mean * mean).squareRoot()
        return Stats(magenta: Double(mag) / Double(n), black: Double(blk) / Double(n), white: Double(wht) / Double(n), lumaStd: sd, hash: hash)
    }

    // Share of pixels whose colour moves by more than 48/255 between two renders.
    static func flickerShare(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var changed = 0
        let n = min(a.count, b.count) / 4
        var i = 0
        while i < n {
            let d = abs(Int(a[i * 4]) - Int(b[i * 4])) + abs(Int(a[i * 4 + 1]) - Int(b[i * 4 + 1])) + abs(Int(a[i * 4 + 2]) - Int(b[i * 4 + 2]))
            if d > 144 { changed += 1 }
            i += 1
        }
        return Double(changed) / Double(max(1, n))
    }

    static func log(path: String, _ s: Stats, flicker: Double?) {
        guard enabled else { return }
        let name = (path as NSString).lastPathComponent
        var line = String(format: "imagecheck %@ magenta=%.5f black=%.4f white=%.4f std=%.1f hash=%016llx", name, s.magenta, s.black, s.white, s.lumaStd, s.hash)
        if let f = flicker { line += String(format: " flicker=%.5f", f) }
        print(line)
        let logPath = "snaps/imagecheck.log"
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); h.closeFile()
        } else {
            try? (line + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
