import Foundation
import simd

// D33: wearable faction armour sets. Each of the three armies keeps a set of its own kit in its armouries; one use of
// the set puts on all four pieces (like the troop class sets, P204). A full set worn gives its army's edge:
//   Greywall field kit    slate and webbing     [2, 6, 5, 2], toughness 1   light: Speed I
//   Capital officer kit   white plate and gold  [3, 7, 6, 3], toughness 2   drilled: Resistance I
//   Ashguard ember kit    blackened, ember-lit  [3, 8, 6, 3], toughness 2   forged in hell: Fire Resistance
// Where: a Greywall armoury chest holds the Greywall set one time in three, a Capital armoury the Capital set, an
// Ashguard armoury the Ashguard set (Loot.extraPools). Repaired at an anvil with steel like the troop pieces.
enum FactionArmour {
    struct Kit { let key: String; let name: String; let pieces: [String]; let armor: [Int]; let tough: Float; let colour: UInt32; let trim: UInt32
                 let effect: Effect }
    static let kits: [Kit] = [
        Kit(key: "greywall", name: "Greywall Field", pieces: ["Cap", "Webbing", "Trousers", "Boots"], armor: [2, 6, 5, 2], tough: 1,
            colour: 0x5E6670, trim: 0x8A7A52, effect: .speed),
        Kit(key: "capital", name: "Capital Officer's", pieces: ["Helm", "Cuirass", "Tassets", "Boots"], armor: [3, 7, 6, 3], tough: 2,
            colour: 0xD8DCE2, trim: 0xC8A24A, effect: .resistance),
        Kit(key: "ashguard", name: "Ashguard Ember", pieces: ["Helm", "Plate", "Greaves", "Sabatons"], armor: [3, 8, 6, 3], tough: 2,
            colour: 0x2A2624, trim: 0xE0602A, effect: .fireResistance),
    ]
    static let slots: [(ArmorSlot, String, Int)] = [(.head, "helmet", 11), (.chest, "chestplate", 16), (.legs, "leggings", 15), (.feet, "boots", 13)]
    static func pieceKey(_ k: Kit, _ i: Int) -> String { "\(k.key)_kit_\(slots[i].1)" }
    static func setKey(_ k: Kit) -> String { "\(k.key)_armour_kit" }

    // The kit the player wears in full, if any.
    static func worn(_ g: Game) -> Kit? {
        kits.first { k in (0..<4).allSatisfy { i in Items.key(g.inventory.armor[slots[i].0.rawValue].item) == pieceKey(k, i) } }
    }

    // Once a second (TownLaw.tick): the full set's edge.
    static func tick(_ g: Game) {
        guard let k = worn(g) else { return }
        g.applyEffect(k.effect, amp: 0, seconds: 2.5, ambient: true)
    }
}

extension ItemRegistry {
    func registerFactionArmour() {
        for k in FactionArmour.kits {
            let sk = FactionArmour.setKey(k)
            if !has(sk) {
                var d = ItemDef(sk, "\(k.name) Armour Set")
                d.sprite = Sprite(mask: "chestplate", base: k.colour, extras: ["c": k.trim])
                d.maxStack = 1
                add(d)
            }
            for i in 0..<4 where !has(FactionArmour.pieceKey(k, i)) {
                var d = ItemDef(FactionArmour.pieceKey(k, i), "\(k.name) \(k.pieces[i])")
                d.sprite = Sprite(mask: FactionArmour.slots[i].1, base: k.colour, extras: ["c": k.trim])
                d.maxStack = 1
                d.armorSlot = FactionArmour.slots[i].0
                d.armor = k.armor[i]
                d.toughness = k.tough
                d.durability = FactionArmour.slots[i].2 * 30
                add(d)
            }
        }
    }
}

extension Game {
    // A held faction set, used: its four pieces go on (whatever was worn goes to the pack).
    func wearFactionKit() -> Bool {
        let st = held
        guard !st.isEmpty, let k = FactionArmour.kits.first(where: { FactionArmour.setKey($0) == Items.key(st.item) }) else { return false }
        for i in 0..<4 where Items.has(FactionArmour.pieceKey(k, i)) {
            let a = FactionArmour.slots[i].0.rawValue
            let old = inventory.armor[a]
            inventory.armor[a] = ItemStack(Items.id(FactionArmour.pieceKey(k, i)), 1)
            if !old.isEmpty { let rest = inventory.add(old); if !rest.isEmpty { dropItem(rest) } }
        }
        inventory.held = .empty
        sfx(.armorEquip(0), 0.8, at: player.eye)
        onToast?("\(k.name) armour on")
        return true
    }
}
