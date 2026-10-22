import Foundation
import simd

// The Ashguard's arms (backlog B7, docs/status/the-last-war.md): period guns in walnut, bakelite and blued steel, under
// their own names since P326 (Oct 15 19:04, "their real WWII weapons by name"). Gun pixels like CapitalArms (barrel
// toward -Z, y up); no part uses the enamel pattern, so a soldier's livery never repaints them.
//   Kessel Bolt Rifle (gun_kessel) long walnut stock, turned-down bolt, barrel bands, hooded front sight; five rounds
//   Hagel Machine Pistol (gun_hagel) round receiver tube, long straight magazine, bakelite grip and housing, folding wire
//                 stock, the barrel rest under the muzzle (P326: back, with its own look)
//   Sturmwind Carbine (gun_sturmwind) stamped receiver, curved magazine, walnut butt, pistol grip
//   Faustrohr     (gun_faust) the single-shot anti-tank tube
// (P217, Oct 14: the machine gun is gone; its key loads as the Sturmwind.)
enum AshArms {
    static let walnut = V3(0.36, 0.2, 0.1), blued = V3(0.11, 0.115, 0.13), steel = V3(0.2, 0.21, 0.23)
    static let bakelite = V3(0.16, 0.09, 0.06), brass = V3(0.72, 0.55, 0.24), bore = V3(0.02, 0.02, 0.02)
    static let pWood: Float = 10, pMetal: Float = 8

    static func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
    }

    static let olive = V3(0.27, 0.29, 0.18), drab = V3(0.33, 0.31, 0.17), warn = V3(0.62, 0.14, 0.1)

    static func model(_ i: Int) -> GunModel {
        switch i {
        case Guns.faust:
            // P320: the Faustrohr: a thin olive tube with the fat drab warhead on its muzzle (the magazine: it leaves
            // with a reload), the leaf sight folded up, the trigger lever on top, a red warning band and the open
            // back end.
            var p: [Part] = [
                b(-0.8, -0.8, -12, 1.6, 1.6, 30, olive, pMetal),                   // tube
                b(-0.95, -0.95, -1.2, 1.9, 1.9, 0.6, warn, pMetal),               // warning band
                b(-0.9, -0.9, 17.4, 1.8, 1.8, 0.6, steel, pMetal),                 // rear rim
                b(-0.5, -0.5, 17.9, 1.0, 1.0, 0.15, bore, 0),                      // open back end
                b(-0.6, 0.8, -6.4, 1.2, 2.8, 0.35, olive, pMetal),                 // folding leaf sight
                b(-0.25, 3.2, -6.45, 0.5, 0.4, 0.45, steel, pMetal),
                b(-0.35, 0.8, -4.2, 0.7, 0.55, 3.2, steel, pMetal),                // trigger lever
                b(-0.3, 0.8, -1.2, 0.6, 0.9, 0.5, steel, pMetal),
            ]
            let m = p.count
            p += [b(-2.4, -2.4, -20, 4.8, 4.8, 8, drab, pMetal),                   // warhead
                  b(-1.6, -1.6, -23, 3.2, 3.2, 3, drab, pMetal),                   // nose
                  b(-0.6, -0.6, -24.2, 1.2, 1.2, 1.2, steel, pMetal),              // fuze tip
                  b(-0.5, -0.5, -12.6, 1.0, 1.0, 1.0, steel, pMetal)]              // tail boom into the tube
            return GunModel(parts: p, mag: [m, m + 1, m + 2, m + 3], grip: V3(0, -1.2, -2.6), fore: V3(0, -1.2, -9.5), butt: V3(0, 0, 10),
                            muzzle: V3(0, 0, -24.4), magAt: V3(0, 0, -16), bolt: V3(0, 1.4, -2.6), scale: 0.56)
        case Guns.hagel:
            var p: [Part] = [
                b(-0.7, -0.2, -8, 1.4, 1.4, 11, blued, pMetal),                    // receiver tube
                b(-0.35, 0.15, -13, 0.7, 0.7, 5, blued, pMetal),                   // barrel
                b(-0.3, -0.65, -12.6, 0.6, 0.5, 2.2, steel, pMetal),               // barrel rest bar
                b(-0.45, 0.05, -13.6, 0.9, 0.9, 0.6, steel, pMetal),               // muzzle nut
                b(-0.15, 0.35, -13.7, 0.3, 0.3, 0.12, bore, 0),
                b(-0.3, 1.2, -12.8, 0.6, 0.7, 0.6, blued, pMetal),                 // hooded front sight
                b(-0.3, 1.2, -2.6, 0.6, 0.6, 1.0, steel, pMetal),                  // rear sight
                b(-0.75, -1.4, -6, 1.5, 1.2, 8, bakelite, pWood),                  // lower housing
                b(-0.6, -2.1, -5.6, 1.2, 0.8, 1.6, blued, pMetal),                 // magazine well
                b(-0.6, -4.4, 0.4, 1.2, 3.0, 1.6, bakelite, pWood),                // pistol grip
                b(-0.25, -1.9, -1.4, 0.5, 0.3, 1.8, steel, pMetal),                // trigger guard
                b(-1.5, 0.4, -5.2, 0.8, 0.5, 0.6, steel, pMetal),                  // cocking handle (left)
                b(-0.7, -0.8, 3, 0.15, 0.5, 8, steel, pMetal),                     // folding stock arms, unfolded
                b(0.55, -0.8, 3, 0.15, 0.5, 8, steel, pMetal),
                b(-0.7, -2.6, 9.6, 1.4, 0.4, 1.0, steel, pMetal),                  // stock strut
                b(-0.75, -2.8, 10.6, 1.5, 2.8, 0.5, steel, pMetal),                // butt plate
            ]
            let m = p.count
            p.append(b(-0.5, -7.8, -5.45, 1.0, 5.8, 1.4, blued, pMetal))           // the long straight magazine
            return GunModel(parts: p, mag: [m], grip: V3(0, -2.4, 1.2), fore: V3(0, -2.6, -4.7), butt: V3(0, -1.4, 11),
                            muzzle: V3(0, 0.5, -13.7), magAt: V3(0, -4.9, -4.75), bolt: V3(-1.1, 0.65, -4.9), scale: 0.6)
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
        default:
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
        }
    }

    // Small fittings: the Ashsaw's jacket cooling slots, the rifle's sling swivels, the carbine's ribs.
    static func details(_ i: Int) -> [Part] {
        var p: [Part] = []
        switch i {
        case Guns.faust:
            break                                                                // (all in the model)
        case Guns.hagel:
            for k in 0..<3 { p.append(b(-0.72, 0.1 + Float(k) * 0.35, -7.5, 0.04, 0.15, 7, steel * 0.75, pMetal)) }   // receiver grooves
            p.append(b(-0.2, -0.95, -7.6, 0.4, 0.3, 0.5, steel, pMetal))        // sling loop
        case Guns.kessel:
            p.append(b(-0.2, -1.6, -19.8, 0.4, 0.4, 0.6, steel, pMetal))
            p.append(b(-0.2, -3.7, 9.0, 0.4, 0.4, 0.8, steel, pMetal))
            // P217 redo (Oct 14, "frontier guns look like their real-world counterparts"): the classic bolt-action
            // service rifle's tells: the cleaning rod under the muzzle, the bayonet lug, the sling slot through the
            // butt, the bolt's flat sleeve behind the handle and the stock's pistol-grip wrist.
            p.append(b(-0.12, 0.45, -26.4, 0.24, 0.24, 6.6, steel, pMetal))      // cleaning rod
            p.append(b(-0.2, 0.15, -21.6, 0.4, 0.45, 1.3, steel, pMetal))        // bayonet lug
            p.append(b(-0.92, -2.2, 7.4, 0.06, 0.5, 1.6, bore, 0))               // sling slot (left)
            p.append(b(0.86, -2.2, 7.4, 0.06, 0.5, 1.6, bore, 0))                // (right)
            p.append(b(-0.45, 1.2, 0.6, 0.9, 0.75, 1.6, steel, pMetal))          // bolt sleeve and safety
            p.append(b(-0.7, -2.6, 0.8, 1.4, 1.2, 2.0, walnut * 0.92, pWood))   // pistol-grip wrist
        default:
            for k in 0..<3 { p.append(b(-0.85, 0.6 + Float(k) * 0.4, -12.5, 0.06, 0.2, 5, steel * 0.8, pMetal)) }
        }
        return p
    }

    static let icons: [String: [String]] = [
        "gun_kessel": ["................", "................", "................", "................", "................",
                       "............1...", "11111111111m1...", "1mmmmmmmmmmmm11.", ".1aaaaaaaaa1aaa1", "..111111111.1aa1",
                       "............1aa1", ".............111", "................", "................", "................", "................"],
        "gun_sturmwind": ["................", "................", "................", "................", "................",
                          "................", "........11......", "11111111mm111111", "1mmmmmmmmmmm1aa1", ".1111dd1d1111aa1",
                          "....1dd11a1..111", "....1dd1.1a1....", ".....1dd1.11....", "......111.......", "................", "................"],
    ]
}
