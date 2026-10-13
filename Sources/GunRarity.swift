import Foundation

// Gun rarity (backlog T7). A gun stack carries a grade (ItemStack.grade, saved as "q"): tier * 100 + a roll 0-99
// inside the tier's stat range. Common guns are grade 0 and play as before.
//   tier     damage        recoil         reload
//   Common   x1.00         x1.00          x1.00
//   Fine     x1.04-1.10    x0.94-0.88     x0.96-0.92
//   Rare     x1.10-1.20    x0.88-0.78     x0.92-0.84
//   Elite    x1.20-1.32    x0.78-0.66     x0.84-0.74
// Where they come from: a soldier's dropped gun rolls by its class (Spec Ops and Hannibal carry better), base and
// citadel chests by the chest (vaults and command rooms the best). The grade shows in the name ("Rare Rifle") and the
// tooltip.
enum GunGrade {
    static let names = ["Common", "Fine", "Rare", "Elite"]
    static let colours: [V4] = [V4(0.8, 0.8, 0.8, 1), V4(0.45, 1, 0.45, 1), V4(0.4, 0.65, 1, 1), V4(1, 0.55, 1, 1)]
    private static let damageRange: [(Float, Float)] = [(1, 1), (1.04, 1.10), (1.10, 1.20), (1.20, 1.32)]
    private static let recoilRange: [(Float, Float)] = [(1, 1), (0.94, 0.88), (0.88, 0.78), (0.78, 0.66)]
    private static let reloadRange: [(Float, Float)] = [(1, 1), (0.96, 0.92), (0.92, 0.84), (0.84, 0.74)]

    static func tier(_ s: ItemStack) -> Int { max(0, min(3, s.grade / 100)) }
    private static func pick(_ r: [(Float, Float)], _ s: ItemStack) -> Float {
        let t = tier(s), q = Float(s.grade % 100) / 99
        return r[t].0 + (r[t].1 - r[t].0) * q
    }
    static func damage(_ s: ItemStack) -> Float { s.grade == 0 ? 1 : pick(damageRange, s) }
    static func recoil(_ s: ItemStack) -> Float { s.grade == 0 ? 1 : pick(recoilRange, s) }
    static func reload(_ s: ItemStack) -> Float { s.grade == 0 ? 1 : pick(reloadRange, s) }

    // The name prefix ("Rare "), none for a common gun.
    static func prefix(_ s: ItemStack) -> String { tier(s) > 0 && Guns.index(s.item) != nil ? names[tier(s)] + " " : "" }

    static func tooltip(_ s: ItemStack) -> String? {
        guard tier(s) > 0 else { return nil }
        let d = Int(((damage(s) - 1) * 100).rounded()), r = Int(((1 - recoil(s)) * 100).rounded()), l = Int(((1 - reload(s)) * 100).rounded())
        return "\(names[tier(s)]): +\(d)% damage, -\(r)% recoil, -\(l)% reload"
    }

    // Tier weights (common, fine, rare, elite) by source.
    static let soldierWeights: [Int: [Int]] = [0: [74, 20, 5, 1], 1: [74, 20, 5, 1], 2: [45, 35, 16, 4], 3: [25, 40, 27, 8]]
    static func chestWeights(_ table: String) -> [Int]? {
        if table.hasSuffix("_vault") || table.hasSuffix("_command") { return [15, 40, 33, 12] }
        if table.hasPrefix("greywall") || table.hasPrefix("steelhold") || table.hasPrefix("capital") || table.hasPrefix("military") { return [55, 30, 12, 3] }
        return [70, 22, 7, 1]
    }

    // A grade from weights and a 0..<1 roll for the tier and one for the place inside it.
    static func roll(_ weights: [Int], _ u: Float, _ v: Float) -> Int {
        let total = weights.reduce(0, +)
        var r = Int(u * Float(total))
        for (t, wt) in weights.enumerated() {
            r -= wt
            if r < 0 { return t == 0 ? 0 : t * 100 + min(99, Int(v * 100)) }
        }
        return 0
    }

    // Grades the ungraded guns a freshly filled chest holds.
    static func gradeChest(_ c: ItemContainer, table: String, rng: inout SRng) {
        guard let w = chestWeights(table) else { return }
        for i in 0..<c.count where !c[i].isEmpty && c[i].grade == 0 && Guns.index(c[i].item) != nil {
            var s = c[i]
            s.grade = roll(w, rng.float(), rng.float())
            c[i] = s
        }
    }
}
