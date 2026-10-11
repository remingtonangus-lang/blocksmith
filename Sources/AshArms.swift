import Foundation
import simd

// The Ashguard's arms (backlog B7, docs/status/the-last-war.md): four period-style guns in walnut and blued steel,
// under invented names. Gun pixels like CapitalArms (barrel toward -Z, y up); no part uses the enamel pattern, so a
// soldier's livery never repaints them.
//   Kessel Bolt Rifle      long walnut stock, turned-down bolt, barrel bands, hooded front sight; five rounds
//   Hagel Machine Pistol   steel tube receiver, long straight stick magazine, folding stock, bakelite grip
//   Sturmwind Carbine      stamped receiver, curved magazine, walnut butt, pistol grip
//   Ashsaw Machine Gun     square perforated barrel jacket, muzzle booster, bipod, belt drum, bakelite stock
enum AshArms {
    static let walnut = V3(0.36, 0.2, 0.1), blued = V3(0.11, 0.115, 0.13), steel = V3(0.2, 0.21, 0.23)
    static let bakelite = V3(0.16, 0.09, 0.06), brass = V3(0.72, 0.55, 0.24), bore = V3(0.02, 0.02, 0.02)
    static let pWood: Float = 10, pMetal: Float = 8

    static func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
    }

    static func model(_ i: Int) -> GunModel {
        switch i {
        case Guns.kessel:
            let p: [Part] = [
                b(-0.9, -1.2, -20, 1.8, 2.2, 20, walnut, pWood),                  // fore-end
                b(-0.75, 0.6, -6, 1.5, 1.6, 7, blued, pMetal),                     // receiver
                b(-0.4, 1.0, -27, 0.8, 0.8, 21, blued, pMetal),                    // barrel
                b(-0.7, 0.9, -16, 1.4, 1.1, 9, walnut, pWood),                     // upper handguard
                b(-0.95, -1.3, -20.5, 1.9, 3.3, 0.6, steel, pMetal),               // barrel bands
                b(-0.95, -1.3, -13.2, 1.9, 3.3, 0.6, steel, pMetal),
                b(-0.35, 1.7, -26.6, 0.7, 0.9, 0.9, blued, pMetal),                // hooded front sight
                b(-0.25, 1.0, -27.1, 0.5, 0.5, 0.12, bore, 0),
                b(-0.45, 1.6, -5.4, 0.9, 0.5, 1.4, steel, pMetal),                 // rear sight
                b(0.75, 1.0, -1.4, 1.2, 0.4, 0.4, steel, pMetal),                  // bolt handle, turned down
                b(1.7, 0.3, -1.6, 0.8, 0.8, 0.8, steel, pMetal),                   // bolt knob
                b(-0.75, -1.7, 0, 1.5, 2.7, 5, walnut, pWood),                     // wrist
                b(-0.9, -3.4, 5, 1.8, 4.6, 7, walnut, pWood),                      // butt
                b(-0.95, -3.5, 12, 1.9, 4.8, 0.4, steel, pMetal),                  // butt plate
                b(-0.6, -1.6, -5, 1.2, 0.4, 3, steel, pMetal),                     // floor plate
                b(-0.25, -2.0, -2.8, 0.5, 0.3, 2.4, steel, pMetal),                // trigger guard
            ]
            return GunModel(parts: p, mag: [], grip: V3(0, -1.0, 2.2), fore: V3(0, -0.6, -12), butt: V3(0, -0.6, 12.4),
                            muzzle: V3(0, 1.4, -27.2), magAt: V3(0, 1.8, -3), bolt: V3(2.1, 0.7, -1.2), scale: 0.56)
        case Guns.hagel:
            var p: [Part] = [
                b(-0.8, -0.2, -7, 1.6, 1.8, 10, blued, pMetal),                    // receiver tube
                b(-0.9, -1.6, -3, 1.8, 1.4, 5, blued, pMetal),                     // lower housing
                b(-0.4, 0.3, -12, 0.8, 0.8, 5, blued, pMetal),                     // barrel
                b(-0.5, -0.6, -11.8, 1.0, 0.8, 1.4, steel, pMetal),                // barrel rest
                b(-0.2, 1.0, -11.5, 0.4, 0.7, 0.4, steel, pMetal),                 // front sight
                b(-0.3, 1.6, -1, 0.6, 0.5, 0.6, steel, pMetal),                    // rear sight
                b(-0.2, 0.5, -12.1, 0.4, 0.4, 0.12, bore, 0),
                b(-0.7, -4.6, 0.2, 1.4, 3.2, 1.8, bakelite, pWood),                // grip
                b(-0.25, -2.0, -2.0, 0.5, 0.3, 2.0, blued, pMetal),                // trigger guard
                b(-0.7, -0.6, 3, 0.3, 0.5, 7.5, steel, pMetal),                    // stock struts
                b(0.4, -0.6, 3, 0.3, 0.5, 7.5, steel, pMetal),
                b(-0.8, -2.0, 10, 1.6, 2.4, 0.5, steel, pMetal),                   // butt plate
                b(-1.6, 0.6, -3, 0.8, 0.4, 0.4, steel, pMetal),                    // bolt handle (left)
                b(-0.7, -2.4, -5.4, 1.4, 1.0, 2, blued, pMetal),                   // magazine well
            ]
            let m = p.count
            p += [b(-0.55, -7.6, -5.2, 1.1, 5.4, 1.6, blued, pMetal)]              // stick magazine
            return GunModel(parts: p, mag: [m], grip: V3(0, -2.6, 1.0), fore: V3(0, -3.2, -4.4), butt: V3(0, -0.8, 10.4),
                            muzzle: V3(0, 0.7, -12.2), magAt: V3(0, -3.6, -4.4), bolt: V3(-1.8, 0.8, -2.8), scale: 0.64)
        case Guns.sturmwind:
            var p: [Part] = [
                b(-0.9, -0.3, -7, 1.8, 2.4, 10, blued, pMetal),                    // stamped receiver
                b(-0.8, 0.3, -13, 1.6, 1.6, 6, blued, pMetal),                     // gas tube / handguard
                b(-0.4, 0.6, -17, 0.8, 0.8, 4, blued, pMetal),                     // barrel
                b(-0.25, 1.4, -16.6, 0.5, 0.8, 0.5, steel, pMetal),                // front sight
                b(-0.5, 0.5, -17.4, 1.0, 1.0, 0.6, steel, pMetal),                 // muzzle nut
                b(-0.2, 0.8, -17.5, 0.4, 0.4, 0.12, bore, 0),
                b(-0.3, 2.1, -4, 0.6, 0.6, 1.2, steel, pMetal),                    // rear sight
                b(-0.65, -3.6, 0.8, 1.3, 3.4, 1.6, walnut, pWood),                 // pistol grip
                b(-0.25, -1.6, -2.4, 0.5, 0.3, 2.2, blued, pMetal),                // trigger guard
                b(-0.8, -1.8, 3, 1.6, 3.0, 8, walnut, pWood),                      // butt
                b(-0.85, -2.8, 7, 1.7, 1.4, 4, walnut, pWood),
                b(-0.9, -2.9, 11, 1.8, 4.2, 0.4, steel, pMetal),                   // butt plate
                b(-1.5, 1.0, -5, 0.6, 0.4, 0.6, steel, pMetal),                    // charging handle (left)
            ]
            let m = p.count
            p += [b(-0.6, -4.0, -6.2, 1.2, 3.8, 1.8, blued, pMetal), b(-0.6, -6.6, -6.9, 1.2, 2.8, 1.8, blued, pMetal)]   // curved magazine
            return GunModel(parts: p, mag: [m, m + 1], grip: V3(0, -2.0, 1.5), fore: V3(0, -0.4, -10.5), butt: V3(0, -0.4, 11.4),
                            muzzle: V3(0, 1.0, -17.5), magAt: V3(0, -2.8, -5.2), bolt: V3(-1.6, 1.2, -4.8), scale: 0.6)
        default:
            var p: [Part] = [
                b(-1.0, -0.4, -8, 2.0, 2.8, 11, blued, pMetal),                    // receiver
                b(-1.1, 2.4, -6, 2.2, 0.6, 6, steel, pMetal),                      // feed cover
                b(-0.9, 0.0, -22, 1.8, 2.0, 14, blued, pMetal),                    // barrel jacket
                b(-0.7, 0.2, -24.5, 1.4, 1.6, 2.5, steel, pMetal),                 // muzzle booster
                b(-0.25, 0.75, -24.6, 0.5, 0.5, 0.12, bore, 0),
                b(-0.2, 2.0, -21.6, 0.4, 1.2, 0.4, steel, pMetal),                 // front sight post
                b(-0.3, 2.9, -3, 0.6, 0.8, 0.8, steel, pMetal),                    // rear sight
                b(-1.0, -2.8, -21, 0.3, 2.8, 0.3, steel, pMetal),                  // bipod legs
                b(0.7, -2.8, -21, 0.3, 2.8, 0.3, steel, pMetal),
                b(-0.6, -3.6, 0.4, 1.2, 3.4, 1.6, bakelite, pWood),                // pistol grip
                b(-0.25, -1.8, -2.2, 0.5, 0.3, 2.0, blued, pMetal),                // trigger guard
                b(-0.8, -1.6, 3, 1.6, 2.8, 8, bakelite, pWood),                    // stock
                b(-0.85, -2.4, 11, 1.7, 3.6, 0.5, steel, pMetal),                  // butt plate
                b(1.0, 0.6, -5, 0.8, 0.5, 0.5, steel, pMetal),                     // charging handle (right)
                b(-1.4, 0.6, -5.8, 0.5, 0.5, 2.6, brass, pMetal),                  // belt into the feed
            ]
            let m = p.count
            p += [b(-3.4, -2.6, -6.8, 2.4, 3.2, 3.2, blued, pMetal)]               // belt drum
            return GunModel(parts: p, mag: [m], grip: V3(0, -2.0, 1.2), fore: V3(0, -0.6, -12), butt: V3(0, -0.6, 11.5),
                            muzzle: V3(0, 1.0, -24.6), magAt: V3(-2.2, -1.0, -5.2), bolt: V3(1.6, 0.8, -5), scale: 0.55)
        }
    }

    // Small fittings: the Ashsaw's jacket cooling slots, the rifle's sling swivels, the carbine's ribs.
    static func details(_ i: Int) -> [Part] {
        var p: [Part] = []
        switch i {
        case Guns.ashsaw:
            for z: Float in [-20.6, -18.0, -15.4, -12.8, -10.2] {
                p.append(b(-0.96, 0.5, z, 0.08, 1.0, 1.4, bore, 0))
                p.append(b(0.88, 0.5, z, 0.08, 1.0, 1.4, bore, 0))
                p.append(b(-0.5, 1.96, z, 1.0, 0.08, 1.4, bore, 0))
            }
        case Guns.kessel:
            p.append(b(-0.2, -1.6, -19.8, 0.4, 0.4, 0.6, steel, pMetal))
            p.append(b(-0.2, -3.7, 9.0, 0.4, 0.4, 0.8, steel, pMetal))
        case Guns.sturmwind:
            for k in 0..<3 { p.append(b(-0.85, 0.6 + Float(k) * 0.4, -12.5, 0.06, 0.2, 5, steel * 0.8, pMetal)) }
        default:
            for k in 0..<4 { p.append(b(-0.82, 0.0, -6 + Float(k) * 2, 0.06, 1.4, 0.4, steel * 0.8, pMetal)) }   // receiver ribs
        }
        return p
    }

    static let icons: [String: [String]] = [
        "gun_kessel": ["................", "................", "................", "................", "................",
                       "............1...", "11111111111m1...", "1mmmmmmmmmmmm11.", ".1aaaaaaaaa1aaa1", "..111111111.1aa1",
                       "............1aa1", ".............111", "................", "................", "................", "................"],
        "gun_hagel": ["................", "................", "................", "................", "................",
                      "......1.....1...", "111111111111111.", "1mmmmmmmmmmmmm1.", ".111ddd1dddd11..", "....1d1..1dd1...",
                      "....1d1...1d1...", "....1d1...111...", "....1d1.........", "....111.........", "................", "................"],
        "gun_sturmwind": ["................", "................", "................", "................", "................",
                          "................", "........11......", "11111111mm111111", "1mmmmmmmmmmm1aa1", ".1111dd1d1111aa1",
                          "....1dd11a1..111", "....1dd1.1a1....", ".....1dd1.11....", "......111.......", "................", "................"],
        "gun_ashsaw": ["................", "................", "................", "................", "................",
                       "..............1.", "111111111111111.", "1d1d1d1dmmmmm1a1", "1mmmmmmmmmmmm1a1", ".11.1111yd11.1a1",
                       ".1...1yyyd1a1...", ".1....111.1a1...", "..........111...", "................", "................", "................"],
    ]
}
