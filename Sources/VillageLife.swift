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
        v.decayGossip(day: Int(g.time / DAY_LENGTH))
        villager = v
        heroGift(g)
        gossipCooldown -= 5
        if g.mobs.mobs.contains(where: { $0.kind == .ironGolem && simd_length($0.pos - pos) < 16 }) { golemSeenAt = g.time }
        gossipTick(g)
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

    // Night (from 12000 ticks): head for the claimed bed and stay there (sleeping) until morning.
    func villagerNight(_ g: Game) -> Bool {
        let f = g.dayFraction
        guard f > 0.5 && f < 0.995, let b = villager?.bed else { sitting = false; return false }
        let bedPos = V3(Float(b[0]) + 0.5, Float(b[1]) + 0.6, Float(b[2]) + 0.5)
        if simd_length(V2(bedPos.x - pos.x, bedPos.z - pos.z)) > 1.2 {
            face(bedPos); moving = true
            sitting = false
            return false
        }
        sitting = true          // asleep in bed
        sleptAt = g.time
        vel.x = 0; vel.z = 0
        return true
    }

    // MARK: Daytime schedule

    enum Activity { case idle, work, meet, play }

    // Reference schedules: adults idle / work from 2000 / meet from 9000 / idle from 11000 / rest from 12000;
    // children idle / play from 3000 / idle from 6000 / play from 10000 / rest from 12000.
    func activity(_ f: Double) -> Activity {
        let t = f * 24000
        if baby { return t < 3000 ? .idle : (t < 6000 ? .play : (t < 10000 ? .idle : .play)) }
        let prof = villager?.profession ?? "none"
        if t >= 2000 && t < 9000 { return prof == "none" || prof == "nitwit" ? .idle : .work }
        if t >= 9000 && t < 11000 { return .meet }
        return .idle
    }

    static let villageThreats: [MobKind] = [.zombie, .husk, .drowned, .zombieVillager, .vex, .ravager, .evoker, .vindicator, .pillager, .zoglin, .illusioner]

    // Walks toward `anchor` when farther than `r`, else strolls; returns the speed.
    func stroll(around anchor: V3, _ r: Float, _ pace: Float) -> Float {
        if simd_length(V2(anchor.x - pos.x, anchor.z - pos.z)) > r { face(anchor); moving = true; return spec.speed * pace }
        wander()
        return moving ? spec.speed * pace * 0.8 : 0
    }

    func villagerDay(_ dt: Float, _ g: Game) -> Float {
        // Panic: zombies within 8, illagers / vexes / siegebeasts within 12 (panicking villagers may call a golem).
        var threat: Mob?
        for k in Mob.villageThreats + [.witch] where threat == nil {
            for o in g.mobs.of(k) where o.health > 0 && (k != .witch || o.raider) && simd_length(o.pos - pos) < (o.isZombie ? 8 : 12) { threat = o; break }
        }
        if let z = threat {
            face(pos * 2 - z.pos)
            moving = true
            if gossipCooldown <= 0 && !baby { gossipCooldown = 5; spawnGolemIfNeeded(g, needed: 3) }
            return 2.2
        }
        if panic > 0 { wander(); return spec.speed * 1.3 }
        let home = self.home ?? pos
        switch activity(g.dayFraction) {
        case .work:
            if let js = villager?.jobSite {
                return stroll(around: V3(Float(js[0]) + 0.5, Float(js[1]), Float(js[2]) + 0.5), 2.5, 0.6)
            }
        case .meet:
            if let bell = meetingPoint(g, dt) {
                return stroll(around: V3(Float(bell.x) + 0.5, Float(bell.y), Float(bell.z) + 0.5), 5, 0.6)
            }
        case .play:
            return stroll(around: home, 16, 1.2)
        case .idle:
            break
        }
        return stroll(around: home, 16, 0.6)
    }

    // The village bell within 32 blocks (searched every 2 minutes).
    func meetingPoint(_ g: Game, _ dt: Float) -> IVec3? {
        meetSearch -= dt
        if meetSearch > 0 { return meetPoint }
        meetSearch = 120
        let bell = Blocks.id("bell")
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        var best: IVec3?
        var bd = Int.max
        for dy in -8...8 { for dz in -32...32 { for dx in -32...32 {
            guard g.world.block(c.x + dx, c.y + dy, c.z + dz) == bell else { continue }
            let d = dx * dx + dz * dz + dy * dy
            if d < bd { bd = d; best = IVec3(c.x + dx, c.y + dy, c.z + dz) }
        } } }
        meetPoint = best
        return best
    }

    // MARK: Gossip and golems

    // Villagers that slept within the last day and haven't seen a golem for 30 s want one.
    func wantsGolem(_ g: Game) -> Bool {
        kind == .villager && !baby && g.time - sleptAt < DAY_LENGTH && g.time - golemSeenAt > 30
    }

    // Reference spawnGolemIfNeeded: enough villagers within 10 blocks wanting a golem summon one nearby.
    func spawnGolemIfNeeded(_ g: Game, needed: Int) {
        guard wantsGolem(g) else { return }
        let group = g.mobs.mobs.filter { $0.kind == .villager && simd_length($0.pos - pos) < 10 && $0.wantsGolem(g) }
        guard group.count >= needed else { return }
        let w = g.world
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        for _ in 0..<10 {
            let x = c.x + Int.random(in: -8...8), z = c.z + Int.random(in: -8...8)
            var y = c.y + 6
            while y > c.y - 6 && !(Blocks.opaque[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))]) { y -= 1 }
            guard y > c.y - 6, !Blocks.isLiquid(w.block(x, y, z)) else { continue }
            let golem = Mob(.ironGolem, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
            if golem.collides(golem.pos, w) { continue }
            golem.persistent = true
            g.mobs.mobs.append(golem)
            for v in group { v.golemSeenAt = g.time }
            return
        }
    }

    // Two villagers next to each other share what they know (every 60 s each), then maybe call a golem.
    func gossipTick(_ g: Game) {
        guard kind == .villager, !baby, gossipCooldown <= 0 else { return }
        guard let o = g.mobs.mobs.first(where: { $0 !== self && $0.kind == .villager && !$0.baby && $0.gossipCooldown <= 0
                                                  && simd_length($0.pos - pos) < 3 }) else { return }
        if var a = villager, var b = o.villager {
            let ga = a.gossip ?? [0, 0, 0, 0, 0], gb = b.gossip ?? [0, 0, 0, 0, 0]
            for t in Gossip.allCases {
                let i = t.rawValue
                a.mergeGossip(t, gb[i] - Gossip.decayTransfer[i])
                b.mergeGossip(t, ga[i] - Gossip.decayTransfer[i])
            }
            villager = a; o.villager = b
        }
        gossipCooldown = 60; o.gossipCooldown = 60
        spawnGolemIfNeeded(g, needed: 5)
    }
}

// Reference gossip types: weight on reputation, cap, decay per day and when passed on.
enum Gossip: Int, CaseIterable {
    case majorNeg, minorNeg, minorPos, majorPos, trading
    static let weight = [-5, -1, 1, 5, 1]
    static let cap = [100, 200, 200, 100, 25]
    static let decayDay = [10, 20, 1, 0, 2]
    static let decayTransfer = [10, 20, 5, 100, 20]
}

extension VillagerData {
    var reputation: Int {
        guard let gs = gossip else { return 0 }
        var r = 0
        for (i, v) in gs.enumerated() where i < Gossip.weight.count { r += v * Gossip.weight[i] }
        return r
    }
    mutating func addGossip(_ t: Gossip, _ n: Int) {
        var gs = gossip ?? [0, 0, 0, 0, 0]
        gs[t.rawValue] = min(Gossip.cap[t.rawValue], gs[t.rawValue] + n)
        gossip = gs
    }
    // Heard from another villager: keep the larger value.
    mutating func mergeGossip(_ t: Gossip, _ n: Int) {
        guard n > 0 else { return }
        var gs = gossip ?? [0, 0, 0, 0, 0]
        gs[t.rawValue] = min(Gossip.cap[t.rawValue], max(gs[t.rawValue], n))
        gossip = gs
    }
    mutating func decayGossip(day: Int) {
        if cured && gossip == nil { addGossip(.majorPos, 20); addGossip(.minorPos, 25) }      // worlds from before gossip
        let last = gossipDay ?? day
        gossipDay = day
        guard day > last, var gs = gossip else { return }
        for _ in 0..<min(30, day - last) { for i in gs.indices { gs[i] = max(0, gs[i] - Gossip.decayDay[i]) } }
        gossip = gs
    }
}

extension Game {
    // A villager killed by the player: every villager within 16 blocks that can see it remembers (major negative 25).
    func villagerDied(_ m: Mob) {
        // Reference drop odds kept out of the plain tables: fish bone meal 5%, rabbit's foot 10% (+3% per
        // Looting) and spider eyes 1 in 3, both only for player kills.
        if !m.baby {
            let at = m.pos + V3(0, 0.4, 0)
            let looting = Float(m.killedByPlayer ? m.lootingLevel : 0)
            if [.cod, .salmon, .tropicalFish, .pufferfish].contains(m.kind) && Float.random(in: 0..<1) < 0.05 && Items.has("bone_meal") {
                drops.spawn(ItemStack(Items.id("bone_meal"), 1), at: at)
            }
            if m.kind == .rabbit && m.killedByPlayer && Float.random(in: 0..<1) < 0.1 + 0.03 * looting && Items.has("rabbit_foot") {
                drops.spawn(ItemStack(Items.id("rabbit_foot"), 1), at: at)
            }
            if (m.kind == .spider || m.kind == .caveSpider) && m.killedByPlayer && Items.has("spider_eye") {
                let n = Int.random(in: -1...1) + Int.random(in: 0...Int(looting))
                if n > 0 { drops.spawn(ItemStack(Items.id("spider_eye"), n), at: at) }
            }
        }
        // Killing prey an axolotl was fighting: Regeneration for the player, and Mining Fatigue lifted.
        if m.killedByPlayer && m.spec.aquatic && m.kind != .axolotl,
           mobs.of(.axolotl).contains(where: { simd_length($0.pos - m.pos) < 12 }) {
            let t = min(120, (effects[.regeneration]?.time ?? 0) + 5)
            applyEffect(.regeneration, amp: 0, seconds: t)
            effects.remove(.miningFatigue)
        }
        if m.carriedBlock != 0, let it = Items.item(forBlock: m.carriedBlock) { drops.spawn(ItemStack(it, 1), at: m.pos + V3(0, 1, 0)) }
        guard m.kind == .villager, m.killedByPlayer else { return }
        for o in mobs.mobs where o !== m && o.kind == .villager && o.health > 0 && simd_length(o.pos - m.pos) < 16
            && world.canSee(o.eye, m.eye) {
            if var v = o.villager { v.addGossip(.majorNeg, 25); o.villager = v }
        }
    }

    // Iron golems turn on a player that a nearby villager thinks badly of (reputation -100 or lower).
    func villagersHatePlayer(near p: V3) -> Bool {
        mobs.mobs.contains { $0.kind == .villager && simd_length($0.pos - p) < 10 && ($0.villager?.reputation ?? 0) <= -100 }
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
