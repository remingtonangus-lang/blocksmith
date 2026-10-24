import Foundation
import simd

// P295 (Oct 16, 11:49: "people and animals should look more realistic"): the farm animals rebuilt to the horse's
// standard (Animals.horseParts). Each has a body of barrel, chest and rump with a belly, legs jointed at the knee and
// hock ending in hooves, trotters or toes, a neck carrying the head, a face with eyes, lids, nostrils, ears and a jaw,
// and idle life: grazing and chewing the cud, rooting, pecking, the tail swishing, ears flicking, blinking. Units
// 1/16 block, feet at y 0, model faces -Z; Part rotation as in Mob.swift. Each animal's own coat seed (Mob.coatSeed)
// picks its coat among its climate's (FarmVariant), so a herd reads as many animals.
// Level of detail (MobDetail): the vertex writer builds near animals in full, the middle distance without the specks
// (nostrils, teats, lids, catchlights, toes), the far ones with one box per leg and a plain head.

enum MobDetail {
    // 0 full, 1 middle (no specks), 2 far (plain shapes). Set per mob while drawing (writeMobVertices); everything else
    // (ragdolls, pose and render checks) builds the full model.
    static var level = 0
    static func level(forDistanceSquared d2: Float) -> Int { d2 < 20 * 20 ? 0 : (d2 < 48 * 48 ? 1 : 2) }
}

extension Mob {
    // A steady cosmetic roll in 0..<1 from the mob's coat seed (not the gameplay RNG).
    func coatRoll(_ salt: Int) -> Float { hashf(Int(coatSeed), salt, 7, 0x295) }

    // True for a moment every few seconds, at the mob's own beat: its eyes are shut.
    var blinking: Bool {
        let t: Float = animT * 0.27 + coatRoll(31)
        return t - floorf(t) < 0.035
    }
}

// A joint of a model: points given relative to it, turned by rotX `a` about it (the composed-pivot rule: a child joint
// at local j, turned a further c, sits at o + Rx(a) j with angle a + c, so a jaw opens in a head that hangs from a neck).
struct ModelJoint {
    var o: V3
    var a: Float
    func at(_ j: V3, _ c: Float) -> ModelJoint {
        let cy = cosf(a), sy = sinf(a)
        let w = V3(j.x, j.y * cy - j.z * sy, j.y * sy + j.z * cy)
        return ModelJoint(o: o + w, a: a + c)
    }
    func box(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 0,
             rz: Float = 0) -> Part {
        Part(mn: o + V3(x0, y0, z0), mx: o + V3(x1, y1, z1), pivot: o, rotX: a, rotZ: rz, color: c, pattern: pat)
    }
}

// A four-legged walk: diagonal pairs (left fore with right hind), the fore knee folding back and the hind hock forward
// as the foot comes through. Returns the upper leg's angle and the lower leg's (both absolute rotX).
struct FarmGait {
    let ph: Float, amt: Float, amp: Float
    var hock: Float = 0.1
    func leg(_ off: Float, front: Bool) -> (Float, Float) {
        let lp: Float = ph + off
        let a: Float = sinf(lp) * amp + (front ? 0 : -hock * 0.6)
        let flex: Float = max(0, cosf(lp)) * 0.65 * amt
        let la: Float = front ? a - flex : a + flex * 0.8 + hock
        return (a, la)
    }
}

// One jointed leg: the upper leg about the hip, the lower leg and the hoof about the knee its turn carries the upper
// leg's end to. Far away: one box from the hip to the ground.
private func farmLeg(_ p: inout [Part], hip: V3, a: Float, la: Float, lu: Float, ll: Float, lh: Float, uw: Float, ud: Float,
                     lw: Float, hw: Float, upper: V3, lower: V3, hoof: V3, pat: Float, lpat: Float, top: Float) {
    let thigh = ModelJoint(o: hip, a: a)
    if MobDetail.level == 2 {
        let w: Float = (uw + lw) * 0.5
        p.append(thigh.box(-w / 2, -(lu + ll + lh), -w / 2, w / 2, top, w / 2, lower, lpat))
        return
    }
    p.append(thigh.box(-uw / 2, -lu - 0.4, -ud / 2, uw / 2, top, ud / 2, upper, pat))
    let knee = thigh.at(V3(0, -lu, 0), la - a)
    p.append(knee.box(-lw / 2, -ll, -lw / 2, lw / 2, 0.4, lw / 2, lower, lpat))
    if lh > 0 { p.append(knee.box(-hw / 2, -ll - lh, -hw / 2 - 0.15, hw / 2, -ll, hw / 2 - 0.1, hoof, 7)) }
}

// Mirrored x span: (a...b) on the right (s > 0), (-b...-a) on the left.
@inline(__always) private func span(_ s: Float, _ a: Float, _ b: Float) -> (Float, Float) { s > 0 ? (a, b) : (-b, -a) }

// The grazing window: the last seconds before each call (callTimer counts down between calls), head down, eased in
// and out; never while it runs, panics or watches you.
private func grazeWindow(_ m: Mob, from: Float, to: Float) -> Float {
    let clock = m.callTimer
    let idle: Float = max(0, 1 - m.walkAmount * 2)
    let watch: Float = max(0, 1 - 2.5 * (abs(m.headYaw) + abs(m.headPitch)))
    let w: Float = max(0, min(1, min(clock - from, to - clock) * 1.5))
    return w * idle * watch * (m.panic > 0 ? 0 : 1)
}

// MARK: Cow

func cowParts(_ m: Mob) -> [Part] {
    let lv = MobDetail.level
    let full = lv == 0, far = lv == 2
    let fv = FarmVariant.climate(m.variant)
    let r0 = m.coatRoll(1), r1 = m.coatRoll(2)
    // Coats: temperate black or brown patched with white (most), or whole red-brown or dun; warm a red or pale zebu with
    // a hump, a deep dewlap and long horns; cold a shaggy long-haired coat with a fringe over the eyes and wide horns.
    var coat: V3
    var pat: Float = 12
    switch fv {
    case 2: coat = r0 < 0.55 ? V3(0.6, 0.31, 0.17) : V3(0.8, 0.7, 0.56)
    case 3: coat = r0 < 0.6 ? V3(0.58, 0.31, 0.16) : (r0 < 0.85 ? V3(0.2, 0.15, 0.12) : V3(0.84, 0.72, 0.52)); pat = 15
    default:
        if r0 < 0.42 { coat = V3(0.12, 0.11, 0.1); pat = 14 }
        else if r0 < 0.78 { coat = V3(0.42, 0.26, 0.16); pat = 14 }
        else if r0 < 0.92 { coat = V3(0.5, 0.3, 0.18) }
        else { coat = V3(0.74, 0.62, 0.46) }
    }
    let muzzle: V3 = pat == 14 ? (r1 < 0.5 ? V3(0.8, 0.58, 0.54) : V3(0.16, 0.13, 0.12)) : coat * 0.62
    let hoof = V3(0.16, 0.13, 0.11), horn = V3(0.86, 0.8, 0.66), hornTip = V3(0.3, 0.26, 0.22)

    let amt = m.walkAmount, ph = m.walkPhase
    let idle: Float = max(0, 1 - amt * 2)
    let gait = FarmGait(ph: ph, amt: amt, amp: 0.5 * amt, hock: 0.16)
    let graze = grazeWindow(m, from: 1.5, to: 7)
    let hipY: Float = 13, lu: Float = 6, ll: Float = 5.5, lh: Float = 1.5
    let bob: Float = abs(sinf(ph)) * 0.25 * amt
    let top: Float = 21 + bob, bot: Float = 9.5 + bob
    var p: [Part] = []
    p.reserveCapacity(60)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pt: Float) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pt))
    }
    // Body: barrel, chest and shoulders, rump; the belly hangs a little lower, the brisket between the fore legs.
    if fv == 3 { b(-5.8, bot - 0.7, -11.4, 5.8, top + 0.9, 11.4, coat, 15) }
    b(-5.2, bot + 0.6, -8, 5.2, top - 0.4, 8, coat, pat)
    b(-5.0, bot, -11.6, 5.0, top, -4, coat, pat)
    b(-5.3, bot + 1.2, 3.5, 5.3, top + 0.2, 11.6, coat, pat)
    if !far {
        b(-4.6, bot - 0.9, -6.5, 4.6, bot + 1.5, 5.5, coat, pat)
        b(-2.6, bot - 0.6, -11.2, 2.6, bot + 3.5, -7.2, coat, pat)
        b(-2.2, top - 0.5, -10, 2.2, top + 0.5, -5, coat, pat)                     // withers
        b(-1, top - 0.3, 10.5, 1, top + 0.6, 12.2, coat, pat)                      // tail head
    }
    if fv == 2 { b(-2.4, top - 0.5, -10.5, 2.4, top + 3, -6, coat * 0.9, pat) }  // the zebu's hump
    if full { b(4, top - 0.4, 5, 5.6, top + 0.6, 7, coat, pat); b(-5.6, top - 0.4, 5, -4, top + 0.6, 7, coat, pat) }   // hook bones
    if !m.baby && !far {
        let teat = V3(0.86, 0.62, 0.58)
        b(-2.3, bot - 2.4, 4.2, 2.3, bot + 0.4, 8.8, teat, 4)                      // udder
        if full {
            for (x, z) in [(-1.3, 5.2), (0.5, 5.2), (-1.3, 7.6), (0.5, 7.6)] as [(Float, Float)] {
                b(x, bot - 3.4, z, x + 0.8, bot - 2.3, z + 0.8, teat * 0.9, 4)
            }
        }
    }
    // Legs.
    let legs: [(Float, Float, Float, Bool)] = [(-3.0, -8.2, 0, true), (3.0, -8.2, .pi, true), (-3.1, 8.0, .pi, false), (3.1, 8.0, 0, false)]
    for (x, z, off, front) in legs {
        let (a, la) = gait.leg(off, front: front)
        farmLeg(&p, hip: V3(x, hipY + bob, z), a: a, la: la, lu: lu, ll: ll, lh: lh, uw: front ? 3.0 : 3.4, ud: front ? 3.6 : 4.4,
                lw: 1.9, hw: 2.4, upper: coat, lower: coat, hoof: hoof, pat: pat, lpat: pat, top: 2.5)
    }
    // Neck: forward and a little up from the shoulders, nodding with the stride; lowered to graze.
    let nod: Float = sinf(ph * 2) * 0.06 * amt
    let nA: Float = -0.85 - nod - graze * 1.4
    let nL: Float = 7.5
    let neck = ModelJoint(o: V3(0, top - 4.5, -10), a: nA)
    let thick: Float = fv == 3 ? 3.0 : 2.6
    p.append(neck.box(-thick, -1.5, -3.0, thick, nL + 0.6, 3.0, coat, fv == 3 ? 15 : pat))
    if !far {
        let dw: Float = fv == 2 ? 2.4 : 1.2                                        // the dewlap below the throat
        p.append(neck.box(-0.9, 0.3, -3.0 - dw, 0.9, nL - 0.6, -2.8, coat, pat))
    }
    // Head: hangs from the poll, face angled down; it drops further to the grass while grazing.
    // P427 (Oct 24 10:17, "why is the nose down so far?"): at rest the face is carried near level (it hung at 34 degrees,
    // the nose pointing at the ground); grazing still takes it right down.
    let hA: Float = -0.22 + nod * 0.5 - graze * 1.23
    let head = neck.at(V3(0, nL, 0), hA - nA)
    p.append(head.box(-2.5, -2.6, -4.8, 2.5, 2.0, 1.0, coat, pat))               // skull and cheeks
    p.append(head.box(-2.0, -2.4, -8.6, 2.0, 1.2, -4.6, coat, pat))              // face
    p.append(head.box(-2.25, -3.0, -10.6, 2.25, -0.5, -8.4, muzzle, pat == 14 ? 4 : pat))
    if far { return p }
    p.append(head.box(-2.7, 1.2, -2.2, 2.7, 2.5, 0.8, coat, pat))                // poll
    p.append(head.box(-1.85, -2.0, -10.8, 1.85, -0.6, -10.5, muzzle * 0.82, 4))  // nose pad
    // The jaw chews: the cud at rest, grass while grazing.
    let chew: Float = -(0.5 + 0.5 * sinf(m.animT * 7)) * 0.14 * idle
    let jaw = head.at(V3(0, -2.8, -4.5), chew)
    p.append(jaw.box(-1.8, -0.7, -5.7, 1.8, 0.2, 0, muzzle, 4))
    // Eyes (glossy), with a brow; lids shut them now and then.
    let eye = V3(0.07, 0.05, 0.04)
    let shut = m.blinking && full
    for s in [-1, 1] as [Float] {
        let (x0, x1) = span(s, 2.5, 2.72)
        p.append(head.box(x0, 0.0, -4.4, x1, 1.1, -3.0, shut ? coat : eye, shut ? pat : 7))
        if full {
            let (bx0, bx1) = span(s, 2.3, 2.66)
            p.append(head.box(bx0, 1.05, -4.6, bx1, 1.45, -2.8, coat * 0.9, pat))
            if !shut { let (cx0, cx1) = span(s, 2.71, 2.75); p.append(head.box(cx0, 0.7, -4.0, cx1, 0.95, -3.75, V3(0.9, 0.9, 0.88), 7)) }
        }
    }
    if full {
        p.append(head.box(-1.25, -1.6, -10.86, -0.55, -1.0, -10.75, V3(0.1, 0.07, 0.07)))      // nostrils
        p.append(head.box(0.55, -1.6, -10.86, 1.25, -1.0, -10.75, V3(0.1, 0.07, 0.07)))
    }
    // Ears out to the sides, flicking now and then.
    let flickT: Float = sinf(m.animT * 0.9 + r1 * 6)
    let flick: Float = max(0, flickT - 0.9) * 3
    for s in [-1, 1] as [Float] {
        let ear = head.at(V3(s * 2.4, 0.9, -0.3), 0)
        let droop: Float = -s * 0.32 + s * (s > 0 ? flick : flick * 0.4)
        let (x0, x1) = span(s, 0, 2.9)
        p.append(ear.box(x0, -0.6, -0.9, x1, 0.55, 0.5, coat, pat, rz: droop))
        if full { let (ix0, ix1) = span(s, 0.4, 2.6); p.append(ear.box(ix0, -0.45, -0.97, ix1, 0.4, -0.88, V3(0.82, 0.6, 0.55), 0, rz: droop)) }
    }
    // Horns: short on the temperate cattle (a few polled), long and lifting on the zebu, wide on the shaggy kind.
    if fv == 3 {
        p.append(head.box(-2.8, -0.4, -5.4, 2.8, 2.9, -1.2, coat * 1.06, 15))     // the fringe
        for s in [-1, 1] as [Float] {
            let (x0, x1) = span(s, 2.3, 6.4), (mx0, mx1) = span(s, 5.8, 6.8)
            p.append(head.box(x0, 1.4, -0.9, x1, 2.4, 0.2, horn))
            p.append(head.box(mx0, 2.0, -1.4, mx1, 3.8, -0.2, horn))
            if full { let (tx0, tx1) = span(s, 6.0, 6.7); p.append(head.box(tx0, 3.6, -2.2, tx1, 4.6, -1.2, hornTip)) }
        }
    } else if fv == 2 {
        for s in [-1, 1] as [Float] {
            let (x0, x1) = span(s, 2.3, 5.5), (tx0, tx1) = span(s, 5.0, 6.0)
            p.append(head.box(x0, 1.6, -0.9, x1, 2.6, 0.3, horn))
            p.append(head.box(tx0, 2.4, -0.8, tx1, 5.2, 0.2, horn))
            if full { let (px0, px1) = span(s, 5.1, 5.9); p.append(head.box(px0, 5.2, -0.7, px1, 5.9, 0.1, hornTip)) }
        }
    } else if r1 > 0.12 {
        for s in [-1, 1] as [Float] {
            let (x0, x1) = span(s, 2.3, 3.6), (tx0, tx1) = span(s, 3.2, 3.9)
            p.append(head.box(x0, 1.7, -0.8, x1, 2.6, 0.2, horn))
            p.append(head.box(tx0, 2.4, -0.7, tx1, 3.7, 0.1, full ? horn : hornTip))
            if full { p.append(head.box(tx0 + 0.05, 3.7, -0.6, tx1 - 0.05, 4.2, 0.0, hornTip)) }
        }
    }
    // Tail: hangs from the tail head to the hock with a switch of long hair; swishes at rest, sways in the walk.
    let sw: Float = sinf(m.callTimer * 2.3) * 0.22 * idle + sinf(ph) * 0.08 * amt
    let tail = ModelJoint(o: V3(0, top - 0.2, 11.7), a: -0.08 - 0.1 * amt)
    p.append(tail.box(-0.55, -11.5, -0.4, 0.55, 0.3, 0.8, coat, pat, rz: sw))
    let switchC: V3 = pat == 14 ? coat * 0.6 + V3(0.35, 0.34, 0.32) : coat * 0.55
    p.append(tail.box(-1.0, -14.5, -0.6, 1.0, -10.8, 1.0, switchC, 15, rz: sw * 1.25))
    return p
}

// MARK: Pig

func pigParts(_ m: Mob) -> [Part] {
    let lv = MobDetail.level
    let full = lv == 0, far = lv == 2
    let fv = FarmVariant.climate(m.variant)
    let r0 = m.coatRoll(1)
    // Skin: temperate pink (a few black with white patches); warm brown or slate with upright ears; cold a blond curly
    // coat all over.
    var skin: V3
    var pat: Float = 4
    switch fv {
    case 2: skin = r0 < 0.6 ? V3(0.5, 0.33, 0.24) : V3(0.25, 0.21, 0.2)
    case 3: skin = V3(0.9, 0.79, 0.6); pat = 2
    default:
        if r0 < 0.2 { skin = V3(0.17, 0.15, 0.15); pat = 14 } else { skin = V3(0.94, 0.66, 0.62) }
    }
    let face: V3 = fv == 3 ? V3(0.88, 0.7, 0.6) : skin
    let disc: V3 = pat == 14 || fv == 2 ? V3(0.3, 0.26, 0.26) : V3(0.96, 0.7, 0.66)
    let trotter: V3 = (fv == 3 ? V3(0.55, 0.42, 0.36) : skin) * 0.55

    let amt = m.walkAmount, ph = m.walkPhase
    let gait = FarmGait(ph: ph, amt: amt, amp: 0.55 * amt, hock: 0.12)
    let root = grazeWindow(m, from: 1.2, to: 5.5)
    let hipY: Float = 6.5, lu: Float = 3.2, ll: Float = 2.3, lh: Float = 1.0
    let bob: Float = abs(sinf(ph)) * 0.2 * amt
    let y0: Float = 5.5 + bob                                                       // the belly line
    var p: [Part] = []
    p.reserveCapacity(40)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pt: Float) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pt))
    }
    // Body: a long barrel, shoulders and hams rounding it out, the back arched, the belly hanging.
    b(-4.6, y0, -8, 4.6, y0 + 7.8, 8.5, skin, pat)
    b(-4.8, y0 + 1, -8.6, 4.8, y0 + 7.3, -3, skin, pat)
    b(-4.9, y0 + 1, 3.5, 4.9, y0 + 7.5, 9.2, skin, pat)
    if !far {
        b(-4.0, y0 + 7.8, -7.0, 4.0, y0 + 8.4, 7.6, skin, pat)
        b(-3.8, y0 - 0.9, -6, 3.8, y0 + 0.2, 6.5, skin, pat)
    }
    let legs: [(Float, Float, Float, Bool)] = [(-2.9, -6.0, 0, true), (2.9, -6.0, .pi, true), (-3.0, 6.2, .pi, false), (3.0, 6.2, 0, false)]
    for (x, z, off, front) in legs {
        let (a, la) = gait.leg(off, front: front)
        farmLeg(&p, hip: V3(x, hipY + bob, z), a: a, la: la, lu: lu, ll: ll, lh: lh, uw: front ? 2.6 : 3.0, ud: front ? 3.0 : 3.6,
                lw: 1.8, hw: 2.0, upper: skin, lower: skin, hoof: trotter, pat: pat, lpat: pat, top: 2)
    }
    // Head: heavy jowls straight off the shoulders; it dips to root at the ground, the snout working.
    let hA: Float = -root * 0.75 + sinf(ph * 2) * 0.04 * amt
    let head = ModelJoint(o: V3(0, y0 + 4.5, -8), a: hA)
    p.append(head.box(-3.5, -3.3, -4.6, 3.5, 2.8, 0.6, face, pat))                // skull and jowls
    let snout = head.at(V3(0, -1.2, -6.6), sinf(m.animT * 14) * 0.12 * root)
    p.append(snout.box(-2.1, -1.3, -1.8, 2.1, 1.6, 0.2, face, pat))
    if far { return p }
    p.append(head.box(-2.6, -2.6, -6.6, 2.6, 1.4, -4.6, face, pat))              // the face tapering to the snout
    p.append(snout.box(-2.25, -1.5, -2.1, 2.25, 1.8, -1.8, disc, 4))              // the snout's disc
    if full {
        p.append(snout.box(-1.3, -0.4, -2.2, -0.5, 0.6, -2.08, V3(0.25, 0.12, 0.12)))
        p.append(snout.box(0.5, -0.4, -2.2, 1.3, 0.6, -2.08, V3(0.25, 0.12, 0.12)))
        p.append(head.box(-2.0, -2.95, -6.3, 2.0, -2.6, -4.4, face * 0.62, pat))  // the mouth's line
    }
    // Small eyes set forward on the face; lids now and then.
    let shut = m.blinking && full
    for s in [-1, 1] as [Float] {
        let (x0, x1) = span(s, 1.4, 2.4)
        p.append(head.box(x0, 1.0, -4.72, x1, 1.8, -4.58, shut ? face : V3(0.08, 0.06, 0.05), shut ? pat : 7))
        if full && !shut { let (cx0, cx1) = span(s, 1.9, 2.15); p.append(head.box(cx0, 1.45, -4.76, cx1, 1.7, -4.7, V3(0.9, 0.9, 0.88), 7)) }
    }
    // Ears: floppy over the eyes, bouncing in the walk (upright on the warm-climate pigs).
    let flop: Float = sinf(ph * 2) * 0.12 * amt - root * 0.2
    for s in [-1, 1] as [Float] {
        let up = fv == 2
        let ear = head.at(V3(s * 2.3, 2.8, -3.0), up ? 1.15 + flop * 0.5 : -0.55 + flop)
        let (x0, x1) = span(s, -1.0, 1.4)
        p.append(ear.box(x0, -0.3, -3.4, x1, 0.3, 0.4, face, pat, rz: -s * 0.25))
    }
    // Tail: a little curl over the rump, twitching.
    let tail = ModelJoint(o: V3(0, y0 + 6.2, 9.2), a: 0)
    let tw: Float = sinf(m.animT * 3.1) * 0.25
    p.append(tail.box(-0.35, -0.4, 0, 0.35, 0.4, 1.4, skin, pat, rz: tw))
    p.append(tail.box(-0.35, 0.2, 1.0, 0.35, 1.6, 1.7, skin, pat, rz: tw))
    p.append(tail.box(-0.35, 1.2, 0.1, 0.35, 1.8, 1.3, skin, pat, rz: tw))
    return p
}

// MARK: Sheep

func sheepParts(_ m: Mob) -> [Part] {
    let lv = MobDetail.level
    let full = lv == 0, far = lv == 2
    let wc = TextureGen.hex(BlockRegistry.colorHex[m.woolColor] ?? 0xE9ECEC)
    let wool = V3(wc.x, wc.y, wc.z)
    let r0 = m.coatRoll(1)
    // Faces and legs: pale (most), black or brown.
    let face: V3 = r0 < 0.62 ? V3(0.86, 0.8, 0.72) : (r0 < 0.88 ? V3(0.15, 0.13, 0.12) : V3(0.46, 0.34, 0.25))
    let dark = r0 >= 0.62 && r0 < 0.88
    let nose: V3 = dark ? V3(0.05, 0.05, 0.05) : V3(0.2, 0.15, 0.14)
    let hoof = V3(0.2, 0.17, 0.15)
    let sheared = m.sheared
    let fl: V3 = sheared ? V3(0.84, 0.8, 0.72) : wool
    let s0: Float = sheared ? 1.4 : 0

    let amt = m.walkAmount, ph = m.walkPhase
    let idle: Float = max(0, 1 - amt * 2)
    let gait = FarmGait(ph: ph, amt: amt, amp: 0.5 * amt, hock: 0.14)
    let graze = grazeWindow(m, from: 1, to: 9)
    let hipY: Float = 11.2, lu: Float = 5, ll: Float = 5, lh: Float = 1.2
    let bob: Float = abs(sinf(ph)) * 0.2 * amt
    var p: [Part] = []
    p.reserveCapacity(44)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pt: Float) {
        p.append(Part(mn: V3(x0, y0 + bob, z0), mx: V3(x1, y1 + bob, z1), color: c, pattern: pt))
    }
    // Fleece: a deep rounded body, domed on top, rounded behind and underneath (shorn: a slim body in stubble).
    b(-5.6 + s0, 10.5 + s0 * 0.5, -9.2 + s0, 5.6 - s0, 20.5 - s0, 8.5 - s0, fl, 2)
    if !far {
        b(-4.9 + s0, 20.5 - s0, -7.6 + s0, 4.9 - s0, 21.3 - s0, 7.6 - s0, fl, 2)
        b(-4.6 + s0, 11.5, 8.5 - s0, 4.6 - s0, 20 - s0, 9.8 - s0, fl, 2)
        b(-4.4 + s0, 9.7 + s0 * 0.5, -6.5, 4.4 - s0, 10.5 + s0 * 0.5, 6.5, fl, 2)
    }
    // Legs: thin, the fleece reaching down over the tops.
    let legs: [(Float, Float, Float, Bool)] = [(-2.6, -6.0, 0, true), (2.6, -6.0, .pi, true), (-2.7, 6.0, .pi, false), (2.7, 6.0, 0, false)]
    for (x, z, off, front) in legs {
        let (a, la) = gait.leg(off, front: front)
        let hip = V3(x, hipY + bob, z)
        farmLeg(&p, hip: hip, a: a, la: la, lu: lu, ll: ll, lh: lh, uw: 2.0, ud: 2.4, lw: 1.4, hw: 1.7,
                upper: face, lower: face, hoof: hoof, pat: 12, lpat: 12, top: 1)
        if !sheared && !far { p.append(ModelJoint(o: hip, a: a).box(-1.5, -2.8, -1.6, 1.5, 0.4, 1.6, fl, 2)) }
    }
    // Neck (in fleece) and head; it goes right down to the grass to graze.
    let nod: Float = sinf(ph * 2) * 0.05 * amt
    let nA: Float = -0.55 - nod - graze * 2.1
    let nL: Float = 6
    let neck = ModelJoint(o: V3(0, 15.8 + bob, -8.4), a: nA)
    p.append(neck.box(-2.2 + s0 * 0.4, -1.5, -3.0 + s0 * 0.3, 2.2 - s0 * 0.4, nL + 0.6, 1.6 - s0 * 0.3, fl, 2))
    let hA: Float = -0.85 + nod * 0.5 - graze * 0.75
    let head = neck.at(V3(0, nL, 0), hA - nA)
    p.append(head.box(-1.9, -2.2, -3.8, 1.9, 1.6, 1.0, face, 12))                 // skull
    p.append(head.box(-1.5, -1.9, -6.8, 1.5, 0.9, -3.8, face, 12))               // the long face
    p.append(head.box(-1.35, -2.1, -8.0, 1.35, -0.2, -6.6, face * 0.92, 12))      // muzzle
    if far { return p }
    p.append(head.box(-2.1, 0.8, -3.4, 2.1, 2.5, 1.3, fl, 2))                     // the wool cap over the brow
    p.append(head.box(-0.9, -1.2, -8.15, 0.9, -0.3, -7.95, nose, 4))
    let chew: Float = -(0.5 + 0.5 * sinf(m.animT * 6.5)) * 0.12 * idle
    let jaw = head.at(V3(0, -1.9, -4.0), chew)
    p.append(jaw.box(-1.1, -0.6, -3.8, 1.1, 0.1, 0, face * 0.9, 12))
    if full {
        p.append(head.box(-0.75, -1.0, -8.25, -0.3, -0.6, -8.1, V3(0.05, 0.04, 0.04)))
        p.append(head.box(0.3, -1.0, -8.25, 0.75, -0.6, -8.1, V3(0.05, 0.04, 0.04)))
    }
    // Eyes on the sides: amber with a long dark pupil up close; lids now and then.
    let shut = m.blinking && full
    for s in [-1, 1] as [Float] {
        let (x0, x1) = span(s, 1.9, 2.05)
        p.append(head.box(x0, 0.0, -3.4, x1, 0.8, -2.4, shut ? face : (full ? V3(0.6, 0.44, 0.16) : V3(0.1, 0.08, 0.05)), shut ? 12 : 7))
        if full && !shut { let (px0, px1) = span(s, 1.97, 2.1); p.append(head.box(px0, 0.3, -3.2, px1, 0.5, -2.6, V3(0.04, 0.03, 0.03), 7)) }
    }
    // Ears out to the sides, drooping, with a twitch.
    let tw: Float = max(0, sinf(m.animT * 1.1 + r0 * 9) - 0.92) * 3
    for s in [-1, 1] as [Float] {
        let ear = head.at(V3(s * 1.9, 0.6, -0.6), 0)
        let (x0, x1) = span(s, 0, 2.6)
        p.append(ear.box(x0, -0.35, -0.6, x1, 0.45, 0.5, face, 12, rz: -s * 0.45 + s * tw))
    }
    // Tail: a short woolly tail, swishing a little.
    let sw: Float = sinf(m.callTimer * 2.1) * 0.15 * idle + sinf(ph) * 0.08 * amt
    let tail = ModelJoint(o: V3(0, 19 + bob - s0, 9.6 - s0), a: -0.15)
    p.append(tail.box(-1.1, -4.5, -0.4, 1.1, 0.4, 1.2, fl, 2, rz: sw))
    return p
}

// MARK: Chicken

func chickenParts(_ m: Mob) -> [Part] {
    let lv = MobDetail.level
    let full = lv == 0, far = lv == 2
    let fv = FarmVariant.climate(m.variant)
    let r0 = m.coatRoll(1)
    let chick = m.baby
    var plume: V3, tailC: V3
    switch fv {
    case 2: plume = V3(0.74, 0.43, 0.21); tailC = V3(0.14, 0.13, 0.12)
    case 3: plume = V3(0.62, 0.66, 0.72); tailC = V3(0.32, 0.34, 0.38)
    default:
        if r0 < 0.7 { plume = V3(0.95, 0.94, 0.9); tailC = plume } else { plume = V3(0.64, 0.35, 0.16); tailC = V3(0.1, 0.1, 0.1) }
    }
    if chick { plume = V3(0.98, 0.86, 0.42); tailC = plume }
    let legC = V3(0.92, 0.68, 0.22), comb = V3(0.82, 0.12, 0.1), beak = V3(0.9, 0.74, 0.38)

    let amt = m.walkAmount, ph = m.walkPhase
    let pw = grazeWindow(m, from: 1, to: 4.5)
    let peck: Float = pw * (0.62 + 0.38 * sinf(m.animT * 7.5))
    let flap: Float = m.onGround ? 0 : sinf(m.walkPhase * 6 + m.hurt * 30) * 0.9
    var p: [Part] = []
    p.reserveCapacity(40)
    // Legs: the feathered drumstick from inside the body, the bare scaled shank, three toes forward and one back.
    for (s, off) in [(Float(-1), Float(0)), (1, .pi)] {
        let lp: Float = ph + off
        let a: Float = sinf(lp) * 0.6 * amt - 0.25
        let la: Float = a + 0.4 + max(0, cosf(lp)) * 0.7 * amt
        let thigh = ModelJoint(o: V3(s * 1.2, 5.0, 0.6), a: a)
        if !far { p.append(thigh.box(-1.0, -2.4, -1.2, 1.0, 0.6, 1.2, plume, 3)) }
        let shank = thigh.at(V3(0, -2.2, 0), la - a)
        p.append(shank.box(-0.32, -2.9, -0.32, 0.32, 0.3, 0.32, legC, 10))
        let foot = shank.at(V3(0, -2.9, 0), -la)
        p.append(foot.box(-0.28, 0, -2.0, 0.28, 0.35, 0.2, legC * 0.92, 10))
        if !far {
            p.append(foot.box(-1.0, 0, -1.5, -0.45, 0.3, -0.2, legC * 0.92, 10))
            p.append(foot.box(0.45, 0, -1.5, 1.0, 0.3, -0.2, legC * 0.92, 10))
            if full { p.append(foot.box(-0.2, 0, 0.1, 0.2, 0.28, 0.9, legC * 0.92, 10)) }
        }
    }
    // Body: carried tilted, breast forward and the back rising to the tail; it tips forward to peck.
    let body = ModelJoint(o: V3(0, 5.0, 0.6), a: -peck * 0.35)
    func bb(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pt: Float = 3) {
        p.append(body.box(x0, y0 - 5.0, z0 - 0.6, x1, y1 - 5.0, z1 - 0.6, c, pt))
    }
    bb(-2.6, 4.6, -3.4, 2.6, 9.4, 3.6, plume)
    bb(-2.3, 4.4, -4.4, 2.3, 8.6, -2.4, plume)                                       // breast
    if !far {
        bb(-2.2, 8.6, 0.5, 2.2, 10.0, 4.2, plume)                                    // back
        bb(-2.2, 5.2, 3.6, 2.2, 9.4, 5.0, plume)                                     // rump
    }
    if !chick {
        let tail = body.at(V3(0, 9.2 - 5.0, 4.4 - 0.6), 0.4 + peck * 0.35 + sinf(ph * 2) * 0.05 * amt)
        p.append(tail.box(-1.1, -0.6, -1.2, 1.1, 3.8, 0.8, tailC, 3))
        if full { p.append(tail.box(-0.7, 2.6, -0.8, 0.7, 4.8, 1.4, tailC * 0.9, 3)) }
    }
    // Wings folded at the sides, beating when it flutters down.
    for s in [-1, 1] as [Float] {
        let wing = body.at(V3(s * 2.6, 9.0 - 5.0, -2.4 - 0.6), 0)
        let (x0, x1) = span(s, 0, 0.6)
        p.append(wing.box(x0, -3.6, 0, x1, 0.2, 5.8, plume * 0.96, 3, rz: s * flap))
        if full && !chick { let (tx0, tx1) = span(s, 0.02, 0.64); p.append(wing.box(tx0, -3.4, 4.2, tx1, -1.6, 6.2, tailC * 0.9, 3, rz: s * flap)) }
    }
    // Neck and head: the head bobs back and forth as it walks; pecking takes the beak to the ground.
    let bobN: Float = sinf(ph * 2) * 0.25 * amt
    let nA: Float = -0.25 - peck * 2.35 + bobN
    let neck = body.at(V3(0, 8.6 - 5.0, -3.0 - 0.6), nA + peck * 0.35)
    p.append(neck.box(-1.2, -0.8, -1.4, 1.2, 3.6, 1.0, plume, 3))
    let hA: Float = -peck * 1.25 - bobN * 0.5
    let head = neck.at(V3(0, 3.4, -0.2), hA - nA)
    p.append(head.box(-1.3, -0.4, -2.1, 1.3, 2.2, 0.8, plume, 3))
    p.append(head.box(-0.5, 0.4, -3.4, 0.5, 1.2, -2.0, beak, 7))
    if far { return p }
    p.append(head.box(-0.42, 0.0, -3.0, 0.42, 0.45, -2.0, beak * 0.9, 7))
    if !chick {
        p.append(head.box(-0.3, 2.1, -1.9, 0.3, 3.3, 0.4, comb, 4))
        p.append(head.box(-0.55, -1.2, -2.3, -0.08, 0.1, -1.6, comb, 4))
        p.append(head.box(0.08, -1.2, -2.3, 0.55, 0.1, -1.6, comb, 4))
        if full {
            for z: Float in [-1.7, -0.8, 0.0] { p.append(head.box(-0.28, 3.3, z, 0.28, 3.8, z + 0.55, comb, 4)) }
        }
    }
    let shut = m.blinking && full
    for s in [-1, 1] as [Float] {
        let (x0, x1) = span(s, 1.3, 1.42)
        p.append(head.box(x0, 1.0, -1.3, x1, 1.7, -0.5, shut ? plume : V3(0.78, 0.46, 0.1), shut ? 3 : 7))
        if full && !shut { let (px0, px1) = span(s, 1.36, 1.46); p.append(head.box(px0, 1.15, -1.1, px1, 1.55, -0.7, V3(0.04, 0.03, 0.03), 7)) }
        if full && !chick { let (lx0, lx1) = span(s, 1.3, 1.4); p.append(head.box(lx0, 0.2, -0.6, lx1, 0.7, 0.0, r0 < 0.7 && fv == 1 ? V3(0.92, 0.9, 0.86) : comb, 4)) }
    }
    return p
}
