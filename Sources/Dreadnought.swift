import Foundation
import simd

// The Sunken Dreadnought (was the Sea Temple, a copy of the ocean monument and its elder guardians): a Capital
// battleship that went down in deep water in the first war.
// P349 (Oct 16 19:59-20:01: "couldn't find it at the locate coordinates", "too small and too simple", "the inside isn't
// realistic: decks, corridors, turrets with their machinery, engine rooms, bridge"):
//   size       131 blocks stem to stern, 23 in the beam, keel on the sea floor 26 down: a ship of the line, not a hut.
//   found      a red wreck buoy with a lamp rides the surface over her bow on its chain, her tripod mast and funnels
//              reach up to a few blocks under the waves, and the locate point is her bridge, so the coordinates lead
//              straight to her.
//   decks      a double bottom, a lower deck, a middle deck and the planked main deck; watertight bulkheads with doors
//              on the centre line; on the middle deck a narrow corridor between rooms on both sides (crew messes with
//              bunks, a galley, a sick bay, the wardroom, the armoury, the radio room, the captain's cabin with the pay
//              chest); companionways with ladders between decks.
//   machinery  the boiler rooms (rows of boilers, uptakes into the funnels), the engine room two decks high (four
//              turbines, condensers, a catwalk over them), shaft alleys aft to four screws; under each turret its shell
//              room and magazine with hoists up the barbette into the gunhouse and its three breeches.
//   topsides   four triple turrets (two forward, two aft, the inner ones superfiring), casemate secondary guns along
//              both sides, the forward superstructure (chart house, the bridge with its helm and windows, the director
//              tower on a tripod mast), two funnels, the aft control tower and mainmast.
//   wrecked    a torpedo hole torn in her starboard side by the engine room, the after funnel fallen across the deck,
//              everything below flooded; a few lamps still burn; drowned crew keep her and a field of mines rides
//              moored round her.
enum SunkenDreadnought {
    static let name = "Sunken Dreadnought"
    static let half = 65                            // half length (x); bow at +x
    static let beam = 11                            // half beam (z)

    // Half-width of the hull at dx from amidships: a long fine bow, a round stern.
    static func hw(_ dx: Int) -> Int {
        if dx > 38 { return max(1, beam - (dx - 38) * 10 / 27) }
        if dx < -50 { return max(5, beam - (-50 - dx) * 6 / 15) }
        return beam
    }

    // The locate point (the bridge) for a start at (cx, cz) with its keel at y0.
    static func anchor(_ cx: Int, _ y0: Int, _ cz: Int) -> IVec3 { IVec3(cx + 14, y0 + 16, cz) }

    static func build(_ w: inout StructWriter, _ cx: Int, _ y0: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed ^ 0xD4_ED)
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let hull = g("ship_metal", g("iron_block")), plank = g("dark_oak_planks"), steel = g("steel_plating", hull), iron = g("iron_block")
        let lamp = g("sea_lantern"), gold = g("gold_block"), bars = g("iron_bars"), chain = g("chain", bars)
        let pane = g("glass_pane", bars), copper = g("copper_block", iron), cutCopper = g("cut_copper", copper)
        let boiler = g("blast_furnace", g("furnace")), furnace = g("furnace"), smoker = g("smoker", furnace)
        let ladder = g("ladder", chain), fence = g("oak_fence", bars), slab = g("spruce_slab", plank), wool = g("white_wool"), red = g("red_wool")
        let barrel = g("barrel", plank), coal = g("coal_block", iron), helm = g("ship_helm", plank), table = g("spruce_planks", plank)
        let yLow = y0 + 2, yMid = y0 + 6, yMain = y0 + 10        // deck floors: lower, middle, main (planked)
        func X(_ dx: Int) -> Int { cx + dx }
        func Z(_ dz: Int) -> Int { cz + dz }
        func fill(_ dx0: Int, _ y0: Int, _ dz0: Int, _ dx1: Int, _ y1: Int, _ dz1: Int, _ b: BlockID) {
            w.fill(X(min(dx0, dx1)), min(y0, y1), Z(min(dz0, dz1)), X(max(dx0, dx1)), max(y0, y1), Z(max(dz0, dz1)), b)
        }
        func set(_ dx: Int, _ y: Int, _ dz: Int, _ b: BlockID) { w.set(X(dx), y, Z(dz), b) }

        // The hull: keel to main deck, the double bottom, the decks, everything inside flooded.
        for dx in -half...half {
            let h = hw(dx)
            for dz in -h...h {
                let edge = abs(dz) == h
                let bilge = abs(dz) >= h - 1 ? 1 : 0                     // the turn of the bilge
                w.groundDown(X(dx), y0 - 1, Z(dz), hull, minY: y0 - 14)
                for y in (y0 + bilge)...yMain { set(dx, y, dz, hull) }
                if bilge == 1 { set(dx, y0, dz, WATER) }
                if edge || abs(dx) == half { continue }
                set(dx, y0 + 1, dz, steel)                               // inner bottom
                for y in (yLow)..<yMain where y != yMid { set(dx, y, dz, WATER) }
                set(dx, yMid, dz, steel)
                set(dx, yMain, dz, plank)
            }
            // Bulwark along the deck edge forward, a rail aft.
            if dx > 40 { set(dx, yMain + 1, -h, hull); set(dx, yMain + 1, h, hull) }
            else if abs(dx) < half { set(dx, yMain + 1, -h, fence); set(dx, yMain + 1, h, fence) }
        }
        // The stem rises to the forecastle head; the screws and rudder under the stern.
        for y in yMain...(yMain + 2) { set(half, y, 0, hull) }
        for dz in [-6, -2, 2, 6] {
            for dx in (-half + 6)...(-half + 14) { set(dx, y0 + 1, dz, iron) }                // shaft brackets
            set(-half + 4, y0 + 1, dz, iron)
            for (bx, by) in [(0, 1), (0, -1), (1, 0), (-1, 0)] { w.set(X(-half + 4), y0 + 1 + by, Z(dz + bx), copper) }   // screw
        }
        fill(-half - 1, y0, 0, -half - 1, y0 + 5, 0, steel)                                   // rudder

        // Watertight bulkheads with a door on the centre line of each deck (and the side passages).
        let bulkheads = [-54, -44, -34, -10, 6, 20, 32, 44, 54]
        for bx in bulkheads {
            let h = hw(bx) - 1
            fill(bx, yLow, -h, bx, yMid - 1, h, steel)
            fill(bx, yMid + 1, -h, bx, yMain - 1, h, steel)
            for y in [yLow, yMid + 1] { fill(bx, y, 0, bx, y + 1, 0, WATER) }
        }

        // MIDDLE DECK: a narrow corridor (z -1...1) walled off from the rooms on both sides, a door into each room.
        let rooms: [(Int, Int, String)] = [(-54, -44, "captain"), (-44, -34, "wardroom"), (-10, 6, "mess"), (6, 20, "mess2"),
                                            (20, 32, "galley"), (32, 44, "sickbay"), (44, 54, "stores")]
        for (x0, x1, _) in rooms {
            for dx in (x0 + 1)...(x1 - 1) { for s in [-2, 2] { fill(dx, yMid + 1, s, dx, yMain - 1, s, steel) } }
            for s in [-2, 2] { let d = (x0 + x1) / 2; fill(d, yMid + 1, s, d, yMid + 2, s, WATER) }
            set((x0 + x1) / 2, yMain - 1, 0, lamp)
        }
        func room(_ x0: Int, _ x1: Int, _ kind: String, side s: Int) {
            let zIn = 3 * s, zOut = (hw(x0 + 1) - 2) * s, y = yMid + 1
            func line(_ b: BlockID, _ dz: Int, _ yy: Int = y) { for dx in (x0 + 2)...(x1 - 2) where dx != (x0 + x1) / 2 { set(dx, yy, dz, b) } }
            switch kind {
            case "captain":
                fill(x0 + 2, y, zOut, x0 + 3, y, zOut, wool)                                   // his bunk
                set(x1 - 3, y, zOut, table); set(x1 - 4, y, zOut, table)                         // the desk
                if s > 0 { w.chest(X(x0 + 5), y, Z(zOut), loot: "shipwreck_treasure", seed: rng.next(), facing: 0) }
                else { w.chest(X(x0 + 5), y, Z(zOut), loot: "shipwreck_map", seed: rng.next(), facing: 0) }
            case "wardroom":
                line(table, (zIn + zOut) / 2); line(fence, (zIn + zOut) / 2 + s); line(fence, (zIn + zOut) / 2 - s)
            case "mess", "mess2":
                line(slab, zOut); line(slab, zOut, y + 2)                                      // two tiers of bunks
                for dx in stride(from: x0 + 3, to: x1 - 1, by: 3) { set(dx, y + 1, zOut, fence) }
                line(table, zIn + s)
            case "galley":
                line(s > 0 ? furnace : smoker, zOut); line(barrel, zIn + s)
                if s < 0 { w.chest(X(x0 + 3), y, Z(zIn + s), loot: "shipwreck_supply", seed: rng.next(), facing: 0) }
            case "sickbay":
                for dx in stride(from: x0 + 2, to: x1 - 1, by: 2) { set(dx, y, zOut, wool) }
            default:
                line(barrel, zOut); line(barrel, zOut, y + 1)
                if s > 0 { w.chest(X(x0 + 3), y, Z(zIn + s), loot: "steelhold_armory", seed: rng.next(), facing: 0) }
            }
            set((x0 + x1) / 2, yMain - 1, zOut, lamp)
        }
        for (x0, x1, k) in rooms { room(x0, x1, k, side: -1); room(x0, x1, k, side: 1) }
        // The radio room by the bridge's foot: consoles along the wall.
        for dx in 8...12 { set(dx, yMid + 1, -beam + 2, g("command_console", iron)) }

        // LOWER DECK: the boiler rooms (-10...20) and the engine room (-34...-10, two decks high), shaft alleys aft.
        fill(-33, yMid, -beam + 1, -11, yMid, beam - 1, WATER)                                 // engine room open to the deck above
        fill(-33, yMid, -1, -11, yMid, 1, steel)                                                // ...its catwalk
        for dx in -33...(-11) { set(dx, yMid + 1, -2, bars); set(dx, yMid + 1, 2, bars) }
        for tz in [-7, -3, 3, 7] {
            fill(-31, yLow, tz - 1, -14, yLow + 2, tz + 1, iron)                                 // turbine casing
            fill(-30, yLow + 3, tz, -15, yLow + 3, tz, copper)                                   // steam pipe
            set(-13, yLow + 1, tz, cutCopper)                                                    // gearing
        }
        for dz in [-9, 9] { fill(-31, yLow, dz, -14, yLow + 1, dz, copper) }                      // condensers
        set(-22, yMain - 1, -5, lamp); set(-22, yMain - 1, 5, lamp)
        for dx in stride(from: -8, through: 18, by: 3) where !bulkheads.contains(dx) {
            for dz in [-7, -4, 4, 7] { fill(dx, yLow, dz, dx + 1, yLow + 3, dz, boiler) }
        }
        set(-2, yMain - 1, 0, lamp); set(13, yMain - 1, 0, lamp)
        for dz in [-6, -2, 2, 6] { for dx in (-half + 15)...(-35) { set(dx, yLow, dz, iron) } }   // the shafts
        // Coal bunkers along the sides of the boiler rooms.
        for dx in -9...19 { for dz in [-beam + 1, beam - 1] where hw(dx) == beam { fill(dx, yLow, dz, dx, yLow + 2, dz, coal) } }

        // Companionways: hatches in the main deck and middle deck with ladders down.
        for hx in [-48, -38, 2, 26, 48] {
            set(hx, yMain, 1, WATER); set(hx, yMid, 1, WATER)
            for y in yLow..<yMain { set(hx, y, 2, ladder) }
            set(hx, yMain + 1, 2, fence)
        }

        // TURRETS: barbette from the lower deck, its shell room and magazine below, hoist, the gunhouse and three guns.
        func turret(_ tx: Int, dir: Int, raise: Int) {
            let top = yMain + 1 + raise
            for dz in -4...4 { for dx in -4...4 where dx * dx + dz * dz <= 18 {
                let rim = dx * dx + dz * dz > 9
                if rim { fill(tx + dx, yLow, dz, tx + dx, top, dz, steel) }
                else { fill(tx + dx, yLow, dz, tx + dx, top - 1, dz, WATER) }
            } }
            for dx in -1...1 { for dz in [-2, 2] { fill(tx + dx, yLow, dz, tx + dx, yLow + 1, dz, iron) } }   // shell racks
            set(tx - 2, yLow, 0, coal); set(tx + 2, yLow, 0, coal)                                             // powder bags
            fill(tx, yLow, 0, tx, top, 0, chain)                                                              // the hoist
            set(tx, yMid, 0, chain)
            fill(tx - 1, yLow, 0, tx - 1, top - 1, 0, ladder)
            for d in [-4, 4] { for y in [yLow, yMid + 1] { fill(tx + d, y, 0, tx + d, y + 1, 0, WATER) } }       // the passage through
            // Gunhouse: armoured box, sloped face, a rangefinder's arms; open to the barbette below.
            let gx0 = tx - 4 * dir, gx1 = tx + 4 * dir
            fill(gx0, top, -4, gx1, top + 3, 4, iron)
            fill(tx - 3, top + 1, -3, tx + 3, top + 2, 3, WATER)
            fill(tx + 4 * dir, top + 3, -4, tx + 4 * dir, top + 3, 4, WATER)                                   // the slope
            fill(tx - 2, top, -2, tx + 2, top, 2, WATER)
            for dz in [-5, 5] { set(tx - 2 * dir, top + 3, dz, bars) }
            for gz in [-2, 0, 2] {
                set(tx + 2 * dir, top + 1, gz, iron)                                                           // breech
                for k in 5...(5 + 13) { set(tx + k * dir, top + 2, gz, steel) }                                 // barrel
            }
        }
        turret(52, dir: 1, raise: 0)
        turret(40, dir: 1, raise: 3)
        turret(-40, dir: -1, raise: 3)
        turret(-52, dir: -1, raise: 0)

        // Casemate secondaries along both sides, in the middle deck's shell.
        for dx in [-28, -18, 0, 12, 26] { for s in [-1, 1] {
            let e = hw(dx) * s
            set(dx, yMid + 2, e, WATER)
            for k in 1...4 { set(dx, yMid + 2, e + k * s, steel) }
            set(dx, yMid + 2, e - s, iron)
        } }

        // FORWARD SUPERSTRUCTURE: chart house, the bridge (helm, windows), the director on a tripod mast.
        fill(8, yMain + 1, -6, 20, yMain + 4, 6, steel)
        fill(9, yMain + 1, -5, 19, yMain + 3, 5, WATER)
        fill(10, yMain + 5, -5, 19, yMain + 7, 5, steel)
        fill(11, yMain + 5, -4, 18, yMain + 6, 4, WATER)
        for dz in -4...4 { set(19, yMain + 6, dz, pane) }
        for dx in 11...18 { set(dx, yMain + 6, -5, pane); set(dx, yMain + 6, 5, pane) }
        set(17, yMain + 5, 0, helm); set(15, yMain + 5, -3, table); set(15, yMain + 5, 3, table)
        fill(14, yMain + 1, 6, 14, yMain + 2, 6, WATER)                                            // its door
        for y in (yMain + 1)...(yMain + 4) { set(13, y, 5, ladder) }
        set(13, yMain + 4, 4, WATER)
        set(14, yMain + 7, 0, lamp)
        for (mx, mz) in [(12, 0), (16, -2), (16, 2)] { fill(mx, yMain + 8, mz, mx, yMain + 11, mz, chain) }   // tripod
        fill(13, yMain + 12, -2, 16, yMain + 13, 2, steel)                                        // director top
        fill(14, yMain + 14, 0, 14, SEA - 2, 0, chain)                                            // topmast

        // FUNNELS (the after one fallen across the deck) and the aft control tower with its mainmast.
        func funnel(_ fx: Int, height: Int) {
            fill(fx - 1, yMain + 1, -2, fx + 1, yMain + height, 2, hull)
            fill(fx, yMain + 1, -1, fx, yMain + height, 1, WATER)
            fill(fx - 1, yMain + height, -2, fx + 1, yMain + height, -2, coal)
        }
        funnel(1, height: 11)
        fill(-8, yMain + 1, -2, -6, yMain + 2, 2, hull)                                             // the stump
        fill(-7, yMain + 1, -1, -7, yMain + 2, 1, WATER)
        fill(-8, yMain + 1, 3, -6, yMain + 2, 13, hull)                                          // lying over the side
        fill(-7, yMain + 1, 4, -7, yMain + 2, 13, WATER)
        fill(-26, yMain + 1, -4, -18, yMain + 4, 4, steel)
        fill(-25, yMain + 1, -3, -19, yMain + 3, 3, WATER)
        fill(-24, yMain + 2, 4, -23, yMain + 2, 4, WATER)
        for dz in -3...3 { set(-26, yMain + 3, dz, pane) }
        fill(-22, yMain + 5, 0, -22, min(SEA - 3, yMain + 18), 0, chain)                          // mainmast

        // THE WOUND: a torpedo hole in the starboard side by the engine room, the plates torn inward.
        for dx in -26...(-19) { for y in (y0 + 1)...(yMid + 1) {
            let r = Float(dx + 22) * Float(dx + 22) / 16 + Float(y - y0 - 4) * Float(y - y0 - 4) / 9
            if r < 1 { set(dx, y, beam, WATER); if rng.chance(0.4) { set(dx, y, beam - 1, WATER) } }
            else if r < 1.4 && rng.chance(0.5) { set(dx, y, beam - 1, hull) }
        } }

        // The pay chest and the strongroom of arms in the after magazine (below X turret), behind bars.
        let mx = -46
        fill(mx - 2, yLow, -6, mx + 2, yLow, -6, gold)
        fill(mx - 3, yLow, -5, mx + 3, yLow + 2, -5, bars)
        set(mx, yLow, -5, WATER); set(mx, yLow + 1, -5, WATER)
        w.chest(X(mx - 1), yLow, Z(-7), loot: "shipwreck_treasure", seed: rng.next(), facing: 0)
        w.chest(X(mx + 1), yLow, Z(-7), loot: "steelhold_armory", seed: rng.next(), facing: 0)

        // The wreck buoy over her bow: a red float with a lamp, on its chain down to the forecastle.
        let bz = beam + 3
        set(46, SEA - 1, bz, red); set(46, SEA, bz, lamp)
        fill(46, y0, bz, 46, SEA - 2, bz, chain)

        // A minefield moored round the hulk (C8, Submarines.swift): horned mines on chains off both sides.
        if Blocks.has(Submarine.mineKey) {
            let dry = Blocks.id(Submarine.mineKey), wet = Blocks.wet[Int(dry)]
            let mine = wet != AIR ? wet : dry                                  // in the water, not a dry cell in it
            for k in 0..<12 {
                let dx = -55 + k * 10, dz = (beam + 6) * (k & 1 == 0 ? -1 : 1)
                let y = min(SEA - 3, y0 + 9 + Int(rng.float() * 8))
                set(dx, y, dz, mine)
                w.groundDown(X(dx), y - 1, Z(dz), chain, minY: y0 - 12)
            }
        }
        // The drowned crew: in the messes, the engine and boiler rooms, the turrets, on the bridge.
        let posts: [(Int, Int, Int)] = [(-50, yMid + 1, 4), (0, yMid + 1, -5), (12, yMid + 1, 5), (26, yMid + 1, -4), (38, yMid + 1, 5),
                                        (-22, yLow, 0), (-28, yMid + 1, 0), (2, yLow, 0), (14, yLow, 2), (40, yLow, 0), (-40, yLow, 3),
                                        (15, yMain + 5, 0), (-22, yMain + 1, 0)]
        for (dx, y, dz) in posts { w.mob("drowned", V3(Float(X(dx)) + 0.5, Float(y), Float(Z(dz)) + 0.5)) }
    }
}
