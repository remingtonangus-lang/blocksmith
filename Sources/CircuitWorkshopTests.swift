import Foundation
import simd
import Metal

// The Sparkstone Workshop's benches (CircuitWorkshop.swift) run through the real circuit engine: the deck is built far
// above the terrain beside the player, every bench is driven the way a player would (Game.useCircuit on its lever or
// button, a block placed, items in a chest) with World.redstone.tick() as the clock, and each must behave like the genre
// reference: the periods, the toggles, the door, the sorted items, the subtraction. Then the deck is cleared.
// Shared (questcheck runs it; the Mac runs it with --coppertest).
enum CircuitWorkshopTests {
    // (the suite's renderer, when it has one: pictures from under the rebuilt deck)
    static var shot: ((Game, String, V3, Float, Float) -> Void)?

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
        let held0 = w.heldDeck
        w.heldDeck = CircuitWorkshop.held(o)
        _ = DeckHold.settle(g, quiet: true)                 // (what earlier checks left queued, first)
        let at = CircuitWorkshop.build(w, at: o)
        defer { CircuitWorkshop.clear(w, at: o); w.heldDeck = held0 }
        // Nov 14: the load checks the build queued run to the end (the whole weigh too): nothing of the deck comes down,
        // and every pillar reaches the land.
        do {
            func census() -> Int {
                var n = 0
                for x in -1...CircuitWorkshop.deckLength { for z in -4...CircuitWorkshop.deckDepth { for y in -1...5 where w.rawBlock(o.x + x, o.y + y, o.z + z) != AIR { n += 1 } } }
                return n
            }
            let before = census()
            let (frames, fell) = DeckHold.settle(g, around: (V3(Float(o.x + CircuitWorkshop.deckLength / 2), Float(o.y), Float(o.z + 4)), Float(CircuitWorkshop.deckLength / 2 + 16)), origin: o)
            let after = census()
            var short = 0
            if !HeldDeck.old {
                for (x, z) in CircuitWorkshop.pillars() {
                    var y = o.y - 2
                    while y > 1 && w.rawBlock(o.x + x, y, o.z + z) == Blocks.id("stone_bricks") { y -= 1 }
                    let b = w.rawBlock(o.x + x, y, o.z + z)
                    if !(Blocks.collide[Int(b)] && SmoothTerrain.natural[Int(b)]) { short += 1 }
                }
            }
            check(after == before && fell == 0 && short == 0,
                  "workshop: the deck stands through its load checks (\(frames) frames, \(before) blocks then \(after), \(fell) fell), \(CircuitWorkshop.pillars().count) pillars, \(short) not down to the land")
        }

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
            if Env.all["BS_WSDEBUG"] != nil {
                var tr = ""
                for _ in 0..<24 { tick(); tr += "\(st(obs) >= 6 ? "A" : "a")\(st(b + IVec3(3, 0, 0)) >= 6 ? "B" : "b") " }
                print("workshop debug: observers \(tr)")
            }
            let (gaps, onTicks) = edges(80) { st(obs) >= 6 }
            check(gaps.count >= 15 && gaps.allSatisfy { $0 == 4 } && onTicks == 40 && lit(b + IVec3(1, 0, 0)),
                  "workshop: the observer clock pulses every 4 game ticks, 2 on (gaps \(Array(Set(gaps)).sorted()), on \(onTicks) of 80), its lamp stays lit")
        } else { check(false, "workshop: the observer clock bench was built") }

        // 3. (P463: the bulb toggle bench left with the copper bulb.)
        check(at["bulb_toggle"] == nil, "workshop: no bulb toggle bench (the copper bulb is retired)")

        // 4. Piston door: shut by the torch at rest; the lever pulls both door blocks back (a 1x2 opening you can walk
        // through), off again it shuts.
        if let b = at["piston_door"] {
            let lever = b + IVec3(3, 2, -2)
            func doorway() -> [String] { [key(b + IVec3(5, 0, 0)), key(b + IVec3(5, 1, 0))] }
            let shut = doorway() == ["stone_bricks", "stone_bricks"] && st(b + IVec3(3, 0, 0)) == 11 && st(b + IVec3(3, 1, 0)) == 11
            // Ledger 192 (Nov 15 20:44:58, at this lever: "too much of a delay between pressing the switch and the
            // redstone occurring"): the game ticks from the lever to the open doorway. The rules' least is the torch's
            // 2 (one circuit tick) and the pistons pulling back on the tick the torch goes out.
            use(lever)
            var openAt = -1
            for i in 1...20 { tick(); if openAt < 0 && blk(b + IVec3(5, 0, 0)) == AIR && blk(b + IVec3(5, 1, 0)) == AIR { openAt = i } }
            check(openAt >= 1 && openAt <= 2,
                  "Ledger 192 workshop: the piston door opens \(openAt) game ticks (\(openAt * 50) ms) after the lever, the rules' least (the torch's one circuit tick)")
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
        rebuild(device: w.device, check: check, shot: shot)
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

extension CircuitWorkshopTests {
    // Ledger 200: his save as the Nov 15 evening pictures show it. A deck that came down lies on the land, an old bench's
    // stone posts on it, short pillars standing on it; a deck over it on those pillars with a bench's sign gone, another
    // stacked over that; items dropped in the box. The save has no record of its deck (as every save before this).
    // Entering the world must leave one deck: its pillars from the land to its floor, every bench as a new world's,
    // nothing else built in the box, no items. Then the held floor is let go and the load checks run: what falls is
    // reported (whether pillars every 8 blocks stand the deck alone).
    static func rebuild(device: MTLDevice, check: (Bool, String) -> Void, shot: ((Game, String, V3, Float, Float) -> Void)?) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wsrebuild-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let dir = root.appendingPathComponent(CircuitWorkshop.worldName, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let save = SaveManager(dir: dir)
        let w = World(seed: CircuitWorkshop.seed, device: device, save: save)
        w.renderDistance = 4
        let g = Game(world: w, save: save, persistent: true)
        g.survival = false; g.player.pos = g.spawnPoint
        g.workshopTick()
        guard case let (o, v)? = g.workshopDeck, v == CircuitWorkshop.version else {
            check(CircuitWorkshop.oldDeck, "Ledger 200 workshop rebuild: a new world records its deck (\(g.workshopDeck.map { "\($0.1)" } ?? "none"))"); return
        }
        let len = CircuitWorkshop.deckLength, depth = CircuitWorkshop.deckDepth
        let brick = Blocks.id("stone_bricks")
        // A new world's deck, as the benches are built (state groups: the clocks tick).
        func deck(_ o: IVec3) -> [BlockID] {
            var out: [BlockID] = []
            for x in -1...len { for z in -4...depth { for y in -1...5 { out.append(Blocks.groupBase[Int(w.rawBlock(o.x + x, o.y + y, o.z + z))]) } } }
            return out
        }
        let fresh = deck(o)
        // His save: a fallen deck on the land, stone posts on it, short pillars from it up to a deck with a sign gone,
        // and one more stacked on that. Items dropped in the box.
        let site = g.findSpawn()
        let (x0, z0) = CircuitWorkshop.corner(site)
        var land = SEA
        for x in -1...len { for z in -4...depth { land = max(land, CircuitWorkshop.landY(w, x0 + x, z0 + z)) } }
        let fallen = IVec3(x0, land + 2, z0)
        CircuitWorkshop.clear(w, at: o)
        CircuitWorkshop.build(w, at: fallen)
        for x in stride(from: 3, to: len, by: 9) { _ = w.setBlockAsync(fallen.x + x, fallen.y, fallen.z + 2, STONE); _ = w.setBlockAsync(fallen.x + x, fallen.y + 1, fallen.z + 2, STONE) }
        let mid = IVec3(x0, fallen.y + 11, z0)
        CircuitWorkshop.build(w, at: mid)
        for (x, z) in CircuitWorkshop.pillars() { for y in (fallen.y + 6)...(mid.y - 2) { _ = w.setBlockAsync(mid.x + x, y, mid.z + z, brick) } }
        let gone = mid + IVec3(CircuitWorkshop.layout()[2].1 - 1, 0, -1)
        w.blockEntities[gone] = nil; _ = w.setBlockAsync(gone.x, gone.y, gone.z, AIR)
        CircuitWorkshop.build(w, at: mid + IVec3(0, 11, 0))
        for i in 0..<5 { g.dim.drops.spawn(ItemStack(Items.id("cobblestone"), 1), at: V3(Float(x0 + 4 + i * 9), Float(fallen.y + 1), Float(z0 + 2))) }
        let items0 = g.dim.drops.items.count
        g.workshopDeck = nil
        g.player.pos = CircuitWorkshop.walkwayStart(mid)
        g.workshopChecked = false
        g.workshopTick()
        guard case let (o2, _)? = g.workshopDeck else { check(false, "Ledger 200 workshop rebuild: no deck recorded after the rebuild"); return }
        // One deck: the walkway's marker corner at one height only, the recorded one.
        var corners: [Int] = []
        let marker = Blocks.id(CircuitWorkshop.markerBlock)
        for y in 1..<(CH - 1) where w.rawBlock(x0 - 1, y - 1, z0 - 4) == marker && w.rawBlock(x0 - 1, y - 1, z0 - 3) == marker { corners.append(y) }
        // Every pillar from the land to the floor.
        var short = 0
        for (x, z) in CircuitWorkshop.pillars() {
            var y = o2.y - 2
            while y > 1 && w.rawBlock(o2.x + x, y, o2.z + z) == brick { y -= 1 }
            let b = Int(w.rawBlock(o2.x + x, y, o2.z + z))
            if !(Blocks.collide[b] && SmoothTerrain.natural[b]) || w.rawBlock(o2.x + x, o2.y - 2, o2.z + z) != brick { short += 1 }
        }
        // Every bench as a new world's.
        let now = deck(o2)
        let benches = now == fresh && CircuitWorkshop.whole(w, at: o2)
        // Nothing else built in the box.
        var pillarCells = Set<IVec3>()
        for (x, z) in CircuitWorkshop.pillars() { for y in 0..<CH where w.rawBlock(o2.x + x, y, o2.z + z) == brick { pillarCells.insert(IVec3(o2.x + x, y, o2.z + z)) } }
        var stray = 0, strayAt: IVec3?
        for x in (o2.x - 2)...(o2.x + len + 2) { for z in (o2.z - 6)...(o2.z + depth + 2) {
            for y in (CircuitWorkshop.landY(w, x, z) + 1)...min(CH - 2, o2.y + CircuitWorkshop.boxUp + CircuitWorkshop.boxReach) {
                let p = IVec3(x, y, z)
                let inDeck = x >= o2.x - 1 && x <= o2.x + len && z >= o2.z - 4 && z <= o2.z + depth && y >= o2.y - 1 && y <= o2.y + 5
                if !inDeck && !pillarCells.contains(p) && !CircuitWorkshop.keeps(w.rawBlock(x, y, z)) { stray += 1; if strayAt == nil { strayAt = p } }
            }
        } }
        let itemsLeft = g.dim.drops.items.filter { $0.pos.x >= Float(x0 - 2) && $0.pos.x < Float(x0 + len + 3) && $0.pos.z >= Float(z0 - 6) && $0.pos.z < Float(z0 + depth + 3) }.count
        let onWalk = simd_length(g.player.pos - CircuitWorkshop.walkwayStart(o2)) < 0.01
        check(corners == [o2.y] && short == 0 && benches && stray == 0 && itemsLeft == 0 && onWalk,
              "Ledger 200 workshop rebuild: his save (a fallen deck, short pillars, a deck with a sign gone, one stacked on it, \(items0) items) enters as one deck (marker rows at \(corners), recorded \(o2.y)), \(CircuitWorkshop.pillars().count) pillars, \(short) not from the land to the floor, benches as a new world's \(benches), \(stray) other built blocks in the box\(strayAt.map { " (first \($0.x) \($0.y) \($0.z): \(Blocks.key(w.rawBlock($0.x, $0.y, $0.z))))" } ?? ""), \(itemsLeft) items left, he stands on the walkway \(onWalk)")
        // Pictures from under the deck (the suite's renderer).
        if let shot = shot {
            let under = Float(o2.y) - 4
            shot(g, "workshop_under_west", V3(Float(o2.x) - 10, under, Float(o2.z) + 4), .pi / 2 + .pi, 0.25)
            shot(g, "workshop_under_south", V3(Float(o2.x + len / 2), under, Float(o2.z + depth) + 14), 0, 0.3)
            shot(g, "workshop_under_mid", V3(Float(o2.x + len / 2), under + 1, Float(o2.z) + 4), -.pi / 2, 0.35)
            shot(g, "workshop_deck", V3(Float(o2.x) + 0.5, Float(o2.y) + 1.6, Float(o2.z) - 1.5), -.pi / 2, -0.1)
        }
        // The held floor let go: what the load checks bring down with pillars alone.
        w.heldDeck = .none
        for x in stride(from: -1, through: len, by: 4) { for z in stride(from: -4, through: depth, by: 4) { w.requeueLoadCheck(IVec3(o2.x + x, o2.y - 1, o2.z + z)) } }
        let (frames, fell) = DeckHold.settle(g, around: (V3(Float(o2.x + len / 2), Float(o2.y), Float(o2.z + 4)), Float(len / 2 + 16)), origin: o2)
        print("workshop held floor off: \(fell) blocks fell in \(frames) frames (\(CircuitWorkshop.pillars().count) pillars, every 8 blocks)")
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

// Nov 14: runs the load checks a build queued (Structure.tick, StructureTip, StructureCollapse's whole weigh) until
// none is left, as the game's ticks would. Returns the frames it took and the blocks brought down.
enum DeckHold {
    // `around`: a centre and half-width the checks run in as though he stood there (a hot zone, FarTicks), the checks
    // parked past the active distance brought back.
    static func settle(_ g: Game, around: (V3, Float)? = nil, origin: IVec3? = nil, quiet: Bool = false, frames most: Int = 400_000) -> (Int, Int) {
        let w = g.world
        let fell0 = Structure.fellTotal
        Structure.fellTally = quiet ? nil : [:]
        Structure.fellOrigin = origin
        defer {
            if let t = Structure.fellTally, !t.isEmpty { print("  fell: " + t.sorted { $0.value > $1.value }.prefix(40).map { "\($0.key) \($0.value)" }.joined(separator: ", ")) }
            Structure.fellTally = nil; Structure.fellOrigin = nil
        }
        if let (c, r) = around { w.heat(at: c, radius: r, seconds: 3600); w.unparkActive() }
        defer { if let (c, _) = around { w.hotZones.removeAll { $0.center == c } } }
        var n = 0, quiet = 0
        while n < most {
            Structure.tick(g); StructureTip.tick(g); StructureCollapse.tick(g)
            n += 1
            if n % 500 == 0 && around != nil { w.unparkActive() }
            if w.loadQueue.isEmpty && !StructureCollapse.busy { quiet += 1; if quiet > 400 { break } } else { quiet = 0 }
            if StructureCollapse.withWorker { usleep(500) }
        }
        return (n, Structure.fellTotal - fell0)
    }
}
