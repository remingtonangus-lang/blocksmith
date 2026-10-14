import Foundation
import simd

// F4 (Oct 13 evening playtest, Remington's idea: "full chunks out to 20, then cheap rings out to 40 or more"): the
// middle ring. Past the loaded chunks the ground goes on as a low-poly height field at its true world position, out
// to `outer` blocks: one vertex every 8 blocks next to the loaded edge, 16 farther, 32 at the rim, coloured per vertex
// from the same column function and map colours as the horizon shell (HorizonRing), lakes and seas as flat quads at
// their water level, volcano crater lakes as lava. No entities, no blocks, no textures: one draw call.
//
// The Quest draws it (WorldRenderer.drawFarRing, quest/shaders/far.vert) right after the opaque terrain with depth
// testing, so the loaded chunks hide it wherever they stand; the vertex shader sinks every vertex inside the loaded
// disc out of sight (a dozen blocks, ramped over the last 24 blocks of the disc) and keeps the edge band 2 blocks under
// its true height, so the seam has no crack and never pokes through real ground. The fog runs out to the ring's rim
// while it shows (WorldRenderer.uniforms), so the chunks and the ring share one fog and the rim melts into the horizon
// shell, which is drawn behind it on the far plane.
//
// Built on a background queue whenever the player crosses a 128-block cell (or the render distance changes) and
// swapped in whole; column samples are kept between builds (a move re-samples only the new strip). Vertices are
// relative to the build centre (`cx`, `cz`), four per quad (the shared quad index buffer draws them).
final class FarRing {
    static let shared = FarRing()
    // BS_FARRING=0 turns the ring off (before/after measurements).
    static var enabled = ProcessInfo.processInfo.environment["BS_FARRING"] != "0"
    static let outer: Float = 1024                 // blocks: the rim (64 chunks)
    static let cell = 128                          // rebuild cell
    static let spacings = [8, 16, 32]

    struct Mesh {
        var seed: UInt64 = 0
        var cx = 0, cz = 0                         // world position of the vertices' origin
        var rd = 0                                 // render distance it was cut for
        var gen = 0                                // build counter (the renderer uploads each one once)
        var verts: [SimpleVert] = []
        var quads: Int { verts.count / 4 }
    }

    struct Sample { var y: Float; var c: V3; var kind: Float }      // kind: 0 ground, 1 water, 2 lava

    private let lock = NSLock()
    private var mesh: Mesh?
    private var building = false
    private var want = (Int.min, Int.min, -1)
    private var seed: UInt64 = 0
    private var builds = 0
    private var memo: [Int64: Sample] = [:]        // touched only by the one build running (`building`)
    private var memoSeed: UInt64 = 0
    private(set) var lastBuildMs = 0.0

    func current() -> Mesh? {
        lock.lock(); defer { lock.unlock() }
        return mesh
    }

    // The radius around the player chunk's centre that is surely inside the loaded (meshed) disc, in blocks: chunk
    // (dx, dz) is meshed when dx^2 + dz^2 <= r^2 + r (World.inMeshRadius), and a point lies within 11.3 blocks of its
    // chunk's centre.
    static func loadedRadius(_ rd: Int) -> Float {
        let r2: Float = Float(rd * rd + rd)
        return 16 * r2.squareRoot() - 12
    }

    // Starts a build when the player has moved into another cell, the render distance changed or the world changed.
    func request(_ g: Game, eye: V3) {
        guard FarRing.enabled, let gen = g.world.gen as? WorldGen else { return }
        let kx = Int(floor(eye.x / Float(FarRing.cell))), kz = Int(floor(eye.z / Float(FarRing.cell)))
        let rd = g.world.renderDistance
        lock.lock()
        let same = want == (kx, kz, rd) && seed == g.world.seed
        if same || building { lock.unlock(); return }
        building = true
        want = (kx, kz, rd)
        seed = g.world.seed
        let fresh = mesh?.seed != seed
        let sd = seed
        builds += 1
        let n = builds
        lock.unlock()
        let cx = kx * FarRing.cell + FarRing.cell / 2, cz = kz * FarRing.cell + FarRing.cell / 2
        let work = { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            if self.memoSeed != sd || self.memo.count > 150_000 { self.memo.removeAll(keepingCapacity: true); self.memoSeed = sd }
            var out = Mesh(seed: sd, cx: cx, cz: cz, rd: rd, gen: n)
            out.verts = FarRing.build(gen, cx: cx, cz: cz, rin: FarRing.loadedRadius(rd), memo: &self.memo)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            self.lock.lock()
            // A build for a world left meanwhile is dropped (the next request starts the new world's).
            if sd == self.seed { self.mesh = out } else { self.want = (Int.min, Int.min, -1) }
            self.lastBuildMs = ms
            self.building = false
            self.lock.unlock()
        }
        // The first ring of a world is built here and now (at load, like HorizonRing); later ones in the background
        // while the old ring stays up.
        if fresh { work() } else { DispatchQueue.global(qos: .utility).async(execute: work) }
    }

    // One column: its top (ground, water surface or crater lava) and colour.
    static func sample(_ gen: WorldGen, _ x: Int, _ z: Int) -> Sample {
        let k = gen.columnData(x, z)
        let b = gen.terrain.biome(k, k.h)
        let top = YOFF + Int(floorf(k.h))
        let wl = YOFF + Int(floorf(k.wl))
        func rgb(_ v: UInt32) -> V3 { V3(Float((v >> 16) & 255), Float((v >> 8) & 255), Float(v & 255)) / 255 }
        if k.vol > 0.2 && k.lava > k.h {
            return Sample(y: Float(YOFF) + floorf(k.lava) + 1, c: V3(0.95, 0.42, 0.1), kind: 2)
        }
        if wl > top {
            return Sample(y: Float(wl) + 0.875, c: rgb(b.info.water), kind: 1)
        }
        // Map colours are the raw biome tints; the blocks' own textures darken them (grass, sand and stone art average
        // about 0.8), so the ring matches the textured ground at the seam.
        var c = rgb(MapCache.shade(b, height: top)) * 0.8
        let vw: Float = k.vol > 0.05 ? min(1, k.vol * 3) : 0
        let rw: Float = max(0, vw * 2 - 1)
        if rw > 0 { c = simd_mix(c, V3(0.2, 0.19, 0.19), V3(repeating: rw)) }      // volcano rock (HorizonRing)
        return Sample(y: Float(YOFF) + k.h + 1, c: c, kind: 0)
    }

    // The quads, band by band (squares round the centre, 8 / 16 / 32 blocks apart), cut to a disc of `outer` and with
    // the cells deep inside the loaded disc (whatever the player's offset from the centre within the cell) left out.
    static func build(_ gen: WorldGen, cx: Int, cz: Int, rin: Float, memo: inout [Int64: Sample]) -> [SimpleVert] {
        func a32(_ v: Float) -> Int { (Int(v.rounded(.up)) + 31) / 32 * 32 }
        let e0 = a32(rin + 64)
        let e1 = max(e0 + 128, a32(rin + 320), 640)
        let e2 = a32(FarRing.outer)
        let edges = [e0, e1, max(e2, e1 + 64)]
        // The player is within 64 blocks (each axis) of the centre: cells within rin - 91 are always under chunks.
        let skip: Float = rin - 100
        let rim: Float = FarRing.outer
        func S(_ x: Int, _ z: Int) -> Sample {
            let key = (Int64(x) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: z)))
            if let s = memo[key] { return s }
            let s = sample(gen, x, z)
            memo[key] = s
            return s
        }
        var out: [SimpleVert] = []
        out.reserveCapacity(64_000)
        for (band, s) in spacings.enumerated() {
            let e = edges[band], ein = band == 0 ? 0 : edges[band - 1]
            let n = e / s
            let coarse = 2 * s
            // Height at a band vertex: on the band's outer square edge, a vertex between two of the next band's
            // vertices takes the mean of its neighbours along the edge, so it lies on the coarser band's edge (no cracks).
            func height(_ ox: Int, _ oz: Int) -> Sample {
                var smp = S(cx + ox, cz + oz)
                guard band < spacings.count - 1 else { return smp }
                if abs(ox) == e && oz % coarse != 0 {
                    let a = S(cx + ox, cz + oz - s), b = S(cx + ox, cz + oz + s)
                    smp.y = (a.y + b.y) * 0.5
                } else if abs(oz) == e && ox % coarse != 0 {
                    let a = S(cx + ox - s, cz + oz), b = S(cx + ox + s, cz + oz)
                    smp.y = (a.y + b.y) * 0.5
                }
                return smp
            }
            func vert(_ ox: Int, _ oz: Int) -> SimpleVert {
                let smp = height(ox, oz)
                var nx: Float = 0, nz: Float = 0
                if smp.kind == 0 {
                    let hx0 = S(cx + ox - s, cz + oz), hx1 = S(cx + ox + s, cz + oz)
                    let hz0 = S(cx + ox, cz + oz - s), hz1 = S(cx + ox, cz + oz + s)
                    let gx: Float = hx0.y - hx1.y, gz: Float = hz0.y - hz1.y
                    let nv = simd_normalize(V3(gx, Float(2 * s), gz))
                    nx = nv.x; nz = nv.z
                }
                let qx: Float = ((nx * 0.5 + 0.5) * 1023).rounded()
                let qz: Float = ((nz * 0.5 + 0.5) * 1023).rounded()
                return SimpleVert(pos: V4(Float(ox), smp.y, Float(oz), qx + qz * 1024), color: V4(smp.c, smp.kind))
            }
            for j in -n..<n {
                for i in -n..<n {
                    let x0 = i * s, z0 = j * s, x1 = x0 + s, z1 = z0 + s
                    // Inside the finer band's square: drawn there.
                    if band > 0 && x0 >= -ein && x1 <= ein && z0 >= -ein && z1 <= ein { continue }
                    let mx: Float = Float(x0) + Float(s) * 0.5, mz: Float = Float(z0) + Float(s) * 0.5
                    let r: Float = (mx * mx + mz * mz).squareRoot()
                    if r > rim - Float(s) * 0.5 { continue }
                    if band == 0 {
                        let fx: Float = max(abs(Float(x0)), abs(Float(x1))), fz: Float = max(abs(Float(z0)), abs(Float(z1)))
                        if (fx * fx + fz * fz).squareRoot() < skip { continue }
                    }
                    out.append(vert(x0, z0)); out.append(vert(x1, z0)); out.append(vert(x1, z1)); out.append(vert(x0, z1))
                }
            }
        }
        return out
    }
}
