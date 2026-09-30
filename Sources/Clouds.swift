import Foundation
import Metal
import simd

// Fancy clouds: the cloud layer as 12x12x4 boxes with shaded sides (the Fast renderer draws the same
// coverage as a flat sheet in cloudFS). The mesh lives in "cloud space" (cells drift with the wind),
// is rebuilt only when the camera or the wind crosses a cell, and is drawn camera-relative with one
// offset. Faces between two cloud cells are skipped, so only blob surfaces are drawn.
final class CloudMesh {
    static let cell: Float = 12
    static let height: Float = 4
    static let maxVerts = 90_000
    private let buffers: [MTLBuffer]
    private var which = 0
    private var key: (Int, Int, Int) = (Int.min, Int.min, 0)
    private(set) var count = 0
    var buffer: MTLBuffer { buffers[which] }

    init?(device: MTLDevice) {
        var b: [MTLBuffer] = []
        for _ in 0..<2 {
            guard let m = device.makeBuffer(length: CloudMesh.maxVerts * MemoryLayout<SimpleVert>.stride, options: .storageModeShared) else { return nil }
            b.append(m)
        }
        buffers = b
    }

    // Same coverage function as cloudFS in Shaders.swift.
    private static func hash21(_ p: V2) -> Float {
        var p3 = simd_fract(V3(p.x, p.y, p.x) * 0.1031)
        p3 += simd_dot(p3, V3(p3.y, p3.z, p3.x) + 33.33)
        return simd_fract((p3.x + p3.y) * p3.z)
    }
    private static func vnoise(_ p: V2) -> Float {
        let i = simd_floor(p)
        var f = simd_fract(p)
        f = f * f * (3 - 2 * f)
        let a = hash21(i), b = hash21(i + V2(1, 0)), c = hash21(i + V2(0, 1)), d = hash21(i + V2(1, 1))
        return simd_mix(simd_mix(a, b, f.x), simd_mix(c, d, f.x), f.y)
    }
    static func cloudy(_ cx: Int, _ cz: Int) -> Bool {
        let cell = V2(Float(cx), Float(cz))
        let n = vnoise(cell * 0.23) * 0.62 + vnoise(cell * 0.06 + 17) * 0.38 + (hash21(cell) - 0.5) * 0.08
        return n >= 0.6
    }

    // Rebuilds when the centre cell or radius changes. Returns the vertex count to draw.
    func update(centerX cx: Int, centerZ cz: Int, radius r: Int) -> Int {
        if key == (cx, cz, r) { return count }
        key = (cx, cz, r)
        which = 1 - which
        let out = buffers[which].contents().bindMemory(to: SimpleVert.self, capacity: CloudMesh.maxVerts)
        var n = 0
        let S = CloudMesh.cell, H = CloudMesh.height
        // Face shades: top bright, bottom dark, sides in between (lit from above).
        func face(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ shade: Float) {
            guard n + 6 <= CloudMesh.maxVerts else { return }
            let col = V4(shade, shade, shade, 1)
            for p in [a, b, c, a, c, d] { out[n] = SimpleVert(pos: V4(p, 1), color: col); n += 1 }
        }
        for dz in -r...r {
            for dx in -r...r where dx * dx + dz * dz <= r * r {
                let x = cx + dx, z = cz + dz
                if !CloudMesh.cloudy(x, z) { continue }
                let x0 = Float(x) * S, z0 = Float(z) * S, x1 = x0 + S, z1 = z0 + S
                face(V3(x0, H, z1), V3(x1, H, z1), V3(x1, H, z0), V3(x0, H, z0), 1.0)      // top
                face(V3(x0, 0, z0), V3(x1, 0, z0), V3(x1, 0, z1), V3(x0, 0, z1), 0.72)     // bottom
                if !CloudMesh.cloudy(x + 1, z) { face(V3(x1, 0, z1), V3(x1, 0, z0), V3(x1, H, z0), V3(x1, H, z1), 0.86) }
                if !CloudMesh.cloudy(x - 1, z) { face(V3(x0, 0, z0), V3(x0, 0, z1), V3(x0, H, z1), V3(x0, H, z0), 0.86) }
                if !CloudMesh.cloudy(x, z + 1) { face(V3(x0, 0, z1), V3(x1, 0, z1), V3(x1, H, z1), V3(x0, H, z1), 0.8) }
                if !CloudMesh.cloudy(x, z - 1) { face(V3(x1, 0, z0), V3(x0, 0, z0), V3(x0, H, z0), V3(x1, H, z0), 0.8) }
            }
        }
        count = n
        return n
    }
}
