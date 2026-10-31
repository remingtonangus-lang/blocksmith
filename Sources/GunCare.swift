import Foundation
import simd

// D9 the suppressor and gun cleaning at camp.
//   suppressor  crafted (iron, wool, an iron ingot core); fitted to a rifle, carbine, pistol or revolver at a lit
//               campfire (the shotgun, launcher and arc gun take none). A suppressed shot is a cough, not a crack:
//               quiet, no muzzle flash worth the name, townsfolk don't come running, soldiers hear it only up close and
//               no base patrol is sent; it costs a little damage and range. Kept in the gun (ItemStack.contents).
//   cleaning    at a lit campfire, a rag (a string) cleans a worn gun: 60% of its wear comes off and the jams go.
// Both from the camp menu: use a lit campfire with a gun in hand.
enum GunCare {
    static let suppressor = "suppressor"
    static let damageScale: Float = 0.9, rangeScale: Float = 0.85
    static let volume: Float = 0.3
    static let soldiersHear: Float = 9
    static var cleaned = 0                             // (tests)

    static func takesSuppressor(_ gi: Int) -> Bool { gi != Guns.shotgun && gi != Guns.autoShotgun && !Guns.isLauncher(gi) && gi != Guns.arc }
    static func suppressed(_ s: ItemStack) -> Bool { s.contents?.contains { Items.key($0.item) == suppressor } ?? false }
    static func suppressedHeld(_ g: Game) -> Bool { g.heldGun != nil && suppressed(g.held) }

    static func fit(_ g: Game, slot: Int) -> (String, Bool) {
        var s = g.inventory.main[slot]
        guard let gi = Guns.index(s.item), takesSuppressor(gi), !suppressed(s) else { return ("That gun can't take one.", false) }
        guard g.inventory.main.countOf(Items.id(suppressor)) > 0 else { return ("No suppressor. Craft one: iron, wool and an ingot core.", false) }
        _ = g.inventory.main.remove(Items.id(suppressor), 1)
        s = g.inventory.main[slot]                    // (the removal may have shifted nothing, but read it fresh)
        s.contents = (s.contents ?? []) + [ItemStack(Items.id(suppressor), 1)]
        g.inventory.main[slot] = s
        g.sfx(.gunReload(Guns.all[gi].sound), 0.6)
        return ("Suppressor threaded on the \(s.displayName).", true)
    }

    static func remove(_ g: Game, slot: Int) -> (String, Bool) {
        var s = g.inventory.main[slot]
        guard suppressed(s) else { return ("Nothing fitted.", false) }
        s.contents = s.contents?.filter { Items.key($0.item) != suppressor }
        if s.contents?.isEmpty == true { s.contents = nil }
        g.inventory.main[slot] = s
        let rest = g.inventory.add(ItemStack(Items.id(suppressor), 1))
        if !rest.isEmpty { g.dropItem(rest) }
        g.sfx(.gunReload(Guns.all[Guns.index(s.item) ?? 0].sound), 0.5)
        return ("Suppressor off.", true)
    }

    static func clean(_ g: Game, slot: Int) -> (String, Bool) {
        var s = g.inventory.main[slot]
        guard Guns.index(s.item) != nil, s.damage > 0 else { return ("It's clean.", false) }
        if g.survival {
            guard g.inventory.main.countOf(Items.id("string")) > 0 else { return ("No rag: a string will do.", false) }
            _ = g.inventory.main.remove(Items.id("string"), 1)
            s = g.inventory.main[slot]
        }
        s.damage = Int(Float(s.damage) * 0.4)
        g.inventory.main[slot] = s
        g.sfx(.gunReload(Guns.all[Guns.index(s.item) ?? 0].sound), 0.4)
        cleaned += 1
        return ("Cleaned and oiled: \(Repairs.describe(s)).", true)
    }
}

extension ItemRegistry {
    func registerGunCare() {
        guard !has(GunCare.suppressor) else { return }
        var d = ItemDef(GunCare.suppressor, "Suppressor")
        d.sprite = Sprite(mask: "rod", base: 0x3A3C42, extras: [:])
        d.maxStack = 4
        add(d)
    }
}

// The camp menu: every gun on you, to clean, and to fit or take off a suppressor.
final class GunCampMenu: ListMenu {
    init(game g: Game) {
        super.init("Gun Care", game: g)
        subtitle = "At the fire: clean (a string as a rag), fit or take off a suppressor"
        say("Pick a gun.", good: true)
    }

    // (main slot, action) for each row: 0 clean, 1 fit, 2 remove.
    var actions: [(Int, Int)] {
        var out: [(Int, Int)] = []
        for i in 0..<36 {
            let s = game.inventory.main[i]
            guard !s.isEmpty, let gi = Guns.index(s.item) else { continue }
            if s.damage > 0 { out.append((i, 0)) }
            if GunCare.suppressed(s) { out.append((i, 2)) } else if GunCare.takesSuppressor(gi) { out.append((i, 1)) }
        }
        return out
    }

    override var rows: [Row] {
        actions.map { (i, a) in
            let s = game.inventory.main[i]
            switch a {
            case 0: return Row(icon: s, name: s.displayName, detail: Repairs.describe(s), value: "Clean", enabled: true, good: true)
            case 1:
                let have = game.inventory.main.countOf(Items.id(GunCare.suppressor)) > 0
                return Row(icon: s, name: s.displayName, detail: have ? "Fit a suppressor" : "No suppressor on you", value: "Fit", enabled: true, good: have)
            default: return Row(icon: s, name: s.displayName, detail: "Suppressed", value: "Take off", enabled: true, good: true)
            }
        }
    }

    override func pressed(_ index: Int) {
        let acts = actions
        guard index < acts.count else { return }
        let (i, a) = acts[index]
        let (msg, ok) = a == 0 ? GunCare.clean(game, slot: i) : (a == 1 ? GunCare.fit(game, slot: i) : GunCare.remove(game, slot: i))
        say(msg, good: ok)
        if !ok { game.sfx(.villagerNo, 0.4) }
    }
}
