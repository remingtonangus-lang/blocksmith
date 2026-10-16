import Foundation
import simd

// L3 part 2 (docs/status/vr-combat-feel.md): how VR melee and the bow feel. Pure rules and game state here (shared, so
// questcheck and the Mac `--swingtest` check what the headset runs); QuestControls feeds them and draws.
//  - Enemy wind-ups (VR only): a melee mob in reach first rears back for windUpTime with a grunt, then strikes only if
//    you are still in reach: stepping or leaning out of the way dodges it. A blade meeting it while it winds up parries.
//  - Hit feel: a landed blade freezes the mob for a hit-stop, and the haptic tells flesh, armour and bone or stone apart.
//  - The blade trail: a short fading ribbon behind a fast blade.
//  - The bow: the arrow slides onto the string, the limbs creak as they bend, the string shivers after the shot.
//  - First-use tutorials for Swing and Reclined melee; Reclined's soft aim-assist cone.

enum HitFeel: Int {
    case flesh = 0, armour, hard           // hard: bone, stone, iron, wood (skeletons, golems)

    // (amplitude, seconds, frequency) of the blade-contact haptic, scaled by the swing's power.
    func haptic(power: Float) -> (Float, Float, Float) {
        switch self {
        case .flesh: return (min(1, 0.55 + 0.35 * power), 0.07, 160)     // a deep thud
        case .armour: return (min(1, 0.6 + 0.35 * power), 0.045, 320)    // a sharp ring
        case .hard: return (min(1, 0.5 + 0.3 * power), 0.035, 260)       // a short knock
        }
    }

    static let hardKinds: Set<MobKind> = [.skeleton, .stray, .witherSkeleton, .bogged, .skeletonHorse, .ironGolem, .snowGolem,
                                          .copperGolem, .shulker, .creaking, .blaze, .breeze, .armorStand, .parched]
    static func of(_ m: Mob) -> HitFeel {
        if hardKinds.contains(m.kind) { return .hard }
        // Worn armour (equipment or Steelhold plate), not the zombie family's natural 2 points.
        var worn = m.steelholdArmor.0
        if let e = m.equip { for s in e.prefix(4) where !s.isEmpty { worn += s.def.armor } }
        return worn >= 4 ? .armour : .flesh
    }
}

// The last few blade poses for the trail: a fixed ring (no allocation per frame). A sample counts only while the blade
// is lit: the tip's speed, smoothed over a few frames, rises to VRMelee.minTipSpeed and the trail stays lit until it
// falls below VRMelee.rearmSpeed (P77: tracking jitter around the threshold flipped the ribbon on and off every frame,
// a white strobe while moving the sword). Each sample fades out over `life` seconds.
struct BladeTrail {
    static let count = 12
    static let life: Float = 0.14
    static let peakAlpha: Float = 0.32
    var base = [V3](repeating: .zero, count: count), tip = [V3](repeating: .zero, count: count)
    var time = [Double](repeating: -10, count: count)
    var fast = [Bool](repeating: false, count: count)
    var head = 0
    var smooth: Float = 0, lit = false

    mutating func add(base b: V3, tip t: V3, speed: Float, now: Double) {
        smooth = 0.6 * speed + 0.4 * smooth
        lit = lit ? smooth >= VRMelee.rearmSpeed : smooth >= VRMelee.minTipSpeed
        base[head] = b; tip[head] = t; time[head] = now; fast[head] = lit
        head = (head + 1) % BladeTrail.count
    }
    mutating func clear() { for i in 0..<BladeTrail.count { time[i] = -10; fast[i] = false }; smooth = 0; lit = false }

    // Visits each ribbon segment from the newest back: (base0, tip0, base1, tip1, alpha0, alpha1). A segment needs
    // both its samples lit and young; alpha falls from peakAlpha at the blade to 0 at `life` seconds old.
    func segments(now: Double, _ body: (V3, V3, V3, V3, Float, Float) -> Void) {
        func alpha(_ i: Int) -> Float { BladeTrail.peakAlpha * max(0, 1 - Float(now - time[i]) / BladeTrail.life) }
        for k in 0..<(BladeTrail.count - 1) {
            let i = (head - 1 - k + 2 * BladeTrail.count) % BladeTrail.count
            let j = (i - 1 + BladeTrail.count) % BladeTrail.count
            guard fast[i] && fast[j] && time[i] > time[j] else { break }
            let ai = alpha(i), aj = alpha(j)
            guard ai > 0.01 else { break }
            body(base[i], tip[i], base[j], tip[j], ai, aj)
        }
    }
    func segmentCount(now: Double) -> Int { var n = 0; segments(now: now) { _, _, _, _, _, _ in n += 1 }; return n }
}

extension VRBow {
    static let nockTime: Float = 0.12          // the arrow slides back onto the string
    static let creaks: [Float] = [0.35, 0.65, 0.9]

    // How far the arrow still sits ahead of the string while nocking (metres), t seconds after it was nocked.
    static func nockSlide(_ t: Float) -> Float {
        let k = max(0, min(1, t / nockTime))
        return 0.22 * (1 - k) * (1 - k)
    }
    // The string's middle shivering sideways after the shot (metres): a damped 28 Hz wobble, gone in 0.4 s.
    static func stringWobble(_ t: Float, draw: Float) -> Float {
        guard t >= 0 && t < 0.4 else { return 0 }
        return 0.035 * draw * expf(-t * 11) * sinf(t * 2 * .pi * 28)
    }
    // The creak threshold the draw just crossed going back (nil: none).
    static func creak(from a: Float, to b: Float) -> Float? { creaks.first { a < $0 && b >= $0 } }
}

extension VRMelee {
    static let windUpTime: Float = 0.4          // a mob's rear-back before a melee strike (VR)
    static let dodgeGrace: Float = 0.3          // still this close past its reach when the strike comes: it lands
    static let hitStop: Float = 0.06            // a landed blade freezes the mob this long
    static let parryStagger: Float = 1.3        // a parried mob can't strike again for this long
    static let reclinedCone: Float = 0.97       // Reclined aim assist: within ~14 degrees of the laser (swords outside it: 10)
}

extension Game {
    // Enemy wind-ups are for VR, where you dodge with your body (vrHead is set by the Quest controls).
    var meleeWindUps: Bool { vrHead != nil }

    // A melee mob's strike gate (Mob.update's melee branches): true when the strike lands now. Off VR: in reach with
    // the cooldown ready (as before). In VR: in reach with the cooldown ready starts a wind-up (the rear-back pose and
    // a grunt); when it ends the strike lands only if the player is still within reach + dodgeGrace, else it's dodged.
    func meleeStrike(_ m: Mob, reach: Float) -> Bool {
        let gap = meleeGap(m)
        guard meleeWindUps else { m.windUp = 0; m.windUpDone = false; return gap < reach && m.attackCooldown <= 0 }
        if m.windUp > 0 { return false }
        if m.windUpDone {
            m.windUpDone = false
            // P308: a feint breaks off (and the real one comes straight after); a blade across the strike takes it.
            if m.feint { m.feint = false; m.attackCooldown = 0.2; SwordPlay.feints += 1; return false }
            if gap < reach + VRMelee.dodgeGrace { return !bladeBlocks(m) }
            m.attackCooldown = 0.5                 // dodged: a beat before it tries again
            dodges += 1
            return false
        }
        if gap < reach && m.attackCooldown <= 0 {
            startWindUp(m)                          // P308: high or low, a feint now and then, a quick counter
            sfx(.meleeWindUp, 0.8, at: m.pos + V3(0, m.height * 0.7, 0))
        }
        return false
    }

    // A blade meeting a mob that is winding up, at its upper body (where its arms or weapon are), parries: no damage,
    // the strike is cancelled, the mob is pushed back and staggered, a clang. Returns true when it parried.
    func tryParry(_ m: Mob, at point: V3, along dir: V3) -> Bool {
        guard m.windUp > 0, point.y >= m.pos.y + m.height * 0.45 else { return false }
        m.windUp = 0; m.windUpDone = false
        m.attackCooldown = VRMelee.parryStagger
        let push = V3(dir.x, 0, dir.z)
        let away = simd_length_squared(push) > 1e-6 ? simd_normalize(push) : simd_normalize(V3(m.pos.x - player.pos.x, 0, m.pos.z - player.pos.z) + V3(1e-4, 0, 0))
        m.vel += away * 5 + V3(0, 2, 0)
        m.hitStop = VRMelee.hitStop
        parries += 1
        sfx(.parryClang, 1, at: point)
        particles.bladeSpark(at: point, along: dir, power: 1.3)
        return true
    }

    // Reclined melee (VR, Swing melee off): the soft aim assist. The nearest hostile in sight within the cone of the
    // laser and the melee reach; friendly creatures never (aim straight at them to hit one).
    func reclinedAssist(reach: Float) -> (Mob, Float)? {
        guard vrHead != nil, !swingMelee, !held.isEmpty, VRMelee.isSwingWeapon(Items.key(held.item)) else { return nil }
        var best: (Mob, Float)?
        let eye = player.eye, look = player.look
        for m in mobs.mobs where isCreature(m) && bladeFree(m) {
            let c = m.pos + V3(0, m.height * 0.5, 0) - eye
            let d = simd_length(c)
            guard d < reach + m.halfW, d > 0.1, simd_dot(c / d, look) > VRMelee.reclinedCone, d < (best?.1 ?? .greatestFiniteMagnitude) else { continue }
            guard world.canSee(eye, m.pos + V3(0, m.height * 0.5, 0)) else { continue }
            best = (m, d)
        }
        return best
    }
}
