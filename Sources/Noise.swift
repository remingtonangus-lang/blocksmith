import Foundation

// Seeded Perlin gradient noise (2D + 3D) with a fractal helper.
final class Noise {
    private var perm = [Int](repeating: 0, count: 512)

    init(seed: UInt64) {
        var p = Array(0..<256)
        var s = seed ^ 0x9E3779B97F4A7C15
        for i in stride(from: 255, to: 0, by: -1) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let j = Int((s >> 33) % UInt64(i + 1))
            p.swapAt(i, j)
        }
        for i in 0..<512 { perm[i] = p[i & 255] }
    }

    @inline(__always) private func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }
    @inline(__always) private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    @inline(__always) private func grad2(_ h: Int, _ x: Float, _ y: Float) -> Float {
        switch h & 7 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        case 3: return -x - y
        case 4: return x
        case 5: return -x
        case 6: return y
        default: return -y
        }
    }

    @inline(__always) private func grad3(_ h: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let hh = h & 15
        let u = hh < 8 ? x : y
        let v = hh < 4 ? y : ((hh == 12 || hh == 14) ? x : z)
        return ((hh & 1) == 0 ? u : -u) + ((hh & 2) == 0 ? v : -v)
    }

    func noise2(_ x: Float, _ y: Float) -> Float {
        let xf = floorf(x), yf = floorf(y)
        let xi = Int(xf) & 255, yi = Int(yf) & 255
        let x0 = x - xf, y0 = y - yf
        let u = fade(x0), v = fade(y0)
        let a = perm[xi] + yi, b = perm[xi + 1] + yi
        let r0 = lerp(grad2(perm[a], x0, y0), grad2(perm[b], x0 - 1, y0), u)
        let r1 = lerp(grad2(perm[a + 1], x0, y0 - 1), grad2(perm[b + 1], x0 - 1, y0 - 1), u)
        return lerp(r0, r1, v)
    }

    func noise3(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let xf = floorf(x), yf = floorf(y), zf = floorf(z)
        let xi = Int(xf) & 255, yi = Int(yf) & 255, zi = Int(zf) & 255
        let x0 = x - xf, y0 = y - yf, z0 = z - zf
        let u = fade(x0), v = fade(y0), w = fade(z0)
        let a = perm[xi] + yi, aa = perm[a] + zi, ab = perm[a + 1] + zi
        let b = perm[xi + 1] + yi, ba = perm[b] + zi, bb = perm[b + 1] + zi
        let x1 = lerp(grad3(perm[aa], x0, y0, z0), grad3(perm[ba], x0 - 1, y0, z0), u)
        let x2 = lerp(grad3(perm[ab], x0, y0 - 1, z0), grad3(perm[bb], x0 - 1, y0 - 1, z0), u)
        let y1 = lerp(x1, x2, v)
        let x3 = lerp(grad3(perm[aa + 1], x0, y0, z0 - 1), grad3(perm[ba + 1], x0 - 1, y0, z0 - 1), u)
        let x4 = lerp(grad3(perm[ab + 1], x0, y0 - 1, z0 - 1), grad3(perm[bb + 1], x0 - 1, y0 - 1, z0 - 1), u)
        let y2 = lerp(x3, x4, v)
        return lerp(y1, y2, w)
    }

    func fbm2(_ x: Float, _ y: Float, _ octaves: Int) -> Float {
        var sum: Float = 0, amp: Float = 1, freq: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += noise2(x * freq, y * freq) * amp
            norm += amp
            amp *= 0.5
            freq *= 2
        }
        return sum / norm
    }
}
