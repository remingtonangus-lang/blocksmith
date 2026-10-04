import Foundation
import simd

// The Capital's soldiers as jointed models: a small skeleton (hips, knees, a torso that leans and twists, shoulders,
// elbows, a head that looks), two-bone IK that puts the hands on the weapon's grip and fore grip, and stances
// chosen from what the soldier is doing (aim, fire, low ready, reload, throw, march, attention / parade rest,
// crew stations). Dress uniforms: white with grey trim, polished boots, silver fittings; each rank reads at a
// distance by its headgear and gear (original designs):
//   Trooper (soldier_recruit)    crested enamel helmet, open face, grey crossbelts, service rifle or carbine
//   Vanguard (soldier_trooper)   visored full helm, enamel cuirass and pauldrons, vambraces, shotgun or rifle
//   Marksman (soldier_marksman)  grey beret, glowing monocular, long coat and capelet, bandolier, scoped rifle
//   Bulwark (soldier_ironclad)   tall crested helm with a glowing slit, full plate, power cell, launcher / arc lance
//   Officer (soldier_officer)    peaked cap, half cape, sash, aiguillette, medals, sabre, one-handed sidearm
//   Pilot (soldier_crew)         white flight helmet with a smoked visor, grey flight suit, harness, sidearm
// Model pixels (1/16 block), feet at y 0, facing -Z; Part rotation convention in Mob.swift (rotX > 0 = forward).

// MARK: Crew station poses (hook for vehicle and ship crews)

// How a soldier stands or sits at a vehicle / ship station. Set `mob.station` (and for the seats `mob.stationSeat`,
// the seat top in blocks above the mob's feet); `.none` hands the body back to its own stances. Only the model
// changes: the caller places the mob (pos, yaw) at the station and keeps it there; brain.pitch steers a gunner's
// head. A seated soldier's weapon is slung on the back (sidearms stay holstered).
enum StationPose: Int, CaseIterable {
    case none = 0
    case seated        // driver / pilot: hands forward on the controls
    case passenger     // troop seat: rifle upright between the knees
    case gunner        // standing at a gun's two handles
    case console       // standing at a console, hands at waist height
    case attention     // drawn up at attention (deck parade, honour guard)
}

extension Mob {
    var station: StationPose {
        get { brain?.station ?? StationPose.none }
        set { soldierBrain.station = newValue }
    }
    var stationSeat: Float {
        get { brain?.seat ?? 0.45 }
        set { soldierBrain.seat = newValue }
    }
}

// MARK: Livery

struct Livery {
    var cloth: V3, legs: V3, trim: V3, plate: V3, dark: V3, metal: V3, accent: V3
    var boots: V3, glove: V3, glass: V3, glow: V3, skin: V3, hair: V3

    static let skins: [V3] = [V3(0.87, 0.68, 0.55), V3(0.74, 0.54, 0.41), V3(0.57, 0.39, 0.27), V3(0.41, 0.27, 0.19), V3(0.93, 0.77, 0.66)]
    static let hairs: [V3] = [V3(0.12, 0.09, 0.07), V3(0.3, 0.2, 0.12), V3(0.55, 0.42, 0.25), V3(0.06, 0.06, 0.06), V3(0.62, 0.6, 0.58)]

    // White dress uniforms with grey trim (the Capital); other factions' crews in their own colours.
    static func of(_ m: Mob, rank r: Int, seed: Int) -> Livery {
        var l = Livery(cloth: V3(0.9, 0.905, 0.915), legs: V3(0.86, 0.865, 0.875), trim: V3(0.52, 0.55, 0.59),
                       plate: V3(0.95, 0.95, 0.94), dark: V3(0.13, 0.14, 0.16), metal: V3(0.8, 0.82, 0.86),
                       accent: V3(0.88, 0.76, 0.46), boots: V3(0.07, 0.07, 0.08), glove: V3(0.94, 0.94, 0.93),
                       glass: V3(0.1, 0.13, 0.17), glow: V3(0.55, 1.55, 1.95),
                       skin: skins[seed % skins.count], hair: hairs[(seed / 7) % hairs.count])
        if r == 5 { l.cloth = V3(0.7, 0.72, 0.76); l.legs = V3(0.66, 0.68, 0.72); l.glove = l.dark }
        if m.faction == Faction.stormwarden.rawValue {
            l.cloth = V3(0.16, 0.22, 0.36); l.legs = V3(0.13, 0.18, 0.3); l.plate = V3(0.36, 0.42, 0.52)
            l.trim = V3(0.92, 0.92, 0.95); l.glow = V3(0.6, 1.2, 2.2)
        } else if m.faction == Faction.ironback.rawValue {
            l.cloth = V3(0.42, 0.25, 0.14); l.legs = V3(0.33, 0.22, 0.14); l.plate = V3(0.3, 0.27, 0.24)
            l.trim = V3(0.1, 0.1, 0.1); l.metal = V3(0.55, 0.45, 0.3); l.glow = V3(2.2, 0.9, 0.3); l.glove = V3(0.2, 0.17, 0.14)
        }
        return l
    }
}

// Shading patterns (Part.pattern, Shaders.swift mobPattern).
enum Pat {
    static let skin: Float = 0, cloth: Float = 6, enamel: Float = 7, metal: Float = 8, glow: Float = 9, leather: Float = 10, glass: Float = 11
}

// MARK: Pose

struct SoldierPose {
    var hipY: Float = 12, lean: Float = 0, twist: Float = 0, lift: Float = 0
    var thighL: Float = 0, thighR: Float = 0, kneeL: Float = 0, kneeR: Float = 0, spreadL: Float = 0, spreadR: Float = 0
    var headPitch: Float = 0, headYaw: Float = 0
    var handL: V3? = nil, handR: V3? = nil            // IK targets (model space)
    var armL = V3(0, 0, 0), armR = V3(0, 0, 0)        // free arms: shoulder rotX, outward spread, elbow bend
    var poleL = V3(-1, -0.9, 0.3), poleR = V3(1, -0.9, 0.3)
    var gunAt = V3(0, 0, 0), gunPitch: Float = 0, gunYaw: Float = 0, gunRoll: Float = 0
    var gunMag = true, magInHandL = false, grenadeR = false, visorDown = false
    var holster = 0                                   // sidearm: 0 in hand, 1 hip, 2 chest

    // The torso frame: standing-pose coordinates (pelvis at y 12) -> model space (lowered / leaned / twisted).
    func t(_ p: V3) -> V3 {
        var q = p - V3(0, 12, 0)
        if p.y > 18 { q.y += lift }
        let cl = cosf(lean), sl = sinf(lean), ct = cosf(twist), st = sinf(twist)
        let r = V3(q.x, q.y * cl - q.z * sl, q.y * sl + q.z * cl)
        return V3(ct * r.x + st * r.z, r.y, -st * r.x + ct * r.z) + V3(0, hipY, 0)
    }
}

struct SoldierRigOut {
    var parts: [Part] = []
    var handR = V3(0, 0, 0), handL = V3(0, 0, 0), muzzle = V3(0, 0, 0)
    var gripR = V3(0, 0, 0), foreL = V3(0, 0, 0)       // where the weapon wants the hands (pose check)
    var chestFront: Float = -2
    var reachErr: Float = 0                            // how far a posed hand fell short of its target
    var stance = ""
}

enum SoldierRig {
    static let hipX: Float = 2.0, thighLen: Float = 6.0, shinLen: Float = 6.0
    static let shoulderX: Float = 5.7, shoulderY: Float = 22.3
    static let upperArm: Float = 6.5, foreArm: Float = 7.0        // shoulder -> elbow -> fist centre (fist at mid thigh)
    // Camera position while mobs are drawn (level of detail); nil draws full detail (pose check, previews).
    static var eye: V3?

    // Rank index used by the rig: 0 trooper, 1 vanguard, 2 marksman, 3 bulwark, 4 officer, 5 pilot.
    static func rank(_ m: Mob) -> Int { Soldier.rank(m.kind) ?? 0 }
    static func seed(_ m: Mob) -> Int { Int(m.reinforceChance * 1_000_000) }

    // MARK: Geometry helpers

    // rotX / rotY that turn a limb hanging straight down (0, -1, 0) to point along `d`.
    static func angles(_ d: V3) -> (Float, Float) {
        let l = simd_length(d)
        guard l > 1e-5 else { return (0, 0) }
        let n = d / l
        let th = acosf(max(-1, min(1, -n.y)))
        let s = sqrtf(n.x * n.x + n.z * n.z)
        let ph: Float = s < 1e-4 ? 0 : atan2f(-n.x, -n.z)
        return (th, ph)
    }

    // Two-bone IK: the elbow for a hand at `h` (clamped to the reach), bending toward `pole`.
    static func ik(_ s: V3, _ h: V3, _ a: Float, _ b: Float, pole: V3) -> (V3, V3) {
        var d = h - s
        var l = simd_length(d)
        if l < 1e-4 { d = V3(0, -1, 0); l = 1 }
        let u = d / l
        let lc = min(max(l, abs(a - b) + 0.05), a + b - 0.02)
        let hand = s + u * lc
        let ca = max(-1, min(1, (a * a + lc * lc - b * b) / (2 * a * lc)))
        let sa = sqrtf(max(0, 1 - ca * ca))
        var v = pole - u * simd_dot(pole, u)
        if simd_length(v) < 1e-4 { v = V3(0, 0, 1) - u * u.z }
        v = simd_normalize(v)
        let e = s + (u * ca + v * sa) * a
        return (e, hand)
    }

    // A box hanging from `from` along the limb toward `to` (local x/z extents, y below the joint).
    static func limb(_ from: V3, _ to: V3, w: Float, d: Float, top: Float, extra: Float, _ c: V3, _ pat: Float) -> Part {
        let len = simd_length(to - from)
        let (th, ph) = angles(to - from)
        return Part(mn: from + V3(-w / 2, -len - extra, -d / 2), mx: from + V3(w / 2, top, d / 2), pivot: from,
                    rotX: th, rotZ: 0, color: c, pattern: pat, rotY: ph)
    }
    // A box in a limb's frame (joint at `at`, limb rest direction straight down).
    static func on(_ at: V3, _ ang: (Float, Float), _ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) -> Part {
        Part(mn: at + mn, mx: at + mx, pivot: at, rotX: ang.0, rotZ: 0, color: c, pattern: pat, rotY: ang.1)
    }

    static func gunRotation(_ p: SoldierPose) -> simd_float3x3 {
        Part(mn: .zero, mx: .zero, rotX: p.gunPitch, rotZ: p.gunRoll, color: .zero, rotY: p.gunYaw).rotation
    }
    // Where the grip anchor must be for `anchor` (gun pixels) to land at `at`.
    static func gripFor(_ gm: GunModel, anchor: V3, at: V3, _ p: SoldierPose) -> V3 {
        at - gunRotation(p) * ((anchor - gm.grip) * gm.scale)
    }
    static func gunPoint(_ gm: GunModel, _ local: V3, _ p: SoldierPose) -> V3 {
        p.gunAt + gunRotation(p) * ((local - gm.grip) * gm.scale)
    }

    // MARK: Build

    static func build(_ m: Mob) -> SoldierRigOut {
        let r = rank(m)
        let b = m.soldierBrain
        let gi = max(0, min(CapitalArms.models.count - 1, b.gun))
        let gm = CapitalArms.models[gi]
        var lod = 0
        if let e = eye {
            let d = simd_length(m.pos - e)
            lod = d > 34 ? 2 : (d > 14 ? 1 : 0)
        }
        var p = pose(m, b, rank: r, gm: gm, gi: gi)
        fit(&p, gm)
        let lv = Livery.of(m, rank: r, seed: seed(m))
        var out = SoldierRigOut()
        out.parts.reserveCapacity(lod == 0 ? 190 : (lod == 1 ? 90 : 34))
        body(&out, m, p, lv, rank: r, lod: lod)
        weapon(&out, m, p, gm, gi: gi, lv: lv, rank: r, lod: lod)
        out.chestFront = p.t(V3(0, 18, -2)).z
        // Plant the boots: the lowest point of a standing soldier on the ground (swinging legs dipped below it).
        let seated = b.station == .seated || b.station == .passenger
        let low = lowest(out.parts)
        if !seated || low < 0 {
            let dy = -low
            for i in out.parts.indices { out.parts[i].mn.y += dy; out.parts[i].mx.y += dy; out.parts[i].pivot.y += dy }
            out.handR.y += dy; out.handL.y += dy; out.muzzle.y += dy; out.gripR.y += dy; out.foreL.y += dy
        }
        let big: Float = r == 3 ? 1.12 : 1
        if big != 1 {
            out.parts = out.parts.map { q in
                var s = q
                s.mn = q.mn * big; s.mx = q.mx * big; s.pivot = q.pivot * big
                return s
            }
            out.handR *= big; out.handL *= big; out.muzzle *= big; out.gripR *= big; out.foreL *= big; out.chestFront *= big
        }
        return out
    }

    // Lowest model point after rotation.
    static func lowest(_ parts: [Part]) -> Float {
        var lo: Float = 1e9
        for q in parts {
            let r = q.rotation
            for k in 0..<8 {
                let c = V3(k & 1 == 0 ? q.mn.x : q.mx.x, k & 2 == 0 ? q.mn.y : q.mx.y, k & 4 == 0 ? q.mn.z : q.mx.z)
                lo = min(lo, q.place(c, r).y)
            }
        }
        return lo
    }

    // A weapon held in both hands slides toward a shoulder that can't reach it (short blocky arms against a long
    // rifle at low ready), carrying both hands with it.
    static func fit(_ p: inout SoldierPose, _ gm: GunModel) {
        let reach = upperArm + foreArm - 0.15
        for _ in 0..<4 {
            let fore = gunPoint(gm, gm.fore, p)
            let onR = p.handR.map { simd_length($0 - p.gunAt) < 0.01 } ?? false
            let onL = p.handL.map { simd_length($0 - fore) < 0.01 } ?? false
            guard onR || onL else { return }
            var move = V3(0, 0, 0)
            for (on, h, side) in [(onR, p.handR, Float(1)), (onL, p.handL, Float(-1))] where on {
                let s = p.t(V3(side * shoulderX, shoulderY, 0))
                let d = h! - s
                let l = simd_length(d)
                if l > reach { move -= d / l * (l - reach) }
            }
            if simd_length(move) < 0.01 { return }
            p.gunAt += move
            if onR { p.handR = p.gunAt }
            if onL { p.handL = gunPoint(gm, gm.fore, p) }
        }
    }

    // MARK: Stances

    static func pose(_ m: Mob, _ b: SoldierBrain, rank r: Int, gm: GunModel, gi: Int) -> SoldierPose {
        var p = SoldierPose()
        let t = b.clock + Float(seed(m) % 1000) * 0.37
        let walk = min(1, m.walkAmount)
        let w = m.walkPhase
        let moving = walk > 0.15
        p.lift = sinf(t * 1.7) * 0.22                          // breathing
        let pistol = gi == Guns.pistol
        let launcher = gi == Guns.launcher
        let aiming = m.aggro && b.aimHold > 0 && b.reload <= 0 && b.throwT <= 0
        let aimPitch = max(-0.9, min(1.0, b.pitch))

        func legs(_ a: Float, knee: Float) {
            let s = sinf(w), c = cosf(w)
            p.thighL = a * walk * s
            p.thighR = -a * walk * s
            p.kneeL = -knee * walk * max(0, c)
            p.kneeR = -knee * walk * max(0, -c)
            p.hipY -= 0.35 * walk * abs(s)
        }
        func swingArms(_ a: Float, left: Bool, right: Bool) {
            let s = sinf(w) * walk
            if left { p.armL = V3(-a * s, 0.06, -0.15 - 0.25 * max(0, -s)) }
            if right { p.armR = V3(a * s, 0.06, -0.15 - 0.25 * max(0, s)) }
        }
        func behindBack(left: Bool, right: Bool) {
            if left { p.handL = p.t(V3(-0.9, 14.6, 2.9)); p.poleL = V3(-1, -0.2, 0.6) }
            if right { p.handR = p.t(V3(0.9, 14.2, 2.9)); p.poleR = V3(1, -0.2, 0.6) }
        }
        func onGun(right: Bool = true, left: Bool = true) {
            if right { p.handR = p.gunAt }
            if left { p.handL = gunPoint(gm, gm.fore, p) }
        }
        // Weapon carried off the hands: slung on the back, or a sidearm holstered on the hip / chest.
        func stow() {
            if pistol {
                p.holster = r == 5 ? 2 : 1
                p.gunPitch = -Float.pi / 2; p.gunYaw = 0; p.gunRoll = 0
                p.gunAt = r == 5 ? p.t(V3(-2.0, 19.6, -3.6)) : p.t(V3(4.9, 12.8, -1.6))
            } else {
                p.gunPitch = .pi / 2; p.gunRoll = -0.55; p.gunYaw = 0
                p.gunAt = gripFor(gm, anchor: gm.butt, at: p.t(V3(-3.2, 13.6, 3.4)), p)
            }
        }
        // Shouldered aim / low ready (pistols held out; launchers on the right shoulder).
        func shoulder(pitch: Float, low: Bool) {
            if launcher {
                p.twist = -0.18
                p.gunPitch = low ? 0.05 : pitch * 0.85
                p.gunYaw = 0.02
                p.gunAt = gripFor(gm, anchor: V3(0, -0.6, 9), at: p.t(V3(5.3, 24.7, 1.4)), p)
                p.poleR = V3(1, -1, 0.1)
                onGun()
            } else if pistol {
                if r == 4 {
                    // The officer duels: side-on, one arm out, the other hand behind the back.
                    p.twist = -0.55
                    p.gunPitch = low ? -0.9 : pitch
                    p.gunYaw = low ? 0.1 : 0.05
                    p.gunAt = low ? p.t(V3(5.4, 14.2, -5.4)) : p.t(V3(3.6, 23.2, -11.2))
                    onGun(left: false)
                    behindBack(left: true, right: false)
                } else {
                    p.twist = -0.12
                    p.gunPitch = low ? -0.75 : pitch
                    p.gunAt = low ? p.t(V3(1.0, 17.6, -7.4)) : p.t(V3(0.9, 23.0, -9.8))
                    onGun()
                }
            } else {
                p.twist = low ? -0.3 : -0.42
                p.gunPitch = low ? -0.55 : pitch
                p.gunYaw = low ? 0.08 : 0.02
                let kick = b.recoil
                var butt = low ? p.t(V3(2.1, 20.2, -2.6)) : p.t(V3(1.8, 21.6, -2.3))
                if gi == Guns.arc { butt = p.t(V3(2.6, 19.4, -2.4)) }
                butt.z += 1.1 * kick
                p.gunPitch += 0.16 * kick
                p.gunAt = gripFor(gm, anchor: gm.butt, at: butt, p)
                onGun()
            }
        }

        // 1. Crew stations.
        let st = b.station
        if st != StationPose.none && st != .attention {
            if st == .seated || st == .passenger {
                p.hipY = b.seat * 16 + 1.5
                // Thighs slope down until the boots reach the floor (a high seat), shins upright.
                let c = max(0, min(1, (p.hipY - shinLen - 0.3) / thighLen))
                let th = acosf(c)
                p.thighL = th; p.thighR = th; p.kneeL = -th; p.kneeR = -th
                p.spreadL = st == .passenger ? -0.18 : -0.08; p.spreadR = -p.spreadL
                p.lean = -0.06
                if st == .seated {
                    stow()
                    p.handL = p.t(V3(-3.0, 20.0, -7.6)); p.handR = p.t(V3(3.0, 20.0, -7.6))
                    p.headPitch = -0.08
                    p.visorDown = r == 5
                } else if pistol {
                    stow()
                    p.handL = p.t(V3(-2.4, 13.4, -5.2)); p.handR = p.t(V3(2.4, 13.4, -5.2))
                } else {
                    p.gunPitch = .pi / 2; p.gunYaw = 0.3
                    p.gunAt = gripFor(gm, anchor: gm.butt, at: V3(0, 0.6, -4.6), p)
                    p.handR = gunPoint(gm, V3(0, 1, -9), p)
                    p.handL = gunPoint(gm, V3(0, 1, -14), p)
                }
                return p
            }
            if st == .gunner || st == .console {
                p.lean = 0.12; p.thighL = 0.12; p.thighR = 0.12; p.kneeL = -0.24; p.kneeR = -0.24; p.hipY = 11.85
                p.spreadL = -0.07; p.spreadR = 0.07
                stow()
                let y: Float = st == .gunner ? 20.6 : 15.4
                let z: Float = st == .gunner ? -8.8 : -7.0
                p.handL = p.t(V3(-2.7, y, z)); p.handR = p.t(V3(2.7, y, z))
                p.headPitch = st == .gunner ? max(-0.5, min(0.6, b.pitch)) : -0.4
                p.visorDown = r == 5 && st == .gunner
                return p
            }
        }

        // 2. Grenade throw: wind up behind the head, whip forward; the weapon in the left hand.
        let parade = st == .attention                   // on parade: strict attention whatever else is going on
        if !parade && b.throwT > 0 {
            let u = 1 - b.throwT / 0.7
            p.twist = u < 0.45 ? 0.35 : -0.3
            p.lean = u < 0.45 ? -0.08 : 0.15
            let sh: Float = u < 0.45 ? -2.4 * (u / 0.45) : -2.4 + 3.7 * min(1, (u - 0.45) / 0.3)
            p.armR = V3(sh, 0.15, u < 0.45 ? -1.2 : -0.3)
            p.grenadeR = u < 0.55
            p.gunPitch = -0.6; p.gunYaw = 0.35
            p.gunAt = p.t(V3(-4.6, 15.6, -4.2))
            p.handL = p.gunAt
            p.thighL = 0.2; p.thighR = -0.2; p.kneeR = -0.12
            return p
        }

        // 3. Reload: the weapon tilted up and to the left, eyes on it, the left hand fetches a fresh magazine.
        if !parade && m.aggro && b.reload > 0 {
            let total = max(0.3, b.reloadTotal)
            let u = max(0, min(1, 1 - b.reload / total))
            p.twist = -0.2; p.lean = 0.08
            p.headPitch = -0.45; p.headYaw = 0.25
            if launcher {
                p.gunPitch = 0.1; p.gunYaw = 0.02
                p.gunAt = gripFor(gm, anchor: V3(0, -0.6, 9), at: p.t(V3(5.3, 24.7, 1.4)), p)
                p.headPitch = -0.1; p.headYaw = -0.3
            } else {
                p.gunPitch = 0.42; p.gunYaw = 0.6
                p.gunAt = p.t(V3(2.4, 18.6, -6.4))
            }
            p.handR = p.gunAt
            let fore = gunPoint(gm, gm.fore, p), well = gunPoint(gm, gm.magAt, p), bolt = gunPoint(gm, gm.bolt, p)
            let pouch = launcher ? p.t(V3(-1.6, 18, 3.6)) : p.t(V3(-3.0, 12.4, -2.9))
            func ease(_ x: Float) -> Float { x * x * (3 - 2 * x) }
            func lerp3(_ a: V3, _ c: V3, _ k: Float) -> V3 { a + (c - a) * ease(max(0, min(1, k))) }
            if gi == Guns.shotgun {
                // Three shells thumbed in, then the pump.
                let k = u * 3.6
                let i = Int(k)
                if i < 3 {
                    let f = k - Float(i)
                    p.handL = f < 0.5 ? lerp3(well, pouch, f * 2) : lerp3(pouch, well, (f - 0.5) * 2)
                } else {
                    let f = (k - 3) / 0.6
                    p.handL = lerp3(fore, fore + (gunPoint(gm, gm.grip, p) - fore) * 0.2, sinf(f * .pi))
                }
            } else if u < 0.18 {
                p.handL = lerp3(fore, well, u / 0.18)
            } else if u < 0.42 {
                p.handL = lerp3(well, pouch, (u - 0.18) / 0.24)
            } else if u < 0.66 {
                p.handL = lerp3(pouch, well, (u - 0.42) / 0.24)
            } else if u < 0.8 {
                p.handL = lerp3(well, bolt, (u - 0.66) / 0.14)
            } else {
                p.handL = lerp3(bolt, fore, (u - 0.8) / 0.2)
            }
            p.gunMag = gi == Guns.shotgun || u < 0.16 || u > 0.64
            p.magInHandL = gi != Guns.shotgun && u > 0.36 && u <= 0.64
            p.poleL = V3(-1, -1, 0.2)
            legs(0.4, knee: 0.7)
            return p
        }

        // 4. Aiming (firing kicks the weapon), shuffling while they shoot.
        if !parade && aiming {
            p.lean = 0.1
            p.headPitch = aimPitch * 0.85 + (gi == Guns.sniper ? 0.2 : 0.12)
            shoulder(pitch: aimPitch, low: false)
            legs(0.42, knee: 0.6)
            if !moving { p.thighL = 0.16; p.thighR = -0.2; p.kneeL = -0.12; p.spreadR = 0.05 }
            if r == 5 || r == 1 { p.visorDown = true }
            return p
        }

        // 5. Alerted, not aiming: low ready, jogging.
        if !parade && m.aggro {
            p.lean = moving ? 0.18 : 0.08
            shoulder(pitch: 0, low: true)
            legs(0.62, knee: 0.95)
            if r == 4 && b.pointT > 0 {
                // The officer points the squad at the threat.
                p.handL = nil
                p.armL = V3(1.5 + aimPitch, -0.25, 0)
            }
            p.visorDown = r == 5
            return p
        }

        // 6. Marching / patrol: crisp straight-legged step, the free arm swinging high.
        if !parade && moving {
            legs(0.5, knee: 0.3)
            switch r {
            case 4:
                stow()
                p.handL = p.t(V3(-4.3, 12.9, -2.6))                 // a hand on the sabre hilt
                swingArms(0.7, left: false, right: true)
            case 5:
                stow()
                swingArms(0.55, left: true, right: true)
            case 1, 3:
                if launcher {
                    shoulder(pitch: 0, low: true)
                } else {
                    // Port arms: across the chest.
                    p.gunPitch = 0.75; p.gunYaw = 0.85
                    p.gunAt = p.t(V3(2.6, 16.2, -4.6))
                    onGun()
                }
            default:
                // Shoulder arms: the butt in the right hand, the weapon slanted up over the right shoulder.
                let hand = p.t(V3(5.1, 15.2, -4.6))
                p.gunPitch = .pi / 2 + 0.5; p.gunYaw = 0; p.gunRoll = 0
                p.gunAt = gripFor(gm, anchor: gm.butt, at: hand, p)
                p.handR = hand
                p.poleR = V3(1, -1, 0.6)
                swingArms(0.75, left: true, right: false)
            }
            return p
        }

        // 7. Standing guard: attention, now and then parade rest; officers with hands behind the back.
        let restCycle = !parade && sinf(t * 0.11) > 0.35
        switch r {
        case 4:
            stow()
            behindBack(left: true, right: true)
            p.spreadL = -0.07; p.spreadR = 0.07
            p.headYaw = sinf(t * 0.23) * 0.4
        case 5:
            stow()
            p.armL = V3(0.02, 0.05, -0.08); p.armR = V3(0.02, 0.05, -0.08)
            p.headYaw = sinf(t * 0.19) * 0.3
        case 1, 3:
            if launcher {
                p.gunPitch = 0.32; p.gunYaw = 0.02
                p.gunAt = gripFor(gm, anchor: V3(0, -0.6, 9), at: p.t(V3(5.3, 24.7, 1.4)), p)
                p.poleR = V3(1, -1, 0.1)
                onGun()
            } else {
                p.gunPitch = 0.75; p.gunYaw = 0.85
                p.gunAt = p.t(V3(2.6, 16.2, -4.6))
                onGun()
            }
            p.spreadL = -0.06; p.spreadR = 0.06
            p.headYaw = sinf(t * 0.17) * 0.25
        default:
            // Order arms: the butt on the ground by the right boot, the right hand on the handguard.
            p.gunPitch = restCycle ? Float.pi / 2 - 0.3 : Float.pi / 2
            p.gunYaw = 0; p.gunRoll = 0
            p.gunAt = gripFor(gm, anchor: gm.butt, at: V3(6.0, 0.5, restCycle ? -0.4 : -1.2), p)
            // The hand closes on the handguard at a set height whatever the weapon's length.
            let up: Float = restCycle ? 12 : 10
            p.handR = gunPoint(gm, V3(0, 1.0, gm.butt.z - up / gm.scale), p)
            p.poleR = V3(1, -0.3, 0.6)
            if restCycle {
                behindBack(left: true, right: false)
                p.spreadL = -0.09; p.spreadR = 0.09
                p.headYaw = sinf(t * (r == 2 ? 0.37 : 0.21)) * (r == 2 ? 0.55 : 0.3)
            } else {
                p.armL = V3(0.03, 0.04, -0.05)
            }
        }
        if m.hurt > 0 { p.lean -= 0.25 * min(1, m.hurt * 3); p.headPitch += 0.2 * min(1, m.hurt * 3) }
        return p
    }

    // MARK: Body

    static func body(_ o: inout SoldierRigOut, _ m: Mob, _ p: SoldierPose, _ lv: Livery, rank r: Int, lod: Int) {
        let hc = V3(0, p.hipY, 0)
        let full = lod == 0, mid = lod <= 1
        // Torso-group box (standing coordinates), optionally tilted further about its own top joint.
        func tb(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) {
            let mn = V3(x, y, z), mx = V3(x + w, y + h, z + d)
            let off = V3(0, p.hipY - 12 + (y > 18 ? p.lift : 0), 0)
            o.parts.append(Part(mn: mn + off, mx: mx + off, pivot: hc, rotX: p.lean, rotZ: 0, color: c, pattern: pat, rotY: p.twist))
        }
        // A pixel-art diagonal (sash, crossbelt): a staircase of boxes on the chest (z0 = front surface).
        func strap(_ a: V2, _ b: V2, width: Float, z0: Float, depth: Float, steps: Int, _ c: V3, _ pat: Float) {
            for i in 0..<steps {
                let f0 = Float(i) / Float(steps), f1 = Float(i + 1) / Float(steps)
                let p0 = a + (b - a) * f0, p1 = a + (b - a) * f1
                let x0 = min(p0.x, p1.x) - width / 2, x1 = max(p0.x, p1.x) + width / 2
                let y0 = min(p0.y, p1.y), y1 = max(p0.y, p1.y)
                tb(x0, y0, z0, x1 - x0, max(0.4, y1 - y0), depth, c, pat)
            }
        }
        // Head-group box (standing coordinates of the head: 24...32).
        let neck0 = V3(0, 24, 0)
        let neck = p.t(neck0)
        func hb(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) {
            let off = neck - neck0
            o.parts.append(Part(mn: V3(x, y, z) + off, mx: V3(x + w, y + h, z + d) + off, pivot: neck,
                                rotX: p.lean + p.headPitch, rotZ: 0, color: c, pattern: pat, rotY: p.headYaw))
        }
        // A box hanging from a torso joint with its own extra tilt (sabre, holster).
        func hang(_ joint: V3, tilt: Float, _ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) {
            let j = p.t(joint)
            o.parts.append(Part(mn: j + mn, mx: j + mx, pivot: j, rotX: p.lean + tilt, rotZ: 0, color: c, pattern: pat, rotY: p.twist))
        }

        // Legs: thigh, shin, knee-high polished boots (pilots: ankle boots), trouser stripe.
        for side in [-1, 1] as [Float] {
            let left = side < 0
            let th = left ? p.thighL : p.thighR, kn = left ? p.kneeL : p.kneeR, sp = left ? p.spreadL : p.spreadR
            let hip = V3(side * hipX, p.hipY, 0)
            let thighRot = Part(mn: .zero, mx: .zero, rotX: th, rotZ: sp, color: .zero).rotation
            let knee = hip + thighRot * V3(0, -thighLen, 0)
            let legW: Float = 3.9
            o.parts.append(Part(mn: hip + V3(-legW / 2, -thighLen - 0.5, -legW / 2), mx: hip + V3(legW / 2, 0.6, legW / 2), pivot: hip,
                                rotX: th, rotZ: sp, color: lv.legs, pattern: Pat.cloth))
            func shin(_ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) {
                o.parts.append(Part(mn: knee + mn, mx: knee + mx, pivot: knee, rotX: th + kn, rotZ: sp, color: c, pattern: pat))
            }
            func thigh(_ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) {
                o.parts.append(Part(mn: hip + mn, mx: hip + mx, pivot: hip, rotX: th, rotZ: sp, color: c, pattern: pat))
            }
            let bootTop: Float = r == 5 ? -shinLen + 2.4 : -1.6
            shin(V3(-1.85, bootTop, -1.85), V3(1.85, 0.3, 1.85), lv.legs, Pat.cloth)
            shin(V3(-2.0, -shinLen, -2.0), V3(2.0, bootTop, 2.0), lv.boots, Pat.leather)
            shin(V3(-1.95, -shinLen, -4.3), V3(1.95, -shinLen + 1.7, -2.0), lv.boots, Pat.leather)     // foot
            if mid {
                shin(V3(-2.08, -shinLen - 0.02, -4.4), V3(2.08, -shinLen + 0.45, 2.08), lv.dark * 0.6, Pat.leather)   // sole
                if r != 5 { shin(V3(-2.12, bootTop - 0.5, -2.12), V3(2.12, bootTop, 2.12), lv.boots, Pat.leather) }   // boot cuff
                thigh(V3(side * 1.92 - 0.12, -thighLen, -0.5), V3(side * 1.92 + 0.12, 0.4, 0.5), lv.trim, Pat.cloth)   // stripe
                if r != 5 { shin(V3(side * 1.86 - 0.11, bootTop, -0.5), V3(side * 1.86 + 0.11, 0.3, 0.5), lv.trim, Pat.cloth) }
            }
            switch r {
            case 1:
                shin(V3(-1.7, -2.0, -2.35), V3(1.7, 0.9, -1.8), lv.plate, Pat.enamel)          // knee guard
            case 2:
                // The long coat's tails over the thighs.
                thigh(V3(-2.25, -thighLen + 0.4, -2.25), V3(2.25, 0.9, 2.25), lv.cloth, Pat.cloth)
                if mid { thigh(V3(-2.3, -thighLen + 0.1, -2.3), V3(2.3, -thighLen + 0.7, 2.3), lv.trim, Pat.cloth) }
            case 3:
                thigh(V3(-2.3, -4.6, -2.4), V3(2.3, 0.4, 2.4), lv.plate, Pat.enamel)           // tassets
                shin(V3(-2.25, -shinLen + 1.6, -2.35), V3(2.25, 0.5, 1.2), lv.plate, Pat.enamel) // greaves
                if mid { shin(V3(-2.3, -0.4, -2.45), V3(2.3, 0.2, 1.3), lv.trim, Pat.enamel) }
            case 5:
                shin(V3(-1.7, -1.8, -2.25), V3(1.7, 0.8, -1.7), lv.dark, Pat.leather)           // knee pads
                if mid { thigh(V3(side * 1.95 - 0.35, -4.4, -1.2), V3(side * 1.95 + 0.35, -2.2, 1.2), lv.dark, Pat.cloth) }   // leg pocket
            default: break
            }
        }

        // Torso: tunic, belt and buckle, short skirt, high collar.
        tb(-4, 12, -2, 8, 12, 4, lv.cloth, Pat.cloth)
        tb(-4.05, 10.4, -2.08, 8.1, 2.2, 4.16, lv.cloth, Pat.cloth)
        let beltC = r == 5 ? lv.dark : lv.plate
        tb(-4.2, 12.4, -2.2, 8.4, 1.6, 4.4, beltC, r == 5 ? Pat.leather : Pat.enamel)
        tb(-0.9, 12.55, -2.34, 1.8, 1.3, 0.16, lv.metal, Pat.metal)
        if r != 3 { tb(-2.6, 23.4, -2.25, 5.2, 1.5, 4.5, r == 5 ? lv.plate : lv.trim, Pat.cloth) }
        if mid && r != 3 && r != 5 {
            tb(-0.35, 14, -2.1, 0.7, 9.4, 0.12, lv.trim, Pat.cloth)                              // placket
            tb(-4.1, 10.4, -2.15, 8.2, 0.45, 4.3, lv.trim, Pat.cloth)                            // hem piping
        }
        switch r {
        case 0:
            // Grey crossbelts over the white tunic, cartridge pouches, a small enamel pack.
            if mid {
                strap(V2(-3.0, 23.6), V2(2.4, 14.0), width: 1.1, z0: -2.22, depth: 0.14, steps: full ? 6 : 3, lv.trim, Pat.cloth)
                strap(V2(3.0, 23.6), V2(-2.4, 14.0), width: 1.1, z0: -2.26, depth: 0.14, steps: full ? 6 : 3, lv.trim, Pat.cloth)
                tb(-0.6, 18.2, -2.42, 1.2, 1.2, 0.16, lv.metal, Pat.metal)                     // crossing plate
            }
            tb(-3.7, 11.8, -2.75, 1.7, 1.7, 0.7, lv.trim, Pat.enamel)
            tb(2.0, 11.8, -2.75, 1.7, 1.7, 0.7, lv.trim, Pat.enamel)
            tb(-2.8, 14.6, 2.0, 5.6, 6.4, 1.7, lv.plate, Pat.enamel)
            if mid { tb(-2.9, 19.4, 1.95, 5.8, 1.6, 1.85, lv.trim, Pat.enamel) }
            if full { for y: Float in [15.2, 17.2, 19.4, 21.6] { tb(-0.42, y, -2.2, 0.84, 0.7, 0.14, lv.metal, Pat.metal) } }
        case 1:
            // Enamel cuirass, front and back, with a centre ridge and grey edging; grenade pouches.
            tb(-4.5, 15.2, -2.7, 9, 8.4, 0.7, lv.plate, Pat.enamel)
            tb(-4.5, 15.2, 2.0, 9, 8.4, 0.7, lv.plate, Pat.enamel)
            tb(-4.55, 15.0, -2.6, 0.6, 8.6, 5.2, lv.plate, Pat.enamel)
            tb(3.95, 15.0, -2.6, 0.6, 8.6, 5.2, lv.plate, Pat.enamel)
            if mid {
                tb(-0.3, 15.4, -2.84, 0.6, 7.8, 0.16, lv.plate * 0.96, Pat.enamel)
                tb(-4.55, 14.9, -2.8, 9.1, 0.42, 0.14, lv.trim, Pat.enamel)
                tb(-2.9, 23.3, -2.82, 5.8, 0.42, 0.14, lv.trim, Pat.enamel)
                tb(2.0, 11.6, -2.7, 1.4, 1.8, 0.6, lv.trim, Pat.enamel); tb(-3.4, 11.6, -2.7, 1.4, 1.8, 0.6, lv.trim, Pat.enamel)
            }
            if full { tb(-1.2, 19.6, -2.86, 2.4, 1.6, 0.14, lv.metal, Pat.metal) }               // emblem
        case 2:
            // Capelet, bandolier with silver tips, long coat body.
            tb(-4.7, 20.4, -2.55, 9.4, 3.6, 5.1, lv.trim, Pat.cloth)
            if mid {
                strap(V2(3.4, 21.0), V2(-3.2, 13.4), width: 1.3, z0: -2.3, depth: 0.25, steps: full ? 6 : 3, lv.dark, Pat.leather)
                if full {
                    for k in 0..<4 {
                        let f = Float(k) / 3.5
                        tb(1.9 - 4.5 * f, 18.9 - 5.0 * f, -2.62, 0.6, 0.6, 0.2, lv.metal, Pat.metal)
                    }
                }
            }
            tb(-2.7, 15, 2.0, 5.4, 5.4, 1.4, lv.trim, Pat.cloth)                                 // coat back pleat
        case 3:
            // Full plate: cuirass, faulds, gorget, the power cell on the back.
            tb(-4.8, 13.4, -2.9, 9.6, 10.2, 5.8, lv.plate, Pat.enamel)
            tb(-4.4, 11.6, -2.75, 8.8, 1.9, 5.5, lv.trim, Pat.enamel)
            tb(-3.2, 23.4, -3.0, 6.4, 1.6, 6.0, lv.trim, Pat.enamel)
            tb(-3.2, 14.6, 2.85, 6.4, 8.4, 2.6, lv.dark, Pat.metal)
            tb(-1.0, 15.8, 5.42, 2.0, 5.2, 0.14, lv.glow, Pat.glow)
            if mid {
                tb(-0.35, 13.6, -3.02, 0.7, 9.8, 0.16, lv.trim, Pat.enamel)
                tb(-4.85, 18.6, -3.02, 9.7, 0.4, 0.16, lv.trim, Pat.enamel)
                tb(-3.0, 22.6, 3.4, 1.1, 1.6, 1.1, lv.metal, Pat.metal); tb(1.9, 22.6, 3.4, 1.1, 1.6, 1.1, lv.metal, Pat.metal)
            }
        case 4:
            // Double-breasted silver buttons, sash, aiguillette, medals, half cape over the left shoulder.
            if full {
                for y: Float in [14.6, 16.7, 18.8, 20.9] {
                    tb(-2.2, y, -2.2, 0.8, 0.8, 0.14, lv.metal, Pat.metal)
                    tb(1.4, y, -2.2, 0.8, 0.8, 0.14, lv.metal, Pat.metal)
                }
                tb(-2.6, 24.75, -2.32, 5.2, 0.25, 4.64, lv.metal, Pat.metal)                     // collar piping
                tb(-3.5, 20.4, -2.18, 2.2, 0.75, 0.12, lv.accent, Pat.metal)                    // medal bar
                tb(-3.3, 19.3, -2.2, 0.6, 1.0, 0.12, lv.accent, Pat.metal); tb(-2.3, 19.3, -2.2, 0.6, 1.0, 0.12, lv.metal, Pat.metal)
            }
            if mid {
                strap(V2(3.3, 23.2), V2(-3.4, 12.8), width: 1.7, z0: -2.28, depth: 0.2, steps: full ? 7 : 3, lv.trim, Pat.cloth)
                strap(V2(4.0, 23.0), V2(1.6, 18.6), width: 0.35, z0: -2.42, depth: 0.12, steps: full ? 4 : 2, lv.metal, Pat.metal)
                strap(V2(1.6, 18.6), V2(4.0, 20.6), width: 0.35, z0: -2.42, depth: 0.12, steps: full ? 3 : 2, lv.metal, Pat.metal)
            }
            tb(-5.3, 9.6, 2.05, 5.8, 14.0, 0.6, lv.trim, Pat.cloth)                              // cape (back left)
            tb(-5.6, 23.0, -2.5, 3.2, 1.1, 5.2, lv.trim, Pat.cloth)                              // over the shoulder
            if mid { tb(-5.32, 9.6, 2.62, 5.84, 0.5, 0.06, lv.metal, Pat.metal) }               // silver hem
            // Sabre on the left hip (hilt forward, scabbard raked back), holster on the right.
            hang(V3(-4.5, 12.6, -1.4), tilt: -0.55, V3(-0.45, -9.6, -0.6), V3(0.45, -0.6, 0.6), lv.dark, Pat.leather)
            hang(V3(-4.5, 12.6, -1.4), tilt: -0.55, V3(-0.5, -10.1, -0.65), V3(0.5, -9.5, 0.65), lv.metal, Pat.metal)
            hang(V3(-4.5, 12.6, -1.4), tilt: -0.55, V3(-0.6, -0.6, -1.5), V3(0.6, -0.2, 0.8), lv.metal, Pat.metal)
            hang(V3(-4.5, 12.6, -1.4), tilt: -0.55, V3(-0.35, -0.2, -0.4), V3(0.35, 2.0, 0.4), lv.plate, Pat.enamel)
            if full { hang(V3(-4.5, 12.6, -1.4), tilt: -0.55, V3(-0.5, 2.0, -0.5), V3(0.5, 2.6, 0.5), lv.accent, Pat.metal) }
            if p.holster == 1 { hang(V3(4.9, 12.9, -0.6), tilt: 0.1, V3(-0.8, -4.6, -1.2), V3(0.8, -0.2, 1.2), lv.dark, Pat.leather) }
        default:
            // Flight suit: white shoulder yoke, harness straps and buckle, chest holster.
            tb(-4.1, 20.4, -2.15, 8.2, 3.6, 4.3, lv.plate, Pat.cloth)
            tb(-2.7, 12.8, -2.24, 0.8, 10.4, 0.14, lv.dark, Pat.leather)
            tb(1.9, 12.8, -2.24, 0.8, 10.4, 0.14, lv.dark, Pat.leather)
            tb(-4.06, 17.8, -2.26, 8.12, 0.8, 0.14, lv.dark, Pat.leather)
            if mid {
                tb(-0.7, 17.6, -2.38, 1.4, 1.2, 0.14, lv.metal, Pat.metal)
                tb(-2.8, 13.0, 2.15, 5.6, 7.4, 1.0, lv.dark, Pat.leather)                         // parachute pack straps / back panel
                tb(-4.06, 15.4, -1.0, 0.1, 2.4, 2.0, lv.trim, Pat.cloth); tb(3.96, 15.4, -1.0, 0.1, 2.4, 2.0, lv.trim, Pat.cloth)
            }
            if p.holster == 2 { tb(-3.4, 16.2, -2.9, 2.6, 4.0, 0.7, lv.dark, Pat.leather) }
        }
        if p.holster == 1 && r != 4 { hang(V3(4.9, 12.9, -0.6), tilt: 0.1, V3(-0.8, -4.6, -1.2), V3(0.8, -0.2, 1.2), lv.dark, Pat.leather) }

        // Arms: upper arm, forearm, cuff, glove; rank shoulder pieces.
        for side in [-1, 1] as [Float] {
            let left = side < 0
            let s = p.t(V3(side * shoulderX, shoulderY, 0))
            var target = left ? p.handL : p.handR
            let posed = target != nil
            if target == nil {
                let a = left ? p.armL : p.armR
                let sp = side * a.y
                let r1 = Part(mn: .zero, mx: .zero, rotX: a.x, rotZ: sp, color: .zero).rotation
                let r2 = Part(mn: .zero, mx: .zero, rotX: a.x - a.z, rotZ: sp, color: .zero).rotation
                target = s + r1 * V3(0, -upperArm, 0) + r2 * V3(0, -foreArm, 0)
            }
            let (e, h) = ik(s, target!, upperArm, foreArm, pole: left ? p.poleL : p.poleR)
            if left { o.handL = h } else { o.handR = h }
            if posed { o.reachErr = max(o.reachErr, simd_length(h - target!)) }
            let ua = angles(e - s), fa = angles(h - e)
            let aw: Float = r == 3 ? 3.7 : 3.4
            o.parts.append(limb(s, e, w: aw, d: aw, top: 1.9, extra: 0.6, lv.cloth, Pat.cloth))
            let fl = simd_length(h - e)
            o.parts.append(on(e, fa, V3(-aw / 2 + 0.1, -fl + 1.2, -aw / 2 + 0.1), V3(aw / 2 - 0.1, 0.5, aw / 2 - 0.1), lv.cloth, Pat.cloth))
            let gloveC = r == 3 ? lv.trim : lv.glove
            o.parts.append(on(e, fa, V3(-1.45, -fl - 1.35, -1.45), V3(1.45, -fl + 1.25, 1.45), gloveC, r == 3 ? Pat.enamel : (r == 5 ? Pat.leather : Pat.cloth)))
            if mid && r != 3 { o.parts.append(on(e, fa, V3(-1.85, -fl + 1.2, -1.85), V3(1.85, -fl + 2.0, 1.85), lv.trim, Pat.cloth)) }   // cuff
            switch r {
            case 0, 2:
                o.parts.append(on(s, ua, V3(-1.95, 1.3, -1.95), V3(1.95, 2.05, 1.95), lv.trim, Pat.cloth))            // shoulder board
                if full { o.parts.append(on(s, ua, V3(-0.4, 2.05, -0.4), V3(0.4, 2.3, 0.4), lv.metal, Pat.metal)) }   // button
            case 1:
                o.parts.append(on(s, ua, V3(-2.35, -1.8, -2.35), V3(2.35, 2.2, 2.35), lv.plate, Pat.enamel))         // pauldron
                if mid { o.parts.append(on(s, ua, V3(-2.42, -2.1, -2.42), V3(2.42, -1.7, 2.42), lv.trim, Pat.enamel)) }
                o.parts.append(on(e, fa, V3(-1.95, -fl + 1.4, -1.95), V3(1.95, -fl + 4.6, 1.95), lv.plate, Pat.enamel))   // vambrace
            case 3:
                o.parts.append(on(s, ua, V3(-2.9, -2.4, -3.0), V3(2.9, 2.4, 3.0), lv.plate, Pat.enamel))
                o.parts.append(on(s, ua, V3(-2.6, -3.7, -2.7), V3(2.6, -2.3, 2.7), lv.plate * 0.97, Pat.enamel))
                if mid { o.parts.append(on(s, ua, V3(-3.0, -2.75, -3.1), V3(3.0, -2.35, 3.1), lv.trim, Pat.enamel)) }
                o.parts.append(on(e, fa, V3(-2.05, -fl + 0.9, -2.05), V3(2.05, -fl + 5.0, 2.05), lv.plate, Pat.enamel))
                o.parts.append(on(e, fa, V3(-2.2, -0.9, -2.2), V3(2.2, 1.0, 2.2), lv.trim, Pat.enamel))   // elbow cop
            case 4:
                o.parts.append(on(s, ua, V3(-2.0, 1.3, -2.0), V3(2.0, 2.15, 2.0), lv.trim, Pat.cloth))
                if mid {
                    // Silver fringe at the epaulette's outer edge.
                    let n = full ? 5 : 2
                    for k in 0..<n {
                        let z = -1.7 + 3.4 * Float(k) / Float(max(1, n - 1)) - 0.15
                        o.parts.append(on(s, ua, V3(side * 1.75 - 0.15, -0.6, z), V3(side * 1.75 + 0.15, 1.3, z + 0.3), lv.metal, Pat.metal))
                    }
                }
                if full { o.parts.append(on(s, ua, V3(-0.6, 2.15, -1.2), V3(0.6, 2.35, 1.2), lv.accent, Pat.metal)) }   // rank pips
            default:
                if mid {
                    // Rank chevron on the outer sleeve.
                    o.parts.append(on(s, ua, V3(side * 1.72 - 0.08, -3.4, -1.2), V3(side * 1.72 + 0.08, -2.9, 1.2), lv.trim, Pat.cloth))
                    o.parts.append(on(s, ua, V3(side * 1.72 - 0.08, -4.3, -1.2), V3(side * 1.72 + 0.08, -3.8, 1.2), lv.trim, Pat.cloth))
                }
            }
            if !left && p.grenadeR {
                o.parts.append(on(e, fa, V3(-1.0, -fl - 1.9, -1.0), V3(1.0, -fl + 0.1, 1.0), lv.dark, Pat.metal))
                if full { o.parts.append(on(e, fa, V3(-0.3, -fl - 2.3, -0.3), V3(0.3, -fl - 1.9, 0.3), lv.glow, Pat.glow)) }
            }
        }

        // Head: face, then the rank's headgear.
        let faceOpen = !(r == 1 || r == 3 || (r == 5 && p.visorDown))
        hb(-4, 24, -4, 8, 8, 8, lv.skin, Pat.skin)
        if full && faceOpen {
            let white = V3(0.92, 0.91, 0.88), iris = V3(0.16, 0.2, 0.26)
            hb(-3.1, 27.3, -4.1, 2.0, 1.1, 0.12, white, 0); hb(1.1, 27.3, -4.1, 2.0, 1.1, 0.12, white, 0)
            hb(-2.0, 27.3, -4.16, 0.9, 1.1, 0.12, iris, 0); hb(1.1, 27.3, -4.16, 0.9, 1.1, 0.12, iris, 0)
            hb(-3.2, 28.6, -4.12, 2.3, 0.5, 0.14, lv.hair, 0); hb(0.9, 28.6, -4.12, 2.3, 0.5, 0.14, lv.hair, 0)
            hb(-0.6, 25.9, -4.6, 1.2, 1.8, 0.62, lv.skin * 0.93, Pat.skin)                      // nose
            hb(-1.4, 25.0, -4.08, 2.8, 0.4, 0.1, lv.skin * 0.62, 0)                             // mouth
            hb(-4.3, 26.4, -0.8, 0.3, 1.9, 1.5, lv.skin * 0.95, Pat.skin); hb(4.0, 26.4, -0.8, 0.3, 1.9, 1.5, lv.skin * 0.95, Pat.skin)
        } else if mid && faceOpen {
            hb(-2.6, 27.3, -4.1, 1.4, 1.1, 0.12, V3(0.12, 0.13, 0.16), 0); hb(1.2, 27.3, -4.1, 1.4, 1.1, 0.12, V3(0.12, 0.13, 0.16), 0)
        }
        if faceOpen && r != 5 { hb(-4.12, 24.8, 1.2, 8.24, 4.8, 2.92, lv.hair, Pat.cloth) }        // hair at the back
        switch r {
        case 0:
            // Crested enamel helmet: dome, grey brow band, crest ridge, ear guards, chin strap, silver badge.
            hb(-4.5, 28.6, -4.5, 9, 4.0, 9, lv.plate, Pat.enamel)
            hb(-3.8, 32.6, -3.8, 7.6, 0.7, 7.6, lv.plate, Pat.enamel)
            hb(-4.62, 28.2, -4.66, 9.24, 1.0, 9.3, lv.trim, Pat.enamel)
            hb(-0.6, 32.7, -4.3, 1.2, 1.3, 8.6, lv.trim, Pat.enamel)
            hb(-4.58, 25.4, -1.9, 0.62, 3.2, 4.2, lv.plate, Pat.enamel); hb(3.96, 25.4, -1.9, 0.62, 3.2, 4.2, lv.plate, Pat.enamel)
            if mid { hb(-2.4, 24.15, -4.14, 4.8, 0.5, 0.12, lv.dark, Pat.leather) }
            if full { hb(-0.7, 29.5, -4.78, 1.4, 1.4, 0.14, lv.metal, Pat.metal) }
        case 1:
            // Full helm with a smoked visor band, mouth vents, low crest, a pale rank light.
            hb(-4.6, 24.2, -4.6, 9.2, 8.6, 9.2, lv.plate, Pat.enamel)
            hb(-3.9, 32.8, -3.9, 7.8, 0.6, 7.8, lv.plate, Pat.enamel)
            hb(-3.9, 26.8, -4.78, 7.8, 2.0, 0.2, lv.glass, Pat.glass)
            hb(-0.5, 33.3, -3.6, 1, 0.8, 7.2, lv.trim, Pat.enamel)
            if mid {
                hb(-4.7, 28.8, -4.82, 9.4, 0.8, 0.5, lv.trim, Pat.enamel)
                for k in 0..<3 { hb(-1.6, 25.0 + Float(k) * 0.6, -4.74, 3.2, 0.25, 0.14, lv.trim, Pat.enamel) }
            }
            if full { hb(4.62, 28.8, -2.0, 0.14, 0.6, 1.6, lv.glow, Pat.glow) }
        case 2:
            // Grey beret slouched to the right, dark band, silver badge; glowing monocular over the right eye.
            hb(-4.45, 30.2, -4.45, 8.9, 0.6, 8.9, lv.dark, Pat.leather)
            hb(-4.4, 30.8, -4.4, 8.8, 1.6, 8.8, lv.trim, Pat.cloth)
            hb(-1.2, 32.0, -4.2, 5.8, 1.1, 8.2, lv.trim, Pat.cloth)
            hb(0.9, 26.8, -5.5, 2.4, 2.2, 1.4, lv.dark, Pat.metal)
            hb(1.25, 27.15, -5.56, 1.7, 1.5, 0.1, lv.glow, Pat.glow)
            if mid {
                hb(-4.16, 28.5, -3.8, 0.12, 0.45, 7.6, lv.dark, Pat.leather)                        // monocular strap
                hb(-3.2, 30.6, -4.6, 1.3, 1.3, 0.16, lv.metal, Pat.metal)
            }
        case 3:
            // Tall helm: faceplate, glowing slit, high grey crest, cheek ridges.
            hb(-4.7, 24.0, -4.7, 9.4, 9.2, 9.4, lv.plate, Pat.enamel)
            hb(-3.6, 24.4, -5.05, 7.2, 6.8, 0.4, lv.plate * 0.97, Pat.enamel)
            hb(-3.2, 28.0, -5.16, 6.4, 0.8, 0.14, lv.glow, Pat.glow)
            hb(-0.7, 33.2, -5.0, 1.4, 3.0, 10.0, lv.trim, Pat.enamel)
            hb(-0.5, 36.2, -3.4, 1.0, 1.0, 7.4, lv.trim, Pat.enamel)
            if mid { hb(-4.85, 25.0, -4.95, 0.5, 3.6, 3.0, lv.trim, Pat.enamel); hb(4.35, 25.0, -4.95, 0.5, 3.6, 3.0, lv.trim, Pat.enamel) }
        case 4:
            // Peaked cap: flared white crown, grey band, glossy graphite peak, silver cord, pale-gold badge.
            hb(-4.3, 29.6, -4.3, 8.6, 1.5, 8.6, lv.trim, Pat.cloth)
            hb(-4.8, 31.0, -4.8, 9.6, 1.7, 9.6, lv.plate, Pat.cloth)
            hb(-5.2, 32.4, -5.5, 10.4, 0.9, 10.5, lv.plate, Pat.cloth)
            hb(-4.0, 29.35, -6.5, 8.0, 0.5, 2.3, lv.dark, Pat.leather)
            if mid { hb(-4.0, 29.9, -4.44, 8.0, 0.32, 0.14, lv.metal, Pat.metal) }
            if full { hb(-0.9, 31.2, -4.98, 1.8, 1.6, 0.2, lv.accent, Pat.metal) }
        default:
            // Flight helmet: white shell (open face unless the smoked visor is down), grey stripe, boom mic.
            hb(-4.6, 30.4, -4.6, 9.2, 2.8, 9.2, lv.plate, Pat.enamel)
            hb(-3.8, 33.2, -3.8, 7.6, 0.6, 7.6, lv.plate, Pat.enamel)
            hb(-4.6, 24.8, -3.4, 0.7, 5.6, 8.0, lv.plate, Pat.enamel); hb(3.9, 24.8, -3.4, 0.7, 5.6, 8.0, lv.plate, Pat.enamel)
            hb(-4.6, 24.8, 3.9, 9.2, 5.6, 0.7, lv.plate, Pat.enamel)
            hb(-0.6, 33.0, -4.1, 1.2, 0.85, 8.5, lv.trim, Pat.enamel)
            if p.visorDown {
                hb(-3.95, 25.3, -4.9, 7.9, 5.2, 0.4, lv.glass, Pat.glass)
            } else {
                hb(-3.95, 31.0, -5.1, 7.9, 1.7, 1.1, lv.glass, Pat.glass)
            }
            if mid { hb(-4.3, 25.2, -4.95, 2.8, 0.4, 0.4, lv.dark, Pat.metal) }
        }
    }

    // MARK: Weapon

    static func weapon(_ o: inout SoldierRigOut, _ m: Mob, _ p: SoldierPose, _ gm: GunModel, gi: Int, lv: Livery, rank r: Int, lod: Int) {
        let rot = gunRotation(p)
        let g = p.gunAt
        let sc = gm.scale
        let tint = m.faction == Faction.none.rawValue || m.faction == Faction.steelhold.rawValue
        func place(_ q: Part, at a: V3) -> Part {
            var c = q.color
            if !tint && q.pattern == Pat.enamel { c = lv.plate }
            return Part(mn: a + (q.mn - gm.grip) * sc, mx: a + (q.mx - gm.grip) * sc, pivot: a,
                        rotX: p.gunPitch, rotZ: p.gunRoll, color: c, pattern: q.pattern, rotY: p.gunYaw)
        }
        let magSet = Set(gm.mag)
        for (i, q) in gm.parts.enumerated() {
            if magSet.contains(i) && !p.gunMag { continue }
            if lod == 2 && q.mx.x - q.mn.x < 1.2 && q.mx.y - q.mn.y < 1.2 { continue }
            o.parts.append(place(q, at: g))
        }
        if p.magInHandL {
            // The fresh magazine follows the left hand, seated the way the well takes it.
            let a = o.handL - rot * ((gm.magAt - gm.grip) * sc)
            for i in gm.mag { o.parts.append(place(gm.parts[i], at: a)) }
        }
        o.muzzle = g + rot * ((gm.muzzle - gm.grip) * sc)
        o.gripR = g
        o.foreL = g + rot * ((gm.fore - gm.grip) * sc)
    }

    // The muzzle in world space (shots and the marksman's laser start there).
    static func muzzleWorld(_ m: Mob) -> V3 {
        let out = build(m)
        let s: Float = m.scale / 16
        let q = out.muzzle * s
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        return m.pos + V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z)
    }
}

// MARK: Harness poses

extension SoldierRig {
    // Puts a spawned soldier into a stance for a still shot (--spawn kind:...:token): aim, fire, low, reload=0.4,
    // throw, march, attention, rest, point, pitch=0.3, turn=90 (degrees), gun=N, and the station names (seated,
    // passenger, gunner, console, attention-station). Seated stances get a slab to sit on.
    static func stage(_ m: Mob, _ tokens: [String], world: World) {
        let b = m.soldierBrain
        if m.variant >= 0 && m.variant < Guns.all.count { b.gun = m.variant }
        b.clock = 0
        for t in tokens {
            let kv = t.split(separator: "=").map(String.init)
            let v = kv.count > 1 ? Float(kv[1]) ?? 0 : 0
            switch kv[0] {
            case "aim": m.aggro = true; b.aimHold = 99
            case "fire": m.aggro = true; b.aimHold = 99; b.recoil = 1
            case "low": m.aggro = true; b.aimHold = 0
            case "reload": m.aggro = true; b.reloadTotal = 2; b.reload = 2 * (1 - max(0.01, min(0.99, v)))
            case "throw": m.aggro = true; b.throwT = kv.count > 1 ? v : 0.45
            case "march": m.walkAmount = 1; m.walkPhase = kv.count > 1 ? v : 0.9
            case "run": m.aggro = true; m.walkAmount = 1; m.walkPhase = kv.count > 1 ? v : 1.2
            case "attention": b.clock = 0
            case "rest": b.clock = 10
            case "point": m.aggro = true; b.pointT = 1
            case "pitch": b.pitch = v
            case "turn": m.yaw += v * .pi / 180
            case "gun": b.gun = max(0, min(Guns.all.count - 1, Int(v))); m.variant = b.gun
            case "seated", "passenger", "gunner", "console", "parade":
                let names: [String: StationPose] = ["seated": .seated, "passenger": .passenger, "gunner": .gunner, "console": .console, "parade": .attention]
                b.station = names[kv[0]] ?? StationPose.none
                if b.station == .seated || b.station == .passenger {
                    b.seat = 0.5
                    let x = Int(floor(m.pos.x)), y = Int(floor(m.pos.y)), z = Int(floor(m.pos.z))
                    if let n = ["smooth_stone_slab", "stone_slab", "oak_slab"].first(where: { Blocks.has($0) }) { world.setBlock(x, y, z, Blocks.id(n)) }
                }
            default: break
            }
        }
    }
}
