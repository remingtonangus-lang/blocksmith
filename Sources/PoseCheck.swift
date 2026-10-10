import Foundation
import simd

// Pose oracle (--posecheck): every model is built in its idle, alerted and attacking states and its limbs are
// checked against the rotation convention (Part: rotX > 0 swings a hanging limb forward, toward -Z).
// Bug class (BUGS.md, "soldier arms render backwards"): poses written with negative rotX raised arms BEHIND the
// body: soldiers, zombies, piglins, blight skeletons, golems, the player's third-person swing.
//  - limbs: a box hanging from a joint beside the torso (arms; legs reach the ground and are skipped) that is
//    rotated off vertical must end in front of its joint, never behind it;
//  - soldiers and crews (Capital ranks): both hands and the weapon's muzzle ahead of the chest while aiming, the
//    muzzle ahead of the hands, the weapon held near the hands in every stance (SoldierRig.swift);
//  - the player's third-person attack swing goes forward.
enum PoseCheck {
    static var failures: [String] = []

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        let d = detail()
        if !ok || verbose { print("posecheck \(ok ? "ok  " : "FAIL") \(name)\(d.isEmpty ? "" : ": " + d)") }
        if !ok { failures.append(name) }
    }
    static var verbose = false

    // Hanging limbs of a model and where each one's far end ends up relative to its joint (model pixels).
    static func limbTips(_ parts: [Part]) -> [(index: Int, angle: Float, tip: V3)] {
        var out: [(Int, Float, V3)] = []
        for (i, p) in parts.enumerated() {
            let h = p.mx.y - p.mn.y
            guard h >= 6, p.mx.x - p.mn.x < h, p.mx.z - p.mn.z < h else { continue }       // long and upright at rest
            guard p.pivot.y >= p.mx.y - 3.5, p.pivot.y <= p.mx.y + 1 else { continue }     // hangs from near its top
            guard abs(p.pivot.x) >= 3.5, p.mn.y > 2 else { continue }                      // beside the torso, off the ground
            let end = V3((p.mn.x + p.mx.x) / 2, p.mn.y, (p.mn.z + p.mx.z) / 2)
            let rest = end - p.pivot
            let tip = p.place(end, p.rotation) - p.pivot
            let c = simd_dot(simd_normalize(rest), simd_normalize(tip))
            out.append((i, acosf(max(-1, min(1, c))), tip))
        }
        return out
    }

    // States a model is checked in: 0 idle, 1 alerted, 2 attacking / casting / carrying, 3 both.
    static func pose(_ k: MobKind, _ state: Int) -> Mob {
        let m = Mob(k, at: .zero)
        m.yaw = 0
        m.walkAmount = 0
        m.walkPhase = 0
        m.aggro = state & 1 != 0
        if state & 2 != 0 {
            m.attackCooldown = 1
            m.spellTimer = 4.5
            if k == .copperGolem {
                m.cargo = ItemContainer(1)
                m.cargo![0] = ItemStack(Items.id("cobblestone"), 16)
            }
        }
        return m
    }

    static func run(game: Game) -> Bool {
        failures = []
        SoldierRig.eye = nil
        var limbs = 0
        let skip: Set<MobKind> = [.deckGun, .boat, .minecart, .enderDragon, .endCrystal, .ashTank, .ashHalftrack, .ashArtillery, .ashTruck]
        for k in MobKind.allCases where !skip.contains(k) && Soldier.rank(k) == nil {      // soldiers: soldiers() below
            for state in 0..<4 {
                let m = pose(k, state)
                let parts = mobModelParts(m)
                for l in limbTips(parts) where l.angle > 0.35 {
                    limbs += 1
                    check(l.tip.z < 1, "\(k.key) state \(state) part \(l.index) raised forward",
                          String(format: "tip %.1f px %@ its joint (rotX %.2f)", abs(l.tip.z), l.tip.z < 0 ? "ahead of" : "behind", parts[l.index].rotX))
                }
            }
        }
        // The player's third-person attack swing (right arm, rotX = playerHitAngle).
        for sw: Float in [0.2, 0.5, 0.8] {
            let arm = Part(mn: V3(4, 12, -2), mx: V3(8, 24, 2), pivot: V3(6, 22, 0), rotX: playerHitAngle(sw), color: .zero)
            let tip = arm.place(V3(6, 12, 0), arm.rotation) - arm.pivot
            check(tip.z < 0, String(format: "player attack swing %.1f forward", sw), String(format: "hand z %.1f", tip.z))
        }
        let pp = playerParts(game, pitch: 0, walk: 0, hit: playerHitAngle(0.4))
        for l in limbTips(pp) where l.angle > 0.35 {
            limbs += 1
            check(l.tip.z < 1, "player model part \(l.index) raised forward", String(format: "tip z %.1f", l.tip.z))
        }
        soldiers(&limbs)
        print("posecheck: \(limbs) raised limbs checked, \(failures.count) failed\(failures.isEmpty ? "" : " -> " + failures.prefix(12).joined(separator: ", "))")
        return failures.isEmpty
    }

    // Lowest and highest model points (after rotation) and whether every coordinate is finite.
    static func extent(_ parts: [Part]) -> (Float, Float, Bool) {
        var lo: Float = 1e9, hi: Float = -1e9, ok = true
        for p in parts {
            let r = p.rotation
            for k in 0..<8 {
                let c = V3(k & 1 == 0 ? p.mn.x : p.mx.x, k & 2 == 0 ? p.mn.y : p.mx.y, k & 4 == 0 ? p.mn.z : p.mx.z)
                let q = p.place(c, r)
                if !(q.x.isFinite && q.y.isFinite && q.z.isFinite) { ok = false }
                lo = min(lo, q.y); hi = max(hi, q.y)
            }
        }
        return (lo, hi, ok)
    }

    // Soldiers: every rank in every stance. Hands reach where the stance puts them, the weapon sits in the hands,
    // boots on the ground, and while aiming both hands and the muzzle are ahead of the chest.
    static func soldiers(_ limbs: inout Int) {
        let kinds = MobKind.allCases.filter { Soldier.rank($0) != nil }
        func make(_ k: MobKind, gun gi: Int) -> Mob {
            let m = Mob(k, at: .zero)
            m.yaw = 0; m.walkAmount = 0; m.walkPhase = 0; m.reinforceChance = 0
            m.variant = gi
            m.soldierBrain.gun = gi
            return m
        }
        typealias Setup = (name: String, standing: Bool, set: (Mob, SoldierBrain) -> Void)
        var stances: [Setup] = [
            ("aim level", true, { m, b in m.aggro = true; b.aimHold = 1; b.pitch = 0 }),
            ("aim up", true, { m, b in m.aggro = true; b.aimHold = 1; b.pitch = 0.6 }),
            ("aim down", true, { m, b in m.aggro = true; b.aimHold = 1; b.pitch = -0.5 }),
            ("firing", true, { m, b in m.aggro = true; b.aimHold = 1; b.recoil = 1 }),
            ("low ready", true, { m, _ in m.aggro = true }),
            ("combat run", false, { m, _ in m.aggro = true; m.walkAmount = 1; m.walkPhase = 1.2 }),
            ("throw windup", true, { m, b in m.aggro = true; b.throwT = 0.5 }),
            ("throw release", true, { m, b in m.aggro = true; b.throwT = 0.15 }),
            ("march", false, { m, _ in m.walkAmount = 1; m.walkPhase = 0.8 }),
            ("march other foot", false, { m, _ in m.walkAmount = 1; m.walkPhase = 3.9 }),
            ("attention", true, { _, b in b.clock = 0 }),
            ("parade rest", true, { _, b in b.clock = 10 }),
        ]
        for u: Float in [0.1, 0.3, 0.5, 0.7, 0.9] {
            stances.append(("reload \(u)", true, { m, b in m.aggro = true; b.reloadTotal = 2; b.reload = 2 * (1 - u) }))
        }
        // A door gunner: a passenger seat, aiming (sidearms stay holstered in a seat: no pistol case).
        stances.append(("aim seated", false, { m, b in b.station = .passenger; b.seat = 0.45; m.aggro = true; b.aimHold = 1 }))
        for st in StationPose.allCases where st != StationPose.none {
            stances.append(("station \(st)", st != .seated && st != .passenger, { _, b in b.station = st; b.seat = 0.45 }))
        }
        for k in kinds {
            let r = Soldier.rank(k) ?? 0
            for gi in 0..<Guns.all.count {
                // Every weapon for the aim stances; the rank's own weapons for the rest.
                let own = (0..<12).map { _ in Soldier.pickGun(k) }.contains(gi)
                for s in stances where own || s.name.hasPrefix("aim") || s.name == "firing" || s.name == "low ready" {
                    if s.name == "aim seated" && Guns.isHandgun(gi) { continue }
                    let m = make(k, gun: gi)
                    s.set(m, m.soldierBrain)
                    let rig = SoldierRig.build(m)
                    let tag = "\(k.key) \(Guns.all[gi].key) \(s.name)"
                    limbs += 1
                    let (lo, hi, finite) = extent(rig.parts)
                    check(finite, "\(tag) finite")
                    check(rig.reachErr < 1.3, "\(tag) hands reach", String(format: "%.1f px short", rig.reachErr))
                    if s.standing { check(lo > -0.8 && lo < 0.9, "\(tag) boots on the ground", String(format: "lowest point %.2f px", lo)) }
                    check(hi > 30, "\(tag) head up", String(format: "top %.1f px", hi))
                    if s.name.hasPrefix("aim") || s.name == "firing" {
                        let chest = rig.chestFront
                        if gi != Guns.launcher { check(rig.handR.z < chest - 0.5, "\(tag) right hand ahead of the chest", String(format: "z %.1f, chest %.1f", rig.handR.z, chest)) }   // launchers: gripped at the shoulder
                        check(rig.muzzle.z < rig.handR.z - 2, "\(tag) muzzle ahead of the hands", String(format: "muzzle %.1f hand %.1f", rig.muzzle.z, rig.handR.z))
                        check(simd_length(rig.handR - rig.gripR) < 1.0, "\(tag) right hand on the grip", String(format: "%.1f px off", simd_length(rig.handR - rig.gripR)))
                        let oneHand = r == 4 && Guns.isHandgun(gi)
                        if !oneHand {
                            check(rig.handL.z < chest - 1, "\(tag) left hand ahead of the chest", String(format: "z %.1f", rig.handL.z))
                            check(simd_length(rig.handL - rig.foreL) < 1.0, "\(tag) left hand on the fore grip", String(format: "%.1f px off", simd_length(rig.handL - rig.foreL)))
                        }
                    }
                }
            }
        }
    }
}
