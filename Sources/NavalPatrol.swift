import Foundation
import simd

// P243 (Oct 13 21:55): "a normal navy warship sailing the seas". The Tidewatch Destroyer: a grey steel patrol ship of
// the Meridian Navy (no lift, no energy weapons) that keeps station over open sea, circling a patrol point a few
// hundred blocks across, with two gun turrets fore and aft, a bridge, a funnel and a mast. About 4% of the 2 km
// encounter regions hold one where the region's point is open water (Vessels.encounter). Its guns fire on you only
// when the Meridian Navy dislikes you (standing below zero, FactionRep); board her, clear the deck and take the helm
// and she is yours. Her hull is Naval Hull Plate: thin steel over a hollow frame (0.45 t a block, ShipParts.mass),
// so she floats with a third of her depth under water.
enum NavalPatrol {
    static let name = "Tidewatch Destroyer"
    static let role = "destroyer"
    static let hull = "naval_hull"

    // Bow toward -Z, 41 long and 9 wide, deck at y 4.
    static func destroyer() -> Blueprint {
        let b = Blueprint()
        func hw(_ z: Int) -> Int {
            if z < -14 { return max(0, (z + 20) * 2 / 3) }      // the bow narrows to a stem
            if z > 17 { return 3 }
            return 4
        }
        for z in -20...20 {
            let w = hw(z)
            for x in -w...w {
                let edge = abs(x) == w || z == -20 || z == 20
                if abs(x) < w || w == 0 { b.set(x, 0, z, hull) }                    // bottom
                for y in 1...3 where edge { b.set(x, y, z, hull) }                // sides
                b.set(x, 4, z, hull)                                              // deck
                if abs(x) == w && w > 0 && (z < -3 || z > 7) { b.set(x, 5, z, "iron_bars") }   // rails
            }
        }
        // The bridge: a hollow house with windows forward, a roof, a mast with a yard.
        b.box(-2, 2, 5, 8, -3, 6, hull, hollow: true)
        for x in -1...1 { b.set(x, 7, -3, "gray_stained_glass") }
        b.set(-2, 7, 0, "gray_stained_glass"); b.set(2, 7, 0, "gray_stained_glass")
        for y in 5...6 { b.clear(0, y, 6) }                                       // the door aft
        for y in 9...14 { b.set(0, y, 1, "iron_bars") }
        for x in -2...2 where x != 0 { b.set(x, 13, 1, "iron_bars") }
        // The funnel.
        for y in 5...10 { b.set(0, y, 9, hull); b.set(0, y, 10, hull) }
        b.set(0, 11, 9, "black_concrete"); b.set(0, 11, 10, "black_concrete")
        // Helm on the bridge, engines in the hold, twin screws astern.
        b.set(0, 5, -1, "ship_helm[south]")
        b.set(-1, 1, 12, "ship_engine"); b.set(1, 1, 12, "ship_engine")
        b.set(-1, 1, 21, "ship_propeller[south]"); b.set(1, 1, 21, "ship_propeller[south]")
        // Gun turrets fore and aft: a cannon behind a steel shield.
        for (z, aft) in [(-10, false), (15, true)] {
            b.set(0, 5, z, "ship_turret_ring")
            let t = Blueprint()
            t.set(0, 0, 0, aft ? "ship_cannon[north]" : "ship_cannon[south]")
            t.set(-1, 0, 0, hull); t.set(1, 0, 0, hull)
            b.turrets.append((IVec3(0, 5, z), t))
        }
        b.chests.append((IVec3(-1, 5, 18), "shipwreck_supply"))
        b.set(-1, 5, 18, "chest")
        b.crew = [V3(-2.5, 5, -6.5), V3(2.5, 5, -6.5), V3(0.5, 5, 1.5), V3(-2.5, 5, 13.5), V3(2.5, 5, 16.5)]
        return b
    }
}
