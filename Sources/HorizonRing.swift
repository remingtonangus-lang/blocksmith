import Foundation
import simd

// The horizon ring: past the loaded terrain the world goes on as a coarse, hazy height field (one sample every 40
// blocks out to 1280), so the landscape doesn't stop at a fog wall and far landmarks (volcano impostors, spires) stand on
// ground instead of floating over empty sky (the pale-disc limit seen on run 563's volcano_horizon). Heights and colours
// come from the same column function and biome colours as the world map, sampled on a background queue whenever the
// player moves 256 blocks. Drawn with the landmark impostors on their shell just inside the far plane, so any loaded
// terrain is always in front of it and it only shows where nothing real has been generated yet.
final class HorizonRing {
    static let shared = HorizonRing()
    static let spacing = 40
    static let cells = 32                        // per side of the centre: 32 x 40 = 1280 blocks
    static var range: Float { Float(spacing * cells) }

    struct Snapshot {
        var x0 = 0, z0 = 0                       // world position of sample (0, 0)
        var n = 0                                // samples per side
        var h: [Float] = []
        var c: [V3] = []
    }

    private let lock = NSLock()
    private var snap: Snapshot?
    private var building = false
    private var wantKey = (Int.min, Int.min)
    private var seed: UInt64 = 0

    func current() -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        return snap
    }

    // Starts a rebuild when the player has moved into another 256-block cell (or the world changed).
    func request(_ g: Game, eye: V3) {
        guard let gen = g.world.gen as? WorldGen else { return }
        let kx = Int(floor(eye.x / 256)), kz = Int(floor(eye.z / 256))
        lock.lock()
        let same = wantKey == (kx, kz) && seed == g.world.seed
        if same || building { lock.unlock(); return }
        building = true
        wantKey = (kx, kz)
        seed = g.world.seed
        lock.unlock()
        let s = HorizonRing.spacing, n = HorizonRing.cells * 2 + 1
        let x0 = kx * 256 + 128 - HorizonRing.cells * s, z0 = kz * 256 + 128 - HorizonRing.cells * s
        // The first ring is built here and now (once, at load: a snapshot or the first frame has it); later ones in the
        // background while the old ring stays up.
        if current() == nil {
            let out = HorizonRing.sample(gen, x0: x0, z0: z0, n: n, s: s)
            lock.lock(); snap = out; building = false; lock.unlock()
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let out = HorizonRing.sample(gen, x0: x0, z0: z0, n: n, s: s)
            guard let self else { return }
            self.lock.lock()
            self.snap = out
            self.building = false
            self.lock.unlock()
        }
    }

    static func sample(_ gen: WorldGen, x0: Int, z0: Int, n: Int, s: Int) -> Snapshot {
        var out = Snapshot(x0: x0, z0: z0, n: n, h: [], c: [])
        out.h.reserveCapacity(n * n)
        out.c.reserveCapacity(n * n)
        for j in 0..<n {
            for i in 0..<n {
                let col = gen.column(x0 + i * s, z0 + j * s)
                let wet = col.biome.isOcean || col.biome.isRiver
                out.h.append(Float(wet ? max(col.height, SEA) : col.height))
                let rgb = MapCache.shade(col.biome, height: col.height)
                var c = V3(Float((rgb >> 16) & 255), Float((rgb >> 8) & 255), Float(rgb & 255)) / 255
                // Volcano flanks in their dark rock (the map's peak white turned the far cone into a snowy mountain).
                let vol = gen.columnData(x0 + i * s, z0 + j * s).vol
                if vol > 0.05 { c = simd_mix(c, V3(0.22, 0.21, 0.21), V3(repeating: min(1, vol * 3))) }
                out.c.append(c)
            }
        }
        return out
    }
}

extension Renderer {
    // Appends the ring's triangles (projected by `project`, the impostor shell), hazed toward the fog: distant ground
    // reads as silhouettes in the haze, a little clearer for high ground lit by the sun.
    func buildHorizon(_ out: inout [SimpleVert], game: Game, eye: V3, loaded: Float, fog: V3, sun: V3, day: Float,
                      hdrK: Float, project p: (V3) -> V4) {
        let ring = HorizonRing.shared
        ring.request(game, eye: eye)
        guard let s = ring.current(), s.n > 1 else { return }
        let sp = Float(HorizonRing.spacing)
        let range = HorizonRing.range
        let inner = loaded * 0.8                 // under the loaded terrain it is hidden anyway; this fills streaming gaps
        let night: Float = 0.3 + 0.7 * day
        for j in 0..<(s.n - 1) {
            for i in 0..<(s.n - 1) {
                let cxw = Float(s.x0) + (Float(i) + 0.5) * sp, czw = Float(s.z0) + (Float(j) + 0.5) * sp
                let dx = cxw - eye.x, dz = czw - eye.z
                let dist = sqrtf(dx * dx + dz * dz)
                if dist < inner || dist > range { continue }
                let k = i + j * s.n
                let a = V3(Float(s.x0) + Float(i) * sp, s.h[k], Float(s.z0) + Float(j) * sp)
                let b = V3(a.x + sp, s.h[k + 1], a.z)
                let c = V3(a.x, s.h[k + s.n], a.z + sp)
                let d = V3(a.x + sp, s.h[k + s.n + 1], a.z + sp)
                var nrm = simd_normalize(simd_cross(c - a, b - a) + V3(0, 1e-4, 0))
                if nrm.y < 0 { nrm = -nrm }
                let base: V3 = (s.c[k] + s.c[k + 1] + s.c[k + s.n] + s.c[k + s.n + 1]) * 0.25
                let lit: Float = (0.45 + 0.55 * max(0, simd_dot(nrm, sun))) * night * hdrK
                // Never clearer than the fully fogged edge of the loaded terrain in front of it: faint silhouettes of
                // hills and coasts (at 0.62 the far land read as a clear band beyond a fog curtain, horizon_ring_evening).
                let haze: Float = 0.8 + 0.17 * Terrain.smooth(loaded, range, dist)
                let col = V4(base * lit * (1 - haze) + fog * haze, 1)
                let pa = p(a), pb = p(b), pc = p(c), pd = p(d)
                out.append(SimpleVert(pos: pa, color: col)); out.append(SimpleVert(pos: pb, color: col)); out.append(SimpleVert(pos: pc, color: col))
                out.append(SimpleVert(pos: pb, color: col)); out.append(SimpleVert(pos: pd, color: col)); out.append(SimpleVert(pos: pc, color: col))
            }
        }
    }
}
