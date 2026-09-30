import Foundation
import simd

// Village life on top of trading: beds and sleeping at night, food pickup and breeding (reference:
// 12 food points, bread 4, carrot/potato/beetroot 1, plus a free bed), farmers harvesting and
// replanting ripe crops, iron golems appearing when villagers gather, and zombie sieges at midnight.
enum VillageLife {
    static let foodPoints: [String: Int] = ["bread": 4, "carrot": 1, "potato": 1, "beetroot": 1]
    static let crops: [String: (Int, String)] = ["wheat": (7, "wheat"), "carrots": (7, "carrot"), "potatoes": (7, "potato"), "beetroots": (3, "beetroot")]
    // Village Hero gifts by profession (reference hero_of_the_village loot tables).
    static let heroGifts: [String: [String]] = [
        "armorer": ["chainmail_helmet", "chainmail_chestplate", "chainmail_leggings", "chainmail_boots"],
        "butcher": ["cooked_rabbit", "cooked_chicken", "cooked_porkchop", "cooked_beef", "cooked_mutton"],
        "cartographer": ["map", "paper"],
        "cleric": ["redstone", "lapis_lazuli"],
        "farmer": ["bread", "pumpkin_pie", "cookie"],
        "fisherman": ["cod", "salmon"],
        "fletcher": ["arrow"],
        "leatherworker": ["leather"],
        "librarian": ["book"],
        "mason": ["clay_ball"],
        "shepherd": ["white_wool", "orange_wool", "magenta_wool", "light_blue_wool", "yellow_wool", "lime_wool", "pink_wool", "gray_wool",
                     "light_gray_wool", "cyan_wool", "purple_wool", "blue_wool", "brown_wool", "green_wool", "red_wool", "black_wool"],
        "toolsmith": ["stone_pickaxe", "stone_axe", "stone_hoe", "stone_shovel"],
        "weaponsmith": ["stone_axe", "golden_axe", "iron_axe"],
        "baby": ["poppy"],
        "none": ["wheat_seeds"],
    ]
}

extension Mob {
    // Every 5 s (from the villager AI): claim a bed, pick up food, breed, farm, call a golem.
    func villageTick(_ g: Game) {
        guard var v = villager else { return }
        let w = g.world
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        // Beds: claim the nearest unclaimed bed head within 16 blocks.
        if let b = v.bed {
            let k = Blocks.key(Blocks.groupBase[Int(w.block(b[0], b[1], b[2]))])
            if !k.hasSuffix("_bed_head") && !k.hasSuffix("_bed") { v.bed = nil }
        }
        if v.bed == nil && !baby {
            let claimed = Set(g.mobs.mobs.compactMap { $0.villager?.bed }.map { IVec3($0[0], $0[1], $0[2]) })
            search: for r in 1...12 { for dy in -3...3 { for dz in -r...r { for dx in -r...r where abs(dx) == r || abs(dz) == r {
                let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                let k = Blocks.key(Blocks.groupBase[Int(w.block(q.x, q.y, q.z))])
                if k.hasSuffix("_bed_head") && !claimed.contains(q) { v.bed = [q.x, q.y, q.z]; break search }
            } } } }
        }
        // Food lying nearby is picked up.
        for e in g.drops.items where e.pickupDelay <= 0 && simd_length(e.pos - pos) < 1.5 {
            if let pts = VillageLife.foodPoints[Items.key(e.stack.item)] {
                v.food = (v.food ?? 0) + pts * e.stack.count
                e.stack = .empty
            }
        }
        // Farmers harvest ripe crops around their farm and replant.
        if v.profession == "farmer" && g.dayFraction < 0.45 {
            for _ in 0..<12 {
                let q = IVec3(c.x + Int.random(in: -6...6), c.y + Int.random(in: -1...1), c.z + Int.random(in: -6...6))
                let b = w.block(q.x, q.y, q.z)
                let base = Blocks.groupBase[Int(b)]
                guard let (ripe, item) = VillageLife.crops[Blocks.key(base)], Int(b - base) >= ripe else { continue }
                if simd_length(V3(Float(q.x) + 0.5, Float(q.y), Float(q.z) + 0.5) - pos) > 2 {
                    face(V3(Float(q.x) + 0.5, Float(q.y), Float(q.z) + 0.5)); moving = true; aiTimer = 2
                    break
                }
                w.setBlock(q.x, q.y, q.z, base)          // replanted at stage 0
                v.food = (v.food ?? 0) + (item == "wheat" ? 2 : 1) * Int.random(in: 1...3)
                g.sfx(.breakBlock(.plant), 0.5, at: V3(Float(q.x) + 0.5, Float(q.y), Float(q.z) + 0.5))
                break
            }
        }
        // Breeding: two willing villagers (12+ food) near a free bed make a baby.
        if !baby && (v.food ?? 0) >= 12 && breedCooldown <= 0,
           let mate = g.mobs.mobs.first(where: { $0 !== self && $0.kind == .villager && !$0.baby && $0.breedCooldown <= 0
                                                 && ($0.villager?.food ?? 0) >= 12 && simd_length($0.pos - pos) < 8 }) {
            let beds = g.mobs.mobs.filter { $0.kind == .villager }.count
            var freeBed = false
            for dz in -16...16 where !freeBed { for dx in -16...16 where !freeBed { for dy in -3...3 {
                if Blocks.key(Blocks.groupBase[Int(w.block(c.x + dx, c.y + dy, c.z + dz))]).hasSuffix("_bed_head") {
                    freeBed = beds < 64; break
                }
            } } }
            if freeBed {
                v.food = (v.food ?? 0) - 12
                if var mv = mate.villager { mv.food = (mv.food ?? 0) - 12; mate.villager = mv }
                breedCooldown = 300; mate.breedCooldown = 300
                let kid = Mob(.villager, at: (pos + mate.pos) * 0.5)
                kid.baby = true; kid.scale = 0.5
                var kv = VillagerData(); kv.type = v.type
                kid.villager = kv
                g.mobs.mobs.append(kid)
                g.particles.hearts(at: kid.pos + V3(0, 1, 0))
            }
        }
        villager = v
        heroGift(g)
        // Iron golems: 3+ villagers gathered and no golem within 16 blocks.
        if Float.random(in: 0..<1) < 0.04 {
            let near = g.mobs.mobs.filter { $0.kind == .villager && !$0.baby && simd_length($0.pos - pos) < 10 }
            if near.count >= 3 && !g.mobs.mobs.contains(where: { $0.kind == .ironGolem && simd_length($0.pos - pos) < 16 }) {
                for _ in 0..<10 {
                    let x = c.x + Int.random(in: -8...8), z = c.z + Int.random(in: -8...8)
                    let y = w.topY(x, z) + 1
                    guard abs(y - c.y) < 8, Blocks.collide[Int(w.block(x, y - 1, z))], !Blocks.collide[Int(w.block(x, y, z))],
                          !Blocks.collide[Int(w.block(x, y + 1, z))], !Blocks.collide[Int(w.block(x, y + 2, z))] else { continue }
                    let golem = Mob(.ironGolem, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                    golem.persistent = true
                    g.mobs.mobs.append(golem)
                    break
                }
            }
        }
    }

    // Village Hero: a villager within 5 blocks of the hero throws a gift every 30 s - 5.5 min (from villageTick, every 5 s).
    func heroGift(_ g: Game) {
        giftTimer -= 5
        guard giftTimer <= 0, g.effects.has(.heroOfTheVillage), g.alive, !sitting, simd_length(g.player.pos - pos) < 5 else { return }
        giftTimer = Float.random(in: 30...330)
        let prof = baby ? "baby" : (villager?.profession ?? "none")
        guard let pool = VillageLife.heroGifts[prof] ?? VillageLife.heroGifts["none"], let name = pool.randomElement(), Items.has(name) else { return }
        face(g.player.pos)
        let dir = simd_normalize(g.player.eye - eye)
        g.drops.spawn(ItemStack(Items.id(name), 1), at: eye + dir * 0.4, vel: dir * 4 + V3(0, 2, 0))
        g.sfx(.mobVillager, 0.8, at: pos)
    }

    // Night: head for the claimed bed and stay there (sleeping) until morning.
    func villagerNight(_ g: Game) -> Bool {
        let f = g.dayFraction
        guard f > 0.52 && f < 0.97, let b = villager?.bed else { sitting = false; return false }
        let bedPos = V3(Float(b[0]) + 0.5, Float(b[1]) + 0.6, Float(b[2]) + 0.5)
        if simd_length(V2(bedPos.x - pos.x, bedPos.z - pos.z)) > 1.2 {
            face(bedPos); moving = true
            sitting = false
            return false
        }
        sitting = true          // asleep in bed
        vel.x = 0; vel.z = 0
        return true
    }
}

extension Game {
    // Zombie siege: at midnight, 10% of nights, while the player is in a village (20 zombies at its edge).
    func siegeTick() {
        let f = dayFraction
        guard dim.dim == .overworld, f > 0.74 && f < 0.76, survival, difficulty > 0 else { return }
        let day = Int(time / DAY_LENGTH)
        guard lastSiegeDay != day else { return }
        lastSiegeDay = day
        guard Float.random(in: 0..<1) < 0.1 else { return }
        let villagers = mobs.mobs.filter { $0.kind == .villager && simd_length($0.pos - player.pos) < 32 }
        guard villagers.count >= 5 else { return }
        let a = Float.random(in: 0..<(2 * .pi))
        let cx = player.pos.x + cosf(a) * 28, cz = player.pos.z + sinf(a) * 28
        for _ in 0..<20 {
            let x = Int(floor(cx)) + Int.random(in: -4...4), z = Int(floor(cz)) + Int.random(in: -4...4)
            guard world.isLoaded(x, z) else { continue }
            let y = world.topY(x, z) + 1
            mobs.mobs.append(Mob(.zombie, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)))
        }
    }
}
