import Foundation

// Per-block state that doesn't fit in a block ID: chest and furnace inventories, furnace progress.
final class BlockEntity: Codable {
    enum Kind: String, Codable { case chest, furnace, spawner, hopper, dispenser, brewing, beacon, shulker, campfire, sign, frame, painting, banner, lectern, shelf, pot, crafter
        case display    // wooden shelf: three items shown on its front (Shelf.swift)
    }
    let kind: Kind
    var items: [ItemStack]
    var mob: String = ""      // spawner: mob kind name
    var delay: Float = 10     // spawner: seconds until the next spawn attempt
    var burn = 0         // furnace: fuel ticks left
    var burnMax = 0
    var cook = 0         // furnace: progress ticks (200 = one item)
    var fuel = 0         // brewing stand: brews left from cinder powder
    var brewTime = 0     // brewing stand: ticks left in the current brew (400 = 20 s)
    var brewIngredient: ItemID = 0
    var level = 0        // beacon: pyramid layers (0 = off)
    var secondary = ""   // beacon: secondary power (primary is kept in `mob`)
    var cooks = [0, 0, 0, 0]  // campfire: ticks left per slot
    var xp: Float = 0         // furnace: experience stored from smelting, paid out when the output is taken
    var bottleOut = false     // brewing stand: a used dragon's breath left a glass bottle to drop (not saved)
    var trial = false    // proving spawner (waves, then a reward and a 30-minute cooldown)
    var spawned = 0      // proving spawner: mobs spawned this round
    var cooldown: Float = 0
    var used = false     // vault: already opened by the player
    var lines: [String] = ["", "", "", ""]   // sign text
    var patterns: [Int] = []  // banner layers
    lazy var container: ItemContainer = {
        let c = ItemContainer(items.count)
        c.slots = items
        return c
    }()

    // Container slots per kind (a switch: the old ternary chain had no wooden-shelf case, so shelves got none).
    static func slotCount(_ k: Kind) -> Int {
        switch k {
        case .chest, .shulker: return 27
        case .shelf: return 6
        case .furnace, .display: return 3
        case .hopper, .brewing: return 5
        case .campfire: return 4
        case .frame, .lectern, .pot: return 1
        case .dispenser, .crafter: return 9
        default: return 0
        }
    }

    init(_ k: Kind) {
        kind = k
        items = Array(repeating: .empty, count: BlockEntity.slotCount(k))
        // Item frames keep their rotation (45 degree steps) in `delay`: they start upright (the spawner default of 10
        // turned every framed item a quarter turn).
        if k == .frame { delay = 0 }
    }

    enum CodingKeys: String, CodingKey { case kind, items, burn, burnMax, cook, mob, fuel, brewTime, secondary, trial, used, lines, delay, pat, cd, sp, cooks, xp }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        items = try c.decode([ItemStack].self, forKey: .items)
        // Wooden shelves were made with no slots (the count had no .display case: using one indexed past the end);
        // saved ones come back with their three.
        if kind == .display && items.count < 3 { items += Array(repeating: .empty, count: 3 - items.count) }
        // Every kind comes back with at least its own slot count: the container screens use fixed slot numbers (a short
        // array from an older build or a damaged file was read past its end as soon as the screen drew).
        let need = BlockEntity.slotCount(kind)
        if items.count < need { items += Array(repeating: .empty, count: need - items.count) }
        burn = (try? c.decode(Int.self, forKey: .burn)) ?? 0
        burnMax = (try? c.decode(Int.self, forKey: .burnMax)) ?? 0
        cook = (try? c.decode(Int.self, forKey: .cook)) ?? 0
        mob = (try? c.decode(String.self, forKey: .mob)) ?? ""
        fuel = (try? c.decode(Int.self, forKey: .fuel)) ?? 0
        brewTime = (try? c.decode(Int.self, forKey: .brewTime)) ?? 0
        secondary = (try? c.decode(String.self, forKey: .secondary)) ?? ""
        trial = (try? c.decode(Bool.self, forKey: .trial)) ?? false
        used = (try? c.decode(Bool.self, forKey: .used)) ?? false
        if let l = try? c.decode([String].self, forKey: .lines) { lines = l }
        if kind == .frame || kind == .lectern { delay = (try? c.decode(Float.self, forKey: .delay)) ?? 0 }
        if kind == .shelf { level = Int((try? c.decode(Float.self, forKey: .delay)) ?? 0) }
        patterns = (try? c.decode([Int].self, forKey: .pat)) ?? []
        // A proving spawner's cooldown and round, and a campfire's cooking (a reload reset them: a beaten spawner fought
        // and rewarded again at once, raw food cooked instantly).
        cooldown = (try? c.decode(Float.self, forKey: .cd)) ?? 0
        spawned = (try? c.decode(Int.self, forKey: .sp)) ?? 0
        if let k = try? c.decode([Int].self, forKey: .cooks), k.count == 4 { cooks = k }
        xp = (try? c.decode(Float.self, forKey: .xp)) ?? 0
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(container.slots, forKey: .items)
        try c.encode(burn, forKey: .burn)
        try c.encode(burnMax, forKey: .burnMax)
        try c.encode(cook, forKey: .cook)
        if !mob.isEmpty { try c.encode(mob, forKey: .mob) }
        if kind == .brewing { try c.encode(fuel, forKey: .fuel); try c.encode(brewTime, forKey: .brewTime) }
        if !secondary.isEmpty { try c.encode(secondary, forKey: .secondary) }
        if trial { try c.encode(trial, forKey: .trial) }
        if used { try c.encode(used, forKey: .used) }
        if kind == .sign { try c.encode(lines, forKey: .lines) }
        if kind == .frame || kind == .lectern { try c.encode(delay, forKey: .delay) }
        if kind == .shelf { try c.encode(Float(level), forKey: .delay) }
        if !patterns.isEmpty { try c.encode(patterns, forKey: .pat) }
        if cooldown != 0 { try c.encode(cooldown, forKey: .cd) }
        if spawned != 0 { try c.encode(spawned, forKey: .sp) }
        if kind == .campfire && cooks.contains(where: { $0 != 0 }) { try c.encode(cooks, forKey: .cooks) }
        if xp > 0 { try c.encode(xp, forKey: .xp) }
    }

    // One furnace game tick (20 per second). Returns true if the lit state changed.
    func tickFurnace() -> Bool {
        let c = container
        let wasLit = burn > 0
        // Smokers (food) and blast furnaces (ores, metal) run twice as fast and burn fuel twice as fast.
        let fast = mob == "smoker" || mob == "blast_furnace"
        if burn > 0 { burn = max(0, burn - (fast ? 2 : 1)) }
        let input = c[0]
        var canSmelt = false
        var out: ItemID = 0
        if !input.isEmpty, let r = Recipes.smelt(input.item), BlockEntity.allowed(r, input.item, in: mob) {
            out = r
            let o = c[2]
            canSmelt = o.isEmpty || (o.item == r && o.count < o.maxStack)
        }
        if burn == 0 && canSmelt {
            let f = c[1]
            let ticks = f.isEmpty ? 0 : Recipes.fuel(f.item)
            if ticks > 0 {
                burn = ticks
                burnMax = ticks
                var nf = f
                nf.count -= 1
                if Items.key(f.item) == "lava_bucket" { nf = ItemStack(Items.id("bucket"), 1) }
                c[1] = nf
            }
        }
        if burn > 0 && canSmelt {
            cook += fast ? 2 : 1
            if cook >= 200 {
                cook = 0
                var i = c[0]; i.count -= 1; c[0] = i
                var o = c[2]
                if o.isEmpty { o = ItemStack(out, 1) } else { o.count += 1 }
                c[2] = o
                xp += Recipes.smeltXP(out)
            }
        } else if cook > 0 {
            cook = max(0, cook - 2)
        }
        return wasLit != (burn > 0)
    }
}

extension BlockEntity {
    static func allowed(_ out: ItemID, _ input: ItemID, in kind: String) -> Bool {
        if Items.key(input) == "steel_blend" { return kind == "blast_furnace" }
        switch kind {
        case "smoker": return Items.def(out).food != nil
        case "blast_furnace":
            let k = Items.key(out), i = Items.key(input)
            return Items.def(out).food == nil && (k.hasSuffix("_ingot") || k.hasSuffix("_nugget") || k == "netherite_scrap" || i.contains("_ore") || i.hasPrefix("raw_"))
        default: return true
        }
    }
}

struct BlockEntitySave: Codable {
    var entries: [String: BlockEntity]
}

extension World {
    // The block entity at p if it is of this kind, else a fresh one stored there. A stale entity of another kind (left
    // when a container was replaced without being broken: setBlock keeps entities) would open a 27-slot screen on a
    // 3-slot furnace container and crash (smoke-test menu tour).
    func entity(_ p: IVec3, _ kind: BlockEntity.Kind) -> BlockEntity {
        if let e = blockEntities[p], e.kind == kind { return e }
        let e = BlockEntity(kind)
        blockEntities[p] = e
        return e
    }
}
