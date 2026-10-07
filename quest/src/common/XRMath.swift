import Foundation
import simd

// Camera math for the headset: OpenXR's asymmetric per-eye fields of view and poses -> the Mac renderer's
// conventions (right-handed, -Z forward, clip z in [0, 1], y up; Vulkan's y-down is undone by a flipped viewport).
enum XRMath {
    // Projection from the four half-angle tangents (left/down negative), depth 0 (near) ... 1 (far).
    static func projection(tanLeft l: Float, tanRight r: Float, tanUp u: Float, tanDown d: Float, near n: Float, far f: Float) -> float4x4 {
        let w = r - l, h = u - d
        let zs = f / (n - f)
        return float4x4(columns: (V4(2 / w, 0, 0, 0),
                                  V4(0, 2 / h, 0, 0),
                                  V4((r + l) / w, (u + d) / h, zs, -1),
                                  V4(0, 0, zs * n, 0)))
    }

    // Rigid transform (rotation then translation) as a matrix.
    static func pose(_ q: simd_quatf, _ p: V3) -> float4x4 {
        var m = float4x4(q)
        m.columns.3 = V4(p.x, p.y, p.z, 1)
        return m
    }

    // Inverse of a rigid transform.
    static func inversePose(_ q: simd_quatf, _ p: V3) -> float4x4 {
        let qi = q.conjugate
        var m = float4x4(qi)
        let t = qi.act(-p)
        m.columns.3 = V4(t.x, t.y, t.z, 1)
        return m
    }

    // Yaw (about +Y, the game's convention: 0 looks -Z, positive turns left) and pitch of a rotation's forward axis.
    /// Yaw of the body under a head pose, stable at every pitch and roll: the forward vector dominates while looking
    /// level, the head's up vector takes over as the gaze tips down or up (f.xz * u.y - u.xz * f.y is exactly the
    /// level forward for any pitch, and roll only shortens it). atan2 of the raw forward spins and jitters when
    /// looking near straight down (walking while looking at the ground).
    static func levelYaw(_ q: simd_quatf) -> Float {
        let f = q.act(V3(0, 0, -1)), u = q.act(V3(0, 1, 0))
        let hx = f.x * u.y - u.x * f.y, hz = f.z * u.y - u.z * f.y
        return hx * hx + hz * hz < 1e-8 ? atan2f(-f.x, -f.z) : atan2f(-hx, -hz)
    }

    static func yawPitch(_ q: simd_quatf) -> (Float, Float) {
        let f = q.act(V3(0, 0, -1))
        let yaw = atan2f(-f.x, -f.z)
        let pitch = asinf(max(-1, min(1, f.y)))
        return (yaw, pitch)
    }
}
