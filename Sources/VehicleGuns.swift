import Foundation
import simd

// P477 (Oct 27 19:21-19:31, the Vehicle Works' presets: "the tank doesn't look anything like the Ashguard's tank...
// tracks go in circles as if they were a wheel. Gun's not powerful enough. Should be four times as powerful. Has a
// tendency to shoot upwards... Should be a straight shooter. The helm shouldn't stick out like that"; "Scout buggy...
// Needs to look entirely different, needs to go faster"; "The gun truck's just a dual-barrelled tank"; "Every tank is
// just a tank with an extra wheel on it. It shoots three cannonballs. Stop using the cannonball thing. Use the barrel
// system"; "Siege gun... This is just a heavy tank. What's the difference?"):
//   the gun system  a cannon block is the breech; bored barrels laid on from it (ShipBlocks: small, medium, large)
//                   set its calibre, and every further tube adds reach and punch. A calibre gun fires a shell flat and
//                   fast (CannonCalibre), drawn as a steel shell with a tracer, never a lobbed ball.
//   the vehicles    each its own build: the Field Tank in the Ashguard's tank's lines (low black hull on track links,
//                   steel deck with a red band, a boxy turret with a long medium gun, the helm sunk in a hatch behind
//                   it); the Scout Buggy an open roll cage on four small wheels with two engines; the Gun Truck a
//                   cab with a windscreen and a flatbed carrying a quick small-bore autocannon; the Heavy Tank wide,
//                   tall on its tracks with skirts and a big-bore gun and the commander's autocannon on its own ring; the Siege Gun a long
//                   large gun behind an open shield on a low tracked carriage, an ammunition rack behind.
enum CannonCalibre {
    struct Spec { let speed: Float, gravity: Float, power: Float, reload: Float, scatter: Float }
    static let small = Spec(speed: 150, gravity: 1.5, power: 1.6, reload: 0.25, scatter: 0.008)
    static let medium = Spec(speed: 120, gravity: 2.5, power: 6, reload: 3.5, scatter: 0)
    static let large = Spec(speed: 140, gravity: 3, power: 7, reload: 6, scatter: 0)
    static func spec(_ c: Int) -> Spec { c <= 1 ? small : (c == 2 ? medium : large) }
    static let maxPower: Float = 12

    // Barrel block group -> calibre (0 for the plain P459 Gun Barrel, which lengthens the old gun).
    static let tubeBases: [BlockID: Int] = {
        var t: [BlockID: Int] = [:]
        for (k, c) in [("ship_gun_barrel", 0), ("gun_barrel_small", 1), ("gun_barrel_medium", 2), ("gun_barrel_large", 3)] where Blocks.has(k) {
            t[Blocks.groupBase[Int(Blocks.id(k))]] = c
        }
        return t
    }()
    // P507: per block state, the calibre of a calibre tube (small, medium, large: 1...3), else 0.
    static let boreT: [UInt8] = (0..<Blocks.count).map { UInt8(max(0, tubeBases[Blocks.groupBase[$0]] ?? 0)) }
}

extension Ship {
    // The speed and drop of this hull's first cannon's shell (what a sight lays it for).
    var shellFlight: (Float, Float) {
        guard let cal = cannonCalibre.first, cal > 0 else { return (gunSpeed, gunGravity) }
        let spec = CannonCalibre.spec(cal)
        return (spec.speed * (1 + 0.06 * Float(max(0, (cannonLength.first ?? 1) - 1))), spec.gravity)
    }
}

extension VehiclePresets {
    // Field Tank: the Ashguard's tank in blocks. Front toward -Z, ground at y 0, centreline x 0.
    static func fieldTank() -> Blueprint {
        let b = Blueprint()
        for x in [-3, 3] { for y in 0...1 { for z in 0...10 { b.set(x, y, z, "ship_track") } } }
        b.box(-2, 2, 1, 1, 0, 10, "black_concrete")                                         // the slab hull between the tracks
        for x in -3...3 { b.set(x, 2, 0, "steel_plating") }                                 // the near-vertical front plate
        b.box(-3, 3, 2, 2, 1, 10, "black_concrete")                                         // deck over the tracks
        for x in [-3, 3] { for z in 2...5 { b.set(x, 2, z, "red_concrete") } }              // the red band on both flanks
        b.set(0, 1, 7, "ship_engine"); b.set(0, 1, 9, "ship_engine")
        b.set(0, 2, 8, "ship_helm[south]")                                                  // sunk in the deck: no post
        b.clear(0, 2, 9)                                                                    // ...his hatch behind it
        for x in [-2, 2] { b.set(x, 3, 10, "iron_bars") }                                   // exhaust stacks
        b.set(0, 2, 4, "ship_turret_ring")
        let t = Blueprint()
        t.box(-2, 2, 0, 1, -2, 2, "black_concrete")                                         // the boxy turret
        for x in [-2, 2] { for z in -1...1 { t.set(x, 1, z, "red_concrete") } }             // turret band
        t.set(-1, 2, 1, "steel_plating")                                                    // commander's cupola
        t.set(0, 0, -2, "ship_cannon[south]")                                               // the breech in its face
        for z in -7 ... -3 { t.set(0, 0, z, "gun_barrel_medium[south]") }                   // the long gun
        t.set(0, 0, -8, "gun_barrel_large[south]")                                          // ...and its muzzle brake
        b.turrets.append((IVec3(0, 2, 4), t))
        return b
    }

    // Scout Buggy: an open roll cage on four small wheels, two engines in a light frame.
    static func scoutBuggy() -> Blueprint {
        let b = Blueprint()
        for x in [-3, 3] { for z in [1, 6] { b.set(x, 0, z, "ship_wheel") } }
        b.box(-3, 3, 1, 1, 0, 7, "steel_grating")                                           // the floor pan
        for x in -2...2 { b.set(x, 2, 0, "hazard_plating") }                                // front bumper
        b.set(-3, 2, 0, "light_panel"); b.set(3, 2, 0, "light_panel")                       // lamps
        b.set(0, 2, 4, "ship_helm[south]")
        b.set(-1, 2, 7, "ship_engine"); b.set(1, 2, 7, "ship_engine")
        for (x, z) in [(-2, 2), (2, 2), (-2, 6), (2, 6)] { for y in 2...3 { b.set(x, y, z, "iron_bars") } }   // the roll cage
        for z in 2...6 { b.set(-2, 4, z, "iron_bars"); b.set(2, 4, z, "iron_bars") }
        for x in -1...1 { b.set(x, 4, 2, "iron_bars"); b.set(x, 4, 6, "iron_bars") }
        return b
    }

    // Gun Truck: a cab with a windscreen, a flatbed behind with a small-bore autocannon on a ring.
    static func gunTruck() -> Blueprint {
        let b = Blueprint()
        for x in [-3, 3] { for z in [1, 7, 10] { b.set(x, 0, z, "ship_wheel") } }
        b.box(-3, 3, 1, 1, 0, 11, "steel_plating")                                          // chassis and bed
        b.set(0, 2, 0, "ship_engine")                                                       // under the bonnet
        for x in [-1, 1] { b.set(x, 2, 0, "steel_plating") }
        for x in [-2, 2] { b.set(x, 2, 0, "light_panel") }                                  // headlamps
        for x in -2...2 { b.set(x, 2, 1, "steel_plating") }                                 // dashboard
        for x in -2...2 { for y in 3...4 { b.set(x, y, 1, abs(x) < 2 ? "armored_glass" : "steel_plating") } }   // windscreen
        for z in 2...3 { for y in 2...4 { b.set(-2, y, z, "steel_plating"); b.set(2, y, z, "steel_plating") } }
        for y in 2...3 { b.clear(-2, y, 3); b.clear(2, y, 3) }                              // the cab doors, open
        b.box(-2, 2, 5, 5, 1, 3, "steel_plating")                                           // cab roof
        b.set(0, 2, 2, "ship_helm[south]")
        for z in 5...11 { b.set(-3, 2, z, "iron_bars"); b.set(3, 2, z, "iron_bars") }      // bed rails
        b.set(0, 2, 11, "ship_engine")
        b.set(0, 1, 8, "ship_turret_ring")
        let t = Blueprint()
        t.set(0, 0, 0, "steel_plating")                                                     // the pedestal
        t.set(0, 1, 0, "ship_cannon[south]")
        for z in -3 ... -1 { t.set(0, 1, z, "gun_barrel_small[south]") }
        for x in [-1, 1] { for y in 1...2 { t.set(x, y, -1, "steel_plating") } }            // the gun shield
        b.turrets.append((IVec3(0, 1, 8), t))
        return b
    }

    // Heavy Tank: wide and tall on its tracks, side skirts, a big-bore gun, and the commander's autocannon behind it.
    static func heavyTank() -> Blueprint {
        let b = Blueprint()
        for x in [-4, 4] { for y in 0...2 { for z in 0...14 { b.set(x, y, z, "ship_track") } } }
        for x in [-5, 5] { for z in 1...13 { b.set(x, 2, z, "steel_plating") } }            // skirts over the tracks
        b.box(-3, 3, 1, 2, 0, 14, "black_concrete")
        for x in -4...4 { for y in 1...3 { b.set(x, y, 0, "steel_plating") } }              // glacis
        b.box(-4, 4, 3, 3, 1, 14, "black_concrete")                                         // deck
        for x in [-4, 4] { for z in 3...7 { b.set(x, 3, z, "red_concrete") } }
        b.set(-1, 2, 11, "ship_engine"); b.set(0, 2, 11, "ship_engine"); b.set(1, 2, 11, "ship_engine")
        b.set(0, 3, 12, "ship_helm[south]"); b.clear(0, 3, 13)
        for x in [-3, 3] { for y in 4...5 { b.set(x, y, 14, "iron_bars") } }                // exhaust stacks
        b.set(0, 3, 6, "ship_turret_ring")
        let t = Blueprint()
        t.box(-3, 3, 0, 2, -3, 3, "black_concrete")
        for x in [-3, 3] { for z in -2...2 { t.set(x, 1, z, "red_concrete") } }
        t.box(-1, 0, 3, 3, 1, 2, "steel_plating")                                           // cupola
        t.set(0, 1, -3, "ship_cannon[south]")
        for z in -9 ... -4 { t.set(0, 1, z, "gun_barrel_large[south]") }
        b.turrets.append((IVec3(0, 3, 6), t))
        // The commander's autocannon on its own ring behind, high enough to fire over the big turret's roof.
        b.set(2, 3, 11, "ship_turret_ring")
        let c = Blueprint()
        for y in 0...2 { c.set(0, y, 0, "steel_plating") }
        c.set(0, 3, 0, "ship_cannon[south]")
        for z in -3 ... -1 { c.set(0, 3, z, "gun_barrel_small[south]") }
        b.turrets.append((IVec3(2, 3, 11), c))
        return b
    }

    // Siege Gun: a long large gun behind an open shield on a low tracked carriage, the ammunition racks behind.
    static func siegeGun() -> Blueprint {
        let b = Blueprint()
        for x in [-4, 4] { for y in 0...1 { for z in 0...13 { b.set(x, y, z, "ship_track") } } }
        b.box(-3, 3, 1, 1, 0, 13, "black_concrete")                                         // the low carriage
        b.box(-4, 4, 2, 2, 0, 13, "steel_grating")                                          // gun platform
        for x in [-3, 3] { for z in 10...13 { for y in 3...4 { b.set(x, y, z, "steel_plating") } } }    // ammunition racks
        for x in [-2, 2] { b.set(x, 3, 12, "hazard_plating") }
        b.set(-1, 3, 13, "ship_engine"); b.set(1, 3, 13, "ship_engine")
        b.set(0, 3, 10, "ship_helm[south]")
        for x in [-4, 4] { b.set(x, 3, 0, "iron_bars"); b.set(x, 3, 1, "iron_bars") }      // rails
        for x in -3...3 { b.set(x, 1, -1, "hazard_plating") }                               // the dozer spade
        b.set(0, 2, 5, "ship_turret_ring")
        let t = Blueprint()
        t.box(-2, 2, 0, 0, -1, 1, "steel_plating")                                          // the mount
        for x in -3...3 { for y in 1...3 where !(x == 0 && y == 2) { t.set(x, y, -2, "steel_plating") } }   // the open shield
        t.set(0, 1, -1, "black_concrete")
        t.set(0, 2, -1, "ship_cannon[south]")
        for z in -9 ... -2 { t.set(0, 2, z, "gun_barrel_large[south]") }                    // the long gun, through the shield
        b.turrets.append((IVec3(0, 2, 5), t))
        return b
    }
}
