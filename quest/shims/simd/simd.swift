import Foundation

// A pure-Swift stand-in for Apple's `simd` module on Android and Linux, so the shared game code (which says
// `import simd`) compiles unchanged for the Quest. Only the API Blocksmith uses: vector helpers over the standard
// library's SIMD types, float3x3 / float4x4 (column major, like Apple's) and simd_quatf. Everything is
// @inlinable so calls specialise and inline across the module boundary like the real header functions.

// MARK: Type names

public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>
public typealias simd_double2 = SIMD2<Double>
public typealias simd_double3 = SIMD3<Double>
public typealias simd_double4 = SIMD4<Double>
public typealias simd_int2 = SIMD2<Int32>
public typealias simd_int3 = SIMD3<Int32>
public typealias simd_int4 = SIMD4<Int32>
public typealias simd_uint2 = SIMD2<UInt32>
public typealias simd_uint3 = SIMD3<UInt32>
public typealias simd_uint4 = SIMD4<UInt32>
public typealias float4x4 = simd_float4x4
public typealias float3x3 = simd_float3x3

// MARK: Vector functions (simd_ names)

@inlinable @inline(__always) public func simd_dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint {
    (a * b).sum()
}
@inlinable @inline(__always) public func simd_length_squared<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint {
    (v * v).sum()
}
@inlinable @inline(__always) public func simd_length<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint {
    (v * v).sum().squareRoot()
}
@inlinable @inline(__always) public func simd_distance<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint {
    simd_length(a - b)
}
@inlinable @inline(__always) public func simd_distance_squared<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint {
    simd_length_squared(a - b)
}
@inlinable @inline(__always) public func simd_normalize<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint {
    v / simd_length(v)
}
@inlinable @inline(__always) public func simd_cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
@inlinable @inline(__always) public func simd_cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
@inlinable @inline(__always) public func simd_min<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable { pointwiseMin(a, b) }
@inlinable @inline(__always) public func simd_max<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable { pointwiseMax(a, b) }
@inlinable @inline(__always) public func simd_min(_ a: Float, _ b: Float) -> Float { Swift.min(a, b) }
@inlinable @inline(__always) public func simd_max(_ a: Float, _ b: Float) -> Float { Swift.max(a, b) }
@inlinable @inline(__always) public func simd_abs<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint {
    var r = v
    for i in r.indices { r[i] = Swift.abs(v[i]) }
    return r
}
@inlinable @inline(__always) public func simd_abs(_ v: Float) -> Float { Swift.abs(v) }
@inlinable @inline(__always) public func simd_clamp<V: SIMD>(_ x: V, _ lo: V, _ hi: V) -> V where V.Scalar: Comparable {
    pointwiseMin(pointwiseMax(x, lo), hi)
}
@inlinable @inline(__always) public func simd_clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { Swift.min(Swift.max(x, lo), hi) }
@inlinable @inline(__always) public func simd_clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(x, lo), hi) }
@inlinable @inline(__always) public func simd_mix<V: SIMD>(_ x: V, _ y: V, _ t: V) -> V where V.Scalar: FloatingPoint {
    x + (y - x) * t
}
@inlinable @inline(__always) public func simd_mix(_ x: Float, _ y: Float, _ t: Float) -> Float { x + (y - x) * t }
@inlinable @inline(__always) public func simd_mix(_ x: Double, _ y: Double, _ t: Double) -> Double { x + (y - x) * t }
@inlinable @inline(__always) public func simd_reflect<V: SIMD>(_ v: V, _ n: V) -> V where V.Scalar: FloatingPoint {
    v - (2 * simd_dot(v, n)) * n
}
@inlinable @inline(__always) public func simd_fract(_ x: Float) -> Float { x - x.rounded(.down) }
@inlinable @inline(__always) public func simd_floor<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v.rounded(.down) }
@inlinable @inline(__always) public func simd_ceil<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v.rounded(.up) }

// MARK: Vector functions (short names)

@inlinable @inline(__always) public func dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_dot(a, b) }
@inlinable @inline(__always) public func length<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length(v) }
@inlinable @inline(__always) public func length_squared<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length_squared(v) }
@inlinable @inline(__always) public func distance<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_distance(a, b) }
@inlinable @inline(__always) public func distance_squared<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_distance_squared(a, b) }
@inlinable @inline(__always) public func normalize<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { simd_normalize(v) }
@inlinable @inline(__always) public func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { simd_cross(a, b) }
@inlinable @inline(__always) public func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> { simd_cross(a, b) }
@inlinable @inline(__always) public func reflect<V: SIMD>(_ v: V, n: V) -> V where V.Scalar: FloatingPoint { simd_reflect(v, n) }
@inlinable @inline(__always) public func min<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable { pointwiseMin(a, b) }
@inlinable @inline(__always) public func max<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable { pointwiseMax(a, b) }
@inlinable @inline(__always) public func abs<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { simd_abs(v) }
@inlinable @inline(__always) public func floor<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v.rounded(.down) }
@inlinable @inline(__always) public func ceil<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v.rounded(.up) }
@inlinable @inline(__always) public func trunc<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v.rounded(.towardZero) }
@inlinable @inline(__always) public func round<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v.rounded(.toNearestOrAwayFromZero) }
@inlinable @inline(__always) public func fract<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v - v.rounded(.down) }
@inlinable @inline(__always) public func fract(_ x: Float) -> Float { x - x.rounded(.down) }
@inlinable @inline(__always) public func fract(_ x: Double) -> Double { x - x.rounded(.down) }
@inlinable @inline(__always) public func sign(_ x: Float) -> Float { x > 0 ? 1 : (x < 0 ? -1 : 0) }
@inlinable @inline(__always) public func sign(_ x: Double) -> Double { x > 0 ? 1 : (x < 0 ? -1 : 0) }
@inlinable @inline(__always) public func sign<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint {
    var r = v
    for i in r.indices { r[i] = v[i] > 0 ? 1 : (v[i] < 0 ? -1 : 0) }
    return r
}
@inlinable @inline(__always) public func clamp(_ x: Float, min lo: Float, max hi: Float) -> Float { Swift.min(Swift.max(x, lo), hi) }
@inlinable @inline(__always) public func clamp(_ x: Double, min lo: Double, max hi: Double) -> Double { Swift.min(Swift.max(x, lo), hi) }
@inlinable @inline(__always) public func clamp<V: SIMD>(_ x: V, min lo: V.Scalar, max hi: V.Scalar) -> V where V.Scalar: Comparable {
    x.clamped(lowerBound: V(repeating: lo), upperBound: V(repeating: hi))
}
@inlinable @inline(__always) public func clamp<V: SIMD>(_ x: V, min lo: V, max hi: V) -> V where V.Scalar: Comparable {
    pointwiseMin(pointwiseMax(x, lo), hi)
}
@inlinable @inline(__always) public func mix(_ x: Float, _ y: Float, t: Float) -> Float { x + (y - x) * t }
@inlinable @inline(__always) public func mix(_ x: Double, _ y: Double, t: Double) -> Double { x + (y - x) * t }
@inlinable @inline(__always) public func mix<V: SIMD>(_ x: V, _ y: V, t: V.Scalar) -> V where V.Scalar: FloatingPoint { x + (y - x) * t }
@inlinable @inline(__always) public func mix<V: SIMD>(_ x: V, _ y: V, t: V) -> V where V.Scalar: FloatingPoint { x + (y - x) * t }
@inlinable @inline(__always) public func step(_ x: Float, edge: Float) -> Float { x < edge ? 0 : 1 }
@inlinable @inline(__always) public func step(_ x: Double, edge: Double) -> Double { x < edge ? 0 : 1 }
@inlinable @inline(__always) public func smoothstep(_ x: Float, edge0: Float, edge1: Float) -> Float {
    let t = Swift.min(Swift.max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
@inlinable @inline(__always) public func smoothstep(_ x: Double, edge0: Double, edge1: Double) -> Double {
    let t = Swift.min(Swift.max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: float3x3

public struct simd_float3x3: Equatable {
    public var columns: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    @inlinable public init() { columns = (.zero, .zero, .zero) }
    @inlinable public init(diagonal d: SIMD3<Float>) {
        columns = (SIMD3(d.x, 0, 0), SIMD3(0, d.y, 0), SIMD3(0, 0, d.z))
    }
    @inlinable public init(columns c: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) { columns = c }
    @inlinable public init(_ s: Float) { self.init(diagonal: SIMD3(repeating: s)) }
    @inlinable public init(_ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>) { columns = (c0, c1, c2) }
    @inlinable public init(_ c: [SIMD3<Float>]) { columns = (c[0], c[1], c[2]) }
    @inlinable public init(rows r: [SIMD3<Float>]) {
        columns = (SIMD3(r[0].x, r[1].x, r[2].x), SIMD3(r[0].y, r[1].y, r[2].y), SIMD3(r[0].z, r[1].z, r[2].z))
    }
    @inlinable public init(_ q: simd_quatf) {
        let m = simd_float4x4(q)
        columns = (SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                   SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                   SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
    }
    @inlinable public subscript(c: Int) -> SIMD3<Float> {
        get { c == 0 ? columns.0 : (c == 1 ? columns.1 : columns.2) }
        set { if c == 0 { columns.0 = newValue } else if c == 1 { columns.1 = newValue } else { columns.2 = newValue } }
    }
    @inlinable public subscript(c: Int, r: Int) -> Float {
        get { self[c][r] }
        set { var v = self[c]; v[r] = newValue; self[c] = v }
    }
    @inlinable public var transpose: simd_float3x3 {
        simd_float3x3.fromRows(columns.0, columns.1, columns.2)
    }
    @inlinable public var determinant: Float { simd_dot(columns.0, simd_cross(columns.1, columns.2)) }
    @inlinable static func fromRows(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> simd_float3x3 {
        simd_float3x3(columns: (SIMD3(a.x, b.x, c.x), SIMD3(a.y, b.y, c.y), SIMD3(a.z, b.z, c.z)))
    }
    @inlinable public var inverse: simd_float3x3 {
        let a = columns.0, b = columns.1, c = columns.2
        let r0 = simd_cross(b, c), r1 = simd_cross(c, a), r2 = simd_cross(a, b)
        let inv = 1 / simd_dot(a, r0)
        return simd_float3x3.fromRows(r0 * inv, r1 * inv, r2 * inv)
    }
    @inlinable public static func == (a: simd_float3x3, b: simd_float3x3) -> Bool {
        a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1 && a.columns.2 == b.columns.2
    }
    @inlinable public static func * (m: simd_float3x3, v: SIMD3<Float>) -> SIMD3<Float> {
        m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z
    }
    @inlinable public static func * (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 {
        simd_float3x3(columns: (a * b.columns.0, a * b.columns.1, a * b.columns.2))
    }
    @inlinable public static func * (m: simd_float3x3, s: Float) -> simd_float3x3 {
        simd_float3x3(columns: (m.columns.0 * s, m.columns.1 * s, m.columns.2 * s))
    }
    @inlinable public static func + (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 {
        simd_float3x3(columns: (a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2))
    }
    @inlinable public static func - (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 {
        simd_float3x3(columns: (a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2))
    }
}
public let matrix_identity_float3x3 = simd_float3x3(diagonal: SIMD3<Float>(1, 1, 1))
@inlinable public func simd_mul(_ a: simd_float3x3, _ b: simd_float3x3) -> simd_float3x3 { a * b }
@inlinable public func simd_mul(_ m: simd_float3x3, _ v: SIMD3<Float>) -> SIMD3<Float> { m * v }
@inlinable public func simd_transpose(_ m: simd_float3x3) -> simd_float3x3 { m.transpose }
@inlinable public func simd_inverse(_ m: simd_float3x3) -> simd_float3x3 { m.inverse }

// MARK: float4x4

public struct simd_float4x4: Equatable {
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    @inlinable public init() { columns = (.zero, .zero, .zero, .zero) }
    @inlinable public init(diagonal d: SIMD4<Float>) {
        columns = (SIMD4(d.x, 0, 0, 0), SIMD4(0, d.y, 0, 0), SIMD4(0, 0, d.z, 0), SIMD4(0, 0, 0, d.w))
    }
    @inlinable public init(columns c: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)) { columns = c }
    @inlinable public init(_ s: Float) { self.init(diagonal: SIMD4(repeating: s)) }
    @inlinable public init(_ c0: SIMD4<Float>, _ c1: SIMD4<Float>, _ c2: SIMD4<Float>, _ c3: SIMD4<Float>) { columns = (c0, c1, c2, c3) }
    @inlinable public init(_ c: [SIMD4<Float>]) { columns = (c[0], c[1], c[2], c[3]) }
    @inlinable public init(rows r: [SIMD4<Float>]) {
        columns = (SIMD4(r[0].x, r[1].x, r[2].x, r[3].x), SIMD4(r[0].y, r[1].y, r[2].y, r[3].y),
                   SIMD4(r[0].z, r[1].z, r[2].z, r[3].z), SIMD4(r[0].w, r[1].w, r[2].w, r[3].w))
    }
    @inlinable public init(_ q: simd_quatf) {
        let x = q.vector.x, y = q.vector.y, z = q.vector.z, w = q.vector.w
        let xx = x * x, yy = y * y, zz = z * z
        let xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z
        columns = (SIMD4(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0),
                   SIMD4(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0),
                   SIMD4(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0),
                   SIMD4(0, 0, 0, 1))
    }
    @inlinable public subscript(c: Int) -> SIMD4<Float> {
        get {
            switch c { case 0: return columns.0; case 1: return columns.1; case 2: return columns.2; default: return columns.3 }
        }
        set {
            switch c { case 0: columns.0 = newValue; case 1: columns.1 = newValue; case 2: columns.2 = newValue; default: columns.3 = newValue }
        }
    }
    @inlinable public subscript(c: Int, r: Int) -> Float {
        get { self[c][r] }
        set { var v = self[c]; v[r] = newValue; self[c] = v }
    }
    @inlinable public var transpose: simd_float4x4 {
        let a = columns.0, b = columns.1, c = columns.2, d = columns.3
        return simd_float4x4(columns: (SIMD4(a.x, b.x, c.x, d.x), SIMD4(a.y, b.y, c.y, d.y), SIMD4(a.z, b.z, c.z, d.z), SIMD4(a.w, b.w, c.w, d.w)))
    }
    @inlinable public var determinant: Float {
        let m = self
        var det: Float = 0
        for c in 0..<4 {
            det += (c % 2 == 0 ? 1 : -1) * m[c, 0] * simd_float4x4.minor3(m, skipCol: c)
        }
        return det
    }
    @inlinable static func minor3(_ m: simd_float4x4, skipCol: Int) -> Float {
        func col(_ c: Int) -> SIMD3<Float> { SIMD3(m[c, 1], m[c, 2], m[c, 3]) }
        let a = col(skipCol == 0 ? 1 : 0), b = col(skipCol <= 1 ? 2 : 1), c = col(skipCol <= 2 ? 3 : 2)
        return simd_dot(a, simd_cross(b, c))
    }
    // General 4x4 inverse (cofactor expansion, as in MESA's gluInvertMatrix), column-major storage. Scalars only: the
    // array form allocated twice per call (questcheck allocation trace: four times per rendered frame).
    @inlinable public var inverse: simd_float4x4 {
        let c0 = columns.0, c1 = columns.1, c2 = columns.2, c3 = columns.3
        let m0 = c0.x, m1 = c0.y, m2 = c0.z, m3 = c0.w
        let m4 = c1.x, m5 = c1.y, m6 = c1.z, m7 = c1.w
        let m8 = c2.x, m9 = c2.y, m10 = c2.z, m11 = c2.w
        let m12 = c3.x, m13 = c3.y, m14 = c3.z, m15 = c3.w
        let i0: Float = m5 * m10 * m15 - m5 * m11 * m14 - m9 * m6 * m15 + m9 * m7 * m14 + m13 * m6 * m11 - m13 * m7 * m10
        let i4: Float = -m4 * m10 * m15 + m4 * m11 * m14 + m8 * m6 * m15 - m8 * m7 * m14 - m12 * m6 * m11 + m12 * m7 * m10
        let i8: Float = m4 * m9 * m15 - m4 * m11 * m13 - m8 * m5 * m15 + m8 * m7 * m13 + m12 * m5 * m11 - m12 * m7 * m9
        let i12: Float = -m4 * m9 * m14 + m4 * m10 * m13 + m8 * m5 * m14 - m8 * m6 * m13 - m12 * m5 * m10 + m12 * m6 * m9
        let i1: Float = -m1 * m10 * m15 + m1 * m11 * m14 + m9 * m2 * m15 - m9 * m3 * m14 - m13 * m2 * m11 + m13 * m3 * m10
        let i5: Float = m0 * m10 * m15 - m0 * m11 * m14 - m8 * m2 * m15 + m8 * m3 * m14 + m12 * m2 * m11 - m12 * m3 * m10
        let i9: Float = -m0 * m9 * m15 + m0 * m11 * m13 + m8 * m1 * m15 - m8 * m3 * m13 - m12 * m1 * m11 + m12 * m3 * m9
        let i13: Float = m0 * m9 * m14 - m0 * m10 * m13 - m8 * m1 * m14 + m8 * m2 * m13 + m12 * m1 * m10 - m12 * m2 * m9
        let i2: Float = m1 * m6 * m15 - m1 * m7 * m14 - m5 * m2 * m15 + m5 * m3 * m14 + m13 * m2 * m7 - m13 * m3 * m6
        let i6: Float = -m0 * m6 * m15 + m0 * m7 * m14 + m4 * m2 * m15 - m4 * m3 * m14 - m12 * m2 * m7 + m12 * m3 * m6
        let i10: Float = m0 * m5 * m15 - m0 * m7 * m13 - m4 * m1 * m15 + m4 * m3 * m13 + m12 * m1 * m7 - m12 * m3 * m5
        let i14: Float = -m0 * m5 * m14 + m0 * m6 * m13 + m4 * m1 * m14 - m4 * m2 * m13 - m12 * m1 * m6 + m12 * m2 * m5
        let i3: Float = -m1 * m6 * m11 + m1 * m7 * m10 + m5 * m2 * m11 - m5 * m3 * m10 - m9 * m2 * m7 + m9 * m3 * m6
        let i7: Float = m0 * m6 * m11 - m0 * m7 * m10 - m4 * m2 * m11 + m4 * m3 * m10 + m8 * m2 * m7 - m8 * m3 * m6
        let i11: Float = -m0 * m5 * m11 + m0 * m7 * m9 + m4 * m1 * m11 - m4 * m3 * m9 - m8 * m1 * m7 + m8 * m3 * m5
        let i15: Float = m0 * m5 * m10 - m0 * m6 * m9 - m4 * m1 * m10 + m4 * m2 * m9 + m8 * m1 * m6 - m8 * m2 * m5
        let det: Float = m0 * i0 + m1 * i4 + m2 * i8 + m3 * i12
        let s: Float = det == 0 ? 0 : 1 / det
        return simd_float4x4(columns: (SIMD4(i0, i1, i2, i3) * s, SIMD4(i4, i5, i6, i7) * s,
                                       SIMD4(i8, i9, i10, i11) * s, SIMD4(i12, i13, i14, i15) * s))
    }
    @inlinable public static func == (a: simd_float4x4, b: simd_float4x4) -> Bool {
        a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1 && a.columns.2 == b.columns.2 && a.columns.3 == b.columns.3
    }
    @inlinable @inline(__always) public static func * (m: simd_float4x4, v: SIMD4<Float>) -> SIMD4<Float> {
        let a = m.columns.0 * v.x + m.columns.1 * v.y
        let b = m.columns.2 * v.z + m.columns.3 * v.w
        return a + b
    }
    @inlinable public static func * (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        simd_float4x4(columns: (a * b.columns.0, a * b.columns.1, a * b.columns.2, a * b.columns.3))
    }
    @inlinable public static func * (m: simd_float4x4, s: Float) -> simd_float4x4 {
        simd_float4x4(columns: (m.columns.0 * s, m.columns.1 * s, m.columns.2 * s, m.columns.3 * s))
    }
    @inlinable public static func + (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        simd_float4x4(columns: (a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2, a.columns.3 + b.columns.3))
    }
    @inlinable public static func *= (a: inout simd_float4x4, b: simd_float4x4) { a = a * b }
}
public let matrix_identity_float4x4 = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
@inlinable public func simd_mul(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 { a * b }
@inlinable public func simd_mul(_ m: simd_float4x4, _ v: SIMD4<Float>) -> SIMD4<Float> { m * v }
@inlinable public func simd_transpose(_ m: simd_float4x4) -> simd_float4x4 { m.transpose }
@inlinable public func simd_inverse(_ m: simd_float4x4) -> simd_float4x4 { m.inverse }

// MARK: Quaternions (x, y, z imaginary, w real; same layout as Apple's simd_quatf)

public struct simd_quatf: Equatable {
    public var vector: SIMD4<Float>
    @inlinable public init() { vector = SIMD4(0, 0, 0, 1) }
    @inlinable public init(vector v: SIMD4<Float>) { vector = v }
    @inlinable public init(ix: Float, iy: Float, iz: Float, r: Float) { vector = SIMD4(ix, iy, iz, r) }
    @inlinable public init(real r: Float, imag i: SIMD3<Float>) { vector = SIMD4(i.x, i.y, i.z, r) }
    @inlinable public init(angle: Float, axis: SIMD3<Float>) {
        let n = simd_normalize(axis)
        let s = sinf(angle * 0.5), c = cosf(angle * 0.5)
        vector = SIMD4(n.x * s, n.y * s, n.z * s, c)
    }
    // Shortest rotation taking unit vector `from` onto unit vector `to`.
    @inlinable public init(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let d = simd_dot(a, b)
        if d < -0.999999 {
            var axis = simd_cross(SIMD3<Float>(1, 0, 0), a)
            if simd_length_squared(axis) < 1e-6 { axis = simd_cross(SIMD3<Float>(0, 1, 0), a) }
            self.init(angle: .pi, axis: axis)
            return
        }
        let c = simd_cross(a, b)
        let q = SIMD4<Float>(c.x, c.y, c.z, 1 + d)
        self.init(vector: q / simd_length(q))
    }
    @inlinable public init(_ m: simd_float3x3) {
        let c0 = m.columns.0, c1 = m.columns.1, c2 = m.columns.2
        let tr = c0.x + c1.y + c2.z
        if tr > 0 {
            let s = (tr + 1).squareRoot() * 2
            vector = SIMD4((c1.z - c2.y) / s, (c2.x - c0.z) / s, (c0.y - c1.x) / s, 0.25 * s)
        } else if c0.x > c1.y && c0.x > c2.z {
            let s = (1 + c0.x - c1.y - c2.z).squareRoot() * 2
            vector = SIMD4(0.25 * s, (c1.x + c0.y) / s, (c2.x + c0.z) / s, (c1.z - c2.y) / s)
        } else if c1.y > c2.z {
            let s = (1 + c1.y - c0.x - c2.z).squareRoot() * 2
            vector = SIMD4((c1.x + c0.y) / s, 0.25 * s, (c2.y + c1.z) / s, (c2.x - c0.z) / s)
        } else {
            let s = (1 + c2.z - c0.x - c1.y).squareRoot() * 2
            vector = SIMD4((c2.x + c0.z) / s, (c2.y + c1.z) / s, 0.25 * s, (c0.y - c1.x) / s)
        }
    }
    @inlinable public init(_ m: simd_float4x4) {
        self.init(simd_float3x3(columns: (SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                          SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                          SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))))
    }
    @inlinable public var real: Float {
        get { vector.w }
        set { vector.w = newValue }
    }
    @inlinable public var imag: SIMD3<Float> {
        get { SIMD3(vector.x, vector.y, vector.z) }
        set { vector.x = newValue.x; vector.y = newValue.y; vector.z = newValue.z }
    }
    @inlinable public var length: Float { simd_length(vector) }
    @inlinable public var normalized: simd_quatf { simd_quatf(vector: vector / simd_length(vector)) }
    @inlinable public var conjugate: simd_quatf { simd_quatf(vector: SIMD4(-vector.x, -vector.y, -vector.z, vector.w)) }
    @inlinable public var inverse: simd_quatf {
        let c = conjugate
        return simd_quatf(vector: c.vector / simd_length_squared(vector))
    }
    @inlinable public var angle: Float { 2 * atan2f(simd_length(imag), real) }
    @inlinable public var axis: SIMD3<Float> {
        let l = simd_length(imag)
        return l > 0 ? imag / l : SIMD3(1, 0, 0)
    }
    @inlinable @inline(__always) public func act(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let u = imag, s = real
        let t = 2 * simd_cross(u, v)
        return v + s * t + simd_cross(u, t)
    }
    @inlinable public static func * (a: simd_quatf, b: simd_quatf) -> simd_quatf {
        let ai = a.imag, bi = b.imag
        let r = a.real * b.real - simd_dot(ai, bi)
        let i = a.real * bi + b.real * ai + simd_cross(ai, bi)
        return simd_quatf(real: r, imag: i)
    }
    @inlinable public static func * (a: simd_quatf, s: Float) -> simd_quatf { simd_quatf(vector: a.vector * s) }
    @inlinable public static func + (a: simd_quatf, b: simd_quatf) -> simd_quatf { simd_quatf(vector: a.vector + b.vector) }
    @inlinable public static func - (a: simd_quatf, b: simd_quatf) -> simd_quatf { simd_quatf(vector: a.vector - b.vector) }
    @inlinable public static prefix func - (a: simd_quatf) -> simd_quatf { simd_quatf(vector: -a.vector) }
    @inlinable public static func == (a: simd_quatf, b: simd_quatf) -> Bool { a.vector == b.vector }
}
@inlinable public func simd_normalize(_ q: simd_quatf) -> simd_quatf { q.normalized }
@inlinable public func simd_conjugate(_ q: simd_quatf) -> simd_quatf { q.conjugate }
@inlinable public func simd_inverse(_ q: simd_quatf) -> simd_quatf { q.inverse }
@inlinable public func simd_mul(_ a: simd_quatf, _ b: simd_quatf) -> simd_quatf { a * b }
@inlinable public func simd_act(_ q: simd_quatf, _ v: SIMD3<Float>) -> SIMD3<Float> { q.act(v) }
@inlinable public func simd_dot(_ a: simd_quatf, _ b: simd_quatf) -> Float { simd_dot(a.vector, b.vector) }
@inlinable public func simd_length(_ q: simd_quatf) -> Float { q.length }
@inlinable public func simd_angle(_ q: simd_quatf) -> Float { q.angle }
@inlinable public func simd_axis(_ q: simd_quatf) -> SIMD3<Float> { q.axis }
@inlinable public func simd_slerp(_ a: simd_quatf, _ b0: simd_quatf, _ t: Float) -> simd_quatf {
    var b = b0
    var d = simd_dot(a.vector, b.vector)
    if d < 0 { b = -b; d = -d }
    if d > 0.9995 { return simd_quatf(vector: a.vector + (b.vector - a.vector) * t).normalized }
    let th = acosf(d)
    let s = sinf(th)
    let wa = sinf((1 - t) * th) / s, wb = sinf(t * th) / s
    return simd_quatf(vector: a.vector * wa + b.vector * wb)
}
@inlinable public func simd_slerp_longest(_ a: simd_quatf, _ b: simd_quatf, _ t: Float) -> simd_quatf { simd_slerp(a, b, t) }

