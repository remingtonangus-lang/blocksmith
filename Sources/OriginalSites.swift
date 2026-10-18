import Foundation
import simd

// G20 (the Oct 11 content audit, docs/status/ip-content-audit-oct11.md): original designs in place of structures that
// copied one reference feature whole. Each keeps its old structure key (saves, maps and the locate list find it) and
// is built only on ground no save generated with the old design (WorldRules.savedBeforeP44).

// The Sealed Armoury (was the Proving Halls, a copy of the trial chambers): a Capital armoury from before the war, sealed
// underground (y -40 to -20) when the garrison above was lost, and the dead garrison still walks it. One long
// cast-concrete gallery with bulkhead doors off it: a firing range with targets, a magazine of crates, a barracks of
// bunks and lockers, and the vault, an iron cage of gun racks. Tunnels at both ends of the gallery meet the caves.
enum SealedArmoury {
    static let name = "Sealed Armoury"

    static func build(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed ^ 0xA2_40)
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let wall = g("bunker_concrete", g("smooth_stone")), steel = g("steel_plating", g("iron_block")), lamp = g("light_panel", g("sea_lantern"))
        let bars = g("iron_bars"), door = g("bulkhead_door", g("iron_door")), barrel = g("barrel"), hay = g("hay_block"), target = g("target", hay)
        let wool = g("white_wool"), slab = g("smooth_stone_slab", wall)
        // The shell, and the gallery along x (seven wide, six tall), its floor banded with steel.
        w.fill(cx - 30, y - 1, cz - 14, cx + 30, y + 7, cz + 14, wall)
        w.fill(cx - 27, y, cz - 3, cx + 27, y + 5, cz + 3, AIR)
        for x in stride(from: cx - 27, through: cx + 27, by: 4) { w.fill(x, y - 1, cz - 3, x, y - 1, cz + 3, steel) }
        for x in stride(from: cx - 24, through: cx + 24, by: 6) { w.set(x, y + 6, cz, lamp) }
        for x in stride(from: cx - 27, through: cx + 27, by: 9) { for z in [cz - 3, cz + 3] { w.fill(x, y, z, x, y + 5, z, steel) } }   // ribs
        // Both ends run out into the rock (three wide, three tall) so caves find it.
        for sx in [-1, 1] { w.fill(cx + sx * 28, y, cz - 1, cx + sx * 31, y + 2, cz + 1, AIR) }

        // A room off the gallery (x0...x1 along it, the north (-1) or south (+1) side), with its bulkhead door at dx.
        func room(_ x0: Int, _ x1: Int, side: Int, door dx: Int) -> (Int, Int) {
            let z0 = side < 0 ? cz - 13 : cz + 5, z1 = side < 0 ? cz - 5 : cz + 13
            w.fill(x0, y, z0, x1, y + 4, z1, AIR)
            w.set(dx, y, cz + side * 4, door); w.set(dx, y + 1, cz + side * 4, door + 8)
            w.set(dx, y + 3, cz + side * 4, lamp)
            w.set((x0 + x1) / 2, y + 5, (z0 + z1) / 2, lamp)
            return (z0, z1)
        }
        // The firing range: a counter across the room, hay-backed targets at the far wall.
        let (rz0, _) = room(cx - 22, cx + 8, side: -1, door: cx - 7)
        for x in (cx - 21)...(cx + 7) where (x - cx) % 6 != 1 { w.set(x, y, rz0 + 6, slab) }
        for x in stride(from: cx - 20, through: cx + 6, by: 6) { w.set(x, y, rz0, hay); w.set(x, y + 1, rz0, target) }
        w.spawner(cx - 7, y, rz0 + 2, mob: "skeleton")
        // The magazine: crates and supply chests.
        let (mz0, mz1) = room(cx + 13, cx + 25, side: -1, door: cx + 19)
        for x in (cx + 14)...(cx + 24) where (x - cx) % 3 != 1 { for z in [mz0, mz0 + 1] { w.set(x, y, z, barrel); if rng.chance(0.5) { w.set(x, y + 1, z, barrel) } } }
        w.chest(cx + 16, y, mz1, loot: "steelhold_supply", seed: rng.next(), facing: 2)
        w.chest(cx + 22, y, mz1, loot: "steelhold_supply", seed: rng.next(), facing: 2)
        // The barracks: rows of bunks (a wool mattress on a slab frame) with a locker at each head.
        let (bz0, bz1) = room(cx - 25, cx - 3, side: 1, door: cx - 14)
        for x in stride(from: cx - 24, through: cx - 4, by: 3) where abs(x - (cx - 14)) > 1 {
            for (z, dz) in [(bz1, -1), (bz0, 1)] {
                w.set(x, y, z, barrel)
                w.set(x, y, z + dz, wool); w.set(x, y, z + 2 * dz, wool)
            }
        }
        if rng.chance(0.6) { w.chest(cx - 4, y, bz0 + 1, loot: "steelhold_supply", seed: rng.next(), facing: 0) }
        w.spawner(cx - 14, y, bz0 + 2, mob: "zombie")
        // The vault: an iron cage of gun racks behind a second door.
        let (vz0, vz1) = room(cx + 6, cx + 25, side: 1, door: cx + 15)
        let gx0 = cx + 10, gx1 = cx + 21, gz0 = vz0 + 3, gz1 = vz1 - 1
        for x in gx0...gx1 { for z in gz0...gz1 where x == gx0 || x == gx1 || z == gz0 || z == gz1 { w.fill(x, y, z, x, y + 3, z, bars) } }
        w.set(cx + 15, y, gz0, door); w.set(cx + 15, y + 1, gz0, door + 8)
        w.fill(gx0 + 1, y - 1, gz0 + 1, gx1 - 1, y - 1, gz1 - 1, steel)
        w.chest(gx0 + 2, y, gz1 - 1, loot: "steelhold_armory", seed: rng.next(), facing: 2)
        w.chest(gx1 - 2, y, gz1 - 1, loot: "steelhold_armory", seed: rng.next(), facing: 2)
        if rng.chance(0.5) { w.chest(cx + 15, y, gz1 - 1, loot: "steelhold_command", seed: rng.next(), facing: 2) }
        w.spawner(cx + 8, y, vz0 + 1, mob: "zombie")
        // The dead garrison in the gallery.
        for x in [cx - 18, cx + 18] { w.spawner(x, y, cz + (x < cx ? -2 : 2), mob: rng.chance(0.5) ? "zombie" : "skeleton") }
    }
}

// The Brigand Roost (was the Forest Manor, a copy of the woodland mansion): a gang's stockade deep in the dark forest.
// A ring of sharpened log palisade with a gate on the north side and a walk round its inside; within it a long log hall
// (a table and benches below, bunks in the loft, the gang's strongbox at the back), a lookout tower on four posts, a
// corral with the gang's horses and a fire pit. Brigands guard the gate and the hall, Marauders the tower.
enum BrigandRoost {
    static let name = "Brigand Roost"
    static let r = 21                    // the palisade's half width

    static func build(_ w: inout StructWriter, _ cx: Int, _ y: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed ^ 0xB2_16)
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let log = g("dark_oak_log"), spruce = g("spruce_log", log), pl = g("spruce_planks"), dpl = g("dark_oak_planks", pl)
        let slab = g("spruce_slab", pl), fence = g("spruce_fence", g("oak_fence")), dirt = g("coarse_dirt", DIRT), path = g("dirt_path", dirt)
        let lantern = g("lantern"), barrel = g("barrel"), hay = g("hay_block"), wool = g("red_wool"), fire = g("campfire", g("netherrack"))
        let ladder = g("ladder"), cob = COBBLE
        // The plot: cleared to the sky, levelled with packed dirt over a cobble footing.
        for z in (cz - r - 1)...(cz + r + 1) { for x in (cx - r - 1)...(cx + r + 1) { w.groundDown(x, y - 2, z, cob, minY: y - 8) } }
        w.fill(cx - r - 1, y, cz - r - 1, cx + r + 1, y + 20, cz + r + 1, AIR)
        w.fill(cx - r - 1, y - 1, cz - r - 1, cx + r + 1, y - 1, cz + r + 1, dirt)
        // The palisade: logs 5 high, every other one a block taller (the sharpened tips), a plank walk inside at y + 3.
        for k in -r...r {
            for (x, z) in [(cx + k, cz - r), (cx + k, cz + r), (cx - r, cz + k), (cx + r, cz + k)] {
                let h = 5 + ((k & 1) == 0 ? 1 : 0)
                w.fill(x, y, z, x, y + h - 1, z, spruce)
            }
            for (x, z) in [(cx + k, cz - r + 1), (cx + k, cz + r - 1), (cx - r + 1, cz + k), (cx + r - 1, cz + k)] where abs(k) < r { w.set(x, y + 3, z, slab) }
        }
        // The gate (north): a three-wide gap under a log lintel, a path in to the hall; ladders up to the walk.
        w.fill(cx - 1, y, cz - r, cx + 1, y + 3, cz - r + 1, AIR)
        w.fill(cx - 2, y + 4, cz - r, cx + 2, y + 4, cz - r, log)
        for z in (cz - r)...(cz - 6) { for x in (cx - 1)...(cx + 1) { w.set(x, y - 1, z, path) } }
        for x in [cx - 3, cx + 3] { w.fill(x, y, cz - r + 1, x, y + 3, cz - r + 1, ladder + 1) }
        // The hall: 17 x 11 of dark log posts and plank walls, a loft at y + 5, a gable roof of slabs.
        let hx0 = cx - 8, hx1 = cx + 8, hz0 = cz - 5, hz1 = cz + 5
        w.fill(hx0, y, hz0, hx1, y + 8, hz1, dpl)
        w.fill(hx0 + 1, y, hz0 + 1, hx1 - 1, y + 7, hz1 - 1, AIR)
        for x in stride(from: hx0, through: hx1, by: 4) { for z in [hz0, hz1] { w.fill(x, y, z, x, y + 8, z, log) } }
        for z in [hz0, hz1] { for x in [hx0, hx1] { w.fill(x, y, z, x, y + 8, z, log) } }
        for x in stride(from: hx0 + 2, through: hx1 - 2, by: 4) { for z in [hz0, hz1] { w.set(x, y + 2, z, g("glass_pane", AIR)) } }
        w.fill(hx0 + 1, y + 5, hz0 + 1, hx1 - 1, y + 5, hz1 - 1, pl)                       // the loft floor
        w.fill(hx0 + 1, y + 5, hz0 + 1, hx0 + 3, y + 5, hz1 - 1, AIR)                       // its hatch at the west end
        for yy in 0..<5 { w.set(hx0 + 1, y + yy, hz1 - 1, ladder) }                         // (on the south wall)
        for k in 0...6 {                                                                      // the roof
            let zz0 = hz0 - 1 + k, zz1 = hz1 + 1 - k
            guard zz0 <= zz1 else { break }
            for x in (hx0 - 1)...(hx1 + 1) { w.set(x, y + 9 + k / 2, zz0, (k & 1) == 0 ? slab : dpl); w.set(x, y + 9 + k / 2, zz1, (k & 1) == 0 ? slab : dpl) }
        }
        w.fill(cx - 1, y, hz0, cx, y + 2, hz0, AIR)                                           // the door gap
        // Below: a long table and benches, barrels, lanterns; up in the loft: bunks; at the back: the strongbox.
        for x in (cx - 5)...(cx + 4) { w.set(x, y, cz, fence); w.set(x, y + 1, cz, dpl) }
        for x in (cx - 5)...(cx + 4) { w.set(x, y, cz - 2, slab); w.set(x, y, cz + 2, slab) }
        for x in [hx0 + 1, hx1 - 1] { for z in [hz0 + 1, hz1 - 1] { w.set(x, y + 4, z, lantern) } }
        for z in (hz0 + 1)...(hz1 - 1) where z != cz { w.set(hx1 - 1, y, z, barrel) }
        for x in stride(from: hx0 + 5, through: hx1 - 2, by: 3) { for z in [hz0 + 1, hz1 - 1] { w.set(x, y + 6, z, wool); w.set(x + 1, y + 6, z, wool) } }
        w.chest(hx1 - 2, y, cz, loot: "mansion", seed: rng.next(), facing: 3)
        w.chest(hx1 - 2, y + 6, cz, loot: "camp_outlaws", seed: rng.next(), facing: 3)
        // The lookout: four posts, a railed platform at y + 9, a ladder up one post.
        let tx = cx - 13, tz = cz + 12
        for (dx, dz) in [(-2, -2), (2, -2), (-2, 2), (2, 2)] { w.fill(tx + dx, y, tz + dz, tx + dx, y + 11, tz + dz, log) }
        w.fill(tx - 2, y + 9, tz - 2, tx + 2, y + 9, tz + 2, pl)
        for k in -2...2 { for (x, z) in [(tx + k, tz - 2), (tx + k, tz + 2), (tx - 2, tz + k), (tx + 2, tz + k)] { w.set(x, y + 10, z, fence) } }
        w.fill(tx - 2, y + 12, tz - 2, tx + 2, y + 12, tz + 2, slab)
        for yy in 0...9 { w.set(tx - 1, y + yy, tz - 2, ladder + 3) }                       // up the north-west post
        w.set(tx - 1, y + 10, tz - 2, AIR)                                                    // (a gap in the rail at its top)
        // The corral (east) with the gang's horses, and the fire pit by the gate.
        let kx = cx + 13, kz = cz + 11
        for k in -5...5 { for (x, z) in [(kx + k, kz - 5), (kx + k, kz + 5), (kx - 5, kz + k), (kx + 5, kz + k)] { w.set(x, y, z, fence) } }
        w.set(kx - 5, y, kz, AIR)
        w.set(kx + 3, y, kz + 3, hay); w.set(kx + 3, y + 1, kz + 3, hay)
        for k in 0..<2 { w.mob("horse", V3(Float(kx - 1 + k * 2) + 0.5, Float(y), Float(kz) + 0.5)) }
        w.set(cx + 6, y - 1, cz - 13, cob); w.set(cx + 6, y, cz - 13, fire)
        for (dx, dz) in [(-2, 0), (2, 0), (0, 2)] { w.set(cx + 6 + dx, y, cz - 13 + dz, g("spruce_log[x]", spruce)) }
        // The gang.
        func mob(_ k: String, _ x: Int, _ yy: Int, _ z: Int) { w.mob(k, V3(Float(x) + 0.5, Float(y + yy), Float(z) + 0.5)) }
        mob("vindicator", cx - 3, 0, cz - r + 3); mob("vindicator", cx + 3, 0, cz - r + 3)
        mob("vindicator", cx - 3, 0, cz - 3); mob("vindicator", cx + 5, 0, cz + 3)
        mob("pillager", tx, 10, tz); mob("pillager", cx + 6, 0, cz - 11)
        if rng.chance(0.5) { mob("pillager", cx - r + 2, 4, cz) }
    }
}

// The Sunken Dreadnought (was the Sea Temple, a copy of the ocean monument and its elder guardians): a Capital
// battleship that went down in deep water in the first war. It lies on the sea floor broken in two, the bow and stern
// apart, with its turrets, funnels and bridge still on deck. Drowned crewmen keep it; its magazine, deep in the stern,
// still holds the pay chest (gold) and a strongroom of arms.
enum SunkenDreadnought {
    static let name = "Sunken Dreadnought"

    static func build(_ w: inout StructWriter, _ cx: Int, _ y0: Int, _ cz: Int, _ seed: UInt64) {
        var rng = SRng(seed ^ 0xD4_ED)
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let hull = g("ship_metal", g("iron_block")), deck = g("dark_oak_planks"), steel = g("steel_plating", hull), iron = g("iron_block")
        let lamp = g("sea_lantern"), gold = g("gold_block"), bars = g("iron_bars"), chain = g("chain", bars)
        let beam = 6                                   // half beam
        // The hull along x in two halves (bow x > 0, stern x < 0) with a torn gap between, each a hollow shell flooded
        // inside, its keel sunk into the sea floor (pillars down to it).
        let halves = [(cx - 30, cx - 3, 0), (cx + 3, cx + 30, 2)]       // (x0, x1, how far the bow half has settled)
        for (x0, x1, sink) in halves {
            let yb = y0 - sink
            for x in x0...x1 {
                // Taper toward the ends: the beam narrows over the last eight blocks of bow and stern.
                let end = min(x - (cx - 30), (cx + 30) - x)
                let hw = end < 8 ? max(2, beam - (8 - end) / 2) : beam
                for z in (cz - hw)...(cz + hw) { w.groundDown(x, yb - 1, z, hull, minY: yb - 12) }
                w.fill(x, yb, cz - hw, x, yb + 7, cz + hw, hull)
                w.fill(x, yb + 1, cz - hw + 1, x, yb + 6, cz + hw - 1, WATER)
                w.fill(x, yb + 7, cz - hw + 1, x, yb + 7, cz + hw - 1, deck)
                if x % 6 == 0 { w.fill(x, yb + 1, cz - hw + 1, x, yb + 6, cz + hw - 1, steel); w.fill(x, yb + 1, cz - 1, x, yb + 3, cz + 1, WATER) }   // bulkheads, a passage through
            }
            // The torn ends: ragged holes into the flooded decks.
            let tear = x0 == cx + 3 ? x0 : x1
            for z in (cz - beam + 1)...(cz + beam - 1) where rng.chance(0.75) { w.fill(tear, yb + 1, z, tear, yb + 7, z, WATER) }
        }
        // Scuttle holes along the sides so divers find a way in.
        for x in stride(from: cx - 24, through: cx + 24, by: 12) where abs(x - cx) > 4 { for z in [cz - beam, cz + beam] { w.fill(x, y0 + 2, z, x + 1, y0 + 3, z, WATER) } }
        // On deck: two gun turrets (forward and aft) with twin barrels, two funnels amidships, the bridge.
        func turret(_ tx: Int, _ dir: Int, _ yb: Int) {
            w.fill(tx - 2, yb + 8, cz - 2, tx + 2, yb + 10, cz + 2, iron)
            w.fill(tx - 1, yb + 8, cz - 1, tx + 1, yb + 9, cz + 1, WATER)
            for z in [cz - 1, cz + 1] { for k in 3...8 { w.set(tx + dir * k, yb + 9, z, steel) } }
        }
        turret(cx + 20, 1, y0 - 2); turret(cx + 12, 1, y0 - 2); turret(cx - 20, -1, y0)
        for fx in [cx - 6, cx - 11] { w.fill(fx, y0 + 8, cz - 1, fx + 2, y0 + 15, cz + 1, hull); w.fill(fx + 1, y0 + 8, cz, fx + 1, y0 + 15, cz, WATER) }
        let bx = cx + 6
        w.fill(bx - 2, y0 + 6, cz - 3, bx + 2, y0 + 12, cz + 3, hull)
        w.fill(bx - 1, y0 + 6, cz - 2, bx + 1, y0 + 11, cz + 2, WATER)
        for z in (cz - 2)...(cz + 2) { w.set(bx + 2, y0 + 10, z, bars) }                          // the bridge windows
        w.fill(bx, y0 + 13, cz, bx, y0 + 18, cz, chain)                                            // the mast stump
        // The magazine in the stern: the pay chest and a strongroom of arms behind bars, a little light left burning.
        let mx = cx - 16
        w.fill(mx - 3, y0 + 1, cz - 3, mx + 3, y0 + 1, cz + 3, steel)
        w.fill(mx - 1, y0 + 2, cz - 1, mx, y0 + 2, cz, gold)
        for z in (cz - 3)...(cz + 3) { w.set(mx + 3, y0 + 2, z, bars); w.set(mx + 3, y0 + 3, z, bars) }
        w.set(mx + 3, y0 + 2, cz, WATER); w.set(mx + 3, y0 + 3, cz, WATER)
        w.chest(mx - 2, y0 + 2, cz + 2, loot: "shipwreck_treasure", seed: rng.next(), facing: 0)
        w.chest(mx + 1, y0 + 2, cz + 2, loot: "steelhold_armory", seed: rng.next(), facing: 0)
        w.set(mx, y0 + 6, cz, lamp); w.set(cx + 18, y0 + 4, cz, lamp)
        // A minefield moored round the hulk (C8, Submarines.swift): horned mines on chains off both sides.
        if Blocks.has(Submarine.mineKey) {
            let dry = Blocks.id(Submarine.mineKey), wet = Blocks.wet[Int(dry)]
            let mine = wet != AIR ? wet : dry                                  // in the water, not a dry cell in it
            for k in 0..<8 {
                let x = cx - 28 + k * 8, z = cz + (k & 1 == 0 ? -8 : 8)
                let y = min(SEA - 3, y0 + 9 + Int(rng.float() * 6))
                w.set(x, y, z, mine)
                w.groundDown(x, y - 1, z, chain, minY: y0 - 12)
            }
        }
        // The drowned crew, through the decks and on the bridge.
        for k in 0..<6 {
            let x = cx + [-24, -12, -4, 9, 18, 25][k]
            w.mob("drowned", V3(Float(x) + 0.5, Float(y0 + 2), Float(cz + (k & 1 == 0 ? -2 : 2)) + 0.5))
        }
        w.mob("drowned", V3(Float(bx) + 0.5, Float(y0 + 7), Float(cz) + 0.5))
    }
}

// Ground a save generated before G20 in the Emberdeep, the Deep and on the surface (World.init loads them): structures there keep
// their old design so no half-built one is left at the edge of explored land.
enum G20Guard {
    static var overworld: Set<Int64> = []        // structure-guard-g20-overworld.txt
    static var nether: Set<Int64> = []
    static var deep: Set<Int64> = []
    static func legacy(_ set: Set<Int64>, _ cx: Int, _ cz: Int, reach: Int) -> Bool {
        guard !set.isEmpty else { return false }
        for dz in -reach...reach { for dx in -reach...reach where set.contains(StructureCache.key(cx + dx, cz + dz)) { return true } }
        return false
    }
}

// The Ash Foundry (was the Cinder Fortress, a copy of the nether fortress): the Ashguard's works in hell, where the army
// below mines the ember country for its forges. The same network of cells as the old fortress (Fortress.layout), built
// as the Reich builds: open steel gantries on riveted girder legs where the bridges were (plate decks, bar railings,
// lamps hung on chains), brick furnace halls where the castle was (a steel floor, iron-barred vents, a smelter in the
// middle of each hall), cinderwisps penned in barred furnace cages on the gantries' ends (their fire runs the works), and
// ember-wart tanks in brick troughs. Loot: the old fortress tables.
enum AshFoundry {
    static let name = "Ash Foundry"

    static func build(_ w: inout StructWriter, _ n: Fortress.Node, cx: Int, cz: Int, y: Int, seed: UInt64, base: Int) {
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let plate = g("steel_plating", g("iron_block")), girder = g("polished_blackstone", g("blackstone")), rail = g("iron_bars")
        let brick = g("bricks"), trim = g("polished_blackstone_bricks", brick), chain = g("chain", rail), lamp = g("lantern[hanging]", g("lantern"))
        let magma = g("magma_block"), soul = g("soul_sand"), wart = g("nether_wart")
        let half = Fortress.cell / 2
        func plan(_ hw: Int, room: Int) -> [(Int, Int, Int, Int)] {
            var out = [(cx - room, cz - room, cx + room, cz + room)]
            for d in 0..<4 where n.links[d] {
                let (dx, dz) = Fortress.dirs[d]
                if dx != 0 { out.append(dx > 0 ? (cx, cz - hw, cx + half, cz + hw) : (cx - half + 1, cz - hw, cx, cz + hw)) }
                else { out.append(dz > 0 ? (cx - hw, cz, cx + hw, cz + half) : (cx - hw, cz - half + 1, cx + hw, cz)) }
            }
            return out
        }
        func isIn(_ x: Int, _ z: Int, _ rs: [(Int, Int, Int, Int)]) -> Bool { rs.contains { x >= $0.0 && x <= $0.2 && z >= $0.1 && z <= $0.3 } }
        var rng = SRng(seed)
        switch n.kind {
        case .bridge, .blaze:
            // A gantry: a plate deck one thick on a girder frame, bar railings, a lamp on a chain over each crossing.
            let room = n.kind == .blaze ? 4 : 2
            let deck = plan(2, room: room)
            for r in deck {
                w.fill(r.0, y, r.1, r.2, y, r.3, plate)
                w.fill(r.0, y - 1, r.1, r.2, y - 1, r.3, AIR)
                w.fill(r.0, y + 1, r.1, r.2, y + 5, r.3, AIR)
            }
            for z in (cz - half)...(cz + half) { for x in (cx - half)...(cx + half) where isIn(x, z, deck) {
                let edge = !isIn(x + 1, z, deck) || !isIn(x - 1, z, deck) || !isIn(x, z + 1, deck) || !isIn(x, z - 1, deck)
                let atCellEdge = abs(x - cx) >= half || (x - cx) == -(half - 1) || abs(z - cz) >= half || (z - cz) == -(half - 1)
                if edge && !atCellEdge { w.set(x, y + 1, z, rail) }
                if edge { w.set(x, y - 1, z, girder) }                        // the side girders under the deck edges
            } }
            // Girder legs under the crossing corners (to the ground), knee braces under the arms.
            for (px, pz) in [(cx - room, cz - room), (cx + room, cz - room), (cx - room, cz + room), (cx + room, cz + room)] {
                w.pillarDown(px, y - 2, pz, girder, minY: base)
            }
            for d in 0..<4 where n.links[d] {
                let (dx, dz) = Fortress.dirs[d]
                for s in [-2, 2] { w.set(cx + dx * 3 + (dz != 0 ? s : 0), y - 2, cz + dz * 3 + (dx != 0 ? s : 0), trim) }
            }
            w.fill(cx, y + 4, cz, cx, y + 5, cz, chain); w.set(cx, y + 3, cz, lamp)
            if n.kind == .blaze {
                // A furnace cage: a magma hearth, bars all round, a brick flue above; the cinderwisp inside.
                w.fill(cx - 1, y + 1, cz - 1, cx + 1, y + 1, cz + 1, magma)
                for dz in -2...2 { for dx in -2...2 where max(abs(dx), abs(dz)) == 2 { w.fill(cx + dx, y + 1, cz + dz, cx + dx, y + 4, cz + dz, rail) } }
                w.fill(cx - 2, y + 5, cz - 2, cx + 2, y + 5, cz + 2, brick)
                w.fill(cx - 1, y + 6, cz - 1, cx + 1, y + 8, cz + 1, brick)
                w.set(cx, y + 6, cz, AIR); w.set(cx, y + 7, cz, AIR); w.set(cx, y + 8, cz, AIR)
                w.set(cx, y + 3, cz, AIR); w.set(cx, y + 4, cz, AIR)
                for (dx, dz) in [(0, -2), (0, 2), (-2, 0), (2, 0)] { w.set(cx + dx, y + 1, cz + dz, AIR); w.set(cx + dx, y + 2, cz + dz, AIR) }   // gaps to fight through
                w.spawner(cx, y + 2, cz, mob: "blaze")
            }
        case .castle, .wart:
            // A furnace hall: brick walls with polished quoins, a steel floor, barred vents high up, a flat roof.
            let room = n.kind == .wart ? 4 : 2
            let outer = plan(3, room: room + 1), inner = plan(2, room: room)
            let h = n.kind == .wart ? 7 : 5
            for r in outer { w.fill(r.0, y - 1, r.1, r.2, y + h + 1, r.3, brick) }
            for r in inner { w.fill(r.0, y + 1, r.1, r.2, y + h, r.3, AIR); w.fill(r.0, y, r.1, r.2, y, r.3, plate) }
            for z in (cz - half)...(cz + half) { for x in (cx - half)...(cx + half) where isIn(x, z, outer) && !isIn(x, z, inner) {
                let nearOpen = isIn(x + 1, z, inner) || isIn(x - 1, z, inner) || isIn(x, z + 1, inner) || isIn(x, z - 1, inner)
                if nearOpen && (x + z) % 3 == 0 && abs(x - cx) < half && abs(z - cz) < half && abs(x - cx) + abs(z - cz) > 2 {
                    w.set(x, y + h - 1, z, rail)
                }
                w.set(x, y + h + 1, z, trim)                                  // a dark coping on the walls
            } }
            for (px, pz) in [(cx - room - 1, cz - room - 1), (cx + room + 1, cz - room - 1), (cx - room - 1, cz + room + 1), (cx + room + 1, cz + room + 1)] {
                w.fill(px, y, pz, px, y + h, pz, trim)
                w.pillarDown(px, y - 2, pz, girder, minY: base)
            }
            if n.kind == .wart {
                // Ember-wart tanks: soul sand in brick troughs either side, a walkway between.
                for side in [-1, 1] {
                    let bz = cz + side * 3
                    for x in (cx - 3)...(cx + 3) { w.set(x, y + 1, bz, soul); w.set(x, y + 2, bz, wart + BlockID(rng.int(4))) }
                    w.fill(cx - 4, y + 1, bz + side, cx + 4, y + 2, bz + side, brick)
                    w.set(cx - 4, y + 1, bz, brick); w.set(cx + 4, y + 1, bz, brick)
                }
                w.set(cx, y + h - 1, cz, lamp)
            } else {
                // The smelter: a blast furnace on a brick plinth in the hall's middle, a chest in a corner now and then.
                // P342 (c) ("structures full of blast furnaces with no purpose"): each is the works' own smelter, still
                // working the ember country's ore: raw gold or iron in it, the ingots it has run off waiting to be taken.
                if n.links.filter({ $0 }).count <= 2 {
                    let gold = rng.chance(0.5)
                    w.furnace(cx, y + 1, cz, kind: "blast_furnace", input: ItemStack(Items.id(gold ? "raw_gold" : "raw_iron"), 1 + rng.int(4)),
                              output: ItemStack(Items.id(gold ? "gold_ingot" : "iron_ingot"), 1 + rng.int(3)))
                }
                w.set(cx + 1, y + h, cz, lamp)
                if rng.chance(0.2) { w.chest(cx - room, y + 1, cz - room, loot: "fortress", seed: rng.next(), facing: rng.int(4)) }
            }
        }
    }
}

// The Boarling Mound (was the Boarling Keep, a copy of the bastion remnant's four layouts): the boarlings' own home, a
// stepped mound of onyxstone they have heaped over their hoard. A ring of domed huts round its foot, a pen of tuskers,
// stairs up the south face to two terraces, a pillared hall inside the first terrace and the hoard vault inside the
// second, its gold piled on the floor; braziers on the summit. The old bastion loot and garrison.
enum BoarlingMound {
    static let name = "Boarling Mound"
    static let half = 22

    static func build(_ w: inout StructWriter, ox: Int, oz: Int, y: Int, seed: UInt64) {
        var rng = SRng(seed ^ 0xB0A2)
        func g(_ k: String, _ alt: BlockID = STONE) -> BlockID { Blocks.has(k) ? Blocks.id(k) : alt }
        let polished = g("polished_blackstone"), bricks = g("polished_blackstone_bricks"), gold = g("gold_block")
        let crimson = g("crimson_planks", bricks), cslab = g("crimson_slab", crimson), soulL = g("soul_lantern"), magma = g("magma_block")
        let wall = g("blackstone_wall", bricks), chain = g("chain")
        let hw = [20, 14, 8]
        func mob(_ k: String, _ x: Int, _ yy: Int, _ z: Int) { w.mob(k, V3(Float(x) + 0.5, Float(yy), Float(z) + 0.5)) }
        // The yard: an onyxstone floor at y on pillars, clear above.
        w.fill(ox - hw[0], y + 1, oz - hw[0], ox + hw[0], y + 28, oz + hw[0], AIR)
        for z in (oz - hw[0])...(oz + hw[0]) { for x in (ox - hw[0])...(ox + hw[0]) { w.set(x, y, z, Bastion.mat(x, y, z)) } }
        Bastion.supports(&w, ox - hw[0], oz - hw[0], ox + hw[0], oz + hw[0], y)
        // The two terraces: solid onyxstone heaped over the floor, a polished lip round each top.
        for t in 1...2 {
            let r = hw[t], top = y + 5 * t
            for yy in (y + 5 * (t - 1) + 1)...top { for z in (oz - r)...(oz + r) { for x in (ox - r)...(ox + r) { w.set(x, yy, z, Bastion.mat(x, yy, z)) } } }
            for k in -r...r { for (x, z) in [(ox + k, oz - r), (ox + k, oz + r), (ox - r, oz + k), (ox + r, oz + k)] { w.set(x, top, z, polished) } }
        }
        // The hall in the first terrace (east and west doors, pillars), the vault in the second (north door).
        w.fill(ox - 12, y + 1, oz - 12, ox + 12, y + 4, oz + 12, AIR)
        for x in stride(from: ox - 8, through: ox + 8, by: 8) { for z in stride(from: oz - 8, through: oz + 8, by: 8) where x != ox || z != oz { w.fill(x, y + 1, z, x, y + 4, z, bricks) } }
        for sx in [-1, 1] { w.fill(ox + sx * 13, y + 1, oz - 1, ox + sx * 14, y + 3, oz + 1, AIR) }
        for x in stride(from: ox - 10, through: ox + 10, by: 5) { w.set(x, y + 4, oz - 11, soulL); w.set(x, y + 4, oz + 11, soulL) }
        w.fill(ox - 6, y + 6, oz - 6, ox + 6, y + 9, oz + 6, AIR)
        w.fill(ox - 1, y + 6, oz - 8, ox + 1, y + 8, oz - 7, AIR)
        for dz in -1...1 { for dx in -1...1 where abs(dx) + abs(dz) <= 1 { w.set(ox + dx, y + 6, oz + 2 + dz, gold) } }
        w.set(ox, y + 7, oz + 2, gold)
        w.chest(ox - 4, y + 6, oz + 4, loot: "bastion", seed: rng.next(), facing: 1)
        w.chest(ox + 4, y + 6, oz + 4, loot: "bastion", seed: rng.next(), facing: 1)
        w.set(ox, y + 9, oz, soulL)
        // Stairs up the south face to each terrace.
        Bastion.stairsUp(&w, x: ox - 1, z: oz + hw[1] + 5, from: y, to: y + 5, dirZ: -1)
        Bastion.stairsUp(&w, x: ox - 1, z: oz + hw[2] + 5, from: y + 5, to: y + 10, dirZ: -1)
        // The summit: braziers at the corners, a chained post in the middle.
        for (dx, dz) in [(-6, -6), (6, -6), (-6, 6), (6, 6)] { w.set(ox + dx, y + 11, oz + dz, magma) }
        w.fill(ox, y + 11, oz, ox, y + 13, oz, wall); w.set(ox, y + 14, oz, soulL)
        for (dx, dz) in [(1, 0), (-1, 0)] { w.set(ox + dx, y + 13, oz + dz, chain) }
        // Huts round the foot: domed onyxstone with crimson roofs, each with a chest and a boarling.
        let spots = [(-17, -17), (0, -17), (17, -17), (-17, 0), (17, 0), (-17, 17), (17, 17)].filter { _ in rng.chance(0.8) }
        for (i, (dx, dz)) in spots.enumerated() {
            let hx = ox + dx, hz = oz + dz
            w.fill(hx - 2, y + 1, hz - 2, hx + 2, y + 3, hz + 2, bricks)
            w.fill(hx - 1, y + 1, hz - 1, hx + 1, y + 3, hz + 1, AIR)
            w.fill(hx - 2, y + 4, hz - 2, hx + 2, y + 4, hz + 2, cslab)
            w.fill(hx - 1, y + 4, hz - 1, hx + 1, y + 4, hz + 1, crimson)
            w.set(hx, y + 5, hz, cslab)
            // The door faces the mound.
            let (ddx, ddz) = abs(dx) >= abs(dz) ? (dx > 0 ? -2 : 2, 0) : (0, dz > 0 ? -2 : 2)
            w.fill(hx + ddx, y + 1, hz + ddz, hx + ddx, y + 2, hz + ddz, AIR)
            w.chest(hx - ddx / 2 + (ddz != 0 ? 1 : 0), y + 1, hz - ddz / 2 + (ddx != 0 ? 1 : 0), loot: "bastion", seed: rng.next(), facing: i % 4)
            mob("piglin", hx, y + 1, hz)
        }
        // The tusker pen on the west side of the yard.
        let px = ox - 17, pz = oz + 8
        for k in -2...2 { for (x, z) in [(px + k, pz - 2), (px + k, pz + 2), (px - 2, pz + k), (px + 2, pz + k)] where !(x == px + 2 && z == pz) { w.set(x, y + 1, z, wall) } }
        for k in 0..<2 { mob("hoglin", px - 1 + 2 * k, y + 1, pz) }
        // The garrison: boarlings in the hall, brutes at the hoard and on the summit.
        mob("piglin", ox - 5, y + 1, oz); mob("piglin", ox + 5, y + 1, oz)
        mob("piglin_brute", ox, y + 6, oz - 3); mob("piglin_brute", ox + 3, y + 11, oz - 3)
    }
}
