import Foundation
import simd

// P508 (Remington, Nov 1 16:26: "maybe some sort of material required to build high tech stuff maybe make it only found
// in those bases... Lets entirely scrap the XP system too"): no experience. Nothing gives levels, no orbs drop, and the
// survival HUD has no experience bar. What levels paid for is now paid in Tech Salvage, salvaged electronics found in
// the chests of the armies' bases (wherever a Bottle of Experience was loot it is Tech Salvage): the Upgrade Bench takes
// it with the item's own materials (Upgrades.cost), and the field mending kit is built from it. A mending kit still
// repairs from what he does near it (the deeds that gave experience: Game.addXP).
extension Game {
    static let xpOn = false
}

enum TechSalvage {
    static let key = "tech_salvage"
}

extension ItemRegistry {
    func registerTechSalvage() {
        guard !has(TechSalvage.key) else { return }
        var d = ItemDef(TechSalvage.key, "Tech Salvage")
        d.sprite = Sprite(mask: "module", base: 0x3E5A48, extras: ["c": 0xD8B04A, "d": 0x8FB8C8])
        add(d)
    }
}
