import Foundation
import simd

// D11 throwing knives and tomahawks. Use one to throw it (no wind-up): it flies like a thrown trident (a thrown
// ProjectileManager arrow carrying the stack), sticks where it lands and is picked up again by walking over it.
//   throwing knife   6 damage, fast and flat, stacks of 8; iron ingot over a stick makes four
//   tomahawk         9 damage and a heavy knock back, slower and dropping more; two iron ingots on a stick
// Both are silent (no gunshot for camps or bases to hear) and take the edge upgrades a blade does in damage.
enum ThrownBlades {
    static let knife = "throwing_knife", tomahawk = "tomahawk"
    static var thrown = 0                              // (tests)

    static func isBlade(_ item: ItemID) -> Bool { let k = Items.key(item); return k == knife || k == tomahawk }
    static func damage(_ s: ItemStack) -> Int? {
        switch Items.key(s.item) {
        case knife: return 6
        case tomahawk: return 9
        default: return nil
        }
    }
    static func speed(_ s: ItemStack) -> Float { Items.key(s.item) == knife ? 46 : 34 }
}

extension ItemRegistry {
    func registerThrownBlades() {
        guard !has(ThrownBlades.knife) else { return }
        var k = ItemDef(ThrownBlades.knife, "Throwing Knife")
        k.sprite = Sprite(mask: "sword", base: 0xB8BEC6, extras: [:])
        k.maxStack = 8
        add(k)
        var t = ItemDef(ThrownBlades.tomahawk, "Tomahawk")
        t.sprite = Sprite(mask: "axe", base: 0x9EA4AC, extras: [:])
        t.maxStack = 4
        add(t)
    }
}

extension Game {
    // Use with a throwing blade in hand: throw one.
    func throwBlade(_ useNow: Bool) -> Bool {
        let h = held
        guard ThrownBlades.isBlade(h.item) else { return false }
        guard useNow else { return true }
        let from = vrAim?.origin ?? player.eye
        let dir = vrAim?.dir ?? player.look
        let a = projectiles.shoot(from: from + dir * 0.3, dir: dir, speed: ThrownBlades.speed(h), fromPlayer: true, damage: 1)
        var one = h; one.count = 1
        a.trident = one
        a.pickup = survival
        if survival {
            var rest = h; rest.count -= 1
            inventory.held = rest.count > 0 ? rest : .empty
        }
        sfx(.tridentThrow, Items.key(h.item) == ThrownBlades.knife ? 0.6 : 0.9)
        swing = 1
        ThrownBlades.thrown += 1
        return true
    }
}
