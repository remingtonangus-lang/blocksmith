import Foundation
import simd

// P512 (Remington, Nov 2 12:17, relayed Nov 3: "make 10 of its own guns from the in-game blocks", and see "the world with
// the 100 vehicles and 100 copper machines... Put it somewhere so I can access it in the game"): the Proving Grounds, a
// creative world picked from the Worlds menu beside the Sparkstone Workshop. The first time it loads, the game builds a
// stone deck high over its spawn and lays out on it, a few steps a tick (so the frame keeps going while it builds):
//   the vehicle park   the vehicle zoo's hundred builds (VehicleZoo.plan), one row a family (cars, trucks, odd builds,
//                      tanks, boats and gunboats afloat in channels, airships, planes, helicopters, hybrids), each standing
//                      as blocks with its helm, a sign in front of it: use the helm and drive, sail or fly it;
//   the circuit field  the circuit zoo's hundred copper circuits (CircuitZoo.cases), each built on its own pad and run
//                      through its own test once, so it stands as the test left it, levers and buttons ready to use;
//   the gun range      ten guns built from the game's own blocks the way a player builds one (a Turret Ring, a cannon or
//                      rows of calibre barrels, a Command Console on its plank pad: Game.builtGunUse), facing a field of
//                      targets to the north.
// Nothing here is text in play but the signs. ProvingGroundsCheck (questcheck --proving) builds it and checks it.
enum ProvingGrounds {
    static let worldName = "Proving Grounds"
    static let seed: UInt64 = 0x5052_4F56_494E          // a fixed seed: the deck stands over the same land every time
    static let deckY = 300                              // internal y of the deck's walking level (well over any land)
    static let markerBlock = "calcite"                  // laid last at the start corner: the grounds are built

    static let familyNames: [VehicleZoo.Family: String] = [.car: "Car", .truck: "Truck", .odd: "Odd Build", .tank: "Tank",
        .boat: "Boat", .gunboat: "Gunboat", .airship: "Airship", .plane: "Plane", .heli: "Helicopter", .hybrid: "Hybrid"]

    // MARK: Layout (x east, z south, relative to the origin at deck level; the deck's blocks are at y -1)

    struct Plot { let index: Int; let at: IVec3; let lo: IVec3; let size: IVec3; let water: Bool }

    // Each vehicle's plot: rows by family, ten across, a walkway and the signs to the north of each row.
    static let park: (plots: [Plot], width: Int, depth: Int, rows: [(z: Int, water: Bool, x1: Int, z0: Int, z1: Int)]) = {
        var plots: [Plot] = [], rows: [(Int, Bool, Int, Int, Int)] = []
        var z = 2, width = 0
        for f in 0..<VehicleZoo.Family.allCases.count {
            let fam = VehicleZoo.Family.allCases[f]
            let water = fam == .boat || fam == .gunboat
            var x = 4, deep = 0
            let zp = z + 5
            for k in 0..<10 {
                let i = f + 10 * k
                let p = VehicleZoo.plan(i)
                let lo = p.cells.reduce(IVec3(99, 99, 99)) { IVec3(min($0.x, $1.0.x), min($0.y, $1.0.y), min($0.z, $1.0.z)) }
                let hi = p.cells.reduce(IVec3(-99, -99, -99)) { IVec3(max($0.x, $1.0.x), max($0.y, $1.0.y), max($0.z, $1.0.z)) }
                let size = hi - lo + IVec3(1, 1, 1)
                plots.append(Plot(index: i, at: IVec3(x, water ? -1 : 0, zp), lo: lo, size: size, water: water))
                x += size.x + 5
                deep = max(deep, size.z)
            }
            rows.append((z, water, x, zp, zp + deep - 1))
            width = max(width, x)
            z = zp + deep + 3
        }
        return (plots, width, z, rows)
    }()

    static let padGap = 32
    static var fieldX: Int { park.width + 24 }                   // the circuit field's first pad centre
    static let fieldZ = 18
    static func pad(_ i: Int) -> IVec3 { IVec3(fieldX + (i % 10) * padGap, 0, fieldZ + (i / 10) * padGap) }

    static let gunZ = -14, gunGap = 16, targetZ = -78
    static func gunAt(_ k: Int) -> IVec3 { IVec3(8 + k * gunGap, 0, gunZ) }

    // The deck's extent (x0...x1, z0...z1).
    static var deck: (x0: Int, x1: Int, z0: Int, z1: Int) {
        (-4, fieldX + 9 * padGap + padGap / 2, targetZ - 10, max(park.depth, fieldZ + 9 * padGap + padGap / 2))
    }

    // Where he stands at first: the walkway between the gun range and the park, looking south down the park.
    static func start(_ o: IVec3) -> V3 { V3(Float(o.x) + 2.5, Float(o.y), Float(o.z) - 1.5) }
    static func marker(_ o: IVec3) -> IVec3 { IVec3(o.x - 2, o.y - 1, o.z - 2) }

    // MARK: The ten guns (ring at the origin at deck level; barrels run north, -z, the way BuiltGunCheck builds his)

    struct GunDesign { let name: String; let lines: [String]; let build: (_ put: (Int, Int, Int, String) -> Void) -> Void }

    static let guns: [GunDesign] = [
        GunDesign(name: "Field Gun", lines: ["Field Gun", "a cannon", "on a ring"]) { put in
            put(0, 0, 0, "ship_turret_ring"); put(0, 1, 0, "ship_cannon[south]")
        },
        GunDesign(name: "Long Gun", lines: ["Long Gun", "six medium", "barrels"]) { put in
            put(0, 0, 0, "ship_turret_ring"); for k in 0..<6 { put(0, 1, -k, "gun_barrel_medium[south]") }
        },
        GunDesign(name: "Twin Light", lines: ["Twin Light", "two rows of", "small barrels"]) { put in
            put(0, 0, 0, "ship_turret_ring")
            for k in 0..<4 { put(0, 1, -k, "gun_barrel_small[south]"); put(1, 1, -k, "gun_barrel_small[south]") }
        },
        GunDesign(name: "Heavy Gun", lines: ["Heavy Gun", "eight large", "barrels"]) { put in
            put(0, 0, 0, "ship_turret_ring"); for k in 0..<8 { put(0, 1, -k, "gun_barrel_large[south]") }
        },
        GunDesign(name: "Triple Mount", lines: ["Triple Mount", "three cannons", "with long tubes"]) { put in
            // (a Gun Barrel lengthens the cannon it runs on from: each row starts at its cannon)
            put(0, 0, 0, "ship_turret_ring")
            for x in -1...1 { put(x, 1, 0, "ship_cannon[south]"); for k in 1..<4 { put(x, 1, -k, "ship_gun_barrel[south]") } }
        },
        GunDesign(name: "Tower Gun", lines: ["Tower Gun", "a ring on a", "plank tower"]) { put in
            for y in 0..<4 { put(0, y, 0, "oak_planks") }
            put(0, 4, 0, "ship_turret_ring"); for k in 0..<5 { put(0, 5, -k, "gun_barrel_medium[south]") }
        },
        GunDesign(name: "Braked Gun", lines: ["Braked Gun", "medium barrels", "a large muzzle"]) { put in
            put(0, 0, 0, "ship_turret_ring")
            for k in 0..<5 { put(0, 1, -k, "gun_barrel_medium[south]") }
            put(0, 1, -5, "gun_barrel_large[south]")
        },
        GunDesign(name: "Casemate", lines: ["Casemate", "a shielded", "cannon"]) { put in
            put(0, 0, 0, "ship_turret_ring"); put(0, 1, 0, "ship_cannon[south]")
            for k in 1...3 { put(0, 1, -k, "gun_barrel_medium[south]") }
            for (x, y, z) in [(-1, 1, 0), (1, 1, 0), (-1, 2, 0), (0, 2, 0), (1, 2, 0), (-1, 1, 1), (1, 1, 1), (0, 2, 1)] {
                put(x, y, z, "iron_block")
            }
        },
        GunDesign(name: "Quad Mount", lines: ["Quad Mount", "four small", "barrels"]) { put in
            put(0, 0, 0, "ship_turret_ring")
            for y in 1...2 { for x in 0...1 { for k in 0..<3 { put(x, y, -k, "gun_barrel_small[south]") } } }
        },
        GunDesign(name: "Long Rifle", lines: ["Long Rifle", "ten small", "barrels"]) { put in
            put(0, 0, 0, "ship_turret_ring"); for k in 0..<10 { put(0, 1, -k, "gun_barrel_small[south]") }
        },
    ]

    // MARK: Building, a step at a time

    final class Build {
        let o: IVec3
        var steps: [(Game) -> Void] = []
        var needs: [(V3, Int)?] = []          // the chunks each step works in (a centre, a radius in chunks)
        var next = 0
        var circuitsOK = 0
        var waited = 0
        init(_ o: IVec3) { self.o = o }
        var done: Bool { next >= steps.count }
        func add(_ at: V3?, _ r: Int, _ f: @escaping (Game) -> Void) { steps.append(f); needs.append(at.map { ($0, r) }) }
        // Runs steps for up to `budget` seconds (at least one). With `stream`, a step whose chunks aren't made yet waits
        // for the world's workers to make them (World.extraCenter streams round it, as round a second player) instead
        // of making them on the frame; after 30 s of waiting it makes them itself.
        func run(_ g: Game, budget: Double, stream: Bool = false) {
            let t0 = CFAbsoluteTimeGetCurrent()
            let w = g.world
            repeat {
                guard next < steps.count else { if stream && !g.coop.active { w.extraCenter = nil }; return }
                if stream && !g.coop.active, let (c, r) = needs[next] {
                    let cx = floorDiv(Int(floor(c.x)), CS), cz = floorDiv(Int(floor(c.z)), CS)
                    var ready = true
                    for dz in -r...r { for dx in -r...r where ready && w.chunks[ChunkKey(x: cx + dx, z: cz + dz)] == nil { ready = false } }
                    if !ready && waited < 600 {
                        w.extraCenter = c
                        waited += 1
                        return
                    }
                }
                waited = 0
                steps[next](g)
                next += 1
            } while CFAbsoluteTimeGetCurrent() - t0 < budget
        }
    }

    static func key(_ n: String, _ f: String = "stone") -> BlockID { Blocks.has(n) ? Blocks.id(n) : Blocks.id(f) }

    static func put(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
        if w.rawBlock(x, y, z) != b { _ = w.setBlockAsync(x, y, z, b) }
    }

    static func sign(_ w: World, _ p: IVec3, facingSouth: Bool, _ lines: [String]) {
        guard Blocks.has("oak_sign") else { return }
        put(w, p.x, p.y, p.z, Blocks.id("oak_sign") + (facingSouth ? 1 : 0))      // a standing sign
        let be = BlockEntity(.sign)
        be.lines = (lines + ["", "", "", ""]).prefix(4).map { ShopMenu.fit($0, 88) }
        w.blockEntities[p] = be
    }

    // Splits a name into sign lines of at most 15 letters by words.
    static func wrap(_ s: String, lines n: Int) -> [String] {
        var out: [String] = [], cur = ""
        for word in s.split(separator: " ") {
            let wd = String(word)
            if cur.isEmpty { cur = wd } else if cur.count + 1 + wd.count <= 15 { cur += " " + wd } else { out.append(cur); cur = wd }
            if out.count == n { break }
        }
        if !cur.isEmpty && out.count < n { out.append(cur) }
        return out
    }

    // Every step that builds the grounds at `o` (the deck's walking level at the start corner).
    static func plan(_ o: IVec3) -> Build {
        let b = Build(o)
        let d = deck
        let stone = STONE, walk = key("andesite"), water = WATER
        // The deck, a 32-block tile a step (each loaded first: the far tiles are past what streams in round him).
        for tz in stride(from: d.z0, through: d.z1, by: 32) { for tx in stride(from: d.x0, through: d.x1, by: 32) {
            let at = V3(Float(o.x + tx + 16), Float(o.y), Float(o.z + tz + 16))
            b.add(at, 1) { g in
                let w = g.world
                _ = w.loadSync(center: at, radius: 1)
                for z in tz..<min(tz + 32, d.z1 + 1) { for x in tx..<min(tx + 32, d.x1 + 1) {
                    put(w, o.x + x, o.y - 1, o.z + z, stone)
                    for y in o.y..<(o.y + 12) where w.rawBlock(o.x + x, y, o.z + z) != AIR { _ = w.setBlockAsync(o.x + x, y, o.z + z, AIR) }
                } }
            }
        } }
        // Over a rectangle (relative x0...x1, z0...z1), a 32-block tile a step, each tile's chunks made first.
        func tiles(_ x0: Int, _ x1: Int, _ z0: Int, _ z1: Int, _ body: @escaping (World, Int, Int) -> Void) {
            for tz in stride(from: z0, through: z1, by: 32) { for tx in stride(from: x0, through: x1, by: 32) {
                let at = V3(Float(o.x + tx + 16), Float(o.y), Float(o.z + tz + 16))
                b.add(at, 1) { g in
                    let w = g.world
                    _ = w.loadSync(center: at, radius: 1)
                    for z in thru(tz, min(tz + 31, z1)) { for x in thru(tx, min(tx + 31, x1)) { body(w, o.x + x, o.z + z) } }
                }
            } }
        }
        // Walkways: north of each vehicle row, along the gun range and round the circuit field.
        for r in park.rows { tiles(0, r.x1 - 1, r.z, r.z + 2) { w, x, z in put(w, x, o.y - 1, z, walk) } }
        tiles(0, gunAt(guns.count - 1).x + 8, gunZ + 7, gunZ + 9) { w, x, z in put(w, x, o.y - 1, z, walk) }
        tiles(0, fieldX + 9 * padGap - 1, -3, -1) { w, x, z in put(w, x, o.y - 1, z, walk) }
        // The water rows' channels: eight deep, walled, under the whole row.
        for r in park.rows where r.water {
            let x0 = 1, x1 = r.x1, z0 = r.z0 - 2, z1 = r.z1 + 2
            tiles(x0, x1, z0, z1) { w, x, z in
                let edge = x == o.x + x0 || x == o.x + x1 || z == o.z + z0 || z == o.z + z1
                put(w, x, o.y - 9, z, stone)
                for y in (o.y - 8)...(o.y - 1) { put(w, x, y, z, edge ? stone : water) }
            }
        }
        // The hundred vehicles, as blocks, each with a sign before it.
        for pl in park.plots {
            let base = o + pl.at
            let at = V3(Float(base.x + pl.size.x / 2), Float(o.y), Float(base.z + pl.size.z / 2))
            b.add(at, 1) { g in
                let w = g.world
                let p = VehicleZoo.plan(pl.index)
                _ = w.loadSync(center: at, radius: 1)
                // Clear the plot of anything built before (a reload mid-build, or one he moved off), water rows to water.
                for y in base.y...(base.y + pl.size.y + 2) { for z in (base.z - 1)...(base.z + pl.size.z) { for x in (base.x - 1)...(base.x + pl.size.x) {
                    let want = pl.water && y <= o.y - 1 ? water : AIR
                    put(w, x, y, z, want)
                } } }
                let shift = base - pl.lo
                for (c, blk) in p.cells { _ = w.setBlockAsync(c.x + shift.x, c.y + shift.y, c.z + shift.z, blk) }
                var lines = [String(format: "Vehicle %03d", pl.index + 1), familyNames[p.family] ?? p.family.rawValue]
                lines.append(p.drives ? (p.guns > 0 ? "\(p.guns) gun\(p.guns == 1 ? "" : "s")" : "") : "no drive")
                sign(w, IVec3(base.x + pl.size.x / 2, o.y, base.z - 2), facingSouth: false, lines)
            }
        }
        // The ten guns, each on its plank pad with its computer, a sign on the walkway side; and the targets.
        for (k, gd) in guns.enumerated() {
            let c = o + gunAt(k)
            b.add(V3(Float(c.x), Float(o.y), Float(c.z)), 1) { g in
                let w = g.world
                _ = w.loadSync(center: V3(Float(c.x), Float(o.y), Float(c.z)), radius: 1)
                for y in o.y...(o.y + 7) { for z in (c.z - 11)...(c.z + 3) { for x in (c.x - 2)...(c.x + 2) { put(w, x, y, z, AIR) } } }
                for z in -2...2 { for x in -2...2 { put(w, c.x + x, o.y - 1, c.z + z, key("oak_planks", "stone")) } }
                gd.build { x, y, z, n in put(w, c.x + x, o.y + y, c.z + z, key(n)) }
                put(w, c.x + 2, o.y, c.z + 2, key("command_console"))
                sign(w, IVec3(c.x, o.y, c.z + 5), facingSouth: true, gd.lines)
            }
        }
        b.add(V3(Float(o.x + 70), Float(o.y), Float(o.z + targetZ)), 3) { g in
            let w = g.world
            let iron = key("iron_block"), bricks = key("stone_bricks"), plank = key("spruce_planks")
            for k in 0..<5 {
                let x0 = 6 + k * 32, z = targetZ
                _ = w.loadSync(center: V3(Float(o.x + x0 + 4), Float(o.y), Float(o.z + z)), radius: 1)
                let mat = [bricks, iron, plank, bricks, iron][k]
                for x in 0..<9 { for y in 0..<(5 + k % 3) { for dz in 0..<2 { put(w, o.x + x0 + x, o.y + y, o.z + z + dz, mat) } } }
            }
        }
        // The hundred circuits, one pad a step, each run through its test and left standing.
        let cases = CircuitZoo.cases()
        for i in 0..<min(100, cases.count) {
            let c = o + pad(i)
            b.add(V3(Float(c.x), Float(o.y), Float(c.z)), 2) { g in
                let w = g.world
                _ = w.loadSync(center: V3(Float(c.x), Float(o.y), Float(c.z)), radius: 2)
                let h = padGap / 2 - 1
                for z in (c.z - h)...(c.z + h) { for x in (c.x - h)...(c.x + h) {
                    for y in o.y...(o.y + 10) where w.rawBlock(x, y, z) != AIR {
                        w.blockEntities[IVec3(x, y, z)] = nil
                        _ = w.setBlockAsync(x, y, z, AIR)
                    }
                    put(w, x, o.y - 1, z, stone)
                } }
                let zb = CircuitZoo.Z(g, c, i)
                let r = cases[i].run(zb)
                if r.0 { b.circuitsOK += 1 }
                // Its sign by the pad's north-west corner, clear of the build.
                // (where the build took that cell, the open cell nearest it along the pad's north edge, then anywhere)
                let want = IVec3(max(c.x - h + 1, min(zb.lo.x, c.x)), o.y, max(c.z - h + 1, min(zb.lo.z, c.z) - 2))
                func free(_ q: IVec3) -> Bool { w.rawBlock(q.x, q.y, q.z) == AIR && w.rawBlock(q.x, q.y + 1, q.z) == AIR }
                var at: IVec3? = free(want) ? want : nil
                for r in 1...h where at == nil {
                    for q in [IVec3(want.x + r, o.y, want.z), IVec3(want.x - r, o.y, want.z), IVec3(want.x, o.y, want.z - r),
                              IVec3(want.x, o.y, want.z + r)] where abs(q.x - c.x) < h && abs(q.z - c.z) < h && free(q) { at = q; break }
                }
                if let at {
                    sign(w, at, facingSouth: false, [String(format: "Circuit %03d", i + 1)] + wrap(cases[i].family + ": " + cases[i].name, lines: 3))
                }
            }
        }
        // Done: the marker at the start corner.
        b.add(nil, 0) { g in put(g.world, marker(o).x, marker(o).y, marker(o).z, key(markerBlock)) }
        return b
    }

    // The deck's origin in this world: over the world's first spawn.
    static func origin(spawn: V3) -> IVec3 { IVec3(Int(floorf(spawn.x)) - 4, deckY, Int(floorf(spawn.z)) + 6) }

    static func built(_ w: World, _ o: IVec3) -> Bool {
        let m = marker(o)
        return w.block(m.x, m.y, m.z) == key(markerBlock)
    }
}

extension Game {
    // In the Proving Grounds world: on its first tick in the overworld, start building the grounds if they aren't there
    // yet and stand him at the start; then a few steps every tick until it's done.
    func provingTick() {
        if let b = provingBuild {
            b.run(self, budget: 0.006, stream: true)
            if b.done {
                provingBuild = nil
                onToast?("Proving Grounds")
            }
            return
        }
        guard !provingChecked else { return }
        guard save?.dir.lastPathComponent == ProvingGrounds.worldName else { provingChecked = true; return }
        guard dim.dim == .overworld else { return }
        provingChecked = true
        world.ships.spawnEncounters = false                                 // (nothing sails in to shell the grounds)
        let o = ProvingGrounds.origin(spawn: findSpawn())
        _ = world.loadSync(center: V3(Float(o.x), Float(o.y), Float(o.z)), radius: 1)
        let first = ProvingGrounds.built(world, o) == false
        if first { provingBuild = ProvingGrounds.plan(o) }
        if first || player.pos.y < Float(o.y) - 30 {
            player.pos = ProvingGrounds.start(o)
            player.vel = .zero
            player.flying = first                                             // (held up while the deck goes down)
            player.yaw = .pi                                                  // looking south down the park
        }
    }
}
