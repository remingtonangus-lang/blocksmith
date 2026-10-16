import Foundation
import simd

// BC3 (DXT5) encoder for the block texture array: 1 byte per texel instead of 4, so 128 px faces with mips take
// about the memory 64 px RGBA did (1665 layers: ~36 MB). Colour: endpoints from the principal axis of the block's
// opaque texels (power iteration), inset slightly, quantised to 565, each texel the nearest of the four palette
// colours. Alpha: BC4 8-value mode between the block's min and max (cutouts and the 0.9 grass overlay stay exact).
// Glyph, HUD and item layers are nearest-upscaled 16 px art: every 4x4 block sits inside one source texel, so they
// come out exact apart from 565 rounding. Apple GPUs on macOS sample BC formats natively.
enum TexCompress {
    static var enabled: Bool {
        if ProcessInfo.processInfo.environment["BLOCKSMITH_TEXCOMPRESS"] == "0" { return false }
        return UserDefaults.standard.object(forKey: "textureCompression") as? Bool ?? true
    }

    @inline(__always) static func to565(_ c: V3) -> UInt16 {
        let r = UInt16(max(0, min(31, Int((c.x * 31 / 255).rounded()))))
        let g = UInt16(max(0, min(63, Int((c.y * 63 / 255).rounded()))))
        let b = UInt16(max(0, min(31, Int((c.z * 31 / 255).rounded()))))
        return (r << 11) | (g << 5) | b
    }
    @inline(__always) static func from565(_ v: UInt16) -> V3 {
        let r = Float((v >> 11) & 31), g = Float((v >> 5) & 63), b = Float(v & 31)
        return V3(r * 255 / 31, g * 255 / 63, b * 255 / 31)
    }

    // One RGBA8 image (size x size) -> BC3 blocks (16 bytes per 4x4 block; sizes under 4 pad by clamping).
    static func encode(_ src: UnsafeRawPointer, size: Int, into out: UnsafeMutablePointer<UInt8>) {
        let px = src.assumingMemoryBound(to: UInt8.self)
        let bw = max(1, (size + 3) / 4)
        var cols = [V3](repeating: .zero, count: 16)
        var alpha = [Float](repeating: 0, count: 16)
        for by in 0..<bw { for bx in 0..<bw {
            for j in 0..<4 { for i in 0..<4 {
                let x = min(size - 1, bx * 4 + i), y = min(size - 1, by * 4 + j)
                let p = (y * size + x) * 4
                cols[j * 4 + i] = V3(Float(px[p]), Float(px[p + 1]), Float(px[p + 2]))
                alpha[j * 4 + i] = Float(px[p + 3])
            } }
            let o = out + (by * bw + bx) * 16
            encodeAlpha(alpha, o)
            encodeColour(cols, alpha, o + 8)
        } }
    }

    static func encodeAlpha(_ a: [Float], _ o: UnsafeMutablePointer<UInt8>) {
        var lo: Float = 255, hi: Float = 0
        for v in a { lo = min(lo, v); hi = max(hi, v) }
        let a0 = UInt8(hi), a1 = UInt8(lo)
        o[0] = a0; o[1] = a1
        var bits: UInt64 = 0
        if a0 > a1 {
            // Palette index order for a0 > a1: 0 = a0, 1 = a1, 2...7 = a0 -> a1 in sixths.
            let span = Float(a0) - Float(a1)
            for k in 0..<16 {
                let t: Float = (Float(a0) - a[k]) / span * 7          // 0 at a0, 7 at a1
                let step = Int(t.rounded())
                let idx: UInt64 = step == 0 ? 0 : (step == 7 ? 1 : UInt64(step + 1))
                bits |= idx << UInt64(3 * k)
            }
        }
        for b in 0..<6 { o[2 + b] = UInt8((bits >> UInt64(8 * b)) & 0xFF) }
    }

    static func encodeColour(_ c: [V3], _ a: [Float], _ o: UnsafeMutablePointer<UInt8>) {
        // Fit to the visible texels (transparent ones carry no colour).
        var mean = V3.zero
        var n: Float = 0
        for k in 0..<16 where a[k] >= 8 { mean += c[k]; n += 1 }
        if n == 0 { for k in 0..<8 { o[k] = 0 }; return }
        mean /= n
        var cxx: Float = 0, cxy: Float = 0, cxz: Float = 0, cyy: Float = 0, cyz: Float = 0, czz: Float = 0
        for k in 0..<16 where a[k] >= 8 {
            let d: V3 = c[k] - mean
            cxx += d.x * d.x; cxy += d.x * d.y; cxz += d.x * d.z
            cyy += d.y * d.y; cyz += d.y * d.z; czz += d.z * d.z
        }
        var axis = V3(1, 1, 1)
        for _ in 0..<4 {
            let nx: Float = cxx * axis.x + cxy * axis.y + cxz * axis.z
            let ny: Float = cxy * axis.x + cyy * axis.y + cyz * axis.z
            let nz: Float = cxz * axis.x + cyz * axis.y + czz * axis.z
            let v = V3(nx, ny, nz)
            let len = simd_length(v)
            if len < 1e-6 { break }
            axis = v / len
        }
        var tmin: Float = 1e9, tmax: Float = -1e9
        for k in 0..<16 where a[k] >= 8 {
            let t = simd_dot(c[k] - mean, axis)
            tmin = min(tmin, t); tmax = max(tmax, t)
        }
        let inset: Float = (tmax - tmin) / 32
        let e0: V3 = mean + axis * (tmax - inset)
        let e1: V3 = mean + axis * (tmin + inset)
        var c0 = to565(simd_clamp(e0, V3(repeating: 0), V3(repeating: 255)))
        var c1 = to565(simd_clamp(e1, V3(repeating: 0), V3(repeating: 255)))
        if c0 < c1 { swap(&c0, &c1) }
        var bits: UInt32 = 0
        if c0 != c1 {
            let p0 = from565(c0), p1 = from565(c1)
            let p2: V3 = (p0 * 2 + p1) / 3
            let p3: V3 = (p0 + p1 * 2) / 3
            for k in 0..<16 {
                let d0 = simd_length_squared(c[k] - p0), d1 = simd_length_squared(c[k] - p1)
                let d2 = simd_length_squared(c[k] - p2), d3 = simd_length_squared(c[k] - p3)
                var best: UInt32 = 0
                var bd: Float = d0
                if d1 < bd { bd = d1; best = 1 }
                if d2 < bd { bd = d2; best = 2 }
                if d3 < bd { best = 3 }
                bits |= best << UInt32(2 * k)
            }
        }
        o[0] = UInt8(c0 & 0xFF); o[1] = UInt8(c0 >> 8)
        o[2] = UInt8(c1 & 0xFF); o[3] = UInt8(c1 >> 8)
        for b in 0..<4 { o[4 + b] = UInt8((bits >> UInt32(8 * b)) & 0xFF) }
    }
}
