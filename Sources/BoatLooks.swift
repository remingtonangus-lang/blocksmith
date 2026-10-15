import Foundation
import simd

// H9 Boats: see yourself in the boat, and a boat that looks like its icon.
// - The hull follows the inventory icon (ItemShapes "boat"): a tapered, clinker-built hull narrowing in steps to a dark
//   keel, bow and stern both swept up into light tips, ribbed plank strakes, a light gunwale, floor boards and a thwart.
// - The player riding it is drawn seated in it as part of the boat's model, so the body rocks with the hull: thighs over
//   the thwart, shins down to the boards, boots on the floor, in every view (the VR chase view, Mac first and third person).
// - Head and arms are left out while the camera is in the head (first person, the headset), so the body never blocks the
//   view; from outside (chase / third person / photo) the head turns with the look and the arms work the paddles.
// - The standing third-person body (writePlayerModel) steps aside while seated, so there is only ever one body.
enum BoatLooks {
    static weak var rider: Mob?          // the boat the local player sits in (Mob.updateBoat keeps it current)
    static weak var game: Game?

    static func track(_ m: Mob, _ g: Game, ridden: Bool) {
        if ridden { rider = m; game = g } else if rider === m { rider = nil }
    }

    // Whether the boat's model draws the player (writePlayerModel then draws nothing).
    static func drawsRider(_ g: Game) -> Bool {
        guard let r = rider, let m = g.riding, m === r, m.kind == .boat, m.health > 0 else { return false }
        return true
    }

    // Every box of a boat as drawn: hull, paddles, chest, the seated rider; tilted by its rock on the waves.
    static func parts(_ m: Mob) -> [Part] {
        var p = hull(m)
        if let g = game, rider === m, g.riding === m, m.health > 0 { p += seated(g, m) }
        let r = m.boatRock
        if r.x != 0 || r.y != 0 { rock(&p, pitch: r.x, roll: r.y) }
        return p
    }

    // The hull, model space (1/16 block, faces -Z): the icon's side view built up in strakes.
    static func hull(_ m: Mob) -> [Part] {
        let c = Boats.color(m.variant)
        let light: V3 = simd_min(c * 1.2 + V3(repeating: 0.04), V3(repeating: 1))
        let band: V3 = c * 0.84
        let dark: V3 = c * 0.72
        let keel: V3 = c * 0.5
        var p: [Part] = []
        p.reserveCapacity(64)
        p.append(box(-1, 0, -9, 2, 1, 18, keel))                    // keel (the icon's dark bottom row)
        p.append(box(-5, 1, -11, 10, 2, 22, dark))                  // bottom planking
        p.append(box(-4, 3, -9, 8, 0.25, 18, c * 0.92))             // floor boards
        // A strake: four walls of thickness t round a hull `hw` wide and `hl` long (half sizes), each wider and longer
        // than the one below it, so the hull tapers to the keel like the icon.
        func ring(_ y: Float, _ h: Float, _ hw: Float, _ hl: Float, _ t: Float, _ col: V3) {
            p.append(box(-hw, y, -hl, t, h, 2 * hl, col))
            p.append(box(hw - t, y, -hl, t, h, 2 * hl, col))
            p.append(box(-hw + t, y, -hl, 2 * (hw - t), h, t, col))
            p.append(box(-hw + t, y, hl - t, 2 * (hw - t), h, t, col))
        }
        ring(3, 2, 7, 12, 3, band)
        ring(5, 2, 8, 13, 2, c)
        ring(7, 2, 9, 14, 1, band)
        ring(9, 1, 9.3, 14.3, 1.3, light)                           // gunwale
        // Rib heads along the banded strakes (the icon's "=#=#" rows).
        for z: Float in [-9, -3, 3, 9] {
            p.append(box(-7.3, 3.5, z - 0.5, 0.3, 1, 1, dark)); p.append(box(7, 3.5, z - 0.5, 0.3, 1, 1, dark))
            p.append(box(-9.3, 7.5, z + 1.5, 0.3, 1, 1, dark)); p.append(box(9, 7.5, z + 1.5, 0.3, 1, 1, dark))
        }
        // Stem and stern post, both swept up above the gunwale into a light tip (the icon's raised ends).
        for s: Float in [-1, 1] {
            p.append(box(-2, 3, s < 0 ? -14.5 : 12, 4, 6, 2.5, dark))
            p.append(box(-1.5, 7, s < 0 ? -16 : 13.5, 3, 4, 2.5, c))
            p.append(box(-1, 9, s < 0 ? -17.5 : 15, 2, 4, 2.5, light))
        }
        p.append(box(-8, 6, 1, 16, 1.5, 4, light))                  // thwart (the rider's seat)
        // Paddles in oarlocks on the gunwale: the handle forward by the rider, the blade aft, dipping as they row.
        let row = sinf(m.walkPhase)
        let dip: Float = 0.5 + row * 0.35
        // P282 (c): the rider's right hand on a weapon lets its paddle rest shipped in the oarlock.
        var rightFree = true
        if let g = game, rider === m, g.riding === m, !g.held.isEmpty { rightFree = false }
        for s: Float in [-1, 1] {
            let x = s * 9.8
            let piv = V3(x, 10, 0)
            let d: Float = s > 0 && !rightFree ? 0.15 : dip
            p.append(Part(mn: V3(x - 0.5, 9.5, -3), mx: V3(x + 0.5, 10.5, 11), pivot: piv, rotX: d, color: dark))
            p.append(Part(mn: V3(x - 0.25, 8.5, 10), mx: V3(x + 0.25, 11.5, 15), pivot: piv, rotX: d, color: c))
        }
        if m.chested {
            // The icon's chest: amber wood with a dark latch, aft of the rider.
            let wood = V3(0.6, 0.42, 0.16)
            p.append(box(-5, 3, 5.5, 10, 9, 8, wood))
            p.append(box(-5.2, 10.5, 5.3, 10.4, 0.6, 8.4, wood * 0.75))      // lid seam
            p.append(box(-1, 8, 5.1, 2, 2.5, 0.4, V3(0.23, 0.23, 0.23)))
        }
        return p
    }

    // The local player seated on the thwart (model space of the boat): the body of playerParts without its standing
    // legs, moved onto the seat, and bent legs of its own.
    static func seated(_ g: Game, _ m: Mob) -> [Part] {
        let pl = g.player
        // The camera in the head (first person; the headset looking from the player's eye): no head or arms.
        let away: Bool = SoldierRig.eye.map { simd_length($0 - pl.eye) > 1.5 } ?? true
        let row = sinf(m.walkPhase)
        let turn = pl.yaw - m.yaw
        let headYaw = max(-1.3, min(1.3, atan2f(sinf(turn), cosf(turn))))
        let body = playerParts(g, pitch: pl.pitch, walk: 0, hit: playerHitAngle(g.swing))
        let armed = !g.held.isEmpty
        var out: [Part] = []
        out.reserveCapacity(body.count + 6)
        let shift = V3(0, -0.5, 2)                                  // hips on the thwart, a little aft of the middle
        for var q in body {
            let pv = q.pivot
            if pv.y == 12 { continue }                              // standing legs and boots: bent ones below
            let head = pv.y == 24 && pv.x == 0
            let arm = pv.y == 22 && abs(pv.x) == 6                  // (the held item rides with the right arm)
            if (head || arm) && !away { continue }
            if head { q.rotY = headYaw }
            if arm && pv.x > 0 && armed {
                // P282 (c): a weapon in the right hand leaves its paddle: a gun points along the look, a blade is held
                // up ready (and still swings); the left hand keeps rowing and steering.
                q.rotX = g.heldGun != nil ? HandsPose.aim(pl.pitch) : 0.5 + playerHitAngle(g.swing)
                q.rotZ = -0.1
            } else if arm {
                // Reaching out and forward to the paddle handles, pulling with the stroke.
                q.rotX += 0.3 + row * 0.22
                q.rotZ = pv.x > 0 ? 0.33 : -0.33
            }
            q.mn += shift; q.mx += shift; q.pivot += shift
            out.append(q)
        }
        // P276 (Oct 14 19:32, "the armour still looks like shit ... make it look the same as in the inventory"): the
        // bent legs wear the same shells as the standing figure (playerArmorParts): leggings over thigh and shin with
        // the belt's trim, boots with a toe cap and a trimmed cuff, in ArmorLook.style's colours and finishes (the old
        // seat only recoloured the trousers flat).
        let armor = playerArmorOverride ?? g.inventory.armor.slots
        let ls: ArmorLook.Style? = armor.count > 2 && !armor[2].isEmpty ? ArmorLook.style(armor[2]) : nil
        let fs: ArmorLook.Style? = armor.count > 3 && !armor[3].isEmpty ? ArmorLook.style(armor[3]) : nil
        let legs = V3(0.22, 0.22, 0.26), feet = V3(0.35, 0.22, 0.12)
        for left in [true, false] {
            let xa: Float = left ? -4 : 0.01, xb: Float = left ? -0.01 : 4
            out.append(Part(mn: V3(xa, 7.5, -6), mx: V3(xb, 11.5, 4), color: legs, pattern: 4))          // thigh over the thwart
            out.append(Part(mn: V3(xa, 5.5, -8), mx: V3(xb, 10, -4), color: legs, pattern: 4))           // shin down to the boards
            out.append(Part(mn: V3(xa - 0.15, 3.25, -8.3), mx: V3(xb + 0.15, 6, -3.8), color: feet, pattern: 4))   // boot
            // Shells: open on the inner side (no fight with the other leg), like the standing figure's.
            let sa: Float = left ? xa - 0.45 : xa, sb: Float = left ? xb : xb + 0.45
            if let s = ls {
                out.append(Part(mn: V3(sa, 7.05, -6.45), mx: V3(sb, 11.95, 3.6), color: s.color * 0.92, pattern: s.pattern))
                out.append(Part(mn: V3(sa, 6.1, -8.45), mx: V3(sb, 10.45, -4.4), color: s.color * 0.92, pattern: s.pattern))
                out.append(Part(mn: V3(sa - 0.05, 9.6, -6.6), mx: V3(sb + 0.05, 10.9, -4.6), color: s.trim ?? s.color * 0.75,
                                pattern: s.trim == nil ? s.pattern : s.trimPattern))                                  // knee cop
            }
            if let s = fs {
                let ba: Float = left ? xa - 0.65 : xa + 0.01, bb: Float = left ? xb - 0.01 : xb + 0.65
                out.append(Part(mn: V3(ba, 3.1, -8.6), mx: V3(bb, 6.4, -3.6), color: s.color * 0.85, pattern: s.pattern))
                out.append(Part(mn: V3(ba, 3.15, -9.3), mx: V3(bb, 4.6, -8.5), color: s.color * 0.75, pattern: s.pattern))   // toe cap
                if let t = s.trim { out.append(Part(mn: V3(ba - 0.05, 5.8, -8.7), mx: V3(bb + 0.05, 6.6, -3.5), color: t, pattern: s.trimPattern)) }
            }
        }
        return out
    }

    // Tilts every part about the hull's middle: pitch (bow up > 0) about the model's x axis, roll (right side up > 0)
    // about z. A part turning about x only (paddles) composes exactly (Part.rotation = Ry * Rz * Rx); the rider's arms
    // and head, which also turn about z or y, are close enough at these angles.
    static func rock(_ p: inout [Part], pitch: Float, roll: Float) {
        let centre = V3(0, 4, 0)
        let cx = cosf(pitch), sx = sinf(pitch), cz = cosf(roll), sz = sinf(roll)
        let rx = simd_float3x3(V3(1, 0, 0), V3(0, cx, sx), V3(0, -sx, cx))
        let rz = simd_float3x3(V3(cz, sz, 0), V3(-sz, cz, 0), V3(0, 0, 1))
        let rb = rz * rx
        for i in p.indices {
            var q = p[i]
            if q.rotX == 0 && q.rotZ == 0 && q.rotY == 0 {
                q.pivot = centre
            } else {
                let moved: V3 = rb * (q.pivot - centre) + centre
                let d: V3 = moved - q.pivot
                q.mn += d; q.mx += d; q.pivot = moved
            }
            q.rotX += pitch
            q.rotZ += roll
            p[i] = q
        }
    }
}
