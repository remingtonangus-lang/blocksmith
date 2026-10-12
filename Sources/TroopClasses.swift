import Foundation
import simd

// Troop classes (backlog A2): every Capital and Greywall soldier is a Regular, a Spec Ops trooper or a Hannibal
// trooper. (Hannibal: a historical name, not one the reference games coined; tools/coined-terms.txt checked.)
//   armour    segmented: helmet, chest and legs, each with its own durability by class. A round lands on a segment
//             by height (melee on the chest); while a segment holds it soaks a share of the hit (Regular 30 %, Spec Ops
//             45 %, Hannibal 65 %) and wears by the full hit. Under half it is cracked (the plate goes dull, it soaks
//             less); at zero it falls off (a cracked piece drops; a broken helmet leaves the head bare) and that part
//             takes full damage. A fallen soldier's surviving pieces may drop with the durability they had left: loot
//             them and repair them at an anvil with steel.
//   guns      Regulars rifles and SMGs; Spec Ops scoped rifles or suppressed SMGs (quiet: no alarm noise) and grenades;
//             Hannibal heavy weapons (launchers, arc guns, the Ashsaw-class machine gun).
//   behaviour Regulars hold and patrol; Spec Ops flank wide and stay quiet until they fire; Hannibal troopers push in
//             while firing and suppress with long bursts (Soldiers.swift reads Mob.troopClass).
//   rarity    rises with the class: Regulars everywhere; Spec Ops the marksmen and officers, from the garrison tier
//             up; Hannibal only the heavies of fortresses, command fortresses and Capital citadels.
// Time to kill against the player's gear: docs/status/troop-classes-ttk.md (written by `--troopclasses-only --write-ttk`).
enum TroopClass: Int, CaseIterable {
    case regular = 1, specOps, hannibal

    var name: String { ["", "Regular", "Spec Ops", "Hannibal"][rawValue] }
    var key: String { ["", "regular", "specops", "hannibal"][rawValue] }
    // Helmet, chest, legs.
    var segMax: SIMD3<Float> { [SIMD3<Float>(0, 0, 0), SIMD3(20, 30, 20), SIMD3(30, 45, 30), SIMD3(60, 90, 60)][rawValue] }
    var absorb: Float { [0, 0.3, 0.45, 0.65][rawValue] }
    static let segNames = ["helmet", "vest", "greaves"]
    static let segLabels = ["Helmet", "Vest", "Greaves"]

    // The armour item for a segment, e.g. "specops_vest".
    func item(_ seg: Int) -> String { "\(key)_\(TroopClass.segNames[seg])" }
}

extension Mob {
    var troopClass: TroopClass? { ensureTroop(); return TroopClass(rawValue: Int(troop)) }

    // The class a soldier was born to, decided once (saved): Capital ranks by kind; Greywall soldiers by their base's
    // tier (greyTroop, from the structure key); never the Ashguard's (their plate is their own, AshUnits).
    func ensureTroop() {
        guard troop < 0 else { return }
        guard let r = Soldier.rank(kind), !kind.ash, faction != Faction.ashguard.rawValue, kind != .ashMarshal, kind != .ashChancellor else { troop = 0; return }
        let c: TroopClass
        switch r {
        case 3: c = .hannibal
        case 2, 4: c = .specOps
        default: c = .regular
        }
        setTroop(c, rearm: false)                 // (a Capital soldier keeps the gun its rank carries)
    }

    func setTroop(_ c: TroopClass, rearm: Bool = true) {
        troop = Int8(c.rawValue)
        troopSeg = c.segMax
        guard rearm else { return }
        // Its class's gun (kept through a save: the brain is rebuilt from `variant`).
        guard kind != .deckGun, Soldier.rank(kind) != nil else { return }
        let gun = TroopClass.pickGun(c, kind, roll: hashf(Int(pos.x * 7), Int(pos.y * 3), Int(pos.z * 5), 8101))
        variant = gun
        let b = soldierBrain
        b.gun = gun; b.mag = Guns.all[gun].mag
    }

    // A Greywall base's soldier: the class rises with the base's tier.
    func greyTroop(tier t: Greywall.Tier, at p: V3) {
        let roll = hashf(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)), 8102)
        guard t != .outpost else { setTroop(.regular); return }      // an outpost's garrison: Regulars only
        switch kind {
        case .soldierIronclad: setTroop(t.rawValue >= 2 ? .hannibal : .specOps)
        case .soldierMarksman: setTroop(t.rawValue >= 1 ? .specOps : .regular)
        case .soldierOfficer: setTroop(.specOps)
        case .soldierTrooper: setTroop(t.rawValue >= 3 && roll < 0.3 ? .specOps : .regular)
        default: setTroop(.regular)
        }
    }

    // The segment a hit at `y` (world) lands on: 0 helmet, 1 chest, 2 legs.
    func troopSegment(at y: Float) -> Int {
        let h = (y - pos.y) / max(0.5, height)
        return h > 0.78 ? 0 : (h < 0.45 ? 2 : 1)
    }

    // A hit on a segment: the share the plate soaks, its wear, cracking and falling off. Returns the damage that gets
    // through.
    func troopArmourHit(_ dmg: Float, seg: Int, _ g: Game?) -> Float {
        guard let c = troopClass, dmg > 0 else { return dmg }
        let left = troopSeg[seg], full = c.segMax[seg]
        guard left > 0 else { return dmg }
        let cracked = left < full * 0.5
        let soak = dmg * c.absorb * (cracked ? 0.6 : 1)
        let now = max(0, left - dmg)
        troopSeg[seg] = now
        if let g = g {
            let at = pos + V3(0, height * [0.9, 0.62, 0.3][seg], 0)
            if left >= full * 0.5 && now < full * 0.5 && now > 0 {
                g.sfx(.bulletImpact(.metal), 0.9, at: at)
                for _ in 0..<5 { g.particles.dust(STONE, at: at, count: 1, spread: 0.2) }
            }
            if now <= 0 {
                // The piece falls off: a cracked piece to loot (a tenth of its life left).
                g.sfx(.bulletImpact(.metal), 1.1, at: at)
                g.particles.explosion(at: at, power: 0.3)
                if Items.has(c.item(seg)) {
                    var s = ItemStack(Items.id(c.item(seg)), 1)
                    let dur = Items.def(s.item).durability
                    s.damage = dur - max(1, dur / 10)
                    g.drops.spawn(s, at: at)
                }
            }
        }
        return dmg - soak
    }

    // A fallen soldier's surviving pieces (35 % each, the player's kill only), with the life they had left.
    func troopLoot(_ g: Game) {
        guard killedByPlayer, let c = troopClass else { return }
        for seg in 0..<3 where troopSeg[seg] > 0 && Items.has(c.item(seg)) && Rand.float(in: 0..<1) < 0.35 {
            var s = ItemStack(Items.id(c.item(seg)), 1)
            let dur = Items.def(s.item).durability
            let frac = troopSeg[seg] / c.segMax[seg]
            s.damage = min(dur - 1, Int(Float(dur) * (1 - frac)))
            g.drops.spawn(s, at: pos + V3(0, 0.6, 0))
        }
    }
}

extension TroopClass {
    // Which gun a soldier of this class carries (Guns indices).
    static func pickGun(_ c: TroopClass, _ k: MobKind, roll r: Float) -> Int {
        switch c {
        case .regular:
            if k == .soldierOfficer || k == .soldierCrew { return Guns.pistol }
            if k == .soldierTrooper { return r < 0.5 ? Guns.shotgun : Guns.rifle }
            return r < 0.6 ? Guns.rifle : Guns.smg
        case .specOps:
            if k == .soldierMarksman { return Guns.sniper }
            return r < 0.7 ? Guns.smg : Guns.rifle
        case .hannibal:
            return r < 0.45 ? Guns.ashsaw : (r < 0.8 ? Guns.launcher : Guns.arc)
        }
    }
    // Spec Ops SMGs and rifles are suppressed: quiet, and their shots don't carry to a base as noise.
    static func suppressed(_ m: Mob) -> Bool { m.troop == 2 && m.soldierBrain.gun != Guns.sniper }
}

extension ItemRegistry {
    // The troop classes' armour pieces: wearable, repaired with steel ingots (Enchant.repairMaterial).
    func registerTroopArmour() {
        let stats: [(TroopClass, [Int], Float, Int, UInt32)] = [
            (.regular, [2, 6, 5], 0, 20, 0x6E7A60), (.specOps, [2, 7, 5], 1, 26, 0x2A2D33), (.hannibal, [3, 8, 7], 3, 36, 0x5A5F66),
        ]
        let slots: [(ArmorSlot, String, Int)] = [(.head, "helmet", 11), (.chest, "chestplate", 16), (.legs, "leggings", 15)]
        for (c, armor, tough, mult, colour) in stats {
            for seg in 0..<3 where !has(c.item(seg)) {
                var d = ItemDef(c.item(seg), "\(c.name) \(TroopClass.segLabels[seg])")
                d.sprite = Sprite(mask: slots[seg].1, base: colour, extras: [:])
                d.maxStack = 1
                d.armorSlot = slots[seg].0
                d.armor = armor[seg]
                d.toughness = tough
                d.durability = slots[seg].2 * mult
                add(d)
            }
        }
    }
}
