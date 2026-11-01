import Foundation
import simd

// P505 (Remington, Nov 1 10:35: "make 100 different ... builds in the game to test the copper logic and search for
// errors. Each should have great variety in tests"; 10:36: "That way if players try to make their own ... copper
// machines there will be few errors"): a hundred circuits built the way players build them, each on its own pad in
// the sky, turned to all four compass directions, on different floors, driven the way a player drives them (levers
// thrown and buttons pressed with Game.useCircuit, blocks placed and broken, items put in chests) with the circuit
// clock (World.redstone.tick, one call per game tick) and checked against the genre reference's numbers: wire falls by
// one a block and dies after 15, repeaters wait 2 game ticks a step and refresh to 15, lamps go out 4 ticks late, torch
// clocks burn out when too fast, pistons push 12 and no more, comparators read containers with the reference formula,
// powered rails carry 8 rails on, a dot of wire powers nothing beside it... Every pad is cleared after its test.
// Families (100 builds): wire runs, repeater lines, repeater locks, logic gates (NOT, OR, NOR, AND, NAND, XOR) with
// their whole truth tables, comparators (compare, subtract, containers), clocks, pistons, observers, buttons, strong
// and weak power through blocks, devices (doors, trapdoors, rails, note blocks, droppers, dispensers, hoppers, TNT)
// and misuse (dots, backwards repeaters, a burning-out loop, a 900-wire grid, cut wires, re-placed parts).
// `questcheck --circuitzoo [N] [--zoofrom K]`; the suite runs all of it after the Sparkstone Workshop.
enum CircuitZoo {
    // Local frame: x right, z toward the builder (south at turn 0); every build is rotated `turn` quarter turns.
    // Local dir6 (0 down, 1 up, 2 north, 3 south, 4 west, 5 east) and facing4 (0 north, 1 south, 2 west, 3 east).
    static let N = 2, S = 3, W = 4, E = 5
    static let fN = 0, fS = 1, fW = 2, fE = 3

    final class Z {
        let g: Game, w: World, rs: Circuit
        let o: IVec3, turn: Int
        var floorKey = "stone"
        private var plan: [(IVec3, BlockID)] = []
        private var ents: [(IVec3, BlockEntity.Kind, [ItemStack])] = []
        private(set) var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        var log: [String] = []

        init(_ g: Game, _ o: IVec3, _ turn: Int) { self.g = g; w = g.world; rs = g.world.redstone; self.o = o; self.turn = turn & 3 }

        // MARK: Frame
        func P(_ x: Int, _ y: Int, _ z: Int) -> IVec3 {
            var a = x, b = z
            for _ in 0..<turn { let t = a; a = -b; b = t }
            return o + IVec3(a, y, b)
        }
        func d6(_ d: Int) -> Int {
            guard d >= 2 else { return d }
            let v = P(Circuit.D[d].x, 0, Circuit.D[d].z) - o
            return v.z < 0 ? 2 : (v.z > 0 ? 3 : (v.x < 0 ? 4 : 5))
        }
        func f4(_ f: Int) -> Int { d6(f + 2) - 2 }

        // MARK: Building (local coordinates; nothing is written until commit)
        func put(_ x: Int, _ y: Int, _ z: Int, _ key: String, _ s: Int = 0) {
            let p = P(x, y, z)
            plan.append((p, Blocks.id(key) + BlockID(s)))
            lo = IVec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = IVec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        func dust(_ x: Int, _ y: Int, _ z: Int) { put(x, y, z, "redstone_wire") }
        func solid(_ x: Int, _ y: Int, _ z: Int, _ key: String = "stone") { put(x, y, z, key) }
        func lamp(_ x: Int, _ y: Int, _ z: Int) { put(x, y, z, "redstone_lamp") }
        func lever(_ x: Int, _ y: Int, _ z: Int) { put(x, y, z, "lever") }                       // on the floor
        func wallLever(_ x: Int, _ y: Int, _ z: Int, faces f: Int) { put(x, y, z, "lever", f4(f) + 4) }
        func button(_ x: Int, _ y: Int, _ z: Int, wood: Bool) { put(x, y, z, wood ? "oak_button" : "stone_button") }
        func wallButton(_ x: Int, _ y: Int, _ z: Int, faces f: Int, wood: Bool) { put(x, y, z, wood ? "oak_button" : "stone_button", f4(f) + 4) }
        func torch(_ x: Int, _ y: Int, _ z: Int) { put(x, y, z, "redstone_torch") }
        func wallTorch(_ x: Int, _ y: Int, _ z: Int, faces f: Int) { put(x, y, z, "redstone_torch", 2 + f4(f)) }
        func repeater(_ x: Int, _ y: Int, _ z: Int, faces f: Int, delay: Int) { put(x, y, z, "repeater", f4(f) + (delay - 1) * 4) }
        func comparator(_ x: Int, _ y: Int, _ z: Int, faces f: Int, subtract: Bool) { put(x, y, z, "comparator", f4(f) + (subtract ? 4 : 0)) }
        func observer(_ x: Int, _ y: Int, _ z: Int, watches d: Int) { put(x, y, z, "observer", d6(d)) }
        func piston(_ x: Int, _ y: Int, _ z: Int, faces d: Int, sticky: Bool) { put(x, y, z, sticky ? "sticky_piston" : "piston", d6(d)) }
        func entity(_ x: Int, _ y: Int, _ z: Int, _ key: String, _ kind: BlockEntity.Kind, _ s: Int = 0, _ items: [ItemStack] = []) {
            put(x, y, z, key, s)
            ents.append((P(x, y, z), kind, items))
        }
        // Hopper output: down or a horizontal local dir6.
        func hopper(_ x: Int, _ y: Int, _ z: Int, out d: Int, _ items: [ItemStack] = []) {
            let wd = d6(d)
            entity(x, y, z, "hopper", .hopper, wd == 0 ? 0 : wd - 1, items)
        }
        // Rails along local x (alongX) or local z.
        func railShape(alongX: Bool) -> Int { let v = P(alongX ? 1 : 0, 0, alongX ? 0 : 1) - o; return v.x != 0 ? 1 : 0 }

        // Lays the floor under everything (one below the lowest layer), then writes the build.
        func commit() {
            guard lo.x != Int.max else { return }
            let fl = Blocks.has(floorKey) ? Blocks.id(floorKey) : STONE
            for x in (lo.x - 1)...(hi.x + 1) { for z in (lo.z - 1)...(hi.z + 1) { _ = w.setBlockAsync(x, lo.y - 1, z, fl) } }
            for (p, b) in plan { _ = w.setBlockAsync(p.x, p.y, p.z, b) }
            for (p, k, items) in ents {
                let be = BlockEntity(k)
                for (i, s) in items.enumerated() where i < be.container.count { be.container[i] = s }
                w.blockEntities[p] = be
            }
        }
        // Everything near the pad back to air (pistons may have pushed blocks a little past the build).
        func clear() {
            guard lo.x != Int.max else { return }
            for x in (lo.x - 3)...(hi.x + 3) { for z in (lo.z - 3)...(hi.z + 3) { for y in (lo.y - 1)...(hi.y + 3) {
                w.blockEntities[IVec3(x, y, z)] = nil
                _ = w.setBlockAsync(x, y, z, AIR)
            } } }
            for _ in 0..<12 { rs.tick() }
        }

        // MARK: Playing
        func tick(_ n: Int = 1) { for _ in 0..<n { rs.tick() } }
        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID { let p = P(x, y, z); return w.block(p.x, p.y, p.z) }
        func key(_ x: Int, _ y: Int, _ z: Int) -> String { Blocks.key(Blocks.groupBase[Int(at(x, y, z))]) }
        func st(_ x: Int, _ y: Int, _ z: Int) -> Int { let b = at(x, y, z); return Int(b - Blocks.groupBase[Int(b)]) }
        func lit(_ x: Int, _ y: Int, _ z: Int) -> Bool { key(x, y, z) == "redstone_lamp" && st(x, y, z) == 1 }
        func lvl(_ x: Int, _ y: Int, _ z: Int) -> Int { key(x, y, z) == "redstone_wire" ? st(x, y, z) & 15 : -1 }
        func use(_ x: Int, _ y: Int, _ z: Int) { _ = g.useCircuit(P(x, y, z)) }
        func set(_ x: Int, _ y: Int, _ z: Int, _ key: String, _ s: Int = 0) { let p = P(x, y, z); w.setBlock(p.x, p.y, p.z, key == "air" ? AIR : Blocks.id(key) + BlockID(s)) }
        func cmpOut(_ x: Int, _ y: Int, _ z: Int) -> Int { rs.comparatorOut[P(x, y, z)] ?? 0 }
        func be(_ x: Int, _ y: Int, _ z: Int) -> BlockEntity? { w.blockEntities[P(x, y, z)] }
        func count(_ x: Int, _ y: Int, _ z: Int) -> Int { be(x, y, z)?.container.slots.reduce(0) { $0 + ($1.isEmpty ? 0 : $1.count) } ?? -1 }
        // Ticks (1-based) until `cond` holds, or nil within `limit`.
        func until(_ limit: Int, _ cond: () -> Bool) -> Int? {
            for i in 1...limit { tick(); if cond() { return i } }
            return nil
        }
        // Rising edges of `on` over n ticks: the gaps between them and the ticks it was on.
        func edges(_ n: Int, _ on: () -> Bool) -> (gaps: [Int], onTicks: Int, longestSteady: Int) {
            var last = -1, gaps: [Int] = [], was = on(), onTicks = 0, steady = 0, longest = 0
            for i in 0..<n {
                tick()
                let now = on()
                if now { onTicks += 1 }
                if now != was { steady = 0 } else { steady += 1; longest = max(longest, steady) }
                if now && !was { if last >= 0 { gaps.append(i - last) }; last = i }
                was = now
            }
            return (gaps, onTicks, longest)
        }
        // What stands on the pad (for a failure's report): circuit parts with their states, local coordinates.
        func dump() -> String {
            var out: [String] = []
            guard lo.x != Int.max else { return "" }
            for y in lo.y...(hi.y + 1) { for z in (lo.z - 1)...(hi.z + 1) { for x in (lo.x - 1)...(hi.x + 1) {
                let b = w.block(x, y, z)
                guard b != AIR, Circuit.kind(b) != .none || Blocks.key(Blocks.groupBase[Int(b)]) == "redstone_wire" else { continue }
                out.append("\(x - o.x),\(y - o.y),\(z - o.z) \(Blocks.key(Blocks.groupBase[Int(b)]))[\(Int(b - Blocks.groupBase[Int(b)]))]")
                if out.count >= 40 { return out.joined(separator: "; ") + " ..." }
            } } }
            return out.joined(separator: "; ")
        }
    }

    struct Case {
        let family: String
        let name: String
        let run: (Z) -> (Bool, String)
    }

    // MARK: The hundred

    static func cases() -> [Case] {
        var c: [Case] = []
        c += wireRuns()          // 12
        c += repeaterLines()     // 10
        c += repeaterLocks()     // 4
        c += gates()             // 18
        c += comparators()       // 10
        c += clocks()            // 6
        c += pistons()           // 10
        c += observers()         // 5
        c += buttons()           // 4
        c += throughBlocks()     // 5
        c += devices()           // 8
        c += misuse()            // 8
        return c
    }

    // Wire runs: a source, n wires along a path (straight, an L, a zigzag, stairs up or down), a lamp in line at the
    // end. Each wire reads 15 minus its place in the run; the lamp lights for n <= 15; the source going off darkens all.
    static func wireRuns() -> [Case] {
        let specs: [(n: Int, shape: Int, src: Int)] = [(1, 0, 0), (8, 0, 1), (15, 0, 0), (16, 0, 0), (14, 1, 2), (15, 1, 3),
                                                       (17, 2, 0), (12, 2, 4), (9, 3, 0), (15, 3, 1), (10, 4, 0), (13, 4, 5)]
        let shapes = ["straight", "L", "zigzag", "stairs up", "stairs down"]
        let sources = ["lever", "copper battery", "torch", "stone button", "wooden button", "wall lever on a post"]
        return specs.map { sp in
            Case(family: "wire", name: "\(sp.n) wires, \(shapes[sp.shape]), \(sources[sp.src])") { z in
                // Path cells (x, height, z) and the direction of the last step.
                var cells: [(Int, Int, Int)] = []
                var x = 0, h = sp.shape == 4 ? (sp.n + 1) / 2 : 0, zz = 0
                let h0 = h
                var lastD = (1, 0)
                for i in 0..<sp.n {
                    if i > 0 {
                        var d = (1, 0)
                        if sp.shape == 1 && i >= sp.n / 2 { d = (0, 1) }
                        if sp.shape == 2 && (i / 2) % 2 == 1 { d = (0, 1) }
                        x += d.0; zz += d.1; lastD = d
                        if sp.shape == 3 && i % 2 == 0 { h += 1 }
                        if sp.shape == 4 && i % 2 == 0 { h -= 1 }
                    }
                    cells.append((x, h, zz))
                }
                func column(_ x: Int, _ hh: Int, _ z0: Int) { if hh > 0 { for y in 0..<hh { z.solid(x, y, z0, "cobblestone") } } }
                for (cx, ch, cz) in cells { column(cx, ch, cz); z.dust(cx, ch, cz) }
                let end = (cells.last!.0 + lastD.0, cells.last!.1, cells.last!.2 + lastD.1)
                column(end.0, end.1, end.2); z.lamp(end.0, end.1, end.2)
                // The source, behind the first wire.
                column(-1, h0, 0)
                switch sp.src {
                case 0: z.lever(-1, h0, 0)
                case 1: break                                               // placed by the test
                case 2: z.solid(-2, h0, 0); z.wallTorch(-1, h0, 0, faces: E)   // a torch on a block's face
                case 3: z.button(-1, h0, 0, wood: false)
                case 4: z.button(-1, h0, 0, wood: true)
                default: z.solid(-1, h0, 0); z.wallLever(-1, h0, -1, faces: N)   // lever on the post's north face: powers the post
                }
                z.commit(); z.tick(10)
                let dark0 = !z.lit(end.0, end.1, end.2) || sp.src == 2
                switch sp.src {
                case 0, 3, 4: z.use(-1, h0, 0)
                case 1: z.set(-1, h0, 0, "redstone_block")
                case 5: z.use(-1, h0, -1)
                default: break
                }
                z.tick(2)
                let levels = cells.map { z.lvl($0.0, $0.1, $0.2) }
                let want = (0..<sp.n).map { max(0, 15 - $0) }
                let on = z.lit(end.0, end.1, end.2)
                // Off again.
                switch sp.src {
                case 0: z.use(-1, h0, 0)
                case 1: z.set(-1, h0, 0, "air")
                case 2: z.set(-1, h0, 0, "air")
                case 5: z.use(-1, h0, -1)
                default: break                                               // buttons release by themselves
                }
                z.tick(sp.src == 4 ? 40 : 30)
                let off = !z.lit(end.0, end.1, end.2) && cells.allSatisfy { z.lvl($0.0, $0.1, $0.2) == 0 }
                let ok = dark0 && levels == want && on == (sp.n <= 15) && off
                return (ok, "levels \(levels) (want \(want)), lamp \(on ? "lit" : "dark") (want \(sp.n <= 15 ? "lit" : "dark")), dark before \(dark0), all dark after \(off)")
            }
        }
    }

    // Repeater lines: a lever, wire runs and repeaters of mixed delays, a lamp. On after 1 + 2 x (sum of delays) ticks,
    // off 4 ticks later than that; a run of 16 wires starves the next repeater.
    static func repeaterLines() -> [Case] {
        let specs: [[Int]] = [[0, 1, 0], [3, 4, 2], [15, 1, 15, 1, 15], [16, 2, 3], [1, 2, 0, 3, 0, 4, 1], [5, 1, 5, 1, 5, 1, 5],
                              [0, 4, 0, 4, 0, 4, 0], [2, 3, 14, 2, 16], [7, 2, 7], [15, 4, 15, 3, 15]]
        return specs.enumerated().map { (k, runs) in
            Case(family: "repeater", name: "runs/delays \(runs)") { z in
                z.floorKey = k % 2 == 0 ? "smooth_stone" : "oak_planks"
                z.lever(0, 0, 0)
                var x = 1, delays: [Int] = [], fed = true
                for (i, v) in runs.enumerated() {
                    if i % 2 == 0 {
                        for _ in 0..<v { z.dust(x, 0, 0); x += 1 }
                        if v > 15 { fed = false }
                    } else { z.repeater(x, 0, 0, faces: fE, delay: v); delays.append(v); x += 1 }
                }
                z.lamp(x, 0, 0)
                z.commit(); z.tick(10)
                z.use(0, 0, 0)
                let tOn = z.until(120) { z.lit(x, 0, 0) }
                z.tick(40)
                z.use(0, 0, 0)
                let tOff = z.until(120) { !z.lit(x, 0, 0) }
                let sum = delays.reduce(0, +) * 2
                let ok = fed ? (tOn == 1 + sum && tOff == 5 + sum) : (tOn == nil)
                let on = tOn.map { "\($0)" } ?? "never", off = tOff.map { "\($0)" } ?? "-"
                return (ok, "lamp on after \(on) ticks (want \(fed ? "\(1 + sum)" : "never")), off after \(off) (want \(fed ? "\(5 + sum)" : "-"))")
            }
        }
    }

    // Repeater locks: a repeater or comparator pointing into a repeater's side holds its output.
    static func repeaterLocks() -> [Case] {
        return [(1, false), (3, false), (2, true), (4, true)].enumerated().map { (k, sp) in
            Case(family: "lock", name: "delay \(sp.0), locked by a \(sp.1 ? "comparator" : "repeater")") { z in
                z.lever(0, 0, 0); z.dust(1, 0, 0)
                z.repeater(2, 0, 0, faces: fE, delay: sp.0); z.lamp(3, 0, 0)
                z.lever(2, 0, 4); z.dust(2, 0, 3); z.dust(2, 0, 2)
                if sp.1 { z.comparator(2, 0, 1, faces: fN, subtract: false) } else { z.repeater(2, 0, 1, faces: fN, delay: 1) }
                z.commit(); z.tick(10)
                z.use(0, 0, 0); z.tick(20); let a = z.lit(3, 0, 0)
                z.use(2, 0, 4); z.tick(20); let lockedBit = (z.st(2, 0, 0) & 32) != 0
                z.use(0, 0, 0); z.tick(20); let held = z.lit(3, 0, 0)
                z.use(2, 0, 4); z.tick(20); let released = !z.lit(3, 0, 0)
                // Locked while off: the input coming on changes nothing until the lock goes.
                z.use(2, 0, 4); z.tick(20)
                z.use(0, 0, 0); z.tick(20); let heldOff = !z.lit(3, 0, 0)
                z.use(2, 0, 4); z.tick(20); let follows = z.lit(3, 0, 0)
                let ok = a && lockedBit && held && released && heldOff && follows
                return (ok, "lit \(a), lock bit \(lockedBit), holds on \(held), lets go \(released), holds off \(heldOff), follows after \(follows)")
            }
        }
    }

    // Logic gates with levers A and B, the whole truth table each.
    static func gates() -> [Case] {
        // (gate, arm) — arm lengthens the input wires.
        let specs: [(String, Int)] = [("NOT", 1), ("NOT", 3), ("NOT up", 1), ("OR", 1), ("OR", 4), ("OR", 2), ("NOR", 1), ("NOR", 3), ("NOR", 2),
                                      ("AND", 0), ("AND", 2), ("AND", 1), ("NAND", 0), ("NAND", 2), ("NAND", 1), ("XOR", 0), ("XOR", 0), ("XOR", 0)]
        return specs.enumerated().map { (k, sp) in
            Case(family: "gate", name: "\(sp.0), arms +\(sp.1)") { z in
                z.floorKey = ["stone", "stone_bricks", "cobblestone"][k % 3]
                let a = sp.1
                var la = (0, 0, 0), lb: (Int, Int, Int)? = nil, out = (0, 0, 0)
                var truth: [Bool] = []                       // for (A, B) = 00, 10, 01, 11 (NOT: 0, 1)
                switch sp.0 {
                case "NOT":
                    // Lever, wires north into a block, a torch on its north face, a lamp in front.
                    la = (0, 0, 2 + a)
                    for zz in 1...(1 + a) { z.dust(0, 0, zz) }
                    z.solid(0, 0, 0); z.wallTorch(0, 0, -1, faces: N); z.lamp(0, 0, -2)
                    out = (0, 0, -2); truth = [true, false]
                case "NOT up":
                    // A torch standing on the block, a lamp over the torch.
                    la = (0, 0, 2); z.dust(0, 0, 1); z.solid(0, 0, 0); z.torch(0, 1, 0); z.lamp(0, 2, 0)
                    out = (0, 2, 0); truth = [true, false]
                case "OR", "NOR":
                    la = (-2 - a, 0, 0); lb = (2 + a, 0, 0)
                    for xx in 1...(1 + a) { z.dust(-xx, 0, 0); z.dust(xx, 0, 0) }
                    z.dust(0, 0, 0); z.dust(0, 0, -1)
                    if sp.0 == "OR" { z.lamp(0, 0, -2); out = (0, 0, -2); truth = [false, true, true, true] }
                    else { z.solid(0, 0, -2); z.wallTorch(0, 0, -3, faces: N); z.lamp(0, 0, -4); out = (0, 0, -4); truth = [true, false, false, false] }
                case "AND", "NAND":
                    // Each input inverted by a torch; the torches' outputs joined (NAND), inverted again (AND).
                    la = (0, 0, 4 + a); lb = (4, 0, 4 + a)
                    for zz in 2...(3 + a) { z.dust(0, 0, zz); z.dust(4, 0, zz) }
                    z.solid(0, 0, 1); z.solid(4, 0, 1)
                    z.wallTorch(0, 0, 0, faces: N); z.wallTorch(4, 0, 0, faces: N)
                    for xx in 0...4 { z.dust(xx, 0, -1) }
                    z.dust(2, 0, -2)
                    if sp.0 == "NAND" { z.lamp(2, 0, -3); out = (2, 0, -3); truth = [true, true, true, false] }
                    else { z.solid(2, 0, -3); z.wallTorch(2, 0, -4, faces: N); z.lamp(2, 0, -5); out = (2, 0, -5); truth = [false, false, false, true] }
                default:
                    // XOR = (A OR B) minus (A AND B): a subtracting comparator, the OR at its back, the AND at its side.
                    la = (0, 0, 6); lb = (4, 0, 6)
                    for zz in 2...5 { z.dust(0, 0, zz); z.dust(4, 0, zz) }
                    z.solid(0, 0, 1); z.solid(4, 0, 1)
                    z.wallTorch(0, 0, 0, faces: N); z.wallTorch(4, 0, 0, faces: N)
                    for xx in 0...4 { z.dust(xx, 0, -1) }
                    z.dust(2, 0, -2); z.solid(2, 0, -3); z.wallTorch(2, 0, -4, faces: N)
                    for xx in 2...6 { z.dust(xx, 0, -5) }
                    for zz in -4...(-2) { z.dust(6, 0, zz) }
                    z.repeater(6, 0, -1, faces: fS, delay: 1)
                    for zz in 0...5 { z.dust(6, 0, zz) }
                    z.repeater(6, 0, 6, faces: fS, delay: 1)
                    z.dust(6, 0, 7); z.dust(6, 0, 8); z.dust(5, 0, 8); z.repeater(4, 0, 8, faces: fW, delay: 1); z.dust(3, 0, 8)
                    // The OR joins through two repeaters (diodes): plain wire would feed A's power back into B's block.
                    z.repeater(1, 0, 4, faces: fE, delay: 1); z.dust(2, 0, 4); z.repeater(3, 0, 4, faces: fW, delay: 1)
                    for zz in 5...7 { z.dust(2, 0, zz) }
                    z.comparator(2, 0, 8, faces: fS, subtract: true); z.lamp(2, 0, 9)
                    out = (2, 0, 9); truth = [false, true, true, false]
                }
                z.lever(la.0, la.1, la.2)
                if let b = lb { z.lever(b.0, b.1, b.2) }
                z.commit(); z.tick(30)
                var got: [Bool] = []
                var aOn = false, bOn = false
                let combos: [(Bool, Bool)] = lb == nil ? [(false, false), (true, false)] : [(false, false), (true, false), (false, true), (true, true)]
                for (wa, wb) in combos {
                    if wa != aOn { z.use(la.0, la.1, la.2); aOn = wa }
                    if let b = lb, wb != bOn { z.use(b.0, b.1, b.2); bOn = wb }
                    z.tick(30)
                    got.append(z.lit(out.0, out.1, out.2))
                }
                let fmt = { (t: [Bool]) in t.map { $0 ? "1" : "0" }.joined() }
                return (got == truth, "truth table \(fmt(got)) (want \(fmt(truth)))")
            }
        }
    }

    // Comparators: compare and subtract on wire levels; containers read with the reference formula, straight behind
    // or through a block; a chest a hopper drains reads lower and lower.
    static func comparators() -> [Case] {
        var out: [Case] = []
        // (rear wires, side wires, subtract)
        for (r, s, sub) in [(1, 1, false), (3, 1, false), (1, 5, false), (2, 8, true), (5, 3, true), (1, 15, true)] {
            out.append(Case(family: "comparator", name: "\(sub ? "subtract" : "compare"), back \(16 - r), side \(16 - s)") { z in
                z.floorKey = sub ? "smooth_stone" : "stone"
                z.comparator(0, 0, 0, faces: fE, subtract: sub)
                for i in 1...r { z.dust(-i, 0, 0) }
                z.lever(-r - 1, 0, 0)
                for i in 1...s { z.dust(0, 0, i) }
                z.lever(0, 0, s + 1)
                for i in 1...15 { z.dust(i, 0, 0) }
                z.commit(); z.tick(10)
                z.use(-r - 1, 0, 0); z.tick(10)
                let alone = z.cmpOut(0, 0, 0)
                z.use(0, 0, s + 1); z.tick(10)
                let both = z.cmpOut(0, 0, 0)
                let rear = 16 - r, side = 16 - s
                let want = sub ? max(0, rear - side) : (rear >= side ? rear : 0)
                let lit = (1...15).filter { z.lvl($0, 0, 0) > 0 }.count
                let ok = alone == rear && both == want && lit == want && z.lvl(1, 0, 0) == want
                return (ok, "alone \(alone) (want \(rear)), with the side \(both) (want \(want)), \(lit) output wires lit")
            })
        }
        // Containers: (kind, key, slots filled as (item, count), through a block)
        let items: [(String, BlockEntity.Kind, [(String, Int)], Bool)] = [
            ("chest", .chest, [("cobblestone", 1)], false),
            ("hopper", .hopper, [("cobblestone", 64), ("stick", 32)], false),
            ("dispenser", .dispenser, Array(repeating: ("arrow", 64), count: 9), true),
        ]
        for (k, kind, fill, through) in items {
            out.append(Case(family: "comparator", name: "reads a \(k)\(through ? " through a block" : "") (\(fill.count) stacks)") { z in
                let stacks = fill.map { ItemStack(Items.id($0.0), $0.1) }
                let cx = through ? -2 : -1
                if through { z.solid(-1, 0, 0) }
                if k == "hopper" { z.hopper(cx, 0, 0, out: 0, stacks) } else { z.entity(cx, 0, 0, k, kind, kind == .dispenser ? 1 : 0, stacks) }
                z.comparator(0, 0, 0, faces: fE, subtract: false)
                for i in 1...15 { z.dust(i, 0, 0) }
                z.commit(); z.tick(20)
                // The reference formula, worked out here on its own.
                var frac: Double = 0
                let c = z.be(cx, 0, 0)?.container
                let slots = c?.count ?? 1
                for s in stacks { frac += Double(s.count) / Double(s.maxStack) }
                let want = fill.isEmpty ? 0 : min(15, Int(floor(1 + frac / Double(slots) * 14)))
                let got = z.cmpOut(0, 0, 0)
                let lit = (1...15).filter { z.lvl($0, 0, 0) > 0 }.count
                return (got == want && lit == want, "reads \(got) (want \(want) for \(slots) slots), \(lit) output wires lit")
            })
        }
        // A chest drained by a hopper: the reading falls step by step to 0, the lamp goes out.
        out.append(Case(family: "comparator", name: "chest drained by a hopper") { z in
            z.entity(-1, 1, 0, "chest", .chest, 0, [ItemStack(Items.id("cobblestone"), 64), ItemStack(Items.id("cobblestone"), 64)])
            z.hopper(-1, 0, 0, out: S)
            z.entity(-1, 0, 1, "chest", .chest)
            z.solid(0, 0, 0); z.comparator(0, 1, 0, faces: fE, subtract: false)
            z.solid(1, 0, 0); z.dust(1, 1, 0); z.solid(2, 0, 0); z.lamp(2, 1, 0)
            z.commit(); z.tick(4)
            let first = z.cmpOut(0, 1, 0)
            var seen: [Int] = [first]
            for _ in 0..<1200 { z.tick(); let v = z.cmpOut(0, 1, 0); if v != seen.last { seen.append(v) } }
            let falling = zip(seen, seen.dropFirst()).allSatisfy { $0.1 < $0.0 }
            let moved = z.count(-1, 0, 1)
            let ok = first == 2 && seen.last == 0 && falling && moved == 128 && !z.lit(2, 1, 0)
            return (ok, "readings \(seen) (want 2 falling to 0), \(moved) of 128 moved, lamp out \(!z.lit(2, 1, 0))")
        })
        return out
    }

    // Clocks.
    static func clocks() -> [Case] {
        var out: [Case] = []
        // Torch + repeater loop: a torch on a block, its output round through a repeater into the block. Period
        // 2 x (2 + 2 x delay); with delay 1 (8 ticks) the torch burns out (8 turn-offs in 60 ticks, reference).
        for d in [1, 2, 3, 4] {
            out.append(Case(family: "clock", name: "torch clock, repeater delay \(d)") { z in
                z.floorKey = d % 2 == 0 ? "stone_bricks" : "oak_planks"
                z.solid(1, 0, 0); z.wallTorch(2, 0, 0, faces: E); z.lamp(2, 1, 0)
                for (x, zz) in [(3, 0), (3, 1), (3, 2), (2, 2), (1, 2)] { z.dust(x, 0, zz) }
                z.repeater(1, 0, 1, faces: fN, delay: d)
                z.commit(); z.tick(30)
                let r = z.edges(300) { z.st(2, 0, 0) < 6 }                 // the wall torch lit
                if d == 1 {
                    return (r.longestSteady >= 100, "burns out: the torch stood still \(r.longestSteady) ticks in 300 (want >= 100)")
                }
                let p = 4 + 4 * d
                let steady = r.gaps.count >= 300 / p - 2 && r.gaps.allSatisfy { $0 == p }
                return (steady && abs(r.onTicks - 150) <= p, "period \(Array(Set(r.gaps)).sorted()) (want \(p)) over \(r.gaps.count + 1) pulses, on \(r.onTicks) of 300")
            })
        }
        // Two observers watching each other: on 2 game ticks of every 4.
        out.append(Case(family: "clock", name: "observer pair") { z in
            z.lamp(1, 0, 0); z.observer(2, 0, 0, watches: E); z.observer(3, 0, 0, watches: W); z.lamp(4, 0, 0)
            z.commit(); z.tick(1)
            // Kick it: a block placed and taken away beside... the pair starts when one of them changes.
            z.set(2, 1, 0, "stone"); z.set(2, 1, 0, "air")
            z.set(3, 0, 0, "observer", z.d6(N)); z.set(3, 0, 0, "observer", z.d6(W))
            z.tick(20)
            let r = z.edges(80) { z.st(2, 0, 0) >= 6 }
            let ok = r.gaps.count >= 15 && r.gaps.allSatisfy { $0 == 4 } && r.onTicks == 40
            return (ok, "gaps \(Array(Set(r.gaps)).sorted()) (want 4), on \(r.onTicks) of 80 (want 40)")
        })
        // Comparator clock: a subtracting comparator feeding its own side; it keeps flipping.
        out.append(Case(family: "clock", name: "comparator clock") { z in
            z.lever(-1, 0, 0); z.comparator(0, 0, 0, faces: fE, subtract: true)
            z.dust(1, 0, 0); z.dust(1, 0, 1); z.dust(0, 0, 1)
            z.commit(); z.tick(5)
            z.use(-1, 0, 0)
            var flips = 0, last = z.cmpOut(0, 0, 0)
            for _ in 0..<100 { z.tick(); let v = z.cmpOut(0, 0, 0); if v != last { flips += 1; last = v } }
            z.use(-1, 0, 0); z.tick(20)
            let stops = z.cmpOut(0, 0, 0) == 0 && z.lvl(1, 0, 0) == 0
            return (flips >= 20 && stops, "\(flips) output changes in 100 ticks (want >= 20), stops with the lever \(stops)")
        })
        return out
    }

    // Pistons.
    static func pistons() -> [Case] {
        var out: [Case] = []
        // A row of n blocks pushed east; 12 is the most, 13 stays put. Sticky pistons pull the first one back.
        for (n, sticky, mat) in [(1, false, "stone"), (5, true, "oak_planks"), (12, false, "cobblestone"), (13, true, "stone_bricks"), (11, true, "white_wool")] {
            out.append(Case(family: "piston", name: "\(sticky ? "sticky " : "")piston pushes \(n) \(mat)") { z in
                z.piston(0, 0, 0, faces: E, sticky: sticky); z.lever(0, 0, 1)
                for x in 1...n { z.solid(x, 0, 0, mat) }
                z.commit(); z.tick(5)
                z.use(0, 0, 1); z.tick(6)
                let ext = z.st(0, 0, 0) >= 6
                let can = n <= 12
                let pushed = can ? (z.key(1, 0, 0) == "piston_head" && (2...(n + 1)).allSatisfy { z.key($0, 0, 0) == mat })
                                 : ((1...n).allSatisfy { z.key($0, 0, 0) == mat } && z.at(n + 1, 0, 0) == AIR)
                z.use(0, 0, 1); z.tick(6)
                let back = z.st(0, 0, 0) < 6
                var after = true
                if can {
                    after = sticky ? (z.key(1, 0, 0) == mat && z.at(2, 0, 0) == AIR && (n < 2 || (3...(n + 1)).allSatisfy { z.key($0, 0, 0) == mat }))
                                   : (z.at(1, 0, 0) == AIR && (2...(n + 1)).allSatisfy { z.key($0, 0, 0) == mat })
                }
                let ok = ext == can && pushed && back && after
                return (ok, "extended \(ext) (want \(can)), row \(pushed ? "right" : "wrong"), retracted \(back), after retracting \(after ? "right" : "wrong")")
            })
        }
        // Straight up: a column of 4 lifted, a torch on the far side broken by a block pushed into it.
        out.append(Case(family: "piston", name: "piston lifts a column") { z in
            z.piston(0, 0, 0, faces: 1, sticky: false); z.lever(1, 0, 0)
            for y in 1...4 { z.solid(0, y, 0, "sand") }
            z.commit(); z.tick(5)
            z.use(1, 0, 0); z.tick(6)
            let up = z.key(0, 1, 0) == "piston_head" && (2...5).allSatisfy { z.key(0, $0, 0) == "sand" }
            return (up, "column lifted \(up): \((1...5).map { z.key(0, $0, 0) })")
        })
        out.append(Case(family: "piston", name: "piston breaks a torch in the way") { z in
            z.piston(0, 0, 0, faces: E, sticky: false); z.lever(0, 0, 1)
            z.solid(1, 0, 0); z.solid(2, 0, 0); z.torch(3, 0, 0)
            z.commit(); z.tick(5)
            z.use(0, 0, 1); z.tick(6)
            let ok = z.key(3, 0, 0) == "stone" && z.key(2, 0, 0) == "stone" && z.key(1, 0, 0) == "piston_head"
            return (ok, "row after the push: \((1...3).map { z.key($0, 0, 0) })")
        })
        out.append(Case(family: "piston", name: "obsidian stops the push") { z in
            z.piston(0, 0, 0, faces: E, sticky: true); z.lever(0, 0, -1)
            z.solid(1, 0, 0); z.solid(2, 0, 0, "obsidian"); z.solid(3, 0, 0)
            z.commit(); z.tick(5)
            z.use(0, 0, -1); z.tick(6)
            let ok = z.st(0, 0, 0) < 6 && z.key(1, 0, 0) == "stone" && z.key(2, 0, 0) == "obsidian"
            return (ok, "piston state \(z.st(0, 0, 0)), row \((1...3).map { z.key($0, 0, 0) })")
        })
        out.append(Case(family: "piston", name: "slime block drags its neighbours") { z in
            z.piston(0, 0, 0, faces: E, sticky: true); z.lever(0, 0, -1)
            z.solid(1, 0, 0, "slime_block"); z.solid(1, 1, 0, "oak_planks"); z.solid(1, 0, 1, "cobblestone")
            z.commit(); z.tick(5)
            z.use(0, 0, -1); z.tick(6)
            let out1 = z.key(2, 0, 0) == "slime_block" && z.key(2, 1, 0) == "oak_planks" && z.key(2, 0, 1) == "cobblestone" && z.at(1, 1, 0) == AIR
            z.use(0, 0, -1); z.tick(6)
            let back = z.key(1, 0, 0) == "slime_block" && z.key(1, 1, 0) == "oak_planks" && z.key(1, 0, 1) == "cobblestone" && z.at(2, 0, 0) == AIR
            return (out1 && back, "pushed together \(out1), pulled back together \(back)")
        })
        // An observer's 2-tick pulse makes a sticky piston spit its block (left where it was pushed).
        out.append(Case(family: "piston", name: "observer pulse spits a block") { z in
            z.observer(-1, 0, 0, watches: W); z.piston(0, 0, 0, faces: E, sticky: true); z.solid(1, 0, 0, "gold_block")
            z.commit(); z.tick(5)
            z.set(-2, 0, 0, "cobblestone")
            z.tick(12)
            let ok = z.key(2, 0, 0) == "gold_block" && z.at(1, 0, 0) == AIR && z.st(0, 0, 0) < 6
            return (ok, "gold at x2 \(z.key(2, 0, 0)), x1 \(z.key(1, 0, 0)), piston \(z.st(0, 0, 0))")
        })
        return out
    }

    // Observers.
    static func observers() -> [Case] {
        var out: [Case] = []
        let triggers = ["a block placed", "a block broken", "a lever thrown", "wire powering up", "a lamp lighting"]
        for (k, t) in triggers.enumerated() {
            out.append(Case(family: "observer", name: "sees \(t)") { z in
                // The watched spot at x 0, the observer at x 1 watching west, its output into a wire run to a lamp.
                z.observer(1, 0, 0, watches: W); z.dust(2, 0, 0); z.dust(3, 0, 0); z.lamp(4, 0, 0)
                switch k {
                case 1: z.solid(0, 0, 0, "cobblestone")
                case 2: z.solid(0, 0, 1); z.wallLever(0, 0, 0, faces: N)
                case 3: z.dust(0, 0, 0); z.dust(0, 0, -1); z.lever(0, 0, -2)
                case 4: z.lamp(0, 0, 0); z.lever(0, 0, 1)
                default: break
                }
                z.commit(); z.tick(20)
                let dark = !z.lit(4, 0, 0)
                switch k {
                case 0: z.set(0, 0, 0, "cobblestone")
                case 1: z.set(0, 0, 0, "air")
                case 2: z.use(0, 0, 0)
                case 3: z.use(0, 0, -2)
                default: z.use(0, 0, 1)
                }
                var pulse = 0, flashed = false
                for _ in 0..<20 { z.tick(); if z.st(1, 0, 0) >= 6 { pulse += 1 }; if z.lit(4, 0, 0) { flashed = true } }
                let ok = dark && flashed && pulse == 2 && !z.lit(4, 0, 0)
                return (ok, "dark before \(dark), pulse \(pulse) ticks (want 2), lamp flashed \(flashed), out after \(!z.lit(4, 0, 0))")
            })
        }
        return out
    }

    // Buttons: how long they hold (stone 20 game ticks, wood 30), on the floor or a wall.
    static func buttons() -> [Case] {
        return [(false, false), (true, false), (false, true), (true, true)].map { (wood, wall) in
            Case(family: "button", name: "\(wood ? "wooden" : "stone") button on the \(wall ? "wall of a block" : "floor")") { z in
                if wall { z.solid(0, 0, 0); z.wallButton(0, 0, -1, faces: N, wood: wood) } else { z.button(0, 0, 0, wood: wood) }
                for x in 1...4 { z.dust(x, 0, 0) }
                z.lamp(5, 0, 0)
                z.commit(); z.tick(10)
                z.use(wall ? 0 : 0, 0, wall ? -1 : 0)
                var held = 0, lampOn = 0
                for _ in 0..<60 { z.tick(); if z.lvl(1, 0, 0) == (wall ? 15 : 15) { held += 1 }; if z.lit(5, 0, 0) { lampOn += 1 } }
                let want = wood ? 30 : 20
                let ok = abs(held - want) <= 1 && abs(lampOn - (want + 4)) <= 1 && !z.lit(5, 0, 0)
                return (ok, "wire powered \(held) ticks (want \(want)), lamp on \(lampOn) (want \(want + 4))")
            }
        }
    }

    // Strong and weak power through blocks.
    static func throughBlocks() -> [Case] {
        var out: [Case] = []
        out.append(Case(family: "power", name: "repeater into a block powers wire beyond it") { z in
            z.lever(0, 0, 0); z.dust(1, 0, 0); z.repeater(2, 0, 0, faces: fE, delay: 1); z.solid(3, 0, 0)
            z.dust(4, 0, 0); z.dust(5, 0, 0); z.lamp(6, 0, 0)
            z.commit(); z.tick(5); z.use(0, 0, 0); z.tick(10)
            return (z.lvl(4, 0, 0) == 15 && z.lit(6, 0, 0), "wire past the block \(z.lvl(4, 0, 0)) (want 15), lamp \(z.lit(6, 0, 0))")
        })
        out.append(Case(family: "power", name: "wire into a block: lamp beside it, not wire beyond") { z in
            z.lever(0, 0, 0); z.dust(1, 0, 0); z.dust(2, 0, 0); z.solid(3, 0, 0)
            z.dust(4, 0, 0); z.dust(5, 0, 0); z.lamp(6, 0, 0); z.lamp(3, 0, 1)
            z.commit(); z.tick(5); z.use(0, 0, 0); z.tick(10)
            let ok = z.lvl(4, 0, 0) == 0 && !z.lit(6, 0, 0) && z.lit(3, 0, 1)
            return (ok, "wire past the block \(z.lvl(4, 0, 0)) (want 0), far lamp \(z.lit(6, 0, 0)) (want dark), lamp beside \(z.lit(3, 0, 1))")
        })
        out.append(Case(family: "power", name: "torch under a block powers wire beside it") { z in
            z.solid(-1, 0, 0); z.wallTorch(0, 0, 0, faces: E); z.wallLever(-1, 0, 1, faces: S)     // the lever on the torch's block
            z.solid(0, 1, 0); z.solid(1, 0, 0); z.dust(1, 1, 0); z.solid(2, 0, 0); z.dust(2, 1, 0); z.solid(3, 0, 0); z.lamp(3, 1, 0)
            z.commit(); z.tick(10)
            let on = z.lvl(1, 1, 0) == 15 && z.lit(3, 1, 0)
            // The lever beside the torch's block turns the torch off and the wire with it.
            z.use(-1, 0, 1); z.tick(10)
            let off = z.lvl(1, 1, 0) == 0 && !z.lit(3, 1, 0)
            return (on && off, "with the torch lit: wire \(on ? "15, lamp lit" : "wrong"); torch off: wire \(z.lvl(1, 1, 0)), lamp \(z.lit(3, 1, 0))")
        })
        out.append(Case(family: "power", name: "lever on a block powers the lamp under it") { z in
            z.lamp(0, 0, 0); z.solid(0, 1, 0); z.lever(0, 2, 0)
            z.solid(1, 0, 0); z.dust(1, 1, 0); z.solid(2, 0, 0); z.lamp(2, 1, 0)
            z.commit(); z.tick(5); z.use(0, 2, 0); z.tick(10)
            let ok = z.lit(0, 0, 0) && z.lvl(1, 1, 0) == 15 && z.lit(2, 1, 0)
            return (ok, "lamp under \(z.lit(0, 0, 0)), wire beside \(z.lvl(1, 1, 0)) (want 15), its lamp \(z.lit(2, 1, 0))")
        })
        out.append(Case(family: "power", name: "comparator powers a block at its own level") { z in
            z.lever(-4, 0, 0); for x in -3...(-1) { z.dust(x, 0, 0) }
            z.comparator(0, 0, 0, faces: fE, subtract: false); z.solid(1, 0, 0)
            for x in 2...14 { z.dust(x, 0, 0) }
            z.commit(); z.tick(5); z.use(-4, 0, 0); z.tick(10)
            let ok = z.cmpOut(0, 0, 0) == 13 && z.lvl(2, 0, 0) == 13 && z.lvl(14, 0, 0) == 1
            return (ok, "comparator \(z.cmpOut(0, 0, 0)) (want 13), wire past the block \(z.lvl(2, 0, 0)) (want 13), the 13th \(z.lvl(14, 0, 0)) (want 1)")
        })
        return out
    }

    // Devices players hang on circuits.
    static func devices() -> [Case] {
        var out: [Case] = []
        out.append(Case(family: "device", name: "lever opens an iron door") { z in
            z.put(0, 0, 0, "iron_door", z.f4(fS)); z.put(0, 1, 0, "iron_door", z.f4(fS) + 8); z.lever(1, 0, 0)
            z.commit(); z.tick(5)
            let shut = z.st(0, 0, 0) & 4 == 0
            z.use(1, 0, 0); z.tick(5)
            let open = z.st(0, 0, 0) & 4 != 0 && z.st(0, 1, 0) & 4 != 0
            z.use(1, 0, 0); z.tick(5)
            let again = z.st(0, 0, 0) & 4 == 0 && z.st(0, 1, 0) & 4 == 0
            return (shut && open && again, "shut \(shut), both halves open \(open), shut again \(again)")
        })
        out.append(Case(family: "device", name: "button opens an iron door for a moment") { z in
            z.put(0, 0, 0, "iron_door", z.f4(fE)); z.put(0, 1, 0, "iron_door", z.f4(fE) + 8)
            z.solid(0, 0, 1); z.solid(0, 1, 1); z.wallButton(1, 1, 1, faces: E, wood: false)
            z.commit(); z.tick(5)
            z.use(1, 1, 1); z.tick(3)
            // The button powers the block it is on; the door's upper half beside that block opens both.
            let open = z.st(0, 1, 0) & 4 != 0 && z.st(0, 0, 0) & 4 != 0
            z.tick(30)
            let shut = z.st(0, 0, 0) & 4 == 0
            return (open && shut, "opened \(open), shut again after the button \(shut)")
        })
        out.append(Case(family: "device", name: "trapdoor on a wire") { z in
            z.put(3, 0, 0, "iron_trapdoor"); z.lever(0, 0, 0); z.dust(1, 0, 0); z.dust(2, 0, 0)
            z.commit(); z.tick(5); z.use(0, 0, 0); z.tick(5)
            let open = z.st(3, 0, 0) & 4 != 0
            z.use(0, 0, 0); z.tick(5)
            return (open && z.st(3, 0, 0) & 4 == 0, "opens \(open), shuts \(z.st(3, 0, 0) & 4 == 0)")
        })
        for n in [6, 12] {
            out.append(Case(family: "device", name: "powered rail line of \(n)") { z in
                let shape = z.railShape(alongX: true)
                for x in 1...n { z.put(x, 0, 0, "powered_rail", shape) }
                z.lever(0, 0, 0)
                z.commit(); z.tick(5); z.use(0, 0, 0); z.tick(5)
                let on = (1...n).map { z.st($0, 0, 0) >= 6 }
                let want = (1...n).map { $0 <= 9 }
                z.use(0, 0, 0); z.tick(5)
                let off = (1...n).allSatisfy { z.st($0, 0, 0) < 6 }
                let fmt = { (t: [Bool]) in t.map { $0 ? "1" : "0" }.joined() }
                return (on == want && off, "powered \(fmt(on)) (want \(fmt(want))), all off after \(off)")
            })
        }
        out.append(Case(family: "device", name: "note block plays once per pulse") { z in
            z.put(2, 0, 0, "note_block", 7); z.lever(0, 0, 0); z.dust(1, 0, 0)
            z.commit(); z.tick(5)
            let n0 = z.rs.notesPlayed
            z.use(0, 0, 0); z.tick(10); let one = z.rs.notesPlayed - n0
            z.tick(40); let still = z.rs.notesPlayed - n0
            z.use(0, 0, 0); z.tick(10); z.use(0, 0, 0); z.tick(10)
            let two = z.rs.notesPlayed - n0
            return (one == 1 && still == 1 && two == 2, "notes after one pulse \(one), held on \(still), after a second \(two)")
        })
        out.append(Case(family: "device", name: "dropper hands one item a pulse into a chest") { z in
            z.entity(0, 0, 0, "dropper", .dispenser, z.d6(E), [ItemStack(Items.id("cobblestone"), 10)])
            z.entity(1, 0, 0, "chest", .chest)
            z.button(0, 0, -1, wood: false)
            z.commit(); z.tick(5)
            for _ in 0..<3 { z.use(0, 0, -1); z.tick(30) }
            let moved = z.count(1, 0, 0), left = z.count(0, 0, 0)
            return (moved == 3 && left == 7, "chest holds \(moved) (want 3), dropper \(left) (want 7)")
        })
        out.append(Case(family: "device", name: "powered hopper holds its items") { z in
            z.hopper(0, 0, 0, out: E, [ItemStack(Items.id("cobblestone"), 8)])
            z.entity(1, 0, 0, "chest", .chest)
            z.lever(0, 0, 1)
            z.commit()
            z.use(0, 0, 1); z.tick(100)
            let held = z.count(1, 0, 0)
            z.use(0, 0, 1); z.tick(100)
            let moved = z.count(1, 0, 0)
            return (held == 0 && moved == 8, "while powered \(held) moved (want 0), after \(moved) (want 8)")
        })
        return out
    }

    // Misuse: what players get wrong, and what the engine must do anyway.
    static func misuse() -> [Case] {
        var out: [Case] = []
        out.append(Case(family: "misuse", name: "a dot of wire powers nothing beside it") { z in
            z.solid(0, 0, 0); z.wallLever(0, 0, 1, faces: S); z.dust(0, 1, 0); z.lamp(1, 1, 0); z.lamp(-1, 1, 0)
            z.solid(1, 0, 0); z.solid(-1, 0, 0)
            z.commit(); z.tick(5); z.use(0, 0, 1); z.tick(10)
            let cross = z.lvl(0, 1, 0) == 15 && z.lit(1, 1, 0) && z.lit(-1, 1, 0)
            z.use(0, 1, 0); z.tick(10)
            let dot = z.lvl(0, 1, 0) == 15 && !z.lit(1, 1, 0) && !z.lit(-1, 1, 0)
            return (cross && dot, "a cross lights both lamps \(cross); a dot lights neither \(dot)")
        })
        out.append(Case(family: "misuse", name: "a backwards repeater passes nothing") { z in
            z.lever(0, 0, 0); z.dust(1, 0, 0); z.repeater(2, 0, 0, faces: fW, delay: 1); z.dust(3, 0, 0); z.lamp(4, 0, 0)
            z.commit(); z.tick(5); z.use(0, 0, 0); z.tick(10)
            return (!z.lit(4, 0, 0) && z.lvl(3, 0, 0) == 0, "lamp \(z.lit(4, 0, 0)) (want dark), wire after \(z.lvl(3, 0, 0))")
        })
        out.append(Case(family: "misuse", name: "a torch looped into its own block burns out") { z in
            z.solid(0, 0, 0); z.wallTorch(1, 0, 0, faces: E)
            let path = [(2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (-1, 2), (-2, 2), (-2, 1), (-2, 0), (-1, 0)]
            for (x, zz) in path { z.dust(x, 0, zz) }
            z.commit()
            let r = z.edges(300) { z.st(1, 0, 0) < 6 }
            return (r.longestSteady >= 100 && r.gaps.count >= 3, "flickered \(r.gaps.count + 1) times, then stood still \(r.longestSteady) ticks (want >= 100)")
        })
        out.append(Case(family: "misuse", name: "a 30 x 30 sheet of wire") { z in
            for x in 0..<30 { for zz in 0..<30 { z.dust(x, 0, zz) } }
            z.lever(-1, 0, 0)
            z.commit(); z.tick(5)
            z.use(-1, 0, 0)
            let t0 = CFAbsoluteTimeGetCurrent(); z.tick(); let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            z.tick(3)
            var bad = 0
            for x in 0..<30 { for zz in 0..<30 where z.lvl(x, 0, zz) != max(0, 15 - x - zz) { bad += 1 } }
            z.use(-1, 0, 0); z.tick(4)
            var left = 0
            for x in 0..<30 { for zz in 0..<30 where z.lvl(x, 0, zz) != 0 { left += 1 } }
            return (bad == 0 && left == 0 && ms < 250, "\(bad) wires off the 15 - distance levels, \(left) still lit after, the solving tick took " + String(format: "%.1f ms", ms))
        })
        out.append(Case(family: "misuse", name: "a wire broken mid-line darkens the rest") { z in
            z.lever(0, 0, 0); for x in 1...8 { z.dust(x, 0, 0) }; z.lamp(9, 0, 0)
            z.commit(); z.tick(5); z.use(0, 0, 0); z.tick(5)
            let lit = z.lit(9, 0, 0)
            z.set(4, 0, 0, "air"); z.tick(10)
            let ok = lit && !z.lit(9, 0, 0) && (5...8).allSatisfy { z.lvl($0, 0, 0) == 0 } && z.lvl(3, 0, 0) == 13
            return (ok, "lit first \(lit), lamp after the break \(z.lit(9, 0, 0)), wires beyond \((5...8).map { z.lvl($0, 0, 0) })")
        })
        out.append(Case(family: "misuse", name: "a comparator re-placed where a lit one stood") { z in
            z.lever(-1, 0, 0); z.comparator(0, 0, 0, faces: fE, subtract: false); z.lamp(1, 0, 0)
            z.commit(); z.tick(5); z.use(-1, 0, 0); z.tick(10)
            let first = z.lit(1, 0, 0)
            // Broken, the lever thrown off, the lamp out; a new comparator goes in: nothing may flash.
            z.set(0, 0, 0, "air"); z.use(-1, 0, 0); z.tick(20)
            z.set(0, 0, 0, "comparator", z.f4(fE))
            var flash = 0
            for _ in 0..<20 { z.tick(); if z.lit(1, 0, 0) { flash += 1 } }
            return (first && flash == 0, "lit at first \(first), the new comparator flashed the lamp for \(flash) ticks (want 0)")
        })
        out.append(Case(family: "misuse", name: "a lamp between two levers") { z in
            z.lever(-1, 0, 0); z.lamp(0, 0, 0); z.lever(1, 0, 0)
            z.commit(); z.tick(5)
            z.use(-1, 0, 0); z.use(1, 0, 0); z.tick(5)
            let both = z.lit(0, 0, 0)
            z.use(-1, 0, 0); z.tick(10)
            let one = z.lit(0, 0, 0)
            z.use(1, 0, 0); z.tick(10)
            return (both && one && !z.lit(0, 0, 0), "both \(both), one left \(one), none \(!z.lit(0, 0, 0))")
        })
        out.append(Case(family: "misuse", name: "a block over a wire step cuts it") { z in
            z.lever(-1, 0, 0); z.dust(0, 0, 0); z.solid(1, 0, 0); z.dust(1, 1, 0); z.solid(2, 0, 0); z.lamp(2, 1, 0)
            z.commit(); z.tick(5); z.use(-1, 0, 0); z.tick(5)
            let climbs = z.lvl(1, 1, 0) == 14 && z.lit(2, 1, 0)
            z.set(0, 1, 0, "glass"); z.tick(10)
            let glass = z.lit(2, 1, 0)
            z.set(0, 1, 0, "stone"); z.tick(10)
            let cut = z.lvl(1, 1, 0) == 0 && !z.lit(2, 1, 0)
            return (climbs && glass && cut, "climbs \(climbs), glass over it leaves it \(glass), stone over it cuts it \(cut)")
        })
        return out
    }

    // MARK: Running

    static func run(_ g: Game, count: Int = 100, from: Int = 0, _ check: (Bool, String) -> Void) {
        let w = g.world
        let all = cases()
        let p0 = g.player.pos
        let bx = Int(floorf(p0.x)) - 160, bz = Int(floorf(p0.z)) - 160
        var passed = 0, byFamily: [String: (Int, Int)] = [:]
        let t0 = CFAbsoluteTimeGetCurrent()
        let end = min(all.count, from + count)
        for i in from..<end {
            let c = all[i]
            // Pads on a 10 x 10 grid 32 apart, south-west of the player, each 8 over the highest ground under it.
            let cx = bx + (i % 10) * 32, cz = bz + (i / 10) * 32
            _ = w.loadSync(center: V3(Float(cx), p0.y, Float(cz)), radius: 3)
            var top = SEA
            for x in stride(from: -48, through: 48, by: 6) { for z in stride(from: -48, through: 48, by: 6) { top = max(top, w.topY(cx + x, cz + z)) } }
            let z = Z(g, IVec3(cx, min(CH - 24, top + 8), cz), i)
            let r = c.run(z)
            if !r.0 { print("circuitzoo \(i) pad: \(z.dump())") }
            z.clear()
            byFamily[c.family, default: (0, 0)].1 += 1
            if r.0 { passed += 1; byFamily[c.family, default: (0, 0)].0 += 1 }
            check(r.0, String(format: "circuitzoo %03d %@ (%@, turned %d): ", i, c.family, c.name, i & 3) + r.1)
        }
        let fams = byFamily.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.0)/\($0.value.1)" }.joined(separator: ", ")
        print(String(format: "circuitzoo: %d of %d circuits work (%@) in %.1f s", passed, end - from, fams, CFAbsoluteTimeGetCurrent() - t0))
    }
}
