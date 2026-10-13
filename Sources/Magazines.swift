import Foundation

// Magazines (P119, Oct 12 PM: "make magazines out of ammo, that way they don't take up so much inventory space"):
// loose rounds are packed into magazines in the crafting book (the rounds plus an iron nugget for the case). A
// magazine stacks 16 and holds a full load (30 Capital rounds: 480 to a slot where loose rounds fit 64). Guns load
// from loose rounds first, then open a magazine (what it doesn't use goes back as loose rounds), so ammo counts,
// reloads and the hip grab (VRReload) all see magazines as rounds.
enum Magazines {
    struct Kind { let ammo: String; let key: String; let name: String; let rounds: Int }
    static let kinds: [Kind] = [
        Kind(ammo: "capital_rounds", key: "capital_magazine", name: "Capital Magazine", rounds: 30),
        Kind(ammo: "rifle_rounds", key: "rifle_magazine", name: "Rifle Magazine", rounds: 24),
        Kind(ammo: "shotgun_shells", key: "shell_box", name: "Shotgun Shell Box", rounds: 12),
        Kind(ammo: "heavy_rounds", key: "heavy_magazine", name: "Heavy Magazine", rounds: 10),
        Kind(ammo: GreywallArms.ammo, key: "slate_magazine", name: "Slate Magazine", rounds: 24),
    ]
    static func of(ammo: String) -> Kind? { kinds.first { $0.ammo == ammo } }
    static func isMagazine(_ key: String) -> Bool { kinds.contains { $0.key == key } }

    static func register(_ reg: ItemRegistry) {
        for k in kinds where !reg.has(k.key) {
            var d = ItemDef(k.key, k.name)
            d.texKey = "item_" + k.key
            d.maxStack = 16
            reg.add(d)
        }
    }

    // Packing a magazine: its rounds plus an iron nugget (crafted from the inventory: more ingredients than a grid holds).
    static func recipes() -> [Recipe?] {
        kinds.map { Recipes.shapeless([String](repeating: $0.ammo, count: $0.rounds) + ["iron_nugget"], $0.key) }
    }

    // A steel box with a lighter band and the top round showing, tinted by the rounds it holds.
    static func painters(_ p: inout [String: TextureGen.Painter]) {
        let rows = ["................", "................", ".......yy.......", "......1yy1......", ".....1mmmm1.....",
                    ".....1dddd1.....", ".....1aaaa1.....", ".....1dddd1.....", ".....1dddd1.....", ".....1aaaa1.....",
                    ".....1dddd1.....", ".....1dddd1.....", ".....1mmmm1.....", "......1111......", "................", "................"]
        let grid = rows.map { Array($0) }
        let tints: [String: V3] = ["capital_magazine": V3(0.8, 0.83, 0.88), "rifle_magazine": V3(0.72, 0.5, 0.3),
                                   "shell_box": V3(0.7, 0.14, 0.12), "heavy_magazine": V3(0.55, 0.6, 0.35), "slate_magazine": V3(0.45, 0.5, 0.58)]
        for k in kinds {
            let a = tints[k.key] ?? V3(0.6, 0.6, 0.6)
            p["item_" + k.key] = { x, y in
                guard y < grid.count, x < grid[y].count else { return TextureGen.clear }
                let h = 0.92 + 0.08 * hashf(x, y, 37, 4343)
                switch grid[y][x] {
                case "1": return V4(0.08, 0.08, 0.09, 1)
                case "d": return V4(0.24 * h, 0.25 * h, 0.27 * h, 1)
                case "m": return V4(0.45 * h, 0.47 * h, 0.5 * h, 1)
                case "a": return V4(a.x * h, a.y * h, a.z * h, 1)
                case "y": return V4(0.86 * h, 0.68 * h, 0.25 * h, 1)
                default: return TextureGen.clear
                }
            }
        }
    }
}

extension Game {
    // Rounds of `ammo` in magazines in the pack.
    func magazineRounds(_ ammo: String) -> Int {
        guard let k = Magazines.of(ammo: ammo) else { return 0 }
        let id = Items.id(k.key)
        var n = 0
        for i in 0..<inventory.main.count where inventory.main[i].item == id { n += inventory.main[i].count }
        return n * k.rounds
    }

    // Takes `count` rounds out of magazines (after the loose rounds ran out): a magazine opened and not used up leaves
    // its other rounds in the pack as loose rounds.
    func takeMagazineRounds(_ ammo: String, _ count: Int) {
        guard let k = Magazines.of(ammo: ammo), count > 0 else { return }
        let id = Items.id(k.key)
        var left = count
        var spare = 0
        for i in 0..<inventory.main.count where left > 0 && inventory.main[i].item == id {
            var s = inventory.main[i]
            while left > 0 && s.count > 0 {
                s.count -= 1
                let used = min(left, k.rounds)
                left -= used
                spare += k.rounds - used
            }
            inventory.main[i] = s.count > 0 ? s : .empty
        }
        if spare > 0 {
            let rest = inventory.add(ItemStack(Items.id(ammo), spare))
            if !rest.isEmpty { dropItem(rest) }
        }
    }
}
