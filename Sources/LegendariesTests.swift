import Foundation
import simd

// Legendary weapons and armour (backlog C10), `questcheck --legends-only`:
//   catalogue  eleven legendaries with distinct keys and names, each with a base item that exists, a perk and a story
//   item       the stack carries its name, gold tooltip lines and a save round trip; two never stack
//   once       a boss killed by the player drops its legendary once per world; a legendary animal's body gives its own;
//              the first command fortress hands over the Aegis; a reload keeps what was found
//   perks      Greyfang +30% and heals; the Marshal's Word +40% damage and no recoil; the Aegis takes 35% off a bullet;
//              the Blightward Helm gives night vision and clears withering; Hush gives speed
//   gallery    legendaries in item frames near the player count as the gallery
enum LegendariesTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let saved = (Legendaries.found, Legendaries.galleryBest)
        let inv = (g.inventory.main.slots, g.inventory.armor.slots, g.inventory.selected)
        let surv = g.survival, hp = g.health
        defer {
            (Legendaries.found, Legendaries.galleryBest) = saved
            g.inventory.main.slots = inv.0; g.inventory.armor.slots = inv.1; g.inventory.selected = inv.2
            g.survival = surv; g.health = hp
            g.drops.items.removeAll()
        }
        Legendaries.reset()
        let all = Legendaries.all
        let made = all.compactMap(Legendaries.make)
        let keys = Set(all.map { $0.key }), names = Set(all.map { $0.name })
        check(all.count == 11 && keys.count == 11 && names.count == 11 && made.count == 11 && all.allSatisfy { !$0.story.isEmpty && !$0.perkLine.isEmpty },
              "C10 catalogue: \(all.count) legendaries, \(made.count) with a base item here (\(made.map { Items.key($0.item) }.joined(separator: ", ")))")

        // The item.
        let fang = Legendaries.make(all[0])!
        let back = (try? JSONEncoder().encode(fang)).flatMap { try? JSONDecoder().decode(ItemStack.self, from: $0) }
        let tip = Legendaries.tooltip(fang)
        check(fang.displayName == "Greyfang" && back?.legend == "greyfang" && back?.displayName == "Greyfang" && !fang.stacks(with: fang)
              && tip.first == "Legendary" && tip.count >= 3,
              "C10 item: \"\(fang.displayName)\" (\(Items.key(fang.item))), tooltip \(tip), survives a save, never stacks")

        // Found once.
        let n0 = g.drops.items.count
        func boss(_ k: MobKind) { let m = Mob(k, at: g.player.pos + V3(4, 0, 0)); m.killedByPlayer = true; Legendaries.bossDied(g, m) }
        boss(.brandCommander); boss(.brandCommander)
        let wither = g.drops.items.count - n0
        let notMine = Mob(.warden, at: g.player.pos); Legendaries.bossDied(g, notMine)
        Legendaries.animalDied(g, 1, at: g.player.pos)
        Legendaries.fortressTaken(g, .garrison)
        Legendaries.fortressTaken(g, .command)
        let aegisInBag = g.inventory.main.slots.contains { $0.legend == "greywall_aegis" }
        var d: [String: String] = [:]
        Legendaries.save(&d)
        let found = Legendaries.found
        Legendaries.load(d)
        check(wither == 1 && !found.contains("hush_boots") && found.contains("frostjaw_mantle") && aegisInBag && Legendaries.found == found
              && found.count == 3,
              "C10 found once: the Blight twice gave \(wither) drop; a Warden not killed by you none; Frostjaw's body the Mantle; the command fortress the Aegis (in the pack: \(aegisInBag)); \(found.count) found survive a reload")

        // Perks.
        g.survival = true
        g.inventory.selected = 0
        g.inventory.main.slots[0] = fang
        let zombie = Mob(.zombie, at: g.player.pos + V3(2, 0, 0))
        let scale = Legendaries.meleeScale(g, zombie)
        g.health = 10
        Legendaries.meleeHit(g, zombie)
        let healed = g.health > 10
        let word = Legendaries.make(all.first { $0.key == "marshals_word" }!)!
        let plainRev = ItemStack(word.item, 1)
        let gun = (Legendaries.gunScale(word), Guns.steadiness(word), Legendaries.gunScale(plainRev), Guns.steadiness(plainRev))
        g.inventory.armor.slots = [ItemStack](repeating: .empty, count: 4)
        g.inventory.armor.slots[2] = Legendaries.make(all.first { $0.key == "greywall_aegis" }!)!
        var shots = 0
        for _ in 0..<200 { shots += Legendaries.taken(g, 10, .projectile, attacker: nil) }
        let fall = Legendaries.taken(g, 10, .fall, attacker: nil)
        g.inventory.armor.slots[3] = Legendaries.make(all.first { $0.key == "blightward_helm" }!)!
        g.inventory.armor.slots[0] = Legendaries.make(all.first { $0.key == "hush_boots" }!)!
        g.applyEffect(.wither, amp: 0, seconds: 10)
        Legendaries.tick(g)
        let nv = g.effects.has(.nightVision), wi = g.effects.has(.wither), sp = g.effects.has(.speed)
        check(scale == 1.3 && healed && gun.0 == 1.4 && gun.1 == 0 && gun.2 == 1 && gun.3 == 1 && shots / 200 >= 6 && shots / 200 <= 7 && fall == 10 && nv && !wi && sp,
              "C10 perks: Greyfang x\(scale), heals \(healed); the Marshal's Word damage x\(gun.0) recoil x\(gun.1) (plain x\(gun.2)/x\(gun.3)); the Aegis takes a 10 bullet to \(Float(shots) / 200), a fall stays \(fall); the Helm night vision \(nv), withering gone \(!wi); Hush speed \(sp)")

        // The gallery.
        let w = g.world
        let p = g.player.pos
        var spots: [IVec3] = []
        for (i, k) in ["greyfang", "greywall_aegis", "tidecaller"].enumerated() {
            let q = IVec3(Int(floor(p.x)) + 3 + i, Int(floor(p.y)) + 1, Int(floor(p.z)) + 3)
            let be = w.entity(q, .frame)
            be.container[0] = Legendaries.make(Legendaries.def(k)!)!
            w.blockEntities[q] = be
            spots.append(q)
        }
        defer { for q in spots { w.blockEntities[q] = nil } }
        Legendaries.galleryBest = 0
        let count = Legendaries.gallery(g)
        check(count == 3 && Legendaries.galleryBest == 3, "C10 gallery: \(count) legendaries in item frames near you count as your gallery")
    }
}
