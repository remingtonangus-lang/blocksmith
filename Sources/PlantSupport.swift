import Foundation
import simd

// Plants that need support pop (with their drops) when it goes, however it goes: broken by hand, blown up, pushed, dug
// out from under, washed away. A popped block is itself a block change, so a whole stack goes one block per tick:
// sugar cane, cactus and bamboo up from a broken base, kelp up through the water, weeping and cave vines down from a
// broken ceiling (playtest 2026-10-05: sugar cane taller than three stayed floating when its bottom block was broken).
// World.setBlock queues the changed cell and its neighbours; Game.gravityTick checks them here.
enum PlantSupport {
    // Per block state: 0 needs nothing, 1 stands on something, 2 hangs from something, 3 a water plant (stands on
    // something, leaves water behind), 4 a vine (a solid side or a vine above).
    static var rule: [UInt8] = []

    static func build() {
        let n = Blocks.count
        var r = [UInt8](repeating: 0, count: n)
        let hanging = ["weeping_vines", "cave_vines", "hanging_roots", "spore_blossom", "pale_hanging_moss"]
        let water = ["kelp", "seagrass", "tall_seagrass"]
        let standing: Set<String> = ["sugar_cane", "cactus", "cactus_flower", "bamboo", "bamboo_sapling", "big_dripleaf",
                                     "big_dripleaf_stem", "small_dripleaf", "sweet_berry_bush", "twisting_vines", "twisting_vines_plant"]
        // Drawn as a cross but held up by other means (or not plants at all).
        let free: Set<String> = ["fire", "soul_fire", "cobweb", "pointed_dripstone", "glow_lichen", "sculk_vein", "lily_pad", "light",
                                 "resin_clump", "chorus_plant", "chorus_flower", "tripwire"]
        let sits: Set<String> = ["snow", "rail", "powered_rail", "detector_rail", "activator_rail", "redstone_wire", "repeater",
                                 "comparator", "flower_pot"]
        for i in 1..<n {
            let k = Blocks.key(Blocks.groupBase[i])
            // Lanterns (plain, ghost, copper): a hanging one needs its ceiling or chain, a standing one its floor.
            if Blocks.shape[i] == "lantern" { r[i] = Blocks.key(BlockID(i)).hasSuffix("[hanging]") ? 2 : 1; continue }
            if k == "vine" { r[i] = 4; continue }
            if hanging.contains(where: { k.hasPrefix($0) }) { r[i] = 2; continue }
            if water.contains(k) || k.hasPrefix("kelp") { r[i] = 3; continue }
            if standing.contains(k) { r[i] = 1; continue }
            // Not plants, but they stand on a block the same way and pop with it in the reference game: carpets, snow
            // layers, pressure plates, rails, sparkstone dust, repeaters, comparators, flower pots.
            if sits.contains(k) || k.hasSuffix("_carpet") || k.hasSuffix("_pressure_plate") || k.hasPrefix("potted_") { r[i] = 1; continue }
            if free.contains(k) || k.contains("amethyst") || k.hasSuffix("_bud") || k.contains("coral") { continue }
            if Blocks.isPlant(BlockID(i)) { r[i] = 1 }
        }
        rule = r
    }

    @inline(__always) static func ruleOf(_ b: BlockID) -> UInt8 {
        if rule.isEmpty { build() }
        return Int(b) < rule.count ? rule[Int(b)] : 0
    }

    // Does the plant at p still have what holds it?
    static func supported(_ w: World, _ p: IVec3, _ b: BlockID) -> Bool {
        let g = Blocks.groupBase[Int(b)]
        func holds(_ q: IVec3) -> Bool {
            let o = w.block(q.x, q.y, q.z)
            return Blocks.collide[Int(o)] || Blocks.groupBase[Int(o)] == g
        }
        switch ruleOf(b) {
        case 1:
            // Standing: something solid under it, or more of the same plant (a cane stack, a tall flower's lower half).
            // A thin non-solid floor that isn't a plant or a liquid (a snow layer, a carpet) still holds it.
            let q = IVec3(p.x, p.y - 1, p.z)
            let below = w.block(q.x, q.y, q.z)
            if below == AIR { return false }
            if holds(q) { return true }
            return !Blocks.isLiquid(below) && !Blocks.isPlant(below)
        case 2:
            // Hanging: a ceiling, or more hanging plant above (cave vines with and without berries, weeping vines).
            let q = IVec3(p.x, p.y + 1, p.z)
            return holds(q) || ruleOf(w.block(q.x, q.y, q.z)) == 2
        case 3:
            // Water plants: the seabed or more of a water plant under them (kelp stacks, tall seagrass).
            let q = IVec3(p.x, p.y - 1, p.z)
            return holds(q) || ruleOf(w.block(q.x, q.y, q.z)) == 3
        case 4:
            // Vines: a vine above, or a solid side block or ceiling to cling to.
            if holds(IVec3(p.x, p.y + 1, p.z)) { return true }
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let o = w.block(p.x + d.x, p.y, p.z + d.z)
                if Blocks.collide[Int(o)] && Blocks.opaque[Int(o)] { return true }
            }
            return false
        default:
            return true
        }
    }
}

extension Game {
    // Pops the plant at p if nothing holds it (called for every changed cell and its neighbours).
    func plantSupportCheck(_ p: IVec3) -> Bool {
        let b = world.block(p.x, p.y, p.z)
        guard b != AIR, PlantSupport.ruleOf(b) != 0, !PlantSupport.supported(world, p, b) else { return false }
        let leave: BlockID = PlantSupport.ruleOf(b) == 3 ? WATER : AIR
        world.setBlock(p.x, p.y, p.z, leave)
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.3, Float(p.z) + 0.5)
        for s in Mining.drops(b, .empty) where !s.isEmpty { drops.spawn(s, at: at) }
        particles.blockBreak(b, at: p)
        return true
    }
}

// --plantcheck: build every kind of supported stack, break its base (or ceiling), let the world tick, and check that
// nothing is left floating and that the pieces dropped.
enum PlantCheck {
    static func run(_ g: Game) -> Int {
        let w = g.world
        let p = g.player.pos
        var fails = 0
        func check(_ ok: Bool, _ what: String) {
            print("plantcheck: \(ok ? "PASS" : "FAIL") \(what)")
            if !ok { fails += 1 }
        }
        // A clear 3x3 column of air per case, on a stone floor, starting a few blocks beside the player.
        let floorY = Int(floor(p.y)) + 2
        var cx = Int(floor(p.x)) + 4
        let cz = Int(floor(p.z)) + 4
        func site(_ height: Int) -> Int {
            let x = cx
            cx += 6
            for dx in -2...2 { for dz in -2...2 {
                w.setBlock(x + dx, floorY - 1, cz + dz, STONE)
                for y in floorY...(floorY + height + 2) { w.setBlock(x + dx, y, cz + dz, AIR) }
            } }
            return x
        }
        func settle() { for _ in 0..<40 { g.gravityTick() } }
        func count(_ x: Int, _ y0: Int, _ y1: Int, _ id: BlockID) -> Int {
            (y0...y1).filter { Blocks.groupBase[Int(w.block(x, $0, cz))] == Blocks.groupBase[Int(id)] }.count
        }
        func dropsNear(_ x: Int, _ item: String) -> Int {
            guard Items.has(item) else { return 0 }
            let it = Items.id(item)
            return g.drops.items.filter { $0.stack.item == it && abs($0.pos.x - (Float(x) + 0.5)) < 1.5 && abs($0.pos.z - (Float(cz) + 0.5)) < 1.5 }
                .reduce(0) { $0 + $1.stack.count }
        }
        let keepSurvival = g.survival
        g.survival = true
        settle()
        // Standing stacks: break the bottom block.
        for (key, ground, h) in [("sugar_cane", "sand", 6), ("cactus", "sand", 5), ("bamboo", "dirt", 7)] where Blocks.has(key) {
            let x = site(h + 1)
            w.setBlock(x, floorY, cz, Blocks.id(ground))
            let id = Blocks.id(key)
            for y in 1...h { w.setBlock(x, floorY + y, cz, id) }
            settle()
            check(count(x, floorY + 1, floorY + h, id) == h, "\(key) stack of \(h) stands before")
            g.breakBlock(IVec3(x, floorY + 1, cz), id, drop: true)
            settle()
            let left = count(x, floorY + 1, floorY + h, id)
            check(left == 0, "\(key): breaking the bottom of \(h) pops the rest (\(left) left floating, \(dropsNear(x, key)) dropped)")
        }
        // The ground under a cane stack dug out.
        if Blocks.has("sugar_cane") {
            let x = site(5)
            let id = Blocks.id("sugar_cane")
            w.setBlock(x, floorY, cz, SAND)
            for y in 1...4 { w.setBlock(x, floorY + y, cz, id) }
            settle()
            g.breakBlock(IVec3(x, floorY, cz), SAND, drop: true)
            settle()
            check(count(x, floorY + 1, floorY + 4, id) == 0, "sugar cane: digging out the sand under it pops all 4")
        }
        // A two-block flower loses its upper half with the lower.
        for key in ["tall_grass", "lilac", "rose_bush", "sunflower"] where Blocks.has(key) {
            let x = site(3)
            w.setBlock(x, floorY, cz, GRASS)
            let lower = Blocks.id(key)
            let upper = Blocks.has("\(key)[upper]") ? Blocks.id("\(key)[upper]") : lower
            w.setBlock(x, floorY + 1, cz, lower); w.setBlock(x, floorY + 2, cz, upper)
            g.breakBlock(IVec3(x, floorY, cz), GRASS, drop: true)
            settle()
            check(w.block(x, floorY + 1, cz) == AIR && w.block(x, floorY + 2, cz) == AIR, "\(key): both halves go with the ground")
            break
        }
        // Hanging vines: break the ceiling.
        for key in ["weeping_vines", "cave_vines"] where Blocks.has(key) {
            let x = site(7)
            let id = Blocks.id(key)
            let top = floorY + 7
            w.setBlock(x, top, cz, STONE)
            for y in (top - 4)...(top - 1) { w.setBlock(x, y, cz, id) }
            settle()
            g.breakBlock(IVec3(x, top, cz), STONE, drop: true)
            settle()
            let left = count(x, top - 4, top - 1, id)
            check(left == 0, "\(key): breaking the ceiling drops all 4 (\(left) left hanging)")
        }
        // Kelp in a water column: break the bottom, the rest pops and water stays.
        if Blocks.has("kelp") {
            let x = site(6)
            let id = Blocks.id("kelp")
            for dx in -1...1 { for dz in -1...1 where dx != 0 || dz != 0 {
                for y in floorY...(floorY + 6) { w.setBlock(x + dx, y, cz + dz, STONE) }
            } }
            w.setBlock(x, floorY, cz, SAND)
            for y in 1...5 { w.setBlock(x, floorY + y, cz, id) }
            w.setBlock(x, floorY + 6, cz, WATER)
            settle()
            g.breakBlock(IVec3(x, floorY + 1, cz), id, drop: true)
            settle()
            let left = count(x, floorY + 2, floorY + 5, id)
            check(left == 0, "kelp: breaking the bottom pops the 4 above (\(left) left)")
            check(Blocks.isLiquid(w.block(x, floorY + 3, cz)), "kelp: the column is water after")
        }
        // A vine on a log: break the log and the vine (and the one hanging under it) go.
        if Blocks.has("vine") && Blocks.has("oak_log") {
            let x = site(5)
            let log = Blocks.id("oak_log"), vine = Blocks.id("vine")
            w.setBlock(x, floorY + 3, cz, log)
            w.setBlock(x + 1, floorY + 3, cz, vine); w.setBlock(x + 1, floorY + 2, cz, vine)
            settle()
            check(w.block(x + 1, floorY + 3, cz) == vine && w.block(x + 1, floorY + 2, cz) == vine, "vine: hangs on the log before")
            g.breakBlock(IVec3(x, floorY + 3, cz), log, drop: true)
            settle()
            check(w.block(x + 1, floorY + 3, cz) == AIR && w.block(x + 1, floorY + 2, cz) == AIR, "vine: both go with the log")
        }
        // A lantern hanging from a ceiling that is broken.
        if Blocks.has("lantern[hanging]") {
            let x = site(4)
            let top = floorY + 4
            w.setBlock(x, top, cz, STONE); w.setBlock(x, top - 1, cz, Blocks.id("lantern[hanging]"))
            settle()
            check(w.block(x, top - 1, cz) != AIR, "lantern: hangs from its ceiling before")
            g.breakBlock(IVec3(x, top, cz), STONE, drop: true)
            settle()
            check(w.block(x, top - 1, cz) == AIR, "lantern: falls with the ceiling it hung from")
        }
        // A carpet and a rail on blocks that go.
        for key in ["white_carpet", "rail"] where Blocks.has(key) {
            let x = site(2)
            let b = Blocks.id(key)
            w.setBlock(x, floorY, cz, STONE); w.setBlock(x, floorY + 1, cz, b)
            settle()
            g.breakBlock(IVec3(x, floorY, cz), STONE, drop: true)
            settle()
            check(w.block(x, floorY + 1, cz) == AIR, "\(key): pops when the block under it is broken")
        }
        // A flower on a block blown away by something other than the player (World.setBlock alone).
        if Blocks.has("poppy") {
            let x = site(2)
            let f = Blocks.id("poppy")
            w.setBlock(x, floorY, cz, GRASS); w.setBlock(x, floorY + 1, cz, f)
            settle()
            w.setBlock(x, floorY, cz, AIR)
            settle()
            check(w.block(x, floorY + 1, cz) == AIR, "a flower whose ground is removed by the world (an explosion, a piston) pops too")
        }
        g.survival = keepSurvival
        print("plantcheck: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails
    }
}
