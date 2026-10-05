import Foundation
import simd

// Advancements: five tabs mirroring the reference tree (story, emberdeep, end, adventure, husbandry) with
// the same criteria and original titles. Item and place criteria are polled once a second; events
// (kills, trades, breeding, brewing, enchanting, raids...) are reported with achieve(_:).
struct Advancement {
    enum Crit {
        case item(String)                 // have this item
        case anyItem([String])
        case itemSuffix(String)           // any item whose name ends with this
        case dim(Dim)
        case event(String)
        case biome(String)
        case allEffects(Int)              // have at least n effects at once
    }
    let id: String
    let tab: Int
    let title: String
    let desc: String
    let crit: Crit
    var challenge = false
}

enum Advancements {
    static let tabs = ["Story", "Emberdeep", "The Hollow", "Adventure", "Husbandry"]
    static let all: [Advancement] = [
        // Story
        Advancement(id: "root", tab: 0, title: "First Steps", desc: "The heart and story of the game", crit: .item("crafting_table")),
        Advancement(id: "mine_stone", tab: 0, title: "Rock Bottom", desc: "Mine stone with your new pickaxe", crit: .item("cobblestone")),
        Advancement(id: "upgrade_tools", tab: 0, title: "Better Tools", desc: "Construct a better pickaxe", crit: .item("stone_pickaxe")),
        Advancement(id: "smelt_iron", tab: 0, title: "Metalworks", desc: "Smelt an iron ingot", crit: .item("iron_ingot")),
        Advancement(id: "obtain_armor", tab: 0, title: "Dressed for Trouble", desc: "Protect yourself with a piece of iron armor",
                    crit: .anyItem(["iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots"])),
        Advancement(id: "lava_bucket", tab: 0, title: "Handle With Care", desc: "Fill a bucket with lava", crit: .item("lava_bucket")),
        Advancement(id: "iron_tools", tab: 0, title: "Iron Grip", desc: "Upgrade your pickaxe", crit: .item("iron_pickaxe")),
        Advancement(id: "deflect_arrow", tab: 0, title: "Not Today", desc: "Block a projectile with a shield", crit: .event("deflect")),
        Advancement(id: "form_obsidian", tab: 0, title: "Cold Glass", desc: "Obtain a block of obsidian", crit: .item("obsidian")),
        Advancement(id: "mine_diamond", tab: 0, title: "Shiny!", desc: "Acquire diamonds", crit: .item("diamond")),
        Advancement(id: "enter_the_nether", tab: 0, title: "Down Below", desc: "Build, light and enter an Ember Gate", crit: .dim(.nether)),
        Advancement(id: "shiny_gear", tab: 0, title: "Glittering Guard", desc: "Diamond armor saves lives",
                    crit: .anyItem(["diamond_helmet", "diamond_chestplate", "diamond_leggings", "diamond_boots"])),
        Advancement(id: "enchant_item", tab: 0, title: "Spellbound", desc: "Enchant an item at an Enchanting Table", crit: .event("enchant")),
        Advancement(id: "cure_zombie_villager", tab: 0, title: "Second Opinion", desc: "Weaken and then cure a Zombie Villager", crit: .event("cure"), challenge: false),
        Advancement(id: "follow_ender_eye", tab: 0, title: "Following the Eye", desc: "Enter a Stronghold", crit: .event("stronghold")),
        Advancement(id: "enter_the_end", tab: 0, title: "Journey's End?", desc: "Enter the Hollow Gate", crit: .dim(.end)),
        // Emberdeep
        Advancement(id: "nether/root", tab: 1, title: "The Other Side", desc: "Bring summer clothes", crit: .dim(.nether)),
        Advancement(id: "nether/return_to_sender", tab: 1, title: "Sent Back", desc: "Destroy a Wailer with a fireball", crit: .event("ghast_fireball"), challenge: true),
        Advancement(id: "nether/find_fortress", tab: 1, title: "Fortified", desc: "Break your way into a Cinder Fortress", crit: .event("fortress")),
        Advancement(id: "nether/obtain_blaze_rod", tab: 1, title: "Fire Walker", desc: "Relieve a Cinderwisp of its rod", crit: .item("blaze_rod")),
        Advancement(id: "nether/brew_potion", tab: 1, title: "Home Chemist", desc: "Brew a potion", crit: .event("brew")),
        Advancement(id: "nether/obtain_ancient_debris", tab: 1, title: "Deep Buried", desc: "Obtain Dusk Relic", crit: .item("ancient_debris")),
        Advancement(id: "nether/netherite_armor", tab: 1, title: "Unbreakable Shell", desc: "Get a full suit of Duskium armor",
                    crit: .event("netherite_suit"), challenge: true),
        Advancement(id: "nether/distract_piglin", tab: 1, title: "Gold Rush", desc: "Distract Boarlings with gold", crit: .event("barter")),
        Advancement(id: "nether/ride_strider", tab: 1, title: "Hot Stroll", desc: "Ride a Magmastrider with a Tealcap Fungus on a Stick", crit: .event("ride_strider")),
        Advancement(id: "nether/summon_wither", tab: 1, title: "Dark Summoning", desc: "Summon the Blight", crit: .event("summon_wither")),
        Advancement(id: "nether/create_beacon", tab: 1, title: "Signal Fire", desc: "Construct and place a Beacon", crit: .event("beacon")),
        Advancement(id: "nether/all_effects", tab: 1, title: "A Heady Mix", desc: "Have every potion effect at the same time", crit: .allEffects(13), challenge: true),
        Advancement(id: "nether/obtain_crying_obsidian", tab: 1, title: "Tearful Stone", desc: "Obtain Weeping Obsidian", crit: .item("crying_obsidian")),
        Advancement(id: "nether/charge_respawn_anchor", tab: 1, title: "Nine Lives", desc: "Charge a Rebirth Anchor to the maximum", crit: .event("anchor_full")),
        // End
        Advancement(id: "end/root", tab: 2, title: "The Hollow", desc: "Or the beginning?", crit: .dim(.end)),
        Advancement(id: "end/kill_dragon", tab: 2, title: "Freedom", desc: "Defeat the Hollow Wyrm", crit: .event("kill_ender_dragon")),
        Advancement(id: "end/dragon_egg", tab: 2, title: "The Next Egg", desc: "Hold the Wyrm Egg", crit: .item("dragon_egg")),
        Advancement(id: "end/enter_end_gateway", tab: 2, title: "Far Islands", desc: "Escape the island", crit: .event("gateway")),
        Advancement(id: "end/respawn_dragon", tab: 2, title: "Once More", desc: "Respawn the Hollow Wyrm", crit: .event("respawn_dragon"), challenge: true),
        Advancement(id: "end/dragon_breath", tab: 2, title: "Bottled Breath", desc: "Collect Wyrm's Breath in a Glass Bottle", crit: .item("dragon_breath")),
        Advancement(id: "end/find_end_city", tab: 2, title: "Distant Towers", desc: "Go on in, what could happen?", crit: .event("end_city")),
        Advancement(id: "end/elytra", tab: 2, title: "Wings", desc: "Find Glider Wings", crit: .item("elytra")),
        Advancement(id: "end/levitate", tab: 2, title: "Lifted", desc: "Levitate up 50 blocks from the attacks of a Shellsentry", crit: .event("levitate50"), challenge: true),
        // Adventure
        Advancement(id: "adventure/root", tab: 3, title: "Out There", desc: "Adventure, exploration and combat", crit: .event("kill_any")),
        Advancement(id: "adventure/kill_a_mob", tab: 3, title: "Hunter", desc: "Kill any hostile monster", crit: .event("kill_hostile")),
        Advancement(id: "adventure/trade", tab: 3, title: "Fair Deal", desc: "Successfully trade with a Villager", crit: .event("trade")),
        Advancement(id: "adventure/sleep_in_bed", tab: 3, title: "Good Night", desc: "Sleep in a bed to change your respawn point", crit: .event("sleep")),
        Advancement(id: "adventure/shoot_arrow", tab: 3, title: "Take Aim", desc: "Shoot something with an arrow", crit: .event("arrow_hit")),
        Advancement(id: "adventure/ol_betsy", tab: 3, title: "Crossed", desc: "Shoot a Crossbow", crit: .event("crossbow")),
        Advancement(id: "adventure/voluntary_exile", tab: 3, title: "Exiled", desc: "Kill a raid captain", crit: .event("kill_captain")),
        Advancement(id: "adventure/hero_of_the_village", tab: 3, title: "Village Keeper", desc: "Successfully defend a village from a raid", crit: .event("raid_win"), challenge: true),
        Advancement(id: "adventure/totem_of_undying", tab: 3, title: "Second Chance", desc: "Use a Totem of Rebirth to cheat death", crit: .event("totem")),
        Advancement(id: "adventure/summon_iron_golem", tab: 3, title: "Hired Muscle", desc: "Summon an Iron Golem", crit: .event("iron_golem")),
        Advancement(id: "adventure/throw_trident", tab: 3, title: "A Throwaway Joke", desc: "Throw a Trident at something", crit: .event("trident_hit")),
        Advancement(id: "adventure/spyglass_at_parrot", tab: 3, title: "Look Closer", desc: "Look at something through a Spyglass", crit: .event("spyglass")),
        Advancement(id: "adventure/walk_on_powder_snow", tab: 3, title: "Light Step", desc: "Walk on Powder Snow with leather boots", crit: .event("powder_walk")),
        Advancement(id: "adventure/salvage_sherd", tab: 3, title: "Careful Dig", desc: "Brush a suspicious block to obtain a Pottery Sherd", crit: .itemSuffix("_pottery_sherd")),
        Advancement(id: "adventure/trim_armor", tab: 3, title: "New Look", desc: "Apply a trim at a Smithing Table", crit: .event("trim")),
        Advancement(id: "adventure/kill_all_mobs", tab: 3, title: "Pest Control", desc: "Kill 30 kinds of hostile monsters", crit: .event("kill30"), challenge: true),
        Advancement(id: "adventure/adventuring_time", tab: 3, title: "Wanderer", desc: "Discover 40 biomes", crit: .event("biomes40"), challenge: true),
        Advancement(id: "adventure/sniper_duel", tab: 3, title: "Long Shot", desc: "Kill a Skeleton from at least 50 blocks away", crit: .event("sniper")),
        Advancement(id: "adventure/play_jukebox_in_meadows", tab: 3, title: "Hillside Tunes", desc: "Play a music disc in a Meadow", crit: .event("meadow_music")),
        Advancement(id: "adventure/proving_run", tab: 3, title: "Proving Run", desc: "Step foot in a Proving Hall", crit: .event("trial_chambers")),
        // Steelhold fortresses (original content).
        Advancement(id: "adventure/steelhold", tab: 3, title: "Behind White Walls", desc: "Set foot inside a Capital citadel", crit: .event("steelhold")),
        Advancement(id: "adventure/steelhold_gun", tab: 3, title: "Locked and Loaded", desc: "Get your hands on a Steelhold gun",
                    crit: .anyItem(["gun_rifle", "gun_smg", "gun_shotgun", "gun_sniper", "gun_launcher", "gun_arc", "gun_sidearm"])),
        Advancement(id: "adventure/steelhold_deck_gun", tab: 3, title: "Silence the Guns", desc: "Destroy a Capital 42 cm turret", crit: .event("deck_gun")),
        Advancement(id: "adventure/steelhold_ironclad", tab: 3, title: "The Bigger They Are", desc: "Defeat a Capital Bulwark",
                    crit: .event("ironclad"), challenge: true),
        // Ships (Blocksmith's own: moving block structures).
        Advancement(id: "adventure/set_sail", tab: 3, title: "Anchors Aweigh", desc: "Steer a ship from its helm", crit: .event("pilot_ship")),
        Advancement(id: "adventure/prize_crew", tab: 3, title: "Prize Crew", desc: "Take the helm of a Skyward Frigate or an Ironstride Siege Carriage",
                    crit: .event("capture_vessel"), challenge: true),
        Advancement(id: "adventure/brought_low", tab: 3, title: "Brought Low", desc: "Wreck a Skyward Frigate or an Ironstride Siege Carriage",
                    crit: .event("wreck_vessel"), challenge: true),
        // Husbandry
        Advancement(id: "husbandry/root", tab: 4, title: "Homestead", desc: "The world is full of friends and food", crit: .event("eat")),
        Advancement(id: "husbandry/plant_seed", tab: 4, title: "Sown", desc: "Plant a seed and watch it grow", crit: .event("plant")),
        Advancement(id: "husbandry/breed_an_animal", tab: 4, title: "Two By Two... Almost", desc: "Breed two animals together", crit: .event("breed")),
        Advancement(id: "husbandry/tame_an_animal", tab: 4, title: "Loyal Company", desc: "Tame an animal", crit: .event("tame")),
        Advancement(id: "husbandry/fishy_business", tab: 4, title: "Caught One", desc: "Catch a fish", crit: .event("fish")),
        Advancement(id: "husbandry/tactical_fishing", tab: 4, title: "Scoop", desc: "Catch a fish... without a fishing rod!",
                    crit: .anyItem(["cod_bucket", "salmon_bucket", "tropical_fish_bucket", "pufferfish_bucket"])),
        Advancement(id: "husbandry/balanced_diet", tab: 4, title: "Omnivore", desc: "Eat everything that is edible", crit: .event("ate_all"), challenge: true),
        Advancement(id: "husbandry/obtain_netherite_hoe", tab: 4, title: "Overdone", desc: "Use a Duskium Ingot to upgrade a hoe", crit: .item("netherite_hoe"), challenge: true),
        Advancement(id: "husbandry/safely_harvest_honey", tab: 4, title: "Sweet Harvest", desc: "Use a Campfire to collect Honey safely", crit: .item("honey_bottle")),
        Advancement(id: "husbandry/wax_on", tab: 4, title: "Sealed", desc: "Apply Honeycomb to a Copper block", crit: .event("wax")),
        Advancement(id: "husbandry/axolotl_in_a_bucket", tab: 4, title: "Cute Catch", desc: "Catch an Axolotl in a bucket", crit: .item("axolotl_bucket")),
        Advancement(id: "husbandry/ride_a_boat_with_a_goat", tab: 4, title: "Afloat", desc: "Get in a Boat and float", crit: .event("boat")),
        Advancement(id: "husbandry/make_a_sign_glow", tab: 4, title: "Bright Letters", desc: "Make the text of a sign glow", crit: .event("glow_sign")),
        Advancement(id: "husbandry/obtain_sniffer_egg", tab: 4, title: "Old Smells", desc: "Obtain a Snuffler Egg", crit: .item("sniffer_egg")),
        Advancement(id: "husbandry/plant_any_sniffer_seed", tab: 4, title: "Ancient Seeds", desc: "Plant any Snuffler seed", crit: .event("plant_sniffer")),
        Advancement(id: "husbandry/remove_wolf_armor", tab: 4, title: "Shears Out", desc: "Remove Wolf Armor from a Wolf using Shears", crit: .event("wolf_armor")),
        Advancement(id: "husbandry/froglights", tab: 4, title: "Three Lights", desc: "Have all Frog Lanterns in your inventory",
                    crit: .event("froglights")),
    ]
    static let index: [String: Int] = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })
}

extension Game {
    // Report an event; grants every advancement it completes.
    func achieve(_ event: String) {
        for a in Advancements.all where !advancements.contains(a.id) {
            if case .event(let e) = a.crit, e == event { grantAdvancement(a) }
        }
    }

    func grantAdvancement(_ a: Advancement) {
        guard advancements.insert(a.id).inserted else { return }
        advToasts.append((a.title, a.challenge, clock))
        sfx(a.challenge ? .levelUp : .xp, a.challenge ? 1 : 0.6)
    }

    // Once a second: item, dimension and effect criteria, plus derived events.
    func advancementTick() {
        guard clock - lastAdvCheck >= 1 else { return }
        lastAdvCheck = clock
        // What every player holds, wears, rides and stands in counts (split screen: player 2's progress was ignored).
        coop.eachSeat(self) { self.advancementCheck() }
    }

    private func advancementCheck() {
        var have = Set<String>()
        for s in inventory.main.slots + inventory.armor.slots + inventory.offhand.slots where !s.isEmpty { have.insert(Items.key(s.item)) }
        for a in Advancements.all where !advancements.contains(a.id) {
            switch a.crit {
            case .item(let k): if have.contains(k) { grantAdvancement(a) }
            case .anyItem(let ks): if ks.contains(where: { have.contains($0) }) { grantAdvancement(a) }
            case .itemSuffix(let s): if have.contains(where: { $0.hasSuffix(s) }) { grantAdvancement(a) }
            case .dim(let d): if dim.dim == d { grantAdvancement(a) }
            case .allEffects(let n): if Effect.allCases.filter({ effects.has($0) }).count >= n { grantAdvancement(a) }
            default: break
            }
        }
        if ["netherite_helmet", "netherite_chestplate", "netherite_leggings", "netherite_boots"].allSatisfy({ k in inventory.armor.slots.contains { Items.key($0.item) == k } }) {
            achieve("netherite_suit")
        }
        if ["ochre_froglight", "verdant_froglight", "pearlescent_froglight"].allSatisfy({ have.contains($0) }) { achieve("froglights") }
        if riding?.kind == .boat { achieve("boat") }
        if riding?.kind == .strider { achieve("ride_strider") }
        if mobs.mobs.contains(where: { $0.owner == true && simd_length($0.pos - player.pos) < 8 }) { achieve("tame") }
        if scoping { achieve("spyglass") }
        if have.contains(where: { k in Items.has(k) && Potions.potion(of: Items.id(k)) != nil && !k.contains("water") }) { achieve("brew") }
        // Structures the player stands in.
        let px = Int(floor(player.pos.x)), py = Int(floor(player.pos.y)), pz = Int(floor(player.pos.z))
        func inside(_ kind: String) -> Bool {
            guard let s = world.gen.structures?.nearest(kind, x: px, z: pz, maxRegions: 2) else { return false }
            return px >= s.min.x && px <= s.max.x && pz >= s.min.z && pz <= s.max.z && py >= s.min.y - 2 && py <= s.max.y + 2
        }
        let under = Blocks.key(Blocks.groupBase[Int(world.block(px, py - 1, pz))])
        if dim.dim == .nether && under == "nether_bricks" { achieve("fortress") }
        if dim.dim == .end && (under == "purpur_block" || under == "purpur_pillar") { achieve("end_city") }
        if dim.dim == .overworld && Int(clock) % 5 == 0 {
            if !advancements.contains("follow_ender_eye") && inside("stronghold") { achieve("stronghold") }
            if !advancements.contains("adventure/proving_run") && inside("trial_chambers") { achieve("trial_chambers") }
        }
        // Biomes visited.
        let b = world.gen.column(Int(floor(player.pos.x)), Int(floor(player.pos.z))).biome
        if dim.dim == .overworld && visitedBiomes.insert("\(b)").inserted && visitedBiomes.count >= 40 { achieve("biomes40") }
    }

    func advancementKill(_ m: Mob) {
        achieve("kill_any")
        if m.kind.hostile { achieve("kill_hostile") }
        if m.kind.hostile && killedKinds.insert(m.kind.key).inserted && killedKinds.count >= 30 { achieve("kill30") }
        if m.kind == .enderDragon { achieve("kill_ender_dragon") }
        if m.captain { achieve("kill_captain") }
        if m.kind == .skeleton && simd_length(m.pos - player.pos) >= 50 { achieve("sniper") }
        if m.kind == .deckGun { achieve("deck_gun") }
        if m.kind == .soldierIronclad { achieve("ironclad") }
    }

    func saveAdvancements(_ d: inout [String: String]) {
        d["adv"] = advancements.sorted().joined(separator: ",")
        d["biomes"] = visitedBiomes.sorted().joined(separator: ",")
        d["killed"] = killedKinds.sorted().joined(separator: ",")
    }
    func loadAdvancements(_ d: [String: String]) {
        advancements = Set((d["adv"] ?? "").split(separator: ",").map(String.init))
        visitedBiomes = Set((d["biomes"] ?? "").split(separator: ",").map(String.init))
        killedKinds = Set((d["killed"] ?? "").split(separator: ",").map(String.init))
    }
}

// The advancements screen: tab buttons and a scrolling checklist.
final class AdvancementMenu: Menu {
    var tab = 0
    var scroll = 0
    static let rows = 11
    init(game: Game) {
        super.init("Advancements", game: game)
        width = 252; height = 222
        showInventoryLabel = false
        for i in 0..<Advancements.tabs.count {
            let b = MenuSlot(6 + i * 48, 14, nil, 0, .button(i)); b.w = 46; b.h = 14; slots.append(b)
        }
        let up = MenuSlot(234, 34, nil, 0, .button(100)); up.w = 12; up.h = 12; slots.append(up)
        let dn = MenuSlot(234, 202, nil, 0, .button(101)); dn.w = 12; dn.h = 12; slots.append(dn)
    }
    var list: [Advancement] { Advancements.all.filter { $0.tab == tab } }
    override func buttonPressed(_ i: Int) {
        if i == 100 { scroll = max(0, scroll - 3) }
        else if i == 101 { scroll = max(0, min(list.count - AdvancementMenu.rows, scroll + 3)) }
        else { tab = i; scroll = 0 }
    }
}
