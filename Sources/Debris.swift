import Foundation
import simd

// Realistic world, layer 3 (docs/design/realistic-world.md 3.2): debris rigid bodies. Fracture pieces (convex hulls
// round their centroid) fly, tumble, land on the drawn surface (PhysicsGround), stack on each other, sleep and fade.
// Every body lives in a fixed slot of flat buffers allocated once, so a frame never allocates. Budget: 160 live pieces
// on the Quest (the oldest/most settled fade first), 24 new a frame, about 0.5 ms a frame.
//
// Solver: 120 Hz fixed sub-steps (at most 3 a frame, drawn interpolated); one ground query per hull vertex at its
// predicted position (a speculative contact: a piece may close a gap but not pass the surface); vertex-in-hull contacts
// between pieces; sequential impulses with Coulomb friction; split-impulse push-out (leaving the ground adds no bounce);
// ground contacts warm-started by hull vertex. A per-vertex step limit keeps pieces from crossing a 1-block wall.
//
// Inside, every vector is a SIMD4<Float> with w = 0: SIMD3<Float> arithmetic compiles to split 2+1-lane code on both
// arm64 and x86 (about 3x the instructions); SIMD3 only appears at the API.

// 3x3 matrix as three columns (w = 0): the same code on Apple simd and the Linux shim, cheap to inline in the solver.
struct DebrisMat3 {
    var c0: SIMD4<Float>, c1: SIMD4<Float>, c2: SIMD4<Float>
    static let zero = DebrisMat3(c0: .zero, c1: .zero, c2: .zero)
    @inline(__always) func mul(_ v: SIMD4<Float>) -> SIMD4<Float> {
        let a = c0 * v.x, b = c1 * v.y, c = c2 * v.z
        return a + b + c
    }
    // Transpose times v: world -> body for a rotation.
    @inline(__always) func tmul(_ v: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(DebrisMath.dot(c0, v), DebrisMath.dot(c1, v), DebrisMath.dot(c2, v), 0)
    }
}

enum DebrisMath {
    @inline(__always) static func dot(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let m = a * b
        return m.x + m.y + m.z
    }
    // Lane shuffles only (w stays 0): a x b = (a * b.yzx - a.yzx * b).yzx
    @inline(__always) static func cross(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
        let ay = SIMD4<Float>(a.y, a.z, a.x, a.w), by = SIMD4<Float>(b.y, b.z, b.x, b.w)
        let c = a * by - ay * b
        return SIMD4<Float>(c.y, c.z, c.x, c.w)
    }
    @inline(__always) static func len2(_ a: SIMD4<Float>) -> Float { dot(a, a) }
    @inline(__always) static func v4(_ a: SIMD3<Float>) -> SIMD4<Float> { SIMD4(a.x, a.y, a.z, 0) }
    @inline(__always) static func v3(_ a: SIMD4<Float>) -> SIMD3<Float> { SIMD3(a.x, a.y, a.z) }
    @inline(__always) static func finite(_ a: SIMD4<Float>) -> Bool { a.x.isFinite && a.y.isFinite && a.z.isFinite }
    @inline(__always) static func finite(_ a: SIMD3<Float>) -> Bool { a.x.isFinite && a.y.isFinite && a.z.isFinite }

    static func matrix(_ q: simd_quatf) -> DebrisMat3 {
        let v = q.vector
        let x = v.x, y = v.y, z = v.z, w = v.w
        let xx = x * x, yy = y * y, zz = z * z
        let xy = x * y, xz = x * z, yz = y * z
        let wx = w * x, wy = w * y, wz = w * z
        let c0 = SIMD4<Float>(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0)
        let c1 = SIMD4<Float>(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0)
        let c2 = SIMD4<Float>(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0)
        return DebrisMat3(c0: c0, c1: c1, c2: c2)
    }
    // R M R^T: a body-frame tensor in world axes.
    @inline(__always) static func sandwich(_ r: DebrisMat3, _ m: DebrisMat3) -> DebrisMat3 {
        let a = DebrisMat3(c0: r.mul(m.c0), c1: r.mul(m.c1), c2: r.mul(m.c2))
        let row0 = SIMD4<Float>(r.c0.x, r.c1.x, r.c2.x, 0)
        let row1 = SIMD4<Float>(r.c0.y, r.c1.y, r.c2.y, 0)
        let row2 = SIMD4<Float>(r.c0.z, r.c1.z, r.c2.z, 0)
        return DebrisMat3(c0: a.mul(row0), c1: a.mul(row1), c2: a.mul(row2))
    }
    static func inverse(_ m: DebrisMat3) -> DebrisMat3? {
        let r0 = cross(m.c1, m.c2), r1 = cross(m.c2, m.c0), r2 = cross(m.c0, m.c1)
        let det = dot(m.c0, r0)
        guard det.isFinite, det > 0 else { return nil }
        let k = 1 / det
        let a = r0 * k, b = r1 * k, c = r2 * k
        let out = DebrisMat3(c0: SIMD4(a.x, b.x, c.x, 0), c1: SIMD4(a.y, b.y, c.y, 0), c2: SIMD4(a.z, b.z, c.z, 0))
        return finite(out.c0) && finite(out.c1) && finite(out.c2) ? out : nil
    }
    // q advanced by angular velocity w over h: q + (h/2) (w, 0) q, renormalised.
    @inline(__always) static func integrate(_ q: simd_quatf, _ w: SIMD4<Float>, _ h: Float) -> simd_quatf {
        let qv = q.vector
        let hw = w * (0.5 * h)
        var n = qv + hw * qv.w + cross(hw, qv)
        n.w = qv.w - dot(hw, qv)
        let l2 = n.x * n.x + n.y * n.y + n.z * n.z + n.w * n.w
        return simd_quatf(vector: n * (1 / l2.squareRoot()))
    }
    @inline(__always) static func nlerp(_ a: simd_quatf, _ b: simd_quatf, _ t: Float) -> simd_quatf {
        let av = a.vector
        var bv = b.vector
        let d = av.x * bv.x + av.y * bv.y + av.z * bv.z + av.w * bv.w
        if d < 0 { bv = -bv }
        let m = av + (bv - av) * t
        let l2 = m.x * m.x + m.y * m.y + m.z * m.z + m.w * m.w
        return simd_quatf(vector: m * (1 / l2.squareRoot()))
    }
    @inline(__always) static func perpendicular(_ n: SIMD4<Float>) -> SIMD4<Float> {
        let a: SIMD4<Float> = abs(n.x) < 0.57 ? SIMD4(1, 0, 0, 0) : SIMD4(0, 1, 0, 0)
        let c = cross(n, a)
        return c * (1 / len2(c).squareRoot())
    }

    // Face planes (n, d), n.v <= d inside, of the convex hull of v (round the origin, which must be inside). Brute force
    // over vertex triples with early rejection: n <= 24, and it has no degenerate cases to get wrong. Each face keeps a
    // bitmask of the vertices on it, so the many triples of a polygon face (fracture faces are polygons) are skipped
    // after the first, and a face comes out once. No square root until a face is accepted. masks: maxOut scratch words.
    // Returns the count; 0 means flat or not round the origin.
    static func hullPlanes(_ v: UnsafePointer<SIMD4<Float>>, _ n: Int, _ out: UnsafeMutablePointer<SIMD4<Float>>,
                           _ maxOut: Int, masks: UnsafeMutablePointer<UInt32>, scale: Float) -> Int {
        if n < 4 || n > 32 { return 0 }
        let tol: Float = 1e-5 + 1e-3 * scale
        let minL2: Float = 1e-12 * scale * scale * scale * scale + 1e-24
        var count = 0
        for i in 0..<(n - 2) {
            let a = v[i]
            for j in (i + 1)..<(n - 1) {
                let ab = v[j] - a
                let ij = (UInt32(1) << UInt32(i)) | (UInt32(1) << UInt32(j))
                var cover: UInt32 = 0                          // vertices on a known face through i and j
                for m in 0..<count where masks[m] & ij == ij { cover |= masks[m] }
                for k in (j + 1)..<n {
                    if cover & (UInt32(1) << UInt32(k)) != 0 { continue }
                    var nrm = cross(ab, v[k] - a)
                    let l2 = len2(nrm)
                    if l2 < minL2 { continue }
                    var d = dot(nrm, a)
                    if d < 0 { nrm = -nrm; d = -d }
                    let t2 = tol * tol * l2                    // tolerance squared, in unnormalised units
                    if d * d <= t2 { continue }
                    var face = true
                    var on: UInt32 = 0
                    for m in 0..<n {
                        let e = dot(nrm, v[m]) - d
                        if e * e <= t2 { on |= UInt32(1) << UInt32(m) } else if e > 0 { face = false; break }
                    }
                    if !face { continue }
                    let il = 1 / l2.squareRoot()
                    out[count] = SIMD4<Float>(nrm.x * il, nrm.y * il, nrm.z * il, d * il)
                    masks[count] = on
                    cover |= on
                    count += 1
                    if count == maxOut { return count }
                }
            }
        }
        return count
    }
}

// Optional fast path a ground can also adopt: "is this ball certainly clear of solid?", answered far more cheaply than
// its per-point contact (say, the few blocks the ball overlaps are all air). A piece whose swept ball is clear skips all
// of its vertex queries that sub-step, so flying debris costs no ground queries. Answering false is always safe.
protocol DebrisFreeSpace {
    func isFree(_ centre: SIMD3<Float>, radius: Float) -> Bool
}

// Owns the flat buffers: allocated once, freed with the world.
final class DebrisArena {
    private var frees: [() -> Void] = []
    func make<T>(_ n: Int, _ value: T) -> UnsafeMutablePointer<T> {
        let c = max(n, 1)
        let p = UnsafeMutablePointer<T>.allocate(capacity: c)
        p.initialize(repeating: value, count: c)
        frees.append { p.deinitialize(count: c); p.deallocate() }
        return p
    }
    deinit { for f in frees { f() } }
}

final class DebrisWorld {
    struct Config {
        var capacity = 160              // pieces that may be live (not fading) at once
        var spare = 24                  // extra slots so pieces pushed out by the budget fade instead of popping
        var maxNewPerFrame = 24         // adds accepted between two step() calls; extras are dropped
        var substep: Float = 1.0 / 120
        var maxSubsteps = 3             // a long frame runs slow rather than spiralling
        var iterations = 4              // at most (6-8 for taller stacks, ~10% more time each); early out below tolerance
        var minIterations = 2
        var tolerance: Float = 2e-3     // blocks/s
        var gravity: Float = 28
        var friction: Float = 0.6
        var restitution: Float = 0.2
        var bounceSpeed: Float = 2      // slower impacts do not bounce (no endless chatter)
        var slop: Float = 0.005         // allowed overlap: keeps resting vertices in contact
        var correction: Float = 0.3     // share of the overlap pushed out per sub-step (split impulse)
        var maxCorrectionSpeed: Float = 3
        var maxVertexStep: Float = 0.35 // no hull vertex moves further per sub-step, so a 1-block wall is never crossed
        var linearDamping: Float = 0.02
        var angularDamping: Float = 0.1
        var contactAngularDamping: Float = 1.5 // rolling resistance while touching: polyhedra stop rocking
        var sleepLinear: Float = 0.12
        var sleepAngular: Float = 0.35
        var sleepDelay: Float = 0.5     // that still for this long -> asleep (costs nothing)
        var wakeSpeed: Float = 1.5      // a piece hitting a sleeper faster than this wakes it (slower: the sleeper is a rock)
        var settleTime: Float = 8       // asleep this long -> fade
        var maxAge: Float = 20          // alive this long -> fade
        var maxAirTime: Float = 6       // touched nothing for this long (fell out of the world) -> fade
        var fadeTime: Float = 1
        var minY: Float = -1e6          // below this -> fade
        var maxFixedContacts = 3072     // body vs ground / sleeper, per sub-step
        var maxPairContacts = 1024      // body vs body, per sub-step
        var maxPairs = 768              // narrow-phase pairs per sub-step
        var maxContactsPerPair = 8
        var minVolume: Float = 1.0 / 4096 // mass floor (a 1/16-block cube) keeps mass ratios sane
        init() {}
    }

    struct Stats {
        var live = 0, awake = 0, substeps = 0
        var fixedContacts = 0, pairContacts = 0, pairs = 0   // summed over the last step's sub-steps
        var groundQueries = 0                                // PhysicsGround.contact calls, same
        var iterations = 0                                   // solver iterations, summed over the last step's sub-steps
        var dropped = 0, replaced = 0, killed = 0            // totals: adds over the quota, budget evictions, bad/NaN
    }

    static let maxVerts = 24
    static let maxPlanes = 32

    let config: Config
    let slotCount: Int
    private(set) var stats = Stats()

    private typealias F4 = SIMD4<Float>
    private static let fLive: UInt8 = 1, fAwake: UInt8 = 2, fFading: UInt8 = 4, fTouch: UInt8 = 8, fWake: UInt8 = 16,
                       fClear: UInt8 = 32

    // A contact's three rows (normal, tangent 1, tangent 2) are stored by component: lx = (n.x, t1.x, t2.x) and
    // ax = ((r x n).x, (r x t1).x, (r x t2).x)..., so the three relative velocities come out of six vector multiply-adds
    // (vr = lx v.x + ly v.y + lz v.z + ax w.x + ay w.y + az w.z) instead of six dot products. Normal and friction are
    // solved together from that one read; the iterations converge the coupling.

    // A contact of a body with something that does not move this sub-step (the ground, a sleeping piece).
    private struct FixedHit {
        var lx = F4(), ly = F4(), lz = F4()
        var ax = F4(), ay = F4(), az = F4()
        var n = F4(), t1 = F4(), t2 = F4()             // linear response per row
        var an = F4(), at1 = F4(), at2 = F4()          // angular response: invI (r x row)
        var m = F4()                                   // 1 / effective mass per row
        var j = F4()                                   // accumulated impulse per row
        var bias: Float = 0, pbias: Float = 0, jp: Float = 0
        var body: Int32 = 0, key: Int32 = -1
    }
    // A contact between two awake bodies; n points from b to a.
    private struct PairHit {
        var lx = F4(), ly = F4(), lz = F4()
        var axa = F4(), aya = F4(), aza = F4()
        var axb = F4(), ayb = F4(), azb = F4()
        var n = F4(), t1 = F4(), t2 = F4()
        var ana = F4(), at1a = F4(), at2a = F4()
        var anb = F4(), at1b = F4(), at2b = F4()
        var m = F4(), j = F4()
        var bias: Float = 0, pbias: Float = 0, jp: Float = 0
        var a: Int32 = 0, b: Int32 = 0
    }

    private let arena: DebrisArena
    // Per slot.
    private let pos, vel, ang, prevPos, pseudoV, pseudoW: UnsafeMutablePointer<SIMD4<Float>>
    private let drawPos: UnsafeMutablePointer<SIMD3<Float>>
    private let rot, prevRot, drawRot: UnsafeMutablePointer<simd_quatf>
    private let rotM, invIBody, invIWorld: UnsafeMutablePointer<DebrisMat3>
    private let invMass, radius, age, restTimer, sleptFor, airTime, fadeP, fadeRate: UnsafeMutablePointer<Float>
    private let tagP, serialP: UnsafeMutablePointer<UInt32>
    private let vertN, planeN: UnsafeMutablePointer<Int32>
    private let flags: UnsafeMutablePointer<UInt8>
    // Per slot x maxVerts (local hull, world hull, ground warm-start impulse) and slot x maxPlanes.
    private let localV, worldV, warm: UnsafeMutablePointer<SIMD4<Float>>
    private let planes: UnsafeMutablePointer<SIMD4<Float>>
    // Lists.
    private let liveList, livePos, freeList, awakeList: UnsafeMutablePointer<Int32>
    private var liveN = 0, freeN = 0, awakeN = 0, nonFading = 0, wakeRequests = 0
    // Broad phase: live slots sorted along one axis, kept from sub-step to sub-step.
    private let sapList: UnsafeMutablePointer<Int32>
    private let sapKey: UnsafeMutablePointer<Float>
    private let inSap: UnsafeMutablePointer<UInt8>
    private var sapN = 0, sapAxis = 0
    // Contacts.
    private let fixed: UnsafeMutablePointer<FixedHit>
    private let pairHits: UnsafeMutablePointer<PairHit>
    private var fixedN = 0, pairHitN = 0, pairN = 0
    // Scratch for add().
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchCap = 1024
    private let faceMasks: UnsafeMutablePointer<UInt32>

    private var accumulator: Float = 0
    private var addsThisFrame = 0
    private var serialCounter: UInt32 = 0

    init(config: Config = Config()) {
        self.config = config
        let S = max(1, config.capacity + max(0, config.spare))
        slotCount = S
        let a = DebrisArena()
        let MV = DebrisWorld.maxVerts, MP = DebrisWorld.maxPlanes
        pos = a.make(S, F4()); vel = a.make(S, F4()); ang = a.make(S, F4())
        prevPos = a.make(S, F4()); pseudoV = a.make(S, F4()); pseudoW = a.make(S, F4())
        drawPos = a.make(S, SIMD3<Float>())
        let q0 = simd_quatf(vector: F4(0, 0, 0, 1))
        rot = a.make(S, q0); prevRot = a.make(S, q0); drawRot = a.make(S, q0)
        rotM = a.make(S, DebrisMat3.zero); invIBody = a.make(S, DebrisMat3.zero); invIWorld = a.make(S, DebrisMat3.zero)
        invMass = a.make(S, Float(0)); radius = a.make(S, Float(0)); age = a.make(S, Float(0))
        restTimer = a.make(S, Float(0)); sleptFor = a.make(S, Float(0)); airTime = a.make(S, Float(0))
        fadeP = a.make(S, Float(0)); fadeRate = a.make(S, Float(0))
        tagP = a.make(S, UInt32(0)); serialP = a.make(S, UInt32(0))
        vertN = a.make(S, Int32(0)); planeN = a.make(S, Int32(0))
        flags = a.make(S, UInt8(0))
        localV = a.make(S * MV, F4()); worldV = a.make(S * MV, F4()); warm = a.make(S * MV, F4())
        planes = a.make(S * MP, F4())
        liveList = a.make(S, Int32(0)); livePos = a.make(S, Int32(-1))
        freeList = a.make(S, Int32(0)); awakeList = a.make(S, Int32(0))
        sapList = a.make(S, Int32(0)); sapKey = a.make(S, Float(0)); inSap = a.make(S, UInt8(0))
        fixed = a.make(max(16, config.maxFixedContacts), FixedHit())
        pairHits = a.make(max(16, config.maxPairContacts), PairHit())
        scratch = a.make(scratchCap, Float(0))
        faceMasks = a.make(MP, UInt32(0))
        arena = a
        for i in 0..<S { freeList[i] = Int32(S - 1 - i) }   // slot 0 is handed out first
        freeN = S
    }

    // MARK: Adding

    // A new piece. verts: hull vertices relative to the centroid (more than 24 are reduced to the 24 most spread out);
    // volume in blocks^3; inertia: the body-frame tensor about the centroid at density 1 (the volume's own second moment,
    // so the mass tensor is density x inertia; nil = a box fit to the hull); density relative (only ratios matter, the
    // game passes velocities); planes: the hull's face planes (n, d), n.v <= d, if the fracture already has them (saves
    // finding them here). Returns the slot, or nil when this frame's quota (maxNewPerFrame) is used up or the input is
    // bad. When the budget is full, the most settled piece starts fading and the new one takes a spare slot (or the
    // most faded piece's slot).
    @discardableResult
    func add(verts: UnsafeBufferPointer<SIMD3<Float>>, volume: Float, inertia: simd_float3x3?,
             position: SIMD3<Float>, orientation: simd_quatf = simd_quatf(vector: SIMD4<Float>(0, 0, 0, 1)),
             velocity: SIMD3<Float> = .zero, angularVelocity: SIMD3<Float> = .zero,
             density: Float = 1, tag: UInt32 = 0, planes given: UnsafeBufferPointer<SIMD4<Float>>? = nil) -> Int? {
        guard addsThisFrame < config.maxNewPerFrame else { stats.dropped += 1; return nil }
        guard verts.count > 0, volume.isFinite, volume > 0, density.isFinite, density > 0,
              DebrisMath.finite(position), DebrisMath.finite(velocity), DebrisMath.finite(angularVelocity)
        else { stats.killed += 1; return nil }
        addsThisFrame += 1
        if nonFading >= config.capacity, let v = settledVictim() { startFade(v, rate: 1 / max(config.fadeTime, 1e-3)) }
        let s: Int
        if freeN > 0 { freeN -= 1; s = Int(freeList[freeN]) } else { s = reclaimSlot() }
        let MV = DebrisWorld.maxVerts, MP = DebrisWorld.maxPlanes
        let base = s * MV
        let nv = copyHull(verts, to: localV + base)
        vertN[s] = Int32(nv)
        var r2: Float = 0
        for k in 0..<nv { r2 = max(r2, DebrisMath.len2(localV[base + k])) }
        let rad = max(r2.squareRoot(), 1e-3)
        radius[s] = rad
        var np = 0
        if let g = given, g.count >= 4 {
            for k in 0..<min(g.count, MP) {
                let p = g[k]
                let l2 = p.x * p.x + p.y * p.y + p.z * p.z
                guard l2 > 1e-12, p.w.isFinite else { continue }
                planes[s * MP + np] = p * (1 / l2.squareRoot())
                np += 1
            }
        } else {
            np = DebrisMath.hullPlanes(UnsafePointer(localV + base), nv, planes + s * MP, MP, masks: faceMasks,
                                       scale: rad)
        }
        planeN[s] = Int32(np < 4 ? 0 : np)                // fewer than 4: bounding spheres between pieces
        setMass(s, volume: volume, inertia: inertia, density: density)
        let ov = orientation.vector
        let ol = ov.x * ov.x + ov.y * ov.y + ov.z * ov.z + ov.w * ov.w
        let q = ol.isFinite && ol > 1e-12 ? simd_quatf(vector: ov * (1 / ol.squareRoot()))
                                          : simd_quatf(vector: F4(0, 0, 0, 1))
        let x = DebrisMath.v4(position)
        pos[s] = x; prevPos[s] = x; drawPos[s] = position
        rot[s] = q; prevRot[s] = q; drawRot[s] = q
        vel[s] = DebrisMath.v4(velocity); ang[s] = DebrisMath.v4(angularVelocity)
        pseudoV[s] = F4(); pseudoW[s] = F4()
        let R = DebrisMath.matrix(q)
        rotM[s] = R
        invIWorld[s] = DebrisMath.sandwich(R, invIBody[s])
        for k in 0..<nv { worldV[base + k] = x + R.mul(localV[base + k]); warm[base + k] = F4() }
        flags[s] = DebrisWorld.fLive | DebrisWorld.fAwake
        age[s] = 0; restTimer[s] = 0; sleptFor[s] = 0; airTime[s] = 0; fadeP[s] = 0; fadeRate[s] = 0
        tagP[s] = tag
        serialCounter &+= 1
        serialP[s] = serialCounter
        livePos[s] = Int32(liveN); liveList[liveN] = Int32(s); liveN += 1
        nonFading += 1
        return s
    }

    @discardableResult
    func add(verts: [SIMD3<Float>], volume: Float, inertia: simd_float3x3?, position: SIMD3<Float>,
             orientation: simd_quatf = simd_quatf(vector: SIMD4<Float>(0, 0, 0, 1)),
             velocity: SIMD3<Float> = .zero, angularVelocity: SIMD3<Float> = .zero,
             density: Float = 1, tag: UInt32 = 0, planes: [SIMD4<Float>]? = nil) -> Int? {
        verts.withUnsafeBufferPointer { vb in
            if let pl = planes {
                return pl.withUnsafeBufferPointer { pb in
                    add(verts: vb, volume: volume, inertia: inertia, position: position, orientation: orientation,
                        velocity: velocity, angularVelocity: angularVelocity, density: density, tag: tag, planes: pb)
                }
            }
            return add(verts: vb, volume: volume, inertia: inertia, position: position, orientation: orientation,
                       velocity: velocity, angularVelocity: angularVelocity, density: density, tag: tag, planes: nil)
        }
    }

    // Up to 24 hull vertices; a bigger hull keeps its most spread-out vertices (farthest point sampling).
    private func copyHull(_ src: UnsafeBufferPointer<SIMD3<Float>>, to dst: UnsafeMutablePointer<SIMD4<Float>>) -> Int {
        let MV = DebrisWorld.maxVerts
        let n = src.count
        if n <= MV { for i in 0..<n { dst[i] = DebrisMath.v4(src[i]) }; return n }
        let m = min(n, scratchCap)
        var first = 0
        var best: Float = -1
        for i in 0..<m {
            let l = DebrisMath.len2(DebrisMath.v4(src[i]))
            if l > best { best = l; first = i }
        }
        dst[0] = DebrisMath.v4(src[first])
        for i in 0..<m { scratch[i] = DebrisMath.len2(DebrisMath.v4(src[i]) - dst[0]) }
        for k in 1..<MV {
            var bi = 0
            var bd: Float = -1
            for i in 0..<m where scratch[i] > bd { bd = scratch[i]; bi = i }
            dst[k] = DebrisMath.v4(src[bi])
            for i in 0..<m {
                let d = DebrisMath.len2(DebrisMath.v4(src[i]) - dst[k])
                if d < scratch[i] { scratch[i] = d }
            }
        }
        return MV
    }

    private func setMass(_ s: Int, volume: Float, inertia: simd_float3x3?, density: Float) {
        let vol = max(volume, config.minVolume)
        let m = vol * density
        invMass[s] = 1 / m
        var I = DebrisMat3.zero
        var ok = false
        if let t = inertia {
            let k = density * vol / volume
            let c0 = t.columns.0 * k, c1 = t.columns.1 * k, c2 = t.columns.2 * k
            // symmetrise: a tensor from float sums is never exactly symmetric
            let xy = (c0.y + c1.x) * 0.5, xz = (c0.z + c2.x) * 0.5, yz = (c1.z + c2.y) * 0.5
            I = DebrisMat3(c0: F4(c0.x, xy, xz, 0), c1: F4(xy, c1.y, yz, 0), c2: F4(xz, yz, c2.z, 0))
            ok = I.c0.x > 0 && I.c1.y > 0 && I.c2.z > 0 && DebrisMath.finite(I.c0) && DebrisMath.finite(I.c1)
                && DebrisMath.finite(I.c2)
        }
        if !ok { I = boxInertia(s, mass: m) }
        // floor under the smallest moment: slivers would otherwise spin at absurd rates and stiffen contacts
        let eps = (I.c0.x + I.c1.y + I.c2.z) * 0.01
        I.c0.x += eps; I.c1.y += eps; I.c2.z += eps
        if let inv = DebrisMath.inverse(I) { invIBody[s] = inv; return }
        let B = boxInertia(s, mass: m)
        invIBody[s] = DebrisMat3(c0: F4(1 / B.c0.x, 0, 0, 0), c1: F4(0, 1 / B.c1.y, 0, 0), c2: F4(0, 0, 1 / B.c2.z, 0))
    }

    private func boxInertia(_ s: Int, mass m: Float) -> DebrisMat3 {
        let base = s * DebrisWorld.maxVerts
        var lo = F4(repeating: .greatestFiniteMagnitude), hi = -lo
        for k in 0..<Int(vertN[s]) { lo = pointwiseMin(lo, localV[base + k]); hi = pointwiseMax(hi, localV[base + k]) }
        let e = pointwiseMax(hi - lo, F4(repeating: 0.02))
        let e2 = e * e
        let k = m / 12
        return DebrisMat3(c0: F4(k * (e2.y + e2.z), 0, 0, 0), c1: F4(0, k * (e2.x + e2.z), 0, 0),
                          c2: F4(0, 0, k * (e2.x + e2.y), 0))
    }

    // Most settled live piece not yet fading: the longest asleep, else the oldest.
    private func settledVictim() -> Int? {
        var best = -1
        var score: Float = -1
        for i in 0..<liveN {
            let s = Int(liveList[i])
            let f = flags[s]
            if f & DebrisWorld.fFading != 0 { continue }
            let sc = f & DebrisWorld.fAwake == 0 ? 1e6 + sleptFor[s] : age[s]
            if sc > score { score = sc; best = s }
        }
        return best >= 0 ? best : nil
    }

    // No free slot: the most faded piece goes now.
    private func reclaimSlot() -> Int {
        var best = Int(liveList[0])
        var score: Float = -1
        for i in 0..<liveN {
            let s = Int(liveList[i])
            let sc = flags[s] & DebrisWorld.fFading != 0 ? 2 + fadeP[s] : (flags[s] & DebrisWorld.fAwake == 0 ? 1 : 0)
            if sc > score { score = sc; best = s }
        }
        free(best)
        stats.replaced += 1
        freeN -= 1
        return Int(freeList[freeN])
    }

    private func startFade(_ s: Int, rate: Float) {
        if flags[s] & DebrisWorld.fFading != 0 { return }
        flags[s] |= DebrisWorld.fFading
        fadeRate[s] = rate
        nonFading -= 1
    }

    private func free(_ s: Int) {
        let f = flags[s]
        if f & DebrisWorld.fLive == 0 { return }
        if f & DebrisWorld.fFading == 0 { nonFading -= 1 }
        flags[s] = 0
        let i = Int(livePos[s])
        liveN -= 1
        let last = liveList[liveN]
        liveList[i] = last
        livePos[Int(last)] = Int32(i)
        livePos[s] = -1
        freeList[freeN] = Int32(s)
        freeN += 1
    }

    // MARK: Stepping

    // Advance by the frame's dt: fixed sub-steps from an accumulator (at most maxSubsteps), then ages and fades, then
    // the interpolated poses the renderer reads. Generic over the ground so a whole-module build calls it directly.
    func step<G: PhysicsGround>(dt: Float, ground: G) { advance(dt, ground, NoFreeSpace(), false) }

    // The same with the free-space fast path. Picked at compile time (no cast, no existential box), so call it with
    // the concrete ground type, or from generic code constrained to PhysicsGround & DebrisFreeSpace.
    func step<G: PhysicsGround & DebrisFreeSpace>(dt: Float, ground: G) { advance(dt, ground, ground, true) }

    private struct NoFreeSpace: DebrisFreeSpace {
        func isFree(_ centre: SIMD3<Float>, radius: Float) -> Bool { false }
    }

    private func advance<G: PhysicsGround, C: DebrisFreeSpace>(_ dt: Float, _ ground: G, _ clear: C, _ useClear: Bool) {
        addsThisFrame = 0
        let h = config.substep
        if dt.isFinite && dt > 0 { accumulator += dt }
        var n = Int(accumulator / h)
        if n > config.maxSubsteps { n = config.maxSubsteps; accumulator = Float(n) * h }
        accumulator = max(0, accumulator - Float(n) * h)
        stats.fixedContacts = 0; stats.pairContacts = 0; stats.pairs = 0; stats.iterations = 0
        stats.groundQueries = 0
        for _ in 0..<n { substep(h, ground, clear, useClear) }
        stats.substeps = n
        updateLifetimes(dt.isFinite ? max(dt, 0) : 0)
        updateDrawPoses(min(1, accumulator / h))
        stats.live = liveN
    }

    private func substep<G: PhysicsGround, C: DebrisFreeSpace>(_ h: Float, _ ground: G, _ clear: C, _ useClear: Bool) {
        var na = 0
        for i in 0..<liveN {
            let s = Int(liveList[i])
            if flags[s] & DebrisWorld.fAwake != 0 { awakeList[na] = Int32(s); na += 1 }
        }
        awakeN = na
        stats.awake = na
        fixedN = 0; pairHitN = 0; pairN = 0
        if na == 0 { return }
        let g = F4(0, -config.gravity * h, 0, 0)
        let linD = 1 / (1 + h * config.linearDamping)
        let angAir = 1 / (1 + h * config.angularDamping)
        let angTouch = 1 / (1 + h * (config.angularDamping + config.contactAngularDamping))
        for i in 0..<na {
            let s = Int(awakeList[i])
            prevPos[s] = pos[s]; prevRot[s] = rot[s]
            vel[s] = (vel[s] + g) * linD
            ang[s] *= flags[s] & DebrisWorld.fTouch != 0 ? angTouch : angAir
            flags[s] &= ~DebrisWorld.fTouch
            let R = DebrisMath.matrix(rot[s])
            rotM[s] = R
            invIWorld[s] = DebrisMath.sandwich(R, invIBody[s])
            pseudoV[s] = F4(); pseudoW[s] = F4()
        }
        groundContacts(h, ground, clear, useClear, na)
        bodyContacts(h, na)
        solve()
        integrate(h, na)
        stats.fixedContacts += fixedN; stats.pairContacts += pairHitN; stats.pairs += pairN
    }

    // One query per hull vertex, at where it will be after this sub-step: the contact holds the vertex at the surface
    // whether it is already in or only about to be (speculative), so fast pieces stop on the surface, not in it.
    // Vertex-major (vertex k of every piece, then k + 1): consecutive contacts belong to different pieces, so the
    // solver's per-piece dependency chains interleave and the CPU overlaps them (about 2x faster than piece by piece).
    private func groundContacts<G: PhysicsGround, C: DebrisFreeSpace>(_ h: Float, _ ground: G, _ clear: C,
                                                                     _ useClear: Bool, _ na: Int) {
        let MV = DebrisWorld.maxVerts
        var maxNV = 0
        var queries = 0
        for i in 0..<na {
            let s = Int(awakeList[i])
            let nv = Int(vertN[s])
            maxNV = max(maxNV, nv)
            flags[s] &= ~DebrisWorld.fClear
            if !useClear { continue }
            // the ball swept by the hull this sub-step, with a margin for the speculative probe
            let v = vel[s], x = pos[s]
            let move = (DebrisMath.len2(v).squareRoot() + DebrisMath.len2(ang[s]).squareRoot() * radius[s]) * h
            let mid = x + v * (0.5 * h)
            if clear.isFree(SIMD3(mid.x, mid.y, mid.z), radius: radius[s] + move + 0.02) {
                flags[s] |= DebrisWorld.fClear
                for k in 0..<nv { warm[s * MV + k] = F4() }
            }
        }
        for k in 0..<maxNV {
            for i in 0..<na {
                let s = Int(awakeList[i])
                if k >= Int(vertN[s]) { continue }
                let R = rotM[s]
                let key = s * MV + k
                let r = R.mul(localV[key])
                let p = pos[s] + r
                worldV[key] = p
                if flags[s] & DebrisWorld.fClear != 0 { continue }
                let u = vel[s] + DebrisMath.cross(ang[s], r)
                let probe = p + u * h
                queries += 1
                guard let hit = ground.contact(SIMD3(probe.x, probe.y, probe.z)), hit.depth.isFinite else {
                    warm[key] = F4()
                    continue
                }
                var n = DebrisMath.v4(hit.normal)
                let l2 = DebrisMath.len2(n)
                if abs(l2 - 1) > 1e-3 {
                    if !(l2 > 1e-12) || !l2.isFinite { warm[key] = F4(); continue }
                    n *= 1 / l2.squareRoot()
                }
                let approach = -DebrisMath.dot(u, n)
                addFixed(s, Int32(key), r, n, u, approach * h - hit.depth, approach, h)
            }
        }
        stats.groundQueries += queries
    }

    @inline(__always) private func tangents(_ u: F4, _ n: F4, _ approach: Float) -> (F4, F4) {
        var t1 = u + n * approach                       // u minus its normal part: the slide direction
        let tl = DebrisMath.len2(t1)
        t1 = tl > 1e-8 ? t1 * (1 / tl.squareRoot()) : DebrisMath.perpendicular(n)
        return (t1, DebrisMath.cross(n, t1))
    }

    private func addFixed(_ s: Int, _ key: Int32, _ r: F4, _ n: F4, _ u: F4, _ sep: Float, _ approach: Float,
                          _ h: Float) {
        if fixedN >= config.maxFixedContacts { return }
        flags[s] |= DebrisWorld.fTouch
        let (t1, t2) = tangents(u, n, approach)
        let I = invIWorld[s], im = invMass[s]
        let c = fixed + fixedN
        fixedN += 1
        let cn = DebrisMath.cross(r, n), c1 = DebrisMath.cross(r, t1), c2 = DebrisMath.cross(r, t2)
        let an = I.mul(cn), at1 = I.mul(c1), at2 = I.mul(c2)
        c.pointee.lx = F4(n.x, t1.x, t2.x, 0); c.pointee.ly = F4(n.y, t1.y, t2.y, 0); c.pointee.lz = F4(n.z, t1.z, t2.z, 0)
        c.pointee.ax = F4(cn.x, c1.x, c2.x, 0); c.pointee.ay = F4(cn.y, c1.y, c2.y, 0); c.pointee.az = F4(cn.z, c1.z, c2.z, 0)
        c.pointee.n = n; c.pointee.t1 = t1; c.pointee.t2 = t2
        c.pointee.an = an; c.pointee.at1 = at1; c.pointee.at2 = at2
        let k = F4(DebrisMath.dot(cn, an), DebrisMath.dot(c1, at1), DebrisMath.dot(c2, at2), 0)
        c.pointee.m = 1 / (k + F4(im, im, im, 1))
        var bias: Float = sep > 0 ? -sep / h : 0         // a gap may close this sub-step, no more
        if approach > config.bounceSpeed { bias = max(bias, config.restitution * approach) }
        c.pointee.bias = bias
        let over = -sep - config.slop
        c.pointee.pbias = over > 0 ? min(config.correction * over / h, config.maxCorrectionSpeed) : 0
        c.pointee.jp = 0
        c.pointee.body = Int32(s); c.pointee.key = key
        var j = F4()
        if key >= 0 {
            let W = warm[Int(key)] * 0.9
            let jn = max(0, DebrisMath.dot(W, n))
            let (j1, j2) = DebrisWorld.clampFriction(DebrisMath.dot(W, t1), DebrisMath.dot(W, t2), config.friction * jn)
            j = F4(jn, j1, j2, 0)
        }
        c.pointee.j = j
    }

    private func addPair(_ a: Int, _ b: Int, _ p: F4, _ n: F4, _ depth: Float, _ h: Float) {
        if pairHitN >= config.maxPairContacts { return }
        flags[a] |= DebrisWorld.fTouch; flags[b] |= DebrisWorld.fTouch
        let ra = p - pos[a], rb = p - pos[b]
        let ua = vel[a] + DebrisMath.cross(ang[a], ra), ub = vel[b] + DebrisMath.cross(ang[b], rb)
        let u = ua - ub
        let approach = -DebrisMath.dot(u, n)
        let (t1, t2) = tangents(u, n, approach)
        let Ia = invIWorld[a], Ib = invIWorld[b]
        let c = pairHits + pairHitN
        pairHitN += 1
        let ca = DebrisMath.cross(ra, n), ca1 = DebrisMath.cross(ra, t1), ca2 = DebrisMath.cross(ra, t2)
        let cb = DebrisMath.cross(rb, n), cb1 = DebrisMath.cross(rb, t1), cb2 = DebrisMath.cross(rb, t2)
        let aa = Ia.mul(ca), aa1 = Ia.mul(ca1), aa2 = Ia.mul(ca2)
        let ab = Ib.mul(cb), ab1 = Ib.mul(cb1), ab2 = Ib.mul(cb2)
        c.pointee.lx = F4(n.x, t1.x, t2.x, 0); c.pointee.ly = F4(n.y, t1.y, t2.y, 0); c.pointee.lz = F4(n.z, t1.z, t2.z, 0)
        c.pointee.axa = F4(ca.x, ca1.x, ca2.x, 0); c.pointee.aya = F4(ca.y, ca1.y, ca2.y, 0)
        c.pointee.aza = F4(ca.z, ca1.z, ca2.z, 0)
        c.pointee.axb = F4(cb.x, cb1.x, cb2.x, 0); c.pointee.ayb = F4(cb.y, cb1.y, cb2.y, 0)
        c.pointee.azb = F4(cb.z, cb1.z, cb2.z, 0)
        c.pointee.n = n; c.pointee.t1 = t1; c.pointee.t2 = t2
        c.pointee.ana = aa; c.pointee.at1a = aa1; c.pointee.at2a = aa2
        c.pointee.anb = ab; c.pointee.at1b = ab1; c.pointee.at2b = ab2
        let ka = F4(DebrisMath.dot(ca, aa), DebrisMath.dot(ca1, aa1), DebrisMath.dot(ca2, aa2), 0)
        let kb = F4(DebrisMath.dot(cb, ab), DebrisMath.dot(cb1, ab1), DebrisMath.dot(cb2, ab2), 0)
        let im = invMass[a] + invMass[b]
        c.pointee.m = 1 / (ka + kb + F4(im, im, im, 1))
        c.pointee.bias = approach > config.bounceSpeed ? config.restitution * approach : 0
        let over = depth - config.slop
        c.pointee.pbias = over > 0 ? min(config.correction * over / h, config.maxCorrectionSpeed) : 0
        c.pointee.j = F4(); c.pointee.jp = 0
        c.pointee.a = Int32(a); c.pointee.b = Int32(b)
    }

    // Sort and sweep along the axis the pieces spread most on: the order barely changes between sub-steps, so the
    // insertion sort is near O(n), and the sweep's branches are predictable. (A uniform hash grid measured 43 us a
    // sub-step for 160 resting pieces against 5 us for this: hash lookups are mostly unpredictable empty buckets.)
    // Pairs of two sleepers are skipped; a sleeper is only ever the passive side.
    private func bodyContacts(_ h: Float, _ na: Int) {
        if liveN < 2 { return }
        var n = 0
        for i in 0..<sapN {                               // drop freed slots, keep the order
            let s = Int(sapList[i])
            if flags[s] & DebrisWorld.fLive != 0 { sapList[n] = Int32(s); n += 1 } else { inSap[s] = 0 }
        }
        var lo = F4(repeating: .greatestFiniteMagnitude), hi = -lo
        for i in 0..<liveN {
            let s = Int(liveList[i])
            if inSap[s] == 0 { inSap[s] = 1; sapList[n] = Int32(s); n += 1 }
            lo = pointwiseMin(lo, pos[s]); hi = pointwiseMax(hi, pos[s])
        }
        sapN = n
        let ext = hi - lo
        let ax = ext.x >= ext.z ? (ext.x >= ext.y ? 0 : 1) : (ext.z >= ext.y ? 2 : 1)
        sapAxis = ax
        for i in 0..<n { let s = Int(sapList[i]); sapKey[s] = pos[s][ax] - radius[s] }
        for i in 1..<max(n, 1) {
            let s = sapList[i]
            let k = sapKey[Int(s)]
            var j = i - 1
            while j >= 0 && sapKey[Int(sapList[j])] > k { sapList[j + 1] = sapList[j]; j -= 1 }
            sapList[j + 1] = s
        }
        let maxPairs = config.maxPairs
        for i in 0..<n {
            let s = Int(sapList[i])
            let ps = pos[s], rs = radius[s]
            let end = ps[ax] + rs
            let sAwake = flags[s] & DebrisWorld.fAwake != 0
            var j = i + 1
            while j < n {
                let t = Int(sapList[j])
                j += 1
                if sapKey[t] > end { break }
                let tAwake = flags[t] & DebrisWorld.fAwake != 0
                if !sAwake && !tAwake { continue }
                let rr = rs + radius[t]
                if DebrisMath.len2(pos[t] - ps) >= rr * rr { continue }
                if pairN >= maxPairs { return }
                pairN += 1
                if sAwake { collide(s, t, tAwake, h) } else { collide(t, s, false, h) }
            }
        }
    }

    // Deepest plane of a hull containing local point l: (depth, face) or depth < 0 when outside.
    @inline(__always) private func inside(_ s: Int, _ l: F4) -> (Float, Int) {
        let P = planes + s * DebrisWorld.maxPlanes
        var best = Float.greatestFiniteMagnitude
        var bi = 0
        for k in 0..<Int(planeN[s]) {
            let p = P[k]
            let d = p.w - DebrisMath.dot(p, l)
            if d < 0 { return (-1, 0) }
            if d < best { best = d; bi = k }
        }
        return (best, bi)
    }

    // Vertices of each piece inside the other's hull (face planes found at add time). Misses pure edge-edge touches,
    // which a vertex then catches a little deeper; good enough for chunky fracture pieces.
    private func collide(_ a: Int, _ b: Int, _ bAwake: Bool, _ h: Float) {
        let MV = DebrisWorld.maxVerts, MP = DebrisWorld.maxPlanes
        let limit = config.maxContactsPerPair
        var made = 0
        if planeN[a] == 0 || planeN[b] == 0 {
            // a hull too flat for planes: bounding spheres
            let d = pos[a] - pos[b]
            let dist = DebrisMath.len2(d).squareRoot()
            let n = dist > 1e-6 ? d * (1 / dist) : F4(0, 1, 0, 0)
            let depth = radius[a] + radius[b] - dist
            let p = pos[a] - n * (radius[a] - depth * 0.5)
            contact(a, b, bAwake, p, n, depth, h)
            return
        }
        // separated along the line between the centres: bounding spheres overlap but the hulls do not
        let xa = pos[a], xb = pos[b]
        let dir = xb - xa
        var supA = -Float.greatestFiniteMagnitude, supB = Float.greatestFiniteMagnitude
        for k in 0..<Int(vertN[a]) { supA = max(supA, DebrisMath.dot(worldV[a * MV + k] - xa, dir)) }
        for k in 0..<Int(vertN[b]) { supB = min(supB, DebrisMath.dot(worldV[b * MV + k] - xa, dir)) }
        if supA < supB { return }
        // a's vertices in b: pushed along b's face normal
        let Rb = rotM[b], rb2 = radius[b] * radius[b]
        let pb = planes + b * MP
        for k in 0..<Int(vertN[a]) {
            let p = worldV[a * MV + k]
            let d = p - xb
            if DebrisMath.len2(d) > rb2 { continue }
            let (depth, f) = inside(b, Rb.tmul(d))
            if depth < 0 { continue }
            let pl = pb[f]
            contact(a, b, bAwake, p, Rb.mul(F4(pl.x, pl.y, pl.z, 0)), depth, h)
            made += 1
            if made >= limit { return }
        }
        // b's vertices in a: a is pushed against its own face normal
        let Ra = rotM[a], ra2 = radius[a] * radius[a]
        let pa = planes + a * MP
        for k in 0..<Int(vertN[b]) {
            let p = worldV[b * MV + k]
            let d = p - xa
            if DebrisMath.len2(d) > ra2 { continue }
            let (depth, f) = inside(a, Ra.tmul(d))
            if depth < 0 { continue }
            let pl = pa[f]
            contact(a, b, bAwake, p, -Ra.mul(F4(pl.x, pl.y, pl.z, 0)), depth, h)
            made += 1
            if made >= limit { return }
        }
    }

    // n pushes a away from b. A sleeping b is a rock this sub-step; hit hard, it wakes for the next.
    @inline(__always)
    private func contact(_ a: Int, _ b: Int, _ bAwake: Bool, _ p: F4, _ n: F4, _ depth: Float, _ h: Float) {
        if bAwake { addPair(a, b, p, n, depth, h); return }
        let r = p - pos[a]
        let u = vel[a] + DebrisMath.cross(ang[a], r)
        let approach = -DebrisMath.dot(u, n)
        addFixed(a, -1, r, n, u, -depth, approach, h)
        if approach > config.wakeSpeed && flags[b] & DebrisWorld.fWake == 0 {
            flags[b] |= DebrisWorld.fWake
            wakeRequests += 1
        }
    }

    // Friction impulse (j1, j2) kept inside the Coulomb disc of radius lim.
    @inline(__always) private static func clampFriction(_ j1: Float, _ j2: Float, _ lim: Float) -> (Float, Float) {
        let jj = j1 * j1 + j2 * j2
        if jj <= lim * lim { return (j1, j2) }
        let f = lim / jj.squareRoot()
        return (j1 * f, j2 * f)
    }

    private func solve() {
        let fx = fixed, pr = pairHits
        let nf = fixedN, np = pairHitN
        let v = vel, w = ang, pv = pseudoV, pw = pseudoW, im = invMass
        let mu = config.friction
        // warm start: ground contacts remember last sub-step's impulse per hull vertex
        for i in 0..<nf {
            let c = fx + i
            let j = c.pointee.j
            if j.x == 0 && j.y == 0 && j.z == 0 { continue }
            let s = Int(c.pointee.body)
            let P = c.pointee.n * j.x + c.pointee.t1 * j.y + c.pointee.t2 * j.z
            v[s] += P * im[s]
            w[s] += c.pointee.an * j.x + c.pointee.at1 * j.y + c.pointee.at2 * j.z
        }
        let maxIt = max(1, config.iterations), minIt = max(1, min(config.minIterations, maxIt))
        let tol2 = config.tolerance * config.tolerance
        var it = 0
        while it < maxIt {
            it += 1
            var change: Float = 0                         // largest squared velocity change this iteration
            for i in 0..<np {
                let c = pr + i
                let a = Int(c.pointee.a), b = Int(c.pointee.b)
                var va = v[a], wa = w[a], vb = v[b], wb = w[b]
                let dv = va - vb
                let vl = c.pointee.lx * dv.x + c.pointee.ly * dv.y + c.pointee.lz * dv.z
                let vwa = c.pointee.axa * wa.x + c.pointee.aya * wa.y + c.pointee.aza * wa.z
                let vwb = c.pointee.axb * wb.x + c.pointee.ayb * wb.y + c.pointee.azb * wb.z
                let vr = vl + vwa - vwb
                let j0 = c.pointee.j, m = c.pointee.m
                let jn = max(j0.x + (c.pointee.bias - vr.x) * m.x, 0)
                let (j1, j2) = DebrisWorld.clampFriction(j0.y - vr.y * m.y, j0.z - vr.z * m.z, mu * jn)
                let j = F4(jn, j1, j2, 0)
                let d = j - j0
                c.pointee.j = j
                let P = c.pointee.n * d.x + c.pointee.t1 * d.y + c.pointee.t2 * d.z
                let ima = im[a], imb = im[b]
                change = max(change, DebrisMath.len2(d) * (ima + imb) * (ima + imb))
                va += P * ima; vb -= P * imb
                wa += c.pointee.ana * d.x + c.pointee.at1a * d.y + c.pointee.at2a * d.z
                wb -= c.pointee.anb * d.x + c.pointee.at1b * d.y + c.pointee.at2b * d.z
                v[a] = va; w[a] = wa; v[b] = vb; w[b] = wb
                let pb = c.pointee.pbias
                if pb > 0 || c.pointee.jp > 0 {
                    let pva = pv[a], pwa = pw[a], pvb = pv[b], pwb = pw[b]
                    let ca = F4(c.pointee.axa.x, c.pointee.aya.x, c.pointee.aza.x, 0)
                    let cb = F4(c.pointee.axb.x, c.pointee.ayb.x, c.pointee.azb.x, 0)
                    let n = c.pointee.n
                    let vpn = DebrisMath.dot(n, pva - pvb) + DebrisMath.dot(ca, pwa) - DebrisMath.dot(cb, pwb)
                    let jp0 = c.pointee.jp
                    let jp1 = max(jp0 + (pb - vpn) * m.x, 0)
                    let dp = jp1 - jp0
                    c.pointee.jp = jp1
                    pv[a] = pva + n * (dp * ima); pw[a] = pwa + c.pointee.ana * dp
                    pv[b] = pvb - n * (dp * imb); pw[b] = pwb - c.pointee.anb * dp
                    change = max(change, dp * dp * (ima + imb) * (ima + imb))
                }
            }
            // ground and sleepers last: they win where constraints disagree
            for i in 0..<nf {
                let c = fx + i
                let s = Int(c.pointee.body)
                var vs = v[s], ws = w[s]
                let vl = c.pointee.lx * vs.x + c.pointee.ly * vs.y + c.pointee.lz * vs.z
                let vw = c.pointee.ax * ws.x + c.pointee.ay * ws.y + c.pointee.az * ws.z
                let vr = vl + vw
                let j0 = c.pointee.j, m = c.pointee.m
                let jn = max(j0.x + (c.pointee.bias - vr.x) * m.x, 0)
                let (j1, j2) = DebrisWorld.clampFriction(j0.y - vr.y * m.y, j0.z - vr.z * m.z, mu * jn)
                let j = F4(jn, j1, j2, 0)
                let d = j - j0
                c.pointee.j = j
                let ims = im[s]
                change = max(change, DebrisMath.len2(d) * ims * ims)
                vs += (c.pointee.n * d.x + c.pointee.t1 * d.y + c.pointee.t2 * d.z) * ims
                ws += c.pointee.an * d.x + c.pointee.at1 * d.y + c.pointee.at2 * d.z
                v[s] = vs; w[s] = ws
                let pb = c.pointee.pbias
                if pb > 0 || c.pointee.jp > 0 {
                    let pvs = pv[s], pws = pw[s]
                    let n = c.pointee.n
                    let cn = F4(c.pointee.ax.x, c.pointee.ay.x, c.pointee.az.x, 0)
                    let vpn = DebrisMath.dot(n, pvs) + DebrisMath.dot(cn, pws)
                    let jp0 = c.pointee.jp
                    let jp1 = max(jp0 + (pb - vpn) * m.x, 0)
                    let dp = jp1 - jp0
                    c.pointee.jp = jp1
                    pv[s] = pvs + n * (dp * ims); pw[s] = pws + c.pointee.an * dp
                    change = max(change, dp * dp * ims * ims)
                }
            }
            if it >= minIt && change < tol2 { break }     // converged (warm-started rest settles in 2-3)
        }
        stats.iterations += it
        for i in 0..<nf {
            let c = fx + i
            let key = Int(c.pointee.key)
            if key < 0 { continue }
            let j = c.pointee.j
            warm[key] = c.pointee.n * j.x + c.pointee.t1 * j.y + c.pointee.t2 * j.z
        }
    }

    private func integrate(_ h: Float, _ na: Int) {
        let maxSpeed = config.maxVertexStep / h
        let sl2 = config.sleepLinear * config.sleepLinear, sa2 = config.sleepAngular * config.sleepAngular
        let delay = config.sleepDelay
        for i in 0..<na {
            let s = Int(awakeList[i])
            var v = vel[s], w = ang[s]
            let sp = DebrisMath.len2(v).squareRoot() + DebrisMath.len2(w).squareRoot() * radius[s]
            if sp > maxSpeed { let f = maxSpeed / sp; v *= f; w *= f }
            let x = pos[s] + (v + pseudoV[s]) * h
            let q = DebrisMath.integrate(rot[s], w + pseudoW[s], h)
            if !DebrisMath.finite(x) || !q.vector.x.isFinite || !q.vector.w.isFinite || !DebrisMath.finite(v)
                || !DebrisMath.finite(w) {
                free(s)                                    // never let one bad piece poison the frame
                stats.killed += 1
                continue
            }
            vel[s] = v; ang[s] = w
            pos[s] = x; rot[s] = q
            if flags[s] & DebrisWorld.fTouch != 0 && DebrisMath.len2(v) < sl2 && DebrisMath.len2(w) < sa2 {
                restTimer[s] += h
                if restTimer[s] >= delay { sleep(s) }
            } else {
                restTimer[s] = 0
            }
        }
        if wakeRequests > 0 {
            for i in 0..<liveN {
                let s = Int(liveList[i])
                if flags[s] & DebrisWorld.fWake != 0 { wakeBody(s) }
            }
            wakeRequests = 0
        }
    }

    private func sleep(_ s: Int) {
        flags[s] &= ~DebrisWorld.fAwake
        vel[s] = F4(); ang[s] = F4()
        restTimer[s] = 0
        let R = DebrisMath.matrix(rot[s])
        rotM[s] = R
        invIWorld[s] = DebrisMath.sandwich(R, invIBody[s])
        let base = s * DebrisWorld.maxVerts, x = pos[s]
        for k in 0..<Int(vertN[s]) { worldV[base + k] = x + R.mul(localV[base + k]); warm[base + k] = F4() }
        prevPos[s] = x; prevRot[s] = rot[s]
    }

    private func wakeBody(_ s: Int) {
        flags[s] = (flags[s] | DebrisWorld.fAwake) & ~DebrisWorld.fWake
        restTimer[s] = 0; sleptFor[s] = 0
        prevPos[s] = pos[s]; prevRot[s] = rot[s]
    }

    private func updateLifetimes(_ dt: Float) {
        let fadeRate1 = 1 / max(config.fadeTime, 1e-3)
        var i = liveN - 1
        while i >= 0 {
            let s = Int(liveList[i])
            i -= 1
            age[s] += dt
            let f = flags[s]
            if f & DebrisWorld.fAwake == 0 { sleptFor[s] += dt; airTime[s] = 0 }
            else if f & DebrisWorld.fTouch != 0 { airTime[s] = 0 } else { airTime[s] += dt }
            if f & DebrisWorld.fFading == 0 {
                if sleptFor[s] >= config.settleTime || age[s] >= config.maxAge || airTime[s] >= config.maxAirTime
                    || pos[s].y < config.minY {
                    startFade(s, rate: fadeRate1)
                }
            }
            if flags[s] & DebrisWorld.fFading != 0 {
                fadeP[s] += dt * fadeRate[s]
                if fadeP[s] >= 1 { fadeP[s] = 1; free(s) }  // swap-remove only moves an already visited entry
            }
        }
    }

    private func updateDrawPoses(_ t: Float) {
        for i in 0..<liveN {
            let s = Int(liveList[i])
            if flags[s] & DebrisWorld.fAwake != 0 {
                drawPos[s] = DebrisMath.v3(prevPos[s] + (pos[s] - prevPos[s]) * t)
                drawRot[s] = DebrisMath.nlerp(prevRot[s], rot[s], t)
            } else {
                drawPos[s] = DebrisMath.v3(pos[s]); drawRot[s] = rot[s]
            }
        }
    }

    // MARK: Game hooks

    // Wake sleepers whose bounds touch the sphere (a block removed or placed there). Returns how many woke.
    @discardableResult
    func wake(centre: SIMD3<Float>, radius r: Float) -> Int {
        let c = DebrisMath.v4(centre)
        var n = 0
        for i in 0..<liveN {
            let s = Int(liveList[i])
            if flags[s] & DebrisWorld.fAwake != 0 { continue }
            let rr = r + radius[s]
            if DebrisMath.len2(pos[s] - c) < rr * rr { wakeBody(s); n += 1 }
        }
        return n
    }

    // A blast: pieces within radius wake and get a push away from the centre (speed falls off linearly) and a tumble.
    func blast(centre: SIMD3<Float>, radius r: Float, speed: Float) {
        let c = DebrisMath.v4(centre)
        for i in 0..<liveN {
            let s = Int(liveList[i])
            let d = pos[s] - c
            let l2 = DebrisMath.len2(d)
            if l2 >= r * r { continue }
            let l = l2.squareRoot()
            let dir = l > 1e-4 ? d * (1 / l) : F4(0, 1, 0, 0)
            let k = speed * (1 - l / r)
            if flags[s] & DebrisWorld.fAwake == 0 { wakeBody(s) }
            vel[s] += dir * k
            ang[s] += DebrisMath.cross(dir, F4(0, 1, 0, 0)) * (k * 2) + F4(0, k * 0.5, 0, 0)
        }
    }

    // An impulse (mass x velocity, mass = volume x density) at a world point; wakes the piece.
    func applyImpulse(slot s: Int, impulse: SIMD3<Float>, at point: SIMD3<Float>) {
        guard isLive(s), DebrisMath.finite(impulse), DebrisMath.finite(point) else { return }
        if flags[s] & DebrisWorld.fAwake == 0 { wakeBody(s) }
        let R = DebrisMath.matrix(rot[s])
        let Iw = DebrisMath.sandwich(R, invIBody[s])
        let J = DebrisMath.v4(impulse)
        vel[s] += J * invMass[s]
        ang[s] += Iw.mul(DebrisMath.cross(DebrisMath.v4(point) - pos[s], J))
    }

    // Every live piece starts its fade (a budget squeeze, a dimension change).
    func fadeAll() {
        let rate = 1 / max(config.fadeTime, 1e-3)
        for i in 0..<liveN { startFade(Int(liveList[i]), rate: rate) }
    }

    func remove(slot s: Int) { if s >= 0 && s < slotCount { free(s) } }

    func clear() { while liveN > 0 { free(Int(liveList[liveN - 1])) } }

    // MARK: Read-out (no allocation; pointers stay valid for the world's life, indexed by slot)

    var count: Int { liveN }
    // Slots of live pieces, dense, in no particular order (valid until the next add/step/remove).
    var liveSlots: UnsafeBufferPointer<Int32> { UnsafeBufferPointer(start: liveList, count: liveN) }
    // Draw poses (interpolated between the last two sub-steps), fade 0 = solid ... 1 = gone, tag, serial.
    var positions: UnsafePointer<SIMD3<Float>> { UnsafePointer(drawPos) }
    var orientations: UnsafePointer<simd_quatf> { UnsafePointer(drawRot) }
    var fades: UnsafePointer<Float> { UnsafePointer(fadeP) }
    var tags: UnsafePointer<UInt32> { UnsafePointer(tagP) }
    // Changes whenever a slot gets a new piece, so a renderer caching a mesh per slot knows to rebuild it.
    var serials: UnsafePointer<UInt32> { UnsafePointer(serialP) }

    @inline(__always)
    func forEachLive(_ body: (_ slot: Int, _ position: SIMD3<Float>, _ orientation: simd_quatf, _ fade: Float,
                              _ tag: UInt32) -> Void) {
        for i in 0..<liveN {
            let s = Int(liveList[i])
            body(s, drawPos[s], drawRot[s], fadeP[s], tagP[s])
        }
    }

    func isLive(_ s: Int) -> Bool { s >= 0 && s < slotCount && flags[s] & DebrisWorld.fLive != 0 }
    func isAwake(_ s: Int) -> Bool { isLive(s) && flags[s] & DebrisWorld.fAwake != 0 }
    func isFading(_ s: Int) -> Bool { isLive(s) && flags[s] & DebrisWorld.fFading != 0 }
    // Physics state (not interpolated).
    func pose(_ s: Int) -> (position: SIMD3<Float>, orientation: simd_quatf) { (DebrisMath.v3(pos[s]), rot[s]) }
    func velocity(_ s: Int) -> (linear: SIMD3<Float>, angular: SIMD3<Float>) {
        (DebrisMath.v3(vel[s]), DebrisMath.v3(ang[s]))
    }
    func boundingRadius(_ s: Int) -> Float { radius[s] }
    func planeCount(_ s: Int) -> Int { Int(planeN[s]) }
    // The hull as stored (local, round the centroid).
    func vertexCount(_ s: Int) -> Int { Int(vertN[s]) }
    func vertex(_ s: Int, _ k: Int) -> SIMD3<Float> { DebrisMath.v3(localV[s * DebrisWorld.maxVerts + k]) }
}
