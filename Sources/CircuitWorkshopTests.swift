import Foundation
import simd
import Metal

// The Sparkstone Workshop's benches (CircuitWorkshop.swift) run through the real circuit engine: the deck is built far
// above the terrain beside the player, every bench is driven the way a player would (Game.useCircuit on its lever or
// button, a block placed, items in a chest) with World.redstone.tick() as the clock, and each must behave like the genre
// reference: the periods, the toggles, the door, the sorted items, the subtraction. Then the deck is cleared.
// Shared (questcheck runs it; the Mac runs it with --coppertest).
enum CircuitWorkshopTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let w = g.world, rs = w.redstone
        let p0 = g.player.pos
        // East of the player, out of the way of later checks, 12 above the highest ground under the deck.
        let x0 = Int(floorf(p0.x)) + 160, z0 = Int(floorf(p0.z))
        let mid = V3(Float(x0 + CircuitWorkshop.deckLength / 2), p0.y, Float(z0))
        _ = w.loadSync(center: mid, radius: (CircuitWorkshop.deckLength / 2) / 16 + 2)
        var top = SEA
        for x in stride(from: -1, through: CircuitWorkshop.deckLength, by: 4) { for z in stride(from: -4, through: CircuitWorkshop.deckDepth, by: 4) { top = max(top, w.topY(x0 + x, z0 + z)) } }
        let o = IVec3(x0, min(CH - 12, top + 12), z0)
        let at = CircuitWorkshop.build(w, at: o)
        defer { CircuitWorkshop.clear(w, at: o) }

        func blk(_ p: IVec3) -> BlockID { w.block(p.x, p.y, p.z) }
        func st(_ p: IVec3) -> Int { let b = blk(p); return Int(b - Blocks.groupBase[Int(b)]) }
        func key(_ p: IVec3) -> String { Blocks.key(Blocks.groupBase[Int(blk(p))]) }
        func lit(_ p: IVec3) -> Bool { key(p) == "redstone_lamp" && st(p) == 1 }
        func tick(_ n: Int = 1) { for _ in 0..<n { rs.tick() } }
        func use(_ p: IVec3) { _ = g.useCircuit(p) }
        func count(_ p: IVec3, _ k: String) -> Int {
            guard let be = w.blockEntities[p] else { return 0 }
            return be.container.slots.reduce(0) { $0 + ($1.isEmpty || Items.key($1.item) != k ? 0 : $1.count) }
        }
        // Rising edges of `on` over `n` ticks and the gaps between them.
        func edges(_ n: Int, _ on: () -> Bool) -> (gaps: [Int], onTicks: Int) {
            var last = -1, gaps: [Int] = [], was = on(), onTicks = 0
            for i in 0..<n {
                tick()
                let now = on()
                if now { onTicks += 1 }
                if now && !was { if last >= 0 { gaps.append(i - last) }; last = i }
                was = now
            }
            return (gaps, onTicks)
        }
        tick(60)                                                     // everything settles (the door shuts, the clocks start)

        // 1. Torch clock: torch 2 game ticks + repeater 8 per half cycle = a 20-tick period, steady, no burnout.
        if let b = at["torch_clock"] {
            let torch = b + IVec3(2, 0, 0), lamp = b + IVec3(2, 1, 0)
            var lampSeen = Set<Bool>()
            let (gaps, onTicks) = edges(200) { lampSeen.insert(lit(lamp)); return st(torch) == 5 }
            check(gaps.count >= 8 && gaps.allSatisfy { $0 == 20 } && abs(onTicks - 100) <= 10 && lampSeen.count == 2,
                  "workshop: the torch clock ticks every 20 game ticks, half on, never burns out, its lamp blinks (gaps \(Array(Set(gaps)).sorted()), \(gaps.count + 1) pulses, on \(onTicks) of 200)")
        } else { check(false, "workshop: the torch clock bench was built") }

        // 2. Observer clock: each observer is on 2 game ticks of every 4.
        if let b = at["observer_clock"] {
            let obs = b + IVec3(2, 0, 0)
            if ProcessInfo.processInfo.environment["BS_WSDEBUG"] != nil {
                var tr = ""
                for _ in 0..<24 { tick(); tr += "\(st(obs) >= 6 ? "A" : "a")\(st(b + IVec3(3, 0, 0)) >= 6 ? "B" : "b") " }
                print("workshop debug: observers \(tr)")
            }
            let (gaps, onTicks) = edges(80) { st(obs) >= 6 }
            check(gaps.count >= 15 && gaps.allSatisfy { $0 == 4 } && onTicks == 40 && lit(b + IVec3(1, 0, 0)),
                  "workshop: the observer clock pulses every 4 game ticks, 2 on (gaps \(Array(Set(gaps)).sorted()), on \(onTicks) of 80), its lamp stays lit")
        } else { check(false, "workshop: the observer clock bench was built") }

        // 3. Bulb toggle: each press of the button flips the lamp; the release doesn't.
        if let b = at["bulb_toggle"] {
            let button = b + IVec3(1, 0, 0), lamp = b + IVec3(4, 0, 0)
            var got: [Bool] = []
            for _ in 0..<4 { use(button); tick(30); got.append(lit(lamp)) }
            check(got == [true, false, true, false], "workshop: the bulb toggle flips its lamp on each press (\(got))")
        } else { check(false, "workshop: the bulb toggle bench was built") }

        // 4. Piston door: shut by the torch at rest; the lever pulls both door blocks back (a 1x2 opening you can walk
        // through), off again it shuts.
        if let b = at["piston_door"] {
            let lever = b + IVec3(3, 2, -2)
            func doorway() -> [String] { [key(b + IVec3(5, 0, 0)), key(b + IVec3(5, 1, 0))] }
            let shut = doorway() == ["stone_bricks", "stone_bricks"] && st(b + IVec3(3, 0, 0)) == 11 && st(b + IVec3(3, 1, 0)) == 11
            use(lever); tick(20)
            let after = "lever \(st(lever)), torch \(st(b + IVec3(3, 1, -1))), pistons \(st(b + IVec3(3, 0, 0)))/\(st(b + IVec3(3, 1, 0))), x4 \(key(b + IVec3(4, 0, 0)))/\(key(b + IVec3(4, 1, 0))), x5 \(doorway())"
            let open = blk(b + IVec3(5, 0, 0)) == AIR && blk(b + IVec3(5, 1, 0)) == AIR
                && key(b + IVec3(4, 0, 0)) == "stone_bricks" && key(b + IVec3(4, 1, 0)) == "stone_bricks"
            let feet = V3(Float(b.x + 5) + 0.5, Float(b.y), Float(b.z) + 0.5)
            let walk = !w.collides(feet - V3(0.3, 0, 0.3), feet + V3(0.3, 1.8, 0.3))
            use(lever); tick(20)
            let again = doorway() == ["stone_bricks", "stone_bricks"]
            check(shut && open && walk && again,
                  "workshop: the piston door is shut at rest (\(shut)), the lever opens a 1x2 way through (\(open), walkable \(walk)), and it shuts again (\(again)); open state: \(after)")
        } else { check(false, "workshop: the piston door bench was built") }

        // 5. Hopper sorter: iron and cobblestone go in; the iron ends up under the filter, the cobblestone at the end
        // of the line, and the filter keeps its 18 iron and 4 fillers.
        if let b = at["hopper_sorter"] {
            let input = w.blockEntities[b + IVec3(0, 4, 0)]
            input?.container[0] = ItemStack(Items.id(CircuitWorkshop.sortItem), 6)
            input?.container[1] = ItemStack(Items.id(CircuitWorkshop.otherItem), 6)
            tick(1600)
            let sorted = count(b + IVec3(2, 0, 0), CircuitWorkshop.sortItem) + count(b + IVec3(2, 1, 0), CircuitWorkshop.sortItem)
            let endIron = count(b + IVec3(5, 3, 0), CircuitWorkshop.sortItem), endCobble = count(b + IVec3(5, 3, 0), CircuitWorkshop.otherItem)
            let filter = b + IVec3(2, 2, 0)
            let kept = count(filter, CircuitWorkshop.sortItem), fillers = count(filter, CircuitWorkshop.fillerItem)
            let strayCobble = count(b + IVec3(2, 0, 0), CircuitWorkshop.otherItem) + count(b + IVec3(2, 1, 0), CircuitWorkshop.otherItem)
            check(sorted == 6 && endIron == 0 && endCobble == 6 && kept == 18 && fillers == 4 && strayCobble == 0,
                  "workshop: the hopper sorter keeps the iron (\(sorted) of 6 sorted, \(endIron) passed), passes the cobblestone (\(endCobble) of 6 at the end, \(strayCobble) sorted by mistake), the filter keeps \(kept) iron + \(fillers) fillers")
        } else { check(false, "workshop: the hopper sorter bench was built") }

        // 6. Subtraction: 12 at the back, the lever's 5 at the side: 7 out, the seventh dust the last one lit.
        if let b = at["comparator_subtract"] {
            let c = b + IVec3(6, 0, 0)
            let alone = rs.comparatorOut[c] ?? 0
            use(b + IVec3(16, 0, 2)); tick(30)
            let out = rs.comparatorOut[c] ?? 0
            let dust = (7...13).map { st(b + IVec3($0, 0, 0)) & 15 }
            let side = st(b + IVec3(6, 0, 1)) & 15
            check(alone == 12 && side == 5 && out == 7 && dust == [7, 6, 5, 4, 3, 2, 1] && lit(b + IVec3(14, 0, 0)),
                  "workshop: comparator subtraction: \(alone) - \(side) = \(out), the output dust reads \(dust)")
        } else { check(false, "workshop: the subtraction bench was built") }

        // 7. Observer sensor: a block placed on the mark flashes the lamp (a 2-tick pulse; the lamp goes out after).
        if let b = at["observer_sensor"] {
            let spot = b + IVec3(1, 0, 0), obs = b + IVec3(2, 0, 0), lamp = b + IVec3(3, 0, 0)
            let dark = !lit(lamp)
            w.setBlock(spot.x, spot.y, spot.z, Blocks.id("cobblestone"))
            var pulse = 0, flashed = false
            for _ in 0..<20 { tick(); if st(obs) >= 6 { pulse += 1 }; if lit(lamp) { flashed = true } }
            check(dark && flashed && pulse == 2 && !lit(lamp),
                  "workshop: the observer sensor sees a block placed and flashes its lamp (\(pulse)-tick pulse, lit \(flashed), out after \(!lit(lamp)))")
        } else { check(false, "workshop: the observer sensor bench was built") }

        // The world: seven benches, each with its sign; picked from the Worlds menu.
        let signs = at.values.filter { w.blockEntities[$0 + IVec3(-1, 0, -1)]?.kind == .sign }.count
        check(at.count == CircuitWorkshop.benches.count && signs == at.count,
              "workshop: \(at.count) benches built, \(signs) signed (the Sparkstone Workshop world in the Worlds menu)")
        entry(device: w.device, check: check)
    }

    // Entering the world the way the Worlds menu does: a fresh save folder named after the workshop, its fixed seed, the
    // player at the world's spawn as a new world puts them. The first tick must build the deck there and stand the
    // player on the walkway; a second visit to the same folder must find it and leave the player alone.
    static func entry(device: MTLDevice, check: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wsentry-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let dir = root.appendingPathComponent(CircuitWorkshop.worldName, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        // As App.makeGame / QuestApp.load: a saved world gets its meta back (its spawn, its position), a new one starts
        // at spawnPoint.
        func visit() -> (Game, V3) {
            let save = SaveManager(dir: dir)
            let meta = save.loadMeta()
            let w = World(seed: CircuitWorkshop.seed, device: device, save: save)
            w.renderDistance = 4
            let g = Game(world: w, save: save, persistent: true)
            if let m = meta { g.apply(m) } else { g.survival = false; g.player.pos = g.spawnPoint }
            let start = g.player.pos
            for _ in 0..<3 { g.workshopTick() }
            return (g, start)
        }
        let (g, start) = visit()
        let site = g.findSpawn()
        // The walkway start in x/z (the deck's height came from the ground before it was built).
        let o = IVec3(Int(floorf(site.x)) - 8, 0, Int(floorf(site.z)) - 4), ws = CircuitWorkshop.walkwayStart(o)
        let onWalk = abs(g.player.pos.x - ws.x) < 0.01 && abs(g.player.pos.z - ws.z) < 0.01
        let built = CircuitWorkshop.built(g.world, spawn: site)
        let below = g.world.block(Int(floorf(g.player.pos.x)), Int(floorf(g.player.pos.y)) - 1, Int(floorf(g.player.pos.z)))
        let near = abs(g.player.pos.x - start.x) < 16 && abs(g.player.pos.z - start.z) < 16
        check(built && onWalk && near && Blocks.key(below) == CircuitWorkshop.markerBlock && g.workshopChecked,
              "workshop world entry: the first tick builds the deck over the world's spawn and stands the player on the walkway (built \(built), on walkway \(onWalk), standing on \(Blocks.key(below)), spawn " + String(format: "%.0f, %.0f)", start.x, start.z))
        // The player moves the spawn 200 blocks away (a bed) and walks off; the next visit must find the deck where it
        // is, build no second one at the new spawn and leave the player where they were.
        let bed = V3(start.x + 200, start.y, start.z)
        g.spawnPoint = g.settleSpawn(bed)
        g.player.pos = g.spawnPoint + V3(0, 0.5, 0)
        g.saveNow(); SaveIO.flush()
        let (g2, start2) = visit()
        _ = g2.world.loadSync(center: g2.spawnPoint, radius: 1)
        let second = CircuitWorkshop.built(g2.world, spawn: g2.spawnPoint)
        check(CircuitWorkshop.built(g2.world, spawn: site) && !second && simd_length(g2.player.pos - start2) < 0.01 && abs(start2.x - bed.x) < 16,
              "workshop world entry: coming back (spawn moved 200 blocks by a bed) finds the deck, builds no second one (\(second)) and leaves the player be")
    }
}

extension CircuitWorkshop {
    // Removes the deck and everything on it (blocks and block entities).
    static func clear(_ w: World, at o: IVec3) {
        for x in -1...deckLength { for z in -4...deckDepth { for y in -1...6 {
            let p = o + IVec3(x, y, z)
            w.blockEntities[p] = nil
            _ = w.setBlockAsync(p.x, p.y, p.z, AIR)
        } } }
        for _ in 0..<10 { w.redstone.tick() }
    }
}
