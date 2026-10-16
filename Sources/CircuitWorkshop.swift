import Foundation
import simd

// The Sparkstone Workshop (backlog L2): a creative test world with the standard circuits players build, each on its own
// bench with a sign, built on a stone deck above the spawn. Pick it from the Worlds menu ("Sparkstone Workshop"); the
// game builds the deck the first time the world loads (Game.workshopTick). CircuitWorkshopTests drives every bench
// through the real circuit engine and checks it behaves like the genre reference.
//
// Benches, west to east along the deck (each faces the walkway on its north side, -Z):
//  1. Torch clock: a sparkstone torch on a block, its output looped through a 4-tick repeater back into the block.
//  2. Observer clock: two observers watching each other.
//  3. Bulb toggle (T flip-flop): a button into a copper bulb, read by a comparator, into a lamp.
//  4. Piston door: a 1x2 sticky-piston door held shut by an inverting torch; the lever on the pillar opens it.
//  5. Hopper sorter: a hopper line over a filter hopper (18 of the sorted item + 4 fillers), a comparator, a torch
//     that locks the hopper under the filter until a 19th sorted item arrives.
//  6. Comparator subtraction: 12 at the back, 5 at the side (lever), 7 out.
//  7. Observer sensor: an observer watching a spot; placing a block there flashes a lamp.
enum CircuitWorkshop {
    static let worldName = "Sparkstone Workshop"
    static let seed: UInt64 = 0x5350_4152_4B53          // a fixed seed: the deck stands over the same land every time

    struct Bench {
        let key: String
        let title: [String]          // the sign's lines
        let width: Int
        let build: (Builder) -> Void
    }

    // Writes relative to a bench's origin (y 0 = the first layer on the deck).
    final class Builder {
        let w: World
        var o: IVec3
        init(_ w: World, _ o: IVec3) { self.w = w; self.o = o }
        func P(_ x: Int, _ y: Int = 0, _ z: Int = 0) -> IVec3 { o + IVec3(x, y, z) }
        func putB(_ p: IVec3, _ b: BlockID) { _ = w.setBlockAsync(p.x, p.y, p.z, b) }
        func put(_ p: IVec3, _ key: String, _ s: Int = 0) { putB(p, Blocks.id(key) + BlockID(s)) }
        func wire(_ p: IVec3) { put(p, "redstone_wire") }
        @discardableResult
        func entity(_ p: IVec3, _ key: String, _ kind: BlockEntity.Kind, _ s: Int = 0, _ items: [ItemStack] = []) -> BlockEntity {
            put(p, key, s)
            let be = BlockEntity(kind)
            w.blockEntities[p] = be
            for (i, st) in items.enumerated() where i < be.container.count { be.container[i] = st }
            return be
        }
    }

    // The sorted item, the filler (never in the stream) and the rest of the stream on the sorter bench.
    static let sortItem = "iron_ingot", fillerItem = "stick", otherItem = "cobblestone"

    static let benches: [Bench] = [
        Bench(key: "torch_clock", title: ["Torch Clock", "torch + 4-tick", "repeater loop", "20-tick period"], width: 8) { b in
            b.put(b.P(1), "stone")
            b.put(b.P(2), "redstone_torch", 5)                      // on the stone's east face
            b.put(b.P(2, 1), "redstone_lamp")                        // lit with the torch (it powers the block above)
            for p in [b.P(3), b.P(3, 0, 1), b.P(3, 0, 2), b.P(2, 0, 2), b.P(1, 0, 2)] { b.wire(p) }
            b.put(b.P(1, 0, 1), "repeater", 0 + 3 * 4)               // facing north into the stone, delay 4
        },
        Bench(key: "observer_clock", title: ["Observer Clock", "two observers", "watching each", "other"], width: 7) { b in
            b.put(b.P(1), "redstone_lamp")
            b.put(b.P(2), "observer", 5)                             // watches east, fires west into the lamp
            b.put(b.P(3), "observer", 4)                             // watches west, fires east
            b.put(b.P(4), "redstone_lamp")
        },
        Bench(key: "bulb_toggle", title: ["Bulb Toggle", "T flip-flop:", "each press flips", "the lamp"], width: 7) { b in
            b.put(b.P(1), "stone_button")                            // on the deck
            b.put(b.P(2), "copper_bulb")
            b.put(b.P(3), "comparator", 3)                           // facing east, reads the bulb
            b.put(b.P(4), "redstone_lamp")
        },
        Bench(key: "piston_door", title: ["Piston Door", "lever opens it", "(an inverting", "torch holds it)"], width: 10) { b in
            // A pillar in front of the wall with the lever on top; a torch on the pillar's face powers the upper piston
            // and, through the block space above it, the lower one (quasi-connectivity). The lever turns the torch off.
            b.put(b.P(3, 0, -2), "stone"); b.put(b.P(3, 1, -2), "stone")
            b.put(b.P(3, 2, -2), "lever", 0)
            b.put(b.P(3, 1, -1), "redstone_torch", 2 + 1)            // on the pillar's south face, facing south
            b.put(b.P(3), "sticky_piston", 5); b.put(b.P(3, 1), "sticky_piston", 5)
            b.put(b.P(4), "stone_bricks"); b.put(b.P(4, 1), "stone_bricks")      // the door, pushed into the doorway at x 5
            for x in [1, 2, 6, 7] { for y in 0...1 { b.put(b.P(x, y), "stone_bricks") } }
            for x in 1...7 { b.put(b.P(x, 2), "stone_bricks") }
        },
        Bench(key: "hopper_sorter", title: ["Hopper Sorter", "keeps the iron,", "passes the rest", "on to the end"], width: 9) { b in
            // Stream: an input chest over the first hopper, five hoppers east, a chest at the end.
            b.entity(b.P(0, 4), "chest", .chest)
            for x in 0...4 { b.entity(b.P(x, 3), "hopper", .hopper, 4) }                  // pointing east
            b.entity(b.P(5, 3), "chest", .chest)
            // Filter under the third stream hopper, pointing west at nothing (it only fills); the lock hopper under it
            // pulls from it into the sorted-items chest.
            let item = { (k: String, n: Int) in ItemStack(Items.id(k), n) }
            b.entity(b.P(2, 2), "hopper", .hopper, 3, [item(sortItem, 18)] + Array(repeating: item(fillerItem, 1), count: 4))
            b.entity(b.P(2, 1), "hopper", .hopper, 0)
            b.entity(b.P(2, 0), "chest", .chest)
            // Comparator (south, reading the filter) -> two dust (s, s - 1) -> into a block -> a torch on its far face,
            // whose output dust runs back to point into the lock hopper.
            for z in 1...4 { b.put(b.P(2, 1, z), "stone") }
            b.put(b.P(2, 2, 1), "comparator", 1)
            b.wire(b.P(2, 2, 2)); b.wire(b.P(2, 2, 3))
            b.put(b.P(2, 2, 4), "stone")
            b.put(b.P(2, 2, 5), "redstone_torch", 2 + 1)            // on the block's south face, facing south
            let back = [b.P(3, 2, 5), b.P(4, 2, 5), b.P(4, 2, 4), b.P(4, 2, 3), b.P(4, 2, 2), b.P(4, 2, 1), b.P(4, 2, 0),
                        b.P(3, 1, 0)]                                // the last steps down, pointing west into the lock hopper
            for p in back { b.put(p + IVec3(0, -1, 0), "stone"); b.wire(p) }
        },
        Bench(key: "comparator_subtract", title: ["Subtraction", "12 at the back,", "5 at the side:", "7 comes out"], width: 17) { b in
            b.put(b.P(1), "redstone_block")
            for x in 2...5 { b.wire(b.P(x)) }                        // 15 -> 12 at the comparator's back
            b.put(b.P(6), "comparator", 3 + 4)                       // facing east, subtract mode
            b.wire(b.P(6, 0, 1)); b.wire(b.P(6, 0, 2))               // the side: the lever's 15 -> 5 over 11 dust
            for x in 7...15 { b.wire(b.P(x, 0, 2)) }
            b.put(b.P(16, 0, 2), "lever")
            for x in 7...13 { b.wire(b.P(x)) }                       // 7 out: the seventh dust is the last lit one
            b.put(b.P(14), "redstone_lamp")
        },
        Bench(key: "observer_sensor", title: ["Observer Sensor", "place a block", "on the gold mark", "and the lamp flashes"], width: 7) { b in
            b.put(b.P(1, -1), "gold_block")                          // the mark (the observed spot is above it)
            b.put(b.P(2), "observer", 4)                             // watches west
            b.put(b.P(3), "redstone_lamp")
        },
    ]

    // Where each bench starts, from the deck's origin (its north-west corner on the walkway).
    static func layout() -> [(Bench, Int)] {
        var x = 2
        return benches.map { b in defer { x += b.width + 3 }; return (b, x) }
    }
    static var deckLength: Int { layout().last.map { $0.1 + $0.0.width + 2 } ?? 10 }
    static let deckDepth = 12            // z 0 walkway rows -3...-1, benches from 0

    // Builds the deck with its benches at `o` (the walkway's west end, at deck level). Returns each bench's origin.
    @discardableResult
    static func build(_ w: World, at o: IVec3) -> [String: IVec3] {
        let b = Builder(w, o)
        let floor = Blocks.has("smooth_stone") ? Blocks.id("smooth_stone") : STONE
        for x in -1...deckLength { for z in -4...deckDepth {
            b.putB(b.P(x, -1, z), (z >= -3 && z <= -1) || (x == -1 && z == -4) ? Blocks.id(markerBlock) : floor)
            for y in 0...5 { b.putB(b.P(x, y, z), AIR) }
        } }
        var at: [String: IVec3] = [:]
        for (bench, x) in layout() {
            b.o = o + IVec3(x, 0, 0)
            bench.build(b)
            at[bench.key] = b.o
            // The sign: a wall sign facing the walkway on a post at the bench's west end (the post stands in the gap
            // between benches, so the 3-wide walkway stays clear: a wall sign has no collision).
            let post = b.P(-1, 0, 0), sign = b.P(-1, 0, -1)
            b.put(post, "chiseled_stone_bricks")
            if Blocks.has("oak_sign") {
                b.putB(sign, Blocks.id("oak_sign") + 4)               // wall sign facing north
                let be = BlockEntity(.sign)
                be.lines = bench.title
                w.blockEntities[sign] = be
            }
        }
        return at
    }

    // The player's start on the walkway: its west end, middle row.
    static func walkwayStart(_ o: IVec3) -> V3 { V3(Float(o.x) + 0.5, Float(o.y), Float(o.z) - 2 + 0.5) }

    // Whether the deck stands at this spawn already: its walkway corner (the deck's marker block) at the origin's
    // column, at any height, or the first bench's sign.
    static func built(_ w: World, spawn: V3) -> Bool {
        let x0 = Int(floorf(spawn.x)) - 8, z0 = Int(floorf(spawn.z)) - 4
        let first = layout()[0].1
        let marker = Blocks.id(markerBlock)
        for y in 1..<CH {
            if w.block(x0 - 1, y - 1, z0 - 4) == marker && w.block(x0 - 1, y - 1, z0 - 3) == marker { return true }
            if w.blockEntities[IVec3(x0 + first - 1, y, z0 - 1)]?.kind == .sign { return true }
        }
        return false
    }
    static let markerBlock = "chiseled_stone_bricks"

    // Where the deck goes in the workshop world: over the fixed spawn, 10 above the highest ground under it.
    static func origin(_ w: World, spawn: V3) -> IVec3 {
        let x0 = Int(floorf(spawn.x)) - 8, z0 = Int(floorf(spawn.z)) - 4
        var top = SEA
        for x in stride(from: -1, through: deckLength, by: 4) { for z in stride(from: -4, through: deckDepth, by: 4) { top = max(top, w.topY(x0 + x, z0 + z)) } }
        return IVec3(x0, min(CH - 12, top + 10), z0)
    }
}

extension Game {
    // In the workshop world: on its first tick in the overworld, build the deck over the world's spawn if this world has
    // none yet (the walkway's marker block, or the first bench's sign) and stand the player on its walkway.
    func workshopTick() {
        guard !workshopChecked else { return }
        guard save?.dir.lastPathComponent == CircuitWorkshop.worldName else { workshopChecked = true; return }
        guard dim.dim == .overworld else { return }                               // back in the overworld later
        workshopChecked = true
        // The site: the world's first spawn (varied per seed, where a new world places the player), from the terrain
        // alone, so it never moves (spawnPoint does: a bed, the spawn command) and never lands on the deck itself.
        let site = findSpawn()
        _ = world.loadSync(center: site, radius: 1)                                // the marker corner is near the site
        if CircuitWorkshop.built(world, spawn: site) { return }
        // Building: the whole deck area now, rather than waiting for streaming (a short render distance never reaches
        // its far end). Once per world.
        let len = CircuitWorkshop.deckLength
        _ = world.loadSync(center: site + V3(Float(len / 2 - 8), 0, 0), radius: len / 32 + 2)
        let o = CircuitWorkshop.origin(world, spawn: site)
        CircuitWorkshop.build(world, at: o)
        player.pos = CircuitWorkshop.walkwayStart(o)
        player.vel = .zero
        player.yaw = -.pi / 2                                          // looking east along the walkway (forward = -sin yaw, -cos yaw)
        onToast?("Sparkstone Workshop")
    }
}
