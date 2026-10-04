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
        var limbs = 0
        let skip: Set<MobKind> = [.deckGun, .boat, .minecart, .enderDragon, .endCrystal]
        for k in MobKind.allCases where !skip.contains(k) {
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
        print("posecheck: \(limbs) raised limbs checked, \(failures.count) failed\(failures.isEmpty ? "" : " -> " + failures.prefix(12).joined(separator: ", "))")
        return failures.isEmpty
    }
}
