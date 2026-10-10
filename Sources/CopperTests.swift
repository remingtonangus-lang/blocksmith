import Foundation
import simd

// --coppertest: copper circuits (our redstone) against the reference, one test per row of docs/status/copper-parity.md.
// Every circuit is built on its own pad high above the terrain and run through the real engine: World.redstone.tick()
// and detectorCheck (the circuit half of Game.gameTick), the player's use action (Game.useCircuit), dispensers and
// hoppers through their Game services, carts through Mob.updateMinecart, arrows through ProjectileManager.update.
// Rows the checklist marks missing run as expected failures (MISSING, not counted); one that starts passing prints
// XPASS and fails the run so the checklist gets updated. Returns the number of failures.
enum CopperTests {
    static func run(_ g: Game) -> Int {
        let w = g.world
        let rs = w.redstone
        var pass = 0, fail = 0, missing = 0, xpass = 0
        var bad: [String] = []

        // Pads: a grid of 20 x 8 cells, three layers 10 apart, above the highest terrain around the player.
        let p0 = g.player.pos
        let cx = Int(floor(p0.x)), cz = Int(floor(p0.z))
        var top = 0
        for dx in stride(from: -48, through: 48, by: 4) { for dz in stride(from: -48, through: 48, by: 4) { top = max(top, w.topY(cx + dx, cz + dz)) } }
        let baseY = min(CH - 40, top + 8)
        var sites: [IVec3] = []
        for ly in 0..<3 { for sx in [-40, -20, 0, 20] { for sz in stride(from: -40, through: 40, by: 8) {
            sites.append(IVec3(cx + sx + 2, baseY + ly * 10, cz + sz + 3))
        } } }
        var next = 0
        var o = IVec3(0, 0, 0)
        var carts: [V3] = []
        let savedTime = g.time

        // MARK: helpers
        func site() { o = sites[min(next, sites.count - 1)]; next += 1 }
        func P(_ x: Int, _ y: Int = 0, _ z: Int = 0) -> IVec3 { o + IVec3(x, y, z) }
        func putB(_ p: IVec3, _ b: BlockID) { w.setBlockAsync(p.x, p.y, p.z, b) }
        func put(_ p: IVec3, _ key: String, _ s: Int = 0) { putB(p, Blocks.id(key) + BlockID(s)) }
        func on(_ p: IVec3, _ key: String, _ s: Int = 0) { putB(p + IVec3(0, -1, 0), STONE); put(p, key, s) }
        func air(_ p: IVec3) { putB(p, AIR) }
        func blk(_ p: IVec3) -> BlockID { w.block(p.x, p.y, p.z) }
        func st(_ p: IVec3) -> Int { let b = blk(p); return Int(b - Blocks.groupBase[Int(b)]) }
        func key(_ p: IVec3) -> String { Blocks.key(Blocks.groupBase[Int(blk(p))]) }
        func tick(_ n: Int = 1) { for _ in 0..<n { rs.tick(); rs.detectorCheck(carts) } }
        // Ticks until `c` holds (1 = on the first tick), -1 if never within `limit`.
        func until(_ limit: Int, _ c: () -> Bool) -> Int { for i in 1...limit { tick(); if c() { return i } }; return -1 }
        func lit(_ p: IVec3) -> Bool { key(p) == "redstone_lamp" && st(p) == 1 }
        func use(_ p: IVec3) { _ = g.useCircuit(p) }
        func wire(_ p: IVec3) { on(p, "redstone_wire") }
        func battery(_ p: IVec3) { put(p, "redstone_block") }
        func item(_ k: String, _ n: Int = 1) -> ItemStack { ItemStack(Items.id(k), n) }
        func entity(_ p: IVec3, _ k: String, _ kind: BlockEntity.Kind, _ items: [ItemStack] = []) -> BlockEntity {
            put(p, k)
            let be = BlockEntity(kind)
            w.blockEntities[p] = be
            for (i, s) in items.enumerated() where i < be.container.count { be.container[i] = s }
            return be
        }
        func total(_ be: BlockEntity, _ k: String? = nil) -> Int {
            be.container.slots.reduce(0) { $0 + ($1.isEmpty || (k != nil && Items.key($1.item) != k!) ? 0 : $1.count) }
        }
        func centre(_ p: IVec3, dy: Float = 0) -> V3 { V3(Float(p.x) + 0.5, Float(p.y) + dy, Float(p.z) + 0.5) }
        // An item entity lying at `p` (plates, tripwire, hoppers); removed by `clearDrops`.
        var spawned: [ItemEntity] = []
        func dropAt(_ p: IVec3, _ k: String = "cobblestone", dy: Float = 0.05) {
            g.drops.spawn(item(k), at: centre(p, dy: dy), vel: .zero, delay: 0.5)
            if let e = g.drops.items.last { e.pos = centre(p, dy: dy); e.vel = .zero; spawned.append(e) }
        }
        func clearDrops() {
            let ids = Set(spawned.map { ObjectIdentifier($0) })
            g.drops.items.removeAll { ids.contains(ObjectIdentifier($0)) }
            spawned.removeAll()
        }
        var mobsAdded: [Mob] = []
        func mob(_ k: MobKind, _ at: V3) -> Mob { let m = Mob(k, at: at); g.mobs.mobs.append(m); mobsAdded.append(m); return m }
        func comparatorOut(_ p: IVec3) -> Int { rs.comparatorOut[p] ?? 0 }

        func t(_ id: String, missing isMissing: Bool = false, _ body: () -> (Bool, String)) {
            site()
            guard w.chunkAt(o.x, o.z) != nil && w.chunkAt(o.x + 18, o.z + 4) != nil else {
                print("coppertest: FAIL \(id) (pad not loaded: run with --rd 5 or more)"); fail += 1; bad.append(id); return
            }
            let (ok, info) = body()
            clearDrops()
            for m in mobsAdded { g.mobs.mobs.removeAll { $0 === m } }
            mobsAdded.removeAll()
            carts = []
            let tag: String
            switch (ok, isMissing) {
            case (true, false): tag = "PASS"; pass += 1
            case (false, false): tag = "FAIL"; fail += 1; bad.append(id)
            case (false, true): tag = "MISSING"; missing += 1
            case (true, true): tag = "XPASS"; xpass += 1; bad.append(id + " (now works: update copper-parity.md)")
            }
            print("coppertest: \(tag) \(id) \(info)")
        }

        // MARK: Wire
        t("wire.decay") {
            on(P(0), "redstone_block")
            for x in 1...16 { wire(P(x)) }
            tick(30)
            let lv = (1...16).map { st(P($0)) }
            return (lv == (1...16).map { max(0, 16 - $0) }, "levels \(lv)")
        }
        func crossRig() {
            battery(P(5, -1)); put(P(5), "redstone_wire")
            for d in [(1, 0), (-1, 0), (0, 1), (0, -1)] { put(P(5 + d.0, 0, d.1), "redstone_lamp") }
            tick(10)
        }
        func crossLamps() -> [Bool] { [(1, 0), (-1, 0), (0, 1), (0, -1)].map { lit(P(5 + $0.0, 0, $0.1)) } }
        t("wire.cross") {
            crossRig()
            let l = crossLamps()
            return (l.allSatisfy { $0 }, "lamps round a lone wire \(l)")
        }
        t("wire.dot") {
            crossRig()
            use(P(5)); tick(10)
            let l = crossLamps()
            let dot = l.allSatisfy { !$0 } && st(P(5)) & 15 == 15
            use(P(5)); tick(10)
            let back = crossLamps().allSatisfy { $0 }
            wire(P(6, 0, 3)); wire(P(7, 0, 3)); use(P(6, 0, 3))        // a wire with a neighbour does not toggle
            return (dot && back && st(P(6, 0, 3)) < 16, "dot: lamps \(l), wire \(st(P(5)) & 15); cross again \(back); connected wire stays a line \(st(P(6, 0, 3)) < 16)")
        }
        t("wire.points") {
            on(P(0), "redstone_block"); for x in 1...3 { wire(P(x)) }
            put(P(4), "stone"); put(P(5), "redstone_lamp")
            put(P(2, 0, 1), "stone"); put(P(2, 0, 2), "redstone_lamp")
            tick(10)
            return (lit(P(5)) && !lit(P(2, 0, 2)), "ahead lit \(lit(P(5))), side lit \(lit(P(2, 0, 2)))")
        }
        t("wire.redirect") {
            on(P(0), "redstone_block"); wire(P(1)); wire(P(2))
            put(P(3), "stone"); put(P(4), "redstone_lamp")
            tick(10)
            let before = lit(P(4))
            on(P(2, 0, 1), "repeater", 1)                      // facing south: the wire end bends toward it
            tick(10)
            return (before && !lit(P(4)), "lamp before \(before), after a repeater turns the wire \(lit(P(4)))")
        }
        t("wire.climb") {
            on(P(0), "redstone_block"); wire(P(1))
            put(P(2), "stone"); put(P(2, 1), "redstone_wire"); put(P(3), "stone"); put(P(3, 1), "redstone_wire")
            tick(15)
            return (st(P(2, 1)) == 14 && st(P(3, 1)) == 13, "up the block \(st(P(2, 1))), along \(st(P(3, 1)))")
        }
        t("wire.descend") {
            put(P(0), "stone"); battery(P(0, 1)); put(P(1), "stone"); put(P(1, 1), "redstone_wire"); wire(P(2))
            tick(15)
            return (st(P(1, 1)) == 15 && st(P(2)) == 14, "top \(st(P(1, 1))), down \(st(P(2)))")
        }
        t("wire.cut") {
            on(P(0), "redstone_block"); wire(P(1))
            put(P(2), "stone"); put(P(2, 1), "redstone_wire"); put(P(1, 1), "stone")
            tick(15)
            return (st(P(1)) == 15 && st(P(2, 1)) == 0, "lower \(st(P(1))), upper (cut) \(st(P(2, 1)))")
        }
        t("wire.weak") {
            on(P(0), "redstone_block"); wire(P(1)); wire(P(2)); put(P(3), "stone"); wire(P(4))
            put(P(3, 0, 1), "redstone_lamp")
            tick(15)
            return (lit(P(3, 0, 1)) && st(P(4)) == 0, "lamp by the block \(lit(P(3, 0, 1))), wire beyond \(st(P(4)))")
        }
        t("wire.below") {
            put(P(1), "redstone_lamp"); put(P(1, 1), "redstone_wire"); put(P(0), "stone"); battery(P(0, 1))
            tick(10)
            return (lit(P(1)), "lamp under the wire \(lit(P(1)))")
        }
        t("wire.glass") {
            on(P(0), "redstone_block"); on(P(1), "repeater", 3); put(P(2), "glass"); wire(P(3))
            tick(10)
            let g0 = st(P(3))
            put(P(2), "stone"); tick(10)
            return (g0 == 0 && st(P(3)) == 15, "through glass \(g0), through stone \(st(P(3)))")
        }
        t("wire.break") {
            on(P(0), "redstone_block"); for x in 1...5 { wire(P(x)) }
            tick(10)
            air(P(2)); tick(2)
            let lv = (1...5).map { st(P($0)) }
            return (lv == [15, 0, 0, 0, 0], "levels after cutting \(lv)")
        }

        // MARK: Power rules
        t("power.strong") {
            on(P(0), "redstone_block"); on(P(1), "repeater", 3); put(P(2), "stone"); wire(P(3)); wire(P(2, 0, 1)); put(P(2, 1), "redstone_wire")
            tick(10)
            let lv = [st(P(3)), st(P(2, 0, 1)), st(P(2, 1))]
            return (lv == [15, 15, 15], "wires round a strongly powered block \(lv)")
        }
        t("power.weak") {
            on(P(0), "redstone_block"); wire(P(1)); put(P(2), "stone"); wire(P(3))
            on(P(2, 0, 1), "repeater", 1); put(P(2, 0, 2), "redstone_lamp")
            tick(15)
            return (st(P(3)) == 0 && lit(P(2, 0, 2)), "wire by a weakly powered block \(st(P(3))), repeater fed by it \(lit(P(2, 0, 2)))")
        }
        t("power.battery") {
            on(P(1), "redstone_block"); wire(P(2)); put(P(1, 0, 1), "redstone_lamp"); put(P(0), "stone"); wire(P(-1))
            tick(10)
            return (st(P(2)) == 15 && lit(P(1, 0, 1)) && st(P(-1)) == 0, "wire \(st(P(2))), lamp \(lit(P(1, 0, 1))), through stone \(st(P(-1)))")
        }
        t("power.lever") {
            put(P(1), "stone"); put(P(1, 1), "lever"); wire(P(0)); wire(P(2))
            tick(5); use(P(1, 1)); tick(5)
            return (st(P(0)) == 15 && st(P(2)) == 15, "wires beside the lever's block \(st(P(0))) \(st(P(2)))")
        }
        t("power.components") {
            on(P(0), "redstone_block"); on(P(1), "repeater", 3); put(P(2), "redstone_lamp"); wire(P(3))
            tick(10)
            return (lit(P(2)) && st(P(3)) == 15, "lamp \(lit(P(2))), wire beyond the strongly powered lamp \(st(P(3)))")
        }

        // MARK: Signal torch
        t("torch.invert") {
            put(P(1), "stone"); put(P(1, 1), "redstone_torch"); on(P(0), "repeater", 3)
            tick(10)
            let a = st(P(1, 1))
            on(P(-1), "redstone_block"); tick(10)
            return (a == 0 && st(P(1, 1)) == 1, "torch state unpowered \(a), powered \(st(P(1, 1)))")
        }
        t("torch.delay") {
            put(P(1), "stone"); put(P(1, 1), "redstone_torch"); put(P(1, 0, 1), "lever", 5)
            tick(5); use(P(1, 0, 1))
            let n = until(10) { st(P(1, 1)) == 1 }
            return (n == 3, "torch off on tick \(n) (2 ticks after the engine sees the lever)")
        }
        t("torch.above") {
            put(P(1), "stone"); put(P(1, 1), "redstone_torch"); put(P(1, 2), "stone"); put(P(2, 1), "stone"); put(P(2, 2), "redstone_wire")
            tick(10)
            return (st(P(2, 2)) == 15, "wire beside the block over the torch \(st(P(2, 2)))")
        }
        t("torch.side") {
            put(P(1), "stone"); put(P(1, 1), "redstone_torch"); put(P(2, 1), "redstone_lamp")
            put(P(0, 1), "stone"); put(P(-1), "stone"); put(P(-1, 1), "redstone_wire")
            tick(10)
            return (lit(P(2, 1)) && st(P(-1, 1)) == 0, "lamp beside \(lit(P(2, 1))), wire behind a block beside \(st(P(-1, 1)))")
        }
        t("torch.wall") {
            put(P(1), "stone"); put(P(2), "redstone_torch", 5); on(P(0), "repeater", 3)
            tick(10)
            let a = st(P(2))
            on(P(-1), "redstone_block"); tick(10)
            return (a == 5 && st(P(2)) == 9, "wall torch unpowered \(a), powered \(st(P(2)))")
        }
        t("torch.burnout") {
            put(P(1), "stone"); put(P(1, 1), "redstone_torch"); put(P(1, 0, 1), "lever", 5)
            tick(5)
            for _ in 0..<10 { use(P(1, 0, 1)); tick(3); use(P(1, 0, 1)); tick(3) }
            tick(4)
            let out = st(P(1, 1)) == 1
            tick(30)
            let still = st(P(1, 1)) == 1
            let back = until(250) { st(P(1, 1)) == 0 }
            return (out && still && back > 0, "burnt out \(out), still off 30 ticks on \(still), relit after \(back)")
        }

        // MARK: Repeater
        t("repeater.delay") {
            var got: [Int] = []
            for d in 0..<4 {
                let z = d * 2 - 3
                on(P(0, 0, z), "lever"); on(P(1, 0, z), "repeater", 3 + d * 4); put(P(2, 0, z), "redstone_lamp")
                tick(5); use(P(0, 0, z))
                got.append(until(20) { lit(P(2, 0, z)) } - 1)
            }
            use(P(1, 0, 3))
            let cycled = (st(P(1, 0, 3)) >> 2) & 3
            return (got == [2, 4, 6, 8] && cycled == 0, "delays \(got) game ticks, delay 4 right-clicked -> \(cycled + 1)")
        }
        t("repeater.refresh") {
            on(P(0), "redstone_block"); for x in 1...15 { wire(P(x)) }; on(P(16), "repeater", 3); wire(P(17))
            tick(40)
            return (st(P(15)) == 1 && st(P(17)) == 15, "in \(st(P(15))), out \(st(P(17)))")
        }
        t("repeater.oneway") {
            on(P(1), "repeater", 3); on(P(2), "redstone_block"); wire(P(0))
            tick(10)
            return (st(P(0)) == 0 && st(P(1)) & 16 == 0, "wire behind \(st(P(0))), repeater powered \(st(P(1)) & 16 != 0)")
        }
        t("repeater.lock") {
            on(P(2), "repeater", 1); on(P(2, 0, -1), "lever"); put(P(2, 0, 1), "redstone_lamp")
            on(P(1), "repeater", 3); on(P(0), "lever")
            tick(5); use(P(0)); tick(10)
            let locked = st(P(2)) & 32 != 0
            use(P(2, 0, -1)); tick(10)
            let held = !lit(P(2, 0, 1))
            use(P(0)); tick(10)
            return (locked && held && lit(P(2, 0, 1)), "locked \(locked), ignores input while locked \(held), follows it after \(lit(P(2, 0, 1)))")
        }
        t("repeater.extend") {
            on(P(1), "repeater", 3 + 12); tick(3)
            battery(P(0)); tick(1); air(P(0))
            var lenOn = 0
            for _ in 0..<30 { tick(); if st(P(1)) & 16 != 0 { lenOn += 1 } }
            return (lenOn == 8, "a 1-tick pulse into a delay-4 repeater comes out \(lenOn) ticks long")
        }
        t("repeater.side") {
            on(P(1), "repeater", 3); put(P(2), "redstone_lamp"); wire(P(1, 0, 1)); on(P(1, 0, 2), "redstone_block")
            tick(10)
            return (st(P(1, 0, 1)) == 15 && st(P(1)) & 16 == 0 && !lit(P(2)), "side wire \(st(P(1, 0, 1))), repeater powered \(st(P(1)) & 16 != 0)")
        }

        // MARK: Comparator
        // Comparator at (6,0,0) facing east: n wires behind it from a battery, m wires to its south side.
        func comparatorRig(rear n: Int, side m: Int, sub: Bool) -> Int {
            site()
            let c = P(6)
            on(c, "comparator", 3 + (sub ? 4 : 0))
            for k in 1...n { wire(P(6 - k)) }
            on(P(6 - n - 1), "redstone_block")
            if m > 0 { for k in 0..<m { wire(P(6 + k, 0, 1)) }; on(P(6 + m, 0, 1), "redstone_block") }
            tick(40)
            return comparatorOut(c)
        }
        t("comparator.compare") {
            let a = comparatorRig(rear: 6, side: 11, sub: false), b = comparatorRig(rear: 6, side: 4, sub: false), c = comparatorRig(rear: 6, side: 6, sub: false)
            return (a == 10 && b == 0 && c == 10, "rear 10 vs side 5 -> \(a), vs 12 -> \(b), vs 10 -> \(c)")
        }
        t("comparator.subtract") {
            let a = comparatorRig(rear: 4, side: 11, sub: true), b = comparatorRig(rear: 4, side: 2, sub: true)
            return (a == 7 && b == 0, "12 - 5 -> \(a), 12 - 14 -> \(b)")
        }
        t("comparator.container") {
            var got: [Int] = []
            for (z, stacks) in [(-3, 0), (-1, 13), (1, 27)] {
                var items = [item("cobblestone", 1)]
                if stacks > 0 { items = Array(repeating: item("cobblestone", 64), count: stacks) }
                _ = entity(P(0, 0, z), "chest", .chest, items)
                on(P(1, 0, z), "comparator", 3)
            }
            tick(6)
            got = [-3, -1, 1].map { comparatorOut(P(1, 0, $0)) }
            return (got == [1, 7, 15], "1 item, 13 of 27 stacks, full -> \(got)")
        }
        t("comparator.through") {
            _ = entity(P(0), "chest", .chest, Array(repeating: item("cobblestone", 64), count: 27))
            put(P(1), "stone"); on(P(2), "comparator", 3)
            tick(6)
            return (comparatorOut(P(2)) == 15, "full chest through a block -> \(comparatorOut(P(2)))")
        }
        t("comparator.special") {
            var got: [String: Int] = [:]
            let rows: [(String, Int, Int)] = [("composter", 5, 5), ("cake", 0, 14), ("respawn_anchor", 4, 15), ("end_portal_frame", 1, 15)]
            for (i, r) in rows.enumerated() where Blocks.has(r.0) {
                let z = i * 2 - 3
                put(P(0, 0, z), r.0, r.1); on(P(1, 0, z), "comparator", 3)
            }
            tick(6)
            var ok = true
            for (i, r) in rows.enumerated() where Blocks.has(r.0) {
                let v = comparatorOut(P(1, 0, i * 2 - 3)); got[r.0] = v; if v != r.2 { ok = false }
            }
            return (ok, "\(got.sorted { $0.key < $1.key })")
        }
        t("comparator.update") {
            let be = entity(P(0), "chest", .chest)
            on(P(1), "comparator", 3)
            tick(6)
            let a = comparatorOut(P(1))
            be.container[0] = item("cobblestone", 64)          // changed directly, as a menu or a mob would
            tick(6)
            return (a == 0 && comparatorOut(P(1)) > 0, "empty \(a), after items appear \(comparatorOut(P(1)))")
        }
        t("comparator.delay") {
            on(P(0), "lever"); on(P(1), "comparator", 3)
            tick(5); use(P(0))
            let n = until(10) { comparatorOut(P(1)) > 0 }
            return (n == 3, "output on tick \(n) (2 ticks after the engine sees the lever)")
        }
        t("comparator.frame") {
            guard Blocks.has("item_frame") else { return (false, "no item frame block") }
            let f = entity(P(0), "item_frame", .frame)
            on(P(1), "comparator", 3); tick(4)
            let empty = comparatorOut(P(1))
            f.container[0] = item("cobblestone"); f.delay = 2
            tick(6)
            return (empty == 0 && comparatorOut(P(1)) == 3, "empty \(empty), item turned twice \(comparatorOut(P(1)))")
        }
        t("comparator.lectern") {
            var book = item("written_book"); book.pages = ["a", "b", "c", "d", "e"]
            let be = entity(P(0), "lectern", .lectern, [book]); be.delay = 2
            on(P(1), "comparator", 3)
            put(P(0, 0, 3), "jukebox"); on(P(1, 0, 3), "comparator", 3)
            g.jukeboxes.append(JukeboxPlayer(P(0, 0, 3), "ward"))
            tick(6)
            let a = comparatorOut(P(1)), b = comparatorOut(P(1, 0, 3))
            g.jukeboxes.removeAll { $0.pos == P(0, 0, 3) }
            return (a == 8 && b == 10, "lectern page 3 of 5 -> \(a), jukebox playing disc 10 -> \(b)")
        }

        // MARK: Observer
        t("observer.pulse") {
            put(P(1), "observer", 4); tick(5)
            put(P(0), "stone")
            var seq: [Bool] = []
            for _ in 0..<6 { tick(); seq.append(st(P(1)) >= 6) }
            return (seq == [false, true, true, false, false, false], "on per tick \(seq.map { $0 ? 1 : 0 })")
        }
        t("observer.strong") {
            put(P(1), "observer", 4); put(P(2), "stone"); wire(P(3)); tick(5)
            put(P(0), "stone")
            var best = 0
            for _ in 0..<6 { tick(); best = max(best, st(P(3))) }
            return (best == 15, "wire behind the observer's block peaks at \(best)")
        }
        t("observer.state") {
            put(P(0), "redstone_lamp"); on(P(-1), "lever"); put(P(1), "observer", 4); tick(5)
            use(P(-1))
            var fired = false
            for _ in 0..<6 { tick(); if st(P(1)) >= 6 { fired = true } }
            return (fired && lit(P(0)), "observer saw the lamp light \(fired)")
        }
        t("observer.clock") {
            put(P(1), "observer", 5); put(P(2), "observer", 4)
            var edges = 0, was = false
            for _ in 0..<40 { tick(); let now = st(P(1)) >= 6; if now && !was { edges += 1 }; was = now }
            return (edges >= 5, "\(edges) pulses in 40 ticks")
        }

        // MARK: Pistons
        t("piston.push") {
            put(P(1), "piston", 5); put(P(2), "cobblestone"); on(P(0), "lever")
            tick(3); use(P(0)); tick(3)
            let out = key(P(3)) == "cobblestone" && key(P(2)) == "piston_head" && st(P(1)) == 11
            use(P(0)); tick(3)
            let back = st(P(1)) == 5 && blk(P(2)) == AIR && key(P(3)) == "cobblestone"
            return (out && back, "extended and pushed \(out), retracted \(back)")
        }
        func pushRow(_ n: Int) -> Bool {
            site()
            put(P(0), "piston", 5); for x in 1...n { put(P(x), "cobblestone") }; on(P(-1), "lever")
            tick(3); use(P(-1)); tick(3)
            return st(P(0)) == 11 && key(P(n + 1)) == "cobblestone"
        }
        t("piston.limit") {
            let a = pushRow(12), b = pushRow(13)
            return (a && !b, "12 blocks pushed \(a), 13 pushed \(b)")
        }
        t("piston.immovable") {
            var got: [String: Bool] = [:]
            for (z, k) in [(-3, "obsidian"), (0, "bedrock"), (3, "chest")] {
                put(P(0, 0, z), "piston", 5); on(P(-1, 0, z), "lever")
                if k == "chest" { _ = entity(P(1, 0, z), "chest", .chest) } else { put(P(1, 0, z), k) }
            }
            tick(3)
            for (z, k) in [(-3, "obsidian"), (0, "bedrock"), (3, "chest")] { use(P(-1, 0, z)); tick(3); got[k] = st(P(0, 0, z)) == 5 && key(P(1, 0, z)) == k }
            return (got.values.allSatisfy { $0 }, "stayed put \(got.sorted { $0.key < $1.key })")
        }
        t("piston.fragile") {
            put(P(0), "piston", 5); put(P(1), "cobblestone"); put(P(2), "poppy"); on(P(-1), "lever")
            tick(3)
            let n0 = g.drops.items.count
            use(P(-1)); tick(3)
            let dropped = g.drops.items.count > n0
            if dropped, let e = g.drops.items.last { spawned.append(e) }
            return (key(P(2)) == "cobblestone" && dropped, "flower broken and dropped \(dropped), block moved in \(key(P(2)))")
        }
        t("piston.sticky") {
            put(P(1), "sticky_piston", 5); put(P(2), "cobblestone"); on(P(0), "lever")
            tick(3); use(P(0)); tick(3)
            let out = key(P(3)) == "cobblestone"
            use(P(0)); tick(3)
            return (out && key(P(2)) == "cobblestone" && blk(P(3)) == AIR, "pushed \(out), pulled back \(key(P(2)))")
        }
        t("piston.stickyimmovable") {
            put(P(1), "sticky_piston", 5); put(P(3), "obsidian"); on(P(0), "lever")
            tick(3); use(P(0)); tick(3)
            let out = st(P(1)) == 11
            use(P(0)); tick(3)
            return (out && key(P(3)) == "obsidian" && blk(P(2)) == AIR, "extended \(out), obsidian left in place \(key(P(3)))")
        }
        t("piston.slime") {
            put(P(1), "piston", 5); put(P(2), "slime_block"); put(P(2, 1), "cobblestone"); put(P(2, 0, 1), "cobblestone"); on(P(0), "lever")
            tick(3); use(P(0)); tick(3)
            let ok = key(P(3)) == "slime_block" && key(P(3, 1)) == "cobblestone" && key(P(3, 0, 1)) == "cobblestone" && blk(P(2, 1)) == AIR
            return (ok, "slime and both stuck blocks moved \(ok)")
        }
        t("piston.honey") {
            put(P(1), "piston", 5); put(P(2), "slime_block"); put(P(2, 0, 1), "honey_block"); on(P(0), "lever")
            tick(3); use(P(0)); tick(3)
            return (key(P(3)) == "slime_block" && key(P(2, 0, 1)) == "honey_block", "slime moved \(key(P(3))), honey stayed \(key(P(2, 0, 1)))")
        }
        t("piston.face") {
            put(P(1), "piston", 5); put(P(2), "stone"); on(P(3), "repeater", 2); on(P(4), "redstone_block")
            tick(10)
            return (st(P(1)) == 5, "powered only through its face: extended \(st(P(1)) >= 6)")
        }
        func qcRig() -> (Bool, Bool) {
            put(P(1), "piston", 5); tick(3)
            battery(P(1, 2)); tick(5)
            let waited = st(P(1)) == 5
            put(P(1, 0, -1), "stone"); tick(3)
            return (waited, st(P(1)) == 11)
        }
        t("piston.qc") {
            let r = qcRig()
            return (r.1, "power at the space above + an update extends it \(r.1)")
        }
        t("piston.bud") {
            let r = qcRig()
            return (r.0 && r.1, "waits for an update \(r.0), then extends \(r.1)")
        }
        t("piston.entities") {
            put(P(1), "piston", 5); put(P(2), "cobblestone"); on(P(0), "lever")
            tick(3)
            let pig = mob(.pig, centre(P(3)))                  // in the path of the pushed block
            let x0 = pig.pos.x
            use(P(0)); tick(3)
            return (abs(pig.pos.x - x0 - 1) < 0.01, String(format: "pig in front of the block shoved %.2f", pig.pos.x - x0))
        }

        // MARK: Hoppers
        t("hopper.rate") {
            _ = entity(P(1, 1), "chest", .chest, [item("cobblestone", 64)])
            _ = entity(P(1), "hopper", .hopper); put(P(1), "hopper", 4)
            let out = entity(P(2), "chest", .chest)
            tick(160)
            let n = total(out)
            return (n >= 18 && n <= 20, "\(n) items in 8 s (2.5/s = 19-20)")
        }
        t("hopper.push") {
            _ = entity(P(1), "hopper", .hopper, [item("cobblestone", 1)]); put(P(1), "hopper", 4)
            let out = entity(P(2), "chest", .chest)
            tick(10)
            return (total(out) == 1, "chest beside got \(total(out))")
        }
        t("hopper.pull") {
            let src = entity(P(1, 1), "chest", .chest, [item("cobblestone", 3)])
            let h = entity(P(1), "hopper", .hopper)
            tick(30)
            return (total(h) == 3 && total(src) == 0, "hopper pulled \(total(h)) from the chest above")
        }
        t("hopper.items") {
            let h = entity(P(1), "hopper", .hopper)
            dropAt(P(1), dy: 1.2)
            tick(10)
            return (total(h) == 1, "hopper picked up \(total(h)) dropped item")
        }
        t("hopper.lock") {
            let h = entity(P(1), "hopper", .hopper); on(P(0), "lever")
            tick(2); use(P(0)); tick(2)
            let src = entity(P(1, 1), "chest", .chest, [item("cobblestone", 3)])
            tick(30)
            let locked = st(P(1)) >= 5 && total(h) == 0
            use(P(0)); tick(30)
            return (locked && total(h) > 0 && total(src) < 3, "locked while powered \(locked), runs again after \(total(h))")
        }
        t("hopper.furnace") {
            let f = entity(P(1), "furnace", .furnace)
            f.container[2] = item("stone", 1)
            _ = entity(P(1, 1), "hopper", .hopper, [item("cobblestone", 1)])
            _ = entity(P(0), "hopper", .hopper, [item("coal", 1)]); put(P(0), "hopper", 4)
            let below = entity(P(1, -1), "hopper", .hopper)
            tick(20)
            let a = Items.key(f.container[0].item), b = Items.key(f.container[1].item)
            return (a == "cobblestone" && b == "coal" && total(below, "stone") == 1, "input \(a), fuel \(b), output pulled below \(total(below, "stone"))")
        }
        t("hopper.chain") {
            _ = entity(P(1), "hopper", .hopper, [item("cobblestone", 2)]); put(P(1), "hopper", 4)
            _ = entity(P(2), "hopper", .hopper); put(P(2), "hopper", 4)
            let out = entity(P(3), "chest", .chest)
            tick(40)
            return (total(out) == 2, "chest at the end got \(total(out))")
        }

        // MARK: Dispensers and droppers
        func dispenser(_ p: IVec3, _ k: String, _ items: [ItemStack], dir: Int = 5) -> BlockEntity {
            let be = entity(p, k, .dispenser, items); put(p, k, dir); return be
        }
        t("dispenser.edge") {
            let be = dispenser(P(1), "dropper", [item("cobblestone", 5)]); on(P(0), "lever")
            tick(3)
            let n0 = g.drops.items.count
            use(P(0))
            let n = until(10) { total(be) < 5 }
            tick(20)
            let once = total(be) == 4
            use(P(0)); tick(2); use(P(0)); tick(6)
            for e in g.drops.items.suffix(max(0, g.drops.items.count - n0)) { spawned.append(e) }
            return (n == 5 && once && total(be) == 3, "fired on tick \(n), once per pulse \(once), again on the next pulse \(total(be) == 3)")
        }
        t("dispenser.qc") {
            let be = dispenser(P(1), "dropper", [item("cobblestone", 2)]); tick(3)
            let n0 = g.drops.items.count
            battery(P(1, 2)); tick(6)
            let waited = total(be) == 2
            put(P(1, 0, -1), "stone"); tick(6)
            for e in g.drops.items.suffix(max(0, g.drops.items.count - n0)) { spawned.append(e) }
            return (waited && total(be) == 1, "waits for an update \(waited), fires after \(total(be) == 1)")
        }
        // Fires the dispenser at P(1) once (a battery beside it) and returns how many item entities it made.
        func pulse(_ p: IVec3) -> Int {
            let n0 = g.drops.items.count
            battery(p + IVec3(0, 0, -1)); tick(6); air(p + IVec3(0, 0, -1)); tick(2)
            let made = g.drops.items.count - n0
            for e in g.drops.items.suffix(max(0, made)) { spawned.append(e) }
            return made
        }
        t("dropper.drop") {
            let be = dispenser(P(1), "dropper", [item("cobblestone", 1)]); tick(2)
            let made = pulse(P(1))
            let e = spawned.last
            let ahead = e.map { $0.pos.x > Float(P(1).x) + 1 } ?? false
            return (made == 1 && total(be) == 0 && ahead, "dropped \(made) item out of the front \(ahead)")
        }
        t("dropper.insert") {
            _ = dispenser(P(1), "dropper", [item("cobblestone", 1)]); let c = entity(P(2), "chest", .chest); tick(2)
            let made = pulse(P(1))
            return (total(c) == 1 && made == 0, "chest in front got \(total(c))")
        }
        t("dispenser.arrow") {
            _ = dispenser(P(1), "dispenser", [item("arrow", 1)]); tick(2)
            let n0 = g.projectiles.arrows.count
            _ = pulse(P(1))
            let shot = g.projectiles.arrows.count - n0
            if shot > 0 { g.projectiles.arrows.removeLast(shot) }
            return (shot == 1, "arrows shot \(shot)")
        }
        t("dispenser.bucket") {
            let be = dispenser(P(1), "dispenser", [item("water_bucket", 1)]); tick(2)
            _ = pulse(P(1))
            let placed = blk(P(2)) == WATER && Items.key(be.container[0].item) == "bucket"
            _ = pulse(P(1))
            let back = blk(P(2)) != WATER && Items.key(be.container[0].item) == "water_bucket"
            air(P(2))
            return (placed && back, "water placed \(placed), picked up again \(back)")
        }
        t("dispenser.tnt") {
            _ = dispenser(P(1), "dispenser", [item("tnt", 1)]); tick(2)
            let n0 = g.tnts.list.count
            _ = pulse(P(1))
            let lit = g.tnts.list.count - n0
            if lit > 0 { g.tnts.list.removeLast(lit) }
            return (lit == 1, "primed \(lit)")
        }
        t("dispenser.bonemeal") {
            _ = dispenser(P(1), "dispenser", [item("bone_meal", 1)]); put(P(2, -1), "farmland"); put(P(2), "wheat"); tick(2)
            _ = pulse(P(1))
            return (key(P(2)) == "wheat" && st(P(2)) > 0, "wheat stage \(st(P(2)))")
        }
        t("dispenser.firecharge") {
            _ = dispenser(P(1), "dispenser", [item("fire_charge", 1)]); tick(2)
            let n0 = g.projectiles.fireballs.count
            _ = pulse(P(1))
            let shot = g.projectiles.fireballs.count - n0
            if shot > 0 { g.projectiles.fireballs.removeLast(shot) }
            return (shot == 1, "fireballs \(shot)")
        }
        t("dispenser.armor") {
            let helm = Items.id("iron_helmet")
            guard let sl = Items.def(helm).armorSlot?.rawValue else { return (false, "no helmet slot") }
            _ = dispenser(P(1), "dispenser", [ItemStack(helm, 1)]); tick(2)
            let keepPos = g.player.pos, keepArmor = g.inventory.armor[sl]
            g.inventory.armor[sl] = .empty
            g.player.pos = centre(P(2))
            _ = pulse(P(1))
            let worn = g.inventory.armor[sl].item == helm
            g.inventory.armor[sl] = keepArmor; g.player.pos = keepPos
            return (worn, "helmet put on the player in front \(worn)")
        }
        t("dispenser.throwables") {
            var got: [String: Bool] = [:]
            for k in ["snowball", "egg", "experience_bottle"] where Items.has(k) {
                site()
                _ = dispenser(P(1), "dispenser", [item(k, 1)]); tick(2)
                let n0 = g.projectiles.fireballs.count
                let made = pulse(P(1))
                let shot = g.projectiles.fireballs.count - n0
                if shot > 0 { g.projectiles.fireballs.removeLast(shot) }
                got[k] = shot == 1 && made == 0
            }
            return (!got.isEmpty && got.values.allSatisfy { $0 }, "thrown \(got.sorted { $0.key < $1.key })")
        }
        t("dispenser.place") {
            on(P(2), "rail", 1)
            _ = dispenser(P(1), "dispenser", [item("minecart", 1)]); tick(2)
            let n0 = g.mobs.mobs.count
            _ = pulse(P(1))
            let cart = g.mobs.mobs.count > n0 && g.mobs.mobs.last?.kind == .minecart
            if g.mobs.mobs.count > n0, let m = g.mobs.mobs.last { mobsAdded.append(m) }
            site()
            _ = dispenser(P(1), "dispenser", [item("pig_spawn_egg", 1)]); tick(2)
            let n1 = g.mobs.mobs.count
            _ = pulse(P(1))
            let pig = g.mobs.mobs.count > n1 && g.mobs.mobs.last?.kind == .pig
            if g.mobs.mobs.count > n1, let m = g.mobs.mobs.last { mobsAdded.append(m) }
            return (cart && pig, "minecart onto the rail \(cart), spawn egg hatched \(pig)")
        }
        t("dispenser.more") {
            // Shears on a sheep in front.
            _ = dispenser(P(1), "dispenser", [item("shears", 1)]); tick(2)
            let sheep = mob(.sheep, centre(P(2)))
            _ = pulse(P(1))
            let shorn = sheep.sheared
            // Glass bottle from water in front.
            site()
            let be = dispenser(P(1), "dispenser", [item("glass_bottle", 1)]); putB(P(2), WATER); tick(2)
            _ = pulse(P(1))
            let filled = total(be, Potions.item(0, "water").map { Items.key($0) } ?? "-") == 1
            air(P(2))
            // Boat onto water.
            site()
            _ = dispenser(P(1), "dispenser", [item("oak_boat", 1)]); putB(P(2), WATER); tick(2)
            let n0 = g.mobs.mobs.count
            _ = pulse(P(1))
            let boat = g.mobs.mobs.count > n0 && g.mobs.mobs.last?.kind == .boat
            if boat, let m = g.mobs.mobs.last { mobsAdded.append(m) }
            air(P(2))
            // Shulker box placed with its contents.
            site()
            var box = item("shulker_box", 1); box.contents = [item("cobblestone", 5)]
            _ = dispenser(P(1), "dispenser", [box]); tick(2)
            _ = pulse(P(1))
            let placed = key(P(2)) == "shulker_box" && w.blockEntities[P(2)].map { total($0) } == 5
            return (shorn && filled && boat && placed, "sheared \(shorn), bottle filled \(filled), boat on water \(boat), shulker box placed \(placed)")
        }

        // MARK: Switches and plates
        t("lever.toggle") {
            on(P(0), "lever"); put(P(1), "redstone_lamp")
            tick(2); use(P(0)); tick(1)
            let a = lit(P(1))
            use(P(0)); tick(6)
            return (a && !lit(P(1)) && st(P(0)) < 12, "on \(a), off \(!lit(P(1)))")
        }
        t("button.stone") {
            on(P(0), "stone_button"); tick(2); use(P(0))
            let n = until(40) { st(P(0)) < 12 }
            return (n == 20, "released after \(n) ticks")
        }
        t("button.wood") {
            on(P(0), "oak_button"); tick(2); use(P(0))
            let n = until(50) { st(P(0)) < 12 }
            return (n == 30, "released after \(n) ticks")
        }
        t("button.arrow") {
            put(P(3), "stone"); put(P(2), "oak_button", 6)       // on the west face of the stone
            tick(2)
            let a = g.projectiles.shoot(from: centre(P(0), dy: 0.55), dir: V3(1, 0, 0), speed: 20, fromPlayer: false, damage: 2)
            for _ in 0..<20 where !a.stuck { g.projectiles.update(0.05, game: g) }
            tick(2)
            let pressed = st(P(2)) >= 12
            g.projectiles.arrows.removeAll { $0 === a }
            return (a.stuck && pressed, "arrow stuck \(a.stuck), button pressed \(pressed)")
        }
        t("plate.arrow") {
            on(P(1), "oak_pressure_plate"); tick(2)
            let a = g.projectiles.shoot(from: centre(P(1), dy: 2.5), dir: V3(0, -1, 0), speed: 20, fromPlayer: false, damage: 2)
            for _ in 0..<20 where !a.stuck { g.projectiles.update(0.05, game: g) }
            tick(2)
            let pressed = st(P(1)) == 1
            g.projectiles.arrows.removeAll { $0 === a }
            return (a.stuck && pressed, "arrow stuck \(a.stuck), wooden plate pressed \(pressed)")
        }
        t("plate.wood") {
            on(P(1), "oak_pressure_plate"); tick(2)
            dropAt(P(1)); tick(2)
            return (st(P(1)) == 1, "an item presses a wooden plate \(st(P(1)) == 1)")
        }
        t("plate.stone") {
            on(P(1), "stone_pressure_plate"); tick(2)
            dropAt(P(1)); tick(3)
            let item = st(P(1))
            _ = mob(.pig, centre(P(1), dy: 0.0625)); tick(3)
            return (item == 0 && st(P(1)) == 1, "item \(item), pig \(st(P(1)))")
        }
        t("plate.light") {
            on(P(1), "light_weighted_pressure_plate"); tick(2)
            for _ in 0..<3 { dropAt(P(1)) }
            tick(3)
            return (st(P(1)) == 3, "3 items -> \(st(P(1)))")
        }
        t("plate.heavy") {
            on(P(1), "heavy_weighted_pressure_plate"); tick(2)
            for _ in 0..<3 { dropAt(P(1)) }
            tick(3)
            let a = st(P(1))
            for _ in 0..<8 { dropAt(P(1)) }
            tick(3)
            return (a == 1 && st(P(1)) == 2, "3 items -> \(a), 11 items -> \(st(P(1)))")
        }
        t("plate.release") {
            on(P(1), "oak_pressure_plate"); tick(2)
            dropAt(P(1)); tick(2)
            clearDrops()
            let n = until(40) { st(P(1)) == 0 }
            return (n >= 19 && n <= 21, "released \(n) ticks after the item left")
        }
        t("tripwire.trip") {
            put(P(0), "stone"); put(P(1), "tripwire_hook", 3); for x in 2...4 { put(P(x), "tripwire") }; put(P(5), "tripwire_hook", 2)
            wire(P(-1)); tick(4)
            dropAt(P(3)); tick(4)
            return (st(P(1)) >= 4 && st(P(5)) >= 4 && st(P(-1)) == 15, "hooks pulled \(st(P(1)) >= 4) \(st(P(5)) >= 4), block behind powers wire \(st(P(-1)))")
        }
        t("tripwire.unarmed") {
            put(P(0), "stone"); put(P(1), "tripwire_hook", 3); for x in 2...4 { put(P(x), "tripwire") }
            tick(4); dropAt(P(3)); tick(4)
            return (st(P(1)) < 4, "single hook pulled \(st(P(1)) >= 4)")
        }

        // MARK: Sensors
        func setDay(_ f: Double) { g.time = (floor(g.time / DAY_LENGTH) + f) * DAY_LENGTH }
        t("daylight.day") {
            on(P(1), "daylight_detector")
            setDay(0.25); tick(41)
            let noon = st(P(1)) & 15
            setDay(0.75); tick(41)
            let night = st(P(1)) & 15
            return (noon >= 13 && night == 0, String(format: "noon %d (daylight %.2f), midnight %d", noon, g.daylight, night))
        }
        t("daylight.inverted") {
            on(P(1), "daylight_detector"); use(P(1))
            setDay(0.75); tick(41)
            let night = st(P(1)) & 15
            setDay(0.25); tick(41)
            let noon = st(P(1)) & 15
            return (st(P(1)) >= 16 && night == 15 && noon <= 2, "inverted: midnight \(night), noon \(noon)")
        }
        t("target.hit") {
            put(P(1), "target"); wire(P(2)); tick(2)
            rs.hitTarget(P(1), at: V3(Float(P(1).x), Float(P(1).y) + 0.5, Float(P(1).z) + 0.5), arrow: true)
            tick(2)
            let centreHit = st(P(1)), w1 = st(P(2))
            tick(8)
            let reset = st(P(1))
            rs.hitTarget(P(1), at: V3(Float(P(1).x), Float(P(1).y) + 0.9, Float(P(1).z) + 0.5), arrow: true)
            let edge = st(P(1))
            return (centreHit == 15 && w1 == 15 && reset == 0 && edge >= 1 && edge <= 5, "centre \(centreHit) (wire \(w1)), reset \(reset), near the edge \(edge)")
        }
        t("trapped.chest") {
            put(P(1), "stone"); _ = entity(P(1, 1), "trapped_chest", .chest); wire(P(2)); put(P(0), "stone"); put(P(0, 1), "redstone_wire")
            tick(2); rs.setTrapped(P(1, 1), 1); tick(3)
            let below = st(P(2)), side = st(P(0, 1))
            rs.setTrapped(P(1, 1), 0); tick(3)
            return (below == 1 && side == 1 && st(P(2)) == 0, "one viewer: beside \(side), through the block below \(below), closed \(st(P(2)))")
        }
        t("murk.sensor") {
            on(P(1), "sculk_sensor"); wire(P(2)); tick(2)
            rs.vibrate(at: centre(P(1), dy: 0.5) + V3(0, 0, 4))
            tick(2)
            let a = st(P(2))
            tick(32)
            return (a == 8 && st(P(2)) == 0, "4 blocks away -> sensor 8, wire \(a); after 30 ticks \(st(P(2)))")
        }
        t("lectern.pulse") {
            var book = item("written_book"); book.pages = ["a", "b", "c"]
            let be = entity(P(1), "lectern", .lectern, [book]); be.delay = 0
            wire(P(2)); tick(3)
            let menu = BookMenu(game: g, stack: book, source: .lectern(be))
            menu.buttonPressed(1)                              // next page
            var seq: [Int] = []
            for _ in 0..<4 { tick(); seq.append(st(P(2))) }
            return (Int(be.delay) == 1 && seq.contains(15) && seq.last == 0, "wire while turning a page \(seq)")
        }

        // MARK: Outputs
        t("lamp.timing") {
            on(P(0), "lever"); put(P(1), "redstone_lamp"); tick(2)
            use(P(0)); let a = until(10) { lit(P(1)) }
            use(P(0)); let b = until(10) { !lit(P(1)) }
            return (a == 1 && b == 5, "lit on tick \(a), dark on tick \(b) (4 ticks after the engine sees it)")
        }
        t("note.pitch") {
            on(P(1), "note_block")
            var seq: [Int] = []
            for _ in 0..<25 { use(P(1)); seq.append(st(P(1))) }
            return (seq == Array(1..<25) + [0], "25 pitches then back to \(seq.last ?? -1)")
        }
        t("note.instrument") {
            let rows: [(String, Int)] = [("dirt", 0), ("oak_planks", 1), ("sand", 2), ("glass", 3), ("stone", 4), ("gold_block", 5), ("clay", 6), ("white_wool", 8)]
            var got: [String: Int] = [:]
            var ok = true
            for (i, r) in rows.enumerated() {
                let p = P(i * 2, 1)
                put(p + IVec3(0, -1, 0), r.0); put(p, "note_block")
                rs.lastNote = nil; use(p)
                let inst = rs.lastNote?.0 ?? -1
                got[r.0] = inst; if inst != r.1 { ok = false }
            }
            return (ok, "\(got.sorted { $0.key < $1.key })")
        }
        t("note.blocked") {
            put(P(1), "dirt"); put(P(1, 1), "note_block"); put(P(1, 2), "stone")
            rs.lastNote = nil; use(P(1, 1))
            return (rs.lastNote == nil, "played under a block \(rs.lastNote != nil)")
        }
        t("note.edge") {
            on(P(1), "note_block"); on(P(0), "lever"); tick(2)
            let n0 = rs.notesPlayed
            use(P(0)); tick(20)
            let once = rs.notesPlayed - n0
            use(P(0)); tick(2); use(P(0)); tick(2)
            return (once == 1 && rs.notesPlayed - n0 == 2, "plays per rising edge: \(once) then \(rs.notesPlayed - n0)")
        }
        t("door.iron") {
            on(P(1), "iron_door", 0); put(P(1, 1), "iron_door", 8); on(P(0), "lever"); tick(2)
            use(P(0)); tick(2)
            let open = st(P(1)) & 4 != 0 && st(P(1, 1)) & 4 != 0
            use(P(0)); tick(2)
            return (open && st(P(1)) & 4 == 0, "opened \(open), closed \(st(P(1)) & 4 == 0)")
        }
        t("door.trapgate") {
            put(P(1, 0, -2), "oak_trapdoor"); on(P(0, 0, -2), "lever")
            on(P(1, 0, 2), "oak_fence_gate"); on(P(0, 0, 2), "lever"); tick(2)
            use(P(0, 0, -2)); use(P(0, 0, 2)); tick(2)
            let a = st(P(1, 0, -2)) & 4 != 0, b = st(P(1, 0, 2)) & 4 != 0
            return (a && b, "trapdoor open \(a), gate open \(b)")
        }
        t("tnt.power") {
            put(P(1), "tnt"); on(P(0), "lever"); tick(2)
            let n0 = g.tnts.list.count
            use(P(0)); tick(2)
            let lit = g.tnts.list.count - n0
            if lit > 0 { g.tnts.list.removeLast(lit) }
            return (lit == 1 && blk(P(1)) == AIR, "primed \(lit)")
        }
        t("bell.power") {
            on(P(1), "bell"); on(P(0), "lever"); tick(2)
            let n0 = rs.bellsRung
            use(P(0)); tick(10)
            return (rs.bellsRung - n0 == 1, "rang \(rs.bellsRung - n0) time(s)")
        }
        t("bulb.toggle") {
            put(P(1), "copper_bulb"); on(P(0), "lever"); tick(2)
            use(P(0)); tick(2); let a = st(P(1))
            use(P(0)); tick(2); let b = st(P(1))
            use(P(0)); tick(2); let c = st(P(1))
            return (a == 1 && b == 1 && c == 0, "on \(a), power off keeps it \(b), next pulse \(c)")
        }
        t("crafter.pulse") {
            let be = entity(P(1), "crafter", .crafter); put(P(1), "crafter", 3)
            be.container[0] = item("oak_log", 2)
            let c = entity(P(2), "chest", .chest); on(P(0), "lever"); tick(2)
            use(P(0)); tick(8)
            return (total(c, "oak_planks") == 4 && total(be) == 1, "crafted \(total(c, "oak_planks")) planks from one pulse")
        }

        // MARK: Rails
        t("rail.propagate") {
            on(P(0), "lever"); for x in 1...10 { on(P(x), "powered_rail", 1) }
            tick(2); use(P(0)); tick(20)
            let lights = (1...10).map { st(P($0)) >= 6 }
            return (lights == Array(repeating: true, count: 9) + [false], "rails on \(lights.map { $0 ? 1 : 0 })")
        }
        t("rail.boost") {
            on(P(0), "lever"); for x in 1...14 { on(P(x), "powered_rail", 1) }
            tick(2); use(P(0)); tick(20)
            let m = Mob(.minecart, at: centre(P(3), dy: 0.0625)); m.vel = V3(1, 0, 0)
            for _ in 0..<10 { m.updateMinecart(0.05, g) }
            let v = simd_length(m.vel)
            return (v > 1.5, String(format: "cart 1.0 -> %.2f m/s", v))
        }
        t("rail.brake") {
            for x in 1...14 { on(P(x), "powered_rail", 1) }
            tick(2)
            let m = Mob(.minecart, at: centre(P(3), dy: 0.0625)); m.vel = V3(3, 0, 0)
            for _ in 0..<10 { m.updateMinecart(0.05, g) }
            let v = simd_length(m.vel)
            return (v < 0.5, String(format: "cart 3.0 -> %.2f m/s", v))
        }
        t("rail.detector") {
            on(P(1), "detector_rail", 1); wire(P(1, 0, 1)); tick(2)
            carts = [centre(P(1), dy: 0.0625)]; tick(2)
            let a = st(P(1)) >= 6 && st(P(1, 0, 1)) == 15
            carts = []
            let n = until(40) { st(P(1)) < 6 }
            return (a && n >= 19 && n <= 21, "powered with a cart \(a), released \(n) ticks after it left")
        }
        t("rail.detectorcomparator") {
            on(P(1), "detector_rail", 1); on(P(2), "comparator", 3); tick(2)
            let cart = mob(.minecart, centre(P(1), dy: 0.0625))
            cart.variant = 1; cart.cargo = ItemContainer(27)
            for i in 0..<27 { cart.cargo?[i] = item("cobblestone", 64) }
            carts = [cart.pos]; tick(6)
            return (comparatorOut(P(2)) == 15, "chest cart full -> \(comparatorOut(P(2)))")
        }
        t("rail.activator") {
            on(P(0), "lever"); for x in 1...3 { on(P(x), "activator_rail", 1) }
            tick(2); use(P(0)); tick(10)
            let all = (1...3).allSatisfy { st(P($0)) >= 6 }
            return (all, "activator rails powered \(all)")
        }

        // MARK: Recipes and names
        t("recipes.all") {
            func i(_ k: String) -> ItemID { Items.has(k) ? Items.id(k) : 0 }
            let W = i("redstone"), T = i("redstone_torch"), S = i("stone"), C = i("cobblestone"), Q = i("quartz"), I = i("iron_ingot")
            let P = i("oak_planks"), G = i("gold_ingot"), K = i("stick"), e: ItemID = 0
            let want: [(String, [ItemID])] = [
                ("redstone_torch", [W, e, e, K, e, e, e, e, e]), ("repeater", [T, W, T, S, S, S, e, e, e]),
                ("comparator", [e, T, e, T, Q, T, S, S, S]), ("observer", [C, C, C, W, W, Q, C, C, C]),
                ("piston", [P, P, P, C, I, C, C, W, C]), ("sticky_piston", [i("slime_ball"), e, e, i("piston"), e, e, e, e, e]),
                ("dispenser", [C, C, C, C, i("bow"), C, C, W, C]), ("dropper", [C, C, C, C, e, C, C, W, C]),
                ("hopper", [I, e, I, I, i("chest"), I, e, I, e]), ("note_block", [P, P, P, P, W, P, P, P, P]),
                ("daylight_detector", [i("glass"), i("glass"), i("glass"), Q, Q, Q, i("oak_slab"), i("oak_slab"), i("oak_slab")]),
                ("target", [e, W, e, W, i("hay_block"), W, e, W, e]), ("redstone_lamp", [e, W, e, W, i("glowstone"), W, e, W, e]),
                ("redstone_block", Array(repeating: W, count: 9)), ("powered_rail", [G, e, G, G, K, G, G, W, G]),
                ("detector_rail", [I, e, I, I, i("stone_pressure_plate"), I, I, W, I]), ("activator_rail", [I, K, I, I, T, I, I, K, I]),
                ("lever", [K, e, e, C, e, e, e, e, e]), ("tripwire_hook", [I, e, e, K, e, e, P, e, e]),
                ("trapped_chest", [i("chest"), i("tripwire_hook"), e, e, e, e, e, e, e]),
                ("crafter", [I, I, I, I, i("crafting_table"), I, W, i("dropper"), W]),
            ]
            var missingR: [String] = []
            for (k, grid) in want where Recipes.match(grid, 3, 3)?.result.item != i(k) { missingR.append(k) }
            return (missingR.isEmpty, missingR.isEmpty ? "\(want.count) reference recipes with copper wire" : "no recipe: \(missingR)")
        }
        t("names.original") {
            let names = Items.allKeys.map { Items.name(Items.id($0)) } + (0..<Blocks.count).map { Blocks.name(BlockID($0)) }
            let hits = names.filter { $0.contains("Redstone") || $0.contains("Sparkstone") }
            return (hits.isEmpty, hits.isEmpty ? "no Redstone in player-facing names" : "\(hits.prefix(4))")
        }

        g.time = savedTime
        print("coppertest: total \(pass + fail + missing + xpass) rows: \(pass) pass, \(fail) fail, \(missing) missing, \(xpass) xpass")
        if !bad.isEmpty { print("coppertest: failing \(bad)") }
        return fail + xpass
    }
}
