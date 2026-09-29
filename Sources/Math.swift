import Foundation
import simd

typealias V2 = SIMD2<Float>
typealias V3 = SIMD3<Float>
typealias V4 = SIMD4<Float>

struct IVec3: Hashable {
    var x: Int
    var y: Int
    var z: Int
    init(_ x: Int, _ y: Int, _ z: Int) { self.x = x; self.y = y; self.z = z }
    static func + (a: IVec3, b: IVec3) -> IVec3 { IVec3(a.x + b.x, a.y + b.y, a.z + b.z) }
}

func perspectiveRH(fovy: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspect
    let zs = far / (near - far)
    return float4x4(columns: (V4(xs, 0, 0, 0), V4(0, ys, 0, 0), V4(0, 0, zs, -1), V4(0, 0, zs * near, 0)))
}

func translationMatrix(_ t: V3) -> float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = V4(t.x, t.y, t.z, 1)
    return m
}

func rotationX(_ a: Float) -> float4x4 {
    let c = cosf(a), s = sinf(a)
    return float4x4(columns: (V4(1, 0, 0, 0), V4(0, c, s, 0), V4(0, -s, c, 0), V4(0, 0, 0, 1)))
}

func rotationY(_ a: Float) -> float4x4 {
    let c = cosf(a), s = sinf(a)
    return float4x4(columns: (V4(c, 0, -s, 0), V4(0, 1, 0, 0), V4(s, 0, c, 0), V4(0, 0, 0, 1)))
}

struct Frustum {
    var planes: [V4]
    init(_ m: float4x4) {
        let r0 = V4(m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x)
        let r1 = V4(m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y)
        let r2 = V4(m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z)
        let r3 = V4(m.columns.0.w, m.columns.1.w, m.columns.2.w, m.columns.3.w)
        planes = [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2]
    }
    func visible(min a: V3, max b: V3) -> Bool {
        for p in planes {
            let x = p.x >= 0 ? b.x : a.x
            let y = p.y >= 0 ? b.y : a.y
            let z = p.z >= 0 ? b.z : a.z
            if p.x * x + p.y * y + p.z * z + p.w < 0 { return false }
        }
        return true
    }
}

@inline(__always) func hash3(_ x: Int, _ y: Int, _ z: Int, _ seed: UInt32) -> UInt32 {
    var h = UInt32(truncatingIfNeeded: x) &* 0x8da6b343
    h ^= UInt32(truncatingIfNeeded: y) &* 0xd8163841
    h ^= UInt32(truncatingIfNeeded: z) &* 0xcb1ab31f
    h ^= seed
    h ^= h >> 13
    h = h &* 0x5bd1e995
    h ^= h >> 15
    return h
}

@inline(__always) func hashf(_ x: Int, _ y: Int, _ z: Int, _ seed: UInt32) -> Float {
    Float(hash3(x, y, z, seed) & 0xFFFFFF) / Float(0x1000000)
}

@inline(__always) func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : (a - b + 1) / b }
@inline(__always) func mod(_ a: Int, _ b: Int) -> Int { let r = a % b; return r < 0 ? r + b : r }
