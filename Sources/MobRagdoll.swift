import Foundation
import simd

// Realistic world, layer 3 (docs/design/realistic-world.md 3.3): a creature that dies in a realistic world falls as a
// ragdoll (Ragdoll.swift) instead of the canned fall (MobAnim.pose). Its bones come from its own model, so every
// creature gets one with no list: the parts that turn about one pivot are one bone (a leg, an arm, a tail, a wing, a
// tentacle), the head joint's parts another, and the biggest of the rest is the body the others hang from. A limb
// hangs from the bone nearest its pivot, so a jointed leg hangs from its thigh.
//
// Drawing (writeMobVertices): the model is posed as it was at the moment of death, placed in the world there, and each
// part is carried by its bone's motion since then (RagdollWorld.delta).
struct MobRagdoll {
    var id = -1
    var base = V3.zero               // the model's origin in the world at death (position plus the drawn step)
    var centres: [V3] = []           // each bone's centre at death
    var pivots: [V3] = []            // model pivots (pixels) ...
    var pivotBone: [UInt8] = []      // ... and the bone each one's parts ride on
    var head = 0                     // the bone the head joint's parts ride on

    // The bone a model part rides on (the same rule the bones were made with).
    @inline(__always) func bone(_ p: Part, _ hj: HeadJoint?) -> Int {
        if let j = hj, j.holds(p) { return head }
        if p.pivot == .zero { return 0 }
        for i in 0..<pivots.count where simd_length_squared(pivots[i] - p.pivot) < 1e-4 { return Int(pivotBone[i]) }
        return 0
    }

    // Per bone this frame, for the vertex writer: the turn since death and where the death-pose origin went (relative
    // to the eye). A death-pose world point P is now at R (P - c0) + c; with P = yaw(q) + base, that is
    // R yaw(q) + [R (base - c0) + c - eye]. (Scratch, filled per corpse on the render thread: no allocation per frame.)
    static var turn = [simd_float3x3](repeating: matrix_identity_float3x3, count: RagdollWorld.maxBones)
    static var shift = [V3](repeating: .zero, count: RagdollWorld.maxBones)
    static let faceNormals = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0), V3(0, 0, 1), V3(0, 0, -1)]   // Mesher order

    // Fills turn/shift for this body; false when its ragdoll is gone (the pool was cleared): drawn the old way.
    func prepare(_ w: RagdollWorld, eye: V3) -> Bool {
        guard id >= 0, w.isLive(id) else { return false }
        let n = min(w.boneCount(id), centres.count)
        for b in 0..<n {
            let r = simd_float3x3(w.delta(id, b).rotation)
            MobRagdoll.turn[b] = r
            MobRagdoll.shift[b] = r * (base - centres[b]) + (w.pose(id, b).position - eye)
        }
        for b in n..<RagdollWorld.maxBones { MobRagdoll.turn[b] = MobRagdoll.turn[0]; MobRagdoll.shift[b] = MobRagdoll.shift[0] }
        return true
    }
}

enum MobRagdolls {
    // The bones of a dying mob's model as it stands now (call after MobManager.addCorpse has set its death clock, so
    // MobAnim.pose gives the unanimated death pose), with the map from parts to bones. nil for a body that can't fall
    // as one (asleep in a bed, sitting, a hunted carcass) or has no parts.
    static func build(_ m: Mob) -> (bones: [RagdollBone], rig: MobRagdoll)? {
        if m.lying || m.sitting || m.carcass { return nil }
        let ps = mobModelParts(m)
        guard !ps.isEmpty else { return nil }
        let hj = MobAnim.headJoint(m)
        let pose = MobAnim.pose(m)

        // Groups: 0 the fixed parts, 1 the head joint's, then one per pivot.
        struct Group {
            var pivot: V3
            var frame = matrix_identity_float3x3     // the box's axes in the model: its biggest part's rotation
            var vol: Float = 0, biggest: Float = -1
            var parts: [Int] = []
            var centre = V3.zero, half = V3.zero      // box in the model (pixels), centre in model axes
            var into = -1                             // merged into this group
        }
        var gs = [Group(pivot: .zero), Group(pivot: hj?.pivot ?? .zero)]
        for (i, p) in ps.enumerated() {
            let size = p.mx - p.mn
            let v = max(size.x * size.y * size.z, 1e-3)
            var g: Int
            if let j = hj, j.holds(p) { g = 1 }
            else if p.pivot == .zero { g = 0 }
            else {
                g = -1
                for k in 2..<gs.count where simd_length_squared(gs[k].pivot - p.pivot) < 1e-4 { g = k; break }
                if g < 0 { gs.append(Group(pivot: p.pivot)); g = gs.count - 1 }
                if v > gs[g].biggest { gs[g].biggest = v; gs[g].frame = p.rotation }
            }
            gs[g].vol += v
            gs[g].parts.append(i)
        }
        // The posed model-space corners of part i.
        func corners(_ i: Int, _ f: (V3) -> Void) {
            let p = ps[i], rot = p.rotation, size = p.mx - p.mn
            let head = pose.joint?.holds(p) ?? false
            for c in 0..<8 {
                var q = p.place(p.mn + size * V3(Float(c & 1), Float((c >> 1) & 1), Float(c >> 2)), rot)
                if head { q = pose.ha * q + pose.hb }
                f(pose.a * q + pose.b)
            }
        }
        func fit(_ g: Int, _ list: [Int]) {
            let r = gs[g].frame, rt = r.transpose
            var lo = V3(repeating: .greatestFiniteMagnitude), hi = -lo
            for i in list { corners(i) { q in let l = rt * q; lo = simd_min(lo, l); hi = simd_max(hi, l) } }
            gs[g].centre = r * ((lo + hi) * 0.5)
            gs[g].half = simd_max((hi - lo) * 0.5, V3(repeating: 0.4))
        }
        for g in gs.indices where !gs[g].parts.isEmpty { fit(g, gs[g].parts) }

        // The body: the biggest group that isn't the head; the fixed parts ride on it.
        var root = -1
        for g in gs.indices where g != 1 && !gs[g].parts.isEmpty && (root < 0 || gs[g].vol > gs[root].vol) { root = g }
        if root < 0 { root = 1 }
        if root != 0 && !gs[0].parts.isEmpty { gs[0].into = root }
        // Limbs: thin specks (an eye, a button) and the smallest past the bone cap ride on the body.
        var limbs = gs.indices.filter { $0 != root && $0 != 0 && !gs[$0].parts.isEmpty }
        for g in limbs where max(gs[g].half.x, max(gs[g].half.y, gs[g].half.z)) < 0.8 && g != 1 { gs[g].into = root }
        limbs = limbs.filter { gs[$0].into < 0 }.sorted { gs[$0].vol > gs[$1].vol }
        for g in limbs.dropFirst(RagdollWorld.maxBones - 1) { gs[g].into = root }
        limbs = Array(limbs.prefix(RagdollWorld.maxBones - 1))
        var rootParts = gs[root].parts
        for g in gs.indices where gs[g].into == root { rootParts += gs[g].parts }
        fit(root, rootParts)

        // Bone order: the body, then limbs by how near their pivot is to it, each hanging from the nearest bone
        // already placed (the body wins near ties), so a shin hangs from its thigh.
        let rc = gs[root].centre
        func pivotOf(_ g: Int) -> V3 { pose.a * gs[g].pivot + pose.b }
        limbs.sort { simd_length_squared(pivotOf($0) - rc) < simd_length_squared(pivotOf($1) - rc) }
        func gap(_ p: V3, _ g: Int) -> Float {                          // point to box distance (model, pixels)
            let l = gs[g].frame.transpose * (p - gs[g].centre)
            return simd_length(simd_max(simd_abs(l) - gs[g].half, .zero))
        }
        let s: Float = (m.sized ? 1 : m.scale) / 16
        let yq = simd_quatf(angle: m.yaw, axis: V3(0, 1, 0))
        let base = m.pos + V3(0, m.viewDY, 0)
        func world(_ q: V3) -> V3 { yq.act(q * s) + base }
        let upright = MobAnim.upright(m)
        var order = [root], kinds: [RagdollJoint] = [.spine]
        var bones = [RagdollBone(centre: world(gs[root].centre), half: gs[root].half * s,
                                 orientation: yq * simd_quatf(gs[root].frame), parent: -1)]
        for g in limbs {
            let pv = pivotOf(g)
            var parent = 0
            var best = gap(pv, root) - 0.5
            for (k, h) in order.enumerated() where k > 0 { let d = gap(pv, h); if d < best { best = d; parent = k } }
            var dir = gs[g].centre - pv
            dir = simd_length(dir) > 1e-3 ? simd_normalize(dir) : V3(0, -1, 0)
            let joint: RagdollJoint
            if g == 1 { joint = .neck }
            else if parent != 0 {
                // A second segment: a knee (the foot swings back, toward +z: the model faces -z) or, below a shoulder,
                // an elbow (the hand comes forward).
                joint = kinds[parent].swing == RagdollJoint.shoulder.swing ? .hinge(min: 0, max: 145) : .hinge(min: -140, max: 0)
            } else if dir.y < -0.6 { joint = upright && pv.y > rc.y ? .shoulder : .hip }
            else if dir.z > 0.6 { joint = .tail }
            else if dir.z < -0.6 { joint = .neck }
            else { joint = .shoulder }
            var j = joint
            // Limits measured from the pose it died in (a zombie's arms held out are their rest).
            j.neutral = simd_quatf(gs[order[parent]].frame).inverse * simd_quatf(gs[g].frame)
            bones.append(RagdollBone(centre: world(gs[g].centre), half: gs[g].half * s, orientation: yq * simd_quatf(gs[g].frame),
                                     parent: parent, pivot: world(pv), joint: j))
            order.append(g); kinds.append(j)
        }

        // Parts to bones: by pivot (the vertex writer's rule, MobRagdoll.bone).
        var rig = MobRagdoll()
        rig.base = base
        rig.centres = bones.map { $0.centre }
        func boneOf(_ g: Int) -> Int {
            let t = gs[g].into >= 0 ? gs[g].into : g
            return order.firstIndex(of: t) ?? 0
        }
        rig.head = hj != nil && !gs[1].parts.isEmpty ? boneOf(1) : 0
        for g in 2..<gs.count {
            rig.pivots.append(gs[g].pivot)
            rig.pivotBone.append(UInt8(boneOf(g)))
        }
        return (bones, rig)
    }

    // Starts the ragdoll of a body that just died (MobManager.addCorpse): thrown by what is left of the killing blow
    // (its knockback), which lands high on the body so it goes over.
    static func start(_ m: Mob, in w: RagdollWorld) {
        guard let (bones, r) = build(m) else { return }
        var v = m.vel
        if !(v.x.isFinite && v.y.isFinite && v.z.isFinite) { v = .zero }
        var flat = V3(v.x, 0, v.z)
        let l = simd_length(flat)
        if l > 12 { flat *= 12 / l }
        let hit = r.base + V3(0, m.height * 0.7, 0)
        let id = w.start(bones, velocity: V3(flat.x * 0.2, max(-20, min(v.y, 2)), flat.z * 0.2), hitPoint: hit, impulse: flat * 0.8)
        guard id >= 0 else { return }
        var rig = r
        rig.id = id
        m.ragdoll = rig
    }
}
