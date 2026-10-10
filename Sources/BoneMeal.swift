import Foundation
import simd

// Bone meal, one place for every plant (playtest Oct 9 PM #7: "bone meal doesn't work on sugar cane"). Follows the
// Bedrock rules: crops, saplings (mangrove propagule, azaleas), grass blocks, sugar cane and cactus (to full height 3),
// bamboo, berry bushes, cocoa, kelp, seagrass and underwater floors, sea pickles on coral, mushrooms (huge mushroom),
// fungi on their nylium (huge fungus), nylium and netherrack beside it, twisting / weeping / cave vines, dripleaves,
// moss, small flowers (more around them), tall flowers / petals / wildflowers (a copy drops), short grass, ferns and
// dry grass (tall versions), bushes, rooted dirt. Not: dead bushes, lily pads, vines, wart, torchflowers, pitcher
// plants, leaf litter. The player path (Farming.useItemOnBlock) and dispensers share `boneMealGrow`.
// Audit table: docs/status/evidence/2026-10-09-pm/bonemeal.md; check: `--questbugs --only pm9b`.
extension Game {
    static let boneMealSmallFlowers: Set<String> = ["dandelion", "poppy", "allium", "azure_bluet", "red_tulip", "orange_tulip",
                                                    "white_tulip", "pink_tulip", "oxeye_daisy", "cornflower", "lily_of_the_valley",
                                                    "blue_orchid"]
    static let boneMealDropCopy: Set<String> = ["sunflower", "lilac", "rose_bush", "peony", "pink_petals", "wildflowers"]

    // The player's bone meal on a block: grows it, uses one bone meal, hearts. False when the block isn't a target.
    func useBoneMeal(_ p: IVec3) -> Bool {
        guard boneMealGrow(p) else { return false }
        consumeHeld()
        particles.hearts(at: V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5))
        swing = 1
        return true
    }

    // Applies bone meal's effect at p. True when bone meal is used up (Bedrock: also on a failed sapling roll).
    func boneMealGrow(_ p: IVec3) -> Bool {
        let w = world
        let b = w.block(p.x, p.y, p.z)
        let base = Blocks.groupBase[Int(b)]
        let key = Blocks.key(base)
        let st = Int(b - base)
        func id(_ k: String) -> BlockID { Blocks.has(k) ? Blocks.id(k) : AIR }
        func at(_ q: IVec3) -> BlockID { w.block(q.x, q.y, q.z) }
        func dropCopy() {
            if Items.has(key) { drops.spawn(ItemStack(Items.id(key), 1), at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)) }
        }
        // A column of `id` through p: (bottom y, top y).
        func column(_ same: (BlockID) -> Bool) -> (Int, Int) {
            var lo = p.y, hi = p.y
            while lo > 1 && same(w.block(p.x, lo - 1, p.z)) { lo -= 1 }
            while hi < CH - 2 && same(w.block(p.x, hi + 1, p.z)) { hi += 1 }
            return (lo, hi)
        }
        let soil: Set<BlockID> = [GRASS, DIRT, id("podzol"), id("coarse_dirt"), id("rooted_dirt"), id("moss_block"), MYCELIUM, id("mud")]
        switch key {
        case "wheat", "carrots", "potatoes", "beetroots":
            let maxStage = key == "beetroots" ? 3 : 7
            guard st < maxStage else { return false }
            let step = key == "beetroots" ? Rand.int(in: 2...5) / 3 : Rand.int(in: 2...5)     // beetroot: +1 on 3 in 4
            if step > 0 { w.setBlock(p.x, p.y, p.z, base + BlockID(min(maxStage, st + step))) }
            return true
        case "torchflower_crop":
            w.setBlock(p.x, p.y, p.z, st < 1 ? b + 1 : id("torchflower"))
            return true
        case "pitcher_crop":
            guard st < 4 || Blocks.has("pitcher_plant") else { return false }
            w.setBlock(p.x, p.y, p.z, st < 4 ? b + 1 : id("pitcher_plant"))
            return true
        case _ where key.hasSuffix("_sapling") || key == "mangrove_propagule" || key == "azalea" || key == "flowering_azalea":
            if Rand.float(in: 0..<1) < 0.45 { saplingAdvance(p, key) }
            return true
        case "red_mushroom", "brown_mushroom":
            if Rand.float(in: 0..<1) < 0.4 { growTree(p, key) }
            return true
        case "crimson_fungus", "warped_fungus":
            let crimson = key == "crimson_fungus"
            guard at(p + IVec3(0, -1, 0)) == id(crimson ? "crimson_nylium" : "warped_nylium") else { return false }
            if Rand.float(in: 0..<1) < 0.4 { growHugeFungus(p, crimson: crimson) }
            return true
        case "crimson_nylium", "warped_nylium":
            guard at(p + IVec3(0, 1, 0)) == AIR else { return false }
            let crimson = key == "crimson_nylium"
            let plants = crimson ? [id("crimson_roots"), id("crimson_roots"), id("crimson_fungus"), id("warped_fungus")]
                                 : [id("warped_roots"), id("warped_roots"), id("warped_fungus"), id("crimson_fungus")]
            for _ in 0..<24 {
                let q = p + IVec3(Rand.int(in: -3...3), Rand.int(in: -1...1), Rand.int(in: -3...3))
                if at(q) == base && at(q + IVec3(0, 1, 0)) == AIR { w.setBlockAsync(q.x, q.y + 1, q.z, plants[Rand.int(in: 0..<plants.count)]) }
            }
            w.setBlock(p.x, p.y + 1, p.z, plants[0])
            return true
        case "netherrack":
            guard at(p + IVec3(0, 1, 0)) == AIR else { return false }
            var kinds: [BlockID] = []
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(1, 0, 1), IVec3(-1, 0, -1), IVec3(1, 0, -1), IVec3(-1, 0, 1),
                      IVec3(0, 1, 0), IVec3(0, -1, 0)] {
                let n = at(p + d)
                if n == id("crimson_nylium") || n == id("warped_nylium") { kinds.append(n) }
            }
            guard !kinds.isEmpty else { return false }
            w.setBlock(p.x, p.y, p.z, kinds[Rand.int(in: 0..<kinds.count)])
            return true
        case _ where b == GRASS:
            for _ in 0..<24 {
                let q = IVec3(p.x + Rand.int(in: -3...3), p.y, p.z + Rand.int(in: -3...3))
                if at(q) == GRASS && at(q + IVec3(0, 1, 0)) == AIR {
                    w.setBlockAsync(q.x, q.y + 1, q.z, Rand.float(in: 0..<1) < 0.85 ? TALL_GRASS : [RED_FLOWER, YELLOW_FLOWER][Rand.int(in: 0...1)])
                }
            }
            return true
        case "moss_block", "pale_moss_block":
            // Moss spreads over the stone and dirt around and sprouts carpets, grass and azaleas (reference feature).
            let carpet = id(key == "moss_block" ? "moss_carpet" : "pale_moss_carpet")
            let spreadable: Set<BlockID> = [STONE, DIRT, GRASS, id("podzol"), id("coarse_dirt"), id("deepslate"), id("tuff"), id("granite"),
                                            id("diorite"), id("andesite"), id("mycelium"), id("rooted_dirt")]
            var changed = false
            for dz in -3...3 { for dx in -3...3 where Rand.float(in: 0..<1) < 0.7 - 0.1 * Float(max(abs(dx), abs(dz))) {
                for dy in [0, 1, -1] {
                    let q = p + IVec3(dx, dy, dz)
                    let g = at(q)
                    guard (spreadable.contains(g) || g == base) && at(q + IVec3(0, 1, 0)) == AIR else { continue }
                    w.setBlockAsync(q.x, q.y, q.z, base)
                    let r = Rand.float(in: 0..<1)
                    let top: BlockID = r < 0.3 ? carpet : (r < 0.42 && key == "moss_block" ? TALL_GRASS : (r < 0.46 && key == "moss_block" ? id("azalea") : AIR))
                    if top != AIR { w.setBlockAsync(q.x, q.y + 1, q.z, top) }
                    changed = true
                    break
                }
            } }
            return changed
        case "sugar_cane", "cactus":
            // Bedrock: bone meal grows the stalk to its full height of 3.
            let (lo, hi) = column { Blocks.groupBase[Int($0)] == base }
            var y = hi + 1, grew = false
            while y - lo < 3 && w.block(p.x, y, p.z) == AIR { w.setBlock(p.x, y, p.z, b); y += 1; grew = true }
            return grew
        case "bamboo":
            let (lo, hi) = column { $0 == b }
            var y = hi + 1, n = 0
            let cap = 12 + Int(hash3(p.x, 0, p.z, 0xBA3B) % 5), len = Rand.int(in: 1...2)
            while n < len && y - lo < cap && w.block(p.x, y, p.z) == AIR { w.setBlock(p.x, y, p.z, b); y += 1; n += 1 }
            return n > 0
        case "sweet_berry_bush":
            guard st < 3 else { return false }
            w.setBlock(p.x, p.y, p.z, b + 1)
            return true
        case "cocoa":
            guard st < 2 else { return false }
            w.setBlock(p.x, p.y, p.z, b + 1)
            return true
        case "kelp":
            let (_, hi) = column { $0 == b }
            guard hi + 1 < CH - 1, w.block(p.x, hi + 1, p.z) == WATER else { return false }
            w.setBlock(p.x, hi + 1, p.z, b)
            return true
        case "seagrass":
            return spreadSeagrass(around: p + IVec3(0, -1, 0), base: p)
        case _ where [SAND, GRAVEL, DIRT, id("clay"), id("mud"), id("red_sand")].contains(b):
            // Underwater floors sprout seagrass (reference: bone meal on a water-covered floor).
            guard at(p + IVec3(0, 1, 0)) == WATER else { return false }
            return spreadSeagrass(around: p, base: p)
        case "sea_pickle":
            // On coral blocks a pickle spreads pickles onto the coral around it (reference).
            guard Blocks.key(at(p + IVec3(0, -1, 0))).hasSuffix("_coral_block") else { return false }
            if st < 3 { w.setBlock(p.x, p.y, p.z, b + 1) }
            for _ in 0..<12 {
                let q = p + IVec3(Rand.int(in: -2...2), Rand.int(in: -1...1), Rand.int(in: -2...2))
                if Blocks.key(at(q)).hasSuffix("_coral_block") && at(q + IVec3(0, 1, 0)) == WATER {
                    w.setBlockAsync(q.x, q.y + 1, q.z, base + BlockID(Rand.int(in: 0...3)))
                }
            }
            return true
        case "twisting_vines", "weeping_vines", "cave_vines":
            // Vines grow 1-3 blocks from their tip (up for twisting, down for the others). Every cave vine block here
            // carries glow berries, so bone meal on cave vines gives more berries, as in the reference.
            let up = key == "twisting_vines"
            let (lo, hi) = column { $0 == b }
            var y = up ? hi + 1 : lo - 1, n = 0
            let len = key == "cave_vines" ? 1 : Rand.int(in: 1...3)
            while n < len && y > 1 && y < CH - 1 && w.block(p.x, y, p.z) == AIR { w.setBlock(p.x, y, p.z, b); y += up ? 1 : -1; n += 1 }
            return n > 0
        case "small_dripleaf":
            // A small dripleaf becomes a big one 2-5 tall where there is room.
            let want = Rand.int(in: 2...5)
            var h = 1
            while h < want && w.block(p.x, p.y + h, p.z) == AIR { h += 1 }
            guard h >= 2, Blocks.has("big_dripleaf") else { return false }
            for k in 0..<(h - 1) { w.setBlock(p.x, p.y + k, p.z, id("big_dripleaf_stem")) }
            w.setBlock(p.x, p.y + h - 1, p.z, id("big_dripleaf"))
            return true
        case "big_dripleaf", "big_dripleaf_stem":
            let leaf = id("big_dripleaf"), stem = id("big_dripleaf_stem")
            let (_, hi) = column { $0 == leaf || $0 == stem }
            guard w.block(p.x, hi, p.z) == leaf, hi + 1 < CH - 1, w.block(p.x, hi + 1, p.z) == AIR else { return false }
            w.setBlock(p.x, hi + 1, p.z, leaf)
            w.setBlock(p.x, hi, p.z, stem)
            return true
        case "short_grass", "fern", "short_dry_grass":
            let tall = key == "short_grass" ? "tall_grass" : (key == "fern" ? "large_fern" : "tall_dry_grass")
            guard Blocks.has(tall) else { return false }
            let t = id(tall)
            if key == "short_dry_grass" { w.setBlock(p.x, p.y, p.z, t); return true }      // (one block tall)
            guard w.block(p.x, p.y + 1, p.z) == AIR else { return false }
            w.setBlock(p.x, p.y, p.z, t)
            w.setBlock(p.x, p.y + 1, p.z, t + 1)
            return true
        case _ where Game.boneMealSmallFlowers.contains(key):
            // Bedrock: more of the same flower grows on the grass around it.
            var n = 0
            for _ in 0..<16 where n < 4 {
                let q = p + IVec3(Rand.int(in: -2...2), Rand.int(in: -1...1), Rand.int(in: -2...2))
                if at(q) == AIR && soil.contains(at(q + IVec3(0, -1, 0))) { w.setBlockAsync(q.x, q.y, q.z, base); n += 1 }
            }
            return true
        case _ where Game.boneMealDropCopy.contains(key):
            dropCopy()
            return true
        case "bush", "firefly_bush":
            // A bush spreads to a free spot beside it.
            for _ in 0..<8 {
                let q = p + IVec3(Rand.int(in: -1...1), 0, Rand.int(in: -1...1))
                if at(q) == AIR && soil.contains(at(q + IVec3(0, -1, 0))) { w.setBlockAsync(q.x, q.y, q.z, base); return true }
            }
            return true
        case "rooted_dirt":
            guard at(p + IVec3(0, -1, 0)) == AIR, Blocks.has("hanging_roots") else { return false }
            w.setBlock(p.x, p.y - 1, p.z, id("hanging_roots"))
            return true
        default:
            return false
        }
    }

    // Seagrass on the water-covered floors around `around` (the block under the water).
    private func spreadSeagrass(around f: IVec3, base: IVec3) -> Bool {
        let w = world
        guard Blocks.has("seagrass") else { return false }
        let sg = Blocks.id("seagrass")
        let floors: Set<BlockID> = [SAND, GRAVEL, DIRT, Blocks.id("clay"), Blocks.id("red_sand")]
        var n = 0
        for _ in 0..<32 {
            let q = f + IVec3(Rand.int(in: -3...3), Rand.int(in: -1...1), Rand.int(in: -3...3))
            if floors.contains(w.block(q.x, q.y, q.z)) && w.block(q.x, q.y + 1, q.z) == WATER && w.block(q.x, q.y + 2, q.z) == WATER {
                w.setBlockAsync(q.x, q.y + 1, q.z, sg); n += 1
            }
        }
        if w.block(f.x, f.y + 1, f.z) == WATER { w.setBlock(f.x, f.y + 1, f.z, sg); n += 1 }
        return n > 0 || w.block(base.x, base.y, base.z) == sg
    }

    // A huge fungus (same shape as the Emberdeep forests grow): stem 4-11 tall, a wart cap with fungal lamps.
    func growHugeFungus(_ p: IVec3, crimson: Bool) {
        let w = world
        let height = Rand.int(in: 4...11)
        for dy in 1...(height + 1) where w.block(p.x, p.y + dy, p.z) != AIR { return }
        let stem = Blocks.id(crimson ? "crimson_stem" : "warped_stem")
        let wart = Blocks.id(crimson ? "nether_wart_block" : "warped_wart_block")
        let lamp = Blocks.id("shroomlight")
        for dy in 0..<height { w.setBlockAsync(p.x, p.y + dy, p.z, stem) }
        let top = p.y + height - 1
        for dy in -2...1 {
            let r = dy == 1 ? 1 : 2
            for dz in -r...r { for dx in -r...r {
                if abs(dx) == 2 && abs(dz) == 2 { continue }
                if dy < 0 && abs(dx) < 2 && abs(dz) < 2 { continue }
                if w.block(p.x + dx, top + dy, p.z + dz) == AIR { w.setBlockAsync(p.x + dx, top + dy, p.z + dz, Rand.int(in: 0..<12) == 0 ? lamp : wart) }
            } }
        }
        w.setBlock(p.x, p.y, p.z, stem)
    }
}
