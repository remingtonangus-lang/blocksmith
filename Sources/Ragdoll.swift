import Foundation
import simd

// Realistic world, layer 3 (docs/design/realistic-world.md 3.3): ragdolls. A dying creature's model parts, grouped
// into bones (oriented boxes hanging from their parent at a pivot), fall over, flop, slide down slopes and settle on
// the drawn ground (PhysicsGround), thrown by the killing blow; then they sleep and cost nothing.
//
// Why rigid bodies (XPBD, Muller et al. 2020, "Detailed Rigid Body Simulation with Extended Position Based
// Dynamics") rather than particles: a bone is exactly what the game draws (a box with an orientation), so the read-out
// is the body pose with no frame fitting; cones, twist ranges and hinges are direct angle constraints, not fragile
// extra distances; and a box can't invert the way a particle tetrahedron does under a hard landing. Small steps (8
// sub-steps of one Gauss-Seidel pass per 72 Hz frame) keep rigid joints tight without iterations or a global solve.
//
// One sub-step: integrate; joint limits (swing clamped to the cone keeping its direction, twist or bend clamped to
// its range, as one rotation, so a limb resting on its limit isn't walked round it); limb ends out of the torso;
// ground contacts; pivots joined last, so the pose read out is attached; velocities from the moves, then a velocity
// pass (no bounce, Coulomb friction). Air, flesh and joint damping once per frame.
//
// Death: the blow throws the body as if it were rigid at that instant, plus a share on the bone it hit; a body the
// blow doesn't move sideways enough gets a shove at the top (a creature standing on stick legs is a table and would
// stay up), and every bone a little seeded spin, so limbs fold even when nothing pushes them.
//
// Ground: one query per box corner per frame, at the corner's predicted end-of-frame position nudged down by a
// margin. A hit gives a contact plane the sub-steps project against (speculative: a corner may close the gap but
// never pass the plane), so resting corners never flicker in and out of contact. Static friction holds each touching
// corner at an anchor kept across sub-steps and frames, so the joints can't walk a resting body across the ground; a
// body that died half inside a block leaves it at a set speed instead of being fired out.
//
// Sleep: when no point of any bone has strayed more than restTolerance from where it was a second ago. A window on
// position, not a speed test: millimetre contact jitter never keeps a body awake (and the window widens for a body
// awake past 3 s, so a slow creep can't either). Waking is the game's call: wake(near:radius:) when the ground changes.
//
// Storage: every ragdoll owns a fixed slot of 12 bones in flat buffers allocated once; no step allocates.

enum RagdollJointKind: UInt8 {
    case ball       // cone (swing) plus a twist range about the bone's own axis: neck, shoulder, hip, tail
    case hinge      // one axis with a bend range: knee, elbow, hock
}

// Limits are angles from the neutral pose (the creature's model with no animation), not from the pose it died in, so
// a leg that died mid-stride still has its full range. Angles in radians.
struct RagdollJoint {
    var kind: RagdollJointKind
    var swing: Float                // ball: largest angle between the parent's and the child's twist axes
    var lo: Float, hi: Float        // ball: twist range about the twist axis; hinge: bend range about the hinge axis
    // Twist axis in the child's box frame; zero means "from the pivot to the box centre" (how a limb hangs).
    var axis: SIMD3<Float> = .zero
    // Hinge axis in the child's box frame. Right-hand rule: a positive bend turns the child about it. For a creature
    // facing +Z with limbs hanging down and axis +X: a knee bends 0...140 degrees (foot back), an elbow -145...0.
    var hingeAxis = SIMD3<Float>(1, 0, 0)
    // The child's orientation relative to its parent in the neutral pose. Identity when, unanimated, every part of
    // the model shares the creature's orientation (true of every model in the game).
    var neutral = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    static func ball(swing: Float, twist: Float) -> RagdollJoint {      // degrees
        let k = Float.pi / 180
        return RagdollJoint(kind: .ball, swing: swing * k, lo: -twist * k, hi: twist * k)
    }
    static func hinge(min: Float, max: Float, axis: SIMD3<Float> = SIMD3(1, 0, 0)) -> RagdollJoint {   // degrees
        let k = Float.pi / 180
        var j = RagdollJoint(kind: .hinge, swing: 0, lo: min * k, hi: max * k)
        j.hingeAxis = axis
        return j
    }
    static let neck = ball(swing: 45, twist: 50)
    static let shoulder = ball(swing: 100, twist: 60)
    static let hip = ball(swing: 80, twist: 30)
    static let spine = ball(swing: 30, twist: 20)
    static let tail = ball(swing: 60, twist: 30)
    static let knee = hinge(min: 0, max: 140)
    static let elbow = hinge(min: -145, max: 0)
}

// One bone at the moment of death, in world space. The parts drawn with it have their vertices in this box's frame
// (centre + orientation), or in world space at this instant: the read-outs serve both.
struct RagdollBone {
    var centre: SIMD3<Float>
    var half: SIMD3<Float>          // half extents of the box, in its own frame
    var orientation: simd_quatf
    var parent: Int                 // index of the bone it hangs from (lower than its own), -1 for the root
    var pivot: SIMD3<Float>         // world point where it hangs from its parent (ignored for a root)
    var joint: RagdollJoint
    var density: Float              // relative; mass follows box volume times this

    init(centre: SIMD3<Float>, half: SIMD3<Float>, orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
         parent: Int = -1, pivot: SIMD3<Float> = .zero, joint: RagdollJoint = .neck, density: Float = 1) {
        self.centre = centre; self.half = half; self.orientation = orientation
        self.parent = parent; self.pivot = pivot; self.joint = joint; self.density = density
    }
}

// Vector and quaternion helpers on raw SIMD4 (x, y, z, w): the same on Apple simd and the Linux shim, and they
// inline into the solver.
enum RagdollMath {
    @inline(__always) static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let m = a * b
        return m.x + m.y + m.z
    }
    @inline(__always) static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    @inline(__always) static func length(_ a: SIMD3<Float>) -> Float { dot(a, a).squareRoot() }
    @inline(__always) static func xyz(_ q: SIMD4<Float>) -> SIMD3<Float> { SIMD3(q.x, q.y, q.z) }
    @inline(__always) static func abs(_ a: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(Swift.abs(a.x), Swift.abs(a.y), Swift.abs(a.z))
    }
    @inline(__always) static func clamp(_ a: SIMD3<Float>, _ h: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(Swift.min(Swift.max(a.x, -h.x), h.x), Swift.min(Swift.max(a.y, -h.y), h.y),
              Swift.min(Swift.max(a.z, -h.z), h.z))
    }
    @inline(__always) static func rot(_ q: SIMD4<Float>, _ v: SIMD3<Float>) -> SIMD3<Float> {
        let u = xyz(q)
        let t = cross(u, v) * 2
        return v + t * q.w + cross(u, t)
    }
    @inline(__always) static func rotInv(_ q: SIMD4<Float>, _ v: SIMD3<Float>) -> SIMD3<Float> {
        let u = -xyz(q)
        let t = cross(u, v) * 2
        return v + t * q.w + cross(u, t)
    }
    @inline(__always) static func mul(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
        let ai = xyz(a), bi = xyz(b)
        let i = bi * a.w + ai * b.w + cross(ai, bi)
        return SIMD4(i.x, i.y, i.z, a.w * b.w - dot(ai, bi))
    }
    @inline(__always) static func conj(_ q: SIMD4<Float>) -> SIMD4<Float> { SIMD4(-q.x, -q.y, -q.z, q.w) }
    // q turned by the small world rotation vector d: q + d/2 * q, renormalised (the XPBD orientation update).
    @inline(__always) static func turn(_ q: SIMD4<Float>, _ d: SIMD3<Float>) -> SIMD4<Float> {
        let u = xyz(q)
        let i = (d * q.w + cross(d, u)) * 0.5
        let r = dot(d, u) * -0.5
        let n = SIMD4<Float>(q.x + i.x, q.y + i.y, q.z + i.z, q.w + r)
        return n * (1 / (n * n).sum().squareRoot())
    }
    typealias Axes = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    // The rotation of unit q as a matrix (its columns): cheaper than rot() once a box needs several corners.
    @inline(__always) static func basis(_ q: SIMD4<Float>) -> Axes {
        let x = q.x, y = q.y, z = q.z, w = q.w
        let xx = x * x, yy = y * y, zz = z * z, xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z
        return (SIMD3(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy)),
                SIMD3(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx)),
                SIMD3(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy)))
    }
    // A box's half axes in world space: its corner c is at the centre plus corner(axes, c).
    @inline(__always) static func axes(_ q: SIMD4<Float>, _ h: SIMD3<Float>) -> Axes {
        let b = basis(q)
        return (b.0 * h.x, b.1 * h.y, b.2 * h.z)
    }
    // Corner c (0...7): bit 0 is +x, bit 1 +y, bit 2 +z.
    @inline(__always) static func corner(_ a: Axes, _ c: Int) -> SIMD3<Float> {
        a.0 * Float((c & 1) * 2 - 1) + a.1 * Float((c & 2) - 1) + a.2 * Float(((c >> 1) & 2) - 1)
    }
    // Columns of R diag(d) R^T, R the rotation of unit q: a box's inverse inertia in world axes.
    @inline(__always) static func tensor(_ q: SIMD4<Float>, _ d: SIMD3<Float>) -> Axes {
        let (c0, c1, c2) = basis(q)
        let a = c0 * d.x, b = c1 * d.y, c = c2 * d.z
        return (a * c0.x + b * c1.x + c * c2.x, a * c0.y + b * c1.y + c * c2.y, a * c0.z + b * c1.z + c * c2.z)
    }
    @inline(__always) static func finite(_ a: SIMD3<Float>) -> Bool { a.x.isFinite && a.y.isFinite && a.z.isFinite }
    @inline(__always) static func finite(_ a: SIMD4<Float>) -> Bool { finite(xyz(a)) && a.w.isFinite }
    static func unit(_ v: SIMD3<Float>, or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let l = length(v)
        return l > 1e-6 && l.isFinite ? v / l : fallback
    }
    static func unit4(_ q: SIMD4<Float>) -> SIMD4<Float> {
        let l = (q * q).sum().squareRoot()
        return l > 1e-6 && l.isFinite ? q / l : SIMD4(0, 0, 0, 1)
    }
    // Deterministic noise in -1...1, so a given death always slumps the same way.
    static func noise(_ seed: UInt32) -> Float {
        var h = seed &* 0x9E37_79B1
        h ^= h >> 15; h = h &* 0x85EB_CA77; h ^= h >> 13; h = h &* 0xC2B2_AE3D; h ^= h >> 16
        return Float(h & 0xFFFF) / 32767.5 - 1
    }
}

final class RagdollWorld {
    static let maxBones = 12
    private static let slotBits = 6             // handle = generation << 6 | slot, so capacity <= 64
    let capacity: Int

    // Tuning, in blocks and seconds.
    var gravity: Float = 28
    var substeps = 8                            // per step() call; 8 at 72 fps is 576 Hz
    var staticFriction: Float = 0.7
    var dynamicFriction: Float = 0.7
    var linearDamping: Float = 0.3              // 1/s: air and flesh
    var angularDamping: Float = 1.5             // 1/s
    var jointDamping: Float = 8                 // 1/s: relative spin across a joint dies at this rate (limp muscle)
    var jointFriction: Float = 3                // rad/s per s: and loses this much outright, so slow flops stop
    var restTolerance: Float = 0.02             // no point of any bone strays further than this from where it was...
    var sleepDelay: Float = 1                   // ...for this long, and the ragdoll sleeps
    var contactMargin: Float = 0.03             // corners this close above the ground get a contact plane
    var depenetration: Float = 2                // blocks/s: a corner that starts inside the ground leaves this fast
    var hitShare: Float = 0.3                   // part of the blow given to the bone it hit alone (the limb flails)
    var maxKick: Float = 12                     // cap on that bone's extra speed from the blow
    var slump: Float = 0.7                      // rad/s of seeded random spin per bone, so limbs fold on their own
    var topple: Float = 1                       // blocks/s: the least sideways speed a death gives the top of the body
    var maxSpeed: Float = 40                    // safety clamps against a bad ground answer
    var maxSpin: Float = 40
    private static let hingePlay: Float = 0.035 // radians a hinge may swing off its axis: a zero-wide cone jitters
    private static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    private(set) var queries = 0                // ground queries made by the last step (diagnostics)
    private(set) var recoveries = 0             // ragdolls reset after a non-finite pose (has never happened in tests)

    // Per slot.
    private let used: UnsafeMutablePointer<Bool>
    private let awake: UnsafeMutablePointer<Bool>
    private let gen: UnsafeMutablePointer<Int>
    private let count: UnsafeMutablePointer<Int>
    private let born: UnsafeMutablePointer<Int>
    private let still: UnsafeMutablePointer<Float>
    private let awakeFor: UnsafeMutablePointer<Float>
    private var births = 0

    // Per bone (slot * 12 + bone): state; previous sub-step; frame start (for recovery); start pose (for read-out);
    // rest check (the pose when the still timer started).
    private let x: UnsafeMutablePointer<SIMD3<Float>>
    private let q: UnsafeMutablePointer<SIMD4<Float>>
    private let v: UnsafeMutablePointer<SIMD3<Float>>
    private let w: UnsafeMutablePointer<SIMD3<Float>>
    private let xp: UnsafeMutablePointer<SIMD3<Float>>
    private let qp: UnsafeMutablePointer<SIMD4<Float>>
    private let xf: UnsafeMutablePointer<SIMD3<Float>>
    private let qf: UnsafeMutablePointer<SIMD4<Float>>
    private let x0: UnsafeMutablePointer<SIMD3<Float>>
    private let q0: UnsafeMutablePointer<SIMD4<Float>>
    private let xr: UnsafeMutablePointer<SIMD3<Float>>
    private let qr: UnsafeMutablePointer<SIMD4<Float>>
    private let invM: UnsafeMutablePointer<Float>
    private let invI: UnsafeMutablePointer<SIMD3<Float>>    // diagonal, in the box frame
    private let iw0: UnsafeMutablePointer<SIMD3<Float>>     // the same in world axes (columns), once per sub-step
    private let iw1: UnsafeMutablePointer<SIMD3<Float>>
    private let iw2: UnsafeMutablePointer<SIMD3<Float>>
    private let half: UnsafeMutablePointer<SIMD3<Float>>
    private let parent: UnsafeMutablePointer<Int>
    // Joint to the parent: the pivot in each body's frame, the child's twist (ball) or hinge axis in its frame, the
    // neutral pose (child relative to parent), and the limits as half-angle cosines and sines, so the common case (in
    // range) needs no trigonometry: cone = (cos, sin of half the cone), range = (sin, cos of half lo; sin, cos of
    // half hi).
    private let anchorP: UnsafeMutablePointer<SIMD3<Float>>
    private let anchorC: UnsafeMutablePointer<SIMD3<Float>>
    private let axisC: UnsafeMutablePointer<SIMD3<Float>>
    private let neutralQ: UnsafeMutablePointer<SIMD4<Float>>
    private let cone: UnsafeMutablePointer<SIMD2<Float>>
    private let range: UnsafeMutablePointer<SIMD4<Float>>
    private let sphere: UnsafeMutablePointer<SIMD4<Float>>     // far-end sphere in the box frame + radius (0 = none)
    private let sphereHit: UnsafeMutablePointer<SIMD4<Float>>  // this sub-step's touch: torso normal (world), push
    private let sphereNear: UnsafeMutablePointer<Bool>         // this frame: the sphere may reach the root box
    // Per corner (bone * 8 + corner): contact plane (n, n.p on the surface), this sub-step's normal push, and where
    // static friction holds the corner (w 1 = held).
    private let planeMask: UnsafeMutablePointer<UInt8>     // per bone: corners with a contact plane this frame
    private let touchMask: UnsafeMutablePointer<UInt8>     // per bone: corners pushed out in this sub-step
    private let plane: UnsafeMutablePointer<SIMD4<Float>>
    private let lam: UnsafeMutablePointer<Float>           // valid where touchMask has the corner
    private let anchor: UnsafeMutablePointer<SIMD4<Float>>
    private var buffers: [UnsafeMutableRawPointer] = []

    init(capacity: Int = 32) {
        let cap = Swift.max(1, Swift.min(capacity, 1 << RagdollWorld.slotBits))
        self.capacity = cap
        let nb = cap * RagdollWorld.maxBones
        var all: [UnsafeMutableRawPointer] = []
        func make<T>(_ n: Int, _ value: T) -> UnsafeMutablePointer<T> {
            let p = UnsafeMutablePointer<T>.allocate(capacity: n)
            p.initialize(repeating: value, count: n)
            all.append(UnsafeMutableRawPointer(p))
            return p
        }
        let z3 = SIMD3<Float>.zero, id4 = SIMD4<Float>(0, 0, 0, 1)
        used = make(cap, false); awake = make(cap, false); gen = make(cap, 0); count = make(cap, 0)
        born = make(cap, 0); still = make(cap, 0); awakeFor = make(cap, 0)
        x = make(nb, z3); q = make(nb, id4); v = make(nb, z3); w = make(nb, z3)
        xp = make(nb, z3); qp = make(nb, id4); xf = make(nb, z3); qf = make(nb, id4)
        x0 = make(nb, z3); q0 = make(nb, id4); xr = make(nb, z3); qr = make(nb, id4)
        invM = make(nb, 0); invI = make(nb, z3); iw0 = make(nb, z3); iw1 = make(nb, z3); iw2 = make(nb, z3)
        half = make(nb, z3); parent = make(nb, -1)
        anchorP = make(nb, z3); anchorC = make(nb, z3); axisC = make(nb, z3); neutralQ = make(nb, id4)
        cone = make(nb, SIMD2(1, 0)); range = make(nb, .zero); sphere = make(nb, .zero); sphereHit = make(nb, .zero)
        sphereNear = make(nb, false)
        planeMask = make(nb, 0); touchMask = make(nb, 0)
        plane = make(nb * 8, .zero); lam = make(nb * 8, 0); anchor = make(nb * 8, .zero)
        buffers = all
    }

    deinit { for p in buffers { p.deallocate() } }     // trivial element types: nothing to deinitialize

    // MARK: handles

    @inline(__always) private func slot(_ id: Int) -> Int? {
        let s = id & ((1 << RagdollWorld.slotBits) - 1)
        guard id >= 0, s < capacity, used[s], gen[s] == id >> RagdollWorld.slotBits else { return nil }
        return s
    }
    func isLive(_ id: Int) -> Bool { slot(id) != nil }
    func isAwake(_ id: Int) -> Bool { slot(id).map { awake[$0] } ?? false }
    func boneCount(_ id: Int) -> Int { slot(id).map { count[$0] } ?? 0 }
    var liveCount: Int { (0..<capacity).reduce(0) { $0 + (used[$1] ? 1 : 0) } }
    var awakeCount: Int { (0..<capacity).reduce(0) { $0 + (used[$1] && awake[$1] ? 1 : 0) } }

    func remove(_ id: Int) { if let s = slot(id) { used[s] = false; awake[s] = false } }
    func removeAll() { for s in 0..<capacity { used[s] = false; awake[s] = false } }
    func wake(_ id: Int) { if let s = slot(id) { rouse(s) } }
    // Wake every sleeping ragdoll with a bone centre within radius of p (the ground under it was dug, a blast).
    func wake(near p: SIMD3<Float>, radius: Float) {
        let r2 = radius * radius
        for s in 0..<capacity where used[s] && !awake[s] {
            let base = s * RagdollWorld.maxBones
            for b in 0..<count[s] {
                let d = x[base + b] - p
                if RagdollMath.dot(d, d) <= r2 { rouse(s); break }
            }
        }
    }
    private func rouse(_ s: Int) {
        if !awake[s] {                              // the ground may have changed: friction holds start afresh
            let base = s * RagdollWorld.maxBones
            for k in base..<(base + count[s]) { for c in 0..<8 { anchor[k * 8 + c].w = 0 } }
        }
        awake[s] = true; still[s] = 0; awakeFor[s] = 0
        let base = s * RagdollWorld.maxBones
        for k in base..<(base + count[s]) { xr[k] = x[k]; qr[k] = q[k] }
    }

    // MARK: start

    // Turn a dying creature into a ragdoll. bones: parent first (bone 0 the root, the torso); velocity: the creature's
    // motion; the blow: impulse (momentum in total-mass units: with mass 1 it is the speed change it gives the body as
    // a whole) at hitPoint. The blow acts as if the body were rigid at that instant (a shot from the left throws it
    // right and spins it about its centre of mass), plus hitShare of it on the bone it struck alone. Returns a handle,
    // or -1 when the bones are malformed. A full pool reuses the oldest slot, sleeping ragdolls first.
    @discardableResult
    func start(_ bones: [RagdollBone], velocity: SIMD3<Float>, hitPoint: SIMD3<Float>, impulse: SIMD3<Float>,
               mass: Float = 1) -> Int {
        typealias M = RagdollMath
        let n = bones.count
        guard n >= 1, n <= RagdollWorld.maxBones, bones[0].parent == -1, M.finite(velocity), M.finite(hitPoint),
              M.finite(impulse) else { return -1 }
        for (i, b) in bones.enumerated() {
            guard b.parent >= -1, b.parent < i, M.finite(b.centre), M.finite(b.half), M.finite(b.orientation.vector),
                  M.finite(b.pivot) else { return -1 }
        }
        var s = -1
        for i in 0..<capacity where !used[i] { s = i; break }
        if s < 0 {
            var best = Int.max
            for i in 0..<capacity {
                let age = born[i] - (awake[i] ? 0 : (1 << 40))
                if age < best { best = age; s = i }
            }
        }
        gen[s] += 1; births += 1
        used[s] = true; awake[s] = true; count[s] = n; born[s] = births; still[s] = 0; awakeFor[s] = 0
        let base = s * RagdollWorld.maxBones

        // Masses by box volume, scaled so the body weighs `mass`.
        var vol: Float = 0
        for b in bones {
            let h = pointwiseMax(b.half, SIMD3<Float>(repeating: 0.01))
            vol += 8 * h.x * h.y * h.z * Swift.max(b.density, 0.01)
        }
        let total = Swift.max(mass, 1e-4)
        for (i, b) in bones.enumerated() {
            let k = base + i
            let h = pointwiseMax(b.half, SIMD3<Float>(repeating: 0.01))
            let m = total * 8 * h.x * h.y * h.z * Swift.max(b.density, 0.01) / vol
            let h2 = h * h
            let inertia = SIMD3<Float>(h2.y + h2.z, h2.x + h2.z, h2.x + h2.y) * (m / 3)
            let qn = M.unit4(b.orientation.vector)
            x[k] = b.centre; q[k] = qn; x0[k] = b.centre; q0[k] = qn; xp[k] = b.centre; qp[k] = qn
            xr[k] = b.centre; qr[k] = qn
            v[k] = velocity; w[k] = .zero
            half[k] = h; invM[k] = 1 / m; invI[k] = SIMD3<Float>(repeating: 1) / inertia
            parent[k] = b.parent; planeMask[k] = 0; touchMask[k] = 0
            for c in 0..<8 { lam[k * 8 + c] = 0; anchor[k * 8 + c] = .zero }
            sphere[k] = .zero; sphereHit[k] = .zero; sphereNear[k] = false
            guard b.parent >= 0 else { continue }

            // Joint: pivots in both frames; the child's axis from its box (or the hinge axis); limits.
            let kp = base + b.parent
            anchorP[k] = M.rotInv(q[kp], b.pivot - x[kp])
            anchorC[k] = M.rotInv(qn, b.pivot - b.centre)
            let hang = M.unit(M.rotInv(qn, b.centre - b.pivot), or: SIMD3(0, -1, 0))
            let j = b.joint
            axisC[k] = j.kind == .hinge ? M.unit(j.hingeAxis, or: SIMD3(1, 0, 0)) : M.unit(j.axis, or: hang)
            neutralQ[k] = M.unit4(j.neutral.vector)
            let lo = Swift.max(Swift.min(j.lo, j.hi), -3.1), hi = Swift.min(Swift.max(j.lo, j.hi), 3.1)
            let sw = j.kind == .hinge ? RagdollWorld.hingePlay : Swift.min(Swift.max(j.swing, 0), 3.1)
            cone[k] = SIMD2(cosf(sw * 0.5), sinf(sw * 0.5))
            range[k] = SIMD4(sinf(lo * 0.5), cosf(lo * 0.5), sinf(hi * 0.5), cosf(hi * 0.5))
            // Far-end sphere along the hang direction, kept unless it already touches the root box at death.
            let rad = 0.9 * Swift.min(h.x, Swift.min(h.y, h.z))
            let c = hang * Swift.max(M.dot(M.abs(hang), h) - rad, 0)
            let l = M.rotInv(q[base], M.rot(qn, c) + b.centre - x[base])
            let e = pointwiseMax(M.abs(l) - half[base], .zero)
            if M.dot(e, e) >= rad * rad { sphere[k] = SIMD4(c, rad) }
        }
        kick(s, at: hitPoint, impulse: impulse, local: hitShare)
        // Topple: a body standing on stick legs with flat feet is a table, and a dead one must still fall. Unless the
        // blow already moves it sideways that fast, the top of the root gets the rest: along the blow, or without one
        // to a seeded side. Then limbs start turning a little (slump), so they fold on their own.
        let seed = UInt32(truncatingIfNeeded: s &* 7919 &+ gen[s] &* 104_729)
        let flat = SIMD3<Float>(impulse.x, 0, impulse.z) / total
        let have = M.length(flat)
        if have < topple {
            var side = M.rot(q[base], SIMD3(M.noise(seed &+ 977) < 0 ? -1 : 1, 0, 0))
            side.y = 0
            let dir = have > 0.05 ? flat / have : M.unit(side, or: SIMD3(1, 0, 0))
            let top = x[base] + M.rot(q[base], SIMD3(0, half[base].y, 0))
            kick(s, at: top, impulse: dir * ((topple - have) * total), local: 0)
        }
        for i in 0..<n {
            let j = seed &+ UInt32(i) &* 3
            w[base + i] += SIMD3<Float>(M.noise(j), M.noise(j &+ 1), M.noise(j &+ 2)) * (i == 0 ? slump * 0.5 : slump)
        }
        return (gen[s] << RagdollWorld.slotBits) | s
    }

    // A later blow on a corpse (a second shot, a blast): on the bone it hits alone, and it wakes the body.
    func push(_ id: Int, at point: SIMD3<Float>, impulse: SIMD3<Float>) {
        guard let s = slot(id), RagdollMath.finite(point), RagdollMath.finite(impulse) else { return }
        rouse(s)
        kick(s, at: point, impulse: impulse, local: 1)
    }

    // The blow: the part `local` on the bone nearest p alone, the rest on the body as if it were rigid.
    private func kick(_ s: Int, at p: SIMD3<Float>, impulse j: SIMD3<Float>, local share: Float) {
        typealias M = RagdollMath
        let base = s * RagdollWorld.maxBones, n = count[s]
        var hit = 0, best = Float.infinity          // the bone whose box is nearest the hit point
        for i in 0..<n {
            let k = base + i
            let l = M.rotInv(q[k], p - x[k])
            let e = pointwiseMax(M.abs(l) - half[k], .zero)
            let d = M.dot(e, e) - 1e-3 * M.dot(l, l)    // inside several boxes: the one whose centre is nearest
            if d < best { best = d; hit = i }
        }
        if share < 1 {
            // The whole body as one rigid body at the instant of the hit: centre of mass, inertia about it (each box's
            // own in world axes, plus the parallel-axis term), then every bone's share of the motion.
            let jr = (1 - share) * j
            var m: Float = 0, com = SIMD3<Float>.zero
            for i in 0..<n { let mi = 1 / invM[base + i]; m += mi; com += x[base + i] * mi }
            com /= m
            var c0 = SIMD3<Float>.zero, c1 = SIMD3<Float>.zero, c2 = SIMD3<Float>.zero
            for i in 0..<n {
                let k = base + i
                let mi = 1 / invM[k]
                let t = M.tensor(q[k], SIMD3<Float>(repeating: 1) / invI[k])
                let d = x[k] - com, d2 = M.dot(d, d)
                c0 += t.0 + (SIMD3(d2, 0, 0) - d * d.x) * mi
                c1 += t.1 + (SIMD3(0, d2, 0) - d * d.y) * mi
                c2 += t.2 + (SIMD3(0, 0, d2) - d * d.z) * mi
            }
            let r0 = M.cross(c1, c2), r1 = M.cross(c2, c0), r2 = M.cross(c0, c1)
            let det = M.dot(c0, r0)
            var dw = SIMD3<Float>.zero
            if det > 1e-12 && det.isFinite {
                let l = M.cross(p - com, jr)
                dw = SIMD3(M.dot(r0, l), M.dot(r1, l), M.dot(r2, l)) / det
            }
            let dv = jr / m
            for k in base..<(base + n) {
                v[k] += dv + M.cross(dw, x[k] - com)
                w[k] += dw
            }
        }
        if share <= 0 { return }
        let k = base + hit
        let sp = M.length(j * (share * invM[k]))
        let part = j * (share * (sp > maxKick ? maxKick / sp : 1))
        v[k] += part * invM[k]
        w[k] += M.rot(q[k], invI[k] * M.rotInv(q[k], M.cross(p - x[k], part)))
    }

    // MARK: step

    // The sub-step's constants, copied once per step so the hot loops read locals, not class properties.
    private struct Tune {
        var h: Float = 0, g: Float = 0, out: Float = 0, muS: Float = 0, muD: Float = 0
        var linKeep: Float = 1, angKeep: Float = 1, jointKeep: Float = 0, jointStop: Float = 0
        var vMax: Float = 0, wMax: Float = 0
    }

    // Advance every awake ragdoll by dt (one frame). Sleeping ragdolls cost one flag test.
    func step<G: PhysicsGround>(dt: Float, ground: G) {
        queries = 0
        let dt = Swift.min(Swift.max(dt, 0), 1.0 / 20)
        if !(dt > 0) { return }
        let subs = Swift.max(1, substeps)
        var t = Tune()
        t.h = dt / Float(subs); t.g = gravity * t.h; t.out = depenetration * t.h
        t.muS = staticFriction; t.muD = dynamicFriction
        t.vMax = maxSpeed; t.wMax = maxSpin
        t.linKeep = Swift.max(0, 1 - linearDamping * dt); t.angKeep = Swift.max(0, 1 - angularDamping * dt)
        t.jointKeep = Swift.min(1, jointDamping * dt); t.jointStop = jointFriction * dt
        let drop = contactMargin + 0.5 * gravity * dt * dt
        for s in 0..<capacity where used[s] && awake[s] {
            let base = s * RagdollWorld.maxBones, n = count[s]
            detect(base, n, dt, drop, ground)
            for _ in 0..<subs {
                integrate(base, n, t)
                limits(base, n)
                spheres(base, n, t)
                contacts(base, n, t)
                attach(base, n)
                velocities(base, n, t)
            }
            damp(base, n, t)                    // once a frame: it only bleeds energy, sub-steps don't need it
            settle(s, base, n, dt)
        }
    }

    // Contact planes for the frame, from each corner's predicted end position (dropped by the margin and the frame's
    // own sag, so a corner resting on the ground always has one).
    private func detect<G: PhysicsGround>(_ base: Int, _ n: Int, _ dt: Float, _ drop: Float, _ ground: G) {
        typealias M = RagdollMath
        let down = SIMD3<Float>(0, -drop, 0)
        for k in base..<(base + n) {
            xf[k] = x[k]; qf[k] = q[k]
            let xk = x[k], vk = v[k] * dt, wk = w[k] * dt, ax = M.axes(q[k], half[k])
            var mask: UInt8 = 0
            for c in 0..<8 {
                let r = M.corner(ax, c)
                let at = xk + r + vk + M.cross(wk, r) + down
                if let hit = ground.contact(at) {
                    let nrm = hit.normal
                    plane[k * 8 + c] = SIMD4(nrm, M.dot(nrm, at + nrm * hit.depth))
                    mask |= UInt8(1 << c)
                } else {
                    anchor[k * 8 + c].w = 0                 // off the ground: friction lets go
                }
            }
            planeMask[k] = mask; touchMask[k] = 0
            // Limb end against the root: only tested this frame if it can get there (twice its relative speed).
            let sp = sphere[k]
            if sp.w > 0 {
                let r = M.rot(q[k], M.xyz(sp)), cw = xk + r, x0 = x[base]
                let l = M.rotInv(q[base], cw - x0)
                let e = pointwiseMax(M.abs(l) - half[base], .zero)
                let rel = v[k] + M.cross(w[k], r) - v[base] - M.cross(w[base], cw - x0)
                let reach = sp.w + 0.05 + 2 * dt * M.length(rel)
                sphereNear[k] = M.dot(e, e) < reach * reach
                sphereHit[k].w = 0
            }
        }
        queries += n * 8
    }

    private func integrate(_ base: Int, _ n: Int, _ t: Tune) {
        for k in base..<(base + n) {
            xp[k] = x[k]; qp[k] = q[k]
            var vk = v[k]
            vk.y -= t.g
            v[k] = vk
            x[k] += vk * t.h
            let qk = RagdollMath.turn(q[k], w[k] * t.h)
            q[k] = qk
            (iw0[k], iw1[k], iw2[k]) = RagdollMath.tensor(qk, invI[k])
        }
    }

    // World inverse inertia of bone k times a vector (the tensor is refreshed once a sub-step; the small turns within
    // it barely change it).
    @inline(__always) private func iw(_ k: Int, _ a: SIMD3<Float>) -> SIMD3<Float> {
        iw0[k] * a.x + iw1[k] * a.y + iw2[k] * a.z
    }

    private func limits(_ base: Int, _ n: Int) {
        if n < 2 { return }
        for b in 1..<n where parent[base + b] >= 0 { limitJoint(base + parent[base + b], base + b) }
    }

    // Pivots together (XPBD positional constraint, zero compliance), parents before children.
    private func attach(_ base: Int, _ n: Int) {
        typealias M = RagdollMath
        if n < 2 { return }
        for b in 1..<n where parent[base + b] >= 0 {
            let k = base + b, kp = base + parent[k]
            let ra = M.rot(q[kp], anchorP[k]), rc = M.rot(q[k], anchorC[k])
            let d = x[kp] + ra - x[k] - rc
            let dl = M.length(d)
            if dl > 1e-7 { pairPush(kp, k, ra, rc, d / dl, dl) }
        }
    }

    private func spheres(_ base: Int, _ n: Int, _ t: Tune) {
        if n < 2 { return }
        for b in 1..<n where sphereNear[base + b] { sphereVsRoot(base, base + b, t) }
    }

    // Ground: push each penetrating corner out along its plane, then hold it at its anchor if friction can.
    private func contacts(_ base: Int, _ n: Int, _ t: Tune) {
        typealias M = RagdollMath
        for k in base..<(base + n) {
            var mask = planeMask[k], touch: UInt8 = 0
            if mask == 0 { continue }
            let hk = half[k], im = invM[k], i0 = iw0[k], i1 = iw1[k], i2 = iw2[k], xpk = xp[k]
            let axp = M.axes(qp[k], hk)
            var xk = x[k], qk = q[k], ax = M.axes(qk, hk)
            while mask != 0 {
                let c = mask.trailingZeroBitCount, ci = k * 8 + c
                mask &= mask - 1
                let pl = plane[ci]
                let nrm = M.xyz(pl)
                let r = M.corner(ax, c)
                var pen = pl.w - M.dot(nrm, xk + r)
                if pen <= 0 {
                    if pen < -0.002 { anchor[ci].w = 0 }      // lifted off: let go of the anchor
                    continue
                }
                // All of this sub-step's motion into the ground is undone, older penetration leaves at the
                // depenetration speed: a body that died half inside a block isn't fired out of it, and a joint that
                // pressed a corner in (a hip end under a landing torso) gives it back gently, without a rebound.
                let was = xpk + M.corner(axp, c)
                pen = Swift.min(pen, Swift.max(M.dot(nrm, was - xk - r), 0) + t.out)
                let rn = M.cross(r, nrm)
                let irn = i0 * rn.x + i1 * rn.y + i2 * rn.z
                let ln = pen / (im + M.dot(rn, irn))
                xk += nrm * (ln * im)
                qk = M.turn(qk, irn * ln)
                ax = M.axes(qk, hk)
                lam[ci] = ln; touch |= UInt8(1 << c)
                // Static friction: back to the anchor (or to where the corner was), if the normal push can carry it.
                let r2 = M.corner(ax, c)
                let now = xk + r2
                let a = anchor[ci]
                let hold = a.w > 0 ? M.xyz(a) : was
                var slip = now - hold
                slip -= nrm * M.dot(slip, nrm)
                let s2 = M.dot(slip, slip)
                if s2 > 1e-14 {
                    let sl = s2.squareRoot()
                    let tg = slip / sl
                    let rt = M.cross(r2, tg)
                    let irt = i0 * rt.x + i1 * rt.y + i2 * rt.z
                    let lt = sl / (im + M.dot(rt, irt))
                    if lt < t.muS * ln {
                        xk -= tg * (lt * im)
                        qk = M.turn(qk, irt * -lt)
                        ax = M.axes(qk, hk)
                        anchor[ci] = SIMD4(hold, 1)
                    } else {
                        anchor[ci] = SIMD4(now, 1)                // sliding: try to hold it here next time
                    }
                } else {
                    anchor[ci] = SIMD4(hold, 1)
                }
            }
            x[k] = xk; q[k] = qk; touchMask[k] = touch
        }
    }

    // Velocities from the moves, then the velocity pass: contacts lose their approach (no bounce) and the push-out
    // speed, sliding corners and limb ends get Coulomb friction.
    private func velocities(_ base: Int, _ n: Int, _ t: Tune) {
        typealias M = RagdollMath
        let inv = 1 / t.h
        for k in base..<(base + n) {
            v[k] = (x[k] - xp[k]) * inv
            let dq = M.mul(q[k], M.conj(qp[k]))
            let wk = M.xyz(dq) * (2 * inv)
            w[k] = dq.w < 0 ? -wk : wk
        }
        for k in base..<(base + n) {
            var mask = touchMask[k]
            if mask == 0 { continue }
            let im = invM[k], i0 = iw0[k], i1 = iw1[k], i2 = iw2[k], ax = M.axes(q[k], half[k])
            var vk = v[k], wk = w[k]
            while mask != 0 {
                let c = mask.trailingZeroBitCount, ci = k * 8 + c
                mask &= mask - 1
                let ln = lam[ci]
                let nrm = M.xyz(plane[ci])
                let r = M.corner(ax, c)
                let vn = M.dot(nrm, vk + M.cross(wk, r))
                let rn = M.cross(r, nrm)
                let irn = i0 * rn.x + i1 * rn.y + i2 * rn.z
                let wn = im + M.dot(rn, irn)
                let jn = (vn < 0 ? -vn : -Swift.min(vn, ln * wn * inv)) / wn
                vk += nrm * (jn * im)
                wk += irn * jn
                let vc = vk + M.cross(wk, r)
                let vt = vc - nrm * M.dot(nrm, vc)
                let vtl = M.length(vt)
                if vtl > 1e-6 {
                    let tg = vt / vtl
                    let rt = M.cross(r, tg)
                    let irt = i0 * rt.x + i1 * rt.y + i2 * rt.z
                    let jt = Swift.min(vtl / (im + M.dot(rt, irt)), t.muD * ln * inv)
                    vk -= tg * (jt * im)
                    wk -= irt * jt
                }
            }
            v[k] = vk; w[k] = wk
        }
        if n > 1 {
            for b in 1..<n where sphereNear[base + b] && sphereHit[base + b].w > 0 {
                sphereVelocity(base, base + b, t)
            }
        }
    }

    // Air and flesh damping, limp-muscle damping and friction across joints, safety clamps.
    private func damp(_ base: Int, _ n: Int, _ t: Tune) {
        typealias M = RagdollMath
        for k in base..<(base + n) {
            var vk = v[k] * t.linKeep, wk = w[k] * t.angKeep
            let sv = M.dot(vk, vk), sw = M.dot(wk, wk)
            if sv > t.vMax * t.vMax { vk *= t.vMax / sv.squareRoot() }
            if sw > t.wMax * t.wMax { wk *= t.wMax / sw.squareRoot() }
            v[k] = vk; w[k] = wk
        }
        if n < 2 { return }
        for b in 1..<n where parent[base + b] >= 0 {
            let k = base + b, kp = base + parent[k]
            let dw = w[k] - w[kp]
            let m2 = M.dot(dw, dw)
            if m2 < 1e-10 { continue }
            let m = m2.squareRoot()
            let nn = dw / m
            let ip = iw(kp, nn), ic = iw(k, nn)
            let j = Swift.min(m, m * t.jointKeep + t.jointStop) / (M.dot(nn, ip) + M.dot(nn, ic))
            w[k] -= ic * j
            w[kp] += ip * j
        }
    }

    // Sleep once no point of any bone has strayed more than the tolerance from where it was sleepDelay ago. Past 3 s
    // awake the tolerance widens (to 4x at 6 s), so a slow creep (an arm sliding off the torso at a centimetre a
    // second, a limb balanced on its end) can't keep a body up for good. Also recovers from a non-finite pose (never
    // seen in tests; a bad ground answer could cause one).
    private func settle(_ s: Int, _ base: Int, _ n: Int, _ dt: Float) {
        typealias M = RagdollMath
        awakeFor[s] += dt
        let tol = restTolerance * Swift.min(4, Swift.max(1, awakeFor[s] - 2))
        var moved = false
        for k in base..<(base + n) {
            if !M.finite(x[k]) || !M.finite(q[k]) || !M.finite(v[k]) || !M.finite(w[k]) {
                recoveries += 1
                for j in base..<(base + n) { x[j] = xf[j]; q[j] = qf[j]; v[j] = .zero; w[j] = .zero }
                awake[s] = false
                return
            }
            let turn = 2 * M.length(M.xyz(M.mul(q[k], M.conj(qr[k]))))   // ~ angle turned, radians
            if M.length(x[k] - xr[k]) + turn * M.length(half[k]) > tol { moved = true; break }
        }
        if moved {
            still[s] = 0
            for k in base..<(base + n) { xr[k] = x[k]; qr[k] = q[k] }
            return
        }
        still[s] += dt
        if still[s] >= sleepDelay {
            awake[s] = false
            for k in base..<(base + n) { v[k] = .zero; w[k] = .zero }
        }
    }

    // MARK: constraints

    // Move body c's point (offset rc) by +n and body a's point (offset ra) by -n, dist in all, shared by their
    // generalised inverse masses. Returns the multiplier.
    @inline(__always) @discardableResult
    private func pairPush(_ a: Int, _ c: Int, _ ra: SIMD3<Float>, _ rc: SIMD3<Float>, _ n: SIMD3<Float>,
                          _ dist: Float) -> Float {
        typealias M = RagdollMath
        let rna = M.cross(ra, n), rnc = M.cross(rc, n)
        let ia = iw(a, rna), ic = iw(c, rnc)
        let ma = invM[a], mc = invM[c]
        let l = dist / (ma + M.dot(rna, ia) + mc + M.dot(rnc, ic))
        x[c] += n * (l * mc)
        q[c] = M.turn(q[c], ic * l)
        x[a] -= n * (l * ma)
        q[a] = M.turn(q[a], ia * -l)
        return l
    }

    // Turn the child by the world rotation vector corr relative to its parent, shared by their angular inverse masses.
    @inline(__always) private func pairTurn(_ a: Int, _ c: Int, _ corr: SIMD3<Float>) {
        typealias M = RagdollMath
        let th = M.length(corr)
        if th < 1e-7 { return }
        let n = corr / th
        let ia = iw(a, n), ic = iw(c, n)
        let l = th / (M.dot(n, ia) + M.dot(n, ic))
        q[c] = M.turn(q[c], ic * l)
        q[a] = M.turn(q[a], ia * -l)
    }

    // Joint limits as one correction: the swing clamped to the cone keeping its direction (a hinge's cone is a hair
    // wide), the twist or bend clamped to its range, then the child turned onto that clamped rotation. Separate swing
    // and twist projections fight each other at the rim and walk a resting limb round it; this can't.
    private func limitJoint(_ kp: Int, _ k: Int) {
        typealias M = RagdollMath
        let c = cone[k], r = range[k], a = axisC[k]
        let nq = neutralQ[k]
        let frame = nq.w == 1 ? q[kp] : M.mul(q[kp], nq)
        var rel = M.mul(M.conj(frame), q[k])
        if rel.w < 0 { rel = -rel }
        // rel = swing * twist with twist = (a s, w) / l: the swing's w is l, and the twist's half-angle sine and
        // cosine are s / l and w / l, so the in-range test (the common case) needs no quaternion products.
        let s = M.dot(M.xyz(rel), a), l = (s * s + rel.w * rel.w).squareRoot()
        let wide = l < c.x, low = s * r.y - rel.w * r.x < 0, high = s * r.w - rel.w * r.z > 0
        if !(wide || low || high) || l < 1e-9 { return }
        var tw = SIMD4<Float>(a * (s / l), rel.w / l)
        var sw = M.mul(rel, M.conj(tw))
        if wide {
            let xyz = M.xyz(sw)
            let sl = M.length(xyz)
            if sl > 1e-9 { sw = SIMD4(xyz * (c.y / sl), c.x) }
        }
        if low { tw = SIMD4(a * r.x, r.y) } else if high { tw = SIMD4(a * r.z, r.w) }
        var d = M.mul(M.mul(sw, tw), M.conj(rel))            // from now onto the target, in the parent's frame
        if d.w < 0 { d = -d }
        let dv = M.xyz(d)
        let dl = M.length(dv)
        if dl < 1e-7 { return }
        pairTurn(kp, k, M.rot(frame, dv * (2 * atan2f(dl, d.w) / dl)))
    }

    // A limb's far-end sphere out of the root's box; both move, by their inverse masses.
    private func sphereVsRoot(_ k0: Int, _ k: Int, _ t: Tune) {
        typealias M = RagdollMath
        sphereHit[k].w = 0
        let sp = sphere[k]
        let r = sp.w, lc = M.xyz(sp)
        let cw = x[k] + M.rot(q[k], lc)
        let q0 = q[k0], hh = half[k0]
        let cl = M.rotInv(q0, cw - x[k0])
        let near = M.clamp(cl, hh)
        let diff = cl - near
        let d2 = M.dot(diff, diff)
        if d2 >= r * r { return }
        var nl: SIMD3<Float>, pen: Float
        if d2 > 1e-12 {
            let d = d2.squareRoot()
            nl = diff / d; pen = r - d
        } else {                                    // centre inside the box: out through the nearest face
            let gap = hh - M.abs(cl)
            var a = 0
            if gap.y < gap[a] { a = 1 }
            if gap.z < gap[a] { a = 2 }
            nl = .zero; nl[a] = cl[a] < 0 ? -1 : 1
            pen = r + gap[a]
        }
        // Depenetration capped as for the ground (relative to the torso: undo this sub-step's approach only).
        let was = M.rotInv(qp[k0], xp[k] + M.rot(qp[k], lc) - xp[k0])
        pen = Swift.min(pen, Swift.max(M.dot(nl, was - cl), 0) + t.out)
        let n = M.rot(q0, nl)
        let ln = pairPush(k0, k, M.rot(q0, near), cw - n * r - x[k], n, pen)
        sphereHit[k] = SIMD4(n, ln)
    }

    // Velocity pass for a limb end touching the torso: no bounce, and Coulomb friction on the relative sliding, so a
    // body lying on its own arm doesn't slide off it. Velocity-level only: it can take energy out, never put it in
    // (a positional hold here closes a loop with the shoulder joint that one Gauss-Seidel pass can pump).
    private func sphereVelocity(_ k0: Int, _ k: Int, _ t: Tune) {
        typealias M = RagdollMath
        let hit = sphereHit[k]
        let n = M.xyz(hit)
        let touch = x[k] + M.rot(q[k], M.xyz(sphere[k])) - n * sphere[k].w
        let ra = touch - x[k0], rc = touch - x[k]
        let rel = (v[k] + M.cross(w[k], rc)) - (v[k0] + M.cross(w[k0], ra))
        let vn = M.dot(rel, n)
        let wn = pairWeight(k0, k, ra, rc, n)
        pairImpulse(k0, k, ra, rc, n, (vn < 0 ? -vn : -Swift.min(vn, hit.w * wn / t.h)) / wn)
        let rel2 = (v[k] + M.cross(w[k], rc)) - (v[k0] + M.cross(w[k0], ra))
        let vt = rel2 - n * M.dot(rel2, n)
        let vtl = M.length(vt)
        if vtl < 1e-6 { return }
        let tg = vt / vtl
        let wt = pairWeight(k0, k, ra, rc, tg)
        pairImpulse(k0, k, ra, rc, tg, -Swift.min(vtl / wt, t.muD * hit.w / t.h))
    }

    @inline(__always) private func pairWeight(_ a: Int, _ c: Int, _ ra: SIMD3<Float>, _ rc: SIMD3<Float>,
                                              _ n: SIMD3<Float>) -> Float {
        let rna = RagdollMath.cross(ra, n), rnc = RagdollMath.cross(rc, n)
        return invM[a] + RagdollMath.dot(rna, iw(a, rna)) + invM[c] + RagdollMath.dot(rnc, iw(c, rnc))
    }
    // Impulse j along n on body c's point (offset rc), and -j on body a's point (offset ra).
    @inline(__always) private func pairImpulse(_ a: Int, _ c: Int, _ ra: SIMD3<Float>, _ rc: SIMD3<Float>,
                                               _ n: SIMD3<Float>, _ j: Float) {
        let p = n * j
        v[c] += p * invM[c]
        w[c] += iw(c, RagdollMath.cross(rc, p))
        v[a] -= p * invM[a]
        w[a] -= iw(a, RagdollMath.cross(ra, p))
    }

    // MARK: read-out

    // World pose of a bone's box: a vertex v in the box frame is at position + orientation.act(v).
    func pose(_ id: Int, _ bone: Int) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        guard let s = slot(id), bone >= 0, bone < count[s] else { return (.zero, RagdollWorld.identity) }
        let k = s * RagdollWorld.maxBones + bone
        return (x[k], simd_quatf(vector: q[k]))
    }

    // Motion since death: a point p of the bone, in world space at death, is now at rotation.act(p) + translation.
    func delta(_ id: Int, _ bone: Int) -> (rotation: simd_quatf, translation: SIMD3<Float>) {
        guard let s = slot(id), bone >= 0, bone < count[s] else { return (RagdollWorld.identity, .zero) }
        let k = s * RagdollWorld.maxBones + bone
        let dq = RagdollMath.mul(q[k], RagdollMath.conj(q0[k]))
        return (simd_quatf(vector: dq), x[k] - RagdollMath.rot(dq, x0[k]))
    }

    // The same as a matrix (column-major, last column the translation): death-time world space -> now.
    func deltaMatrix(_ id: Int, _ bone: Int) -> simd_float4x4 {
        let d = delta(id, bone)
        let dq = d.rotation.vector
        let c0 = RagdollMath.rot(dq, SIMD3(1, 0, 0)), c1 = RagdollMath.rot(dq, SIMD3(0, 1, 0))
        let c2 = RagdollMath.rot(dq, SIMD3(0, 0, 1))
        return simd_float4x4(columns: (SIMD4(c0, 0), SIMD4(c1, 0), SIMD4(c2, 0), SIMD4(d.translation, 1)))
    }

    // Every bone's delta as three rows of a 3x4 matrix (row-major, for a uniform buffer): rows[3 * bone + i].
    // Returns the bone count written (0 for a stale handle). No allocation.
    @discardableResult
    func writeDeltas(_ id: Int, _ rows: UnsafeMutablePointer<SIMD4<Float>>) -> Int {
        guard let s = slot(id) else { return 0 }
        let base = s * RagdollWorld.maxBones
        for b in 0..<count[s] {
            let k = base + b
            let dq = RagdollMath.mul(q[k], RagdollMath.conj(q0[k]))
            let c0 = RagdollMath.rot(dq, SIMD3(1, 0, 0)), c1 = RagdollMath.rot(dq, SIMD3(0, 1, 0))
            let c2 = RagdollMath.rot(dq, SIMD3(0, 0, 1))
            let t = x[k] - RagdollMath.rot(dq, x0[k])
            rows[3 * b] = SIMD4(c0.x, c1.x, c2.x, t.x)
            rows[3 * b + 1] = SIMD4(c0.y, c1.y, c2.y, t.y)
            rows[3 * b + 2] = SIMD4(c0.z, c1.z, c2.z, t.z)
        }
        return count[s]
    }

    // MARK: diagnostics

    // World corner i (0...7) of a bone's box (bit 0 +x, bit 1 +y, bit 2 +z).
    func corner(_ id: Int, _ bone: Int, _ i: Int) -> SIMD3<Float> {
        guard let s = slot(id), bone >= 0, bone < count[s] else { return .zero }
        let k = s * RagdollWorld.maxBones + bone
        return x[k] + RagdollMath.corner(RagdollMath.axes(q[k], half[k]), i & 7)
    }
    // The widest pivot gap over the ragdoll's joints, blocks.
    func jointGap(_ id: Int) -> Float {
        guard let s = slot(id) else { return 0 }
        let base = s * RagdollWorld.maxBones
        var worst: Float = 0
        for b in 0..<count[s] where parent[base + b] >= 0 {
            let k = base + b, kp = base + parent[k]
            let d = x[kp] + RagdollMath.rot(q[kp], anchorP[k]) - x[k] - RagdollMath.rot(q[k], anchorC[k])
            worst = Swift.max(worst, RagdollMath.length(d))
        }
        return worst
    }
    // Speed of the fastest point of any bone (estimate: centre speed plus spin times the box's half diagonal).
    func motion(_ id: Int) -> Float {
        guard let s = slot(id) else { return 0 }
        let base = s * RagdollWorld.maxBones
        var top: Float = 0
        for k in base..<(base + count[s]) {
            top = Swift.max(top, RagdollMath.length(v[k]) + RagdollMath.length(w[k]) * RagdollMath.length(half[k]))
        }
        return top
    }
    // A bone's linear and angular velocity (zero while asleep).
    func velocity(_ id: Int, _ bone: Int) -> (linear: SIMD3<Float>, angular: SIMD3<Float>) {
        guard let s = slot(id), bone >= 0, bone < count[s] else { return (.zero, .zero) }
        let k = s * RagdollWorld.maxBones + bone
        return (v[k], w[k])
    }
    // A joint's angles from neutral, radians: ball (swing, twist); hinge (bend, off-axis swing).
    func jointAngles(_ id: Int, _ bone: Int) -> SIMD2<Float> {
        guard let s = slot(id), bone > 0, bone < count[s] else { return .zero }
        let base = s * RagdollWorld.maxBones, k = base + bone
        if parent[k] < 0 { return .zero }
        typealias M = RagdollMath
        // rel = P^-1 * child = swing * twist, P the parent's neutral frame, as in limitJoint.
        var rel = M.mul(M.conj(M.mul(q[base + parent[k]], neutralQ[k])), q[k])
        if rel.w < 0 { rel = -rel }
        let ts = M.dot(M.xyz(rel), axisC[k]), l = (ts * ts + rel.w * rel.w).squareRoot()
        let swing = 2 * atan2f((Swift.max(0, 1 - l * l)).squareRoot(), l), twist = 2 * atan2f(ts, rel.w)
        return cone[k].y < 0.05 ? SIMD2(twist, swing) : SIMD2(swing, twist)
    }
}
