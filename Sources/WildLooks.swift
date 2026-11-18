import Foundation
import simd

// Ledger 332 and 333 (Nov 17 evening playtest, 20:11:14-18, flying over the Snowy Slopes and Jagged Peaks: "They make
// the polar bears a little more scary here." ... "Mountain goats don't look good enough"): the polar bear and the
// mountain goat were each a box on four posts with a box for a head (a two-pixel snout, two sticks for horns). Rebuilt
// to the farm animals' standard (FarmLooks.swift: jointed legs, a neck carrying the head, a face with a jaw, eyes and
// lids, idle life, three levels of detail):
//   the polar bear: heavy shoulders over a long low neck, the head carried low and forward, a long muzzle with a black
//     nose and lips, small ears, broad paws with black claws; now and then it bares its teeth, and angry it drops its
//     head, raises its hackles and opens its jaws on its fangs;
//   the mountain goat: a shaggy white coat with a hump at the shoulders, long hair on the upper legs ("pants") and under
//     the belly, a long face with a beard hanging from the chin, slender black horns sweeping back, black hooves; it
//     grazes and chews like the farm animals.
// Units 1/16 block, feet at y 0, the model faces -Z; Part rotation as in Mob.swift. BS_OLDWILDLOOKS=1: the old boxes.
enum WildLooks {
    static let old = Env.all["BS_OLDWILDLOOKS"] == "1"

    // The bear's snarl, 0...1: angry, always; otherwise for a moment now and then at its own beat.
    static func snarl(_ m: Mob) -> Float {
        if m.aggro || m.strikeT > 0 { return 1 }
        let t: Float = sinf(m.animT * 0.37 + m.coatRoll(41) * 6.28)
        return max(0, min(1, (t - 0.94) * 22))
    }
}

// One leg as farmLeg draws it (upper leg about the hip, lower leg and foot about the knee), with claws on the foot.
private func wildLeg(_ p: inout [Part], hip: V3, a: Float, la: Float, lu: Float, ll: Float, lh: Float, uw: Float, ud: Float,
                     lw: Float, hw: Float, upper: V3, lower: V3, foot: V3, pat: Float, lpat: Float, fpat: Float, top: Float, claw: V3?) {
    let thigh = ModelJoint(o: hip, a: a)
    if MobDetail.level == 2 {
        let w: Float = (uw + lw) * 0.5
        p.append(thigh.box(-w / 2, -(lu + ll + lh), -w / 2, w / 2, top, w / 2, lower, lpat))
        return
    }
    p.append(thigh.box(-uw / 2, -lu - 0.4, -ud / 2, uw / 2, top, ud / 2, upper, pat))
    let knee = thigh.at(V3(0, -lu, 0), la - a)
    p.append(knee.box(-lw / 2, -ll, -lw / 2, lw / 2, 0.4, lw / 2, lower, lpat))
    p.append(knee.box(-hw / 2, -ll - lh, -hw / 2 - 0.3, hw / 2, -ll, min(hw / 2, lw / 2 + 0.2), foot, fpat))   // (heel flush: a long foot rocked under the knee dug in)
    if let c = claw, MobDetail.level == 0 {
        let y0: Float = -ll - lh + 0.1, z0: Float = -hw / 2 - 0.3
        for x in [-hw / 2 + 0.2, -0.35, hw / 2 - 0.9] as [Float] {
            p.append(knee.box(x, y0, z0 - 0.45, x + 0.7, y0 + 0.65, z0 + 0.3, c, 7))     // (short: a long claw rocked down as the fore knee folds)
        }
    }
}

@inline(__always) private func wspan(_ s: Float, _ a: Float, _ b: Float) -> (Float, Float) { s > 0 ? (a, b) : (-b, -a) }

// MARK: Polar bear

func polarBearParts(_ m: Mob) -> [Part] {
    let lv = MobDetail.level
    let full = lv == 0, far = lv == 2
    let coat = V3(0.94, 0.93, 0.86), under = V3(0.86, 0.84, 0.76), skin = V3(0.07, 0.07, 0.08)
    let mouth = V3(0.42, 0.11, 0.12), tooth = V3(0.93, 0.91, 0.82)
    let amt = m.walkAmount, ph = m.walkPhase
    let snarl = WildLooks.snarl(m)
    let angry: Float = m.aggro ? 1 : 0
    let gait = FarmGait(ph: ph, amt: amt, amp: 0.36 * amt, hock: 0.12)   // (a heavy, short stride)
    let bob: Float = abs(sinf(ph)) * 0.35 * amt
    let hipY: Float = 11.7, lu: Float = 5.6, ll: Float = 4.6, lh: Float = 1.2
    let top: Float = 23 + bob, bot: Float = 9.5 + bob
    var p: [Part] = []
    p.reserveCapacity(64)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pt: Float) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pt))
    }
    // Body: deep shoulders, a long barrel, the rump a little lower; long fur hangs under the belly.
    b(-7.0, bot, -13, 7.0, top, -2.5, coat, 4)                                   // shoulders and chest
    b(-7.4, bot + 0.4, -6, 7.4, top - 0.8, 6, coat, 4)                           // barrel
    b(-7.0, bot + 1.0, 3, 7.0, top - 2.0, 13, coat, 4)                           // rump
    if !far {
        b(-4.6, top - 0.6, -11.5, 4.6, top + 1.4 + angry * 1.2, -4.5, coat, 15)  // the shoulder hump (hackles up, angry)
        b(-6.2, bot - 1.6, -10, 6.2, bot + 0.8, 9.5, under, 15)                  // long belly fur
        b(-1.4, top - 3.6, 12.4, 1.4, top - 1.6, 14.0, coat, 15)                 // the stub of a tail
    }
    // Legs: thick, the fore paws turned a little in, broad feet with black claws.
    let legs: [(Float, Float, Float, Bool)] = [(-4.7, -9.0, 0, true), (4.7, -9.0, .pi, true), (-4.9, 8.8, .pi, false), (4.9, 8.8, 0, false)]
    for (x, z, off, front) in legs {
        let (a, la) = gait.leg(off, front: front)
        wildLeg(&p, hip: V3(x, hipY + bob, z), a: a, la: la, lu: lu, ll: ll, lh: lh, uw: front ? 5.4 : 6.0, ud: front ? 5.8 : 7.0,
                lw: 4.4, hw: 5.0, upper: coat, lower: coat, foot: under, pat: 4, lpat: 4, fpat: 4, top: 3, claw: skin)
    }
    // Neck: long and low from the shoulders, swinging with the walk; angry, it drops the head and thrusts it out.
    let sway: Float = sinf(ph) * 0.05 * amt
    let nA: Float = -1.38 - 0.22 * angry - sway
    let nL: Float = 7.5
    let neck = ModelJoint(o: V3(0, top - 4.5, -12), a: nA)
    p.append(neck.box(-4.2, -2.0, -3.8, 4.2, nL + 0.8, 3.8, coat, 4))
    // Head: carried near level, the long muzzle forward; a snarl lifts the nose.
    let hA: Float = -0.1 + 0.15 * snarl
    let head = neck.at(V3(0, nL, 0), hA - nA)
    p.append(head.box(-3.8, -3.2, -5.6, 3.8, 2.6, 1.2, coat, 4))                 // skull and cheeks
    p.append(head.box(-2.5, -3.0, -10.6, 2.5, 0.6, -5.2, coat, 4))               // muzzle
    if !far { p.append(head.box(-3.4, 1.7, -6.0, 3.4, 2.5, -5.2, under, 4)) }    // brow
    p.append(head.box(-1.1, -0.6, -10.9, 1.1, 0.7, -10.3, skin, 7))              // nose
    // The jaw: shut, lips black; open on the fangs as it snarls.
    let jaw = head.at(V3(0, -3.0, -5.0), -(0.06 + 0.62 * snarl))
    p.append(jaw.box(-2.3, -1.6, -5.5, 2.3, 0.0, 0.0, coat, 4))
    if !far {
        p.append(head.box(-2.55, -3.1, -10.4, 2.55, -2.6, -5.6, skin))           // upper lip
        p.append(jaw.box(-2.35, -0.25, -5.6, 2.35, 0.25, -4.9, skin))            // lower lip
    }
    if snarl > 0.05 && !far {
        p.append(head.box(-2.0, -2.95, -10.0, 2.0, -2.75, -5.3, mouth))          // the roof of the mouth
        p.append(jaw.box(-2.0, -0.4, -4.8, 2.0, -0.15, -0.4, mouth))             // tongue
        if full {
            for s in [-1, 1] as [Float] {
                let (x0, x1) = wspan(s, 1.3, 2.1)
                p.append(head.box(x0, -4.1, -10.0, x1, -2.9, -9.3, tooth, 7))      // upper fangs
                p.append(jaw.box(x0, -0.1, -5.1, x1, 1.0, -4.4, tooth, 7))       // lower fangs
            }
        }
    }
    // Eyes: small and dark, set forward on the skull, a lid now and then; ears small and round.
    let shut = m.blinking && full && snarl < 0.1
    for s in [-1, 1] as [Float] {
        let (x0, x1) = wspan(s, 1.5, 2.4)
        p.append(head.box(x0, 0.75, -5.75, x1, 1.55, -5.6, shut ? coat : skin, shut ? 4 : 7))
        let (ex0, ex1) = wspan(s, 2.2, 3.6)
        p.append(head.box(ex0, 2.3, -1.4, ex1, 3.7 - angry * 0.5, -0.2, coat, 4))
        if full { let (ix0, ix1) = wspan(s, 2.5, 3.3); p.append(head.box(ix0, 2.5, -1.5, ix1, 3.4 - angry * 0.5, -1.38, under * 0.8)) }
    }
    return p
}

// MARK: Mountain goat

func goatParts(_ m: Mob) -> [Part] {
    let lv = MobDetail.level
    let full = lv == 0, far = lv == 2
    let coat = V3(0.94, 0.93, 0.88), shag = V3(0.9, 0.89, 0.83), face = V3(0.96, 0.95, 0.91)
    let horn = V3(0.1, 0.09, 0.09), hoof = V3(0.12, 0.11, 0.1), eye = V3(0.06, 0.05, 0.04)
    let amt = m.walkAmount, ph = m.walkPhase
    let idle: Float = max(0, 1 - amt * 2)
    let gait = FarmGait(ph: ph, amt: amt, amp: 0.5 * amt, hock: 0.16)
    let graze = goatGraze(m)
    let hipY: Float = 10.5, lu: Float = 5.0, ll: Float = 4.4, lh: Float = 1.2
    let bob: Float = abs(sinf(ph)) * 0.3 * amt
    let top: Float = 19.5 + bob, bot: Float = 10 + bob
    var p: [Part] = []
    p.reserveCapacity(60)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pt: Float) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pt))
    }
    // Body: a deep chest under a hump at the shoulders, a narrow rump; a skirt of long hair under the belly.
    b(-4.0, bot, -8.6, 4.0, top + 0.4, -2.5, coat, 15)                           // chest and shoulders
    b(-4.2, bot + 0.6, -5, 4.2, top - 0.8, 5, coat, 15)                          // barrel
    b(-3.8, bot + 1.2, 3, 3.8, top - 1.2, 8.2, coat, 15)                         // rump
    b(-3.0, top, -8.0, 3.0, top + 2.2, -3.0, shag, 15)                           // the hump
    if !far {
        b(-4.5, bot - 2.2, -7.5, 4.5, bot + 1.0, 6.5, shag, 15)                  // the skirt
        b(-2.2, bot - 1.6, -9.0, 2.2, bot + 3.0, -7.0, shag, 15)                 // the shaggy brisket
    }
    // Legs: long hair to the knee, slim below, black hooves.
    let legs: [(Float, Float, Float, Bool)] = [(-2.5, -6.4, 0, true), (2.5, -6.4, .pi, true), (-2.5, 5.6, .pi, false), (2.5, 5.6, 0, false)]
    for (x, z, off, front) in legs {
        let (a, la) = gait.leg(off, front: front)
        wildLeg(&p, hip: V3(x, hipY + bob, z), a: a, la: la, lu: lu, ll: ll, lh: lh, uw: front ? 3.4 : 3.6, ud: front ? 3.8 : 4.4,
                lw: 1.7, hw: 2.1, upper: shag, lower: coat, foot: hoof, pat: 15, lpat: 4, fpat: 7, top: 2.5, claw: nil)
    }
    // Neck: thick and short, forward from the hump; lowered to graze.
    let nod: Float = sinf(ph * 2) * 0.06 * amt
    let nA: Float = -0.7 - nod - graze * 1.25
    let nL: Float = 5.5
    let neck = ModelJoint(o: V3(0, top - 3.2, -8.0), a: nA)
    p.append(neck.box(-2.3, -1.4, -2.8, 2.3, nL + 0.6, 2.6, coat, 15))
    if !far { p.append(neck.box(-1.6, -0.6, -3.8, 1.6, nL - 0.4, -2.6, shag, 15)) }    // the throat's long hair
    // Head: a long face angled down, a little more as it grazes.
    let hA: Float = -0.5 + nod * 0.5 - graze * 0.75
    let head = neck.at(V3(0, nL, 0), hA - nA)
    p.append(head.box(-2.0, -2.2, -4.0, 2.0, 1.8, 0.8, face, 4))                 // skull
    p.append(head.box(-1.5, -2.0, -8.2, 1.5, 0.7, -3.8, face, 4))                // face
    p.append(head.box(-1.35, -2.3, -9.8, 1.35, -0.2, -7.9, face, 4))             // muzzle
    p.append(head.box(-0.95, -1.5, -9.95, 0.95, -0.5, -9.75, eye, 7))            // nose
    let chew: Float = -(0.5 + 0.5 * sinf(m.animT * 7)) * 0.12 * idle
    let jaw = head.at(V3(0, -2.2, -3.8), chew)
    p.append(jaw.box(-1.2, -0.7, -5.8, 1.2, 0.2, 0, face, 4))
    // The beard hangs straight down from the chin, swaying as it walks.
    let beard = head.at(V3(0, -2.2, -7.2), -hA + sinf(ph) * 0.12 * amt)
    p.append(beard.box(-1.1, -4.6, -1.2, 1.1, 0.4, 1.4, shag, 15))
    // Horns: slender and black, up from the brow and sweeping back.
    for s in [-1, 1] as [Float] {
        let base = head.at(V3(s * 1.05, 1.5, -2.4), 0.95)
        p.append(base.box(-0.55, 0, -0.55, 0.55, 3.4, 0.55, horn, 7))
        if !far {
            let tip = base.at(V3(0, 3.2, 0), 0.55)
            p.append(tip.box(-0.4, 0, -0.4, 0.4, 2.6, 0.4, horn, 7))
        }
    }
    if far { return p }
    // Eyes on the sides of the head, lids now and then; ears out to the sides, flicking.
    let shut = m.blinking && full
    for s in [-1, 1] as [Float] {
        let (x0, x1) = wspan(s, 1.85, 2.05)
        p.append(head.box(x0, -0.2, -4.4, x1, 0.8, -3.1, shut ? face : eye, shut ? 4 : 7))
        let flick: Float = max(0, sinf(m.animT * 1.1 + m.coatRoll(5) * 6) - 0.9) * 3
        let ear = head.at(V3(s * 1.9, 1.0, -0.6), 0)
        let (ex0, ex1) = wspan(s, 0, 2.5)
        p.append(ear.box(ex0, -0.45, -0.8, ex1, 0.45, 0.4, face, 4, rz: -s * 0.25 + s * flick))
    }
    if full { p.append(head.box(-1.0, -2.25, -9.9, 1.0, -2.05, -8.6, eye * 2.5)) }  // the mouth line
    // Tail: short, held down, flicking at rest.
    let tail = ModelJoint(o: V3(0, top - 1.6, 8.0), a: -0.35 + sinf(m.animT * 2.1) * 0.15 * idle)
    p.append(tail.box(-0.8, -2.6, -0.5, 0.8, 0.4, 1.1, shag, 15))
    return p
}

// The goat's grazing window (FarmLooks' rule): the last seconds before each call, head down, eased; never while it
// runs, panics or watches you.
private func goatGraze(_ m: Mob) -> Float {
    let clock = m.callTimer
    let idle: Float = max(0, 1 - m.walkAmount * 2)
    let watch: Float = max(0, 1 - 2.5 * (abs(m.headYaw) + abs(m.headPitch)))
    let w: Float = max(0, min(1, min(clock - 1.5, 7 - clock) * 1.5))
    return w * idle * watch * (m.panic > 0 || m.aggro ? 0 : 1)
}
