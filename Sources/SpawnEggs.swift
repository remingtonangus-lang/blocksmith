import Foundation
import simd

// Spawn eggs for every living mob kind: one shared shell texture (outline + speckles) with the shell
// tinted per kind through the item overlay layer. Using one on a block spawns the mob on that face;
// using one on a grown mob of the same kind spawns a baby (animals) — the reference behaviour.
enum SpawnEggs {
    static var kindOf: [ItemID: MobKind] = [:]

    static func eligible(_ k: MobKind) -> Bool {
        ![.minecart, .boat, .armorStand, .endCrystal].contains(k)
    }

    static func itemName(_ k: MobKind) -> String { "\(k.key)_spawn_egg" }

    // Shell colour per kind (original palette).
    static func color(_ k: MobKind) -> UInt32 {
        switch k {
        case .cow, .mooshroom: return k == .cow ? 0x443626 : 0xA00F10
        case .sheep: return 0xE7E7E7
        case .chicken: return 0xA1A1A1
        case .pig: return 0xF0A5A2
        case .zombie, .zombieVillager: return 0x00AFAF
        case .husk: return 0x797061
        case .drowned: return 0x8FF1D7
        case .skeleton, .stray, .bogged: return k == .skeleton ? 0xC1C1C1 : (k == .stray ? 0x617677 : 0x8A9A5B)
        case .creeper: return 0x0DA70B
        case .spider, .caveSpider: return k == .spider ? 0x342D27 : 0x0C424E
        case .enderman, .endermite: return 0x161616
        case .slime: return 0x51A03E
        case .magmaCube: return 0x340000
        case .zombifiedPiglin, .piglin, .piglinBrute: return k == .zombifiedPiglin ? 0xEA9393 : (k == .piglin ? 0x995F40 : 0x592A10)
        case .ghast: return 0xF9F9F9
        case .blaze: return 0xF6B201
        case .witherSkeleton, .wither: return 0x141414
        case .hoglin, .zoglin: return k == .hoglin ? 0xC66E55 : 0xC66E7A
        case .strider: return 0x9C3436
        case .enderDragon: return 0x1C1C1C
        case .shulker: return 0x946794
        case .villager, .wanderingTrader: return k == .villager ? 0x563C33 : 0x456296
        case .ironGolem: return 0xDBCDC1
        case .snowGolem: return 0xD9F2F2
        case .witch: return 0x340000
        case .pillager, .vindicator, .evoker: return 0x959B9B
        case .vex: return 0x7A90A4
        case .ravager: return 0x757470
        case .silverfish: return 0x6E6E6E
        case .rabbit: return 0x995F40
        case .fox: return 0xD5B69F
        case .wolf: return 0xD7D3D3
        case .cat, .ocelot: return k == .cat ? 0xEFC88E : 0xEFDE7D
        case .horse, .donkey, .mule, .skeletonHorse: return k == .horse ? 0xC09E7D : (k == .skeletonHorse ? 0x68684F : 0x534539)
        case .llama, .traderLlama: return 0xC09E7D
        case .camel: return 0xFCC369
        case .goat: return 0xA5947C
        case .panda: return 0xE7E7E7
        case .polarBear: return 0xEEEEDE
        case .turtle: return 0xE7E7E7
        case .frog, .tadpole: return k == .frog ? 0xD07444 : 0x6D533D
        case .armadillo: return 0xAD716D
        case .sniffer: return 0x871E09
        case .bee: return 0xEDC343
        case .parrot: return 0x0DA70B
        case .bat: return 0x4C3E30
        case .allay: return 0x00DAFF
        case .axolotl: return 0xFBC1E3
        case .squid, .glowSquid: return k == .squid ? 0x223B4D : 0x095656
        case .dolphin: return 0x223B4D
        case .cod, .salmon: return k == .cod ? 0xC1A76A : 0xA00F10
        case .tropicalFish, .pufferfish: return k == .tropicalFish ? 0xEF6915 : 0xF6B201
        case .phantom: return 0x43518A
        case .guardian, .elderGuardian: return k == .guardian ? 0x5A8272 : 0xCECCBA
        case .warden: return 0x0F4649
        case .breeze: return 0xAF94DF
        case .creaking: return 0x5F5F5F
        default:
            let h = hash3(k.rawValue, 3, 7, 0xE66)
            return 0x404040 | (h & 0x7F7F7F)
        }
    }

    static func register(_ reg: ItemRegistry) {
        Cloudwailer.register(reg)
        for k in MobKind.allCases where eligible(k) {
            let n = itemName(k)
            guard !reg.has(n) else { continue }
            var d = ItemDef(n, "\(k.name) Spawn Egg")
            d.texKey = "item_spawn_egg"
            d.overlay = "item_spawn_egg_shell"
            d.overlayColor = color(k)
            kindOf[reg.add(d)] = k
        }
    }

    static let shape: [String] = [
        "................",
        "................",
        ".......11.......",
        "......1ss1......",
        ".....1ssss1.....",
        ".....1sdss1.....",
        "....1ssssss1....",
        "....1ssdsss1....",
        "....1ssssss1....",
        "...1sssdssds1...",
        "...1ssssssss1...",
        "...1sdssssss1...",
        "....1ssssds1....",
        ".....1ssss1.....",
        "......1111......",
        "................",
    ]

    // Base layer: outline and speckles; overlay layer: the shell (white, tinted per kind).
    static func painters(_ p: inout [String: TextureGen.Painter]) {
        Cloudwailer.painters(&p)
        let rows = shape.map { Array($0) }
        p["item_spawn_egg"] = { x, y in
            guard y < rows.count, x < rows[y].count else { return TextureGen.clear }
            switch rows[y][x] {
            case "1": return V4(0.12, 0.12, 0.12, 1)
            case "d": return V4(0.22, 0.2, 0.2, 1)
            default: return TextureGen.clear
            }
        }
        p["item_spawn_egg_shell"] = { x, y in
            guard y < rows.count, x < rows[y].count, rows[y][x] == "s" else { return TextureGen.clear }
            let shade: Float = x < 7 && y < 8 ? 1 : (x > 9 || y > 11 ? 0.72 : 0.88)
            return V4(shade, shade, shade, 1)
        }
    }
}

extension Game {
    // Right-click with a spawn egg: a baby from a grown mob of the same kind, else the mob on the clicked face.
    func useSpawnEgg(on t: (hit: IVec3, normal: IVec3)?) -> Bool {
        guard let kind = SpawnEggs.kindOf[held.item] else { return false }
        if let hit = mobs.raycast(player.eye, player.look, maxDist: 3.5), hit.0.kind == kind, !hit.0.baby,
           kind.category == .creature || kind == .villager {
            let b = Mob(kind, at: hit.0.pos)
            b.baby = true
            b.scale = 0.5
            mobs.mobs.append(b)
            if survival { consumeHeld() }
            return true
        }
        guard let t = t else { return false }
        let p = t.hit + t.normal
        let solid = Blocks.collide[Int(world.block(t.hit.x, t.hit.y, t.hit.z))]
        let y = Float(solid ? p.y : t.hit.y)
        let m = Mob(kind, at: V3(Float(p.x) + 0.5, y, Float(p.z) + 0.5))
        m.persistent = kind.category != .creature
        if kind == .slime || kind == .magmaCube { m.makeSlime(size: [1, 2, 4][Int.random(in: 0...2)]) }
        if kind == .enderDragon { m.phase = 0 }
        mobs.mobs.append(m)
        if survival { consumeHeld() }
        sfx(.place(.dirt), 0.4, at: m.pos)
        return true
    }
}
