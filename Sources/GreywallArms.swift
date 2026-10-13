import Foundation
import simd

// Greywall's own arms (P104, Oct 12 12:17: "Greywall troops drop and carry Capital rounds and Capital weapons"), and
// the handling spread across the pistols and rifles (P105, 12:18: "at least three pistol types... the better guns
// are harder to handle because of their recoil"). Slate-grey polymer and dark steel with a hazard-yellow mark, under
// invented names, on Slate Rounds (never sold or crafted: taken from Greywall troops and bases).
//   Slatefall Carbine   squared receiver, top sensor rail, short shrouded barrel, skeleton stock (the line rifle)
//   Longwatch Rifle     long fluted barrel, a big optic, a bipod folded under (the marksman's)
//   Wren Pistol         slim slab-sided pistol, long magazine, light and soft (the crews')
//   Breaker Revolver    a heavy top-break hand cannon on heavy rounds: hits like a rifle, kicks like a mule (officers)
//   Slate Repeater      box-fed light machine gun with a carry handle and a heat shield (heavy troopers)
// Handling ladder, pistols: Needle (3, kick 0.014) < Capital Sidearm (4, 0.03) < Six-Iron (7, 0.065) < Breaker (12,
// 0.14); rifles: Service Rifle / Sturmwind (~5, 0.013) < Slatefall (5.5, 0.02) < Kessel (16, 0.08) < Longwatch (20,
// 0.085) < Farsight (24, 0.09). A soldier's aim is wider by its gun's kick on every shot (Mob.aimKick: recoil x 0.6),
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
        case .soldierOfficer: return Guns.breaker
        // P216 (Oct 13 19:01, "nothing fires arc cells or heavy rounds, shotguns are rare, everything takes slate"):
        // the crews' sidearm is the Breaker (heavy rounds), the marksmen's Longwatch takes heavy rounds, a third of
        // the heavies carry the arc gun, and troopers carry shotguns too.
        case .soldierCrew: return Guns.breaker
        case .soldierMarksman: return c == .regular && r < 0.4 ? Guns.slatefall : Guns.longwatch
        case .soldierIronclad: return r < 0.35 ? Guns.arc : Guns.repeater
        case .soldierTrooper: return c == .regular && r < 0.2 ? Guns.repeater : (r > 0.7 ? Guns.shotgun : Guns.slatefall)
        default: return r < 0.7 ? Guns.slatefall : Guns.shotgun
        }
    }

    static func model(_ i: Int) -> GunModel {
        switch i {
        case Guns.slatefall:
            var p: [Part] = [
                b(-1.0, -0.3, -7, 2.0, 2.8, 11, slate, pPoly),                   // squared receiver
                b(-0.7, 2.5, -7, 1.4, 0.45, 10, dark, pMetal),                    // top rail
                b(-0.6, 2.95, -3.6, 1.2, 1.1, 2.6, dark, pMetal),                 // sensor sight
                b(-0.4, 3.2, -3.7, 0.8, 0.7, 0.12, lens, pGlass),
                b(-0.95, 0.2, -13.5, 1.9, 2.0, 6.5, slate * 0.9, pPoly),          // shroud
                b(-0.4, 0.8, -17.2, 0.8, 0.8, 3.8, steel, pMetal),                // barrel
                b(-0.2, 1.0, -17.3, 0.4, 0.4, 0.12, bore, 0),
                b(-1.02, 0.9, -6, 0.1, 0.5, 2.2, hazard, pPoly),                   // hazard mark
                b(-0.6, -3.4, 0.6, 1.2, 3.2, 1.6, dark, pPoly),                   // grip
                b(-0.25, -1.5, -2.4, 0.5, 0.3, 2.2, dark, pMetal),                // trigger guard
                b(-0.6, -0.2, 4, 0.4, 0.6, 7, dark, pMetal),                      // skeleton stock struts
                b(0.2, -0.2, 4, 0.4, 0.6, 7, dark, pMetal),
                b(-0.9, -1.6, 10.6, 1.8, 3.4, 0.7, dark, pPoly),                  // butt pad
            ]
            let m = p.count
            p += [b(-0.6, -4.4, -5.4, 1.2, 4.2, 2.0, dark, pPoly)]                  // magazine
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.8, 1.4), fore: V3(0, -0.2, -10.5), butt: V3(0, -0.2, 11.2),
                            muzzle: V3(0, 1.2, -17.3), magAt: V3(0, -2.6, -4.4), bolt: V3(-1.4, 1.2, -4.5), scale: 0.6)
        case Guns.longwatch:
            var p: [Part] = [
                b(-0.9, -0.6, -6, 1.8, 2.4, 10, slate, pPoly),                    // receiver
                b(-0.45, 0.6, -26, 0.9, 0.9, 20, steel, pMetal),                  // long barrel
                b(-0.5, 1.45, -24, 1.0, 0.12, 16, dark, pMetal),                  // flutes
                b(-0.25, 0.85, -26.1, 0.5, 0.5, 0.12, bore, 0),
                b(-0.7, 0.4, -26.8, 1.4, 1.3, 1.6, dark, pMetal),                  // muzzle brake
                b(-0.9, 2.0, -7, 1.8, 0.4, 8, dark, pMetal),                      // rail
                b(-0.8, 2.4, -6.2, 1.6, 1.8, 6.4, dark, pMetal),                  // optic
                b(-0.55, 2.65, -6.3, 1.1, 1.3, 0.12, lens, pGlass),
                b(-0.85, -0.9, -14, 1.7, 1.6, 8, slate * 0.9, pPoly),             // fore-end
                b(-0.2, -1.6, -13.5, 0.4, 0.7, 5, dark, pMetal),                  // folded bipod
                b(-0.6, -3.6, 0.6, 1.2, 3.2, 1.6, dark, pPoly),                   // grip
                b(-0.25, -1.7, -2.4, 0.5, 0.3, 2.2, dark, pMetal),
                b(-0.85, -1.8, 4, 1.7, 3.6, 7.8, slate, pPoly),                   // stock
                b(-0.9, -2.0, 11.8, 1.8, 4.2, 0.6, dark, pPoly),
                b(-0.92, 1.0, -4, 0.1, 0.5, 2.0, hazard, pPoly),
            ]
            let m = p.count
            p += [b(-0.55, -2.6, -4.6, 1.1, 2.2, 2.6, dark, pPoly)]
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.9, 1.4), fore: V3(0, -0.9, -11), butt: V3(0, -0.2, 12.1),
                            muzzle: V3(0, 1.05, -26.8), magAt: V3(0, -1.8, -3.4), bolt: V3(1.5, 0.9, -1.5), scale: 0.56)
        case Guns.breaker:
            // A top-break hand cannon: a deep frame, a six-round cylinder, a long ribbed barrel, a rubber grip.
            let p: [Part] = [
                b(-0.55, 0.25, -9.5, 1.1, 1.1, 7, steel, pMetal),                 // barrel
                b(-0.3, 1.35, -9.4, 0.6, 0.35, 6.8, dark, pMetal),                // rib
                b(-0.25, 0.55, -9.62, 0.5, 0.5, 0.12, bore, 0),
                b(-0.95, -0.6, -2.6, 1.9, 1.9, 2.4, dark, pMetal),                // cylinder
                b(-0.7, -0.8, -0.2, 1.4, 2.1, 1.8, steel, pMetal),               // frame
                b(-0.25, 1.1, 1.1, 0.5, 0.6, 0.8, dark, pMetal),                  // hammer
                b(-0.3, -1.5, -1.8, 0.6, 0.3, 1.7, dark, pMetal),                 // trigger guard
                b(-0.6, -2.5, 0.4, 1.2, 1.8, 1.5, dark, pPoly),                   // grip
                b(-0.6, -3.8, 0.9, 1.2, 1.4, 1.5, dark, pPoly),
                b(-0.98, 0.3, -2.0, 0.1, 0.6, 1.2, hazard, pPoly),
            ]
            return GunModel(parts: p, mag: [], grip: V3(0, -1.6, 0.9), fore: V3(-0.4, -2.6, 1.2), butt: V3(0, -1.6, 0.9),
                            muzzle: V3(0, 0.8, -9.7), magAt: V3(0, -0.4, -1.4), bolt: V3(0, 1.3, 1.2), scale: 0.68, shouldered: false)
        case Guns.repeater:
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
        default:
            // Wren Pistol: a slim slab slide, a long magazine below the grip.
            var p: [Part] = [
                b(-0.55, 0.0, -6.8, 1.1, 1.2, 8.2, slate, pPoly),                 // slide
                b(-0.5, -0.6, -6.2, 1.0, 0.6, 7.2, dark, pPoly),                  // frame
                b(-0.2, 0.35, -6.92, 0.4, 0.4, 0.12, bore, 0),
                b(-0.12, 1.2, -6.3, 0.24, 0.25, 0.3, steel, pMetal), b(-0.3, 1.2, 0.8, 0.6, 0.25, 0.4, steel, pMetal),
                b(-0.25, -1.3, -2.2, 0.5, 0.3, 1.8, dark, pMetal),
                b(-0.57, 0.5, -5.5, 0.06, 0.4, 1.4, hazard, pPoly),
            ]
            p += [b(-0.55, -2.4, -0.1, 1.1, 1.8, 1.5, dark, pPoly)]
            let m = p.count
            p += [b(-0.45, -4.4, 0.3, 0.9, 2.1, 1.3, dark, pPoly)]
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.5, 0.6), fore: V3(-0.4, -2.4, 0.9), butt: V3(0, -1.5, 0.6),
                            muzzle: V3(0, 0.55, -7.0), magAt: V3(0, -3.6, 0.9), bolt: V3(0, 0.6, -1), scale: 0.68, shouldered: false)
        }
    }

    static func details(_ i: Int) -> [Part] {
        switch i {
        case Guns.slatefall: return (0..<3).map { k in b(-0.98, 0.0 + Float(k) * 0.5, -12, 0.06, 0.25, 4, dark, pMetal) }   // shroud slots
        case Guns.repeater: return (0..<3).map { k in b(-0.78, 0.6, -17 + Float(k) * 2.4, 0.06, 1.0, 1.2, bore, 0) }      // shield vents
        case Guns.longwatch: return [b(-0.3, 4.2, -3.4, 0.6, 0.5, 0.8, steel, pMetal)]                                      // turret
        default: return []
        }
    }

    static let icons: [String: [String]] = [
        "gun_slatefall": ["................", "................", "................", "................", "......111.......",
                          "......1g1.......", "11111111111111..", "1aaaaaaaammmmm11", "1a1aaaaaa1111...", "11.1d1dd1.......",
                          "....1d11d1......", "....1d1.d1......", ".....1..11......", "................", "................", "................"],
        "gun_longwatch": ["................", "................", "................", "......11111.....", ".....1dddg1.....",
                          "......11111.....", "111..11aa1......", "1aa11aaaaa111111", "1aaaaaaaammmmmd1", ".1a1d1d1111111..",
                          "..1.1d11.1......", "....1d1..1......", ".....1...1......", "................", "................", "................"],
        "gun_needle": ["................", "................", "................", "................", "................",
                       ".111111111111...", ".1aaaaaaaaaay1..", ".1111111111111..", "......1d1d1.....", ".....1dd111.....",
                       ".....1dd1.......", ".....1dd1.......", ".....1dd1.......", ".....1111.......", "................", "................"],
        "gun_breaker": ["................", "................", "................", "................", ".1............1.",
                        "..111111111111..", ".1mm1mmmmmmmmm1.", ".1mmmm11111111..", "..1mmmm1.1......", "..1dd111y1......",
                        ".1ddd1.11.......", ".1ddd1..........", "1ddd1...........", "1111............", "................", "................"],
        "gun_repeater": ["................", "................", "................", "................", ".....111111.....",
                         ".....1....1.....", "1111111111111111", "1aaaaaaammmmmmm1", "1a1aaaaaa11111..", "11.1ddd1d1......",
                         "...1ddd11d1.....", "...11111.d1.....", ".........11.....", "................", "................", "................"],
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
        guard factionValue == .greywall, Soldier.rank(kind) != nil, !Guns.isGreyArm(variant) else { return }
        let c = TroopClass(rawValue: Int(troop)) ?? .regular
        variant = GreywallArms.pickGun(c, kind, roll: hashf(Int(pos.x * 7), Int(pos.y * 3), Int(pos.z * 5), 8101))
        if let b = brain { b.gun = variant; b.mag = Guns.all[variant].mag }
    }
}
