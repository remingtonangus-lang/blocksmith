import Foundation
import simd

// P185 (Oct 13 13:21: "make the zombies look less like Minecraft; scarier"): the zombie and the husk as gaunt, hunched
// dead men instead of a green box figure. Tall and thin on long legs, the back bent forward from the hips so the head
// hangs ahead of the body and droops to one side; arms too long, reaching at different heights, with hooked fingers;
// the shirt rotted away over a sunken chest where the ribs show; a jaw hanging open over a row of teeth; small dim
// ember eyes deep in dark sockets; lank strands of hair; one shoe lost. Original design (no reference art).
func walkerParts(_ m: Mob, swing: Float) -> [Part] {
    let husk = m.kind == .husk
    let lawman = DeadSheriff.isOne(m)                        // P483: the Dead Sheriff (DeadSheriff.swift)
    let skin = husk ? V3(0.58, 0.5, 0.36) : V3(0.45, 0.5, 0.42)
    let bruise = husk ? V3(0.4, 0.31, 0.2) : V3(0.3, 0.32, 0.3)
    let shirt = husk ? V3(0.46, 0.38, 0.26) : lawman ? V3(0.12, 0.11, 0.1) : V3(0.27, 0.3, 0.29)
    let pants = husk ? V3(0.36, 0.3, 0.22) : V3(0.2, 0.2, 0.24)
    let dark = V3(0.05, 0.04, 0.04), bone = V3(0.74, 0.7, 0.6), hair = husk ? V3(0.24, 0.2, 0.15) : V3(0.12, 0.12, 0.11)
    let ember = V3(1.0, 0.42, 0.16) * (m.aggro ? 1.0 : 0.75)
    let legH: Float = 13, limb: Float = 3
    // The hunch: the upper body turns about the hips (model faces -Z; a negative rotX leans it forward).
    let hunch: Float = m.aggro ? -0.42 : -0.32
    let hip = V3(0, legH, 0)
    func up(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float = 4) -> Part {
        Part(mn: V3(x, legH + y, z), mx: V3(x + w, legH + y + h, z + d), pivot: hip, rotX: hunch, color: c, pattern: pat)
    }
    // Where a point of the upper body (height above the hips, depth) ends up after the hunch.
    func bent(_ x: Float, _ y: Float, _ z: Float) -> V3 {
        V3(x, legH + cosf(hunch) * y - sinf(hunch) * z, sinf(hunch) * y + cosf(hunch) * z)
    }
    var p: [Part] = []
    // Legs: thin, the left in a torn trouser leg, the right foot bare.
    p += [Part(mn: V3(-limb - 0.4, 0, -limb / 2), mx: V3(-0.4, legH, limb / 2), pivot: V3(-limb / 2 - 0.4, legH, 0), rotX: swing, color: pants, pattern: 4),
          Part(mn: V3(0.4, 0, -limb / 2), mx: V3(limb + 0.4, legH, limb / 2), pivot: V3(limb / 2 + 0.4, legH, 0), rotX: -swing, color: pants, pattern: 4),
          Part(mn: V3(0.3, 0, -limb / 2 - 0.1), mx: V3(limb + 0.5, 4.5, limb / 2 + 0.1), pivot: V3(limb / 2 + 0.4, legH, 0), rotX: -swing, color: skin, pattern: 4),
          Part(mn: V3(-limb - 0.55, 0, -limb / 2 - 0.9), mx: V3(-0.25, 1.6, limb / 2 + 0.15), pivot: V3(-limb / 2 - 0.4, legH, 0), rotX: swing, color: V3(0.15, 0.12, 0.1)),
          Part(mn: V3(0.35, 0, -limb / 2 - 0.8), mx: V3(limb + 0.45, 0.9, limb / 2), pivot: V3(limb / 2 + 0.4, legH, 0), rotX: -swing, color: skin * 0.8, pattern: 4)]
    // Pelvis and the rope of a belt.
    p += [up(-3.6, -0.5, -1.6, 7.2, 2.5, 3.2, pants), up(-3.7, 1.4, -1.7, 7.4, 0.7, 3.4, V3(0.3, 0.24, 0.16), 0)]
    // Torso: a narrow sunken chest; the rotted shirt hangs off the shoulders, open over the ribs.
    p += [up(-3.3, 2, -1.5, 6.6, 10, 3, skin),
          up(-3.0, 3.5, -1.62, 6.0, 6.5, 0.15, dark, 0),                                     // the hollow under the ribs
          up(-3.1, 4.0, -1.75, 6.2, 0.7, 0.25, bone, 5), up(-3.1, 5.6, -1.75, 6.2, 0.7, 0.25, bone, 5),
          up(-3.1, 7.2, -1.75, 6.2, 0.7, 0.25, bone, 5), up(-0.4, 3.8, -1.8, 0.8, 5.5, 0.3, bone * 0.9, 5),   // ribs, breastbone
          up(-3.7, 8.5, -1.9, 2.2, 3.6, 3.8, shirt), up(1.5, 8.5, -1.9, 2.2, 3.6, 3.8, shirt),         // shirt over the shoulders
          up(-3.7, 2.0, 1.4, 7.4, 10.2, 0.6, shirt),                                                  // the back of the shirt
          up(-3.6, 4.5, -1.95, 1.2, 4.2, 0.3, shirt * 0.8), up(2.6, 2.5, -1.95, 1.0, 6.5, 0.3, shirt * 0.8),   // tatters
          up(-2.2, 9.6, -1.7, 4.4, 1.2, 0.2, bruise),                                                 // the collarbones' shadow
          up(-1.2, 12, -1.0, 2.4, 1.6, 2.0, skin * 0.85)]                                           // the neck
    // Arms: from the bent shoulders, too long, one reaching higher than the other; claw-like fingers.
    let reach: Float = 1.45 + (m.aggro ? 0.1 : 0)
    let twitch = sinf(m.walkPhase * 1.7) * 0.12
    for side: Float in [-1, 1] {
        let sh = bent(side * 4.4, 10.5, 0)
        // (The Dead Sheriff's gun arm comes up level at you while he aims, and kicks with the shot.)
        let aiming = lawman && side > 0 && (m.town.aim > 0 || m.town.swing > 0)
        let a = aiming ? 1.57 + m.town.swing * 1.5 : reach + hunch * 0.25 + (side < 0 ? 0.12 : -0.14)              // reaching out ahead of the bent body + (side < 0 ? twitch : -twitch) + (m.attackCooldown > 0.6 ? -0.5 : 0)
        let x0 = side < 0 ? sh.x - limb + 0.6 : sh.x - 0.6
        let len: Float = 15.5
        func arm(_ dx: Float, _ y0: Float, _ y1: Float, _ dz0: Float, _ dz1: Float, _ w: Float, _ c: V3, _ pat: Float = 4) -> Part {
            Part(mn: V3(x0 + dx, sh.y - y1, sh.z + dz0), mx: V3(x0 + dx + w, sh.y - y0, sh.z + dz1), pivot: sh, rotX: a, color: c, pattern: pat)
        }
        p += [arm(0, 0, 5.5, -1.6, 1.6, limb + 0.2, shirt),                                         // the sleeve stump
              arm(0.25, 4.5, len, -1.2, 1.2, limb - 0.3, skin),                                     // bare forearm
              arm(0.1, 9, 10.5, -1.35, 1.35, limb - 0.1, bruise)]                                   // a dark wrist band of rot
        if lawman && side > 0 {
            // His six-iron: the grip in the fist, the cylinder and the long barrel on along the arm.
            let iron = DeadSheriff.iron
            p += [arm(0.2, len - 1.2, len + 1.6, -1.3, 1.3, limb - 0.2, skin * 0.75),                 // the fist round the grip
                  arm(0.4, len + 1.2, len + 3.2, -1.0, 1.0, 2.0, iron, 0),                           // the cylinder
                  arm(0.85, len + 3.0, len + 8.0, -0.5, 0.5, 1.0, iron, 0),                          // the barrel
                  arm(0.4, len + 0.4, len + 1.6, 0.9, 2.6, 1.2, V3(0.32, 0.22, 0.14))]               // the walnut grip
            continue
        }
        // Three hooked fingers and a thumb past the hand.
        for f in 0..<3 {
            let fx = Float(f) * 0.9
            p.append(arm(0.1 + fx, len, len + 2.6, -0.4, 0.4, 0.6, skin * 0.75))
            p.append(arm(0.1 + fx, len + 2.2, len + 2.9, -1.0, -0.2, 0.6, bone * 0.8, 0))           // the nails, curled in
        }
        p.append(arm(side < 0 ? limb - 0.6 : -0.1, len - 1.5, len + 1.0, -1.2, -0.6, 0.6, skin * 0.75))
    }
    // The head: hung forward from the neck, drooping and cocked to one side.
    let neck = bent(0, 13.2, -0.6)
    let droop: Float = hunch * 0.7 - 0.12, tilt: Float = 0.2 + sinf(m.walkPhase * 0.5) * 0.04
    func hd(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float = 4) -> Part {
        Part(mn: neck + V3(x, y, z), mx: neck + V3(x + w, y + h, z + d), pivot: neck, rotX: droop, rotZ: tilt, color: c, pattern: pat)
    }
    p += [hd(-3.4, 0, -4.2, 6.8, 7.6, 6.8, skin),                                                 // the skull
          hd(-3.5, 5.6, -4.3, 7.0, 2.4, 7.0, hair, 15),                                           // lank hair, thinning
          hd(-3.6, 1.5, -2.5, 0.8, 5.0, 4.8, hair, 15), hd(2.8, 0.8, -2.0, 0.8, 5.6, 4.6, hair, 15),
          hd(-2.0, -1.8, 2.0, 1.0, 3.4, 0.6, hair, 15), hd(1.2, -2.6, 1.8, 0.8, 4.2, 0.6, hair, 15),    // strands down the neck
          hd(-1.6, 5.8, -4.35, 3.2, 1.4, 0.2, skin * 0.8),                                         // a bare patch of scalp
          // Deep sockets with small ember eyes, a sunken nose, the brow ridge.
          hd(-3.0, 3.3, -4.3, 2.5, 2.1, 0.2, dark, 0), hd(0.5, 3.3, -4.3, 2.5, 2.1, 0.2, dark, 0),
          hd(-2.1, 3.9, -4.36, 0.8, 0.8, 0.1, ember, 9), hd(1.4, 3.9, -4.36, 0.8, 0.8, 0.1, ember, 9),
          hd(-3.2, 5.3, -4.45, 6.4, 0.7, 0.4, skin * 0.75), hd(-0.5, 2.4, -4.5, 1.0, 0.9, 0.3, dark, 0),
          hd(-3.4, 1.8, -4.25, 1.4, 1.6, 0.2, bruise), hd(2.1, 1.6, -4.25, 1.3, 1.8, 0.2, bruise),   // hollow cheeks
          // The jaw hangs open: the upper teeth, a black mouth, the lower jaw dropped with its own teeth.
          hd(-2.2, 1.2, -4.32, 4.4, 0.6, 0.2, bone, 0),
          hd(-2.2, -0.6, -4.3, 4.4, 1.8, 0.2, dark, 0),
          hd(-2.6, -1.9, -4.0, 5.2, 1.4, 4.2, skin * 0.88),
          hd(-2.0, -0.7, -4.15, 4.0, 0.5, 0.2, bone * 0.9, 0)]
    if lawman {
        // The wide-brimmed hat, crown and band, pulled down on the drooping head; the tarnished star on the waistcoat.
        p += [hd(-6.0, 7.2, -6.8, 12.0, 0.6, 12.0, DeadSheriff.hat),
              hd(-3.7, 7.6, -4.5, 7.4, 3.4, 7.2, DeadSheriff.hat),
              hd(-3.75, 7.7, -4.55, 7.5, 0.7, 7.3, DeadSheriff.band, 0),
              up(-3.0, 7.6, -2.0, 1.6, 1.6, 0.25, DeadSheriff.star, 9)]
    }
    // Rot and old blood: dark patches on the skin and the cloth.
    p += [up(1.8, 6.0, -1.7, 1.3, 2.4, 0.2, V3(0.22, 0.08, 0.06)), up(-3.0, 9.0, 1.9, 2.0, 1.8, 0.2, V3(0.22, 0.08, 0.06), 0)]
    return p
}
