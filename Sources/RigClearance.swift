import Foundation
import simd

// P353 (Oct 16 20:05: "a beached pirate's gun passes through his arm"; fix it generally, on every character): the
// weapon a soldier-rig character holds (every soldier rank, corsairs, the Ashguard, crews and bounty hunters) never
// passes through his arms or his body. After a stance places the weapon and the hands, the rig measures how far the
// weapon's centre line (butt to muzzle, and its magazine) sinks into each arm (upper arm and forearm as capsules,
// the fist that holds it excepted) and the torso; it first swings each elbow out round the weapon (the IK pole: out,
// down, back), and if that is not enough moves the weapon clear, the hands on it carried along. The pose check
// (--posecheck) holds every rank, every weapon and every stance to it (SoldierRigOut.clip).
extension SoldierRig {
    static let armR: Float = 1.75, gunR: Float = 0.55       // arm half-width, the weapon's half-thickness (model px)

    // Where an arm's hand goes in this pose (as body() places it): the posed target, or the hanging arm's angles.
    static func armTarget(_ p: SoldierPose, side: Float) -> (s: V3, h: V3, posed: Bool) {
        let left = side < 0
        let s = p.t(V3(side * shoulderX, shoulderY, 0))
        if let h = left ? p.handL : p.handR { return (s, h, true) }
        let a = left ? p.armL : p.armR
        let sp = side * a.y
        let r1 = Part(mn: .zero, mx: .zero, rotX: a.x, rotZ: sp, color: .zero).rotation
        let r2 = Part(mn: .zero, mx: .zero, rotX: a.x - a.z, rotZ: sp, color: .zero).rotation
        return (s, s + r1 * V3(0, -upperArm, 0) + r2 * V3(0, -foreArm, 0), false)
    }

    // The weapon's centre line, butt to muzzle, and its magazine well (model px).
    static func gunSamples(_ gm: GunModel, _ p: SoldierPose) -> [V3] {
        var out: [V3] = []
        out.reserveCapacity(13)
        for i in 0...10 { out.append(gunPoint(gm, gm.butt + (gm.muzzle - gm.butt) * (Float(i) / 10), p)) }
        out.append(gunPoint(gm, gm.magAt, p))
        out.append(gunPoint(gm, gm.grip, p))
        return out
    }

    static func closest(_ q: V3, _ a: V3, _ b: V3) -> (V3, Float) {
        let d = b - a
        let l2 = simd_length_squared(d)
        let t = l2 < 1e-6 ? 0 : max(0, min(1, simd_dot(q - a, d) / l2))
        return (a + d * t, t)
    }

    // Model space -> the standing torso frame (undoes p.t, the breathing lift aside).
    static func torsoLocal(_ q: V3, _ p: SoldierPose) -> V3 {
        let r0 = q - V3(0, p.hipY, 0)
        let ct = cosf(p.twist), st = sinf(p.twist)
        let r = V3(ct * r0.x - st * r0.z, r0.y, st * r0.x + ct * r0.z)
        let cl = cosf(p.lean), sl = sinf(p.lean)
        return V3(r.x, r.y * cl + r.z * sl, -r.y * sl + r.z * cl) + V3(0, 12, 0)
    }
    static func torsoDir(_ d: V3, _ p: SoldierPose) -> V3 { p.t(d + V3(0, 12, 0)) - p.t(V3(0, 12, 0)) }

    // Nov 4 (frame rate, the worst-case soak's callgrind: the mobs' drawn rigs, 1.0 G instructions of 3.75 G in the mob
    // pass, clip 22k a call): each measure built its 13 samples with a rotation each (sines and cosines), and made 22 small
    // arrays (the two arm segments per sample, the sides, the torso samples). It now turns the weapon once, keeps the
    // samples on the stack and makes no arrays; the same numbers (questcheck --posecheck compares it with the old
    // measure, BS_CLIPOLD=1 draws with the old one).
    static let clipOldEnv = ProcessInfo.processInfo.environment["BS_CLIPOLD"] == "1"
    static var clipCompare = false, clipDiff: Float = 0, clipCompared = 0      // (posecheck)
    static var clipTimes = (fast: 0.0, old: 0.0)
    static func clip(_ p: SoldierPose, _ gm: GunModel, poleL: V3? = nil, poleR: V3? = nil) -> (depth: Float, push: V3, armL: Float, armR: Float, torso: Float) {
        if clipOldEnv { return clipOld(p, gm, poleL: poleL, poleR: poleR) }
        guard clipCompare else { return clipFast(p, gm, poleL: poleL, poleR: poleR) }
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = clipFast(p, gm, poleL: poleL, poleR: poleR)
        let t1 = CFAbsoluteTimeGetCurrent()
        do {
            let o = clipOld(p, gm, poleL: poleL, poleR: poleR)
            clipTimes.fast += t1 - t0; clipTimes.old += CFAbsoluteTimeGetCurrent() - t1
            let d = max(abs(r.depth - o.depth), simd_length(r.push - o.push), abs(r.armL - o.armL), abs(r.armR - o.armR), abs(r.torso - o.torso))
            clipDiff = max(clipDiff, d); clipCompared += 1
        }
        return r
    }
    // The weapon's 13 samples (as gunSamples) into `pts`.
    @inline(__always) static func samples(_ p: SoldierPose, _ gm: GunModel, into pts: UnsafeMutableBufferPointer<V3>) {
        let rot = gunRotation(p)
        @inline(__always) func at(_ local: V3) -> V3 { p.gunAt + rot * ((local - gm.grip) * gm.scale) }
        for i in 0...10 { pts[i] = at(gm.butt + (gm.muzzle - gm.butt) * (Float(i) / 10)) }
        pts[11] = at(gm.magAt)
        pts[12] = at(gm.grip)
    }
    // How deep the weapon sinks into one arm (clipFast's armL or armR) with its elbow toward `pole`: the same steps.
    @inline(__always) static func armDepth(_ s: V3, _ target: V3, pole: V3, shoulderedButt: Bool, _ pts: UnsafeMutableBufferPointer<V3>) -> Float {
        let reachIn = armR + gunR
        let (e, h) = ik(s, target, upperArm, foreArm, pole: pole)
        var per: Float = 0
        for i in 0..<13 {
            let q = pts[i]
            if simd_length(q - h) < 3.0 { continue }
            if i == 0 && shoulderedButt && simd_length(q - s) < 3.2 { continue }
            for seg in 0..<2 {
                let a = seg == 0 ? s : e, b = seg == 0 ? e : h
                let (c, t) = closest(q, a, b)
                if seg == 1 && t > 0.75 { continue }
                let d = simd_length(q - c)
                let pen = reachIn - d
                if pen > 0 { per = max(per, pen) }
            }
        }
        return per
    }
    static func clipFast(_ p: SoldierPose, _ gm: GunModel, poleL: V3?, poleR: V3?) -> (depth: Float, push: V3, armL: Float, armR: Float, torso: Float) {
        return withUnsafeTemporaryAllocation(of: V3.self, capacity: 13) { pts -> (depth: Float, push: V3, armL: Float, armR: Float, torso: Float) in
            samples(p, gm, into: pts)
            var depth: Float = 0, push = V3(0, 0, 0)
            var perL: Float = 0, perR: Float = 0, body: Float = 0
            let shoulderedButt = gm.shouldered
            let reachIn = armR + gunR
            for k in 0..<2 {
                let side: Float = k == 0 ? -1 : 1
                let (s, target, _) = armTarget(p, side: side)
                let pole = side < 0 ? (poleL ?? p.poleL) : (poleR ?? p.poleR)
                let (e, h) = ik(s, target, upperArm, foreArm, pole: pole)
                var per: Float = 0
                for i in 0..<13 {
                    let q = pts[i]
                    if simd_length(q - h) < 3.0 { continue }
                    if i == 0 && shoulderedButt && simd_length(q - s) < 3.2 { continue }
                    // (upper arm s-e, then forearm e-h but the wrist into the fist)
                    for seg in 0..<2 {
                        let a = seg == 0 ? s : e, b = seg == 0 ? e : h
                        let (c, t) = closest(q, a, b)
                        if seg == 1 && t > 0.75 { continue }
                        let d = simd_length(q - c)
                        let pen = reachIn - d
                        if pen > 0 {
                            per = max(per, pen)
                            depth = max(depth, pen)
                            let dir = d > 1e-3 ? (q - c) / d : simd_normalize(V3(side, 0, -1))
                            push += dir * pen
                        }
                    }
                }
                if k == 0 { perL = per } else { perR = per }
            }
            // The torso (as clipOld): the samples inside it, then the side most of them is on.
            var n = 0, sum = V3(0, 0, 0)
            for i in 0..<13 {
                if i == 0 && shoulderedButt { continue }
                let l = torsoLocal(pts[i], p)
                let dx = 4 + gunR - abs(l.x), dy = min(l.y - 12, 24 - l.y) + gunR, dz = 2.5 + gunR - abs(l.z)
                guard dx > 0 && dy > 0 && dz > 0 else { continue }
                body = max(body, min(dx, dz))
                sum += l; n += 1
            }
            if n > 0 {
                let mean = sum / Float(n)
                let grip = torsoLocal(pts[12], p)
                let sz: Float = abs(mean.z) > 0.3 ? (mean.z < 0 ? -1 : 1) : (grip.z < 0 ? -1 : 1)
                let sx: Float = mean.x < 0 ? -1 : 1
                var needZ = -Float.greatestFiniteMagnitude, needX = -Float.greatestFiniteMagnitude
                for i in 0..<13 {
                    if i == 0 && shoulderedButt { continue }
                    let l = torsoLocal(pts[i], p)
                    let dx = 4 + gunR - abs(l.x), dy = min(l.y - 12, 24 - l.y) + gunR, dz = 2.5 + gunR - abs(l.z)
                    guard dx > 0 && dy > 0 && dz > 0 else { continue }
                    needZ = max(needZ, 2.5 + gunR - sz * l.z); needX = max(needX, 4 + gunR - sx * l.x)
                }
                push += needZ <= needX ? torsoDir(V3(0, 0, sz), p) * needZ : torsoDir(V3(sx, 0, 0), p) * needX
                depth = max(depth, body)
            }
            return (depth, push, perL, perR, body)
        }
    }

    // How deep the weapon sinks into the arms and torso (the deepest sample, px) and which way it should move.
    static func clipOld(_ p: SoldierPose, _ gm: GunModel, poleL: V3? = nil, poleR: V3? = nil) -> (depth: Float, push: V3, armL: Float, armR: Float, torso: Float) {
        let pts = gunSamples(gm, p)
        var depth: Float = 0, push = V3(0, 0, 0)
        var per: [Float] = [0, 0], body: Float = 0
        let shoulderedButt = gm.shouldered
        for (k, side) in ([-1, 1] as [Float]).enumerated() {
            let (s, target, _) = armTarget(p, side: side)
            let pole = side < 0 ? (poleL ?? p.poleL) : (poleR ?? p.poleR)
            let (e, h) = ik(s, target, upperArm, foreArm, pole: pole)
            for (i, q) in pts.enumerated() {
                if simd_length(q - h) < 3.0 { continue }                   // the fist holding it
                if i == 0 && shoulderedButt && simd_length(q - s) < 3.2 { continue }   // a stock in the shoulder
                for (a, b) in [(s, e), (e, h)] {
                    let (c, t) = closest(q, a, b)
                    if a == e && t > 0.75 { continue }                          // the wrist into the fist
                    let d = simd_length(q - c)
                    let pen = armR + gunR - d
                    if pen > 0 {
                        per[k] = max(per[k], pen)
                        depth = max(depth, pen)
                        let dir = d > 1e-3 ? (q - c) / d : simd_normalize(V3(side, 0, -1))
                        push += dir * pen
                    }
                }
            }
        }
        // The torso: x +-4, y 12...24, z +-2.5 in the standing frame. A weapon through it leaves by the side most of it
        // is on (all of it at once: per-sample pushes cancel for a weapon run right through).
        var inside: [V3] = []
        for (i, q) in pts.enumerated() {
            if i == 0 && shoulderedButt { continue }
            let l = torsoLocal(q, p)
            let dx = 4 + gunR - abs(l.x), dy = min(l.y - 12, 24 - l.y) + gunR, dz = 2.5 + gunR - abs(l.z)
            guard dx > 0 && dy > 0 && dz > 0 else { continue }
            body = max(body, min(dx, dz))
            inside.append(l)
        }
        if !inside.isEmpty {
            let mean = inside.reduce(V3(0, 0, 0), +) / Float(inside.count)
            let grip = torsoLocal(gunPoint(gm, gm.grip, p), p)
            let sz: Float = abs(mean.z) > 0.3 ? (mean.z < 0 ? -1 : 1) : (grip.z < 0 ? -1 : 1)
            let sx: Float = mean.x < 0 ? -1 : 1
            let needZ = inside.map { 2.5 + gunR - sz * $0.z }.max()!, needX = inside.map { 4 + gunR - sx * $0.x }.max()!
            push += needZ <= needX ? torsoDir(V3(0, 0, sz), p) * needZ : torsoDir(V3(sx, 0, 0), p) * needX
            depth = max(depth, body)
        }
        return (depth, push, per[0], per[1], body)
    }

    // Store review (Nov 2, VRC.Quest.Performance.1; questcheck --framesoak battle, callgrind): clear() is up to ~90
    // clip measures a soldier, every soldier, every drawn frame: three quarters of the mobs' vertex time in the Ash
    // Vault battle (136 soldiers). Drawn past 14 blocks (the middle and far models), a soldier's correction (how far the
    // weapon moved, where the elbows swung) is measured again every few frames, staggered, and reused between: a
    // stance moves less in 4-8 frames than a pixel shows at that distance. Near ones, and the AI's muzzle lookups,
    // are measured every time.
    static var clearFrame = 0
    private static var clearKept: [ObjectIdentifier: (frame: Int, move: V3, poleL: V3, poleR: V3)] = [:]
    static func clear(_ p: inout SoldierPose, _ gm: GunModel, for m: Mob, lod: Int) {
        guard drawing, lod > 0 else { clear(&p, gm); return }
        let key = ObjectIdentifier(m)
        let every = lod == 1 ? 4 : 8
        if let k = clearKept[key], clearFrame - k.frame < every, clearFrame >= k.frame {
            let fore = gunPoint(gm, gm.fore, p)
            let onR = p.handR.map { simd_length($0 - p.gunAt) < 0.01 } ?? false
            let onL = p.handL.map { simd_length($0 - fore) < 0.01 } ?? false
            p.poleL = k.poleL; p.poleR = k.poleR
            if simd_length_squared(k.move) > 0 {
                p.gunAt += k.move
                if onR { p.handR = p.gunAt }
                if onL { p.handL = gunPoint(gm, gm.fore, p) }
            }
            return
        }
        let g0 = p.gunAt
        clear(&p, gm)
        if clearKept.count > 4000 { clearKept.removeAll(keepingCapacity: true) }
        // (staggered: a soldier's next measure falls on its own frame of the cycle)
        let phase = Int(UInt(bitPattern: key.hashValue) % UInt(every))
        clearKept[key] = (clearFrame - phase, p.gunAt - g0, p.poleL, p.poleR)
    }

    // Nov 9 (callgrind of the battle soak's mob drawing: this was a fifth of it, the near soldiers measured every
    // frame): each of the 14 elbow tries a round measured the whole clip (the weapon's samples turned again, both
    // arms and the torso twice) for one arm's depth. A try now measures only that arm, on samples and a shoulder
    // worked out once a side (the pole moves neither): the same numbers, so the same choices (BS_OLDCLEAR=1: as
    // before; BS_CLEARVERIFY=1: every clear run both ways and the poses compared).
    static let oldClear = ProcessInfo.processInfo.environment["BS_OLDCLEAR"] == "1"
    static let clearVerify = ProcessInfo.processInfo.environment["BS_CLEARVERIFY"] == "1"
    static var clearVerified = 0, clearVerifyDiffs = 0
    static func clear(_ p: inout SoldierPose, _ gm: GunModel) {
        guard clearVerify else { clearOnce(&p, gm, old: oldClear); return }
        var o = p
        clearOnce(&o, gm, old: true)
        clearOnce(&p, gm, old: false)
        clearVerified += 1
        @inline(__always) func same(_ a: V3?, _ b: V3?) -> Bool { a == nil ? b == nil : (b != nil && a! == b!) }
        if !(o.gunAt == p.gunAt && o.poleL == p.poleL && o.poleR == p.poleR && same(o.handL, p.handL) && same(o.handR, p.handR)
             && o.gunPitch == p.gunPitch && o.gunYaw == p.gunYaw && o.gunRoll == p.gunRoll && o.armL == p.armL && o.armR == p.armR) {
            clearVerifyDiffs += 1
            if clearVerifyDiffs <= 5 { print("clearverify: DIFFERS: gun \(o.gunAt) vs \(p.gunAt), poles \(o.poleL) \(o.poleR) vs \(p.poleL) \(p.poleR)") }
        }
    }
    // Swing the elbows round the weapon, then move the weapon (and the hands on it) clear.
    private static func clearOnce(_ p: inout SoldierPose, _ gm: GunModel, old: Bool) {
        guard clip(p, gm).depth > 0.25 else { return }
        let quick = !old && !clipOldEnv && !clipCompare        // (the arm measure is clipFast's)
        for _ in 0..<6 {
            for side in [-1, 1] as [Float] {
                let left = side < 0
                guard (left ? p.handL : p.handR) != nil else { continue }
                let cur = left ? p.poleL : p.poleR
                let tries = [cur, V3(side, -0.6, 0.2), V3(side, 0, 0), V3(side, -1, -0.4), V3(side * 0.4, -1, 0.6),
                             V3(side, 0.4, 0.3), V3(side * 0.6, -0.3, -1)]
                var best = cur, bestD = Float.greatestFiniteMagnitude
                if quick {
                    let pp = p
                    withUnsafeTemporaryAllocation(of: V3.self, capacity: 13) { pts in
                        samples(pp, gm, into: pts)
                        let (s, target, _) = armTarget(pp, side: side)
                        for t in tries {
                            let d = armDepth(s, target, pole: t, shoulderedButt: gm.shouldered, pts)
                            if d < bestD - 0.05 { best = t; bestD = d }
                        }
                    }
                } else {
                    for t in tries {
                        let c = left ? clip(p, gm, poleL: t) : clip(p, gm, poleR: t)
                        let d = left ? c.armL : c.armR
                        if d < bestD - 0.05 { best = t; bestD = d }
                    }
                }
                if left { p.poleL = best } else { p.poleR = best }
            }
            let c = clip(p, gm)
            if c.depth <= 0.25 { return }
            let l = simd_length(c.push)
            guard l > 1e-4 else { return }
            let fore = gunPoint(gm, gm.fore, p)
            let onR = p.handR.map { simd_length($0 - p.gunAt) < 0.01 } ?? false
            let onL = p.handL.map { simd_length($0 - fore) < 0.01 } ?? false
            let move = c.push / l * min(2.0, c.depth + 0.15)
            p.gunAt += move
            if onR { p.handR = p.gunAt }
            if onL { p.handL = gunPoint(gm, gm.fore, p) }
            fit(&p, gm)
        }
    }
}
