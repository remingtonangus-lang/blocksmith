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

    // How deep the weapon sinks into the arms and torso (the deepest sample, px) and which way it should move.
    static func clip(_ p: SoldierPose, _ gm: GunModel, poleL: V3? = nil, poleR: V3? = nil) -> (depth: Float, push: V3, armL: Float, armR: Float, torso: Float) {
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

    // Swing the elbows round the weapon, then move the weapon (and the hands on it) clear.
    static func clear(_ p: inout SoldierPose, _ gm: GunModel) {
        guard clip(p, gm).depth > 0.25 else { return }
        for _ in 0..<6 {
            for side in [-1, 1] as [Float] {
                let left = side < 0
                guard (left ? p.handL : p.handR) != nil else { continue }
                let cur = left ? p.poleL : p.poleR
                let tries = [cur, V3(side, -0.6, 0.2), V3(side, 0, 0), V3(side, -1, -0.4), V3(side * 0.4, -1, 0.6),
                             V3(side, 0.4, 0.3), V3(side * 0.6, -0.3, -1)]
                var best = cur, bestD = Float.greatestFiniteMagnitude
                for t in tries {
                    let c = left ? clip(p, gm, poleL: t) : clip(p, gm, poleR: t)
                    let d = left ? c.armL : c.armR
                    if d < bestD - 0.05 { best = t; bestD = d }
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
