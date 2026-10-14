import Foundation
import simd

// Greywall's own arms (P104, Oct 12 12:17: "Greywall troops drop and carry Capital rounds and Capital weapons"), and
// the handling spread across the pistols and rifles (P105, 12:18: "at least three pistol types... the better guns
// are harder to handle because of their recoil"). Slate-grey polymer and dark steel with a hazard-yellow mark, under
// invented names, on Slate Rounds (never sold or crafted: taken from Greywall troops and bases).
//   Slatefall Carbine   a bullpup: magazine behind the grip, carry rail and sensor sight (the line rifle)
//   Slate Repeater      box-fed light machine gun with a carry handle and a heat shield (heavy troopers)
// (P217, Oct 14: the Longwatch, Wren and Breaker are gone; marksmen carry the Kessel, officers and crews the six-iron.)
// Handling ladder, pistols: Falke (4, kick 0.03) < Six-Iron (7, 0.065); rifles: Service Rifle / Sturmwind (~5, 0.013)
// < Slatefall (5.5, 0.02) < Kessel (16, 0.08) < Farsight (24, 0.09). A soldier's aim is wider by its gun's kick on every shot (Mob.aimKick: recoil x 0.6),
// except a Hannibal trooper's: the power suit takes it.
enum GreywallArms {
    static let slate = V3(0.3, 0.34, 0.38), dark = V3(0.12, 0.13, 0.15), steel = V3(0.22, 0.23, 0.25)
    static let hazard = V3(0.85, 0.66, 0.12), lens = V3(0.2, 0.55, 0.75), bore = V3(0.02, 0.02, 0.02)
    static let pPoly: Float = 7, pMetal: Float = 8, pGlass: Float = 11
    static let ammo = "greywall_rounds"

    static func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
    }

    static let specs: [GunSpec] = [
        GunSpec(key: "gun_slatefall", name: "Slatefall Carbine", ammo: ammo, mag: 30, interval: 0.1, auto: true, damage: 5.5, pellets: 1,
                spread: 0.028, aimSpread: 0.006, speed: 170, recoil: 0.02, reload: 2.1, range: 120, durability: 1200, zoom: 0.78,
                shot: .bullet, sound: 18, accent: V3(0.33, 0.37, 0.41)),
        GunSpec(key: "gun_longwatch", name: "Longwatch Rifle", ammo: "heavy_rounds", mag: 6, interval: 1.1, auto: false, damage: 20, pellets: 1,
                spread: 0.05, aimSpread: 0.0008, speed: 300, recoil: 0.085, reload: 2.6, range: 240, durability: 500, zoom: 0.3,
                shot: .bullet, sound: 3, accent: V3(0.33, 0.37, 0.41)),
        GunSpec(key: "gun_needle", name: "Wren Pistol", ammo: ammo, mag: 20, interval: 0.16, auto: false, damage: 3, pellets: 1,
                spread: 0.03, aimSpread: 0.01, speed: 150, recoil: 0.014, reload: 1.2, range: 50, durability: 1000, zoom: 0.9,
                shot: .bullet, sound: 13, accent: V3(0.33, 0.37, 0.41)),
        GunSpec(key: "gun_breaker", name: "Breaker Revolver", ammo: "heavy_rounds", mag: 6, interval: 0.55, auto: false, damage: 12, pellets: 1,
                spread: 0.04, aimSpread: 0.005, speed: 200, recoil: 0.14, reload: 2.6, range: 90, durability: 600, zoom: 0.85,
                shot: .bullet, sound: 13, accent: V3(0.85, 0.66, 0.12)),
        GunSpec(key: "gun_repeater", name: "Slate Repeater", ammo: ammo, mag: 90, interval: 0.06, auto: true, damage: 4, pellets: 1,
                spread: 0.07, aimSpread: 0.02, speed: 160, recoil: 0.012, reload: 4.0, range: 110, durability: 1600, zoom: 0.85,
                shot: .bullet, sound: 19, accent: V3(0.33, 0.37, 0.41)),
    ]

    // Greywall's loadouts by rank and troop class.
    static func pickGun(_ c: TroopClass, _ k: MobKind, roll r: Float) -> Int {
        switch k {
        case .soldierOfficer: return Guns.revolver
        // P216 (Oct 13 19:01, "nothing fires arc cells or heavy rounds, shotguns are rare, everything takes slate"):
        // a third of the heavies carry the arc gun, and troopers carry shotguns too. P217 (Oct 14): the Breaker and
        // Longwatch are gone; officers and crews carry the six-iron, marksmen the Kessel (heavy rounds).
        case .soldierCrew: return Guns.revolver
        case .soldierMarksman: return c == .regular && r < 0.4 ? Guns.slatefall : Guns.kessel
        case .soldierIronclad: return r < 0.35 ? Guns.arc : Guns.repeater
        case .soldierTrooper: return c == .regular && r < 0.2 ? Guns.repeater : (r > 0.7 ? Guns.shotgun : Guns.slatefall)
        default: return r < 0.7 ? Guns.slatefall : Guns.shotgun
        }
    }

    static func model(_ i: Int) -> GunModel {
        switch i {
        case Guns.slatefall:
            // P217 redo (Oct 14, "fewer, clearly different guns"): a bullpup, so it no longer reads as a third copy of
            // the Service Rifle: the action and magazine sit in the stock behind the pistol grip, a short overall
            // length, a long handguard, a carry rail with the sensor sight, a squared cheek piece and a butt pad
            // straight behind the magazine (like the real bullpup carbines).
            var p: [Part] = [
                b(-1.05, -1.6, -6.5, 2.1, 3.6, 15.5, slate, pPoly),               // body: receiver and stock in one
                b(-1.1, 1.2, -1.5, 2.2, 0.8, 9.5, slate * 0.85, pPoly),            // cheek piece
                b(-0.95, -0.4, -14.5, 1.9, 2.3, 8.0, slate * 0.9, pPoly),          // handguard
                b(-0.4, 0.4, -18.4, 0.8, 0.8, 3.9, steel, pMetal),                 // barrel
                b(-0.55, 0.25, -19.2, 1.1, 1.1, 0.9, dark, pMetal),                // flash hider
                b(-0.2, 0.6, -19.28, 0.4, 0.4, 0.1, bore, 0),
                b(-0.6, 2.0, -9.5, 1.2, 0.45, 12.5, dark, pMetal),                 // carry rail
                b(-0.6, 2.45, -6.2, 1.2, 1.2, 3.0, dark, pMetal),                  // sensor sight
                b(-0.4, 2.7, -6.32, 0.8, 0.75, 0.12, lens, pGlass),
                b(-0.15, 1.9, -14.2, 0.3, 0.9, 0.4, dark, pMetal),                 // front sight post
                b(-1.12, 0.3, 2.0, 0.1, 0.55, 2.4, hazard, pPoly),                 // hazard mark
                b(-0.6, -5.0, -6.0, 1.2, 3.5, 1.6, dark, pPoly),                   // pistol grip, forward
                b(-0.25, -2.0, -8.6, 0.5, 0.3, 3.0, dark, pMetal),                 // long trigger guard
                b(-0.1, -1.95, -7.6, 0.2, 0.75, 0.3, steel, pMetal),               // trigger
                b(-1.2, 0.6, 1.2, 0.14, 0.5, 1.2, dark, pMetal),                   // charging handle (left)
                b(1.06, 0.2, 0.8, 0.08, 0.9, 2.8, dark, pMetal),                   // ejection port (right)
                b(-1.1, -1.9, 8.9, 2.2, 4.2, 0.8, dark, pPoly),                    // butt pad
                b(-0.8, -2.1, -14.0, 1.6, 0.4, 5.0, dark, pPoly),                  // handguard grip ribs
            ]
            let m = p.count
            p += [b(-0.6, -5.2, 2.0, 1.2, 3.8, 2.2, dark, pPoly), b(-0.62, -5.5, 1.9, 1.24, 0.4, 2.4, steel, pMetal)]   // magazine behind the grip
            return GunModel(parts: p, mag: [m, m + 1], grip: V3(0, -3.2, -5.2), fore: V3(0, -1.2, -11.5), butt: V3(0, 0.2, 9.7),
                            muzzle: V3(0, 0.8, -19.3), magAt: V3(0, -3.4, 3.1), bolt: V3(-1.4, 0.85, 1.8), scale: 0.6)
        default:
            var p: [Part] = [
                b(-1.2, -0.6, -8, 2.4, 3.2, 13, slate, pPoly),                    // receiver
                b(-0.5, 0.6, -22, 1.0, 1.0, 14, steel, pMetal),                   // barrel
                b(-0.75, 0.35, -18, 1.5, 1.5, 8, dark, pMetal),                   // heat shield
                b(-0.25, 0.85, -22.1, 0.5, 0.5, 0.12, bore, 0),
                b(-0.3, 2.6, -4, 0.6, 1.6, 0.6, dark, pMetal),                    // carry handle
                b(-0.3, 4.0, -4, 0.6, 0.5, 6, dark, pMetal),
                b(-0.3, 2.6, 1.4, 0.6, 1.6, 0.6, dark, pMetal),
                b(-1.22, 1.0, -7, 0.1, 0.6, 3, hazard, pPoly),
                b(-0.65, -3.6, 0.8, 1.3, 3.4, 1.6, dark, pPoly),                  // grip
                b(-0.25, -1.6, -2.4, 0.5, 0.3, 2.2, dark, pMetal),
                b(-0.9, -1.8, 5, 1.8, 3.6, 6.4, slate * 0.9, pPoly),              // stock
                b(-0.95, -2.0, 11.2, 1.9, 4.0, 0.6, dark, pPoly),
                b(-0.2, -1.6, -20, 0.4, 0.8, 5, dark, pMetal),                    // bipod
            ]
            let m = p.count
            p += [b(-2.9, -2.8, -6.8, 1.9, 3.0, 3.6, dark, pPoly)]                  // box magazine on the left
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.9, 1.6), fore: V3(0, -0.6, -12), butt: V3(0, -0.2, 11.5),
                            muzzle: V3(0, 1.1, -22.1), magAt: V3(-2.0, -1.2, -5), bolt: V3(1.5, 0.8, -5), scale: 0.55)
        }
    }

    static func details(_ i: Int) -> [Part] {
        switch i {
        case Guns.slatefall: return (0..<3).map { k in b(-0.98, 0.2 + Float(k) * 0.5, -13.5, 0.06, 0.25, 4.5, dark, pMetal) } // handguard slots
        case Guns.repeater: return (0..<3).map { k in b(-0.78, 0.6, -17 + Float(k) * 2.4, 0.06, 1.0, 1.2, bore, 0) }      // shield vents
        default: return []
        }
    }

    static let icons: [String: [String]] = [
        "greywall_rounds": ["................", "................", "................", "....g.....g.....", "...ggg...ggg....",
                            "...ggg...ggg..g.", "...mmm...mmm.ggg", "...mmm...mmm.ggg", "...mmm...mmm.mmm", "...mmm...mmm.mmm",
                            "...mmm...mmm.mmm", "...ddd...ddd.mmm", ".............mmm", ".............ddd", "................", "................"],
    ]
}

extension Mob {
    // P105: how far a soldier's aim opens with a gun's kick (radians added to its spread); a Hannibal trooper's suit
    // takes all of it.
    func aimKick(_ gs: GunSpec) -> Float { troop == Int8(TroopClass.hannibal.rawValue) ? 0 : gs.recoil * 0.6 }

    // A Greywall soldier saved with a Capital gun (before P104) takes its own on load, like the Ashguard's.
    func greyRearm() {
        guard factionValue == .greywall, Soldier.rank(kind) != nil, !Guns.isGreyArm(variant) || Guns.isRetired(variant) else { return }
        let c = TroopClass(rawValue: Int(troop)) ?? .regular
        variant = GreywallArms.pickGun(c, kind, roll: hashf(Int(pos.x * 7), Int(pos.y * 3), Int(pos.z * 5), 8101))
        if let b = brain { b.gun = variant; b.mag = Guns.all[variant].mag }
    }
}
