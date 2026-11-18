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
        // Ledger 332-333 (WildLooks.swift): the polar bear and the mountain goat, to the farm animals' standard.
        for k in [MobKind.goat, .polarBear] {
            let m = Mob(k, at: .zero)
            m.coatSeed = 7; m.walkAmount = 0; m.walkPhase = 0; m.callTimer = 15; m.aggro = false
            while WildLooks.snarl(m) > 0 { m.animT += 0.5 }
            let c = (0..<3).map { built(m, $0).count }
            let (lo, hi, finite) = PoseCheck.extent(built(m, 0))
            var walkOK = true, worst = ""
            m.walkAmount = 1
            for i in 0..<12 {
                m.walkPhase = Float(i) * Float.pi / 6
                let (wl, _, wok) = PoseCheck.extent(built(m, 0))
                if !wok || wl < -0.6 || wl > 1.2 { walkOK = false; worst = String(format: " (walk phase %d lowest %.2f)", i, wl) }
            }
            m.walkAmount = 0; m.walkPhase = 0
            check(finite && !WildLooks.old && c[0] <= 64 && c[0] >= 30 && c[0] > c[1] && c[1] > c[2] && abs(lo) <= 0.35 && walkOK,
                  String(format: "\(k.key): a jointed model, parts near %d, middle %d, far %d; stands on its feet (%.2f) at rest and through the walk%@",
                         c[0], c[1], c[2], lo, worst))
            let ps = built(m, 0)
            guard let j = MobAnim.headJoint(m) else { check(false, "\(k.key): has a head joint (its head turns to look)"); continue }
            var front = 0
            for (i, p) in ps.enumerated() where p.place(p.mn, p.rotation).z < ps[front].place(ps[front].mn, ps[front].rotation).z { front = i }
            let held = ps.filter { j.holds($0) }
            let legHeld = held.contains { (($0.mn.y + $0.mx.y) * 0.5) < 4 }
            check(j.holds(ps[front]) && held.count >= 8 && !legHeld, "\(k.key): the head turn takes \(held.count) head parts, no leg")
            if k == .goat {
                let horn = V3(0.1, 0.09, 0.09), shag = V3(0.9, 0.89, 0.83)
                let horns = ps.filter { $0.color == horn }
                let hornTop = horns.map { PoseCheck.extent([$0]).1 }.max() ?? 0
                let beardLow = ps.filter { $0.color == shag && $0.pivot != .zero && j.holds($0) }.map { PoseCheck.extent([$0]).0 }.min() ?? 99
                check(horns.count == 4 && hornTop > hi - 0.5 && beardLow < 13, String(format: "goat: two black horns in two pieces (%d) reaching the top of it (%.1f of %.1f px), a beard down to %.1f px",
                                                                                    horns.count, hornTop, hi, beardLow))
                m.callTimer = 3.5
                let low = mouthLow(built(m, 0), j)
                check(low < 3.0, String(format: "goat: grazes with its mouth %.1f px off the ground", low))
            } else {
                let skin = V3(0.07, 0.07, 0.08), tooth = V3(0.93, 0.91, 0.82)
                let claws = ps.filter { $0.color == skin && PoseCheck.extent([$0]).1 < 1.5 }.count
                let coat = V3(0.94, 0.93, 0.86)
                // The jaw's opening: how far its lowest point hangs under the muzzle's; the body's top (the hackles).
                func opening(_ q: [Part]) -> Float {
                    guard let mz = q.first(where: { $0.color == coat && $0.mn.x == -2.5 && $0.mx.x == 2.5 }),
                          let jw = q.first(where: { $0.color == coat && $0.mn.x == -2.3 && $0.mx.x == 2.3 }) else { return -99 }
                    return PoseCheck.extent([mz]).0 - PoseCheck.extent([jw]).0
                }
                func bodyTop(_ q: [Part]) -> Float { q.filter { $0.pivot == .zero && !j.holds($0) }.map { $0.mx.y }.max() ?? 0 }
                let calm = opening(ps), calmTeeth = ps.filter { $0.color == tooth }.count, calmTop = bodyTop(ps)
                m.aggro = true
                let mad = built(m, 0)
                let madTeeth = mad.filter { $0.color == tooth }.count
                check(hi >= 23 && claws == 12, String(format: "polar bear: %.1f px tall (was 24 in boxes), black claws on its four paws (%d)", hi, claws))
                check(calmTeeth == 0 && madTeeth == 4 && opening(mad) > calm + 2 && bodyTop(mad) > calmTop,
                      String(format: "polar bear: angry, it opens its jaws %.1f px (shut %.1f) on %d fangs (shut %d) with its hackles up (%.1f px, calm %.1f)",
                             opening(mad), calm, madTeeth, calmTeeth, bodyTop(mad), calmTop))
                // Now and then it bares its teeth unprovoked.
                m.aggro = false
                var bared = 0
                for i in 0..<400 { m.animT = Float(i) * 0.25; if WildLooks.snarl(m) > 0.5 { bared += 1 } }
                check(bared > 0 && bared < 80, "polar bear: bares its teeth now and then at rest (\(bared) of 400 quarter-seconds)")
            }
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
