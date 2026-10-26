import Foundation

// P450 + P461 (Remington, Oct 25 09:16-09:18 aboard the Stormwarden Frigate he had taken: "Way too hollow"; "it's just a
// shell of a ship... All this hollowness reads as cheap"; "Enough with the ladders, okay? Staircases. No ladders, only
// staircases"; "it just drops into another hollow part"; "I want hallways, not this shit"; and 17:02 on another one:
// "the ship needs to have more hallways... Looks like they made the shell and just didn't do anything else"): the
// frigate was a 480-block skin round a hangar and one upper deck. Now its hull is decked every 5 blocks (rooms 4 high)
// from the keel to the bridge. Each deck is a hallway down the middle with cabins off both sides: bays 12 long, an inner
// and an outer cabin each side, a door off the hallway into the inner one and on through to the outer, a light in each
// ceiling and the cabin's fittings (bunks, lockers, mess tables, consoles, the odd stores chest). The rail cannon runs
// through the middle of its two decks between the hallway's walls. Staircases (two lanes of 5-step flights, switching
// back, walled in) replace the ladders: in the bow, from the keel into the hangar, aft of the hangar and up into the
// bridge. The hangar (open through both flanks), the bridge and the engine hall stay open, closed off from the decks by
// bulkheads with a door at the hallway.
extension Capital {
    static let frigateLevels = Array(stride(from: 11, through: 86, by: 5))
    static var decksOff = false              // (questcheck --frigatedecks: the hull as it was, for the before)

    static func frigateDecks(_ hb: HullBuilder) {
        let deck = id("steel_grating"), wall = id("warship_panel"), light = id("light_panel")
        let stairUp = id("steel_plating_stairs[south]", deck), stairDown = id("steel_plating_stairs", deck)
        let console = id("command_console"), cabinet = id("data_cabinet", console), barrel = id("barrel", wall)
        let wool = id("gray_wool", wall), slab = id("steel_plating_slab", deck), bars = id("iron_bars", wall)
        let door = id("bulkhead_door", id("iron_door"))
        let my = 60                                         // the rail cannon's axis (y), z 0-400, radius 4.6
        // Inside the hull, not its skin.
        func inner(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            frigateInside(x, y, z) && frigateInside(x + 1, y, z) && frigateInside(x - 1, y, z) && frigateInside(x, y + 1, z)
                && frigateInside(x, y - 1, z) && frigateInside(x, y, z + 1) && frigateInside(x, y, z - 1)
        }
        func tube(_ x: Int, _ y: Int, _ z: Int) -> Bool { z <= 400 && x * x + (y - my) * (y - my) <= 21 }
        // Left open: the hangar, the bridge over the hull top, the engine hall.
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            if abs(x) <= 30 && y >= 27 && y <= 45 && z >= 160 && z <= 340 { return true }
            if z >= 296 && z <= 336 && abs(x) <= 10 && y >= 76 { return true }
            if z >= 341 && (y < 21 || y >= 71) { return true }   // (pockets under and over the aft decks no stair reaches)
            return z >= 384
        }
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            if hb.get(x, y, z) == AIR && inner(x, y, z) && !open(x, y, z) && !tube(x, y, z) { hb.set(x, y, z, b) }
        }
        // A deck at level f where cell (x, f, z) has a room at least 3 high over it.
        func floorOK(_ x: Int, _ f: Int, _ z: Int) -> Bool { inner(x, f, z) && inner(x, f + 3, z) && !open(x, f, z) }
        let W = 56, L = frigateLength
        let trades = ["bunks", "stores", "mess", "bunks", "workshop", "quarters", "comms", "bunks", "armoury", "medbay", "stores", "galley"]
        for f in frigateLevels {
            let gallery = f == 56 || f == 61                    // the decks the rail cannon runs through
            let c = gallery ? 7 : 2                              // the hallway's half-width
            for z in 20..<(L - 1) {
                for x in -W...W where floorOK(x, f, z) {
                    put(x, f, z, deck)
                    // Walls up to the next deck: the hallway's sides (a door into each inner cabin), the cabins' ends
                    // every 12, the wall between inner and outer cabins (a door through it).
                    let ax = abs(x), bay = z % 12
                    for y in (f + 1)...(f + 4) {
                        let doorway = y <= f + 2
                        if ax == c + 1 { if !(doorway && (bay == 6 || bay == 7)) { put(x, y, z, wall) } }
                        else if ax > c + 1 && bay == 0 { put(x, y, z, wall) }
                        else if ax == 16 && c < 15 && !(doorway && bay == 3) { put(x, y, z, wall) }
                    }
                }
            }
            // Lights in each cabin's ceiling and along the hallway; the fittings against the cabins' end walls (no
            // chests: hundreds of cabins would be hundreds of stores).
            for z in stride(from: 24, to: L - 13, by: 12) {
                for x in [-10, 10, -24, 24] where floorOK(x, f, z + 6) { put(x, f + 4, z + 6, light) }
                for x in gallery ? [-6, 6] : [0] { for dz in [3, 9] where floorOK(x, f, z + dz) { put(x, f + 4, z + dz, light) } }
                for sg in [-1, 1] { for (k, x) in [12, 22].enumerated() where floorOK(sg * x, f, z + 1) {
                    let i = (z / 12 + k * 5 + f) % trades.count
                    for dz in 0..<2 {
                        furnish(hb, sg * x, f + 1, z + 1 + dz * 2, trades[i], dz * 2, put: put, console: console, cabinet: cabinet,
                                barrel: barrel, wool: wool, slab: slab, bars: bars)
                    }
                } }
            }
        }
        // Bulkheads where the decks meet the hangar (fore and aft) and the engine hall, a pair of doors at the hallway.
        // (Shut, they seal the decks off from the hangar's open flanks: ShipMesh.sealedKeys leaves the decks undrawn
        // while he is outside the hull.)
        for (z, y0, y1, lv) in [(159, 27, 45, 26), (341, 27, 45, 26), (383, 11, 80, 21)] {
            for y in y0...y1 { for x in -W...W where inner(x, y, z) && !Blocks.opaque[Int(hb.get(x, y, z))] && !tube(x, y, z) {   // (over fittings too: bars in it let the air through)
                if (x == -1 || x == 0) && (y == lv + 1 || y == lv + 2) { continue }
                hb.set(x, y, z, wall)
            } }
            for x in [-1, 0] { hb.set(x, lv + 1, z, door); hb.set(x, lv + 2, z, door + 8) }
        }
        // The engine hall's floor is a block under the aft decks' (20 against 21): a step at the door.
        for x in -2...2 where hb.get(x, 21, 384) == AIR { hb.set(x, 21, 384, stairDown) }

        // Staircases, walled in: two lanes (x0...x0+1 climbing aft, x0+3...x0+4 climbing forward) with a wall between,
        // 5 steps a flight, landings across both lanes at z0-1 and z0+5 on every deck, and a floor over the lane that
        // doesn't come up to it. Out at either end onto the deck.
        func stairs(_ x0: Int, _ z0: Int, from lo: Int, to hi: Int, head: Bool = false) {
            let zs = (z0 - 1)...(z0 + 5)
            for y in (lo + 1)...hi { for z in zs { for x in (x0 - 1)...(x0 + 5) where inner(x, y, z) && !tube(x, y, z) { hb.set(x, y, z, AIR) } } }
            for y in (lo + 1)...(hi + 1) { for z in zs { for x in [x0 - 1, x0 + 5] where inner(x, y, z) && !tube(x, y, z) { hb.set(x, y, z, wall) } } }
            var k = 0
            for f in stride(from: lo, to: hi, by: 5) {
                let aft = k % 2 == 0
                for x in (aft ? x0 : x0 + 3)...(aft ? x0 + 1 : x0 + 4) { for j in 0..<5 {
                    hb.set(x, f + 1 + j, aft ? z0 + j : z0 + 4 - j, aft ? stairUp : stairDown)
                } }
                for z in z0...(z0 + 4) { for y in (f + 1)...(f + 5) { hb.set(x0 + 2, y, z, wall) } }
                k += 1
            }
            for z in z0...(z0 + 4) where inner(x0 + 2, hi + 1, z) { hb.set(x0 + 2, hi + 1, z, wall) }     // a rail at the top
            // Coming up into an open space (the hangar, the bridge): a stairhead round the top, roofed, with a pair of
            // doors where the last flight arrives, so the decks below stay sealed.
            if head {
                let flights = (hi - lo) / 5
                let aftLast = (flights - 1) % 2 == 0
                let zDoor = aftLast ? z0 + 6 : z0 - 2, zBack = aftLast ? z0 - 2 : z0 + 6
                let lane = aftLast ? x0 : x0 + 3
                for y in (hi + 1)...(hi + 3) {
                    for z in (z0 - 2)...(z0 + 6) { hb.set(x0 - 1, y, z, wall); hb.set(x0 + 5, y, z, wall) }
                    for x in x0...(x0 + 4) { hb.set(x, y, zBack, wall); if y == hi + 3 || (x != lane && x != lane + 1) { hb.set(x, y, zDoor, wall) } }
                }
                for x in (x0 - 1)...(x0 + 5) { for z in (z0 - 2)...(z0 + 6) { hb.set(x, hi + 4, z, wall) } }
                for x in [lane, lane + 1] {
                    hb.set(x, hi + 1, zDoor, door + (aftLast ? 1 : 0)); hb.set(x, hi + 2, zDoor, door + (aftLast ? 9 : 8))
                    for z in [zDoor - 1, zDoor + 1] where hb.get(x, hi, z) == AIR { hb.set(x, hi, z, deck) }
                }
            }
            k = 0
            for f in stride(from: lo, through: hi, by: 5) {
                for z in [z0 - 1, z0 + 5] { for x in x0...(x0 + 4) { hb.set(x, f, z, deck) } }
                let arriving = f > lo ? (k - 1) % 2 : -1          // 0: the aft-climbing lane came up to it
                for lane in 0..<2 where lane != arriving {
                    for x in (x0 + lane * 3)...(x0 + lane * 3 + 1) { for z in z0...(z0 + 4) where hb.get(x, f, z) == AIR { hb.set(x, f, z, deck) } }
                }
                k += 1
            }
        }
        stairs(8, 92, from: 11, to: 81)            // the bow, from the lowest deck to the top
        stairs(-2, 200, from: 11, to: 26, head: true)    // the keel up into the hangar floor
        stairs(-14, 351, from: 21, to: 66)         // aft of the hangar up through the decks
        stairs(5, 324, from: 46, to: 76, head: true)     // the upper decks into the bridge
    }
}
