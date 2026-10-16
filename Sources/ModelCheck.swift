import Foundation
import simd

// P295's quick check (questcheck --modelcheck): the rebuilt people and animals. Every farm animal builds at the three
// detail levels (MobDetail) with every coordinate finite, the near model within its part budget and each level lighter
// than the one before; it stands on its hooves at rest and through the walk; grazing, rooting and pecking bring the mouth
// to the ground; the head turn (MobAnim.headJoint) takes the head and never a leg. Townsfolk and soldiers have their
// smaller heads on a neck, hands, and the near detail (lids, pupils) the far models leave out.
enum ModelCheck {
    static func run() -> Int32 {
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "ok   " : "FAIL ") + what)
            if !ok { fails.append(what) }
        }
        func built(_ m: Mob, _ level: Int) -> [Part] {
            MobDetail.level = level
            defer { MobDetail.level = 0 }
            return mobModelParts(m)
        }
        // The lowest point of the parts in front of the neck (the mouth while grazing).
        func mouthLow(_ ps: [Part], _ j: HeadJoint) -> Float {
            var lo: Float = 1e9
            for p in ps where (p.mn.z + p.mx.z) * 0.5 < j.maxZ - 1 {
                let r = p.rotation
                for k in 0..<8 {
                    let c = V3(k & 1 == 0 ? p.mn.x : p.mx.x, k & 2 == 0 ? p.mn.y : p.mx.y, k & 4 == 0 ? p.mn.z : p.mx.z)
                    lo = min(lo, p.place(c, r).y)
                }
            }
            return lo
        }
        for k in [MobKind.cow, .pig, .sheep, .chicken] {
            var counts = [0, 0, 0], worst = "", groundOK = true, walkOK = true, finite = true
            for v in 1...3 {
                for seed: UInt32 in [0, 7, 1234, 40000, 65000] {
                    let m = Mob(k, at: .zero)
                    m.variant = v; m.coatSeed = seed; m.walkAmount = 0; m.walkPhase = 0; m.callTimer = 15
                    let c = (0..<3).map { built(m, $0).count }
                    for i in 0..<3 { counts[i] = max(counts[i], c[i]) }
                    if !(c[0] >= c[1] && c[1] > c[2]) { worst = "variant \(v) seed \(seed): \(c)" }
                    let (lo, _, ok) = PoseCheck.extent(built(m, 0))
                    if !ok { finite = false }
                    if abs(lo) > 0.35 { groundOK = false; worst = "variant \(v) seed \(seed) rests at y \(lo)" }
                    m.walkAmount = 1
                    for i in 0..<12 {
                        m.walkPhase = Float(i) * Float.pi / 6
                        let (wl, _, wok) = PoseCheck.extent(built(m, 0))
                        if !wok { finite = false }
                        if wl < -0.6 || wl > 1.2 { walkOK = false; worst = String(format: "walk phase %d lowest %.2f", i, wl) }
                    }
                }
            }
            check(finite && counts[0] <= 64 && counts[2] <= 20 && worst.isEmpty, "\(k.key): parts near \(counts[0]), middle \(counts[1]), far \(counts[2])" + (worst.isEmpty ? "" : " (\(worst))"))
            check(groundOK && walkOK, "\(k.key): stands on its feet at rest and through the walk")
            // The head turn holds the head (the frontmost part) and no leg.
            let m = Mob(k, at: .zero)
            m.variant = 1; m.walkAmount = 0; m.callTimer = 15
            let ps = built(m, 0)
            guard let j = MobAnim.headJoint(m) else { check(false, "\(k.key): has a head joint"); continue }
            var front = 0
            for (i, p) in ps.enumerated() where p.place(p.mn, p.rotation).z < ps[front].place(ps[front].mn, ps[front].rotation).z { front = i }
            let held = ps.filter { j.holds($0) }
            let legHeld = held.contains { (($0.mn.y + $0.mx.y) * 0.5) < 4 && k != .chicken || (($0.mn.y + $0.mx.y) * 0.5) < 3 }
            check(j.holds(ps[front]) && held.count >= 5 && !legHeld, "\(k.key): the head turn takes \(held.count) head parts, no leg")
            // Grazing (cow, sheep), rooting (pig), pecking (chicken): the mouth comes down to the ground.
            m.callTimer = 3.5
            m.animT = 0.21                                     // (the peck's own beat: near the bottom of a dip)
            let low = mouthLow(built(m, 0), j)
            check(low < 3.0, String(format: "\(k.key): grazes with its mouth %.1f px off the ground", low))
        }
        // People: a neck and a smaller head; hands; near detail.
        let w = Mob(.villager, at: .zero)
        var v = VillagerData(); v.role = "worker"; v.look = 14; v.person = "Amos Hale"
        w.villager = v
        let near = built(w, 0), far = built(w, 2)
        let skin = TownLook.of(w).skin
        let headW = near.filter { $0.pivot == .zero && $0.mn.y > 23.4 && $0.mx.y - $0.mn.y > 4 && $0.color == skin }.map { $0.mx.x - $0.mn.x }.max() ?? 99
        let neck = near.contains { $0.mn.y < 23.5 && $0.mx.y > 24.5 && $0.mx.x - $0.mn.x < 3.5 && $0.pivot == .zero }
        let hand = near.filter { $0.pivot.y == 23 }.map { $0.mn.y }.min() ?? 99
        check(headW < 5.6 && neck, String(format: "townsfolk: head %.1f px across on a neck (was 6.4)", headW))
        check(hand < 12.5 && near.count > far.count, "townsfolk: hands to \(hand) px, \(near.count) parts near, \(far.count) far")
        SoldierRig.eye = nil
        let s = Mob(.soldierRecruit, at: .zero)
        s.reinforceChance = 0
        let sp = mobModelParts(s)
        let sw = sp.filter { $0.mx.y - $0.mn.y > 5 && $0.mx.x - $0.mn.x > 5 && $0.mn.y > 23 }.map { $0.mx.x - $0.mn.x }.min() ?? 99
        check(sw < 7.6, String(format: "soldiers: head %.1f px across (was 8)", sw))
        print("modelcheck: \(fails.isEmpty ? "all ok" : "\(fails.count) failed")")
        return fails.isEmpty ? 0 : 1
    }
}
