import Foundation
import simd

// Troop class checks (backlog A2; `questcheck --troopclasses-only`, and part of every questcheck run):
//   classes    a Greywall base's soldiers by tier: Hannibal only on fortresses and up, Spec Ops from the garrison up, the
//              class's guns; a Capital soldier's class by rank (its gun unchanged); none for the Ashguard
//   segments   rounds land on the helmet, vest or greaves by height; a segment soaks its class's share, cracks at half
//              (soaks less), falls off at zero (a cracked piece drops, the hit goes through in full, the helmet leaves
//              the head bare); melee wears the vest
//   save/loot  class, segments and gun kept through a save; a fallen soldier's pieces drop with the life they had
//              left; repaired with steel at an anvil; wearable
//   behaviour  Spec Ops pick a flank well off the line to the target; Hannibal troopers advance while firing and fire
//              longer bursts; Spec Ops SMGs are hushed (no alarm noise)
//   balance    the time-to-kill table (classes x player weapons, soldier guns x player armour), printed and, with
//              --write-ttk, written to docs/status/troop-classes-ttk.md
enum TroopTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        classes(g, check)
        segments(g, check)
        saveAndLoot(g, check)
        behaviour(g, check)
        ttk(g, check)
    }

    static func grey(_ kind: String, _ t: Greywall.Tier, _ p: V3) -> Mob? {
        Mob.structureMob("\(kind)@grey\(Greywall.leashTag(Int(p.x), Int(p.z), t))", at: p)
    }

    static func classes(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player.pos + V3(5, 0, 0)
        var rows: [String] = []
        var ok = true
        for t in Greywall.Tier.allCases {
            var seen: [TroopClass: Int] = [:]
            for (i, k) in ["soldier_recruit", "soldier_trooper", "soldier_marksman", "soldier_ironclad", "soldier_officer", "soldier_crew"].enumerated() {
                for j in 0..<4 {
                    guard let m = grey(k, t, p + V3(Float(i * 3), 0, Float(j * 3))), let c = m.troopClass else { ok = false; continue }
                    seen[c, default: 0] += 1
                    let gun = m.soldierBrain.gun
                    let fits: Bool
                    switch c {
                    case .regular: fits = [Guns.rifle, Guns.smg, Guns.shotgun, Guns.pistol].contains(gun)
                    case .specOps: fits = [Guns.sniper, Guns.smg, Guns.rifle].contains(gun)
                    case .hannibal: fits = [Guns.ashsaw, Guns.launcher, Guns.arc].contains(gun)
                    }
                    if !fits || m.variant != gun { ok = false; rows.append("\(t) \(k) \(c.name) carries \(Guns.all[gun].name)") }
                }
            }
            let h = seen[.hannibal] ?? 0, s = seen[.specOps] ?? 0
            if (t.rawValue < 2 && h > 0) || (t.rawValue >= 2 && h == 0) || (t.rawValue >= 1 && s == 0) || (t == .outpost && s > 0) { ok = false }
            rows.append("\(t): \(seen[.regular] ?? 0) regular, \(s) spec ops, \(h) Hannibal")
        }
        check(ok, "troop classes by Greywall tier, with their guns: \(rows.joined(separator: "; "))")
        let cap = Mob(.soldierIronclad, at: p), mk = Mob(.soldierMarksman, at: p), rec = Mob(.soldierRecruit, at: p)
        let gun0 = rec.soldierBrain.gun
        let ash = Mob(.soldierTrooper, at: p); ash.faction = Faction.ashguard.rawValue
        check(cap.troopClass == .hannibal && mk.troopClass == .specOps && rec.troopClass == .regular && rec.soldierBrain.gun == gun0 && ash.troopClass == nil,
              "troop classes: Capital heavies are Hannibal, marksmen Spec Ops, recruits Regular (gun kept); the Ashguard have none")
    }

    static func segments(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player.pos + V3(40, 30, 0)
        let m = Mob(.soldierIronclad, at: p)
        m.setTroop(.hannibal, rearm: false)
        let top = p.y + m.height * 0.95, mid = p.y + m.height * 0.6, low = p.y + m.height * 0.2
        check(m.troopSegment(at: top) == 0 && m.troopSegment(at: mid) == 1 && m.troopSegment(at: low) == 2,
              "troop armour: a round at the head, chest and legs lands on the helmet, vest and greaves")
        let drops0 = g.drops.items.count
        var through: [Float] = []
        var crackedAt = -1, offAt = -1
        for i in 0..<12 {
            through.append(m.troopArmourHit(8, seg: 0, g))
            if crackedAt < 0 && m.troopSeg.x < TroopClass.hannibal.segMax.x * 0.5 { crackedAt = i + 1 }
            if offAt < 0 && m.troopSeg.x <= 0 { offAt = i + 1 }
        }
        let dropped = g.drops.items.count - drops0
        let piece = g.drops.items.last.map { Items.key($0.stack.item) } ?? "none"
        g.drops.items.removeSubrange(drops0..<g.drops.items.count)
        check(abs(through[0] - 8 * 0.35) < 0.01 && through[crackedAt] > through[0] && through.last == 8 && offAt > 0 && dropped == 1 && piece == "hannibal_helmet",
              String(format: "troop armour: a Hannibal helmet lets %.1f of 8 through, cracked after %d hits (then %.1f), shot off after %d (then 8: %.1f), dropping %@",
                     through[0], crackedAt, crackedAt >= 0 ? through[crackedAt] : -1, offAt, through.last ?? -1, piece))
        // Melee wears the vest.
        let v0 = m.troopSeg.y
        Mob.playerMelee = true
        m.invulnerable = 0
        m.hit(from: p + V3(1, 0, 0), damage: 7)
        Mob.playerMelee = false
        check(m.troopSeg.y < v0 && m.troopSeg.z == TroopClass.hannibal.segMax.z, String(format: "troop armour: a sword blow wears the vest (%.0f -> %.0f), not the greaves", v0, m.troopSeg.y))
        // Every class soaks more than the one below.
        let shares = TroopClass.allCases.map { c -> Float in let x = Mob(.soldierTrooper, at: p); x.setTroop(c, rearm: false); return x.troopArmourHit(10, seg: 1, nil) }
        check(shares[0] > shares[1] && shares[1] > shares[2], "troop armour: 10 to the vest lets through \(shares.map { String(format: "%.1f", $0) }.joined(separator: " / ")) (Regular / Spec Ops / Hannibal)")
    }

    static func saveAndLoot(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player.pos + V3(40, 30, 6)
        guard let m = grey("soldier_ironclad", .fortress, p) else { check(false, "troop save: key parses"); return }
        _ = m.troopArmourHit(25, seg: 1, nil)
        var d: [String: Float] = [:]
        m.saveExtra(&d)
        let back = Mob(Soldier.garrison(.soldierIronclad, at: p), at: p)
        back.variant = m.variant
        back.loadExtra(d)
        check(back.troopClass == .hannibal && back.troopSeg == m.troopSeg && back.soldierBrain.gun == m.soldierBrain.gun,
              "troop save: class, worn vest (\(Int(back.troopSeg.y))) and \(Guns.all[back.soldierBrain.gun].name) kept through a save")
        // Loot: of 60 fallen Hannibal troopers about a third of each surviving piece drops, with its life left.
        let drops0 = g.drops.items.count
        for i in 0..<60 {
            let x = Mob(.soldierIronclad, at: p + V3(Float(i % 6), 0, Float(i / 6)))
            x.setTroop(.hannibal, rearm: false)
            x.killedByPlayer = true
            x.troopSeg.y = TroopClass.hannibal.segMax.y * 0.5
            x.troopLoot(g)
        }
        let got = g.drops.items[drops0...].map { $0.stack }
        g.drops.items.removeSubrange(drops0..<g.drops.items.count)
        let vests = got.filter { Items.key($0.item) == "hannibal_vest" }
        let half = vests.allSatisfy { s in let dur = Items.def(s.item).durability; return abs(Float(dur - s.damage) / Float(dur) - 0.5) < 0.05 }
        check(got.count > 30 && got.count < 95 && !vests.isEmpty && half,
              "troop loot: 60 fallen Hannibal troopers drop \(got.count) pieces (\(vests.count) vests, each with the half life it had left: \(half))")
        let vest = Items.id("hannibal_vest")
        check(Enchant.repairMaterial(vest) == "steel_ingot" && Items.def(vest).armorSlot == .chest && Items.def(vest).armor > Items.def(Items.id("iron_chestplate")).armor,
              "troop loot: a Hannibal Vest is worn on the chest (\(Items.def(vest).armor) armour) and repaired with steel")
    }

    static func behaviour(_ g: Game, _ check: (Bool, String) -> Void) {
        let p0 = g.player.pos, surv0 = g.survival, alive0 = g.alive
        defer { g.player.pos = p0; g.survival = surv0; g.alive = alive0 }
        g.survival = true; g.alive = true
        let base = V3(p0.x, p0.y + 60, p0.z)
        g.player.pos = base; g.player.vel = .zero
        // Spec Ops flank: the spot they pick is well off the line between them and the target.
        var angles: [Float] = []
        for i in 0..<12 {
            let at = base + V3(14, 0, Float(i) * 0.1)
            let m = Mob(.soldierTrooper, at: at)
            m.setTroop(.specOps)
            m.soldierBrain.gun = Guns.smg; m.soldierBrain.react = 0; m.soldierBrain.flankTimer = 0
            m.aggro = true; m.soldierBrain.sees = true; m.soldierBrain.losTimer = 5
            _ = m.soldierAI(0.05, g, dist: simd_length(at - base), canTarget: true)
            guard let f = m.soldierBrain.flank else { continue }
            let a = simd_normalize(V2(at.x - base.x, at.z - base.z)), b = simd_normalize(V2(f.x - base.x, f.z - base.z))
            angles.append(acosf(max(-1, min(1, simd_dot(a, b)))) * 180 / .pi)
        }
        let mean = angles.isEmpty ? 0 : angles.reduce(0, +) / Float(angles.count)
        check(angles.count >= 10 && mean > 60 && mean < 95, String(format: "troop behaviour: Spec Ops flank %.0f degrees off the line on average (%d of 12 picked a flank)", mean, angles.count))
        // Hannibal push: it walks in while firing at mid range.
        let h = Mob(.soldierIronclad, at: base + V3(12, 0, 0))
        h.setTroop(.hannibal)
        h.aggro = true; h.soldierBrain.react = 0; h.soldierBrain.sees = true; h.soldierBrain.losTimer = 5
        let sp = h.soldierAI(0.05, g, dist: 12, canTarget: true)
        let r = Mob(.soldierRecruit, at: base + V3(12, 0, 0))
        r.setTroop(.regular)
        r.aggro = true; r.soldierBrain.react = 0; r.soldierBrain.sees = true; r.soldierBrain.losTimer = 5
        let sr = r.soldierAI(0.05, g, dist: 12, canTarget: true)
        check(sp > 0.4 * h.spec.speed && sp >= sr, String(format: "troop behaviour: a Hannibal trooper pushes in at 12 blocks (%.2f, a Regular %.2f)", sp, sr))
        let q = Mob(.soldierTrooper, at: base); q.setTroop(.specOps); q.soldierBrain.gun = Guns.smg
        let s = Mob(.soldierMarksman, at: base); s.setTroop(.specOps)
        check(TroopClass.suppressed(q) && !TroopClass.suppressed(s), "troop behaviour: Spec Ops SMGs are suppressed, their scoped rifles are not")
    }

    // Time to kill, both ways. Soldier side: full plate, chest hits. Player side: the soldier's gun at Normal against
    // the player's armour set (the reference armour formula).
    static func ttk(_ g: Game, _ check: (Bool, String) -> Void) {
        func hitsToKill(_ c: TroopClass, _ kind: MobKind, _ dmg: Float) -> Int {
            let m = Mob(kind, at: g.player.pos + V3(40, 30, 12))
            m.setTroop(c, rearm: false)
            var hp = Float(m.spec.health), n = 0
            let (a, t) = m.armorPoints
            while hp > 0 && n < 400 {
                var d = m.troopArmourHit(dmg, seg: 1, nil)
                let f = min(20, max(Float(a) / 5, Float(a) - d / (2 + t / 4))) / 25
                d *= 1 - f
                hp -= max(1, d); n += 1
            }
            return n
        }
        let weapons: [(String, Float, Float)] = [
            ("iron sword", Items.def(Items.id("iron_sword")).attack, 1 / Items.def(Items.id("iron_sword")).attackSpeed),
            ("Duskium sword", Items.def(Items.id("netherite_sword")).attack, 1 / Items.def(Items.id("netherite_sword")).attackSpeed),
            (Guns.all[Guns.rifle].name, Guns.all[Guns.rifle].damage, Guns.all[Guns.rifle].interval),
            (Guns.all[Guns.smg].name, Guns.all[Guns.smg].damage, Guns.all[Guns.smg].interval),
            (Guns.all[Guns.sniper].name, Guns.all[Guns.sniper].damage, Guns.all[Guns.sniper].interval),
        ]
        let kinds: [(TroopClass, MobKind)] = [(.regular, .soldierRecruit), (.specOps, .soldierTrooper), (.hannibal, .soldierIronclad)]
        var lines = ["| class (as) | " + weapons.map { $0.0 }.joined(separator: " | ") + " |", "|---|" + weapons.map { _ in "---|" }.joined()]
        var secs: [[Float]] = []
        for (c, k) in kinds {
            var row: [Float] = []
            for w in weapons { row.append(Float(hitsToKill(c, k, w.1) - 1) * w.2) }
            secs.append(row)
            lines.append("| \(c.name) (\(Mob(k, at: .zero).spec.name)) | " + row.map { String(format: "%.1f s", $0) }.joined(separator: " | ") + " |")
        }
        // The soldier's guns against the player's armour.
        let sets: [(String, Int, Float)] = [("none", 0, 0), ("iron", 15, 0), ("steel", 17, 1), ("Titanium", 20, 2), ("Duskium", 20, 3)]
        let scale = Soldier.difficultyScale(2)
        var back = ["| soldier gun | " + sets.map { $0.0 }.joined(separator: " | ") + " |", "|---|" + sets.map { _ in "---|" }.joined()]
        for gi in [Guns.rifle, Guns.smg, Guns.sniper, Guns.ashsaw] {
            let gs = Guns.all[gi]
            var row: [String] = []
            for (_, a, t) in sets {
                var hp: Float = 20, n = 0
                while hp > 0 && n < 400 {
                    let d = gs.damage * scale
                    let f = min(20, max(Float(a) / 5, Float(a) - d / (2 + t / 4))) / 25
                    hp -= max(1, d * (1 - f)); n += 1
                }
                row.append(String(format: "%.1f s", Float(n - 1) * gs.interval))
            }
            back.append("| \(gs.name) | " + row.joined(separator: " | ") + " |")
        }
        print("troop TTK (seconds of continuous hits to the vest, Normal):\n" + lines.joined(separator: "\n") + "\n" + back.joined(separator: "\n"))
        let rising = (0..<weapons.count).allSatisfy { secs[0][$0] <= secs[1][$0] && secs[1][$0] <= secs[2][$0] }
        check(rising && secs[2][0] < 30, String(format: "troop TTK: every weapon takes longer on each class up (iron sword %.1f / %.1f / %.1f s)", secs[0][0], secs[1][0], secs[2][0]))
        if CommandLine.arguments.contains("--write-ttk") {
            let doc = """
            # Troop classes: time-to-kill table (backlog A2)

            Written by `questcheck --troopclasses-only --write-ttk` (TroopTests.ttk); the numbers come from the game's own
            damage code. Classes and rules: Sources/TroopClasses.swift.

            ## Player weapons against each class (full plate, every hit on the vest)

            \(lines.joined(separator: "\n"))

            ## Soldier guns against the player's armour (Normal, continuous hits, 20 health)

            \(back.joined(separator: "\n"))
            """
            try? doc.write(toFile: "docs/status/troop-classes-ttk.md", atomically: true, encoding: .utf8)
        }
    }
}
