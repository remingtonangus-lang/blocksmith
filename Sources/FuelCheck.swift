import Foundation
import simd

// P478's fuel check (questcheck --fuelcheck): fuel is a third liquid. Poured on a floor it runs out as water does
// (its own flowing states, no infinite source); he swims in it (and breathes none of it); fire or lava touching it
// sets it alight and the fire runs through the pool; an empty bucket dips it, a full one pours it or fills his
// vehicle's tank (the bucket back); a fuel depot's storage tanks are full of it.
enum FuelCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, p = g.player
        let home = p.pos, survival0 = g.survival, fly0 = p.flying
        defer { p.pos = home; g.survival = survival0; p.flying = fly0; p.vel = .zero }
        _ = w.loadSync(center: home, radius: 3)
        let bx = Int(floor(home.x)) - 6, bz = Int(floor(home.z)) - 6, by = min(CH - 30, w.topY(bx + 6, bz + 6) + 40)
        // A walled stone tray 13 x 13 in the air, two deep.
        func tray() {
            for z in -1...13 { for x in -1...13 { for y in 0...4 {
                let rim = x < 0 || x > 12 || z < 0 || z > 12
                w.setBlock(bx + x, by + y, bz + z, y == 0 || (rim && y <= 2) ? STONE : AIR)
            } } }
            for _ in 0..<4 { w.fluidTick() }
        }
        func count(_ y: Int, _ test: (BlockID) -> Bool) -> Int {
            var n = 0
            for z in 0...12 { for x in 0...12 where test(w.block(bx + x, by + y, bz + z)) { n += 1 } }
            return n
        }
        let fk = Blocks.fluidKind
        p.pos = V3(Float(bx) + 6.5, Float(by) + 6, Float(bz) + 6.5)
        let active0 = w.activeCenter
        w.activeCenter = p.pos                              // (the fluids round him run)
        defer { w.activeCenter = active0 }

        // Poured: it runs out over the floor in its own states.
        tray()
        w.setBlock(bx + 6, by + 1, bz + 6, FUEL)
        for _ in 0..<40 { w.fluidTick() }
        let spread = count(1) { fk[Int($0)] == 3 }, sources = count(1) { $0 == FUEL }, water = count(1) { fk[Int($0)] == 1 }
        check(spread >= 60 && sources == 1 && water == 0 && Blocks.watery[Int(FUEL)] && !Blocks.watery[Int(LAVA)],
              "fuelcheck: one source poured on a floor runs out over \(spread) cells as fuel (\(sources) source, \(water) water)")
        // Two sources a cell apart: the cell between stays a flow (no infinite fuel), as water's would fill.
        tray()
        w.setBlock(bx + 5, by + 1, bz + 6, FUEL); w.setBlock(bx + 7, by + 1, bz + 6, FUEL)
        for _ in 0..<40 { w.fluidTick() }
        let mid = w.block(bx + 6, by + 1, bz + 6)
        check(fk[Int(mid)] == 3 && mid != FUEL, "fuelcheck: between two sources the cell stays flowing fuel (\(Blocks.key(mid))), never a new source")

        // He swims in it, and under it he's in a liquid he can't breathe (the view goes amber).
        tray()
        for z in 4...8 { for x in 4...8 { for y in 1...3 { w.setBlock(bx + x, by + y, bz + z, FUEL) } } }
        for z in 3...9 { for x in 3...9 where x == 3 || x == 9 || z == 3 || z == 9 { for y in 1...3 { w.setBlock(bx + x, by + y, bz + z, STONE) } } }
        p.flying = false; p.vel = .zero; p.pos = V3(Float(bx) + 6.5, Float(by) + 1.2, Float(bz) + 6.5)
        p.update(dt: 1.0 / 60, input: MoveInput(), world: w)
        let under = p.inWater && p.inFuel && p.headInWater && p.headInFuel
        let flags = "swimming \(p.inWater), in fuel \(p.inFuel), head under \(p.headInFuel)"
        var up = MoveInput(); up.jump = true
        let y0 = p.pos.y
        for _ in 0..<60 { p.update(dt: 1.0 / 60, input: up, world: w) }
        check(under && p.pos.y > y0 + 0.8, "fuelcheck: under it he's in a liquid (\(flags)) and swims up " + String(format: "%.1f in a second", p.pos.y - y0))
        g.onFire = 0

        // An empty bucket dips a source; a full one at no vehicle pours it out.
        g.survival = true
        let sel = g.inventory.selected
        let held0 = g.inventory.main[sel]
        defer { g.inventory.main[sel] = held0 }
        g.inventory.main[sel] = ItemStack(Items.id("bucket"), 1)
        p.pos = V3(Float(bx) + 6.5, Float(by) + 4.2, Float(bz) + 6.5); p.yaw = 0; p.pitch = -Float.pi / 2 + 0.01
        g.target = nil
        let dipped = g.useBucket()
        let bucketFull = Items.key(g.inventory.main[sel].item) == VehicleDepot.bucketKey
            || (0..<36).contains { Items.key(g.inventory.main[$0].item) == VehicleDepot.bucketKey }
        let holeLeft = w.block(bx + 6, by + 3, bz + 6) == AIR
        for i in 0..<36 where Items.key(g.inventory.main[i].item) == VehicleDepot.bucketKey { g.inventory.main[i] = .empty }
        check(dipped && bucketFull && holeLeft, "fuelcheck: an empty bucket dips a fuel source (\(bucketFull)) and takes it (\(holeLeft))")
        tray()
        g.inventory.main[sel] = ItemStack(Items.id(VehicleDepot.bucketKey), 1)
        p.pos = V3(Float(bx) + 6.5, Float(by) + 2.2, Float(bz) + 6.5)
        g.target = (IVec3(bx + 6, by, bz + 6), IVec3(0, 1, 0))
        let poured = g.useBucket()
        g.target = nil
        check(poured && w.block(bx + 6, by + 1, bz + 6) == FUEL && Items.key(g.inventory.main[sel].item) == "bucket",
              "fuelcheck: a fuel bucket pours a source onto the floor (\(Blocks.key(w.block(bx + 6, by + 1, bz + 6)))) and leaves the bucket")

        // Set alight: a pool with fire at its edge burns away; lava touching fuel lights it.
        tray()
        for z in 2...10 { for x in 2...10 { w.setBlock(bx + x, by + 1, bz + z, FUEL) } }
        let pool0 = count(1) { fk[Int($0)] == 3 }
        w.placeFire(IVec3(bx + 1, by + 1, bz + 6))
        var tFire = 0
        for t in 0..<120 {
            w.fluidTick()
            if t % 7 == 6 { w.fireTick() }
            if count(1, { fk[Int($0)] == 3 }) == 0 { tFire = t + 1; break }
        }
        let left = count(1) { fk[Int($0)] == 3 }
        check(pool0 >= 70 && left == 0, "fuelcheck: fire at the edge of a \(pool0)-cell pool burns it all away in \(Double(tFire) * 0.25) s (\(left) left)")
        tray()
        for x in 2...6 { w.setBlock(bx + x, by + 1, bz + 6, FUEL) }
        w.setBlock(bx + 7, by + 1, bz + 6, LAVA)
        for t in 0..<40 { w.fluidTick(); if t % 6 == 5 { w.fluidTick(lava: true) } }
        let lavaLeft = (2...6).filter { fk[Int(w.block(bx + $0, by + 1, bz + 6))] == 3 }.count
        check(lavaLeft == 0, "fuelcheck: lava touching a line of fuel lights it all (\(lavaLeft) of 5 left)")
        tray()

        // P504 ("We got some hovering fire"): a crater's fire burns as fire (it ticks), goes out when the ground under it
        // goes, and a flame in the air beside leaves doesn't hang there.
        let f1 = IVec3(bx + 3, by + 1, bz + 3)
        w.lightFire(f1)
        w.fireTick()
        let ticking = w.fires[f1] != nil && w.block(f1.x, f1.y, f1.z) == FIRE
        w.setBlock(f1.x, f1.y - 1, f1.z, AIR)
        for _ in 0..<4 { g.gravityTick() }
        let outWhenUndercut = w.block(f1.x, f1.y, f1.z) != FIRE
        w.setBlock(f1.x, f1.y - 1, f1.z, STONE)
        let leaf = Blocks.id("oak_leaves")
        w.setBlock(bx + 8, by + 3, bz + 8, leaf)
        w.lightFire(IVec3(bx + 9, by + 3, bz + 8))
        for _ in 0..<3 { w.fireTick() }
        let hanging = (7...10).filter { w.block(bx + $0, by + 3, bz + 8) == FIRE }.count
        check(ticking && outWhenUndercut && hanging == 0,
              "fuelcheck: a crater's fire ticks (\(ticking)), goes out when the ground under it goes (\(outWhenUndercut)), none hangs in the air by leaves (\(hanging))")
        tray()

        // A fuel bucket beside his vehicle fills its tank (half a tank), the bucket back.
        let car = w.ships.spawn(AshCommandeer.sidecar(), at: home + V3(0, 30, 0), yaw: 0, name: "Test Car", role: "")
        car.role = nil
        defer { w.ships.remove(car) }
        VehicleDepot.setLevel(car, 0.1)
        p.pos = car.toWorld(car.com)
        g.inventory.main[sel] = ItemStack(Items.id(VehicleDepot.bucketKey), 1)
        let filled = g.useBucket()
        check(filled && abs(VehicleDepot.level(car) - 0.6) < 0.01 && Items.key(g.inventory.main[sel].item) == "bucket",
              String(format: "fuelcheck: a fuel bucket beside his car fills its tank to %.0f%% and leaves the bucket", VehicleDepot.level(car) * 100))
        let can = Recipes.match([Items.id(VehicleDepot.bucketKey), Items.id("iron_ingot"), 0, 0], 2, 2)
        check(can.map { Items.key($0.result.item) } == VehicleDepot.canKey
              && Game.craftRemainder(ItemStack(Items.id(VehicleDepot.bucketKey), 1)).item == Items.id("bucket"),
              "fuelcheck: a fuel bucket and an iron ingot craft a Fuel Can, the bucket back")

        // A fuel depot's three storage tanks hold it.
        let site = Depots.Site(x0: 0, x1: Depots.AW, z0: 0, z1: Depots.AD, S: 100, side: 1, fuel: true, baseKey: "fuelcheck")
        var cells = 0
        for cz in -1...(Depots.AD / CS + 1) { for cx in -1...(Depots.AW / CS + 1) {
            var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
            for z in 0..<CS { for x in 0..<CS { for y in 0...100 { buf[Chunk.index(x, y, z)] = STONE } } }
            buf.withUnsafeMutableBufferPointer { b in
                var sw = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                Depots.build(&sw, site, 4789)
            }
            cells += buf.filter { $0 == FUEL }.count
        } }
        check(cells > 900, "fuelcheck: a fuel depot's three storage tanks hold \(cells) cells of fuel")
    }
}
