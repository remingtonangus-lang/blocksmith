import Foundation
import simd

// Remington's Quest playtest of 2026-10-09 PM, items 3, 4, 7, 8: plant density per biome (old vs new generator on the
// same seed), surface vs cave spawning (old vs new share on the same world), bone meal on every plant it grows (through
// Game.useItemOnBlock), leather drops. Run with `--questbugs --only pm9b`. Lines starting "pm9b-table:" are the
// evidence tables (docs/status/evidence/2026-10-09-pm/).
enum PlaytestPM9BTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        plants(game, check)
        spawning(game, check)
        boneMeal(game, check)
        leather(game, check)
    }

    // MARK: 3. Plants

    static let plantKeys = ["short_grass", "tall_grass", "fern", "large_fern", "flowers", "tall_flowers", "dead_bush", "cactus",
                            "sugar_cane", "sweet_berry_bush", "mushrooms", "kelp", "seagrass", "lily_pad", "leaf_litter",
                            "wildflowers", "pink_petals", "pumpkin", "melon", "bush", "firefly_bush", "short_dry_grass",
                            "tall_dry_grass", "bamboo"]

    // The middle of a biome: spiral out in 64-block steps until the centre and 8 points 40 blocks out all match.
    static func find(_ gen: WorldGen, _ want: String) -> (Int, Int)? {
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<20000 {
            let wx = x * 64 + 8, wz = z * 64 + 8
            let probes = [(0, 0), (40, 0), (-40, 0), (0, 40), (0, -40), (40, 40), (-40, 40), (40, -40), (-40, -40)]
            if probes.allSatisfy({ gen.column(wx + $0.0, wz + $0.1).biome.name == want }) { return (wx, wz) }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        return nil
    }

    // Plants per 256 columns of the biome over 5 x 5 chunks around (x, z).
    static func count(_ gen: WorldGen, _ biome: String, _ x0: Int, _ z0: Int) -> (cols: Int, n: [String: Int]) {
        var n: [String: Int] = [:], cols = 0
        let small = Game.boneMealSmallFlowers, tall: Set<String> = ["sunflower", "lilac", "rose_bush", "peony"]
        let cx0 = floorDiv(x0, CS) - 2, cz0 = floorDiv(z0, CS) - 2
        let leafy = Set((0..<Blocks.count).filter { k in let s = Blocks.key(BlockID(k)); return s.hasSuffix("_leaves") || s.hasSuffix("_log") }.map { BlockID($0) })
        for cz in cz0..<(cz0 + 5) { for cx in cx0..<(cx0 + 5) {
            let b = gen.generate(cx: cx, cz: cz)
            for lz in 0..<CS { for lx in 0..<CS {
                guard gen.column(cx * CS + lx, cz * CS + lz).biome.name == biome else { continue }
                cols += 1
                var y = CH - 2
                while y > 1 {
                    let id = b[Chunk.index(lx, y, lz)]
                    if Blocks.opaque[Int(id)] && !leafy.contains(id) && Blocks.key(Blocks.groupBase[Int(id)]) != "melon" && Blocks.key(Blocks.groupBase[Int(id)]) != "pumpkin" { break }
                    let base = Blocks.groupBase[Int(id)]
                    if id != AIR && Blocks.groupBase[Int(b[Chunk.index(lx, y - 1, lz)])] != base {
                        var k = Blocks.key(base)
                        if small.contains(k) { k = "flowers" } else if tall.contains(k) { k = "tall_flowers" }
                        else if k == "red_mushroom" || k == "brown_mushroom" { k = "mushrooms" }
                        if plantKeys.contains(k) { n[k, default: 0] += 1 }
                    }
                    y -= 1
                }
            } }
        } }
        return (cols, n)
    }

    static func plants(_ game: Game, _ check: (Bool, String) -> Void) {
        let seed = game.world.seed
        let oldGen = WorldGen(seed: seed), newGen = WorldGen(seed: seed)
        oldGen.plantsBeforePM9 = true
        print("pm9b-table: | biome | plant | before /chunk | after /chunk |")
        print("pm9b-table: |---|---|---|---|")
        var grassOld: Float = 0, grassNew: Float = 0
        // Target ranges per 256 columns (after): ground cover reads as sparse, not a carpet.
        for biome in ["plains", "forest", "desert", "savanna", "jungle", "taiga", "swamp", "dark_forest", "birch_forest"] {
            guard let (x, z) = find(newGen, biome) else { check(false, "plants: no \(biome) found"); continue }
            let a = count(oldGen, biome, x, z), b = count(newGen, biome, x, z)
            guard a.cols > 1000 && b.cols == a.cols else { check(false, "plants: \(biome) at \(x), \(z): only \(a.cols) columns"); continue }
            func per(_ c: Int, _ cols: Int) -> Float { Float(c) * 256 / Float(cols) }
            var line: [String] = []
            for k in plantKeys {
                let o = a.n[k] ?? 0, nn = b.n[k] ?? 0
                guard o > 0 || nn > 0 else { continue }
                print(String(format: "pm9b-table: | %@ | %@ | %.2f | %.2f |", biome, k, per(o, a.cols), per(nn, b.cols)))
                line.append(String(format: "%@ %.1f->%.1f", k, per(o, a.cols), per(nn, b.cols)))
                if k != "short_grass" && k != "cactus" {
                    check(nn <= o + max(2, o / 10), String(format: "plants: %@ %@ not denser than before (%d -> %d)", biome, k, o, nn))
                }
            }
            print("pm9b: \(biome) at \(x), \(z), \(a.cols) columns: " + line.joined(separator: ", "))
            let og = a.n["short_grass"] ?? 0, ng = b.n["short_grass"] ?? 0
            let ratio = Float(ng) / Float(max(1, og))
            grassOld += per(og, a.cols); grassNew += per(ng, b.cols)
            // Per biome a few dozen blades decide it: 1/8 with room for sampling noise; the sum over biomes below is strict.
            check(og < 20 || ratio <= 0.2, String(format: "plants: %@ short grass %.1f -> %.1f per chunk (x%.3f, want ~1/8)", biome, per(og, a.cols), per(ng, b.cols), ratio))
            let total = plantKeys.reduce(0) { $0 + (b.n[$1] ?? 0) } - (b.n["kelp"] ?? 0) - (b.n["seagrass"] ?? 0) - (b.n["bamboo"] ?? 0)
            let before = plantKeys.reduce(0) { $0 + (a.n[$1] ?? 0) } - (a.n["kelp"] ?? 0) - (a.n["seagrass"] ?? 0) - (a.n["bamboo"] ?? 0)
            check(per(total, b.cols) <= 22, String(format: "plants: %@ land plants %.1f -> %.1f per chunk (want <= 22: about one column in 12)", biome, per(before, a.cols), per(total, b.cols)))
            if biome == "desert" {
                let c = per(b.n["cactus"] ?? 0, b.cols), co = per(a.n["cactus"] ?? 0, a.cols)
                // One cactus per 256-400 blocks of desert: one every ~16-20 blocks.
                check(c >= 0.25 && c <= 1.0, String(format: "plants: desert cacti %.2f -> %.2f per chunk (want 0.25-1.0: one every 16-32 blocks)", co, c))
                let dead = per(b.n["dead_bush"] ?? 0, b.cols)
                check(dead >= 0.3 && dead <= 2.5, String(format: "plants: desert dead bushes %.2f per chunk (want 0.3-2.5)", dead))
            }
        }
        check(grassNew <= grassOld / 8, String(format: "plants: short grass over all nine biomes %.1f -> %.1f per chunk (x%.3f, want <= 1/8)", grassOld, grassNew, grassNew / max(0.01, grassOld)))
    }

    // MARK: 4. Spawning

    static func spawning(_ game: Game, _ check: (Bool, String) -> Void) {
        let w = game.world, p = game.player, mm = game.mobs
        let save = (game.survival, game.difficulty, game.time, w.renderDistance, p.pos, mm.mobs, mm.populated, MobManager.surfaceSpawnScale)
        defer { (game.survival, game.difficulty, game.time, w.renderDistance, p.pos, mm.mobs, mm.populated, MobManager.surfaceSpawnScale) = save }
        game.survival = true; game.difficulty = 2; game.time = 0.75 * DAY_LENGTH
        w.renderDistance = 6
        func run(_ at: V3, secs: Int) -> (surface: Int, under: Int) {
            p.pos = at
            mm.mobs.removeAll { $0.kind.category == .monster }
            for _ in 0..<(secs * 4) { mm.hostileAttempts(game) }
            let ms = mm.mobs.filter { $0.kind.category == .monster }
            let under = ms.filter { Int(floor($0.pos.y)) < w.topY(Int(floor($0.pos.x)), Int(floor($0.pos.z))) - 8 }.count
            return (ms.count - under, under)
        }
        let sx = Int(floor(save.4.x)), sz = Int(floor(save.4.z))
        let surfaceAt = V3(Float(sx) + 0.5, Float(w.topY(sx, sz) + 1), Float(sz) + 0.5)
        var cave: V3?
        search: for r in stride(from: 0, through: 40, by: 4) { for dx in stride(from: -r, through: r, by: 4) { for dz in [-r, r] {
            let x = sx + dx, z = sz + dz, top = w.topY(x, z)
            guard top > 20 else { continue }
            for y in stride(from: top - 12, to: 8, by: -1) where Blocks.opaque[Int(w.block(x, y - 1, z))] && w.block(x, y, z) == AIR && w.block(x, y + 1, z) == AIR && w.lightAt(x, y, z).sky == 0 {
                cave = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5); break search
            }
        } } }
        var res: [Float: (surf: Int, caveUnder: Int, animals: Int)] = [:]
        let creatureKeys = Set(MobKind.allCases.filter { $0.category == .creature })
        for scale: Float in [1, 0.5] {
            MobManager.surfaceSpawnScale = scale
            var surf = 0, under = 0
            for _ in 0..<3 { surf += run(surfaceAt, secs: 60).surface }        // three 60 s nights
            if let c = cave { for _ in 0..<3 { under += run(c, secs: 60).under } }
            // Animal packs in the chunks around the spawn, as they first load.
            mm.mobs.removeAll { creatureKeys.contains($0.kind) }
            mm.populated.removeAll()
            for _ in 0..<(w.chunks.count / 12 + 2) { mm.populateChunks(game) }
            let animals = mm.mobs.filter { creatureKeys.contains($0.kind) }.count
            res[scale] = (surf, under, animals)
            print("pm9b: spawning scale \(scale): night surface \(surf) (3 x 60 s), cave \(under) underground (3 x 60 s), \(animals) animals over \(w.chunks.count) chunks")
        }
        guard let o = res[1], let n = res[0.5] else { return }
        let rs = Float(n.surf) / Float(max(1, o.surf))
        check(o.surf >= 20 && rs >= 0.35 && rs <= 0.65, String(format: "spawning: night surface monsters %d -> %d (x%.2f, want ~0.5)", o.surf, n.surf, rs))
        check(cave != nil && n.caveUnder >= 6 && Float(n.caveUnder) >= 0.75 * Float(o.caveUnder),
              "spawning: cave monsters kept: \(o.caveUnder) -> \(n.caveUnder) (want >= 6 and >= 0.75x)")
        let ra = Float(n.animals) / Float(max(1, o.animals))
        check(o.animals >= 6 && ra <= 0.75, String(format: "spawning: animals in the chunks around the spawn %d -> %d (x%.2f, want ~0.5)", o.animals, n.animals, ra))
        // The pack roll itself (populateChunks' per-chunk roll) over many chunks: the exact share.
        var rolls = (0, 0)
        for cz in -60..<60 { for cx in -60..<60 {
            var rng = SRng(UInt64(hash3(cx, 7, cz, 0xA41A1)) | 1)
            let f = rng.float()
            if f < 0.035 { rolls.0 += 1 }
            if f < 0.035 * save.7 { rolls.1 += 1 }
        } }
        let rr = Float(rolls.1) / Float(max(1, rolls.0))
        check(rr >= 0.45 && rr <= 0.55, String(format: "spawning: animal packs over 14400 new chunks %d -> %d (x%.2f, want ~0.5)", rolls.0, rolls.1, rr))
        check(save.7 == 0.5, "spawning: the game runs at half the surface density (scale \(save.7))")
    }

    // MARK: 7. Bone meal

    static func boneMeal(_ game: Game, _ check: (Bool, String) -> Void) {
        let p = game.player, w = game.world
        let save = (p.pos, game.survival, game.inventory.held)
        defer { (p.pos, game.survival) = (save.0, save.1); game.inventory.held = save.2 }
        game.survival = true
        let bx = Int(floor(p.pos.x)), bz = Int(floor(p.pos.z)), by = Int(floor(p.pos.y)) + 70
        func g(_ k: String) -> BlockID { Blocks.id(k) }
        func set(_ x: Int, _ y: Int, _ z: Int, _ k: BlockID) { w.setBlock(x, y, z, k) }
        // A grass floor at by - 1 over 17 x 17, air above to by + 30.
        func reset() {
            for x in (bx - 8)...(bx + 8) { for z in (bz - 8)...(bz + 8) {
                for y in (by - 3)...(by + 30) {
                    let want: BlockID = y == by - 1 ? GRASS : (y < by - 1 ? STONE : AIR)
                    if w.block(x, y, z) != want { set(x, y, z, want) }
                }
            } }
            game.drops.items.removeAll()
        }
        defer { for x in (bx - 8)...(bx + 8) { for z in (bz - 8)...(bz + 8) { for y in (by - 3)...(by + 30) where w.block(x, y, z) != AIR { set(x, y, z, AIR) } } } }
        func snapshot() -> [BlockID] {
            var s: [BlockID] = []
            for x in (bx - 8)...(bx + 8) { for z in (bz - 8)...(bz + 8) { for y in (by - 3)...(by + 30) { s.append(w.block(x, y, z)) } } }
            return s
        }
        let meal = Items.id("bone_meal")
        var rows: [String] = []
        // Apply bone meal at `at` (up to `tries` times until something changes); returns (changed, used per try ok, uses).
        func apply(_ at: IVec3, tries: Int) -> (changed: Bool, uses: Int, consumed: Int, dropped: Int) {
            game.inventory.held = ItemStack(meal, 64)
            let s0 = snapshot()
            var uses = 0, changed = false
            for _ in 0..<tries {
                let ok = game.useItemOnBlock((hit: at, normal: IVec3(0, 1, 0)))
                if ok { uses += 1 }
                let dropped = game.drops.items.filter { !$0.stack.isEmpty }.count
                if snapshot() != s0 || dropped > 0 { changed = true; break }
                if !ok { break }
            }
            let left = game.inventory.held.item == meal ? game.inventory.held.count : 0
            return (changed, uses, 64 - left, game.drops.items.filter { !$0.stack.isEmpty }.count)
        }
        let c = IVec3(bx, by, bz)
        typealias Case = (name: String, setup: () -> IVec3, tries: Int, expect: String)
        var cases: [Case] = []
        func plant(_ k: String, on ground: BlockID = GRASS, tries: Int = 1, expect: String) {
            guard Blocks.has(k) else { rows.append("| \(k) | (not in the game) | - |"); return }
            cases.append((k, { set(c.x, c.y - 1, c.z, ground); set(c.x, c.y, c.z, g(k)); return c }, tries, expect))
        }
        let farmland = g("farmland")
        for k in ["wheat", "carrots", "potatoes", "beetroots", "torchflower_crop", "pitcher_crop"] { plant(k, on: farmland, tries: 4, expect: "grows a stage (or more)") }
        let saplings = (0..<Blocks.count).map { Blocks.key(BlockID($0)) }.filter { $0.hasSuffix("_sapling") && !$0.contains("[") && Blocks.groupBase[Int(Blocks.id($0))] == Blocks.id($0) }
        for k in saplings + ["mangrove_propagule", "azalea", "flowering_azalea"] where Blocks.has(k) {
            let square = k == "dark_oak_sapling" || k == "pale_oak_sapling"
            cases.append((k, {
                for q in square ? [c, c + IVec3(1, 0, 0), c + IVec3(0, 0, 1), c + IVec3(1, 0, 1)] : [c] { set(q.x, q.y, q.z, g(k)) }
                if k == "mangrove_propagule" { set(c.x, c.y - 1, c.z, g("mud")) }
                return c
            }, 40, square ? "a 2x2 grows a big tree" : "grows a tree (45% a use, two stages)"))
        }
        for k in ["red_mushroom", "brown_mushroom"] { plant(k, on: MYCELIUM, tries: 40, expect: "huge mushroom (40%)") }
        plant("crimson_fungus", on: g("crimson_nylium"), tries: 40, expect: "huge fungus on its nylium (40%)")
        plant("warped_fungus", on: g("warped_nylium"), tries: 40, expect: "huge fungus on its nylium (40%)")
        for k in ["crimson_nylium", "warped_nylium", "moss_block", "pale_moss_block"] where Blocks.has(k) {
            cases.append((k, { set(c.x, c.y - 1, c.z, g(k)); return c + IVec3(0, -1, 0) }, 1, k.hasSuffix("nylium") ? "roots and fungi on the nylium around" : "moss spreads, carpets"))
        }
        cases.append(("netherrack (beside nylium)", {
            set(c.x, c.y - 1, c.z, NETHERRACK); set(c.x + 1, c.y - 1, c.z, g("crimson_nylium")); return c + IVec3(0, -1, 0)
        }, 1, "turns into the nylium beside it"))
        cases.append(("grass_block", { c + IVec3(0, -1, 0) }, 1, "grass and flowers around"))
        for k in ["sugar_cane", "cactus"] {
            cases.append((k, {
                set(c.x, c.y - 1, c.z, SAND); set(c.x + 1, c.y - 1, c.z, WATER); set(c.x, c.y, c.z, g(k)); return c
            }, 1, "grows to full height 3"))
        }
        plant("bamboo", tries: 1, expect: "grows 1-2 blocks")
        plant("sweet_berry_bush", tries: 1, expect: "next stage")
        if Blocks.has("cocoa") {
            cases.append(("cocoa", { set(c.x, c.y, c.z - 1, g("jungle_log")); set(c.x, c.y, c.z, g("cocoa")); return c }, 1, "next stage"))
        }
        cases.append(("kelp", {
            set(c.x, c.y - 1, c.z, SAND); for y in 0..<6 { set(c.x, c.y + y, c.z, WATER) }; set(c.x, c.y, c.z, g("kelp")); return c
        }, 1, "grows a block up the water"))
        cases.append(("seagrass", {
            for dx in -2...2 { for dz in -2...2 { set(c.x + dx, c.y - 1, c.z + dz, SAND); for y in 0..<3 { set(c.x + dx, c.y + y, c.z + dz, WATER) } } }
            set(c.x, c.y, c.z, g("seagrass")); return c
        }, 1, "seagrass spreads over the floor"))
        cases.append(("sand under water", {
            for dx in -2...2 { for dz in -2...2 { set(c.x + dx, c.y - 1, c.z + dz, SAND); for y in 0..<3 { set(c.x + dx, c.y + y, c.z + dz, WATER) } } }
            return c + IVec3(0, -1, 0)
        }, 1, "seagrass sprouts"))
        if Blocks.has("sea_pickle") {
            cases.append(("sea_pickle (on coral)", {
                for dx in -2...2 { for dz in -2...2 { set(c.x + dx, c.y - 1, c.z + dz, g("brain_coral_block")); for y in 0..<3 { set(c.x + dx, c.y + y, c.z + dz, WATER) } } }
                set(c.x, c.y, c.z, g("sea_pickle")); return c
            }, 1, "more pickles, spread onto coral"))
        }
        plant("twisting_vines", on: NETHERRACK, tries: 1, expect: "grows 1-3 up")
        for k in ["weeping_vines", "cave_vines"] where Blocks.has(k) {
            cases.append((k, { set(c.x, c.y + 6, c.z, NETHERRACK); set(c.x, c.y + 5, c.z, g(k)); return c + IVec3(0, 5, 0) }, 1, k == "cave_vines" ? "grows down (every cave vine bears berries)" : "grows 1-3 down"))
        }
        plant("small_dripleaf", tries: 1, expect: "becomes a big dripleaf 2-5 tall")
        plant("big_dripleaf", tries: 1, expect: "grows a block taller")
        for k in ["short_grass", "fern"] { plant(k, tries: 1, expect: k == "fern" ? "large fern" : "tall grass") }
        plant("short_dry_grass", on: SAND, tries: 1, expect: "tall dry grass")
        for k in Game.boneMealSmallFlowers.sorted() { plant(k, tries: 1, expect: "more of it on the grass around") }
        for k in ["sunflower", "lilac", "rose_bush", "peony"] where Blocks.has(k) {
            cases.append((k, { set(c.x, c.y, c.z, g(k)); set(c.x, c.y + 1, c.z, g(k) + 1); return c }, 1, "drops a copy"))
        }
        for k in ["pink_petals", "wildflowers"] { plant(k, tries: 1, expect: "drops a copy") }
        for k in ["bush", "firefly_bush"] { plant(k, tries: 1, expect: "spreads beside it") }
        cases.append(("rooted_dirt", { set(c.x, c.y + 4, c.z, g("rooted_dirt")); return c + IVec3(0, 4, 0) }, 1, "hanging roots below"))

        var fails: [String] = []
        for cs in cases {
            reset()
            let at = cs.setup()
            let r = apply(at, tries: cs.tries)
            let ok = r.changed && r.uses >= 1 && r.consumed == r.uses
            rows.append("| \(cs.name) | \(cs.expect) | \(ok ? "yes" : "NO") (\(r.uses) used) |")
            if !ok { fails.append("\(cs.name) (changed \(r.changed), uses \(r.uses), consumed \(r.consumed))") }
        }
        check(fails.isEmpty, "bone meal: \(cases.count) targets grow and use bone meal" + (fails.isEmpty ? "" : "; failed: " + fails.joined(separator: ", ")))
        // Non-targets (Bedrock): nothing happens and no bone meal is used.
        var wrong: [String] = []
        for k in ["dead_bush", "lily_pad", "vine", "nether_wart", "torchflower", "pitcher_plant", "leaf_litter", "tall_dry_grass", "cactus_flower", "crimson_roots"] where Blocks.has(k) {
            reset()
            let ground: BlockID = k == "nether_wart" ? g("soul_sand") : (k == "lily_pad" ? WATER : (k == "cactus_flower" ? CACTUS : GRASS))
            set(c.x, c.y - 1, c.z, ground); set(c.x, c.y, c.z, g(k))
            let r = apply(c, tries: 1)
            rows.append("| \(k) | nothing (Bedrock) | \(r.changed || r.consumed > 0 ? "WRONG" : "nothing") |")
            if r.changed || r.consumed > 0 { wrong.append(k) }
        }
        reset()
        check(wrong.isEmpty, "bone meal: non-targets (dead bush, lily pad, vine, wart, torchflower, ...) unchanged and keep the bone meal" + (wrong.isEmpty ? "" : ": " + wrong.joined(separator: ", ")))
        // Sugar cane to exactly 3 from 1 and 2; never taller.
        for start in 1...3 {
            reset()
            set(c.x, c.y - 1, c.z, SAND); set(c.x + 1, c.y - 1, c.z, WATER)
            for y in 0..<start { set(c.x, c.y + y, c.z, g("sugar_cane")) }
            game.inventory.held = ItemStack(meal, 64)
            let used = game.useItemOnBlock((hit: c, normal: IVec3(0, 1, 0)))
            var h = 0
            while w.block(c.x, c.y + h, c.z) == g("sugar_cane") { h += 1 }
            check(h == 3 && used == (start < 3), "bone meal: sugar cane \(start) tall -> \(h) (want 3), bone meal used \(used)")
        }
        reset()
        for r in rows { print("pm9b-bonemeal: \(r)") }
    }

    // MARK: 8. Leather

    static func leather(_ game: Game, _ check: (Bool, String) -> Void) {
        let p = game.player
        let leatherID = Items.id("leather")
        for kind in [MobKind.cow, .mooshroom, .horse, .llama] {
            game.drops.items.removeAll()
            let n = 400
            for _ in 0..<n {
                let m = Mob(kind, at: p.pos + V3(3, 0, 0))
                m.killedByPlayer = true
                game.mobDied(m)
            }
            let total = game.drops.items.filter { $0.stack.item == leatherID }.reduce(0) { $0 + $1.stack.count }
            game.drops.items.removeAll()
            let avg = Float(total) / Float(n)
            check(avg >= 1.8 && avg <= 2.2, String(format: "leather: %@ drops %.2f a kill (was 1.0 from 0-2; want ~2 from 1-3)", kind.spec.name, avg))
        }
    }
}
