import Foundation
import simd

// Mobs: data-driven specs (size, health, speed, behaviour, drops) + cuboid models built on the CPU
// each frame. Numbers follow the reference game on Normal difficulty.

struct MobVert { var pos: V4; var color: V4; var local: V4 } // pos.w = pattern id, color.a = shade

enum Behavior { case passive, melee, ranged, creeper, spider, enderman, slime, neutral, piglin, ghast, blaze, dragon, crystal, shulker, villager, golem, witch, vehicle, wither, evoker, vex, ravager, snowGolem, animal, monster }

enum MobKind: Int, CaseIterable {
    case cow, sheep, chicken, pig, zombie, skeleton, creeper, spider, enderman, slime
    case zombifiedPiglin, piglin, ghast, blaze, magmaCube, witherSkeleton, hoglin, piglinBrute, strider
    case enderDragon, endCrystal, silverfish, shulker
    case villager, ironGolem
    case husk, stray, drowned, caveSpider, witch, pillager, vindicator
    case minecart
    case wither, snowGolem, evoker, vex, ravager, zombieVillager
    // Animals and the rest of the reference roster (Animals.swift).
    case rabbit, fox, wolf, cat, ocelot, horse, donkey, mule, llama, traderLlama, camel, goat, panda, polarBear, turtle, frog, tadpole
    case armadillo, sniffer, mooshroom, bee, parrot, bat, allay, axolotl, squid, glowSquid, dolphin, cod, salmon, tropicalFish, pufferfish
    case wanderingTrader, skeletonHorse, phantom, guardian, elderGuardian, endermite, warden, breeze, bogged, zoglin
    case boat, armorStand
    case creaking
    case zombieHorse, illusioner
    case happyGhast
    case parched, camelHusk, nautilus, zombieNautilus
    case soldierRecruit, soldierTrooper, soldierMarksman, soldierIronclad, deckGun
    case copperGolem
    case soldierOfficer, soldierCrew       // the Capital's officers and pilots / vehicle crews (SoldierRig.swift)
    case ashTank, ashHalftrack, ashArtillery, ashTruck, ashMarshal     // the Ashguard in the Ash Vault (AshUnits.swift)

    struct Spec {
        var name: String
        var halfW: Float
        var height: Float
        var health: Int
        var speed: Float          // walk speed, blocks/s (10x the reference movement attribute: zombie 0.23 -> 2.3)
        var behavior: Behavior
        var attack: Int = 0       // melee damage (half-hearts)
        var burnsInSun = false
        var drops: [(String, Int, Int)] = []
        var xp = 0
        var call: Snd
        var fireImmune = false
        var flying = false
        var aquatic = false       // swims; suffocates on land
    }

    var spec: Spec {
        switch self {
        case .cow: return Spec(name: "Cow", halfW: 0.45, height: 1.4, health: 10, speed: 1.0, behavior: .passive,
                               drops: [("beef", 1, 3), ("leather", 1, 3)], xp: 2, call: .mobCow)
        case .sheep: return Spec(name: "Sheep", halfW: 0.45, height: 1.3, health: 8, speed: 1.0, behavior: .passive,
                                 drops: [("mutton", 1, 2)], xp: 2, call: .mobSheep)
        case .chicken: return Spec(name: "Chicken", halfW: 0.2, height: 0.7, health: 4, speed: 1.0, behavior: .passive,
                                   drops: [("chicken", 1, 1), ("feather", 0, 2)], xp: 2, call: .mobChicken)
        case .pig: return Spec(name: "Pig", halfW: 0.45, height: 0.9, health: 10, speed: 1.0, behavior: .passive,
                               drops: [("porkchop", 1, 3)], xp: 2, call: .mobPig)
        case .zombie: return Spec(name: "Zombie", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .melee, attack: 3,
                                  burnsInSun: true, drops: [("rotten_flesh", 0, 2)], xp: 5, call: .mobZombie)
        case .skeleton: return Spec(name: "Skeleton", halfW: 0.3, height: 1.99, health: 20, speed: 2.5, behavior: .ranged,
                                    burnsInSun: true, drops: [("bone", 0, 2), ("arrow", 0, 2)], xp: 5, call: .mobSkeleton)
        case .creeper: return Spec(name: "Hisser", halfW: 0.3, height: 1.7, health: 20, speed: 2.5, behavior: .creeper,
                                   drops: [("gunpowder", 0, 2)], xp: 5, call: .creeperHiss)
        case .spider: return Spec(name: "Spider", halfW: 0.7, height: 0.9, health: 16, speed: 3.0, behavior: .spider, attack: 2,
                                  drops: [("string", 0, 2)], xp: 5, call: .mobSpider)
        case .enderman: return Spec(name: "Voidwalker", halfW: 0.3, height: 2.9, health: 40, speed: 3.0, behavior: .enderman, attack: 7,
                                    drops: [("ender_pearl", 0, 1)], xp: 5, call: .mobVoidwalker)
        case .slime: return Spec(name: "Slime", halfW: 0.26, height: 0.52, health: 1, speed: 2.0, behavior: .slime, attack: 0,
                                 drops: [("slime_ball", 0, 2)], xp: 1, call: .mobSlime)
        case .zombifiedPiglin: return Spec(name: "Undead Boarling", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .neutral, attack: 8,
                                           drops: [("rotten_flesh", 0, 1), ("gold_nugget", 0, 1)], xp: 5, call: .mobUndeadBoarling, fireImmune: true)
        case .piglin: return Spec(name: "Boarling", halfW: 0.3, height: 1.95, health: 16, speed: 3.5, behavior: .piglin, attack: 8,
                                  drops: [], xp: 5, call: .mobBoarling)
        case .ghast: return Spec(name: "Wailer", halfW: 2, height: 4, health: 10, speed: 2.0, behavior: .ghast,
                                 drops: [("ghast_tear", 0, 1), ("gunpowder", 0, 2)], xp: 5, call: .mobWailer, fireImmune: true, flying: true)
        case .blaze: return Spec(name: "Cinderwisp", halfW: 0.3, height: 1.8, health: 20, speed: 2.3, behavior: .blaze, attack: 6,
                                 drops: [], xp: 10, call: .mobCinderwisp, fireImmune: true, flying: true)
        case .magmaCube: return Spec(name: "Lava Blob", halfW: 0.26, height: 0.52, health: 1, speed: 2.4, behavior: .slime, attack: 0,
                                     drops: [], xp: 1, call: .mobSlime, fireImmune: true)
        case .hoglin: return Spec(name: "Tusker", halfW: 0.7, height: 1.4, health: 40, speed: 3.0, behavior: .melee, attack: 6,
                                  drops: [("porkchop", 2, 4), ("leather", 0, 2)], xp: 5, call: .mobPig)
        case .piglinBrute: return Spec(name: "Boarling Brute", halfW: 0.3, height: 1.95, health: 50, speed: 3.5, behavior: .melee, attack: 13,
                                       drops: [], xp: 20, call: .mobBoarling)
        case .strider: return Spec(name: "Magmastrider", halfW: 0.45, height: 1.7, health: 20, speed: 1.0, behavior: .passive,
                                   drops: [("string", 2, 5)], xp: 2, call: .mobPig, fireImmune: true)
        case .enderDragon: return Spec(name: "Hollow Wyrm", halfW: 4, height: 4, health: 200, speed: 14, behavior: .dragon,
                                       drops: [], xp: 0, call: .mobWailer, fireImmune: true, flying: true)
        case .endCrystal: return Spec(name: "Hollow Crystal", halfW: 1, height: 2, health: 1, speed: 0, behavior: .crystal,
                                      drops: [], xp: 0, call: .click, fireImmune: true, flying: true)
        case .shulker: return Spec(name: "Shellsentry", halfW: 0.5, height: 1, health: 30, speed: 0, behavior: .shulker,
                                   drops: [("shulker_shell", 0, 1)], xp: 5, call: .click, flying: true)
        case .villager: return Spec(name: "Townsperson", halfW: 0.3, height: 1.95, health: 20, speed: 1.6, behavior: .villager,
                                    drops: [], xp: 0, call: .mobVillager)
        case .ironGolem: return Spec(name: "Iron Golem", halfW: 0.7, height: 2.7, health: 100, speed: 1.6, behavior: .golem, attack: 14,
                                     drops: [("iron_ingot", 3, 5), ("poppy", 0, 2)], xp: 0, call: .mobGolem)
        case .minecart: return Spec(name: "Minecart", halfW: 0.49, height: 0.7, health: 6, speed: 0, behavior: .vehicle,
                                    drops: [("minecart", 1, 1)], xp: 0, call: .click)
        case .boat: return Spec(name: "Boat", halfW: 0.6875, height: 0.5625, health: 4, speed: 0, behavior: .vehicle,
                                drops: [], xp: 0, call: .click)
        case .armorStand: return Spec(name: "Armor Stand", halfW: 0.25, height: 1.975, health: 1, speed: 0, behavior: .vehicle,
                                      drops: [("armor_stand", 1, 1)], xp: 0, call: .click)
        case .husk: return Spec(name: "Dust Zombie", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .melee, attack: 3,
                                drops: [("rotten_flesh", 0, 2)], xp: 5, call: .mobZombie)
        case .stray: return Spec(name: "Frost Skeleton", halfW: 0.3, height: 1.99, health: 20, speed: 2.5, behavior: .ranged,
                                 burnsInSun: true, drops: [("bone", 0, 2), ("arrow", 0, 2)], xp: 5, call: .mobSkeleton)
        case .drowned: return Spec(name: "Sunken", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .melee, attack: 3,
                                   burnsInSun: true, drops: [("rotten_flesh", 0, 2), ("copper_ingot", 0, 1)], xp: 5, call: .mobZombie)
        case .caveSpider: return Spec(name: "Cave Spider", halfW: 0.35, height: 0.5, health: 12, speed: 3.0, behavior: .spider, attack: 2,
                                      drops: [("string", 0, 2)], xp: 5, call: .mobSpider)
        case .witch: return Spec(name: "Witch", halfW: 0.3, height: 1.95, health: 26, speed: 2.5, behavior: .witch,
                                 drops: [("glass_bottle", 0, 2), ("glowstone_dust", 0, 2), ("gunpowder", 0, 2), ("redstone", 0, 2),
                                         ("spider_eye", 0, 2), ("sugar", 0, 2), ("stick", 0, 2)], xp: 5, call: .mobVillager)
        case .pillager: return Spec(name: "Marauder", halfW: 0.3, height: 1.95, health: 24, speed: 3.5, behavior: .ranged,
                                    drops: [("arrow", 0, 2)], xp: 5, call: .mobVillager)
        case .vindicator: return Spec(name: "Brigand", halfW: 0.3, height: 1.95, health: 24, speed: 3.5, behavior: .melee, attack: 13,
                                      drops: [("emerald", 0, 1)], xp: 5, call: .mobVillager)
        case .silverfish: return Spec(name: "Silverfish", halfW: 0.2, height: 0.3, health: 8, speed: 2.5, behavior: .melee, attack: 1,
                                      drops: [], xp: 5, call: .mobSpider)
        case .wither: return Spec(name: "Blight", halfW: 0.45, height: 3.5, health: 300, speed: 6, behavior: .wither,
                                  drops: [("nether_star", 1, 1)], xp: 50, call: .mobBlight, fireImmune: true, flying: true)
        case .snowGolem: return Spec(name: "Snow Golem", halfW: 0.35, height: 1.9, health: 4, speed: 2.2, behavior: .snowGolem,
                                     drops: [("snowball", 0, 15)], xp: 0, call: .step(.snow))
        case .evoker: return Spec(name: "Conjurer", halfW: 0.3, height: 1.95, health: 24, speed: 5.0, behavior: .evoker,
                                  drops: [("totem_of_undying", 1, 1), ("emerald", 0, 1)], xp: 10, call: .mobVillager)
        case .vex: return Spec(name: "Hexling", halfW: 0.2, height: 0.8, health: 14, speed: 6, behavior: .vex, attack: 9,
                               drops: [], xp: 3, call: .mobVex, flying: true)
        case .ravager: return Spec(name: "Siegebeast", halfW: 0.98, height: 2.2, health: 100, speed: 3, behavior: .ravager, attack: 12,
                                   drops: [("saddle", 1, 1)], xp: 20, call: .mobRavager)
        case .zombieVillager: return Spec(name: "Zombie Townsperson", halfW: 0.3, height: 1.95, health: 20, speed: 2.3, behavior: .melee, attack: 3,
                                          burnsInSun: true, drops: [("rotten_flesh", 0, 2)], xp: 5, call: .mobZombie)
        case .rabbit, .fox, .wolf, .cat, .ocelot, .horse, .donkey, .mule, .llama, .traderLlama, .camel, .goat, .panda, .polarBear, .turtle, .frog, .tadpole,
             .armadillo, .sniffer, .mooshroom, .bee, .parrot, .bat, .allay, .axolotl, .squid, .glowSquid, .dolphin, .cod, .salmon, .tropicalFish, .pufferfish,
             .wanderingTrader, .skeletonHorse, .phantom, .guardian, .elderGuardian, .endermite, .warden, .breeze, .bogged, .zoglin, .creaking,
             .zombieHorse, .illusioner, .happyGhast, .parched, .camelHusk, .nautilus, .zombieNautilus, .copperGolem:
            return animalSpec
        case .soldierRecruit, .soldierTrooper, .soldierMarksman, .soldierIronclad, .deckGun, .soldierOfficer, .soldierCrew:
            return militarySpec
        case .ashTank, .ashHalftrack, .ashArtillery, .ashTruck, .ashMarshal:
            return ashSpec
        case .witherSkeleton: return Spec(name: "Blight Skeleton", halfW: 0.35, height: 2.4, health: 20, speed: 2.5, behavior: .melee, attack: 8,
                                          drops: [("coal", 0, 1), ("bone", 0, 2)], xp: 5, call: .mobSkeleton, fireImmune: true)
        }
    }
    var hostile: Bool { spec.behavior != .passive && spec.behavior != .villager && spec.behavior != .golem && spec.behavior != .vehicle && spec.behavior != .snowGolem && spec.behavior != .animal }
    // Save / command keys: fixed forever so saves survive display-name changes.
    var key: String { MobKind.keys[self] ?? "\(self)" }
    static let keys: [MobKind: String] = [
        .cow: "cow",
        .sheep: "sheep",
        .chicken: "chicken",
        .pig: "pig",
        .zombie: "zombie",
        .skeleton: "skeleton",
        .creeper: "creeper",
        .spider: "spider",
        .enderman: "enderman",
        .slime: "slime",
        .zombifiedPiglin: "zombified_piglin",
        .piglin: "piglin",
        .ghast: "ghast",
        .blaze: "blaze",
        .magmaCube: "magma_cube",
        .witherSkeleton: "wither_skeleton",
        .hoglin: "hoglin",
        .piglinBrute: "piglin_brute",
        .strider: "strider",
        .enderDragon: "ender_dragon",
        .endCrystal: "end_crystal",
        .silverfish: "silverfish",
        .shulker: "shulker",
        .villager: "villager",
        .ironGolem: "iron_golem",
        .husk: "husk",
        .stray: "stray",
        .drowned: "drowned",
        .caveSpider: "cave_spider",
        .witch: "witch",
        .pillager: "pillager",
        .vindicator: "vindicator",
        .minecart: "minecart",
        .wither: "wither",
        .snowGolem: "snow_golem",
        .evoker: "evoker",
        .vex: "vex",
        .ravager: "ravager",
        .zombieVillager: "zombie_villager",
        .rabbit: "rabbit",
        .fox: "fox",
        .wolf: "wolf",
        .cat: "cat",
        .ocelot: "ocelot",
        .horse: "horse",
        .donkey: "donkey",
        .mule: "mule",
        .llama: "llama",
        .traderLlama: "trader_llama",
        .camel: "camel",
        .goat: "goat",
        .panda: "panda",
        .polarBear: "polar_bear",
        .turtle: "turtle",
        .frog: "frog",
        .tadpole: "tadpole",
        .armadillo: "armadillo",
        .sniffer: "sniffer",
        .mooshroom: "mooshroom",
        .bee: "bee",
        .parrot: "parrot",
        .bat: "bat",
        .allay: "allay",
        .axolotl: "axolotl",
        .squid: "squid",
        .glowSquid: "glow_squid",
        .dolphin: "dolphin",
        .cod: "cod",
        .salmon: "salmon",
        .tropicalFish: "tropical_fish",
        .pufferfish: "pufferfish",
        .wanderingTrader: "wandering_trader",
        .skeletonHorse: "skeleton_horse",
        .phantom: "phantom",
        .guardian: "guardian",
        .elderGuardian: "elder_guardian",
        .endermite: "endermite",
        .warden: "warden",
        .breeze: "breeze",
        .bogged: "bogged",
        .zoglin: "zoglin",
        .boat: "boat",
        .armorStand: "armor_stand",
        .creaking: "creaking",
        .zombieHorse: "zombie_horse",
        .illusioner: "illusioner",
        .happyGhast: "happy_ghast",
        .parched: "parched",
        .camelHusk: "camel_husk",
        .nautilus: "nautilus",
        .zombieNautilus: "zombie_nautilus",
        .soldierRecruit: "soldier_recruit", .soldierTrooper: "soldier_trooper", .soldierMarksman: "soldier_marksman",
        .soldierIronclad: "soldier_ironclad", .deckGun: "deck_gun",
        .copperGolem: "copper_golem",
        .soldierOfficer: "soldier_officer", .soldierCrew: "soldier_crew",
        .ashTank: "ash_tank", .ashHalftrack: "ash_halftrack", .ashArtillery: "ash_artillery", .ashTruck: "ash_truck", .ashMarshal: "ash_marshal",
    ]
    static func named(_ n: String) -> MobKind? { allCases.first { $0.key == n } }
    var call: Snd { spec.call }
    var name: String { spec.name }
}

final class Mob {
    static weak var trace: Mob?     // harness: print this mob's physics steps
    let kind: MobKind
    var spec: MobKind.Spec       // per mob: the Ashguard renames its soldiers (AshUnits.swift)
    var pos: V3
    var vel = V3(0, 0, 0)
    var yaw: Float
    var onGround = false
    var viewDY: Float = 0, viewDV: Float = 0        // eased step offset of the drawn model (ViewStep.swift)
    var health: Int
    var boatWear: Float = 0         // boats: wear toward the next lost health point (Boats.updateBoat)
    var scale: Float = 1            // babies 0.5
    var walkPhase: Float = 0
    var walkAmount: Float = 0
    var moving = false
    var wanderGoal: V3?             // current stroll target (wander)
    var strollArea: (V3, Float)?    // keep stroll targets within this circle (villager schedules), set per update
    var unreachable: V3?            // a walk target the pathfinder couldn't reach (giveUp)
    var unreachableTimer: Float = 0
    var strollFails = 0             // strolls given up in a row (a mob in a pit or a pen rests instead of retrying)
    var huntTime: Float = 0         // a wild predator's committed chase of its prey (Animals.swift)
    var fleeGoal: V3?               // where it runs from a threat, kept about a second (not re-aimed every tick)
    var fleeTime: Float = 0
    var bedWalk: V3?                // villager: heading to its bed tonight (villagerNight -> villagerDay)
    static weak var world: World?   // the world mobs are updating in (stroll targets)
    var path = PathState()          // ground navigation (Pathfinding.swift)
    var faceGoal: V3?               // what face() last aimed at during this update
    var aiTimer: Float
    var panic: Float = 0
    var hurt: Float = 0
    var invulnerable: Float = 0          // seconds of hurt invulnerability left (hit(iframes:))
    var lastHurtAmount = 0
    var spiderChasing = false            // a spider that turned on you in the dark keeps at it in the light
    var equipKeep: UInt8 = 0             // equipment slots picked up from the ground: they always drop (bit per slot)
    var arrowDamage = 0               // harness: health lost to arrow hits (not saved)
    var hurtSound = false           // set by hit(); MobManager plays the hurt call once
    var teleportSound = false       // set by teleport(); MobManager plays it at both ends
    var stepAcc: Float = 0          // distance walked since the last footstep sound
    var callTimer: Float
    var attackCooldown: Float = 0
    var fuse: Float = 0             // hisser
    var flinch: Float = 0           // hisser: a hit stops the swell this long
    var fire: Float = 0             // seconds left burning
    var fireTick: Float = 0
    var aggro = false               // voidwalker / spider provoked
    var stare: Float = 0            // voidwalker: s the player has looked it in the face (1.5 s provokes it)
    var inLove: Float = 0
    var breedCooldown: Float = 0
    var age: Float = 0              // babies grow up at 1200 s
    var baby = false
    var sheared = false
    var woolColor = "white"
    var eggTimer = Rand.float(in: 300...600)
    var killedByPlayer = false
    var slimeSize = 1

    var sized: Bool { kind == .slime || kind == .magmaCube }
    var halfW: Float { spec.halfW * (sized ? Float(slimeSize) : scale) }
    var height: Float { spec.height * (sized ? Float(slimeSize) : scale) }
    var admire: Float = 0           // boarling: seconds left inspecting a gold ingot before bartering
    var flyTarget: V3?              // wailer / cinderwisp hover target
    var volley = 0                  // cinderwisp: fireballs left in the current burst
    var persistent = false          // structure mobs never despawn at random
    // Depth toughness (task 22): monsters spawned deep underground take damage / power and deal damage x power.
    var power: Float = 1
    var faction = 0                 // soldiers crewing a capital ship: its faction (CapitalShips.swift); 0 Steelhold
    var phase = 0                   // hollow wyrm phase (see updateDragon)
    var phaseTime: Float = 0
    var circleAngle: Float = 0
    var aimHold: Float = 0          // bow mobs: > 0 while drawing on a target (arms raised, bow up)
    weak var healTarget: Mob?       // hollow crystal currently healing the dragon
    var sitDamage = 0               // damage the wyrm has taken during this perch
    var sideHeads: [Float] = [1, 1.5]   // Blight side heads: seconds until each fires again
    var peek: Float = 0             // shellsentry lid opening 0...1
    var home: V3?                   // villager / golem: where it was placed (it stays near)
    weak var target: Mob?           // golem: the monster it is chasing
    var effects: EffectSet?         // status effects (allocated on first use)
    var lootingLevel = 0            // Looting on the weapon that last hit it
    var villager: VillagerData?     // profession, level, trades
    var town = TownState()          // townsperson: anger, reactions, swings (Townsfolk.swift; not saved)
    var customName: String?         // name tag
    var owner: Bool?                // tamed by the player (wolves, cats, horses, parrots)
    var variant = 0                 // colour / breed variant
    var sitting = false
    var lying = false               // a villager asleep in its bed: drawn on its back along the bed (VillageLife)
    var collar = 0
    var saddled = false
    var armorTier = 0               // horse / wolf armour
    var armorHP = 0                 // wolf armour durability
    var chested = false
    var cargo: ItemContainer?      // chest boat / pack animal inventory
    var spin: Float = 0            // boat turn rate (deg per tick)
    var equip: [ItemStack]?        // head, chest, legs, feet, main hand
    var leashed = false
    var leashSeat = 0               // split screen: the player holding the lead (rope, pull and fence tying follow them)
    var knot: IVec3?               // fence the lead is tied to (nil = the player)
    var raider = false              // part of a raid
    var breakTimer: Float = 0       // blight: breaks surrounding blocks when this runs out
    var lifeSpan: Float = 1e9       // hexling: seconds before it starts to blight away
    var spellTimer: Float = 2       // conjurer: next spell
    var vexCooldown: Float = 0
    var stun: Float = 0             // siegebeast: stunned by a shield block, then roars
    var bond: Float = 0             // the player's bonded horse (Game.horseBond; Riding.swift), saved
    var playerBuilt = false         // iron golem built by the player (never attacks them)
    var cureTimer: Float = 0        // zombie villager being cured
    var charged = false             // hisser struck by lightning (bigger blast)
    var lastHitBySkeleton = false   // hissers killed by skeleton arrows drop a music disc
    var scuteTimer: Float = Rand.float(in: 300...600)   // armadillo scutes / snuffler digging
    var heldItem: ItemID = 0        // fetchling: item it collects
    var carried = 0                 // fetchling: collected count
    var airTime: Float = 0          // aquatic mobs out of water
    var beam: Float = 0             // spikefish laser charge
    var anger: Float = 0            // deep stalker
    var jumpCharge: Float = 0       // horse jump when ridden
    var boostTime: Float = 0        // pig / magmastrider stick boost: elapsed and total seconds (0 total = none)
    var boostTotal: Float = 0
    var temper = 0                  // horse taming progress
    weak var mount: Mob?            // rider (raid siegebeast riders)
    weak var deck: Ship?            // the moving ship it rides (ShipPhysics carries it; it walks in the ship's frame)
    var crewPost: V3?               // capital crew: its post in the ship's frame, held while the vehicle runs
    var crewRoute: [V3] = []        // capital crew: ship-space waypoints it walks (troops leaving by the ramp)
    var crewFree = false            // crew of a disabled vehicle: fights where it likes aboard, never off a ledge
    var captain = false             // raid / patrol captain (banner)
    var jobTimer: Float = Rand.float(in: 0...5)
    var giftTimer: Float = 0        // villager: seconds until it may throw the Village Hero another gift
    var breaksDoors = false         // zombie able to break wooden doors on Hard (reference: 10% x regional difficulty)
    var farTime: Float = 0          // seconds spent more than 32 blocks from the player (despawn timer)
    var jockey = false              // spawned riding another mob (chicken / spider jockeys)
    var driven: Float = 0           // mount steered by its rider this long
    var driveSpeed: Float = 0
    var driveYaw: Float = 0
    var lockTime: Float = 0         // remembers the player this long after last seeing them (MobAI.swift)
    var sightTimer: Float = Rand.float(in: 0...0.5)
    var wasHit = false              // hit since the last update (pack rally)
    var convertTime: Float = 0      // drowning zombie / freezing skeleton / boarling out of the Emberdeep / tadpole (Conversions.swift)
    var reinforceChance = Rand.float(in: 0..<0.1)
    var trap = false                // skeleton trap horse
    var carriedBlock: BlockID = 0   // voidwalker: block it picked up
    var canPickUp = false           // zombie / skeleton that picks up gear (55% x regional difficulty)
    var emergeTime: Float = 0       // deep stalker digging out of the ground (invulnerable meanwhile)
    var patrolling = false          // marauder patrol member (Raid.swift patrolTick)
    weak var patrolLeader: Mob?
    var patrolGoal: V3?
    var hasEgg = false              // turtle / frog / snuffler carrying an egg after breeding
    var hive: IVec3?                // bee: its nest / hive (Bees.swift)
    var golemGoal: IVec3?           // copper golem: the chest it is walking to (CopperGolem.swift)
    var golemVisited: [IVec3] = []  // copper golem: chests tried on this trip
    var golemTimer: Float = 0       // copper golem: search / give-up timer
    var nectar = false
    var flower: IVec3?
    var sleptAt: Double = -1e9      // villager: game time it last slept (golem summoning needs sleep within a day)
    var golemSeenAt: Double = -1e9  // villager: last saw an iron golem
    var gossipCooldown: Float = 0
    var meetPoint: IVec3?           // villager: the bell it meets at
    var meetSearch: Float = 0
    var brain: SoldierBrain?        // Capital soldiers and deck guns (Soldiers.swift, SoldierRig.swift)
    var strafe: Float = 0           // sideways walk speed this update (right is positive)

    init(_ kind: MobKind, at p: V3) {
        self.kind = kind
        spec = kind.spec
        pos = p
        yaw = Rand.float(in: 0..<(2 * .pi))
        health = kind.spec.health
        aiTimer = Rand.float(in: 0.5...3)
        callTimer = Rand.float(in: 6...20)
        randomizeVariant()
        if kind.ash { ashSetup() }
        if kind == .sheep {
            let r = Rand.float(in: 0..<1)
            woolColor = r < 0.81836 ? "white" : (r < 0.86836 ? "black" : (r < 0.91836 ? "gray" : (r < 0.96836 ? "light_gray" : (r < 0.99836 ? "brown" : "pink"))))
        }
    }

    func makeSlime(size: Int) {
        slimeSize = size
        health = size * size
    }

    // Anger this mob and every undead boarling nearby at the player.
    func provoke(_ g: Game) {
        aggro = true
        g.petsAttack(self)
        // Hitting a townsperson who is already fighting you (self-defence) doesn't cost more standing or raise a new alarm.
        if kind == .villager, town.anger <= 0, var v = villager { v.addGossip(.minorNeg, 25); villager = v; g.townAlarm(self) }
        if kind == .zombifiedPiglin {
            for o in g.mobs.mobs where o.kind == .zombifiedPiglin && simd_length(o.pos - pos) < 20 { o.aggro = true }
        }
    }

    var forward: V3 { V3(-sinf(yaw), 0, -cosf(yaw)) }
    /// Where a ranged mob's shot leaves: the bow in its raised right hand (skeletons), else just in front of the eyes.
    var bowMuzzle: V3 {
        guard Mob.bowKinds.contains(kind) else { return eye + forward * 0.3 }
        let r = V3(cosf(yaw), 0, -sinf(yaw))
        return pos + V3(0, 22.0 / 16 * scale, 0) + forward * 0.5 * scale + r * 0.31 * scale
    }
    static let bowKinds: Set<MobKind> = [.skeleton, .stray, .parched, .bogged]
    static let hisserFuse: Float = 1.75   // s of swell to blow (reference 1.5; playtest v78: a VR swing needs the extra)
    var eye: V3 { pos + V3(0, height * 0.85, 0) }

    func intersects(_ b: IVec3) -> Bool {
        let bx = Float(b.x), by = Float(b.y), bz = Float(b.z)
        return pos.x + halfW > bx && pos.x - halfW < bx + 1 && pos.y + height > by && pos.y < by + 1
            && pos.z + halfW > bz && pos.z - halfW < bz + 1
    }

    private func solid(_ x: Float, _ y: Float, _ z: Float, _ w: World) -> Bool {
        Blocks.collide[Int(w.block(Int(floor(x)), Int(floor(y)), Int(floor(z))))]
    }

    func face(_ p: V3) {
        let d = V2(p.x - pos.x, p.z - pos.z)
        if simd_length(d) > 0.01 { yaw = atan2f(-d.x, -d.y) }
        faceGoal = p
    }

    // MARK: Update

    func update(_ dt: Float, game g: Game) {
        let w = g.world
        // (A rider of a ship moves in the ship's frame and needs no ground loaded: crew at a long hull's far end.)
        guard deck != nil || w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) else { return }
        // A mob killed earlier this tick (player hit, projectile) is removed by the death sweep after this loop: it
        // must not act or heal in between (the Blight's 1 HP/s regeneration revived it and lost the Blight Star).
        if health <= 0 && kind != .enderDragon { return }
        if kind == .rabbit && variant < 16 { variant = 16 | FarmVariant.rabbitCoat(w, pos) }
        faceGoal = nil
        strafe = 0
        path.climbUp = false
        hurt = max(0, hurt - dt)
        invulnerable = max(0, invulnerable - dt)
        panic = max(0, panic - dt)
        callTimer -= dt
        aiTimer -= dt
        unreachableTimer -= dt
        attackCooldown -= dt
        inLove = max(0, inLove - dt)
        breedCooldown = max(0, breedCooldown - dt)
        // Young animals and villagers grow up in 20 minutes; baby monsters (zombies, boarlings) never do.
        if baby && (!kind.hostile || kind == .hoglin) {
            age += dt
            if age >= 1200 {
                baby = false; scale = 1
                // A baby turtle growing up sheds a scute (reference).
                if kind == .turtle && Items.has("turtle_scute") { g.drops.spawn(ItemStack(Items.id("turtle_scute"), 1), at: pos + V3(0, 0.3, 0)) }
            }
        }
        if leashed { leashTick(dt, g) }
        if kind == .boat { updateBoat(dt, g); return }
        if kind == .armorStand { updateArmorStand(dt, g); return }
        if kind == .goat && aggro { goatRam(g) }
        if g.riding === self && kind != .minecart { updateRidden(dt, g); return }
        if kind == .enderDragon { updateDragon(dt, g); return }
        if kind == .endCrystal { updateCrystal(dt, g); return }
        if kind == .shulker { updateSentry(dt, g); return }
        if kind == .deckGun { updateDeckGun(dt, g); return }
        if kind == .minecart { updateMinecart(dt, g); cartExtras(dt, g); return }
        if kind == .wither { updateBlight(dt, g); return }
        if cureTick(dt, g) { return }
        if kind == .vex { updateVex(dt, g); return }

        let feetBlock = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))
        let inWater = Blocks.isLiquid(feetBlock) && !w.ships.dry(at: pos + V3(0, 0.2, 0))     // not inside a hull

        // Undead burn in daylight under open sky.
        if spec.burnsInSun && !inWater && g.dim.dim.hasSky && g.daylight > 0.6 && !g.isRainingAt(pos) {
            let l = w.lightAt(Int(floor(pos.x)), Int(floor(pos.y + height)), Int(floor(pos.z)))
            if l.sky >= 15 {
                // A helmet shields the head from the sun and wears down instead (reference).
                if var eq = equip, !eq[0].isEmpty {
                    if Rand.float(in: 0..<1) < dt * 0.5 {
                        eq[0].damage += 1
                        let dur = eq[0].def.durability
                        if dur > 0 && eq[0].damage >= dur { eq[0] = .empty; g.sfx(.breakBlock(.stone), 0.6, at: pos) }
                        equip = eq
                    }
                } else {
                    fire = max(fire, 8)
                }
            }
        }
        if inWater && Blocks.fluidKind[Int(feetBlock)] == 1 { fire = 0 }
        if spec.fireImmune { fire = 0 }
        let contact = spec.fireImmune ? 0 : Blocks.contactDamage[Int(feetBlock)]
        if contact > 0 && kind != .slime {
            if Blocks.fluidKind[Int(feetBlock)] == 2 || feetBlock == FIRE { fire = max(fire, 8) }
            if attackCooldown < -0.5 { health -= Int(contact); hurt = 0.3; attackCooldown = 0 }
        }
        if fire > 0 {
            fire -= dt
            fireTick += dt
            if fireTick >= 1 { fireTick = 0; health -= 1; hurt = 0.3 }
            if effects?.has(.fireResistance) ?? false { fire = 0 }
        }
        effectTick(dt, g)
        if canPickUp { pickUpLoot(g) }
        if conversionTick(dt, g) { return }
        if trap { trapTick(g) }
        if spec.aquatic { updateAquatic(dt, g, inWater: inWater); return }

        let player = g.player.pos
        let toPlayer = player - pos
        let dist = simd_length(toPlayer)
        // Invisible players are only noticed up close.
        let canTarget = senseTarget(g, dist: dist, dt)
        var speed: Float = 0
        if wasHit { wasHit = false; rallyPack(g) }
        let fleeFrom = panic > 0 ? nil : threat(g)

        switch spec.behavior {
        case _ where fleeFrom != nil:
            // Avoid-entity goal: run to a spot 8 blocks away from the threat, re-aimed about once a second (a point
            // re-aimed every tick moved with the mob and replanned its path each time: behaviour sim, fleeing rabbits).
            fleeTime -= dt
            if fleeGoal == nil || fleeTime <= 0 || simd_length(V2(fleeGoal!.x - pos.x, fleeGoal!.z - pos.z)) < 1.5 {
                var away = V3(pos.x - fleeFrom!.x, 0, pos.z - fleeFrom!.z)
                if simd_length(away) < 0.01 { away = V3(1, 0, 0) }
                fleeGoal = pos + simd_normalize(away) * 8
                fleeTime = Rand.float(in: 0.8...1.4)
            }
            face(fleeGoal!)
            moving = true
            speed = spec.speed * 1.25
            fuse = max(0, fuse - dt)
        case .passive:
            // Follow a player holding breeding food; seek a mate when in love.
            if let food = MobManager.breedFood[kind], dist < 8, food.contains(Items.key(g.held.item)), !baby {
                face(player); moving = dist > 2; speed = dist > 2 ? spec.speed : 0
            } else if inLove > 0, let mate = g.mobs.mobs.first(where: { $0 !== self && $0.kind == kind && $0.inLove > 0 && simd_length($0.pos - pos) < 8 }) {
                face(mate.pos)
                speed = simd_length(mate.pos - pos) > 1.2 ? spec.speed : 0
            } else if panic <= 0 && followParent(g) {
                speed = spec.speed
            } else {
                wander()
                speed = moving ? (panic > 0 ? (kind == .chicken ? 2.4 : 2.8) : spec.speed) : 0
            }
            if kind == .sheep { sheepGraze(dt, g) }
            if variant == 0 && (kind == .cow || kind == .pig || kind == .chicken) { variant = FarmVariant.forBiome(g.world, pos) }
            if kind == .chicken && !baby {
                eggTimer -= dt
                if eggTimer <= 0 { eggTimer = Rand.float(in: 300...600); g.drops.spawn(ItemStack(Items.id(FarmVariant.eggKey(variant)), 1), at: pos + V3(0, 0.3, 0)) }
            }
        case .neutral, .piglin:
            // Zombified boarlings only fight back; boarlings attack players not wearing gold armor.
            let goldWorn = g.inventory.armor.slots.contains { !$0.isEmpty && Items.key($0.item).hasPrefix("golden_") }
            let angry = aggro || (spec.behavior == .piglin && !goldWorn && dist < 12 && admire <= 0)
            var gold: ItemEntity?
            if kind == .piglin && !baby && admire <= 0 && !angry {
                gold = g.drops.items.first { !$0.stack.isEmpty && $0.pickupDelay <= 0 && Items.key($0.stack.item) == "gold_ingot" && simd_length($0.pos - pos) < 8 }
            }
            if admire > 0 {
                admire -= dt
                speed = 0
                if admire <= 0 { g.barter(self) }
            } else if let e = gold {
                // Boarlings walk over to gold ingots lying around and pick one up to barter with.
                face(e.pos)
                speed = spec.speed
                if simd_length(e.pos - pos) < 1.3 {
                    var st = e.stack; st.count -= 1; e.stack = st.count > 0 ? st : .empty
                    admire = 6
                    g.sfx(.mobBoarling, 0.8, at: pos)
                }
            } else if canTarget && angry {
                face(player)
                speed = spec.speed * 1.2
                if dist < halfW + 1.3 && abs(toPlayer.y) < 2 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by \(spec.name)", attacker: self)
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .ghast:
            // Drifts around; shoots an explosive fireball at a visible player within 64 blocks every 3 s.
            if flyTarget == nil || aiTimer <= 0 || simd_length(flyTarget! - pos) < 2 {
                aiTimer = Rand.float(in: 3...7)
                flyTarget = pos + V3(Rand.float(in: -16...16), Rand.float(in: -8...8), Rand.float(in: -16...16))
            }
            if canTargetFar(g, dist, 64) && w.canSee(eye, g.player.eye) {
                face(player)
                attackCooldown -= 0
                if attackCooldown <= 0 {
                    attackCooldown = 3
                    let from = pos + V3(0, height * 0.5, 0) + forward * 2.2
                    g.projectiles.fireball(from: from, dir: simd_normalize(g.player.eye - from), big: true, byPlayer: false)
                    g.sfx(.fireball, 1.2, at: from)
                }
            } else {
                let d = flyTarget! - pos
                yaw = atan2f(-d.x, -d.z)
            }
            speed = 0
            let d = flyTarget! - pos
            let l = simd_length(d)
            if l > 0.1 {
                let want: V3 = d * (spec.speed / l)
                let k: Float = min(1, dt * 1.5)
                vel += (want - vel) * k
            }
        case .blaze:
            // Hovers a little above the player; bursts of three small fireballs.
            let hover = canTargetFar(g, dist, 48) ? player.y + 2.5 : pos.y + Rand.float(in: -1...1)
            vel.y += ((hover - pos.y) * 1.5 - vel.y) * min(1, dt * 2)
            if canTargetFar(g, dist, 48) && w.canSee(eye, g.player.eye) {
                face(player)
                speed = dist > 6 ? spec.speed : 0
                if dist < 1.8 && attackCooldown <= 0 && volley == 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Cinderwisp")
                } else if attackCooldown <= 0 {
                    if volley == 0 { volley = 3 }
                    let from = eye + forward * 0.5
                    var dir = simd_normalize(g.player.eye - V3(0, 0.4, 0) - from)
                    let spread = sqrtf(dist) * 0.02
                    dir = simd_normalize(dir + V3(Rand.float(in: -spread...spread), 0, Rand.float(in: -spread...spread)))
                    g.projectiles.fireball(from: from, dir: dir, big: false, byPlayer: false)
                    g.sfx(.fireball, 0.6, at: from)
                    volley -= 1
                    attackCooldown = volley > 0 ? 0.3 : 8        // reference: 5 s rest + 3 s charge between volleys
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0; volley = 0 }
            if Rand.float(in: 0..<1) < dt * 6 { g.particles.smoke(at: pos + V3(Rand.float(in: -0.4...0.4), Rand.float(in: 0.2...1.4), Rand.float(in: -0.4...0.4))) }
        case .dragon, .crystal, .shulker, .vehicle, .wither, .vex:
            break
        case .evoker: speed = aiEvoker(dt, g, dist: dist, canTarget: canTarget)
        case .ravager: speed = aiRavager(dt, g, dist: dist, canTarget: canTarget)
        case .snowGolem: speed = aiSnowGolem(dt, g, inWater: inWater)
        case .animal: speed = bondedHorseAI(dt, g, dist: dist) ?? animalAI(dt, g, dist: dist, canTarget: canTarget, inWater: inWater)
            if kind == .horse { speed *= horseSpeed / 10.4 }            // a fast horse visibly trots and bolts faster
        case .monster: speed = monsterAI(dt, g, dist: dist, canTarget: canTarget, inWater: inWater)
        case .witch:
            // Reference witch: drinks water breathing / fire resistance / healing / swiftness as needed, and
            // throws slowness (far), poison (healthy target), weakness (close, 25%) or harming.
            if attackCooldown <= 0 {
                var drink: String?
                if inWater && !(effects?.has(.waterBreathing) ?? false) && Rand.float(in: 0..<1) < 0.15 { drink = "water_breathing" }
                else if fire > 0 && !(effects?.has(.fireResistance) ?? false) && Rand.float(in: 0..<1) < 0.15 { drink = "fire_resistance" }
                else if health < spec.health && Rand.float(in: 0..<1) < 0.05 { drink = "healing" }
                else if canTarget && dist > 11 && !(effects?.has(.speed) ?? false) && Rand.float(in: 0..<1) < 0.5 { drink = "swiftness" }
                if let d = drink, let t = Potions.types.first(where: { $0.key == d }) {
                    attackCooldown = 1.6
                    for e in t.effects { applyEffect(e.0, amp: e.2, seconds: e.1, game: g) }
                    g.sfx(.drink, 0.6, at: pos)
                }
            }
            if canTarget && dist < 16 && w.canSee(eye, g.player.eye) {
                face(player)
                speed = dist > 8 ? spec.speed : (dist < 4 ? -spec.speed * 0.5 : 0)
                if attackCooldown <= 0 && dist < 10 {
                    attackCooldown = 3
                    var d = g.player.eye - eye
                    d.y += simd_length(V2(d.x, d.z)) * 0.15
                    var type = "harming"
                    if dist >= 8 && !g.effects.has(.slowness) { type = "slowness" }
                    else if g.health >= 8 && !g.effects.has(.poison) { type = "poison" }
                    else if dist <= 3 && !g.effects.has(.weakness) && Rand.float(in: 0..<1) < 0.25 { type = "weakness" }
                    g.projectiles.fireball(from: eye + forward * 0.4, dir: simd_normalize(d), big: false, byPlayer: false, potion: Potions.item(1, type) ?? 0)
                    g.sfx(.bow, 0.5, at: pos)
                }
            } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .villager:
            // Wander near home; run from zombies; claim a job site; work there by day; restock.
            if home == nil { home = pos }
            jobTimer -= dt
            if jobTimer <= 0 {
                jobTimer = 5
                if villager == nil {
                    var v = VillagerData()
                    let b = g.world.gen.column(Int(floor(pos.x)), Int(floor(pos.z))).biome
                    v.type = Villagers.type(for: b)
                    // One in ~8 village villagers is a nitwit (reference spawn odds for unemployed variants).
                    if !baby && Rand.float(in: 0..<1) < 0.12 { v.profession = "nitwit" }
                    villager = v
                }
                findJob(g)
                if villager?.person == nil || villager?.town == nil { Townsfolk.setup(self, game: g) }
                else if villager?.role == "child" && !baby { villager?.role = nil; Townsfolk.setup(self, game: g) }     // grew up
                restock(g)
                villageTick(g)
            }
            // Townsfolk: fight monsters (and a player who hurt one of them), react to the player, then the routine.
            if let s = townDefend(dt, g) {
                if lying { pos.y += 0.1; lying = false; sitting = false }
                speed = s; break
            }
            if townReact(dt, g) { speed = 0; break }
            if villagerNight(g) { speed = 0; break }
            speed = villagerDay(dt, g)
        case .golem:
            if home == nil { home = pos }
            // Village-made golems defend villagers from a player they think badly of (reputation <= -100).
            jobTimer -= dt
            if jobTimer <= 0 {
                jobTimer = 1
                if !playerBuilt && g.villagersHatePlayer(near: pos) { aggro = true; lockTime = max(lockTime, 5) }
            }
            if target == nil || target!.health <= 0 || simd_length(target!.pos - pos) > 20 {
                target = g.mobs.mobs.first { $0.kind.hostile && $0.kind != .creeper && $0.health > 0 && simd_length($0.pos - pos) < 16 }
            }
            if let t = target {
                face(t.pos)
                let d = simd_length(t.pos - pos)
                speed = d > halfW + t.halfW + 0.8 ? spec.speed * 1.4 : 0
                if d < halfW + t.halfW + 1.2 && attackCooldown <= 0 {
                    attackCooldown = 1.25
                    t.hit(from: pos, damage: Rand.int(in: 7...21), knockback: 1)
                    t.vel.y += 8
                    g.sfx(.attack, 0.9, at: t.pos)
                }
            } else if aggro && canTarget && dist < 16 {
                face(player)
                speed = spec.speed * 1.4
                if dist < 2.2 && attackCooldown <= 0 {
                    attackCooldown = 1.25
                    g.hurtPlayer(Rand.int(in: 7...21), from: pos, cause: "was slain by Iron Golem", knockback: 2)
                }
            } else {
                // Too far from home: walk back (wander() faced the stroll goal and this faced home, every tick: the
                // golem flipped between the two on the spot, behaviour sim spinning 20 windows).
                if let h = home, simd_length(V2(h.x - pos.x, h.z - pos.z)) > 12 && !gaveUp(h) {
                    wanderGoal = nil; face(h); moving = true
                } else {
                    wander()
                }
                speed = moving ? spec.speed * 0.4 : 0
            }
        case .melee, .spider:
            let l = w.lightAt(Int(floor(pos.x)), Int(floor(pos.y + 0.5)), Int(floor(pos.z)))
            // Spiders: hostile below raw light 12 (block light or darkened sky); a spider already after you gives up in
            // the light only 1 time in 100 a tick (reference; any shade at all turned them, and light dropped the chase).
            var hostileNow = spec.behavior == .melee || aggro
            if !hostileNow {
                let darken = max(0, min(11, Int(((1 - (g.daylight - 0.12) / 0.88) * 11).rounded())))
                let raw = max(l.block, l.sky - darken)
                if raw < 12 { hostileNow = true; spiderChasing = true }
                else if spiderChasing && Rand.float(in: 0..<1) >= dt * 0.2 { hostileNow = true }
                else { spiderChasing = false }
            }
            // Zombies go for villagers, raiders for villagers and golems (when nearer than the player).
            if let v = villagerTarget(g), !(canTarget && hostileNow && dist <= simd_length(v.pos - pos)) {
                face(v.pos)
                speed = spec.speed * (baby ? 1.5 : 1)
                if simd_length(v.pos - pos) < halfW + v.halfW + 1 && attackCooldown <= 0 {
                    attackCooldown = 1
                    v.hit(from: pos, damage: meleeDamage, knockback: 0.6)
                    if v.health <= 0 && v.kind == .villager && isZombie && Rand.float(in: 0..<1) < ([0, 0, 0.5, 1] as [Float])[max(0, min(3, g.difficulty))] { v.health = -2000; g.zombify(v) }
                }
            } else if canTarget && hostileNow {
                face(player)
                speed = spec.speed * (baby ? 1.5 : 1)
                if drownedThrow(g, dist: dist) { speed = 0 }
                // Spiders leap at a target 2-4 blocks away (reference leap goal).
                if (kind == .spider || kind == .caveSpider) && onGround && dist > 2 && dist < 4 && Rand.float(in: 0..<1) < dt * 4 {
                    vel += forward * 4 + V3(0, 5, 0)
                }
                let reach = halfW + 1.1
                if dist < reach + 0.2 && abs(toPlayer.y) < 2 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(meleeDamage, from: pos, cause: "was slain by \(spec.name)", attacker: self)
                    if kind == .witherSkeleton { g.applyEffect(.wither, amp: 0, seconds: 10) }
                    if kind == .caveSpider {
                        let poison: [Float] = [0, 0, 7, 15]                 // none on easy, 15 s on hard (reference)
                        let s = poison[max(0, min(3, g.difficulty))]
                        if s > 0 { g.applyEffect(.poison, amp: 0, seconds: s) }
                    }
                    if kind == .husk { g.applyEffect(.hunger, amp: 0, seconds: 7) }
                }
            } else if let ps = patrolStep(g) { speed = ps } else if let es = trampleEggs(dt, g) { speed = es } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .ranged:
            aimHold = max(0, aimHold - dt)
            if kind == .illusioner && canTarget { illusionerSpells(dt, g) }
            if let v = villagerTarget(g), !(canTarget && dist <= simd_length(v.pos - pos)), w.canSee(eye, v.pos + V3(0, v.height * 0.6, 0)) {
                face(v.pos)
                aimHold = 0.8
                let dv = simd_length(v.pos - pos)
                speed = dv > 10 ? spec.speed : (dv < 5 ? -spec.speed * 0.6 : 0)
                if attackCooldown <= 0 && dv < 16 {
                    attackCooldown = crossbowReload
                    var d = v.pos + V3(0, v.height * 0.6, 0) - eye
                    d.y += simd_length(V2(d.x, d.z)) * 0.2
                    tipArrow(g.projectiles.shoot(from: bowMuzzle, dir: simd_normalize(d), speed: kind == .pillager ? 40 : 32, fromPlayer: false, damage: 2))
                    g.sfx(.bow, 0.7, at: pos)
                }
            } else if canTarget && w.canSee(eye, g.player.eye) {
                face(player)
                aimHold = 0.8
                speed = dist > 10 ? spec.speed : (dist < 5 ? -spec.speed * 0.6 : 0)
                // Bow skeletons circle-strafe in range, switching side now and then (reference ranged bow goal).
                if kind != .pillager && kind != .illusioner && dist <= 12 {
                    phaseTime -= dt
                    if phaseTime <= 0 {
                        phaseTime = 1
                        if circleAngle == 0 || Rand.float(in: 0..<1) < 0.3 { circleAngle = circleAngle > 0 ? -1 : 1 }
                    }
                    strafe = circleAngle * spec.speed * 0.5
                }
                if attackCooldown <= 0 && dist < 16 {
                    attackCooldown = crossbowReload
                    let target = g.player.eye - V3(0, 0.3, 0)
                    var d = target - eye
                    let horiz = simd_length(V2(d.x, d.z))
                    d.y += horiz * 0.2
                    // Marauders fire crossbow bolts (faster, flatter).
                    tipArrow(g.projectiles.shoot(from: bowMuzzle, dir: simd_normalize(d), speed: kind == .pillager ? 32 : 32 + Rand.float(in: -3...3), fromPlayer: false, damage: 2))   // 1.6 a tick (reference)
                    g.sfx(.bow, 0.7, at: pos)
                }
            } else if let ps = patrolStep(g) { speed = ps } else { wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .creeper:
            if canTarget {
                face(player)
                // Reference swell goal: starts within 3 blocks, keeps swelling until the target is 7+ away or out of
                // sight (behind a wall it un-swells instead of blowing up through it).
                if flinch > 0 {
                    flinch -= dt
                    speed = 0
                } else if (dist < 3 || (fuse > 0 && dist < 7)) && w.canSee(eye, g.player.eye) {
                    if fuse == 0 { g.sfx(.creeperHiss, 1, at: pos) }
                    fuse += dt
                    speed = 0
                } else {
                    fuse = max(0, fuse - dt)
                    speed = spec.speed
                }
                if fuse >= Mob.hisserFuse {
                    Explosion.explode(at: pos + V3(0, 0.8, 0), power: charged ? 6 : 3, game: g)
                    health = -1000
                    return
                }
            } else { fuse = max(0, fuse - dt); wander(); speed = moving ? spec.speed * 0.5 : 0 }
        case .enderman:
            // Provoked by being looked at (in the face) or hit; teleports away from water.
            if !aggro && canTarget && dist < 64 && Items.key(g.inventory.armor[0].item) != "carved_pumpkin" {
                let head = pos + V3(0, height - 0.3, 0)
                let rel = head - g.player.eye
                let rd = max(0.1, simd_length(rel))
                // Reference isLookingAtMe: dot > 1 - 0.025 / distance (about 4 degrees at 10 blocks; it was a fixed 8).
                // A steady look for 1.5 s provokes it, not a glance (Remington, Quest round 3); looking away drains it.
                if simd_dot(g.player.look, rel / rd) > 1 - 0.025 / rd && w.canSee(g.player.eye, head) { stare += dt } else { stare = max(0, stare - dt * 2) }
                if stare >= 1.5 { aggro = true; stare = 0; g.sfx(.mob(.enderman, .hurt), 1.2, at: pos) }
            }
            if inWater { teleport(w) }
            voidwalkerTick(dt, g)
            if aggro && canTarget {
                face(player)
                speed = spec.speed * 2
                // Far from its target, an angry voidwalker blinks closer (reference teleport-towards).
                if dist > 16 && Rand.float(in: 0..<1) < dt * 0.5 {
                    let back = simd_normalize(V3(pos.x - player.x + 1e-4, 0, pos.z - player.z))     // straight above: no NaN
                    let to = player + back * Rand.float(in: 3...8)
                    let x = Int(floor(to.x)), z = Int(floor(to.z))
                    let top = w.topY(x, z)
                    if top > 0 && abs(Float(top + 1) - player.y) < 8 && !Blocks.isLiquid(w.block(x, top, z)) {
                        pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
                        vel = .zero
                    }
                }
                if dist < 1.6 && attackCooldown <= 0 {
                    attackCooldown = 1
                    g.hurtPlayer(spec.attack, from: pos, cause: "was slain by Voidwalker", attacker: self)
                }
            } else { wander(); speed = moving ? spec.speed * 0.4 : 0 }
        case .slime:
            if onGround && aiTimer <= 0 {
                aiTimer = Rand.float(in: 1...2)
                if canTarget { face(player) } else { yaw += Rand.float(in: -1.5...1.5) }
                vel.y = kind == .magmaCube ? 7 + Float(slimeSize) * 0.8 : 7
                vel.x = forward.x * spec.speed * 1.5
                vel.z = forward.z * spec.speed * 1.5
                g.sfx(kind == .magmaCube ? .mob(.magmaCube, .ambient) : .place(.slime), slimeSize > 1 ? 0.6 : 0.35, at: pos)
            }
            if canTarget && (slimeSize > 1 || kind == .magmaCube) && dist < halfW + 0.9 && attackCooldown <= 0 {
                attackCooldown = 1
                let dmg = kind == .magmaCube ? [0, 3, 4, 0, 6][min(4, slimeSize)] : (slimeSize == 4 ? 4 : 2)
                g.hurtPlayer(dmg, from: pos, cause: "was slain by \(spec.name)", attacker: self)
            }
        }

        // Crew aboard a capital vehicle hold their posts in the hull's frame (they turn and fire as the soldier AI
        // decides, but don't stroll, flank or chase off the deck); troops sent out walk their route down the ramp.
        if let s = deck, crewPost != nil || !crewRoute.isEmpty || crewFree { speed = crewStep(s, speed) }
        // A passive mount carrying a jockey goes where the rider wants.
        if driven > 0 {
            driven -= dt
            yaw = driveYaw
            speed = driveSpeed
            faceGoal = nil
        }
        // Riders sit on their mount (and attack from there).
        if let mt = mount {
            if mt.health > 0 {
                if speed != 0 && !mt.kind.hostile { mt.driven = 0.3; mt.driveSpeed = abs(speed); mt.driveYaw = speed < 0 ? yaw + .pi : yaw }
                pos = mt.pos + V3(0, mt.height * 0.8, 0)
                vel = .zero
                onGround = true
                return
            }
            mount = nil
        }
        // Walking towards something: follow a path around obstacles instead of straight at it.
        var onPath = false
        if speed > 0, let t = faceGoal, !spec.flying, spec.behavior != .slime {
            steerAlongPath(t, dt, g, repath: onGround || inWater)
            onPath = path.index < path.nodes.count
        } else {
            path.stallPos = pos; path.stallTime = 0          // standing still on purpose is not a stall
        }
        // Passive mobs avoid drops and water while calmly wandering. Not while following a path (the path finder
        // already weighs water and drops), and after steering so the probe looks along the waypoint: probing along
        // the straight line to a stroll goal behind a pond turned the mob half round every second or two
        // (behaviour sim: pigs, wolves, rabbits, chickens spinning 800-1100 degrees in 10 s on strolls).
        if spec.behavior == .passive && speed > 0 && onGround && panic <= 0 && !onPath {
            let a = pos + forward * (halfW + 0.45)
            let wet = Blocks.isLiquid(w.block(Int(floor(a.x)), Int(floor(pos.y - 0.5)), Int(floor(a.z))))
            let drop = !solid(a.x, pos.y - 0.5, a.z, w) && !solid(a.x, pos.y - 1.5, a.z, w) && !solid(a.x, pos.y - 2.5, a.z, w)
            if wet || drop { yaw += .pi * Rand.float(in: 0.6...1.4); speed = 0; moving = false; aiTimer = Rand.float(in: 1...3) }
        }
        // Calm soldiers walking straight (no path to an order or stroll goal) stop at a ledge rather than step off it
        // (citadel behaviour sim: a patrol leader searching a hillside fell 5 blocks).
        if kind.steelhold && !aggro && speed > 0 && onGround && !onPath {
            let a = pos + forward * (halfW + 0.45)
            if !solid(a.x, pos.y - 0.5, a.z, w) && !solid(a.x, pos.y - 1.5, a.z, w) && !solid(a.x, pos.y - 2.5, a.z, w) { speed = 0 }
        }
        if spec.flying {
            if kind == .blaze && speed != 0 {
                let target = forward * speed
                vel.x += (target.x - vel.x) * min(1, dt * 4)
                vel.z += (target.z - vel.z) * min(1, dt * 4)
            }
            if kind == .blaze && speed == 0 { vel.x *= expf(-3 * dt); vel.z *= expf(-3 * dt) }
            let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: false)
            if hit.x { vel.x = 0; flyTarget = nil }
            if hit.y { vel.y = 0; flyTarget = nil }
            if hit.z { vel.z = 0; flyTarget = nil }
            onGround = false
            walkPhase += dt * 3
            return
        }
        if spec.behavior != .slime || onGround {
            // Magmastriders out of lava are cold: half speed (reference).
            let cold: Float = kind == .strider && Blocks.fluidKind[Int(w.block(Int(floor(pos.x)), Int(floor(pos.y - 0.2)), Int(floor(pos.z))))] != 2
                && Blocks.fluidKind[Int(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.3)), Int(floor(pos.z))))] != 2 ? 0.5 : 1
            let side = V3(cosf(yaw), 0, -sinf(yaw)) * strafe
            let target = (forward * speed + side) * effectSpeed * cold
            let k = 1 - expf(-(onGround ? 12 : 3) * dt)
            vel.x += (target.x - vel.x) * k
            vel.z += (target.z - vel.z) * k
            if abs(vel.x) < 1e-5 { vel.x = 0 }          // settled: no subnormal tail for `!= 0` tests to see
            if abs(vel.z) < 1e-5 { vel.z = 0 }
        }
        if kind == .drowned && inWater && canTarget {
            vel.y += ((player.y - pos.y) * 2 - vel.y) * min(1, dt * 3)
        } else if kind == .strider && Blocks.fluidKind[Int(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.3)), Int(floor(pos.z))))] == 2 {
            vel.y = 2          // magmastriders stand on lava
        } else if inWater {
            vel.y += 18 * dt
            vel.y = min(vel.y, 1.6)
            vel.y *= expf(-2 * dt)
        } else {
            vel.y -= 28 * dt
            if kind == .chicken { vel.y = max(vel.y, -3.5) }
            vel.y = max(vel.y, -40)
        }

        // Ladders and vines: climb when the path leads up (centred on the rung), slow slide otherwise.
        let lx = Int(floor(pos.x)), lz = Int(floor(pos.z))
        let onLadder = !spec.flying && (PathFinder.climbable(w.block(lx, Int(floor(pos.y)), lz)) || PathFinder.climbable(w.block(lx, Int(floor(pos.y + 1)), lz)))
        if onLadder {
            if path.climbUp {
                vel.y = 2.35
                vel.x = (Float(lx) + 0.5 - pos.x) * 4
                vel.z = (Float(lz) + 0.5 - pos.z) * 4
            } else {
                vel.y = max(vel.y, -3)
            }
        }

        let before = pos
        var hit: (x: Bool, y: Bool, z: Bool)
        var deckBumped = false
        if let s = deck {
            // On a moving deck: walk and collide in the ship's own frame (its blocks are exact there; the
            // world-space boxes of a turned hull are only an approximation), with velocity relative to the deck.
            var l = s.toLocal(pos)
            var lv = s.dirToLocal(vel)
            w.frame = s
            if collides(l, w) {
                // Carried into a block (the hull settling onto a rider at the ramp's foot, ground beside it): step up
                // to the first free height within a block, as a walker would, instead of being shoved out sideways.
                var up: Float = 0.1
                while up <= 1.01 && collides(l + V3(0, up, 0), w) { up += 0.1 }
                if up <= 1.01 { l.y += up; pos = s.toWorld(l) }
            }
            // A length test, not `!= 0`: a crew member's velocity decays geometrically into subnormal floats at its post,
            // and normalizing those gave NaN, which trapped in the collision test (Int(floor(NaN)); level frigate decks).
            if (crewPost != nil || crewFree || !crewRoute.isEmpty) && onGround && lv.x * lv.x + lv.z * lv.z > 1e-6 {
                // Crew never step off a ledge of their vehicle: no floor within three blocks where the next step lands.
                let h = simd_normalize(V2(lv.x, lv.z))
                let a = l + V3(h.x, 0, h.y) * (halfW + 0.35)
                if !w.collides(V3(a.x - 0.2, a.y - 3, a.z - 0.2), V3(a.x + 0.2, a.y + 0.05, a.z + 0.2)) { lv.x = 0; lv.z = 0 }
            }
            hit = w.moveBody(&l, halfW: halfW, height: height, lv * dt, step: 0.6, onGround: onGround)
            w.frame = nil
            if hit.x { lv.x = 0 }
            if hit.z { lv.z = 0 }
            pos = s.toWorld(l)
            if hit.x || hit.z { let wv = s.dirToWorld(lv); vel.x = wv.x; vel.z = wv.z; deckBumped = true }
            hit.x = false; hit.z = false                  // handled in the ship's axes above
        } else {
            hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0.6, onGround: onGround)
        }
        if self === Mob.trace {
            print(String(format: "      pre %.3f,%.3f,%.3f vel %.2f,%.2f,%.2f -> %.3f,%.3f,%.3f hit %@%@%@ ground %@ speed %.2f yaw %.0f", before.x, before.y, before.z,
                         vel.x, vel.y, vel.z, pos.x, pos.y, pos.z, hit.x ? "x" : "-", hit.y ? "y" : "-", hit.z ? "z" : "-", onGround ? "1" : "0", speed, yaw * 180 / .pi))
            if path.index < path.nodes.count {
                let n = path.nodes[path.index]
                let ny: Int = n.y - YOFF
                print(String(format: "        node %ld/%ld at %ld,%ld,%ld, stall %.1f s, moving %@, ai %.1f", path.index, path.nodes.count, n.x, ny, n.z, path.stallTime, moving ? "yes" : "no", aiTimer))
            } else {
                print(String(format: "        no node (%ld), stall %.1f s, moving %@, ai %.1f", path.nodes.count, path.stallTime, moving ? "yes" : "no", aiTimer))
            }
        }
        var landed = false, bumped = deckBumped
        if hit.y { if vel.y < 0 { landed = true }; vel.y = 0 }
        if hit.x { vel.x = 0; bumped = true }
        if hit.z { vel.z = 0; bumped = true }
        if let s = deck {
            w.frame = s
            onGround = landed || (vel.y <= 0 && collides(s.toLocal(pos) - V3(0, 0.06, 0), w))
            w.frame = nil
        } else {
            onGround = landed || (vel.y <= 0 && collides(pos - V3(0, 0.06, 0), w))
        }
        if bumped && speed != 0 {
            if kind == .spider || kind == .caveSpider { vel.y = 3.5 }     // climbs walls
            else if onLadder { vel.y = 2.35 }
            // Hop up one block: gravity acts before the first move, so 7.4 left the ground at 6.0 and peaked 0.8 up,
            // short of a full block (behaviour-sim trace, run 355: villagers bounced at every 1-block step for
            // minutes). The player's 8.6 peaks at 1.1.
            else if onGround && spec.behavior != .slime { vel.y = 8.6 }
        }
        if pos.y < -10 { health = 0 }

        let hs = simd_length(V2(vel.x, vel.z))
        // Horses: long strides, so the gait rate grows slower than the speed (a gallop is ~4 strides/s, not 10).
        let horsey = kind == .horse || kind == .donkey || kind == .mule || kind == .skeletonHorse || kind == .zombieHorse
        walkPhase += hs * dt * 5.5 / (horsey ? 1 + hs * 0.12 : 1)
        walkAmount += (min(1, hs / 1.2) - walkAmount) * min(1, dt * 8)
    }

    // Capital crew aboard (see crewPost): the speed to walk this tick, setting yaw / strafe in the ship's frame.
    func crewStep(_ s: Ship, _ want: Float) -> Float {
        let l = s.toLocal(pos)
        let walking = !crewRoute.isEmpty
        var goal: V3
        if walking {
            goal = crewRoute[0]
            if simd_length(V2(goal.x - l.x, goal.z - l.z)) < 0.6 {
                crewRoute.removeFirst()
                if crewRoute.isEmpty { faceGoal = nil; strafe = 0; return 0 }
                goal = crewRoute[0]
            }
        } else if crewFree {
            faceGoal = nil          // straight at what it wants (the path finder reads the world, not the hull)
            return want
        } else if let p = crewPost {
            goal = p
        } else {
            return want
        }
        faceGoal = nil
        let d = s.dirToWorld(V3(goal.x - l.x, 0, goal.z - l.z))
        let dist = simd_length(d)
        if !walking && dist < 0.3 { strafe = 0; return 0 }
        let dir = d / max(dist, 1e-4)
        if walking {
            yaw = atan2f(-dir.x, -dir.z)
            strafe = 0
            return spec.speed
        }
        // Back to the post without turning from the fight: forward and sideways steps.
        let sp = spec.speed * min(1, dist + 0.3)
        let right = V3(cosf(yaw), 0, -sinf(yaw))
        strafe = simd_dot(dir, right) * sp
        return simd_dot(dir, forward) * sp
    }

    func collides(_ p: V3, _ w: World) -> Bool {
        let hw = halfW
        return w.collides(V3(p.x - hw, p.y, p.z - hw), V3(p.x + hw, p.y + height, p.z + hw))
    }

    func canTargetFar(_ g: Game, _ dist: Float, _ range: Float) -> Bool {
        g.survival && g.alive && dist < range
    }

    // Strolling: walk to a random standable spot 3-9 blocks away along a path (reference random stroll), instead
    // of a random heading straight into walls, fences and off ledges (behaviour sim: villagers spent most of the
    // day pushing against house walls and hopping). Falls back to a random heading when no spot is found.
    func wander() {
        if panic > 0 {
            moving = true
            wanderGoal = nil
            if aiTimer <= 0 { yaw += Rand.float(in: -1.2...1.2); aiTimer = 0.6 }
        } else if aiTimer <= 0 {
            moving.toggle()
            wanderGoal = nil
            if moving {
                if !spec.flying, let w = Mob.world, let goal = strollGoal(w, within: strollArea) { wanderGoal = goal; aiTimer = Rand.float(in: 5...9) }
                else if !spec.flying && Mob.world != nil && (kind == .villager || kind.steelhold) {
                    // Nowhere to stroll to (a closed room, a ledge): stand a while instead of walking into the walls
                    // (behaviour sim: villagers stuck in 100+ of 120 windows; Steelhold sentries on a railed roof or deck
                    // walked into the rails turning up to 115 degrees at a time: 14 spinning windows, run 417).
                    moving = false; aiTimer = Rand.float(in: 2...5)
                } else { yaw += Rand.float(in: -2...2); aiTimer = Rand.float(in: 1.5...4) }
            } else { aiTimer = Rand.float(in: 2...7) }
        }
        if moving, let goal = wanderGoal {
            let d: Float = simd_length(V2(goal.x - pos.x, goal.z - pos.z))
            // Arrived within a block: at 0.7 a mob sliding round a corner or post next to the goal could circle it
            // (behaviour sim: pigs and sheep spinning on strolls).
            if d < 1.0 || gaveUp(goal) {
                // Three strolls in a row that couldn't be walked: rest longer (behaviour sim: a cow in a pit gave up
                // 81 strolls in 120 s, pressing against the pit wall for 4 s each).
                strollFails = d < 1.0 ? 0 : strollFails + 1
                moving = false; wanderGoal = nil
                if strollFails >= 3 { strollFails = 0; aiTimer = Rand.float(in: 8...15) } else { aiTimer = Rand.float(in: 2...6) }
            } else { face(goal) }
        }
    }

    // Natural ground (stone, soil, sand, gravel, ores; not leaves): what a cave has overhead and a house doesn't.
    static let earth: [Bool] = (0..<Blocks.count).map { i in
        Blocks.opaque[i] && Blocks.fullCollide[i] && ShipParts.natural[i] && !Blocks.key(Blocks.groupBase[i]).hasSuffix("_leaves")
    }

    // Under natural ground: the first solid block over the head (up to 7 above the feet) is stone, soil and the like.
    static func underground(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Bool {
        for yy in (y + 2)...(y + 8) {
            let b = Int(w.block(x, yy, z))
            if Blocks.collide[b] || Blocks.opaque[b] { return earth[b] }
        }
        return false
    }

    func strollGoal(_ w: World, within area: (V3, Float)? = nil) -> V3? {
        var pr = PathProfile()
        pr.tall = max(1, min(3, Int(ceilf(height - 0.05))))
        pr.span = halfW > 0.5 ? 2 : 1
        pr.doors = opensDoors
        let y0 = Int(floor(pos.y + 0.01))
        // Villagers and golems don't stroll into caves: a goal with natural ground overhead is passed over (a stroll
        // a block or two down at a time led a villager 6 blocks under its village into a cave it had no way out of:
        // behaviour sim seed 777, 121 give-ups on its way to bed, run 634). One already underground strolls as before.
        let caveShy = (kind == .villager || kind == .ironGolem) && !Mob.underground(w, Int(floor(pos.x)), y0, Int(floor(pos.z)))
        for _ in 0..<6 {
            let ang: Float = Rand.float(in: 0..<(2 * .pi))
            let d: Float = Rand.float(in: 3...9)
            var x = Int(floor(pos.x + sinf(ang) * d)), z = Int(floor(pos.z + cosf(ang) * d))
            if let a = area {
                // Inside the area the schedule keeps the mob in (else it turns back at the edge every tick: spinning).
                let c = a.0
                let rr: Float = a.1 * 0.8 * Rand.float(in: 0.2...1)
                x = Int(floor(c.x + sinf(ang) * rr)); z = Int(floor(c.z + cosf(ang) * rr))
            }
            // The footprint's centre: a 2-wide mob (iron golem) stands centred on the corner of its 2x2 cells, so a
            // cell-centre goal sat 0.71 from where it could ever stand, outside the 0.7 arrival radius; it circled
            // the goal (behaviour sim: golems spinning 15 and 8 windows, every one on a stroll).
            let off: Float = pr.span == 2 ? 1 : 0.5
            // A tight area (a keeper behind the counter, a clerk at a desk: radius 3 or less) keeps to the floor of its
            // anchor: a goal a block up was the counter top, and keepers stood on their counters (CapitalTownTests).
            let tight = area.map { $0.1 <= 3 } ?? false
            let base = tight ? Int(floor(area!.0.y + 0.01)) : y0
            for dy in tight ? [0] : [0, 1, -1, 2, -2] {
                let g = V3(Float(x) + off, Float(base + dy), Float(z) + off)
                if let c = PathFinder.standCost(w, x, base + dy, z, pr), c < 5, !gaveUp(g), !(caveShy && Mob.underground(w, x, base + dy, z)) { return g }
            }
        }
        return nil
    }

    func teleport(_ w: World) {
        for _ in 0..<16 {
            let x = Int(floor(pos.x)) + Rand.int(in: -16...16), z = Int(floor(pos.z)) + Rand.int(in: -16...16)
            let top = w.topY(x, z)
            if top < 1 { continue }
            if Blocks.isLiquid(w.block(x, top, z)) { continue }
            teleportSound = true
            pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
            vel = .zero
            return
        }
    }

    // `iframes`: the reference 0.5 s after a hit in which only a bigger hit counts, and only by the difference, with no
    // knockback (player melee and arrows: fists and hoes hit 4 times a second, and all three Multishot arrows landed).
    // Off for guns, blasts and scripted hits, which have their own rates.
    func hit(from src: V3, damage: Int, knockback: Float = 1, iframes: Bool = false) {
        if kind == .warden && emergeTime > 0 { return }
        var damage = damage
        var knockback = knockback
        if iframes && damage > 0 {
            if invulnerable > 0 {
                if damage <= lastHurtAmount { return }
                let extra = damage - lastHurtAmount
                lastHurtAmount = damage
                damage = extra
                knockback = 0
            } else {
                invulnerable = 0.5
                lastHurtAmount = damage
            }
        }
        if power > 1 && damage > 0 { damage = max(1, Int((Float(damage) / power).rounded())) }
        // Ashguard armour is thinnest at the back: hits from behind a tank or half-track do 1.6x (flank them).
        if (kind == .ashTank || kind == .ashHalftrack) && damage > 0 {
            let d = V2(src.x - pos.x, src.z - pos.z)
            if simd_length(d) > 0.01 && simd_dot(simd_normalize(d), V2(forward.x, forward.z)) < -0.35 { damage = damage * 8 / 5 }
        }
        hurtSound = true
        if kind == .creaking { hurt = 0.25; return }            // only breaking its heart ends a Barkwraith
        if kind == .enderDragon {
            // Head hits land in full; hits anywhere else (body, wings, tail) at a quarter + 1, like the reference
            // game's multi-part wyrm. A perched wyrm takes off once it has lost a quarter of its health up there.
            if phase == 6 { return }
            let head = pos + forward * 5 + V3(0, 2, 0)
            let onHead = simd_length(src - head) < simd_length(src - (pos + V3(0, 2, 0)))
            let dealt = onHead ? damage : damage / 4 + min(damage, 1)
            health -= dealt
            hurt = 0.4
            if health <= 0 { health = 1; phase = 6; phaseTime = 0 }
            else if phase == 4 {
                sitDamage += dealt
                if sitDamage > spec.health / 4 { sitDamage = 0; phase = 5; phaseTime = 0 }
            }
            return
        }
        if kind == .wither {
            // Invulnerable while charging; takes hits normally otherwise and starts breaking blocks.
            if phase == 1 { return }
            health -= armorReduced(damage)              // its 4 natural armour points
            hurt = 0.4
            breakTimer = 1
            return
        }
        // A closed sentry shell shrugs off most of a hit.
        damage = armorReduced(damage)
        // Wolf armour takes the hit until it breaks; horse armour reduces like player armour.
        if kind == .wolf && armorTier == 5 && damage > 0 {
            armorHP -= damage; damage = 0
            if armorHP <= 0 { armorTier = 0 }
        }
        if kind == .horse && armorTier > 0 {
            let table: [Float] = [0, 3, 5, 7, 11, 0, 4, 19]              // ... 6 copper, 7 duskium
            let pts: Float = table[min(7, armorTier)]
            let d: Float = Float(damage)
            let cut: Float = min(20, max(pts / 5, pts - d / 2)) / 25
            damage = Int((d * (1 - cut)).rounded())
        }
        health -= kind == .shulker && peek < 0.2 ? damage / 5 : damage
        hurt = 0.4
        if kind == .shulker { aggro = true; return }
        if kind == .boat { spin += Rand.float(in: -8...8); return }
        if kind == .armorStand { return }
        if spec.behavior == .passive { panic = 5; aiTimer = 0 }
        aggro = true
        lockTime = max(lockTime, 10)
        wasHit = true
        admire = 0
        if spec.flying { vel += V3(0, 1, 0); return }
        // A hit hisser flinches: its swell drops back 0.6 s and pauses 0.4 s, so steady melee (one swing per sword
        // cooldown) can finish it before it blows (playtest v78: it went off before enough hits landed).
        if kind == .creeper && damage > 0 { fuse = max(0, fuse - 0.6); flinch = 0.4 }
        if kind == .enderman && Rand.float(in: 0..<1) < 0.5 { return }
        var away = pos - src
        away.y = 0
        let l = simd_length(away)
        away = l > 0.01 ? away / l : forward
        let kb = knockback * knockbackTaken
        vel += away * 5.5 * kb + V3(0, 5, 0) * min(1, kb)
    }

    // Ray vs AABB; returns the entry distance.
    func rayHit(_ o: V3, _ d: V3, maxDist: Float) -> Float? {
        let mn = V3(pos.x - halfW, pos.y, pos.z - halfW)
        let mx = V3(pos.x + halfW, pos.y + height, pos.z + halfW)
        guard let h = World.rayBox(o, d, mn, mx), h.0 <= maxDist else { return nil }
        return h.0
    }
}

// MARK: Models

// A model box. Rotations about `pivot`, applied X, then Z, then Y. Sign convention (model faces -Z):
// rotX > 0 swings a limb hanging down FORWARD (toward -Z) and tips a barrel lying along -Z UP; rotX = .pi / 2
// holds an arm straight out in front. (Arms "raised" with negative rotX pointed backwards: BUGS.md,
// soldier arms; --posecheck guards it.) rotY turns like the mob's yaw: > 0 swings a forward-pointing limb toward
// -X, the model's left (+X is its right).
struct Part {
    var mn: V3, mx: V3       // model-space box in pixels (1/16 block); model faces -Z
    var pivot: V3 = .zero
    var rotX: Float = 0
    var rotZ: Float = 0
    var color: V3
    var pattern: Float = 0   // 0 plain, 1 cow patches, 2 wool, 3 feathers, 4 mottled, 5 bone, 6 dress cloth,
                             // 7 enamel (glossy), 8 polished metal, 9 emissive, 10 polished leather, 11 smoked glass
    var rotY: Float = 0

    // The part's rotation (Ry * Rz * Rx) as a matrix: one set of trig per part instead of per vertex.
    var rotation: simd_float3x3 {
        let cx = cosf(rotX), sx = sinf(rotX), cz = cosf(rotZ), sz = sinf(rotZ), cy = cosf(rotY), sy = sinf(rotY)
        let rx = simd_float3x3(V3(1, 0, 0), V3(0, cx, sx), V3(0, -sx, cx))
        let rz = simd_float3x3(V3(cz, sz, 0), V3(-sz, cz, 0), V3(0, 0, 1))
        let ry = simd_float3x3(V3(cy, 0, -sy), V3(0, 1, 0), V3(sy, 0, cy))
        return ry * rz * rx
    }
    // A model-space point of this part's box after its rotation.
    func place(_ lp: V3, _ r: simd_float3x3) -> V3 { r * (lp - pivot) + pivot }
}

// A bow gripped in a hand at model x `x` (arm hanging from `pivot`, hand end at `handY`, arm turned by `rotX`). Arm-local
// -y points along the arm, so with the arm raised (rotX ~1.45) the bow's limbs (along arm-local z) stand upright in
// front of the mob, tips curving back toward it, the string on the archer's side.
func bowParts(x: Float, pivot: V3, handY: Float, rotX r: Float) -> [Part] {
    let wood = V3(0.45, 0.3, 0.14), dark = V3(0.3, 0.19, 0.09), str = V3(0.85, 0.85, 0.8)
    let g = handY - 1.2                                   // grip centre, just past the fingers
    func b(_ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float, _ c: V3, _ w: Float = 0.5) -> Part {
        Part(mn: V3(x - w, y0, z0), mx: V3(x + w, y1, z1), pivot: pivot, rotX: r, color: c)
    }
    return [
        b(g - 0.8, g + 0.8, -1.2, 1.2, dark, 0.6),          // grip wrap
        b(g - 0.5, g + 0.5, -4.5, -1.2, wood), b(g - 0.5, g + 0.5, 1.2, 4.5, wood),
        b(g + 0.2, g + 1.4, -6.5, -4.5, wood), b(g + 0.2, g + 1.4, 4.5, 6.5, wood),
        b(g + 1.2, g + 2.4, -7.5, -6.5, dark), b(g + 1.2, g + 2.4, 6.5, 7.5, dark),
        b(g + 2.0, g + 2.25, -6.8, 6.8, str, 0.12),         // string
    ]
}

func box(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float = 0) -> Part {
    Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
}

// Every box of a mob's model as drawn (body + worn equipment), for the pose check (PoseCheck.swift).
func mobModelParts(_ m: Mob) -> [Part] { parts(m) + equipmentParts(m) }

private func parts(_ m: Mob) -> [Part] {
    let swing = sinf(m.walkPhase) * 0.7 * m.walkAmount
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3, _ pat: Float = 0) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c, pattern: pat)
    }
    // A hoof / foot band over the bottom `hh` of a leg(...) with the same arguments (same pivot and swing).
    func hoof(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3, _ hh: Float = 1.5) -> Part {
        let e: Float = w / 2 + 0.15
        return Part(mn: V3(x - e, 0, z - e), mx: V3(x + e, hh, z + e), pivot: V3(x, h, z), rotX: swing * ph, color: c)
    }
    let black = V3(0.06, 0.06, 0.06)
    func eyes(_ y: Float, _ z: Float, _ sep: Float, _ size: Float = 1.2, _ c: V3 = V3(0.06, 0.06, 0.06)) -> [Part] {
        [Part(mn: V3(-sep - size, y, z - 0.2), mx: V3(-sep, y + size, z), color: c),
         Part(mn: V3(sep, y, z - 0.2), mx: V3(sep + size, y + size, z), color: c)]
    }
    switch m.kind {
    case .cow:
        let hide = [V3(0.36, 0.24, 0.16), V3(0.36, 0.24, 0.16), V3(0.6, 0.3, 0.17), V3(0.3, 0.22, 0.17)][min(3, m.variant)]
        let fv = FarmVariant.climate(m.variant)
        var extra: [Part] = []
        if fv == 2 { extra = [box(-6, 21, -13, 2, 1.5, 1.5, V3(0.9, 0.85, 0.7)), box(4, 21, -13, 2, 1.5, 1.5, V3(0.9, 0.85, 0.7))] }   // long horns
        if fv == 3 { extra = [box(-6.5, 11, -9.5, 13, 3, 19, hide * 0.85, 2), box(-4.5, 22, -14, 9, 2, 5, hide * 0.85, 2)] }          // shaggy coat
        let hoofC = V3(0.17, 0.13, 0.1)
        return extra + [
            Part(mn: V3(-6, 12, -9), mx: V3(6, 22, 9), color: hide, pattern: 1),
            Part(mn: V3(-4, 15, -15), mx: V3(4, 23, -9), pivot: V3(0, 19, -9), color: hide, pattern: 1),
            Part(mn: V3(-2.5, 15.5, -15.6), mx: V3(2.5, 18.5, -15), color: V3(0.82, 0.6, 0.55)),
            box(-5, 21, -13, 1, 3, 1, V3(0.85, 0.82, 0.72)), box(4, 21, -13, 1, 3, 1, V3(0.85, 0.82, 0.72)),
            leg(-3.5, -6, 4, 12, 1, hide, 1), leg(3.5, -6, 4, 12, -1, hide, 1),
            leg(-3.5, 6, 4, 12, -1, hide, 1), leg(3.5, 6, 4, 12, 1, hide, 1),
            box(-1.8, 16.6, -15.8, 1, 0.9, 0.2, V3(0.32, 0.18, 0.16)), box(0.8, 16.6, -15.8, 1, 0.9, 0.2, V3(0.32, 0.18, 0.16)),   // nostrils
            hoof(-3.5, -6, 4, 12, 1, hoofC), hoof(3.5, -6, 4, 12, -1, hoofC), hoof(-3.5, 6, 4, 12, -1, hoofC), hoof(3.5, 6, 4, 12, 1, hoofC),
        ] + eyes(20, -15, 1.8)
    case .sheep:
        let wc = TextureGen.hex(BlockRegistry.colorHex[m.woolColor] ?? 0xE9ECEC)
        let wool = V3(wc.x, wc.y, wc.z), skin = V3(0.72, 0.62, 0.52), hoofC = V3(0.24, 0.2, 0.17)
        var p = [
            Part(mn: V3(-3, 15, -14), mx: V3(3, 21, -7), pivot: V3(0, 18, -7), color: skin),
            leg(-3, -5, 3.5, 12, 1, skin), leg(3, -5, 3.5, 12, -1, skin),
            leg(-3, 5, 3.5, 12, -1, skin), leg(3, 5, 3.5, 12, 1, skin),
            box(-1, 15.8, -14.2, 2, 0.8, 0.2, V3(0.34, 0.25, 0.22)),                          // nose
            hoof(-3, -5, 3.5, 12, 1, hoofC), hoof(3, -5, 3.5, 12, -1, hoofC), hoof(-3, 5, 3.5, 12, -1, hoofC), hoof(3, 5, 3.5, 12, 1, hoofC),
        ] + eyes(18, -14, 1.2)
        if m.sheared { p.append(box(-4.5, 12, -7, 9, 8, 14, skin)) }
        else { p.append(box(-6, 11, -8, 12, 11, 16, wool, 2)); p.append(box(-3.5, 19.5, -12.5, 7, 2.5, 5.5, wool, 2)) }
        return p
    case .chicken:
        let white = [V3(0.95, 0.94, 0.9), V3(0.95, 0.94, 0.9), V3(0.75, 0.45, 0.24), V3(0.72, 0.76, 0.82)][min(3, m.variant)]
        let orange = V3(0.95, 0.6, 0.15)
        let flap: Float = m.onGround ? 0 : sinf(m.walkPhase * 6 + m.hurt * 30) * 0.9
        return [
            box(-3, 5, -4, 6, 6, 8, white, 3),
            Part(mn: V3(-2, 9, -7), mx: V3(2, 15, -4), pivot: V3(0, 11, -4), color: white, pattern: 3),
            box(-2, 11.5, -9, 4, 1.5, 2, orange),
            box(-1, 9.5, -8, 2, 2, 1, V3(0.85, 0.12, 0.1)),
            Part(mn: V3(-4, 6, -3), mx: V3(-3, 10, 3), pivot: V3(-3, 10, 0), rotZ: -flap, color: white, pattern: 3),
            Part(mn: V3(3, 6, -3), mx: V3(4, 10, 3), pivot: V3(3, 10, 0), rotZ: flap, color: white, pattern: 3),
            leg(-1.5, 0.5, 1, 5, 1, orange), leg(1.5, 0.5, 1, 5, -1, orange),
            // three-toed feet, swinging with the legs
            Part(mn: V3(-2.5, 0, -1), mx: V3(-0.5, 0.4, 1.2), pivot: V3(-1.5, 5, 0.5), rotX: swing, color: orange * 0.9),
            Part(mn: V3(0.5, 0, -1), mx: V3(2.5, 0.4, 1.2), pivot: V3(1.5, 5, 0.5), rotX: -swing, color: orange * 0.9),
        ] + eyes(13, -7, 1.2, 1)
    case .pig:
        let pink = [V3(0.94, 0.62, 0.6), V3(0.94, 0.62, 0.6), V3(0.56, 0.37, 0.27), V3(0.88, 0.66, 0.6)][min(3, m.variant)]
        var fluff: [Part] = []
        if FarmVariant.climate(m.variant) == 3 { fluff = [box(-5.5, 11, -8.5, 11, 3.5, 17, V3(0.95, 0.92, 0.88), 2)] }         // woolly back
        return fluff + [
            box(-5, 6, -8, 10, 8, 16, pink, 4),
            Part(mn: V3(-4, 8, -15), mx: V3(4, 16, -7), pivot: V3(0, 12, -7), color: pink, pattern: 4),
            box(-2, 9, -16, 4, 3, 1, V3(0.98, 0.72, 0.7)),
            box(-1.2, 10, -16.2, 0.8, 1, 0.3, V3(0.4, 0.2, 0.2)), box(0.4, 10, -16.2, 0.8, 1, 0.3, V3(0.4, 0.2, 0.2)),
            leg(-3, -5, 4, 6, 1, pink), leg(3, -5, 4, 6, -1, pink), leg(-3, 5, 4, 6, -1, pink), leg(3, 5, 4, 6, 1, pink),
            hoof(-3, -5, 4, 6, 1, pink * 0.55, 1.2), hoof(3, -5, 4, 6, -1, pink * 0.55, 1.2),
            hoof(-3, 5, 4, 6, -1, pink * 0.55, 1.2), hoof(3, 5, 4, 6, 1, pink * 0.55, 1.2),
        ] + eyes(13, -15, 2)
    case .wither, .snowGolem, .evoker, .vex, .ravager, .zombieVillager:
        return extraParts(m, swing: swing)
    case .rabbit, .fox, .wolf, .cat, .ocelot, .horse, .donkey, .mule, .llama, .traderLlama, .camel, .goat, .panda, .polarBear, .turtle, .frog, .tadpole,
         .armadillo, .sniffer, .mooshroom, .bee, .parrot, .bat, .allay, .axolotl, .squid, .glowSquid, .dolphin, .cod, .salmon, .tropicalFish, .pufferfish,
         .wanderingTrader, .skeletonHorse, .phantom, .guardian, .elderGuardian, .endermite, .warden, .breeze, .bogged, .zoglin, .creaking, .zombieHorse, .happyGhast, .camelHusk, .nautilus, .zombieNautilus:
        return animalParts(m, swing: swing)
    case .soldierRecruit, .soldierTrooper, .soldierMarksman, .soldierIronclad, .soldierOfficer, .soldierCrew:
        return soldierParts(m, swing: swing)
    case .deckGun:
        return deckGunParts(m)
    case .ashTank, .ashHalftrack, .ashArtillery, .ashTruck:
        return ashVehicleParts(m)
    case .ashMarshal:
        return soldierParts(m, swing: swing)
    case .copperGolem:
        return copperGolemParts(m, swing: swing)
    case .zombie, .skeleton, .enderman, .husk, .stray, .drowned, .pillager, .vindicator, .witch, .illusioner, .parched:
        let sk = m.kind == .skeleton || m.kind == .stray || m.kind == .parched, en = m.kind == .enderman
        let illager = m.kind == .pillager || m.kind == .vindicator || m.kind == .witch
        var skin = sk ? V3(0.78, 0.78, 0.76) : (en ? V3(0.08, 0.06, 0.1) : V3(0.36, 0.55, 0.3))
        var shirt = sk || en ? skin : V3(0.15, 0.55, 0.58)
        var pants = sk || en ? skin : V3(0.25, 0.25, 0.55)
        switch m.kind {
        case .husk: skin = V3(0.62, 0.55, 0.38); shirt = V3(0.55, 0.45, 0.3); pants = V3(0.42, 0.36, 0.25)
        case .stray: skin = V3(0.7, 0.76, 0.78); shirt = V3(0.45, 0.52, 0.55); pants = shirt
        case .parched: skin = V3(0.86, 0.78, 0.6); shirt = V3(0.72, 0.6, 0.42); pants = shirt
        case .drowned: skin = V3(0.3, 0.55, 0.55); shirt = V3(0.25, 0.45, 0.4); pants = V3(0.3, 0.35, 0.45)
        case .pillager: skin = V3(0.55, 0.57, 0.58); shirt = V3(0.25, 0.25, 0.3); pants = V3(0.3, 0.3, 0.32)
        case .vindicator: skin = V3(0.55, 0.57, 0.58); shirt = V3(0.2, 0.22, 0.28); pants = V3(0.15, 0.15, 0.2)
        case .witch: skin = V3(0.6, 0.55, 0.45); shirt = V3(0.3, 0.2, 0.35); pants = shirt
        case .illusioner: skin = V3(0.55, 0.57, 0.58); shirt = V3(0.2, 0.32, 0.62); pants = V3(0.16, 0.2, 0.4)
        default: break
        }
        _ = illager
        let limb: Float = sk || en ? 2 : 4
        let legH: Float = en ? 30 : 12
        let armLen: Float = en ? 30 : 12
        let bodyY = legH
        let zombieLike = m.kind == .zombie || m.kind == .husk || m.kind == .drowned
        let armFwd: Float = zombieLike || (en && m.aggro) || (m.kind == .vindicator && m.aggro) || (sk && m.aimHold > 0) ? 1.45 : 0
        let armAngle = armFwd + (armFwd == 0 ? swing : 0)
        let pat: Float = sk ? 5 : 4
        let armC = sk || en ? skin : shirt
        var p: [Part] = [
            Part(mn: V3(-limb - 0.01, 0, -limb / 2), mx: V3(-0.01, legH, limb / 2), pivot: V3(-limb / 2, legH, 0), rotX: swing, color: pants, pattern: pat),
            Part(mn: V3(0.01, 0, -limb / 2), mx: V3(limb + 0.01, legH, limb / 2), pivot: V3(limb / 2, legH, 0), rotX: -swing, color: pants, pattern: pat),
            box(-4, bodyY, -2, 8, 12, 4, shirt, pat),
            Part(mn: V3(-4 - limb, bodyY + 12 - armLen, -limb / 2), mx: V3(-4, bodyY + 12, limb / 2), pivot: V3(-4 - limb / 2, bodyY + 10, 0), rotX: armAngle, color: armC, pattern: pat),
            Part(mn: V3(4, bodyY + 12 - armLen, -limb / 2), mx: V3(4 + limb, bodyY + 12, limb / 2), pivot: V3(4 + limb / 2, bodyY + 10, 0), rotX: armFwd == 0 ? -armAngle : armAngle, color: armC, pattern: pat),
            box(-4, bodyY + 12, -4, 8, 8, 8, skin, pat),
        ]
        let hy = bodyY + 12
        if en {
            p += [box(-3, hy + 3.5, -4.2, 2.2, 1, 0.3, V3(0.85, 0.3, 0.95)), box(0.8, hy + 3.5, -4.2, 2.2, 1, 0.3, V3(0.85, 0.3, 0.95))]
            if m.carriedBlock != 0 { p.append(box(-5, bodyY + 4, -12, 10, 10, 10, Mob.carryColor(m.carriedBlock), 4)) }
        } else {
            p += eyes(hy + 3.5, -4, 1, 1.5, sk ? V3(0.15, 0.15, 0.15) : (m.kind == .drowned ? V3(0.3, 0.9, 0.9) : black))
            if zombieLike {
                // Face: sunken sockets round the eyes and a dark mouth; skin-coloured hands at the arm ends (same pivot
                // and swing as the arms), a torn shirt hem, shoes on the feet (not the barefoot drowned).
                let sock = skin * 0.55, armB = bodyY + 12 - armLen
                p += [box(-3, hy + 3, -4.1, 2.5, 2.5, 0.1, sock), box(0.5, hy + 3, -4.1, 2.5, 2.5, 0.1, sock),
                      box(-2, hy + 1, -4.15, 4, 0.8, 0.15, skin * 0.32),
                      Part(mn: V3(-4 - limb - 0.12, armB, -limb / 2 - 0.12), mx: V3(-3.9, armB + 3, limb / 2 + 0.12),
                           pivot: V3(-4 - limb / 2, bodyY + 10, 0), rotX: armAngle, color: skin, pattern: 4),
                      Part(mn: V3(3.9, armB, -limb / 2 - 0.12), mx: V3(4 + limb + 0.12, armB + 3, limb / 2 + 0.12),
                           pivot: V3(4 + limb / 2, bodyY + 10, 0), rotX: armAngle, color: skin, pattern: 4),
                      box(-3, bodyY, -2.12, 2.5, 1.4, 0.12, pants * 0.85), box(1.2, bodyY + 5.5, -2.12, 1.6, 2, 0.12, skin, 4)]
                if m.kind != .drowned {
                    let shoe = m.kind == .husk ? V3(0.3, 0.24, 0.17) : V3(0.2, 0.18, 0.21)
                    p += [Part(mn: V3(-limb - 0.13, 0, -limb / 2 - 0.13), mx: V3(-0.03, 2, limb / 2 + 0.13), pivot: V3(-limb / 2, legH, 0), rotX: swing, color: shoe),
                          Part(mn: V3(0.03, 0, -limb / 2 - 0.13), mx: V3(limb + 0.13, 2, limb / 2 + 0.13), pivot: V3(limb / 2, legH, 0), rotX: -swing, color: shoe)]
                }
            }
            if sk {
                p.append(box(-2, hy + 1, -4.1, 4, 1, 0.2, V3(0.2, 0.2, 0.2)))
                // Skull and ribcage: dark sockets and nose hole, rib bars over a dark chest cavity, a pelvis band.
                let hole = V3(0.07, 0.07, 0.07)
                p += [box(-3, hy + 3, -4.1, 2.5, 2.5, 0.1, hole), box(0.5, hy + 3, -4.1, 2.5, 2.5, 0.1, hole),
                      box(-0.5, hy + 2.2, -4.12, 1, 1, 0.12, hole),
                      box(-3, bodyY + 3.5, -2.12, 6, 7.5, 0.12, skin * 0.16),
                      box(-3.2, bodyY + 4.5, -2.3, 6.4, 1, 0.3, skin, 5), box(-3.2, bodyY + 6.7, -2.3, 6.4, 1, 0.3, skin, 5),
                      box(-3.2, bodyY + 8.9, -2.3, 6.4, 1, 0.3, skin, 5), box(-3, bodyY, -2.2, 6, 2, 0.2, skin * 0.92, 5)]
                p += bowParts(x: 4 + limb / 2, pivot: V3(4 + limb / 2, bodyY + 10, 0), handY: bodyY + 12 - armLen,
                              rotX: armFwd == 0 ? -armAngle : armAngle)
            }
            if illager { p.append(box(-1, hy + 1, -6, 2, 4, 2, skin)) }                           // nose
            if m.kind == .witch {
                p += [box(-5, hy + 8, -5, 10, 1, 10, V3(0.15, 0.1, 0.18)), box(-3, hy + 9, -3, 6, 4, 6, V3(0.15, 0.1, 0.18)),
                      box(-1.5, hy + 13, -1.5, 3, 3, 3, V3(0.15, 0.1, 0.18))]
            }
        }
        return p
    case .creeper:
        let g = V3(0.35, 0.72, 0.3)
        let pulse: Float = m.fuse > 0 ? 1 + 0.15 * sinf(m.fuse * 30) : 1
        let white = m.fuse > 0 && Int(m.fuse * 8) % 2 == 0
        let c = white ? V3(1, 1, 1) : g
        let s = pulse
        let dk = c * 0.68                                       // mottled darker patches over body and head
        return [
            box(-3 * s, 13, -2 * s - 0.1, 2, 2, 0.1, dk), box(1 * s, 9, -2 * s - 0.1, 2, 2.5, 0.1, dk),
            box(-1 * s, 14, 2 * s, 2.5, 2, 0.1, dk), box(-4 * s - 0.1, 23, -1, 0.1, 2, 2.5, dk),
            box(4 * s, 19.5, 0, 0.1, 2, 2, dk), box(-1 * s, 26, -2, 3, 0.1, 2, dk),
            box(-4 * s, 6, -2 * s, 8 * s, 12, 4 * s, c, 4),
            box(-4 * s, 18, -4 * s, 8 * s, 8, 8 * s, c, 4),
            // Hisser face (original): wide-set glowing slit eyes, zigzag hissing mouth.
            box(-4 * s, 22, -4.2 * s, 1, 1, 0.3, black), box(-3 * s, 22, -4.2 * s, 1, 1, 0.3, V3(0.95, 0.9, 0.3), 9),
            box(2 * s, 22, -4.2 * s, 1, 1, 0.3, V3(0.95, 0.9, 0.3), 9), box(3 * s, 22, -4.2 * s, 1, 1, 0.3, black),
            box(-4 * s, 20, -4.2 * s, 1, 1, 0.3, black), box(-2 * s, 20, -4.2 * s, 1, 1, 0.3, black),
            box(1 * s, 20, -4.2 * s, 1, 1, 0.3, black), box(3 * s, 20, -4.2 * s, 1, 1, 0.3, black),
            box(-3 * s, 19, -4.2 * s, 1, 1, 0.3, black), box(-1 * s, 19, -4.2 * s, 2, 1, 0.3, black), box(2 * s, 19, -4.2 * s, 1, 1, 0.3, black),
            leg(-2, -4, 4, 6, 1, c, 4), leg(2, -4, 4, 6, -1, c, 4), leg(-2, 4, 4, 6, -1, c, 4), leg(2, 4, 4, 6, 1, c, 4),
        ]
    case .spider, .caveSpider:
        let body = m.kind == .caveSpider ? V3(0.1, 0.22, 0.26) : V3(0.2, 0.17, 0.15)
        let red = V3(0.9, 0.1, 0.1)
        var p: [Part] = [
            box(-5, 4, 0, 10, 8, 12, body, 4),
            box(-3, 5, -4, 6, 6, 4, body, 4),
            box(-4, 4, -12, 8, 8, 8, body, 4),
            // Glowing eye cluster: two big eyes, a brow bar, four small ones; dark fangs below.
            box(-3, 8, -12.2, 1.5, 1.5, 0.3, red, 9), box(1.5, 8, -12.2, 1.5, 1.5, 0.3, red, 9),
            box(-1, 9.5, -12.2, 2, 1, 0.3, red, 9),
            box(-3.5, 10.2, -12.15, 1, 1, 0.15, red, 9), box(2.5, 10.2, -12.15, 1, 1, 0.15, red, 9),
            box(-2, 6.6, -12.15, 0.8, 0.8, 0.15, red, 9), box(1.2, 6.6, -12.15, 0.8, 0.8, 0.15, red, 9),
            box(-2, 4, -12.6, 1, 2, 0.6, body * 0.45), box(1, 4, -12.6, 1, 2, 0.6, body * 0.45),
        ]
        for i in 0..<4 {
            let z = -3 + Float(i) * 2
            let wiggle = sinf(m.walkPhase * 2 + Float(i)) * 0.3 * m.walkAmount
            p.append(Part(mn: V3(3, 7, z - 1), mx: V3(18, 9, z + 1), pivot: V3(3, 8, z), rotX: wiggle, rotZ: -0.5, color: body))
            p.append(Part(mn: V3(-18, 7, z - 1), mx: V3(-3, 9, z + 1), pivot: V3(-3, 8, z), rotX: -wiggle, rotZ: 0.5, color: body))
            // knee joints (same pivot and turn as the leg)
            p.append(Part(mn: V3(10, 6.7, z - 1.25), mx: V3(11.6, 9.3, z + 1.25), pivot: V3(3, 8, z), rotX: wiggle, rotZ: -0.5, color: body * 0.6))
            p.append(Part(mn: V3(-11.6, 6.7, z - 1.25), mx: V3(-10, 9.3, z + 1.25), pivot: V3(-3, 8, z), rotX: -wiggle, rotZ: 0.5, color: body * 0.6))
        }
        return p
    case .hoglin:
        let hide = V3(0.62, 0.42, 0.34), mane = V3(0.85, 0.65, 0.45)
        return [
            box(-8, 12, -12, 16, 14, 26, hide, 4),
            box(-2, 26, -12, 4, 4, 16, mane, 2),                                             // mane
            Part(mn: V3(-7, 9, -28), mx: V3(7, 21, -12), pivot: V3(0, 18, -12), rotX: 0.35, color: hide, pattern: 4),
            box(-8, 16, -27, 2, 7, 2, V3(0.95, 0.92, 0.82)), box(6, 16, -27, 2, 7, 2, V3(0.95, 0.92, 0.82)), // tusks
            box(-9, 21, -16, 2, 2, 5, hide), box(7, 21, -16, 2, 2, 5, hide),
            leg(-5, -8, 6, 12, 1, hide, 4), leg(5, -8, 6, 12, -1, hide, 4), leg(-5, 9, 6, 12, -1, hide, 4), leg(5, 9, 6, 12, 1, hide, 4),
        ] + eyes(18, -26, 3)
    case .strider:
        let red = V3(0.62, 0.16, 0.14)
        var p: [Part] = [
            box(-8, 16, -8, 16, 14, 16, red, 4),
            leg(-4, 0, 4, 16, 1, V3(0.45, 0.12, 0.1)), leg(4, 0, 4, 16, -1, V3(0.45, 0.12, 0.1)),
        ] + eyes(24, -8, 2, 2, V3(0.15, 0.05, 0.05))
        for i in 0..<6 {
            let x = -7 + Float(i) * 2.8
            p.append(Part(mn: V3(x, 30, -1), mx: V3(x + 1, 38, 1), pivot: V3(x, 30, 0), rotZ: sinf(m.walkPhase + Float(i)) * 0.3, color: V3(0.75, 0.6, 0.5)))
        }
        return p
    case .zombifiedPiglin, .piglin, .piglinBrute:
        let zp = m.kind == .zombifiedPiglin
        let skin = V3(0.93, 0.6, 0.55), rot = V3(0.45, 0.62, 0.35)
        let tunic = zp ? V3(0.55, 0.45, 0.35) : (m.kind == .piglinBrute ? V3(0.25, 0.22, 0.24) : V3(0.5, 0.33, 0.18))
        let arm = zp ? rot : skin
        let armFwd: Float = m.aggro ? 1.3 : 0
        var p: [Part] = [
            Part(mn: V3(-4.01, 0, -2), mx: V3(-0.01, 12, 2), pivot: V3(-2, 12, 0), rotX: swing, color: V3(0.35, 0.25, 0.15), pattern: 4),
            Part(mn: V3(0.01, 0, -2), mx: V3(4.01, 12, 2), pivot: V3(2, 12, 0), rotX: -swing, color: V3(0.35, 0.25, 0.15), pattern: 4),
            box(-4, 12, -2, 8, 12, 4, tunic, 4),
            Part(mn: V3(-8, 12, -2), mx: V3(-4, 24, 2), pivot: V3(-6, 22, 0), rotX: armFwd + swing, color: arm, pattern: 4),
            Part(mn: V3(4, 12, -2), mx: V3(8, 24, 2), pivot: V3(6, 22, 0), rotX: armFwd - swing, color: skin, pattern: 4),
            box(-5, 24, -4, 10, 8, 8, zp ? V3(0.85, 0.55, 0.5) : skin, 4),
            box(-2, 25, -5, 4, 3, 1, V3(0.98, 0.7, 0.65)),
            box(-1.4, 26, -5.2, 0.8, 1, 0.3, V3(0.3, 0.15, 0.15)), box(0.6, 26, -5.2, 0.8, 1, 0.3, V3(0.3, 0.15, 0.15)),
            box(-6, 27, -1, 1, 4, 3, skin), box(5, 27, -1, 1, 4, 3, skin),        // ears
            box(-3, 23.5, -5.1, 1, 1.5, 0.3, V3(0.95, 0.9, 0.8)), box(2, 23.5, -5.1, 1, 1.5, 0.3, V3(0.95, 0.9, 0.8)), // tusks
            // Golden sword in the right hand.
            Part(mn: V3(5.5, 11, -12), mx: V3(6.5, 12.5, 0), pivot: V3(6, 22, 0), rotX: armFwd - swing, color: V3(0.98, 0.84, 0.3)),
        ] + eyes(29, -4, 1, 1.5, zp ? V3(0.8, 0.8, 0.3) : black)
        if zp { p.append(box(-5.1, 27, -3, 0.3, 3, 4, V3(0.8, 0.85, 0.8), 5)) }     // exposed skull patch
        return p
    case .ghast:
        // 16px cube scaled 4x, nine tentacles; the face opens its eyes and mouth while shooting.
        let white = V3(0.94, 0.94, 0.94), grey = V3(0.55, 0.55, 0.55)
        let firing = m.attackCooldown > 2.4
        var p: [Part] = [box(-32, 16, -32, 64, 64, 64, white, 4)]
        p += [box(-20, 52, -32.4, 12, firing ? 8 : 3, 0.3, firing ? V3(0.8, 0.1, 0.1) : grey),
              box(8, 52, -32.4, 12, firing ? 8 : 3, 0.3, firing ? V3(0.8, 0.1, 0.1) : grey),
              box(-12, 30, -32.4, 24, firing ? 12 : 4, 0.3, firing ? V3(0.15, 0.15, 0.15) : grey)]
        for i in 0..<9 {
            let tx = Float(i % 3 - 1) * 20, tz = Float(i / 3 - 1) * 20
            let len: Float = 28 + Float((i * 7) % 5) * 6
            let wig = sinf(m.walkPhase * 1.3 + Float(i)) * 0.25
            p.append(Part(mn: V3(tx - 4, 16 - len, tz - 4), mx: V3(tx + 4, 16, tz + 4), pivot: V3(tx, 16, tz), rotX: wig, color: white))
        }
        return p
    case .blaze:
        let yellow = V3(1.0, 0.78, 0.2), dark = V3(0.7, 0.4, 0.05)
        var p: [Part] = [box(-4, 20, -4, 8, 8, 8, yellow, 4)]
        p += eyes(24, -4, 1, 1.5, V3(0.15, 0.08, 0.02))
        let t = m.walkPhase * 0.9
        for i in 0..<12 {
            let ring = i / 4
            let a = t * (ring == 1 ? -1 : 1) + Float(i % 4) * .pi / 2 + Float(ring) * 0.4
            let r: Float = [9, 7, 5][ring]
            let y: Float = [14, 6, -2][ring] + 2 + sinf(t * 2 + Float(i)) * 1.2
            let x = cosf(a) * r, z = sinf(a) * r
            p.append(box(x - 1, y + 2, z - 1, 2, 8, 2, i % 2 == 0 ? yellow : dark, 4))
        }
        return p
    case .witherSkeleton:
        let c = V3(0.16, 0.16, 0.17)
        let s: Float = 1.2
        func sb(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ col: V3) -> Part { box(x * s, y * s, z * s, w * s, h * s, d * s, col, 5) }
        return [
            Part(mn: V3(-2.4, 0, -1.2), mx: V3(0, 14.4, 1.2), pivot: V3(-1.2, 14.4, 0), rotX: swing, color: c, pattern: 5),
            Part(mn: V3(0, 0, -1.2), mx: V3(2.4, 14.4, 1.2), pivot: V3(1.2, 14.4, 0), rotX: -swing, color: c, pattern: 5),
            sb(-4, 12, -2, 8, 12, 4, c),
            Part(mn: V3(-7.2, 14.4, -1.2), mx: V3(-4.8, 28.8, 1.2), pivot: V3(-6, 27, 0), rotX: m.aggro ? 1.4 : swing, color: c, pattern: 5),
            Part(mn: V3(4.8, 14.4, -1.2), mx: V3(7.2, 28.8, 1.2), pivot: V3(6, 27, 0), rotX: m.aggro ? 1.4 : -swing, color: c, pattern: 5),
            // Stone sword.
            Part(mn: V3(5.5, 13, -14), mx: V3(6.5, 14.5, 0), pivot: V3(6, 27, 0), rotX: m.aggro ? 1.4 : -swing, color: V3(0.5, 0.5, 0.5)),
            sb(-4, 24, -4, 8, 8, 8, c),
            sb(-2.5, 27.5, -4.1, 1.5, 1.5, 0.2, V3(0.02, 0.02, 0.02)), sb(1, 27.5, -4.1, 1.5, 1.5, 0.2, V3(0.02, 0.02, 0.02)),
        ]
    case .enderDragon:
        // ~9 blocks nose to tail, 12-block wingspan; wings flap, neck and tail sway.
        let hide = V3(0.1, 0.09, 0.12), belly = V3(0.2, 0.17, 0.22), purple = V3(0.85, 0.35, 1.0)
        let flap = sinf(m.walkPhase * 1.6) * (m.phase == 4 ? 0.15 : 0.7)
        var p: [Part] = [box(-12, 24, -32, 24, 24, 64, hide, 4), box(-10, 22, -30, 20, 2, 60, belly, 4)]
        for i in 0..<5 {
            let z = -32 - Float(i + 1) * 10, y = 34 + Float(i) * 2 + sinf(m.walkPhase + Float(i) * 0.6) * 1.5
            p.append(box(-5, y, z, 10, 10, 10, hide, 4))
            p.append(box(-1, y + 10, z + 3, 2, 3, 4, belly))
        }
        let hy: Float = 44 + sinf(m.walkPhase + 3) * 1.5, hz: Float = -82
        p += [box(-8, hy, hz - 16, 16, 16, 16, hide, 4),
              box(-6, hy - 4, hz - 32, 12, 5, 16, hide, 4),                 // lower jaw
              box(-6, hy + 1, hz - 32, 12, 5, 16, hide, 4),                 // upper jaw
              box(-6, hy + 9, hz - 12, 3, 2, 1, purple), box(3, hy + 9, hz - 12, 3, 2, 1, purple),
              box(-6, hy + 16, hz - 8, 2, 4, 6, belly), box(4, hy + 16, hz - 8, 2, 4, 6, belly)]
        for i in 0..<12 {
            let z = 32 + Float(i) * 10, y = 32 + sinf(m.walkPhase * 0.8 + Float(i) * 0.5) * Float(i) * 0.6
            p.append(box(-5, y, z, 10, 10, 10, hide, 4))
            if i % 2 == 0 { p.append(box(-1, y + 10, z + 3, 2, 3, 4, belly)) }
        }
        for side: Float in [-1, 1] {
            let pivot = V3(side * 12, 44, -20)
            p.append(Part(mn: side < 0 ? V3(-68, 42, -24) : V3(12, 42, -24), mx: side < 0 ? V3(-12, 46, -16) : V3(68, 46, -16),
                          pivot: pivot, rotZ: side * flap, color: hide, pattern: 4))
            p.append(Part(mn: side < 0 ? V3(-68, 43, -16) : V3(12, 43, -16), mx: side < 0 ? V3(-12, 44, 36) : V3(68, 44, 36),
                          pivot: pivot, rotZ: side * flap, color: V3(0.16, 0.13, 0.2), pattern: 4))
            p.append(leg(side * 10, -20, 6, 24, 0.3, hide, 4))
            p.append(leg(side * 12, 20, 8, 26, -0.3, hide, 4))
        }
        return p
    case .endCrystal:
        // Spinning glass cubes around a core over a bedrock base.
        let spin = m.walkPhase
        let bob = sinf(spin * 1.5) * 3
        return [
            box(-6, 0, -6, 12, 4, 12, V3(0.25, 0.25, 0.25), 4),
            Part(mn: V3(-8, 12 + bob, -8), mx: V3(8, 28 + bob, 8), pivot: V3(0, 20 + bob, 0), rotX: spin, rotZ: spin * 0.7, color: V3(0.75, 0.6, 0.95)),
            Part(mn: V3(-6, 14 + bob, -6), mx: V3(6, 26 + bob, 6), pivot: V3(0, 20 + bob, 0), rotX: -spin * 1.3, rotZ: spin, color: V3(0.9, 0.8, 1.0)),
            Part(mn: V3(-3.5, 16.5 + bob, -3.5), mx: V3(3.5, 23.5 + bob, 3.5), pivot: V3(0, 20 + bob, 0), rotX: spin * 2, color: V3(1.0, 0.45, 0.85)),
        ]
    case .shulker:
        let shell = V3(0.58, 0.4, 0.62), head = V3(0.93, 0.88, 0.62)
        let lift = m.peek * 8
        return [
            box(-8, 0, -8, 16, 8, 16, shell, 4),
            box(-8, 8 + lift, -8, 16, 8, 16, shell, 4),
            box(-3, 6, -3, 6, 6 + lift, 6, head),
            box(-2, 8 + lift * 0.6, -3.2, 1.2, 1.2, 0.2, V3(0.1, 0.1, 0.1)), box(0.8, 8 + lift * 0.6, -3.2, 1.2, 1.2, 0.2, V3(0.1, 0.1, 0.1)),
        ]
    case .boat:
        return boatParts(m)
    case .armorStand:
        return armorStandParts(m)
    case .minecart:
        let iron = V3(0.55, 0.56, 0.6), dark = V3(0.3, 0.3, 0.33)
        return [
            box(-10, 2, -7, 20, 2, 14, dark, 4),
            box(-10, 4, -8, 20, 7, 1, iron, 4), box(-10, 4, 7, 20, 7, 1, iron, 4),
            box(-11, 4, -8, 1, 7, 16, iron, 4), box(10, 4, -8, 1, 7, 16, iron, 4),
            box(-8, 0, -7, 3, 2, 1, dark), box(5, 0, -7, 3, 2, 1, dark), box(-8, 0, 6, 3, 2, 1, dark), box(5, 0, 6, 3, 2, 1, dark),
        ] + cartTop(m)
    case .villager:
        // Townsfolk: jointed people dressed for their trade, carrying their tool or weapon (TownsfolkModel.swift).
        return townsfolkParts(m, swing: swing)
    case .ironGolem:
        let iron = V3(0.82, 0.8, 0.76), vine = V3(0.3, 0.55, 0.2)
        let armSwing = m.attackCooldown > 0.9 ? 1.4 : swing * 0.5
        return [
            Part(mn: V3(-7, 0, -3), mx: V3(-1, 16, 3), pivot: V3(-4, 16, 0), rotX: swing, color: iron, pattern: 4),
            Part(mn: V3(1, 0, -3), mx: V3(7, 16, 3), pivot: V3(4, 16, 0), rotX: -swing, color: iron, pattern: 4),
            box(-9, 16, -6, 18, 12, 11, iron, 4),
            box(-4.5, 28, -2.5, 9, 5, 5, iron, 4),
            Part(mn: V3(-13, 5, -3), mx: V3(-9, 33, 3), pivot: V3(-11, 32, 0), rotX: armSwing, color: iron, pattern: 4),
            Part(mn: V3(9, 5, -3), mx: V3(13, 33, 3), pivot: V3(11, 32, 0), rotX: m.attackCooldown > 0.9 ? armSwing : -armSwing, color: iron, pattern: 4),     // both arms up to strike
            box(-4, 33, -7.5, 8, 10, 8, iron, 4),
            box(-1, 34, -9.5, 2, 4, 2, iron),
            box(-9.2, 18, -4, 0.4, 6, 3, vine), box(5, 26, -6.2, 3, 4, 0.3, vine),
        ] + eyes(38, -7.5, 1, 1.4, V3(0.7, 0.15, 0.1))
    case .silverfish:
        let c = V3(0.55, 0.57, 0.62)
        var p: [Part] = []
        for i in 0..<5 {
            let w: Float = [3, 4, 6, 4, 2][i], z = -4 + Float(i) * 2.5
            let wob = sinf(m.walkPhase * 3 + Float(i)) * 0.6
            p.append(box(-w / 2 + wob, 0, z, w, w * 0.7, 2.5, c, 4))
        }
        return p
    case .slime, .magmaCube:
        if m.kind == .magmaCube {
            let s = Float(m.slimeSize) * 8
            let stretch: Float = m.onGround ? 1 : 1.35
            var p: [Part] = []
            // Stacked slices that spread apart mid-jump; glowing core.
            for i in 0..<4 {
                let y0 = Float(i) * s / 4 * stretch
                p.append(box(-s / 2, y0, -s / 2, s, s / 4, s, i % 2 == 0 ? V3(0.35, 0.08, 0.05) : V3(0.5, 0.12, 0.05), 4))
            }
            p.append(box(-s * 0.3, s * 0.25, -s * 0.3, s * 0.6, s * 0.5 * stretch, s * 0.6, V3(1, 0.55, 0.1)))
            p += [box(-s * 0.32, s * 0.55 * stretch, -s / 2 - 0.1, s * 0.18, s * 0.12, 0.2, V3(1, 0.8, 0.2)),
                  box(s * 0.14, s * 0.55 * stretch, -s / 2 - 0.1, s * 0.18, s * 0.12, 0.2, V3(1, 0.8, 0.2))]
            return p
        }
        let s = Float(m.slimeSize) * 8
        let squash: Float = m.onGround ? 1 : 1.15
        return [
            box(-s / 2, 0, -s / 2, s, s * squash, s, V3(0.45, 0.8, 0.4), 2),
            box(-s * 0.3, s * 0.55, -s / 2 - 0.1, s * 0.15, s * 0.15, 0.2, V3(0.1, 0.2, 0.1)),
            box(s * 0.15, s * 0.55, -s / 2 - 0.1, s * 0.15, s * 0.15, 0.2, V3(0.1, 0.2, 0.1)),
        ]
    }
}

// Writes the mob triangles (camera-relative) into `out`; returns the vertex count written.
enum MobLight {
    static var nightVision: Float = 0
    // The cave fill's level this frame (Shaders.caveFill: 0.06 + 0.3 x Brightness, doubled in Fast), for mobs, dropped
    // items and the held item, which are lit on the CPU.
    static var fill: Float = 0.21
}

// Last frame's mob drawing, for the F3 overlay and voice bug notes (playtest 2026-10-05: mobs invisible in real play,
// never in the CI renderer): how many mobs, how many near, vertices written and drawn, and which path drew them.
enum MobDrawStats {
    static var mobs = 0, near = 0, written = 0, drawn = 0, culled = 0, dropped = 0
    static var path = "none"
    static var line: String {
        "mobs \(mobs) (\(near) within 32), \(written) vertices written, \(drawn) drawn via \(path), \(culled) culled, \(dropped) dropped (buffer full)"
    }
}

// Mobs in drawing order, nearest first (reused storage: no per-frame allocation once warm).
enum MobOrder { static var list: [Mob] = [] }

func writeMobVertices(_ mobs: [Mob], eye: V3, daylight: Float, world: World,
                      into out: UnsafeMutablePointer<MobVert>, capacity: Int, cull: Frustum? = nil,
                      maxDist: Float = .greatestFiniteMagnitude) -> Int {
    let CT = Mesher.cornerTable
    let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
    let order = [0, 1, 2, 0, 2, 3]
    var n = 0
    SoldierRig.eye = eye                    // soldier level of detail by distance
    // Dimension ambient, lifted by night vision like the terrain (Renderer: 1 - (1 - dim) * (1 - 0.85 nv)).
    let amb: Float = 1 - (1 - world.dim.ambient) * (1 - 0.85 * MobLight.nightVision)
    // Nearest first, and nothing past the fog: the buffer holds ~2400 model parts, and with the hundreds of mobs loaded
    // at render distance 16-24 (a citadel's jointed soldiers alone) it filled before the mobs beside the player, who
    // were then never drawn (playtest 2026-10-05: mobs invisible in game; the harness never loads that many).
    var list = MobOrder.list
    MobOrder.list = []                       // taken out while filled: the only reference, so no copy on write
    list.removeAll(keepingCapacity: true)
    let maxD2 = maxDist * maxDist
    for ring in 0..<3 {
        let lo: Float = ring == 0 ? -1 : (ring == 1 ? 24 * 24 : 80 * 80)
        let hi: Float = ring == 0 ? 24 * 24 : (ring == 1 ? 80 * 80 : maxD2)
        for m in mobs {
            let dx = m.pos.x - eye.x, dz = m.pos.z - eye.z
            let d2 = dx * dx + dz * dz
            if d2 > lo && d2 <= hi { list.append(m) }
        }
    }
    defer { MobOrder.list = list }
    for (idx, m) in list.enumerated() {
        // Out of view and over 64 blocks away (nearer ones can still throw a shadow into view): skipped. Every mob in
        // the loaded area was rebuilt each frame (a quarter of the frame's CPU encode in the flight profile).
        if let fr = cull {
            let dx = m.pos.x - eye.x, dz = m.pos.z - eye.z
            if dx * dx + dz * dz > 64 * 64 {
                let r: Float = 3 + 2 * m.height
                if !fr.visible(min: m.pos - V3(r, r, r), max: m.pos + V3(r, r + m.height, r)) { MobDrawStats.culled += 1; continue }
            }
        }
        let l = world.lightAt(Int(floor(m.pos.x)), Int(floor(m.pos.y + m.height * 0.5)), Int(floor(m.pos.z)))
        let base = m.pos + V3(0, m.viewDY, 0) - eye
        // The cave fill (Shaders.caveFill): mobs in the dark stay visible a few blocks away.
        let near: Float = 1 - 0.55 * Terrain.smooth(5, 30, simd_length(base))
        let fill: Float = max(0.04, MobLight.fill * near)
        var bright = max(fill, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
        bright = bright + (1 - bright) * amb
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        let tint = m.hurt > 0 ? V3(1, 0.45, 0.45) : (m.fire > 0 ? V3(1, 0.7, 0.4) : V3(1, 1, 1))
        let scale: Float = m.sized ? 1 : m.scale
        let glow = m.kind == .blaze || m.kind == .magmaCube || m.kind == .ghast || m.kind == .endCrystal
        let lit = glow ? max(bright, 0.85) : bright
        let body = parts(m), worn = equipmentParts(m)          // walked in turn: no concatenated array per mob per frame
        let lie = m.lying
        // Far detail: past 64 blocks a part under 1.2/16 of a block across (eyes, noses, buttons) is about a pixel on a
        // 1080p screen but costs 36 vertices; soldiers have their own levels of detail (SoldierRig).
        let far = !m.kind.steelhold && simd_length_squared(base) > 64 * 64
        let tiny: Float = 1.2 / max(0.25, scale)
        for pi in 0..<(body.count + worn.count) {
            let p = pi < body.count ? body[pi] : worn[pi - body.count]
            if n + 36 > capacity { MobDrawStats.dropped += list.count - idx; return n }
            let size = p.mx - p.mn
            if far && max(size.x, max(size.y, size.z)) < tiny { continue }
            let rot = p.rotation
            for f in 0..<6 {
                for k in order {
                    let ci = (f * 4 + k) * 3
                    let lp = p.mn + size * V3(Float(CT[ci]), Float(CT[ci + 1]), Float(CT[ci + 2]))
                    var q = p.place(lp, rot)
                    if lie { q = V3(q.x, 4 - q.z, q.y) }          // on its back: model up runs toward the pillow
                    // Cheap ambient occlusion: darker toward the feet (x0.72 at model y 0, full by y 10) and at each
                    // box's lower end, so legs and bellies read as shaded rather than flat-lit.
                    let t = min(1, max(0, q.y * 0.1))
                    let ground: Float = glow ? 1 : 0.72 + 0.28 * t * t * (3 - 2 * t)
                    let ao = ground * (CT[ci + 1] == 0 ? 0.9 : 1)
                    q *= scale / 16
                    let r = V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z) + base
                    out[n] = MobVert(pos: V4(r, p.pattern), color: V4(p.color * tint, faceShade[f] * lit * ao), local: V4(lp, 0))
                    n += 1
                }
            }
        }
    }
    return n
}

// MARK: Manager

final class MobManager {
    var mobs: [Mob] = []
    var stored: [ChunkKey: [MobRecord]] = [:]     // mobs outside the loaded area (see MobSave.swift)
    private var restoreTimer: Float = 0
    static let passiveCap = 10
    static let hostileCap = 70
    var passiveTimer: Float = 2
    var hostileTimer: Float = 1
    var populateTimer: Float = 0.5
    var hives: [IVec3: [(nectar: Bool, time: Float)]] = [:]   // bees inside nests / hives (Bees.swift)
    var hiveTimer: Float = 0                      // hives are checked twice a second (Bees.swift)
    static var quarantined = 0                    // mobs whose update produced NaN (reported by smoke / agent oracles)
    var phantomTimer: Float = 60                  // seconds to the next nightwing check (Spawning.swift)
    var populated = Set<ChunkKey>()               // chunks that already had their generation-time animals (Spawning.swift)
    // Live mobs by kind, rebuilt at the start of every update (reused storage: no per-tick allocation).
    private(set) var kindIndex: [[Mob]] = Array(repeating: [], count: MobKind.allCases.count)
    func of(_ k: MobKind) -> [Mob] { kindIndex[k.rawValue] }
    func rebuildIndex() {
        for i in kindIndex.indices { kindIndex[i].removeAll(keepingCapacity: true) }
        for m in mobs where m.health > 0 { kindIndex[m.kind.rawValue].append(m) }
    }
    static let breedFood: [MobKind: [String]] = [
        .cow: ["wheat"], .sheep: ["wheat"], .pig: ["carrot", "potato", "beetroot"], .chicken: ["wheat_seeds", "beetroot_seeds", "melon_seeds", "pumpkin_seeds", "torchflower_seeds", "pitcher_pod"],
        .hoglin: ["crimson_fungus"], .strider: ["warped_fungus"],
    ]

    // Per-block-state tables the mob AI builds lazily (string tests over every state, 3-5 ms each): built at load,
    // not by the first villager that looks for a bed in the middle of play (Quest bench, village and forest routes).
    static func warmTables() {
        _ = PathFinder.doorTable.count; _ = PathFinder.woodDoorTable.count; _ = PathFinder.climbIds.count
        _ = Mob.earth.count; _ = VillageLife.bedHead.count; _ = Villagers.jobSiteOf.count
    }

    func update(_ dt: Float, game: Game) {
        Mob.world = game.world
        PathFinder.budget = 4
        PathFinder.spent = 0
        let w = game.world
        let p = game.player.pos
        rebuildIndex()
        Mob.hardMode = game.difficulty == 3
        let second = game.coop.current > 0          // split screen: a second seat updates only the mobs nearest it
        if !second { hiveTick(dt, game) }
        for m in mobs where game.seatOwns(m.pos) {
            let before = m.pos, wasGround = m.onGround
            m.update(dt, game: game)
            m.easeStep(fromY: before.y, wasGround: wasGround, dt)
            // NaN quarantine: a non-finite position, velocity or facing reaches Int(floor(...)) in the chunk and unload
            // checks (undefined in the -Ounchecked build) and makes the mob save fail as a whole. Put it back where it was.
            let sane: Bool = m.pos.x.isFinite && m.pos.y.isFinite && m.pos.z.isFinite && m.vel.x.isFinite && m.vel.y.isFinite && m.vel.z.isFinite
            if !sane || !m.yaw.isFinite {
                MobManager.quarantined += 1
                if MobManager.quarantined <= 5 { print("mob NaN quarantine: \(m.kind.key) at \(before) (\(MobManager.quarantined) so far)") }
                m.pos = before.x.isFinite && before.y.isFinite && before.z.isFinite ? before : p
                m.vel = .zero
                if !m.yaw.isFinite { m.yaw = 0 }
            }
            // Footsteps for walking mobs near the listener (size sets the stride and loudness).
            let dxm = m.pos.x - before.x, dzm = m.pos.z - before.z
            if game.sound != nil && m.onGround && dxm * dxm + dzm * dzm > 1e-6 && simd_length_squared(m.pos - p) < 256 {
                let sp = MobVoice.stepInfo[m.kind.rawValue]
                let moved: Float = sqrtf(dxm * dxm + dzm * dzm)
                if moved < 1 && sp.walks { m.stepAcc += moved }
                let stride: Float = sp.stride
                if m.stepAcc > stride {
                    m.stepAcc = 0
                    do {
                        let under = w.block(Int(floor(m.pos.x)), Int(floor(m.pos.y - 0.2)), Int(floor(m.pos.z)))
                        if under != AIR {
                            let vol: Float = sp.volume * (m.baby ? 0.5 : 1)
                            if let r = Soldier.rank(m.kind) { game.sfx(.soldierStep(Soldier.voice(r)), vol + 0.15, at: m.pos) }
                            else { game.sfx(.step(soundMat(under)), vol, at: m.pos) }
                        }
                    }
                }
            }
            if m.teleportSound {
                m.teleportSound = false
                game.sfx(.teleport, 0.9, at: before + V3(0, 1, 0))
                game.sfx(.teleport, 0.9, at: m.pos + V3(0, 1, 0))
            }
            if m.hurtSound {
                m.hurtSound = false
                if MobVoice.profile(m.kind).family != .silent { game.sfx(m.baby ? .babyMob(m.kind, .hurt) : .mob(m.kind, .hurt), 0.8, at: m.pos + V3(0, m.height * 0.8, 0)) }
            }
            if m.callTimer <= 0 {
                m.callTimer = Rand.float(in: 8...24)
                if let r = Soldier.rank(m.kind) {
                    // Soldiers chatter at ease and shout orders in a fight (more often while fighting).
                    if m.aggro { m.callTimer = Rand.float(in: 4...9) }
                    game.sfx(.soldier(Soldier.voice(r), m.aggro ? (Rand.float(in: 0..<1) < 0.25 ? .retreat : .attack) : .idle), m.aggro ? 1 : 0.6, at: m.pos + V3(0, m.height * 0.8, 0))
                } else if MobVoice.profile(m.kind).family != .silent {
                    // Hissers and magma cubes only rustle / squelch faintly; everyone else calls at the usual level.
                    let quiet: Bool = m.kind == .creeper || m.kind == .magmaCube
                    let vol: Float = quiet ? 0.25 : (m.baby ? 0.45 : 0.6)
                    game.sfx(m.baby ? .babyMob(m.kind, .ambient) : .mob(m.kind, .ambient), vol, at: m.pos + V3(0, m.height * 0.8, 0))
                }
            }
        }
        if second { spawnTick(dt, game); return }
        // Breeding: two mobs of a kind in love next to each other make a baby.
        var babies: [Mob] = []
        for a in mobs where a.inLove > 0 {
            if let b = mobs.first(where: { $0 !== a && a.breedsWith($0) && $0.inLove > 0 && simd_length($0.pos - a.pos) < 1.5 }) {
                a.inLove = 0; b.inLove = 0
                a.breedCooldown = 300; b.breedCooldown = 300
                game.achieve("breed")
                game.addXP(Rand.int(in: 1...7))
                game.particles.hearts(at: (a.pos + b.pos) * 0.5 + V3(0, 0.8, 0))
                // Egg layers (reference): turtles lay on their home beach, frogs lay spawn on water, snufflers an egg.
                if a.kind == .turtle || a.kind == .frog || a.kind == .sniffer { a.hasEgg = true; continue }
                let baby = Mob(a.kind != b.kind ? .mule : a.kind, at: (a.pos + b.pos) * 0.5)
                baby.baby = true
                baby.scale = 0.5
                baby.inheritFrom(a, b)
                babies.append(baby)
            }
        }
        mobs += babies
        // The wyrm never just vanishes: however its health ran out (potions, /kill, explosions) it plays its death
        // sequence, which opens the exit portal (Hollow.swift).
        for m in mobs where m.kind == .enderDragon && m.health <= 0 && m.health > -1000 { m.health = 1; m.phase = 6; m.phaseTime = 0 }
        // Deaths: loot + XP, slime splitting.
        var spawned: [Mob] = []
        for m in mobs where m.health <= 0 {
            if m.sized && m.slimeSize > 1 {
                for _ in 0..<Rand.int(in: 2...4) {
                    let s = Mob(m.kind, at: m.pos + V3(Rand.float(in: -0.4...0.4), 0.2, Rand.float(in: -0.4...0.4)))
                    s.makeSlime(size: m.slimeSize / 2)
                    spawned.append(s)
                }
            }
            if m.health > -1000 { game.mobDied(m) }
        }
        let limit = Float((w.renderDistance + 1) * CS)
        mobs.removeAll { m in
            if m.health <= 0 { return true }
            // Riders of a ship still in play stay with it, however far its hull reaches from the player (a frigate's bow
            // crew were stashed with their unloaded chunk and came back hundreds of blocks behind it: ride check).
            if let dk = m.deck, w.ships.list.contains(where: { $0 === dk }) { return false }
            // A position made non-finite outside this seat's update (another seat's knockback) can't be turned into a
            // chunk: the mob goes (its update would put it back, but Int(floor(NaN)) below is undefined).
            guard m.pos.x.isFinite && m.pos.y.isFinite && m.pos.z.isFinite else { MobManager.quarantined += 1; return true }
            let pn = game.coop.active ? game.coop.nearestPlayerPos(m.pos, game) : p
            if abs(m.pos.x - pn.x) > limit || abs(m.pos.z - pn.z) > limit || !w.isLoaded(Int(floor(m.pos.x)), Int(floor(m.pos.z))) {
                if m.keepOnUnload { stash(m) }
                return true
            }
            return shouldDespawn(m, simd_length(m.pos - pn), dt, game)      // 3D, as the reference (a mob far below stayed)
        }
        mobs += spawned
        restoreTimer -= dt
        if restoreTimer <= 0 {
            restoreTimer = 1
            // Round every player (split screen: stashed villagers near player 2 came back only when player 1 went there).
            for i in 0..<max(1, game.coop.seatCount) { restore(w, center: game.coop.seatPlayer(i, game).pos, limit: limit) }
        }
        spawnTick(dt, game)
    }

    // Surface y (feet) at a column if it's grass with two free blocks above, else nil.
    // Highest solid-or-liquid block in a column (from CH - 2 down; 1 if none). Reads the chunk's array once instead of
    // two world lookups per y: animal packs probing up to 24 columns cost 7-25 ms ticks at spawn (--sim 60 profile).
    static func surfaceScan(_ w: World, _ x: Int, _ z: Int) -> Int {
        guard w.frame == nil, let c = w.chunkAt(x, z) else {
            var y = CH - 2
            while y > 1 && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.isLiquid(w.block(x, y, z)) { y -= 1 }
            return y
        }
        let lx = mod(x, CS), lz = mod(z, CS)
        let collide = Blocks.collide
        var y = CH - 2
        while y > 1 {
            let b = c.blocks[Chunk.index(lx, y, lz)]
            if collide[Int(b)] || Blocks.isLiquid(b) { break }
            y -= 1
        }
        return y
    }

    func grassSurface(_ w: World, _ x: Int, _ z: Int) -> Int? {
        let y = MobManager.surfaceScan(w, x, z)
        guard w.block(x, y, z) == GRASS else { return nil }
        let a = w.block(x, y + 1, z), b = w.block(x, y + 2, z)
        guard !Blocks.collide[Int(a)] && !Blocks.collide[Int(b)] && !Blocks.isLiquid(a) else { return nil }
        return y + 1
    }

    // Reference spawn weights per biome (creature category).
    static func pickAnimal(_ b: Biome) -> (MobKind, Int, Int)? {
        let std: [(MobKind, Int, Int, Int)] = [(.sheep, 12, 4, 4), (.pig, 10, 4, 4), (.chicken, 10, 4, 4), (.cow, 8, 4, 4)]
        var t: [(MobKind, Int, Int, Int)]
        switch b {
        case .plains, .sunflowerPlains: t = std + [(.horse, 5, 2, 6), (.donkey, 1, 1, 3)]
        case .forest, .flowerForest, .birchForest, .oldGrowthBirchForest, .darkForest: t = std + (b == .forest ? [(.wolf, 5, 4, 4)] : []) + (b == .flowerForest ? [(.rabbit, 4, 2, 3)] : [])
        case .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga: t = std + [(.wolf, 8, 4, 4), (.rabbit, 4, 2, 3), (.fox, 8, 2, 4)]
        case .snowyTaiga: t = [(.wolf, 8, 4, 4), (.rabbit, 4, 2, 3), (.fox, 8, 2, 4)]
        case .snowyPlains, .iceSpikes: t = [(.rabbit, 10, 2, 3), (.polarBear, 1, 1, 2)]
        case .snowySlopes, .jaggedPeaks, .frozenPeaks: t = [(.goat, 5, 1, 3)]
        case .grove: t = [(.wolf, 1, 1, 1), (.rabbit, 8, 2, 3), (.fox, 4, 2, 4)]
        case .meadow: t = [(.donkey, 1, 1, 2), (.rabbit, 2, 2, 6), (.sheep, 2, 2, 4)]
        case .cherryGrove: t = [(.pig, 1, 1, 2), (.rabbit, 2, 2, 6), (.sheep, 2, 2, 4)]
        case .desert: t = [(.rabbit, 4, 2, 3)]
        case .savanna, .savannaPlateau: t = std + [(.horse, 1, 2, 6), (.donkey, 1, 1, 1), (.armadillo, 10, 2, 3)] + (b == .savannaPlateau ? [(.llama, 8, 4, 4), (.wolf, 8, 4, 8)] : [])
        case .windsweptSavanna: t = std + [(.horse, 1, 2, 6), (.donkey, 1, 1, 1), (.armadillo, 10, 2, 3)]
        case .windsweptHills, .windsweptGravellyHills, .windsweptForest: t = std + [(.llama, 5, 4, 6)]
        case .jungle, .sparseJungle: t = std + [(.parrot, 40, 1, 2), (.ocelot, 2, 1, 3)] + (b == .jungle ? [(.panda, 1, 1, 2)] : [(.wolf, 8, 2, 4)])
        case .bambooJungle: t = std + [(.parrot, 40, 1, 2), (.panda, 80, 1, 2), (.ocelot, 2, 1, 1)]
        case .swamp: t = std + [(.frog, 10, 2, 5)]
        case .mangroveSwamp: t = [(.frog, 10, 2, 5)]
        case .mushroomFields: t = [(.mooshroom, 8, 4, 8)]
        case .beach: t = [(.turtle, 5, 2, 5)]
        case .badlands, .woodedBadlands, .erodedBadlands: t = [(.armadillo, 6, 1, 2)] + (b == .woodedBadlands ? [(.wolf, 2, 4, 8)] : [])
        default: return nil
        }
        let total = t.reduce(0) { $0 + $1.1 }
        var r = Rand.int(in: 0..<max(1, total))
        for e in t { r -= e.1; if r < 0 { return (e.0, e.2, e.3) } }
        return nil
    }

    // Grass-like ground with room above (sand for turtles/rabbits, snow for bears, mycelium for mushroom cows).
    func animalSurface(_ w: World, _ x: Int, _ z: Int, _ k: MobKind) -> Int? {
        let y = MobManager.surfaceScan(w, x, z)
        let g = Blocks.key(w.block(x, y, z))
        let ok: Bool
        switch k {
        case .turtle: ok = g == "sand"
        case .mooshroom: ok = g == "mycelium"
        case .rabbit, .polarBear, .goat, .fox, .wolf, .armadillo, .camel: ok = ["grass_block", "snowy_grass_block", "sand", "red_sand", "snow_block", "snow", "stone", "podzol", "coarse_dirt", "terracotta", "packed_ice", "ice", "powder_snow"].contains(g) || g.hasSuffix("_terracotta")
        case .frog: ok = ["grass_block", "mud", "mangrove_roots", "muddy_mangrove_roots"].contains(g)
        case .parrot, .panda, .ocelot: ok = ["grass_block", "podzol"].contains(g) || g.hasSuffix("_leaves")
        default: ok = g == "grass_block" || g == "snowy_grass_block"
        }
        guard ok else { return nil }
        let a = w.block(x, y + 1, z), b = w.block(x, y + 2, z)
        guard !Blocks.collide[Int(a)] && !Blocks.collide[Int(b)] && !Blocks.isLiquid(a) else { return nil }
        return y + 1
    }

    // Emberdeep spawning (no light requirement): per-biome weighted lists, overridden inside fortresses.
    func trySpawnEmberdeep(_ game: Game, base: Int = YOFF) {
        let w = game.world
        let pp = game.player.pos
        let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 24...64)
        let x = Int(floor(pp.x + cosf(a) * r)), z = Int(floor(pp.z + sinf(a) * r))
        guard w.isLoaded(x, z) else { return }
        // Magmastriders: groups on the lava sea surface.
        let lavaY = base + EmberGen.lavaLevel
        if Rand.float(in: 0..<1) < 0.1 {
            if Blocks.fluidKind[Int(w.block(x, lavaY, z))] == 2 && w.block(x, lavaY + 1, z) == AIR && w.block(x, lavaY + 2, z) == AIR
                && mobs.filter({ $0.kind == .strider }).count < 8 {
                for i in 0..<Rand.int(in: 1...2) {
                    let st = Mob(.strider, at: V3(Float(x + i) + 0.5, Float(lavaY + 1), Float(z) + 0.5))
                    mobs.append(st)
                    // Reference jockeys: 1 in 30 carry an undead boarling, otherwise 1 in 10 a young magmastrider.
                    let riderKind: MobKind? = Rand.int(in: 0..<30) == 0 ? .zombifiedPiglin : (Rand.int(in: 0..<10) == 0 ? .strider : nil)
                    if let rk = riderKind {
                        let r = Mob(rk, at: st.pos + V3(0, st.height, 0))
                        if rk == .strider { r.baby = true; r.scale = 0.5 }
                        r.mount = st; r.jockey = true
                        mobs.append(r)
                    }
                }
            }
            return
        }
        var y = base + Rand.int(in: 1...126)
        // Walk down to a floor with two free blocks above it.
        while y > base + 1 && !(Blocks.opaque[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))]
                                 && !Blocks.collide[Int(w.block(x, y + 1, z))]) { y -= 1 }
        if y <= base + 1 || Blocks.isLiquid(w.block(x, y, z)) || w.block(x, y - 1, z) == BEDROCK { return }
        let spawnPos = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
        if simd_length(spawnPos - pp) < 24 { return }
        typealias Entry = (MobKind, Int, Int, Int)      // kind, weight, min group, max group
        var list: [Entry]
        if w.gen.structures?.structure(at: x, y, z, kind: "fortress") != nil && Blocks.key(w.block(x, y - 1, z)) == "nether_bricks" {
            list = [(.blaze, 10, 2, 3), (.zombifiedPiglin, 5, 4, 4), (.witherSkeleton, 8, 5, 5), (.skeleton, 2, 5, 5), (.magmaCube, 3, 4, 4)]
        } else {
            switch w.gen.column(x, z).biome {
            case .soulSandValley: list = [(.skeleton, 20, 5, 5), (.ghast, 50, 4, 4), (.enderman, 1, 4, 4)]
            case .basaltDeltas: list = [(.ghast, 40, 1, 1), (.magmaCube, 100, 2, 5)]
            case .crimsonForest: list = [(.zombifiedPiglin, 1, 2, 4), (.hoglin, 9, 3, 4), (.piglin, 5, 3, 4)]
            case .warpedForest: list = [(.enderman, 1, 4, 4)]
            default: list = [(.zombifiedPiglin, 100, 4, 4), (.ghast, 50, 4, 4), (.magmaCube, 2, 4, 4), (.enderman, 1, 4, 4), (.piglin, 15, 4, 4)]
            }
        }
        let total = list.reduce(0) { $0 + $1.1 }
        var roll = Rand.int(in: 0..<total)
        var pick = list[0]
        for e in list { roll -= e.1; if roll < 0 { pick = e; break } }
        // Wailers are rare per attempt (they need a big open space) — the reference game's spawn
        // attempts fail for them most of the time.
        if pick.0 == .ghast && Rand.float(in: 0..<1) < 0.8 { return }
        let n = Rand.int(in: pick.2...pick.3)
        for _ in 0..<n {
            let sx = x + Rand.int(in: -3...3), sz = z + Rand.int(in: -3...3)
            var sy = y + 2
            while sy > y - 4 && !Blocks.opaque[Int(w.block(sx, sy - 1, sz))] { sy -= 1 }
            let p = V3(Float(sx) + 0.5, Float(sy), Float(sz) + 0.5)
            let m = Mob(pick.0, at: pick.0 == .ghast ? p + V3(0, 3, 0) : p)
            if m.sized { m.makeSlime(size: [1, 2, 4][Rand.int(in: 0...2)]) }
            // Young boarlings: 20%; young undead boarlings: 5% (reference).
            if (pick.0 == .piglin && Rand.float(in: 0..<1) < 0.2) || (pick.0 == .zombifiedPiglin && Rand.float(in: 0..<1) < 0.05) {
                m.baby = true; m.scale = 0.5
            }
            if m.collides(m.pos, w) { continue }
            mobs.append(m)
            if mobs.count >= MobManager.hostileCap + 10 { return }
        }
    }

    // Nearest mob along a ray.
    func raycast(_ o: V3, _ d: V3, maxDist: Float, except: Mob? = nil) -> (Mob, Float)? {
        var best: (Mob, Float)?
        for m in mobs where m !== except {
            if let t = m.rayHit(o, d, maxDist: maxDist), t < (best?.1 ?? .greatestFiniteMagnitude) { best = (m, t) }
        }
        return best
    }
}
