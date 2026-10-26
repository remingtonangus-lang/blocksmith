import Foundation
import simd

// VR combat geometry (Quest; docs/status/vr-melee.md). Pure functions, so the Mac `--swingtest` and the Quest sim
// (quest/src/test/QuestSim.swift) check the same code the headset runs.
//
// Swing melee: the held weapon, tool or fist is a capsule from the hand along the drawn blade, a little longer and
// thicker than drawn (generous but physical). It hurts a mob only when the capsule, swept from last frame's pose to
// this one, touches the mob's box while the tip moves at minTipSpeed or more relative to the head, within `reach` of
// the eyes and in plain sight. It never touches blocks: blocks only break from the trigger.
enum VRMelee {
    static let minTipSpeed: Float = 2.0      // m/s relative to the head: slower is a touch (a light buzz), not a hit
    static let rearmSpeed: Float = 1.2       // the tip slowing below this ends the swing (each mob is hit once per swing)
    // P459 (Oct 25 17:05, "Classify as a hit is way too generous... I'm just pretty much helicoptering my hand here. I'm
    // just absolutely destroying these guys"): a wrist twirled in circles kept the tip over minTipSpeed, so the swing
    // never ended, its wind-up bonus grew to the full x1.4, and the fat, long capsule caught every mob in reach again
    // each 0.16 s. Now a mob takes the blade again only after 0.45 s (about two cuts a second), the capsule is closer
    // to the drawn blade, the wind-up counts from the last hit, and the power follows the hand's own speed as well as
    // the tip's (handLever): a cut needs the arm behind it, a wrist flick only grazes.
    static let rehit: Double = 0.45          // ... or this long after the hit: a fast back-and-forth lands about two cuts a second
    static let reach: Float = 3.0            // eyes to the contact point, blocks (the reference melee reach)
    static let bladeScale: Float = 1.15      // hit capsule length vs the drawn blade
    static let bladeRadius: Float = 0.14
    // The tip of a blade swung from the shoulder moves about 2.5 times as fast as the hand; spun from the wrist, many
    // times. The swing's speed for a hit and its power is the tip's, capped at handLever times the hand's.
    static let handLever: Float = 3
    static func swingSpeed(tip: Float, hand: Float) -> Float { min(tip, hand * handLever) }
    static let fistLength: Float = 0.15, fistRadius: Float = 0.15
    static let weaponHostileGuard: Float = 6 // a melee weapon never mines with a hostile this close (blocks)
    static let weaponMobGuard: Float = 3     // ... or any other creature this close (a cow 4 blocks off is fine)

    // The Quest options page's text (QuestOptions), here so the Mac `--swingtest` can check it fits the pause menu.
    static let optionHelp = "Swing: hit mobs by swinging your weapon into them. Reclined: no swinging, the trigger attacks."
    static let reclinedPostureHelp = "Lying Down View: Recenter levels the view to your gaze. On: Reclined melee, snap turns, a vignette."
    static let touchRows = ["Swing melee: swing the blade into mobs", "Reclined melee: trigger attacks",
                            "Main trigger: mine / fire (both modes)", "Bow: off-hand trigger at string, pull"]

    // Damage scale from the tip speed, linear (Oct 12 PM P136, "damage in the sword should vary linearly with the speed"):
    // tip speed / 4.5 m/s, so 0.45 at the minimum, 1 at 4.5 m/s, 2 at 9 m/s and over. On top of the attack charge, so a
    // middling swing deals about what Reclined's trigger does.
    static let powerAt1: Float = 4.5, powerMin: Float = 0.45, powerMax: Float = 2
    static func power(_ tipSpeed: Float) -> Float { max(powerMin, min(powerMax, tipSpeed / powerAt1)) }
    // ... times the wind-up (P136, "how much the sword moved before it hit"): the tip's path since this swing began, up to
    // x1.4 for a full 1.4 m arc; a jab of a hand's width adds nothing.
    static func travelBonus(_ metres: Float) -> Float { 1 + max(0, min(0.4, (metres - 0.3) * 0.36)) }
    // Head hits (P136, "if you aim at their head with a sword, do more"): x1.5 where the blade lands on the head: the top
    // fifth of an upright body, the front of a beast's upper half.
    static let headMult: Float = 1.5
    static var headHits = 0
    static func headHit(_ m: Mob, at p: V3) -> Bool {
        let rel = p - m.pos
        if m.height >= m.halfW * 4.5 { return rel.y >= m.height * 0.8 }          // upright: zombies, Powderwights, people
        let ahead = simd_dot(V3(rel.x, 0, rel.z), m.forward)
        return rel.y >= m.height * 0.45 && ahead >= m.halfW * 0.35
    }
    // A swung hit's attack charge is at least this: quick re-swings land weaker hits instead of none (P13/P16).
    static let swingChargeFloor: Float = 0.5

    // Real melee weapons, the only items that hit by blade contact in Swing melee (anything else, the fist included,
    // attacks with the trigger as in Reclined).
    static func isSwingWeapon(_ key: String) -> Bool {
        key.hasSuffix("_sword") || key.hasSuffix("_axe") || key == "mace" || key == "trident" || key.hasSuffix("_spear")
    }

    // The hit capsule (base, tip, radius) for a hand pose. `size` is the drawn icon half size and `tool` whether it is
    // held by the handle (QuestControls.heldSize); the blade runs along the icon's diagonal like drawHeld draws it.
    static func blade(handPos: V3, handRot: simd_quatf, size: Float, tool: Bool) -> (V3, V3, Float) {
        guard tool && size > 0 else {
            return (handPos, handPos + handRot.act(V3(0, 0, -fistLength)), fistRadius)
        }
        let r = handRot.act(simd_normalize(V3(0, 0.15, -1))), up = handRot.act(simd_normalize(V3(0, 1, 0.15)))
        let grip = handPos + handRot.act(V3(0, 0.01, -0.03))
        let base = grip + (r * 0.22 + up * 0.1) * size                     // just above the hand: the handle doesn't hit
        let tipK = size * bladeScale
        let tip = grip + (r * 1.62 + up * 1.5) * tipK
        return (base, tip, bladeRadius)
    }

    // Entry fraction 0...1 of the segment p -> q into the box [mn, mx], nil if it misses.
    static func segmentBox(_ p: V3, _ q: V3, _ mn: V3, _ mx: V3) -> Float? {
        let d = q - p
        var t0: Float = 0, t1: Float = 1
        for a in 0..<3 {
            if abs(d[a]) < 1e-7 {
                if p[a] < mn[a] || p[a] > mx[a] { return nil }
                continue
            }
            var ta = (mn[a] - p[a]) / d[a], tb = (mx[a] - p[a]) / d[a]
            if ta > tb { swap(&ta, &tb) }
            t0 = max(t0, ta); t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        return t0
    }

    // The blade (base a, tip b) swept from last frame (a0, b0) to this one (a1, b1) against the box grown by the blade's
    // radius, in sub-steps no farther apart than the radius: a fast swing can't pass through a mob between two frames.
    // Returns the first contact point.
    static func sweepHit(a0: V3, b0: V3, a1: V3, b1: V3, radius: Float, mn: V3, mx: V3) -> V3? {
        let r = V3(repeating: radius)
        let lo = mn - r, hi = mx + r
        let move = max(simd_length(a1 - a0), simd_length(b1 - b0))
        let n = max(1, min(32, Int(ceilf(move / max(0.05, radius)))))
        for i in 0...n {
            let t = Float(i) / Float(n)
            let a = a0 + (a1 - a0) * t, b = b0 + (b1 - b0) * t
            if let s = segmentBox(a, b, lo, hi) { return a + (b - a) * s }
        }
        return nil
    }
}

// The VR bow: held in the aiming hand, drawn by the other hand. The limbs stand across the arrow in the plane of the
// bow hand's up axis; the string runs from the tips to the nock, which follows the drawing hand back (up to a full
// draw); the arrow points from the drawing hand through the grip, and flies that way when let go.
enum VRBow {
    static let halfHeight: Float = 0.6       // grip to tip (the bow is 1.2 m, larger than life like the other tools)
    static let brace: Float = 0.15           // string to grip at rest
    static let fullDraw: Float = 0.68        // grip to nock at full draw
    static let nockRange: Float = 0.3        // the drawing hand within this of the resting string nocks an arrow
    static let arrowLength: Float = 0.8

    struct Pose {
        var grip: V3, dir: V3, up: V3
        var nock: V3
        var draw: Float                       // 0 rest ... 1 full
        var tipTop: V3, tipBottom: V3
        // A point on the limbs, u -1 (bottom tip) ... 1 (top tip): the grip is foremost, the tips bend back to the string.
        func limb(_ u: Float) -> V3 {
            grip + up * (VRBow.halfHeight * u * (1 - 0.1 * draw)) - dir * ((VRBow.brace + 0.07 * draw) * u * u)
        }
    }

    // grip: the bow hand's grip point; handRot: its aim rotation (-Z forward, +Y up); drawHand: the drawing hand while an
    // arrow is nocked (nil at rest). Any space (tracking or world) as long as all three share it.
    static func pose(grip: V3, handRot: simd_quatf, drawHand: V3?) -> Pose {
        let fwd = handRot.act(V3(0, 0, -1))
        var dir = fwd
        var len = brace
        // Only a pull back behind the grip draws: the hand's depth along the bow's rear axis, within 60 degrees of it.
        // A hand ahead of the grip (or out to the side) leaves the string at rest: no draw, no shot.
        if let h = drawHand {
            let d = grip - h
            let l = simd_length(d)
            let back = simd_dot(d, fwd)
            if l > 0.05 && back > brace * 0.5 && back >= l * 0.5 {
                dir = d / l
                len = max(brace, min(fullDraw, back))
            }
        }
        var draw = (len - brace) / (fullDraw - brace)
        if draw > 0.97 { draw = 1 }
        let up0 = handRot.act(V3(0, 1, 0))
        var up = up0 - dir * simd_dot(up0, dir)
        if simd_length_squared(up) < 1e-6 { let s = handRot.act(V3(1, 0, 0)); up = s - dir * simd_dot(s, dir) }
        up = simd_normalize(up)
        var p = Pose(grip: grip, dir: dir, up: up, nock: grip - dir * len, draw: draw, tipTop: .zero, tipBottom: .zero)
        p.tipTop = p.limb(1); p.tipBottom = p.limb(-1)
        return p
    }

    // Where the string sits at rest (the nocking spot) for a bow hand pose.
    static func restNock(grip: V3, handRot: simd_quatf) -> V3 { grip - handRot.act(V3(0, 0, -1)) * brace }
}

extension Game {
    // A melee weapon in VR: Swing melee hits with its blade; it never mines with a creature near (Game.interact).
    var vrWeaponHeld: Bool { bufferAttacks && !held.isEmpty && VRMelee.isSwingWeapon(Items.key(held.item)) }
    // Swing melee with a weapon in hand: only its blade's contact attacks creatures; the trigger mines, fires and
    // still hits non-living things (armor stands, boats, minecarts). Anything else held attacks with the trigger.
    var meleeContactOnly: Bool { swingMelee && vrWeaponHeld }

    // A creature (not the mount, a boat, a minecart, an armor stand or another vehicle).
    func isCreature(_ m: Mob) -> Bool { m.health > 0 && m !== riding && m.kind != .boat && m.kind.spec.behavior != .vehicle }
    // A creature the blade may hit from a casual swing: hostile, not tamed, a neutral one only once provoked.
    // Villagers, townsfolk, golems, animals and pets need the trigger held during the swing.
    func bladeFree(_ m: Mob) -> Bool {
        let b = m.kind.spec.behavior
        return m.kind.hostile && !m.tamed && ((b != .neutral && b != .enderman && b != .piglin) || m.aggro)
    }

    // The weapon mining guard: a hostile within weaponHostileGuard, or any other creature within weaponMobGuard.
    // Axes are tools too: only a hostile stops them, so a tree still chops with a cow beside it.
    func creatureNearForWeapon() -> Bool {
        let p = player.pos
        let axe = Items.key(held.item).hasSuffix("_axe")
        return mobs.mobs.contains { m in
            guard isCreature(m), !axe || m.kind.hostile else { return false }
            let r = m.kind.hostile ? VRMelee.weaponHostileGuard : VRMelee.weaponMobGuard
            return simd_length_squared(m.pos - p) < r * r
        }
    }

    // Where mobs walk and face (Mob.update; their reach is meleeGap): the player's feet, or in VR the column under the
    // headset (seated leaning moves the head without moving the player), at most 0.5 m from the feet.
    var meleeBody: V3 {
        guard let h = vrHead else { return player.pos }
        var d = V2(h.x - player.pos.x, h.z - player.pos.z)
        let l = simd_length(d)
        if l > 0.5 { d *= 0.5 / l }
        return V3(player.pos.x + d.x, player.pos.y, player.pos.z + d.y)
    }

    // A melee hit that did damage (Game.interact): the hit mob flashes white-hot for Mob.hitFlashTime (distinct from the
    // red hurt tint) and sparks fly from the contact point along the swing. Quest: the blade's contact point and sweep
    // (QuestControls.swingContact, with its haptic); the Mac and pads: the near side of the mob along the look.
    // A fist or a non-weapon (sparks false): a dimmer, shorter flash and no sparks.
    func bladeFlash(_ m: Mob, at point: V3? = nil, along dir: V3? = nil, power: Float = 1, sparks: Bool = true) {
        m.hitFlash = Mob.hitFlashTime * (sparks ? 1 : 0.55)
        guard sparks else { return }
        let c = point ?? (m.pos + V3(0, m.height * 0.6, 0) - V3(player.look.x, 0, player.look.z) * m.halfW)
        particles.bladeSpark(at: c, along: dir ?? player.look, power: min(1.3, max(0.3, power)))
        // A red streak where the blade cut, along the swing (P16).
        particles.slashMark(at: c, along: dir ?? player.look, toward: player.eye, power: min(1.4, max(0.5, power)), on: m)
    }

    // How far a mob's arms are from the player's body, for melee reach (Mob.update): the horizontal distance from the
    // mob's centre to the part of the player's body level with the mob (its feet to its top, as the reference attack box:
    // inflated sideways, not up). The body is a segment from the feet to the headset in VR (wherever the head leans, no
    // clamp) or to the eyes on the Mac. Leaning in over a zombie gets hit, a mob on a ledge reaches down to the head, a
    // player on a 2-block pillar or the floor above is out of reach (infinite gap).
    func meleeGap(_ m: Mob) -> Float {
        let f = player.pos
        let d = (vrHead ?? player.eye) - f
        let lo = m.pos.y, hi = m.pos.y + m.height
        // The stretch t0...t1 of the body (0 feet, 1 head) whose height is within the mob's.
        var t0: Float = 0, t1: Float = 1
        if abs(d.y) < 1e-4 {
            if f.y < lo || f.y > hi { return .greatestFiniteMagnitude }
        } else {
            let a = (lo - f.y) / d.y, b = (hi - f.y) / d.y
            t0 = max(0, min(a, b)); t1 = min(1, max(a, b))
            if t0 > t1 { return .greatestFiniteMagnitude }
        }
        // Closest point of that stretch to the mob's centre, sideways.
        let h = V2(d.x, d.z), r = V2(m.pos.x - f.x, m.pos.z - f.z)
        let hh: Float = simd_dot(h, h)
        let t: Float = hh < 1e-8 ? t0 : min(t1, max(t0, simd_dot(r, h) / hh))
        return simd_length(r - h * t)
    }

    // The first living mob the swept blade touches, within VRMelee.reach of `eye` and in sight of it (world space).
    // `except`: mobs already hit by this swing; `deliberate`: the trigger is held (friendly creatures may be hit too).
    func bladeContact(a0: V3, b0: V3, a1: V3, b1: V3, radius: Float, eye: V3, except: [ObjectIdentifier], deliberate: Bool = false) -> (Mob, V3)? {
        let lo = simd_min(simd_min(a0, b0), simd_min(a1, b1)) - V3(repeating: radius)
        let hi = simd_max(simd_max(a0, b0), simd_max(a1, b1)) + V3(repeating: radius)
        var best: (Mob, V3, Float)?
        for m in mobs.mobs where isCreature(m) && (deliberate || bladeFree(m)) {
            let mn = V3(m.pos.x - m.halfW, m.pos.y, m.pos.z - m.halfW)
            let mx = V3(m.pos.x + m.halfW, m.pos.y + m.height, m.pos.z + m.halfW)
            guard mx.x >= lo.x && mn.x <= hi.x && mx.y >= lo.y && mn.y <= hi.y && mx.z >= lo.z && mn.z <= hi.z else { continue }
            guard !except.contains(ObjectIdentifier(m)) else { continue }
            guard let p = VRMelee.sweepHit(a0: a0, b0: b0, a1: a1, b1: b1, radius: radius, mn: mn, mx: mx) else { continue }
            let d = simd_length(p - eye)
            // Sight to the contact point on the mob itself: the grown box reaches below its feet, so an uppercut or a
            // low target's contact point sat inside the floor and was never in sight (Oct 11 playtest P13/P16).
            let onMob = simd_clamp(p, mn + V3(0.02, 0.1, 0.02), mx - V3(0.02, 0.02, 0.02))
            guard d <= VRMelee.reach, d < (best?.2 ?? .greatestFiniteMagnitude),
                  world.canSee(eye, onMob) || world.canSee(eye, m.pos + V3(0, m.height * 0.5, 0)) else { continue }
            best = (m, p, d)
        }
        return best.map { ($0.0, $0.1) }
    }
}
