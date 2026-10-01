import Foundation

// Items: everything that can sit in an inventory slot. Every placeable block has a block item
// (same name); tools, food, armor and materials are registered below. Sprite textures are painted
// from the pixel-art masks in ItemArt.swift, tinted per material.
typealias ItemID = UInt16

struct FoodInfo { var hunger: Int; var saturation: Float }

enum ArmorSlot: Int { case head = 0, chest, legs, feet }

struct Sprite {
    var mask: String
    var base: UInt32                    // material colour (shade 4)
    var extras: [Character: UInt32] = [:]
}

struct ItemDef {
    var name: String
    var display: String
    var maxStack = 64
    var block: BlockID? = nil        // places this block state
    var sprite: Sprite? = nil        // nil for block items (drawn as a block icon)
    var food: FoodInfo? = nil
    var tool: ToolType = .none
    var tier = 0                     // harvest tier: 0 wood/gold, 1 stone, 2 iron, 3 diamond, 4 duskium
    var toolSpeed: Float = 1
    var durability = 0
    var attack: Float = 1            // damage dealt (hearts x2), 1 = fist
    var attackSpeed: Float = 4       // attacks per second at full charge
    var armorSlot: ArmorSlot? = nil
    var armor = 0
    var toughness: Float = 0
    var fuelTicks = 0                // furnace burn time (20 ticks = 1 s)
    var plants: String? = nil        // crop block planted on farmland (seeds, carrot, potato)
    var texKey: String? = nil        // shared sprite texture (potions) instead of item_<name>
    var overlay: String? = nil       // second sprite layer drawn tinted with overlayColor (potion liquid)
    var overlayColor: UInt32 = 0xFFFFFF
    var enchantability = 0           // enchanting table: material enchantability (0 = can't be enchanted)
    var drink = false                // consumed by drinking (potions, milk, honey)
    init(_ name: String, _ display: String) { self.name = name; self.display = display }
}

final class ItemRegistry {
    private(set) var defs: [ItemDef] = []
    private var byName: [String: ItemID] = [:]
    private(set) var forBlock: [ItemID]    // indexed by block group base state; 0 = none

    var count: Int { defs.count }

    @discardableResult
    func add(_ d: ItemDef) -> ItemID {
        let i = ItemID(defs.count)
        // The release build (-Ounchecked) drops preconditions; the warning shows up in CI logs either way.
        if byName[d.name] != nil { print("warning: duplicate item \(d.name)") }
        precondition(byName[d.name] == nil, "duplicate item \(d.name)")
        byName[d.name] = i
        defs.append(d)
        if let k = d.texKey { _ = Tex.id(k) } else if d.sprite != nil { _ = Tex.id("item_" + d.name) }
        if let o = d.overlay { _ = Tex.id(o) }
        return i
    }

    func id(_ name: String) -> ItemID {
        guard let i = byName[name] else { fatalError("unknown item \(name)") }
        return i
    }
    func has(_ name: String) -> Bool { byName[name] != nil }
    func def(_ i: ItemID) -> ItemDef { defs[Int(i)] }
    func name(_ i: ItemID) -> String { Int(i) < defs.count ? defs[Int(i)].display : "?" }
    func key(_ i: ItemID) -> String { Int(i) < defs.count ? defs[Int(i)].name : "?" }
    func texLayer(_ i: ItemID) -> Int? {
        let d = defs[Int(i)]
        if let k = d.texKey { return Int(Tex.id(k)) }
        return d.sprite == nil ? nil : Int(Tex.id("item_" + d.name))
    }
    func overlayLayer(_ i: ItemID) -> (Int, UInt32)? {
        let d = defs[Int(i)]
        guard let o = d.overlay else { return nil }
        return (Int(Tex.id(o)), d.overlayColor)
    }

    // Item that a given block state drops/picks as (its group's block item), or nil.
    func item(forBlock b: BlockID) -> ItemID? {
        let base = Int(Blocks.groupBase[Int(b)])
        let i = forBlock[base]
        return i == 0 ? nil : i
    }

    // Items shown in the creative inventory (blocks first, then everything else).
    var creativeList: [ItemID] { (1..<count).map { ItemID($0) } }

    init() {
        forBlock = [ItemID](repeating: 0, count: Blocks.count)
        var air = ItemDef("air", "Air")
        air.maxStack = 0
        add(air)
        for b in 1..<Blocks.count where Int(Blocks.groupBase[b]) == b && !Blocks.hidden[b] {
            let bd = Blocks.def(BlockID(b))
            var d = ItemDef(bd.name, bd.display)
            d.block = BlockID(b)
            if bd.sound == .wood { d.fuelTicks = 300 }
            if bd.shape == "banner" {
                d.sprite = Sprite(mask: "banner", base: BlockRegistry.colorHex[String(bd.name.dropLast(7))] ?? 0xFFFFFF, extras: [:])
                d.maxStack = 16
            }
            forBlock[b] = add(d)
        }

        func item(_ n: String, _ disp: String, _ mask: String, _ color: UInt32, _ extras: [Character: UInt32] = [:],
                  stack: Int = 64, fuel: Int = 0) {
            var d = ItemDef(n, disp)
            d.sprite = Sprite(mask: mask, base: color, extras: extras)
            d.maxStack = stack
            d.fuelTicks = fuel
            add(d)
        }
        func food(_ n: String, _ disp: String, _ mask: String, _ color: UInt32, _ h: Int, _ s: Float,
                  _ extras: [Character: UInt32] = [:], stack: Int = 64) {
            var d = ItemDef(n, disp)
            d.sprite = Sprite(mask: mask, base: color, extras: extras)
            d.food = FoodInfo(hunger: h, saturation: s)
            d.maxStack = stack
            add(d)
        }

        // Materials
        item("stick", "Stick", "stick", 0x6B4F2C, fuel: 100)
        item("coal", "Coal", "lump", 0x2B2B2B, fuel: 1600)
        item("charcoal", "Charcoal", "lump", 0x3A3026, fuel: 1600)
        item("raw_iron", "Raw Iron", "lump", 0xD8AF93)
        item("raw_gold", "Raw Gold", "lump", 0xF8D23C)
        item("raw_copper", "Raw Copper", "lump", 0xD6784E)
        item("iron_ingot", "Iron Ingot", "ingot", 0xD8D8D8)
        item("gold_ingot", "Gold Ingot", "ingot", 0xFAD64A)
        item("copper_ingot", "Copper Ingot", "ingot", 0xE0845C)
        item("netherite_ingot", "Duskium Ingot", "ingot", 0x4D494D)
        item("netherite_scrap", "Duskium Scrap", "lump", 0x5E4A45)
        item("iron_nugget", "Iron Nugget", "nugget", 0xD8D8D8)
        item("copper_nugget", "Copper Nugget", "nugget", 0xC87A55)
        item("gold_nugget", "Gold Nugget", "nugget", 0xFAD64A)
        item("diamond", "Diamond", "gem", 0x4AEDD9)
        item("emerald", "Emerald", "gem", 0x17DD62)
        item("lapis_lazuli", "Lapis Lazuli", "gem", 0x2A5BC8)
        item("amethyst_shard", "Amethyst Shard", "gem", 0xA87CE0)
        item("quartz", "Ember Quartz", "gem", 0xEDE6DE)
        item("redstone", "Sparkstone Dust", "dust", 0xE01010)
        item("glowstone_dust", "Lumenstone Dust", "dust", 0xF5D878)
        item("gunpowder", "Gunpowder", "dust", 0x6E6E6E)
        item("sugar", "Sugar", "dust", 0xF4F4F4)
        item("bone_meal", "Bone Meal", "dust", 0xE8E6DA)
        item("blaze_powder", "Cinder Powder", "dust", 0xF7A93A)
        item("flint", "Flint", "lump", 0x3C3C3C)
        item("string", "String", "string", 0xEDEDED)
        item("feather", "Feather", "feather", 0xEAEAEA, ["a": 0xB0B0B0])
        item("bone", "Bone", "bone", 0xE8E4D6)
        item("leather", "Leather", "leather", 0xA0592B)
        item("paper", "Paper", "paper", 0xE6E6DC)
        item("book", "Book", "book", 0x7A4A28, ["c": 0xD8B84A])
        item("slime_ball", "Slimeball", "ball", 0x74C45E)
        item("snowball", "Snowball", "ball", 0xF4FAFF, stack: 16)
        item("clay_ball", "Clay Ball", "ball", 0xA4A9B8)
        item("brick", "Brick", "ingot", 0xB5563A)
        item("nether_brick", "Ember Brick", "ingot", 0x5A2A30)
        item("ender_pearl", "Void Pearl", "pearl", 0x2F8C7C, stack: 16)
        item("ender_eye", "Seeker Eye", "eye", 0x2F8C7C, ["c": 0x7ED957, "d": 0x173D1A])
        item("blaze_rod", "Cinder Rod", "rod", 0xF7C23A)
        item("ghast_tear", "Wailer Tear", "tear", 0xDDF2F2)
        item("wheat", "Wheat", "wheat", 0xD8B64A, ["c": 0xB0902A])
        item("wheat_seeds", "Wheat Seeds", "seeds", 0x3EA42B)
        item("nether_wart", "Ember Wart", "berries", 0x8A1A20, ["a": 0x5A0E12])
        item("saddle", "Saddle", "saddle", 0x8A4A22, stack: 1)
        item("name_tag", "Name Tag", "name_tag", 0xE6E0C8)
        item("magma_cream", "Lava Cream", "ball", 0xE8762A)
        item("fire_charge", "Fire Charge", "charge", 0x3A2A22, ["c": 0xF08A2A])
        item("prismarine_shard", "Tidestone Shard", "gem", 0x6AA89A)
        item("prismarine_crystals", "Tidestone Crystals", "dust", 0xC8E0D0)
        item("heart_of_the_sea", "Tide Heart", "ball", 0x2A6AA8)
        item("nautilus_shell", "Nautilus Shell", "shell", 0xE8D8C8)
        item("minecart", "Minecart", "minecart", 0x8A8A90, ["c": 0x4A4A50], stack: 1)
        item("chest_minecart", "Minecart with Chest", "minecart", 0x8A8A90, ["c": 0x9A6A2A], stack: 1)
        item("hopper_minecart", "Minecart with Hopper", "minecart", 0x8A8A90, ["c": 0x3A3A3A], stack: 1)
        item("tnt_minecart", "Minecart with TNT", "minecart", 0x8A8A90, ["c": 0xC83A2A], stack: 1)
        item("furnace_minecart", "Minecart with Furnace", "minecart", 0x8A8A90, ["c": 0x6A6A6A], stack: 1)
        for (i, w) in Boats.woods.enumerated() {
            let raft = w.0 == "bamboo"
            item(Boats.itemKey(i, chest: false), raft ? "Bamboo Raft" : "\(w.1) Boat", "boat", w.2, stack: 1, fuel: 1200)
            item(Boats.itemKey(i, chest: true), raft ? "Bamboo Raft with Chest" : "\(w.1) Boat with Chest", "chest_boat", w.2, ["c": 0x9A6A2A, "d": 0x3A3A3A], stack: 1, fuel: 1200)
        }
        item("shulker_shell", "Sentry Shell", "shell", 0x9A6A9A)
        item("dragon_breath", "Wyrm's Breath", "bottle", 0xE8D8F0, ["c": 0xC050E0])
        item("firework_rocket", "Firework Rocket", "rocket", 0xC83A3A)
        item("firework_star", "Firework Star", "firework_star", 0x6A6A6A, ["c": 0x9A9AA0])
        item("bundle", "Bundle", "bundle", 0xB0703A, stack: 1)
        for (c, d) in BlockRegistry.colors { item("\(c)_bundle", "\(d) Bundle", "bundle", BlockRegistry.colorHex[c] ?? 0xB0703A, stack: 1) }
        item("writable_book", "Book and Quill", "book", 0x6A4A2A, ["c": 0xE8E8E8], stack: 1)
        item("written_book", "Written Book", "book", 0x7A5A2A, ["c": 0xD8B84A], stack: 16)
        item("popped_chorus_fruit", "Popped Spiral Fruit", "berries", 0xB08AC0, ["a": 0x6A4A7A])
        item("melon_seeds", "Melon Seeds", "seeds", 0x4A3A2A)
        item("pumpkin_seeds", "Pumpkin Seeds", "seeds", 0xD8C88A)
        item("beetroot_seeds", "Beetroot Seeds", "seeds", 0x8A5A3A)
        item("egg", "Egg", "egg", 0xE9DCBC, stack: 16)
        item("brown_egg", "Brown Egg", "egg", 0xB07A4A, stack: 16)          // warm-climate chickens (FarmVariants.swift)
        item("blue_egg", "Blue Egg", "egg", 0x8FB8D8, stack: 16)            // cold-climate chickens
        item("arrow", "Arrow", "arrow", 0x9A9A9A, ["f": 0xEDEDED, "a": 0x6B4F2C])
        item("bowl", "Bowl", "bowl", 0x8A6435, fuel: 100)
        item("flint_and_steel", "Flint and Steel", "flint_steel", 0x7A7A7A, ["c": 0x3A3A3A, "d": 0x5A5A5A], stack: 1)
        item("bucket", "Bucket", "bucket", 0xC8C8C8, ["c": 0x5A5A5A], stack: 16)
        item("water_bucket", "Water Bucket", "bucket", 0xC8C8C8, ["c": 0x3F76E4], stack: 1)
        item("lava_bucket", "Lava Bucket", "bucket", 0xC8C8C8, ["c": 0xE8661A], stack: 1)
        item("milk_bucket", "Milk Bucket", "bucket", 0xC8C8C8, ["c": 0xF4F4F4], stack: 1)
        item("compass", "Compass", "compass", 0x9A9A9A, ["c": 0xD02020, "d": 0x404040])
        item("clock", "Clock", "compass", 0xF2C94A, ["c": 0x3F76E4, "d": 0x404040])
        item("bow", "Bow", "bow", 0x6B4F2C, ["s": 0xDDDDDD], stack: 1)
        item("shears", "Shears", "shears", 0xD8D8D8, ["d": 0x5A3D1F], stack: 1)
        item("shield", "Shield", "shield", 0x9A7A4A, ["a": 0x5A5A5A], stack: 1)
        item("crossbow", "Crossbow", "crossbow", 0x6B4F2C, ["s": 0xDDDDDD], stack: 1)
        item("trident", "Trident", "trident", 0x4AA89A, stack: 1)
        item("fishing_rod", "Fishing Rod", "fishing_rod", 0x6B4F2C, ["s": 0xDDDDDD, "c": 0xD03030], stack: 1)
        item("carrot_on_a_stick", "Carrot on a Stick", "fishing_rod", 0x6B4F2C, ["s": 0xDDDDDD, "c": 0xF08A1A], stack: 1)
        item("glass_bottle", "Glass Bottle", "bottle", 0xD0DCF0, ["c": 0xDCE8F6])
        item("fermented_spider_eye", "Fermented Spider Eye", "eye", 0xB0506A, ["c": 0xE8C0C8, "d": 0x5A2030])
        item("glistering_melon_slice", "Glistering Melon Slice", "melon", 0xF0C040, ["c": 0xFFF0A0, "d": 0xC89A20])
        item("rabbit_foot", "Rabbit's Foot", "foot", 0xC8A078, ["c": 0xE8D8C0])
        item("rabbit_hide", "Rabbit Hide", "leather", 0xC8A078)
        item("phantom_membrane", "Nightwing Membrane", "membrane", 0xC8C0A0)
        item("breeze_rod", "Gust Rod", "rod", 0xBDC9FF)
        item("experience_bottle", "Bottle o' Enchanting", "bottle", 0xD0DCF0, ["c": 0x7ED957])
        item("enchanted_book", "Enchanted Book", "book", 0x8A3AA8, ["c": 0xE8C850], stack: 1)
        item("nether_star", "Blight Star", "star", 0xF0F0FF)
        item("totem_of_undying", "Totem of Rebirth", "totem", 0xE8C040, ["c": 0x2A8A3A])
        item("turtle_scute", "Turtle Scute", "scute", 0x4A9A3A)
        item("ink_sac", "Ink Sac", "sac", 0x1A1A2A)
        item("glow_ink_sac", "Glow Ink Sac", "sac", 0x4AE8C8)
        item("honeycomb", "Honeycomb", "honeycomb", 0xE8A020, ["c": 0xF8C850])
        item("resin_clump", "Resin Clump", "ball", 0xD9701E)
        item("resin_brick", "Resin Brick", "ingot", 0xCC6420)
        item("goat_horn", "Goat Horn", "horn", 0xC8C0A8, stack: 1)
        item("armadillo_scute", "Armadillo Scute", "scute", 0xA06A58)
        item("wolf_armor", "Wolf Armor", "horse_armor", 0xA06A58, stack: 1)
        item("end_crystal", "Hollow Crystal", "crystal", 0xD8A8E8)
        item("ominous_bottle", "Omen Bottle", "bottle", 0x2A5A4A, ["c": 0x0B6138])
        for (n, d, c) in [("cod_bucket", "Bucket of Cod", 0xB8A58A), ("salmon_bucket", "Bucket of Salmon", 0xC0504A),
                          ("tropical_fish_bucket", "Bucket of Tropical Fish", 0xE87A2A), ("pufferfish_bucket", "Bucket of Pufferfish", 0xE8C040),
                          ("axolotl_bucket", "Bucket of Axolotl", 0xF09AB0), ("tadpole_bucket", "Bucket of Tadpole", 0x5A4A30)] as [(String, String, UInt32)] {
            item(n, d, "bucket", 0xC8C8C8, ["c": c], stack: 1)
        }
        item("warped_fungus_on_a_stick", "Tealcap Fungus on a Stick", "fishing_rod", 0x6B4F2C, ["s": 0xDDDDDD, "c": 0x2A9A8A], stack: 1)
        for (c, d) in BlockRegistry.colors {
            item("\(c)_dye", "\(d) Dye", "dust", BlockRegistry.colorHex[c] ?? 0xFFFFFF)
        }
        item("leather_horse_armor", "Leather Horse Armor", "horse_armor", 0xA0592B, stack: 1)
        item("iron_horse_armor", "Iron Horse Armor", "horse_armor", 0xE0E0E0, stack: 1)
        item("golden_horse_armor", "Golden Horse Armor", "horse_armor", 0xF8D84A, stack: 1)
        item("diamond_horse_armor", "Diamond Horse Armor", "horse_armor", 0x4AEDD9, stack: 1)
        item("lead", "Lead", "lead", 0xB08A5A)
        item("spyglass", "Spyglass", "spyglass", 0xC8783A, ["c": 0xE8C040], stack: 1)
        for (_, disp, need) in Banners.patterns { if let n = need { item(n, "Banner Pattern (\(disp))", "paper", 0xE0D8C0, ["a": 0x5A5040], stack: 1) } }
        item("armor_stand", "Armor Stand", "armor_stand", 0x9A7A4A, stack: 16)
        item("cocoa_beans", "Cocoa Beans", "seeds", 0x7A4A2A)
        item("torchflower_seeds", "Torchflower Seeds", "seeds", 0x5A7A2A)
        item("pitcher_pod", "Pitcher Pod", "seeds", 0x3A7A6A)
        item("brush", "Brush", "brush", 0xC8A878, ["a": 0x6B4F2C], stack: 1)
        item("echo_shard", "Resonant Shard", "crystal", 0x0A4A58)
        item("recovery_compass", "Recovery Compass", "compass", 0x3A6A6A, ["c": 0x3AD8D8, "d": 0x1A2A2A], stack: 1)
        item("disc_fragment_5", "Disc Fragment", "nugget", 0x2A2A2A)
        item("mace", "Mace", "mace", 0x6A6A70, stack: 1)
        item("wind_charge", "Wind Charge", "ball", 0xBDC9FF)
        item("powder_snow_bucket", "Powder Snow Bucket", "bucket", 0xB0B0B8, ["c": 0xF8F8FF], stack: 1)
        item("trial_key", "Proving Key", "key", 0xE8A040)
        item("map", "Empty Map", "map", 0xC8B888, ["c": 0xE8E0C0, "d": 0xE8E0C0, "r": 0xE8E0C0])
        item("filled_map", "Map", "map", 0xC8B888, ["c": 0xE8D8A8, "d": 0x6A9A5A], stack: 1)
        for s in ["angler", "archer", "arms_up", "blade", "brewer", "burn", "danger", "explorer", "flow", "friend", "guster", "heart",
                  "heartbreak", "howl", "miner", "mourner", "plenty", "prize", "scrape", "sheaf", "shelter", "skull", "snort"] {
            item("\(s)_pottery_sherd", "\(s.replacingOccurrences(of: "_", with: " ").capitalized) Pottery Sherd", "sherd", 0xA8583A, ["c": 0x6A3A2A])
        }
        for d in MusicDiscs.all {
            item("music_disc_\(d.0)", "Music Disc", "disc", 0x1A1A1A, ["c": d.1], stack: 1)
        }
        item("ominous_trial_key", "Omen Proving Key", "key", 0x3A8A7A)
        item("netherite_upgrade_smithing_template", "Duskium Upgrade", "template", 0x3A2A2A, ["c": 0x8A5A4A])
        for t in Smithing.trims {
            item("\(t)_armor_trim_smithing_template", "\(t == "vex" ? "Hexling" : t.capitalized) Armor Trim", "template", 0x2A3A4A, ["c": 0x6A8AAA])
        }

        // Food (hunger, saturation as in the reference game)
        food("apple", "Apple", "apple_shape", 0xD11F1A, 4, 2.4, ["a": 0x5A3D1F])
        food("golden_apple", "Golden Apple", "apple_shape", 0xF2D23A, 4, 9.6, ["a": 0x5A3D1F])
        food("bread", "Bread", "bread", 0xC08A3E, 5, 6)
        food("beef", "Raw Beef", "steak", 0xD43B3B, 3, 1.8, ["c": 0xF0E0D0])
        food("cooked_beef", "Steak", "steak", 0x7A4A2A, 8, 12.8, ["c": 0xF0E0D0])
        food("porkchop", "Raw Porkchop", "chop", 0xF08C8C, 3, 1.8, ["c": 0xF8D8D0])
        food("cooked_porkchop", "Cooked Porkchop", "chop", 0xC9864A, 8, 12.8, ["c": 0xF0D0A0])
        food("chicken", "Raw Chicken", "drumstick", 0xF2C6B0, 2, 1.2, ["c": 0xF0E8E0])
        food("cooked_chicken", "Cooked Chicken", "drumstick", 0xC88A48, 6, 7.2, ["c": 0xF0E8E0])
        food("mutton", "Raw Mutton", "chop", 0xD24848, 2, 1.2, ["c": 0xF0E0D0])
        food("cooked_mutton", "Cooked Mutton", "chop", 0x8A4E2E, 6, 9.6, ["c": 0xE8C8A0])
        food("rabbit", "Raw Rabbit", "drumstick", 0xE8B0A0, 3, 1.8, ["c": 0xF0E8E0])
        food("cooked_rabbit", "Cooked Rabbit", "drumstick", 0xB57A48, 5, 6, ["c": 0xF0E8E0])
        food("cod", "Raw Cod", "fish", 0xB8A58A, 2, 0.4, ["c": 0x303030])
        food("cooked_cod", "Cooked Cod", "fish", 0xD8C8A8, 5, 6, ["c": 0x303030])
        food("salmon", "Raw Salmon", "fish", 0xC0504A, 2, 0.4, ["c": 0x303030])
        food("cooked_salmon", "Cooked Salmon", "fish", 0xD8804A, 6, 9.6, ["c": 0x303030])
        food("rotten_flesh", "Rotten Flesh", "rotten", 0x9A6A4A, 4, 0.8, ["c": 0x6A8A3A, "d": 0x4A2A1A])
        food("potato", "Potato", "potato", 0xC8A050, 1, 0.6)
        food("baked_potato", "Baked Potato", "potato", 0xD8A040, 5, 6)
        food("carrot", "Carrot", "carrot", 0xF08A1A, 3, 3.6)
        food("golden_carrot", "Golden Carrot", "carrot", 0xF2D23A, 6, 14.4)
        food("beetroot", "Beetroot", "potato", 0xA02838, 1, 1.2)
        food("cookie", "Cookie", "cookie", 0xC88A48, 2, 0.4, ["a": 0x4A2A1A])
        food("melon_slice", "Melon Slice", "melon", 0xE04A3A, 2, 1.2, ["c": 0x2A1A10, "d": 0x4A9A2A])
        food("sweet_berries", "Sweet Berries", "berries", 0xC0203A, 2, 0.4, ["a": 0x3A6A2A])
        food("pumpkin_pie", "Pumpkin Pie", "pie", 0xE8A050, 8, 4.8, ["c": 0xA85A1A])
        food("mushroom_stew", "Mushroom Stew", "stew", 0x8A6435, 6, 7.2, ["c": 0xB08858, "d": 0xD8C0A0], stack: 1)
        food("beetroot_soup", "Beetroot Soup", "stew", 0x8A6435, 6, 7.2, ["c": 0xA02838, "d": 0xC04050], stack: 1)
        food("dried_kelp", "Dried Kelp", "kelp", 0x3A4A2A, 1, 0.6)
        food("glow_berries", "Glow Berries", "berries", 0xF2A83A, 2, 0.4, ["a": 0x3A6A2A])
        food("chorus_fruit", "Spiral Fruit", "berries", 0x8A5A9A, 4, 2.4, ["a": 0x4A2A5A])
        food("spider_eye", "Spider Eye", "eye", 0x8A2A3A, 2, 3.2, ["c": 0xC04050, "d": 0x200810])
        food("enchanted_golden_apple", "Enchanted Golden Apple", "apple_shape", 0xF8E050, 4, 9.6, ["a": 0x5A3D1F])
        food("pufferfish", "Pufferfish", "pufferfish", 0xE8C040, 1, 0.2, ["c": 0x303030])
        food("tropical_fish", "Tropical Fish", "fish", 0xE87A2A, 1, 0.2, ["c": 0xF8F8F8])
        food("poisonous_potato", "Poisonous Potato", "potato", 0xA8B050, 2, 1.2)
        food("honey_bottle", "Honey Bottle", "bottle", 0xD0DCF0, 6, 1.2, ["c": 0xF0A020], stack: 16)
        food("rabbit_stew", "Rabbit Stew", "stew", 0x8A6435, 10, 12, ["c": 0xB07040, "d": 0xD8A060], stack: 1)
        for f in SuspiciousStew.flowers {
            var d = ItemDef("suspicious_stew_" + f.0, "Suspicious Stew")
            d.sprite = Sprite(mask: "stew", base: 0x8A6435, extras: ["c": 0xB08858, "d": 0xD8A868])
            d.food = FoodInfo(hunger: 6, saturation: 7.2)
            d.maxStack = 1
            add(d)
        }

        for (n, crop) in [("wheat_seeds", "wheat"), ("beetroot_seeds", "beetroots"), ("carrot", "carrots"), ("potato", "potatoes"), ("nether_wart", "nether_wart"),
                          ("torchflower_seeds", "torchflower_crop"), ("pitcher_pod", "pitcher_crop")] where has(n) {
            defs[Int(id(n))].plants = crop
        }

        // Tools: (name, harvest tier, durability, mining speed, colour)
        let tiers: [(String, String, Int, Int, Float, UInt32)] = [
            ("wooden", "Wooden", 0, 59, 2, 0x9A7A4A), ("stone", "Stone", 1, 131, 4, 0x8A8A8A),
            ("iron", "Iron", 2, 250, 6, 0xE0E0E0), ("golden", "Golden", 0, 32, 12, 0xF8D84A),
            ("diamond", "Diamond", 3, 1561, 8, 0x4AEDD9), ("netherite", "Duskium", 4, 2031, 9, 0x5A555A),
            ("copper", "Copper", 1, 190, 5, 0xC87A55),                     // between stone and iron; mines like stone
        ]
        let swordDmg: [Float] = [4, 5, 6, 4, 7, 8, 5], axeDmg: [Float] = [7, 9, 9, 7, 9, 10, 9]
        let axeSpd: [Float] = [0.8, 0.8, 0.9, 1.0, 1.0, 1.0, 0.8]
        for (i, t) in tiers.enumerated() {
            let kinds: [(String, String, ToolType, Float, Float)] = [
                ("sword", "Sword", .sword, swordDmg[i], 1.6),
                ("shovel", "Shovel", .shovel, swordDmg[i] - 1.5, 1),
                ("pickaxe", "Pickaxe", .pickaxe, swordDmg[i] - 2, 1.2),
                ("axe", "Axe", .axe, axeDmg[i], axeSpd[i]),
                ("hoe", "Hoe", .hoe, 1, Float(i == 6 ? 2 : (i == 0 || i == 3 ? 1 : i + 1))),
            ]
            for k in kinds {
                var d = ItemDef("\(t.0)_\(k.0)", "\(t.1) \(k.1)")
                d.sprite = Sprite(mask: k.0, base: t.5, extras: [:])
                d.maxStack = 1
                d.tool = k.2
                d.tier = t.2
                d.durability = t.3
                d.toolSpeed = t.4
                d.attack = k.3
                d.attackSpeed = k.4
                if t.0 == "wooden" { d.fuelTicks = 200 }
                add(d)
            }
            // Spear (Spear.swift): a longer jab than the sword, slower, and a charge attack while moving fast.
            var sp = ItemDef("\(t.0)_spear", "\(t.1) Spear")
            sp.sprite = Sprite(mask: "spear", base: t.5, extras: [:])
            sp.maxStack = 1
            sp.tier = t.2
            sp.durability = t.3
            sp.attack = Spear.jabDamage[i]
            sp.attackSpeed = Spear.jabSpeed[i]
            if t.0 == "wooden" { sp.fuelTicks = 200 }
            add(sp)
        }

        // Armor: (name, points per slot head/chest/legs/feet, durability multiplier, toughness, colour)
        let armors: [(String, String, [Int], Int, Float, UInt32)] = [
            ("leather", "Leather", [1, 3, 2, 1], 5, 0, 0xA0592B), ("chainmail", "Chainmail", [2, 5, 4, 1], 15, 0, 0x9A9A9A),
            ("iron", "Iron", [2, 6, 5, 2], 15, 0, 0xE0E0E0), ("golden", "Golden", [2, 5, 3, 1], 7, 0, 0xF8D84A),
            ("diamond", "Diamond", [3, 8, 6, 3], 33, 2, 0x4AEDD9), ("netherite", "Duskium", [3, 8, 6, 3], 37, 3, 0x5A555A),
            ("copper", "Copper", [2, 4, 3, 1], 11, 0, 0xC87A55),
        ]
        let pieces: [(String, String, ArmorSlot, Int)] = [("helmet", "Helmet", .head, 11), ("chestplate", "Chestplate", .chest, 16),
                                                           ("leggings", "Leggings", .legs, 15), ("boots", "Boots", .feet, 13)]
        for a in armors {
            for (pi, p) in pieces.enumerated() {
                let n = a.0 == "leather" && p.0 == "helmet" ? "leather_helmet" : "\(a.0)_\(p.0)"
                let disp = a.0 == "leather" ? "Leather \(p.0 == "chestplate" ? "Tunic" : (p.0 == "leggings" ? "Pants" : (p.0 == "helmet" ? "Cap" : p.1)))" : "\(a.1) \(p.1)"
                var d = ItemDef(n, disp)
                d.sprite = Sprite(mask: p.0, base: a.5, extras: [:])
                d.maxStack = 1
                d.armorSlot = p.2
                d.armor = a.2[pi]
                d.toughness = a.4
                d.durability = p.3 * a.3
                add(d)
            }
        }
        var turtle = ItemDef("turtle_helmet", "Turtle Shell")
        turtle.sprite = Sprite(mask: "helmet", base: 0x4A9A3A, extras: [:])
        turtle.maxStack = 1; turtle.armorSlot = .head; turtle.armor = 2; turtle.durability = 275
        add(turtle)
        var ely = ItemDef("elytra", "Glider Wings")
        ely.sprite = Sprite(mask: "chestplate", base: 0x8E8AA8, extras: [:])
        ely.maxStack = 1; ely.armorSlot = .chest; ely.armor = 0; ely.durability = 432
        add(ely)
        // Durability / combat numbers for the weapon items above.
        for (n, dur, atk, spd) in [("shield", 336, Float(1), Float(4)), ("crossbow", 465, 1, 4), ("trident", 250, 9, 1.1), ("fishing_rod", 64, 1, 4),
                                   ("carrot_on_a_stick", 25, 1, 4), ("bow", 384, 1, 4), ("mace", 500, 6, 0.6), ("brush", 64, 1, 4), ("flint_and_steel", 64, 1, 4), ("shears", 238, 1, 4)] where has(n) {
            defs[Int(id(n))].durability = dur
            defs[Int(id(n))].attack = atk
            defs[Int(id(n))].attackSpeed = spd
        }
        Potions.register(self)
        SpawnEggs.register(self)
        Guns.register(self)
        ExplorerMaps.register(self)
        for n in ["milk_bucket"] { defs[Int(id(n))].drink = true }
        for n in ["honey_bottle", "ominous_bottle"] { defs[Int(id(n))].drink = true }
        Enchant.assignEnchantability(self)
    }

    func setEnchantability(_ n: String, _ v: Int) { if has(n) { defs[Int(id(n))].enchantability = v } }
}

let Items = ItemRegistry()

enum ItemTextures {
    // Material shades from a base colour: 1 outline ... 5 highlight.
    static func shade(_ base: UInt32, _ k: Int) -> V4 {
        let c = TextureGen.hex(base)
        switch k {
        case 1: return V4(c.x * 0.3, c.y * 0.3, c.z * 0.3, 1)
        case 2: return V4(c.x * 0.6, c.y * 0.6, c.z * 0.6, 1)
        case 3: return V4(c.x * 0.8, c.y * 0.8, c.z * 0.8, 1)
        case 4: return c
        default: return V4(min(1, c.x * 0.6 + 0.4), min(1, c.y * 0.6 + 0.4), min(1, c.z * 0.6 + 0.4), 1)
        }
    }

    // Auto-shaded silhouettes (ItemShapes): a dark outline around the shape, a light rim on the
    // top-left edges, a shade rim on the bottom-right, a soft diagonal gradient. `hole` pixels are left
    // clear (but still shape the outline); with `only`, just those pixels are painted (potion liquid).
    static let fixed: [Character: UInt32] = ["a": 0x49361B, "b": 0x896727, "w": 0xF2F2F2, "k": 0x1E1E24, "g": 0xBFD6EE,
                                             "r": 0xC42A2A, "y": 0xF2D23A, "z": 0x8A8A92, "l": 0x4A9A2A, "s": 0xDDDDDD]
    static func autoPainter(_ rowsIn: [String], base: UInt32, extras: [Character: UInt32],
                            hole: Character? = nil, only: Character? = nil) -> TextureGen.Painter {
        let rows = rowsIn.map { Array($0) }
        let b = TextureGen.hex(base)
        func ch(_ x: Int, _ y: Int) -> Character {
            if x < 0 || y < 0 || y >= rows.count || x >= rows[y].count || x > 15 { return "." }
            return rows[y][x]
        }
        func mat(_ c: Character) -> V3 {
            switch c {
            case "#": return V3(b.x, b.y, b.z)
            case "+": return V3(b.x, b.y, b.z) + (V3(1, 1, 1) - V3(b.x, b.y, b.z)) * 0.3
            case "=": return V3(b.x, b.y, b.z) * 0.72
            case "-": return V3(b.x, b.y, b.z) * 0.5
            default:
                if let h = extras[c] ?? fixed[c] { let v = TextureGen.hex(h); return V3(v.x, v.y, v.z) }
                return V3(b.x, b.y, b.z) * 0.72
            }
        }
        func filled(_ x: Int, _ y: Int) -> Bool { ch(x, y) != "." }
        func solid(_ x: Int, _ y: Int) -> Bool { let c = ch(x, y); return c != "." && c != "s" }
        return { x, y in
            let c = ch(x, y)
            if let o = only, c != o { return TextureGen.clear }
            if c == "." {
                var acc = V3(0, 0, 0), n: Float = 0
                for (nx, ny) in [(x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)] where solid(nx, ny) {
                    acc += mat(ch(nx, ny)); n += 1
                }
                if n == 0 { return TextureGen.clear }
                let m = acc / n
                return V4(m.x * 0.26, m.y * 0.26, m.z * 0.3, 1)
            }
            if let h = hole, c == h { return TextureGen.clear }
            let m = mat(c)
            if c == "s" { return V4(m.x, m.y, m.z, 1) }
            let up = filled(x, y - 1), left = filled(x - 1, y), right = filled(x + 1, y), down = filled(x, y + 1)
            var col: V3
            if !up || !left { col = m + (V3(1, 1, 1) - m) * 0.38 }
            else if !down || !right { col = m * 0.7 }
            else if !filled(x - 1, y - 1) { col = m + (V3(1, 1, 1) - m) * 0.15 }
            else if !filled(x + 1, y + 1) { col = m * 0.85 }
            else { col = m }
            let k = 1 + (7.5 - Float(x + y) / 2) * 0.012
            return V4(min(1, col.x * k), min(1, col.y * k), min(1, col.z * k), 1)
        }
    }

    static func painter(_ s: Sprite) -> TextureGen.Painter {
        if let shape = ItemShapes.s[s.mask] { return autoPainter(shape, base: s.base, extras: s.extras) }
        let rows = (ItemArt.masks[s.mask] ?? []).map { Array($0) }
        return { x, y in
            guard y < rows.count, x < rows[y].count else { return TextureGen.clear }
            let ch = rows[y][x]
            switch ch {
            case ".": return TextureGen.clear
            case "1", "2", "3", "4", "5": return shade(s.base, Int(String(ch))!)
            case "a": return TextureGen.hex(s.extras["a"] ?? 0x49361B)
            case "b": return TextureGen.hex(s.extras["b"] ?? 0x896727)
            default: return TextureGen.hex(s.extras[ch] ?? 0xFF00FF)
            }
        }
    }

    static func painters() -> [String: TextureGen.Painter] {
        var p: [String: TextureGen.Painter] = [:]
        for d in Items.defs { if let s = d.sprite { p["item_" + d.name] = painter(s) } }
        return p
    }
}
