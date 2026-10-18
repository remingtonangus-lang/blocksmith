import Foundation
import simd

// The Ashguard's field dress (backlog B7, docs/status/the-last-war.md), drawn by SoldierRig for every soldier of
// the Ashguard faction: the period's silhouette in black, marked only with the Ashguard's own ember mark (P360 (b): a
// field-grey armband with an ember-orange patch and a black bar; red collar tabs). No real insignia, runes, crosses or eagles.
//   Riflemen, stormers and heavies   flared steel helmet, pocketed tunic, Y-straps, belt pouches, gas-mask canister, jackboots
//   Heavies                          a gas mask with red lenses, ammunition belts across the chest, a spare-barrel case
//   Sharpshooters                    a soft field cap with a short bill, a binocular case
//   Officers, the Marshal            high-crowned peaked cap with red piping, greatcoat with red lapels, breeches, cross strap
//   Drivers                          side cap and headset, short wrap jacket
//   The Ash Chancellor               an officer's cut in black leather, silver cords on the cap
enum AshLook {
    static let leather = V3(0.05, 0.045, 0.04), white = V3(0.86, 0.85, 0.82), mark = V3(0.03, 0.03, 0.035)
    static let band = V3(0.29, 0.3, 0.27), ember = V3(0.85, 0.41, 0.12)
    static let brass = V3(0.72, 0.55, 0.24)

    typealias Box = (Float, Float, Float, Float, Float, Float, V3, Float) -> Void
    typealias Strap = (V2, V2, Float, Float, Float, Int, V3, Float) -> Void

    static func torso(_ m: Mob, _ lv: Livery, rank r: Int, full: Bool, mid: Bool, tb: Box, strap: Strap) {
        let steps = full ? 4 : 2
        if mid { tb(-2.5, 23.5, -2.42, 1.3, 1.0, 0.14, lv.trim, Pat.cloth); tb(1.2, 23.5, -2.42, 1.3, 1.0, 0.14, lv.trim, Pat.cloth) }   // collar tabs
        if r == 4 {
            // Greatcoat: double-breasted, red lapels, belted, a cross strap from the right shoulder.
            let coat: Float = m.kind == .ashChancellor ? Pat.leather : Pat.cloth
            tb(-4.35, 10.2, -2.35, 8.7, 13.6, 4.7, lv.cloth, coat)
            tb(-2.9, 18.6, -2.5, 1.4, 4.8, 0.14, lv.trim, Pat.cloth); tb(1.5, 18.6, -2.5, 1.4, 4.8, 0.14, lv.trim, Pat.cloth)
            if full { for y: Float in [11.2, 14.6, 17.0] { tb(-2.0, y, -2.52, 0.7, 0.7, 0.12, lv.metal, Pat.metal); tb(1.3, y, -2.52, 0.7, 0.7, 0.12, lv.metal, Pat.metal) } }
            tb(-4.45, 12.6, -2.45, 8.9, 1.4, 4.9, leather, Pat.leather)
            tb(-0.8, 12.75, -2.58, 1.6, 1.1, 0.14, lv.metal, Pat.metal)
            if mid { strap(V2(3.2, 23.4), V2(-3.0, 13.8), 0.9, -2.5, 0.12, full ? 6 : 3, leather, Pat.leather) }
            if m.kind == .ashMarshal && full {
                tb(-3.4, 20.8, -2.56, 2.2, 0.6, 0.12, lv.accent, Pat.metal)                     // ribbon bar
                tb(-3.1, 19.4, -2.56, 0.8, 1.0, 0.12, lv.metal, Pat.metal)
            }
            return
        }
        if mid {
            // Four pockets with flaps.
            let pocket = lv.cloth * 1.18, flap = lv.cloth * 1.4
            for x: Float in [-3.4, 1.0] {
                tb(x + 0.1, 18.0, -2.1, 2.2, 2.2, 0.12, pocket, Pat.cloth)
                tb(x, 20.2, -2.14, 2.4, 0.7, 0.14, flap, Pat.cloth)
            }
            for x: Float in [-3.7, 1.0] {
                tb(x + 0.1, 14.2, -2.1, 2.6, 2.4, 0.12, pocket, Pat.cloth)
                tb(x, 16.5, -2.14, 2.8, 0.6, 0.14, flap, Pat.cloth)
            }
            // Y-straps over the shoulders to the belt, joined at the back.
            strap(V2(-2.6, 23.8), V2(-2.0, 14.0), 0.75, -2.24, 0.14, steps, leather, Pat.leather)
            strap(V2(2.6, 23.8), V2(2.0, 14.0), 0.75, -2.24, 0.14, steps, leather, Pat.leather)
            tb(-0.4, 14.0, 2.05, 0.8, 9.6, 0.14, leather, Pat.leather)
        }
        // Gas-mask canister on the back (ridged), bread bag on the right hip.
        tb(-1.1, 9.6, 2.1, 2.2, 4.6, 2.2, lv.metal * 0.9, Pat.metal)
        if mid { tb(-1.15, 11.0, 2.08, 2.3, 0.3, 2.3, lv.metal * 1.3, Pat.metal); tb(-1.15, 12.6, 2.08, 2.3, 0.3, 2.3, lv.metal * 1.3, Pat.metal) }
        tb(2.4, 9.2, -0.6, 1.9, 2.6, 2.0, lv.cloth * 1.6, Pat.cloth)
        switch r {
        case 3:
            // Heavy: ammunition belts crossed over the chest, a spare-barrel case slung on the back.
            strap(V2(-3.4, 23.0), V2(2.8, 13.4), 1.0, -2.32, 0.3, full ? 6 : 3, brass, Pat.metal)
            strap(V2(3.4, 23.0), V2(-2.8, 13.4), 1.0, -2.36, 0.3, full ? 6 : 3, brass, Pat.metal)
            tb(-3.6, 12.0, 2.1, 1.0, 10.0, 1.0, lv.metal, Pat.metal)
        case 2:
            tb(2.2, 12.8, -2.6, 1.4, 2.0, 0.8, leather, Pat.leather)                            // binocular case
            for x: Float in [-3.9, -2.7] { tb(x, 11.4, -2.8, 1.1, 1.8, 0.7, leather, Pat.leather) }
        case 5:
            // Driver: a short wrap jacket buttoned on the diagonal.
            if mid { strap(V2(3.4, 23.0), V2(-1.4, 14.2), 0.4, -2.2, 0.12, steps, lv.cloth * 1.5, Pat.cloth) }
        default:
            // Riflemen and stormers: three ammunition pouches either side of the buckle.
            for x: Float in [-3.9, -2.7, 1.6, 2.8] { tb(x, 11.4, -2.8, 1.1, 1.8, 0.7, leather, Pat.leather) }
            if r == 1 {
                // A stick grenade pushed into the belt.
                tb(-1.6, 10.6, -2.75, 0.5, 3.6, 0.5, AshArms.walnut, 10)
                tb(-1.85, 14.1, -2.95, 1.0, 1.3, 1.0, lv.metal, Pat.metal)
            }
        }
    }

    // Shoulder straps on both arms; the armband (field grey, the ember mark's orange patch and black bar) on the left.
    static func arm(_ s: V3, _ ua: (Float, Float), side: Float, _ lv: Livery, rank r: Int, full: Bool, mid: Bool) -> [Part] {
        var o: [Part] = []
        o.append(SoldierRig.on(s, ua, V3(-1.95, 1.3, -1.95), V3(1.95, 2.05, 1.95), r == 4 ? lv.metal * 0.85 : lv.cloth * 1.3, Pat.cloth))
        if mid { o.append(SoldierRig.on(s, ua, V3(-2.0, 1.2, -2.0), V3(2.0, 1.36, 2.0), lv.trim, Pat.cloth)) }
        if side < 0 {
            o.append(SoldierRig.on(s, ua, V3(-1.84, -3.6, -1.84), V3(1.84, -1.9, 1.84), band, Pat.cloth))
            if mid {
                let x = side * 1.86
                o.append(SoldierRig.on(s, ua, V3(x - 0.06, -3.35, -0.75), V3(x + 0.06, -2.15, 0.75), ember, Pat.cloth))
                if full { o.append(SoldierRig.on(s, ua, V3(x - 0.1, -3.15, -0.16), V3(x + 0.1, -2.35, 0.16), mark, 0)) }
            }
        }
        return o
    }

    static func head(_ m: Mob, _ lv: Livery, rank r: Int, full: Bool, mid: Bool, hb: Box) {
        switch r {
        case 0, 1, 3:
            // Flared steel helmet: dome, rim, a short brow, the skirt flaring out over the ears and the neck.
            hb(-4.4, 28.6, -4.4, 8.8, 3.4, 8.8, lv.plate, Pat.metal)
            hb(-3.6, 32.0, -3.6, 7.2, 0.8, 7.2, lv.plate, Pat.metal)
            hb(-4.7, 27.9, -4.7, 9.4, 0.9, 9.4, lv.plate, Pat.metal)
            hb(-4.5, 28.2, -5.4, 9.0, 0.6, 1.2, lv.plate, Pat.metal)
            hb(-5.0, 25.9, -2.2, 0.9, 2.4, 7.1, lv.plate, Pat.metal); hb(4.1, 25.9, -2.2, 0.9, 2.4, 7.1, lv.plate, Pat.metal)
            hb(-5.0, 25.9, 4.1, 10.0, 2.4, 0.9, lv.plate, Pat.metal)
            if mid { hb(-4.2, 24.1, -1.0, 8.4, 0.4, 0.4, leather, Pat.leather) }                    // chin strap
            if r == 3 {
                // Gas mask: rubber face, two round red lenses, the filter snout. P315 (Oct 15 19:06, "the mask should
                // cover the whole head"): a full rubber hood under the helmet, over the sides, back and nape, so no skin
                // shows anywhere; the face plate and lenses sit on it.
                hb(-4.3, 24.0, -4.3, 8.6, 4.7, 8.6, leather * 0.85, Pat.leather)
                hb(-3.9, 22.9, -3.9, 7.8, 1.2, 7.8, leather * 0.85, Pat.leather)                // the hood's neck skirt
                hb(-3.7, 24.3, -4.5, 7.4, 4.8, 0.5, leather, Pat.leather)
                hb(-2.9, 26.9, -4.62, 1.7, 1.5, 0.14, lv.glow * 0.6, Pat.glow); hb(1.2, 26.9, -4.62, 1.7, 1.5, 0.14, lv.glow * 0.6, Pat.glow)
                hb(-1.0, 24.0, -5.7, 2.0, 1.8, 1.3, lv.metal, Pat.metal)
            }
        case 2:
            // Soft field cap with a short bill and a small red ember badge.
            hb(-4.3, 29.4, -4.3, 8.6, 2.4, 8.6, lv.cloth * 1.2, Pat.cloth)
            hb(-4.0, 31.8, -4.0, 8.0, 0.5, 8.0, lv.cloth * 1.2, Pat.cloth)
            hb(-3.6, 29.2, -5.7, 7.2, 0.45, 1.5, lv.cloth, Pat.cloth)
            if full { hb(-0.5, 30.4, -4.42, 1.0, 1.0, 0.14, lv.trim, Pat.cloth) }
        case 4:
            // High-crowned peaked cap: band with red piping, the crown raised at the front, a glossy black peak, cords,
            // the ember badge.
            hb(-4.3, 29.4, -4.3, 8.6, 1.7, 8.6, lv.cloth, Pat.cloth)
            hb(-4.9, 31.0, -5.1, 9.8, 1.2, 9.9, lv.cloth * 1.1, Pat.cloth)
            hb(-4.6, 32.1, -5.4, 9.2, 1.1, 2.8, lv.cloth * 1.1, Pat.cloth)
            hb(-4.0, 29.15, -6.7, 8.0, 0.5, 2.5, V3(0.02, 0.02, 0.02), Pat.leather)
            if mid {
                hb(-4.36, 29.35, -4.36, 8.72, 0.22, 8.72, lv.trim, Pat.cloth)
                hb(-4.36, 30.95, -4.36, 8.72, 0.22, 8.72, lv.trim, Pat.cloth)
                hb(-3.8, 29.8, -4.46, 7.6, 0.3, 0.14, lv.metal, Pat.metal)
            }
            if full {
                // a red cockade with a white centre (one round badge, nothing letter-like)
                hb(-0.75, 31.4, -5.48, 1.5, 1.5, 0.14, mark, 0)
                hb(-0.3, 31.85, -5.56, 0.6, 0.6, 0.14, white, Pat.cloth)
            }
        default:
            // Side cap and a headset.
            hb(-3.0, 30.0, -4.3, 6.0, 1.8, 8.6, lv.cloth * 1.2, Pat.cloth)
            hb(-2.4, 31.8, -4.0, 4.8, 0.5, 8.0, lv.cloth * 1.2, Pat.cloth)
            hb(-4.7, 25.8, -1.2, 0.7, 2.4, 2.4, leather, Pat.leather); hb(4.0, 25.8, -1.2, 0.7, 2.4, 2.4, leather, Pat.leather)
            hb(-4.7, 28.2, -0.5, 9.4, 0.5, 1.0, leather, Pat.leather)
        }
    }
}
