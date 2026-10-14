import Foundation
import simd

// P246 (Oct 13 22:00: "zombies look terrific; skeletons need an upgrade, golems need an upgrade, even the creeper guy
// needs an upgrade"): new models in the gaunt, detailed style of the dead men (WalkerModel.swift). Original designs.

// The skeleton (and its frost and sun-scorched kin): real bones instead of a white box figure. Thin leg and arm bones
// with knobbed knees and elbows, paired forearm bones, finger bones; a pelvis and a spine you can see through the gaps
// of the ribcage; a skull with deep sockets holding a pinprick of cold light, a nasal hole, cheekbones, a row of teeth
// and a hinged jaw that chatters. What's left of its gear: a rotted hood and a quiver (skeleton), frost-stiff rags and
// icicles (frost), a sun-bleached head wrap and sash (sun-scorched).
func skeletonParts(_ m: Mob, swing: Float) -> [Part] {
    let frost = m.kind == .stray, sun = m.kind == .parched
    let bone = frost ? V3(0.74, 0.8, 0.84) : (sun ? V3(0.9, 0.83, 0.66) : V3(0.82, 0.8, 0.73))
    let old = bone * 0.82, hole = V3(0.05, 0.05, 0.06)
    let glow: V3 = (frost ? V3(0.7, 1.1, 1.5) : (sun ? V3(1.4, 0.9, 0.4) : V3(1.0, 1.05, 1.2))) * (m.aggro ? 1.2 : 0.8)
    var p: [Part] = []
    // Legs: thigh and shin bones with a knee knob, a flat foot, swinging from the hip.
    let lost = m.lostBones                                            // P247: bones a blade broke off (SkeletonBreak.swift)
    for side: Float in [-1, 1] where lost & (side < 0 ? 4 : 8) == 0 {
        let x = side * 2, pv = V3(x, 12, 0), r = side < 0 ? swing : -swing
        func lb(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3) -> Part {
            Part(mn: V3(x + x0, y0, z0), mx: V3(x + x1, y1, z1), pivot: pv, rotX: r, color: c, pattern: 5)
        }
        p += [lb(-0.7, 6.8, -0.7, 0.7, 12, 0.7, bone),                // thigh
              lb(-1.0, 5.6, -1.1, 1.0, 7.4, 0.9, old),                // knee
              lb(-0.55, 0.8, -0.6, 0.55, 5.8, 0.6, bone),             // shin
              lb(-0.9, 0, -2.4, 0.9, 0.9, 0.9, old)]                  // foot
    }
    // Pelvis, spine and the dark hollow of the chest behind the ribs.
    p += [box(-3.0, 11.2, -1.3, 6, 2.2, 2.6, bone, 5), box(-1.4, 10.6, -1.4, 2.8, 1, 2.6, old, 5),
          box(-0.6, 13, 0.4, 1.2, 11.5, 1.2, old, 5),
          box(-2.6, 14.8, -0.9, 5.2, 8.6, 1.4, hole)]
    // Four ribs a side: around the sides and in to the breastbone at the front, gaps between them.
    for i in 0..<4 {
        let y = 15.2 + Float(i) * 2.1, inset = Float(i == 0 ? 0.3 : 0)
        p += [box(-3.3 + inset, y, -1.6, 0.8, 0.9, 3.0, bone, 5), box(2.5 - inset, y, -1.6, 0.8, 0.9, 3.0, bone, 5),
              box(-3.3 + inset, y + 0.2, -1.9, 2.8, 0.8, 0.5, bone, 5), box(0.5, y + 0.2, -1.9, 2.8 - inset, 0.8, 0.5, bone, 5),
              box(-3.0 + inset, y, 1.2, 2.6, 0.8, 0.5, old, 5), box(0.4, y, 1.2, 2.6 - inset, 0.8, 0.5, old, 5)]
    }
    p += [box(-0.5, 15.8, -2.05, 1, 7.6, 0.5, bone, 5),                                   // breastbone
          box(-4.6, 23.4, -1.4, 9.2, 0.9, 0.9, bone, 5)]                                  // collarbones
    // Arms: a bow held up in both hands while aiming, otherwise hanging and swinging.
    let aim = m.aimHold > 0
    let armFwd: Float = aim ? 1.45 : 0
    let armAngle = armFwd + (aim ? 0 : swing)
    for side: Float in [-1, 1] where lost & (side < 0 ? 1 : 2) == 0 {
        let x = side * 5, sp = V3(x, 22.5, 0)
        let r = side < 0 ? armAngle : (aim ? armAngle : -armAngle)
        func ab(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 5) -> Part {
            Part(mn: V3(x + x0, y0, z0), mx: V3(x + x1, y1, z1), pivot: sp, rotX: r, color: c, pattern: pat)
        }
        p += [ab(-1.1, 22, -1.1, 1.1, 24, 1.1, old),                  // shoulder knob
              ab(-0.6, 16.6, -0.6, 0.6, 22.4, 0.6, bone),            // upper arm
              ab(-0.9, 15.6, -0.9, 0.9, 17.2, 0.9, old),             // elbow
              ab(-0.7, 10.4, -0.55, -0.1, 15.8, 0.05, bone),         // the two forearm bones, a gap between
              ab(0.1, 10.4, -0.05, 0.7, 15.8, 0.55, bone),
              ab(-0.8, 9.0, -0.8, 0.8, 10.6, 0.8, old)]              // wrist and palm
        for f in 0..<3 { p.append(ab(-0.75 + Float(f) * 0.55, 7.2 + Float(f % 2) * 0.4, -0.3, -0.4 + Float(f) * 0.55, 9.1, 0.25, bone)) }
    }
    if lost & 3 == 0 { p += bowParts(x: 5, pivot: V3(5, 22.5, 0), handY: 9.5, rotX: armAngle) }
    // The skull on a short neck: cranium, upper jaw, sockets with a cold pinprick, nose hole, cheekbones, teeth; the
    // lower jaw hinged behind and chattering (wider while it hunts).
    p += [box(-0.6, 24.2, -0.4, 1.2, 1.6, 1.2, old, 5)]
    p += [box(-3.6, 27.0, -3.7, 7.2, 5.2, 7.2, bone, 5),
          box(-3.0, 25.6, -3.9, 6.0, 1.6, 4.6, bone, 5),
          box(-2.9, 27.9, -3.85, 2.0, 2.0, 0.3, hole), box(0.9, 27.9, -3.85, 2.0, 2.0, 0.3, hole),
          box(-2.25, 28.55, -3.95, 0.6, 0.6, 0.2, glow, 9), box(1.65, 28.55, -3.95, 0.6, 0.6, 0.2, glow, 9),
          box(-0.5, 26.7, -3.95, 1.0, 1.1, 0.25, hole),
          box(-3.9, 26.9, -3.2, 1.0, 0.9, 2.6, old, 5), box(2.9, 26.9, -3.2, 1.0, 0.9, 2.6, old, 5),
          box(-3.7, 29.9, -3.95, 7.4, 0.7, 0.3, old, 5),                                  // the brow
          box(-2.2, 25.6, -4.0, 4.4, 0.75, 0.2, bone * 1.05, 5)]
    for t in 0..<3 { p.append(box(-1.25 + Float(t) * 1.1, 25.6, -4.05, 0.18, 0.75, 0.15, hole)) }
    let chatter = (m.aggro ? 0.18 : 0.06) * max(0, sinf(m.walkPhase * 3.1 + m.animT * 2))
    let jp = V3(0, 25.8, 1.2)
    p += [Part(mn: V3(-2.8, 24.3, -3.8), mx: V3(2.8, 25.4, 1.8), pivot: jp, rotX: -chatter, color: bone, pattern: 5),
          Part(mn: V3(-2.0, 25.3, -3.85), mx: V3(2.0, 25.85, -3.6), pivot: jp, rotX: -chatter, color: bone * 1.05, pattern: 5)]
    // What's left of its gear.
    if frost {
        let rag = V3(0.42, 0.5, 0.56), ice = V3(0.8, 0.92, 1.0)
        p += [box(-3.4, 10.4, -1.7, 6.8, 2.6, 3.4, rag, 6), box(-3.2, 7.8, -1.75, 1.6, 2.8, 0.4, rag, 6), box(1.4, 8.4, -1.75, 1.8, 2.2, 0.4, rag, 6),
              box(-5.4, 21.6, -1.6, 2.4, 2.6, 3.2, rag, 6),                                // a frozen shoulder rag
              box(-3.75, 31.6, -3.9, 7.5, 0.9, 7.5, ice, 7),                              // frost on the crown
              box(-1.8, 23.6, -4.0, 0.5, 1.4, 0.5, ice, 7), box(1.2, 23.9, -3.9, 0.45, 1.1, 0.45, ice, 7),   // icicles off the jaw
              box(-2.6, 14.0, -1.95, 0.4, 1.2, 0.4, ice, 7), box(2.1, 13.6, -1.95, 0.4, 1.6, 0.4, ice, 7)]   // and off the ribs
    } else if sun {
        let wrap = V3(0.78, 0.66, 0.46), sash = V3(0.62, 0.3, 0.18)
        p += [box(-3.85, 29.6, -3.95, 7.7, 2.9, 7.7, wrap, 6),                            // the head wrap
              box(-3.85, 26.6, 2.2, 7.7, 3.0, 1.7, wrap, 6), box(-1.0, 22.0, 3.0, 2.2, 5.0, 0.5, wrap, 6),   // its tail down the back
              box(-3.4, 10.6, -1.8, 6.8, 1.6, 3.6, sash, 6), box(1.6, 7.4, -1.85, 1.6, 3.4, 0.4, sash, 6)]
    } else {
        let hood = V3(0.22, 0.17, 0.12), quiver = V3(0.36, 0.22, 0.12)
        p += [box(-3.9, 27.0, 0.6, 7.8, 5.6, 3.3, hood, 6), box(-3.9, 32.0, -2.4, 7.8, 0.7, 6.3, hood, 6),   // the rotted hood
              box(-3.95, 26.0, -1.0, 0.5, 5.2, 4.8, hood, 6), box(3.45, 26.5, -1.0, 0.5, 4.6, 4.8, hood, 6),
              box(-4.6, 21.2, 1.2, 9.2, 2.6, 1.4, hood, 6),                                // the cowl over the shoulders
              Part(mn: V3(-1.4, 14.5, 1.8), mx: V3(1.6, 23.5, 4.2), pivot: V3(0, 19, 3), rotZ: 0.35, color: quiver, pattern: 10),
              Part(mn: V3(-1.0, 23.5, 2.2), mx: V3(-0.2, 26.0, 3.0), pivot: V3(0, 19, 3), rotZ: 0.35, color: V3(0.9, 0.88, 0.82)),
              Part(mn: V3(0.3, 23.5, 2.6), mx: V3(1.1, 25.4, 3.4), pivot: V3(0, 19, 3), rotZ: 0.35, color: V3(0.7, 0.2, 0.15)),
              box(-4.4, 12.6, -2.0, 1.2, 9.6, 0.4, quiver * 0.7)]                          // the quiver strap
    }
    // Both legs gone: the rest of it drags itself along the ground.
    if lost & 12 == 12 {
        for i in p.indices { p[i].mn.y -= 11; p[i].mx.y -= 11; p[i].pivot.y -= 11 }
    }
    return p
}

// The Iron Sentinel (the village guardian, save key "iron_golem"): a riveted ironclad giant rather than a grey stack
// of boxes. Plated column legs with knee guards and broad feet, a skirt of hanging plates, a barrel chest with a furnace
// grille glowing in it, heavy pauldrons, long arms with banded forearms and big knuckled fists, a small head sunk low
// between the shoulders with a lit visor slit, rivet rows, rust streaks, vines the village grew on it, cracks once hurt.
func ironSentinelParts(_ m: Mob, swing: Float) -> [Part] {
    let iron = V3(0.6, 0.6, 0.58), dark = V3(0.34, 0.34, 0.34), rivet = V3(0.78, 0.76, 0.72)
    let rust = V3(0.46, 0.26, 0.13), vine = V3(0.27, 0.48, 0.18), hole = V3(0.05, 0.05, 0.05)
    let hurt = Float(m.health) / Float(max(1, m.spec.health))
    let fire = V3(1.9, 0.85, 0.25) * (0.55 + 0.45 * hurt) * (m.attackCooldown > 0.9 ? 1.35 : 1)
    let strike = m.attackCooldown > 0.9
    let armSwing: Float = strike ? 1.4 : swing * 0.5
    var p: [Part] = []
    for side: Float in [-1, 1] {
        let x = side * 4, pv = V3(x, 16, 0), r = side < 0 ? swing : -swing
        func lg(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 8) -> Part {
            Part(mn: V3(x + x0, y0, z0), mx: V3(x + x1, y1, z1), pivot: pv, rotX: r, color: c, pattern: pat)
        }
        p += [lg(-3, 2, -3, 3, 16, 3, iron),
              lg(-3.4, 0, -4.2, 3.4, 2.2, 3.6, dark),                 // broad foot
              lg(-3.3, 7, -3.6, 3.3, 10.5, -2.9, dark),                // knee guard
              lg(-0.4, 7.8, -3.75, 0.4, 9.6, -3.55, rivet, 0),
              lg(-3.2, 12.5, -3.3, 3.2, 13.3, 3.3, dark)]              // a band at the thigh
    }
    // Skirt of hanging plates, the barrel body, the chest plate with its furnace grille.
    for i in 0..<4 {
        let x = -8 + Float(i) * 4
        p.append(box(x + 0.2, 13.6, -4.4, 3.6, 4.2, 8.6, i % 2 == 0 ? dark : dark * 1.15, 8))
    }
    p += [box(-9, 17, -5.5, 18, 13, 10.5, iron, 8),
          box(-7, 19.5, -6.1, 14, 9.5, 0.7, iron * 1.08, 8),
          box(-3.2, 21.3, -6.35, 6.4, 4.8, 0.3, fire, 9)]
    for b in 0..<3 { p.append(box(-3.4, 21.9 + Float(b) * 1.5, -6.5, 6.8, 0.45, 0.2, hole)) }   // the grille bars
    for y: Float in [20.2, 27.6] {
        for x: Float in [-6.2, -3.2, 2.5, 5.5] { p.append(box(x, y, -6.25, 0.7, 0.7, 0.2, rivet)) }
    }
    p += [box(-9.2, 29.4, -5.7, 18.4, 1.2, 10.9, dark, 8),             // collar band
          box(5.2, 23.0, -6.2, 0.6, 3.8, 0.15, rust), box(-4.6, 18.2, -6.2, 0.5, 3.0, 0.15, rust),
          box(-9.25, 18.5, -3.0, 0.3, 7.0, 0.6, rust)]
    // Arms: pauldron, upper arm, banded forearm, fist with knuckle plates; both raised together to strike.
    for side: Float in [-1, 1] {
        let x = side * 11, sp = V3(x, 30, 0)
        let r = side < 0 ? armSwing : (strike ? armSwing : -armSwing)
        func ar(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 8) -> Part {
            Part(mn: V3(x + x0, y0, z0), mx: V3(x + x1, y1, z1), pivot: sp, rotX: r, color: c, pattern: pat)
        }
        p += [ar(-3.2, 26.5, -4.6, 3.2, 32.5, 4.6, iron * 1.05),         // pauldron
              ar(-2.4, 31.8, -3.6, 2.4, 33.3, 3.6, dark),
              ar(-2, 17, -2.2, 2, 27, 2.2, iron),
              ar(-2.7, 6.5, -2.9, 2.7, 17.5, 2.9, iron),
              ar(-2.9, 13.0, -3.1, 2.9, 14.2, 3.1, dark), ar(-2.9, 9.0, -3.1, 2.9, 10.2, 3.1, dark),
              ar(-3.2, 1.6, -3.6, 3.2, 6.8, 3.6, iron * 0.95),           // fist
              ar(-3.3, 1.4, -3.8, 3.3, 2.8, -2.6, dark)]                 // knuckle plate
        for k in 0..<3 { p.append(ar(-2.4 + Float(k) * 1.8, 1.9, -3.95, -1.6 + Float(k) * 1.8, 2.5, -3.75, rivet, 0)) }
    }
    // The head, low and forward between the shoulders: brow ridge, a lit visor slit, a jaw grille.
    let hp = V3(0, 30, -2)
    let look: Float = m.aggro ? 0.08 : 0
    func hd(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float = 8) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), pivot: hp, rotX: look, color: c, pattern: pat)
    }
    p += [hd(-4, 30, -7.5, 8, 8, 8, iron),
          hd(-4.5, 35.2, -8.0, 9, 1.6, 2.4, dark),
          hd(-3.2, 33.3, -7.65, 6.4, 0.9, 0.2, fire, 9),
          hd(-2.6, 30.7, -7.65, 5.2, 1.9, 0.2, hole, 0),
          hd(-0.5, 33.9, -8.05, 1.0, 2.4, 0.5, iron * 1.1)]               // nose guard
    for k in 0..<3 { p.append(hd(-2.0 + Float(k) * 1.6, 30.7, -7.75, 0.4, 1.9, 0.15, dark)) }
    // Vines the village grew on it, and cracks when it has taken a beating.
    p += [box(-9.3, 17.5, -4.2, 0.4, 7.5, 2.4, vine, 4), box(4.6, 25.5, -6.4, 3.0, 4.4, 0.3, vine, 4),
          box(-6.5, 1.8, -3.9, 2.4, 6.0, 0.3, vine, 4), box(-2.4, 29.6, -5.9, 1.4, 3.2, 0.3, vine, 4)]
    if hurt < 0.6 {
        p += [box(-6.0, 24.0, -6.2, 2.6, 0.35, 0.15, hole), box(-4.0, 22.6, -6.2, 0.35, 1.6, 0.15, hole),
              box(6.0, 18.4, -5.7, 0.35, 3.6, 0.15, hole)]
    }
    if hurt < 0.3 { p += [box(-1.8, 35.0, -7.65, 0.35, 2.0, 0.15, hole), box(2.4, 26.4, -6.35, 2.2, 0.35, 0.15, hole)] }
    return p
}

// More of the Powderwight (look-upgrade part 2 built the dead miner with the keg): ribs through the gaping coat, bony
// hands with hooked fingers, a pick through the belt, a coil of fuse cord over the shoulder, ragged coat tails, rock
// dust caked on the cap and boots. Added to the model in Mob.swift (same hunch pivot).
func powderwightExtras(_ m: Mob, hip: V3, hunch: Float, sy: Float, sz: Float, armRot: Float, swing: Float, lit: Bool) -> [Part] {
    let bone = V3(0.7, 0.68, 0.6), dust = V3(0.48, 0.46, 0.42), haft = V3(0.42, 0.29, 0.15), head = V3(0.36, 0.36, 0.38)
    let cord = V3(0.62, 0.52, 0.3)
    func tb(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float = 0) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), pivot: hip, rotX: hunch, color: c, pattern: pat)
    }
    var p: [Part] = [
        tb(-2.0, 17.6, -2.72, 4.0, 0.6, 0.12, bone, 5), tb(-2.0, 19.0, -2.72, 4.0, 0.6, 0.12, bone, 5),
        tb(-2.0, 20.4, -2.72, 4.0, 0.6, 0.12, bone, 5), tb(-0.3, 17.4, -2.76, 0.6, 3.8, 0.12, bone * 0.9, 5),
        // the pick through the belt: haft down the right hip, the head across
        tb(3.6, 7.5, -1.2, 0.8, 7.5, 0.8, haft, 4), tb(2.2, 14.2, -1.6, 3.8, 1.0, 1.6, head, 8),
        // a coil of fuse cord over the right shoulder and down the chest
        tb(2.2, 20.5, -2.9, 2.6, 2.6, 0.5, cord, 4), tb(3.0, 15.0, -2.85, 0.5, 5.6, 0.3, cord, 4),
        // ragged tails, dust caked on the cap and the boots
        tb(-4.3, 5.2, -2.8, 1.6, 2.0, 0.3, V3(0.26, 0.22, 0.17), 4), tb(1.8, 4.4, -2.8, 1.4, 2.8, 0.3, V3(0.26, 0.22, 0.17), 4),
        tb(-4.05, 29.0, -5.65, 8.1, 0.25, 8.1, dust, 4),
    ]
    let k: Float = 15.9
    for side in [-1, 1] as [Float] {
        let x = side * 5.4, r = armRot + (lit ? 0 : swing * side * 0.8)
        for f in 0..<3 {
            let fx = x - 1.0 + Float(f) * 0.8
            p.append(Part(mn: V3(fx, sy - k, sz - 0.9), mx: V3(fx + 0.5, sy - 13.3, sz - 0.3), pivot: V3(x, sy, sz), rotX: r, color: bone, pattern: 5))
        }
        p.append(Part(mn: V3(x - 1.6, sy - 9.5, sz - 1.6), mx: V3(x + 1.6, sy - 8.4, sz + 1.6), pivot: V3(x, sy, sz), rotX: r,
                      color: V3(0.24, 0.2, 0.15), pattern: 4))                     // a frayed cuff
    }
    p.append(Part(mn: V3(-2.4, 0, -2.6), mx: V3(-0.6, 0.6, 1.2), pivot: V3(-2, 12, 0), rotX: swing, color: dust, pattern: 4))
    p.append(Part(mn: V3(0.6, 0, -2.6), mx: V3(2.4, 0.6, 1.2), pivot: V3(2, 12, 0), rotX: -swing, color: dust, pattern: 4))
    return p
}
