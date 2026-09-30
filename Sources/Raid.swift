import Foundation
import simd

// Raids (reference rules): drinking an omen bottle gives Ill Omen; walking into a village with it
// turns it into Siege Omen, and 30 s later the raid starts. 3 / 5 / 7 waves on Easy / Normal / Hard
// (+1 bonus wave when the omen level is above I) of marauders, brigands, siegebeasts, witches and
// conjurers spawn at the village edge; each wave has a captain carrying the omen banner, siegebeasts
// carry riders on the last Normal wave and from Hard's seventh, and raiders get enchanted weapons at
// higher omen levels. Winning gives Village Hero (villagers throw gifts, trades get cheaper); losing
// every villager is a defeat. Marauder patrols roam by day after day 5; their captains drop omen bottles.

final class Raid {
    var center: V3
    var level: Int                // omen level 1...5
    var wave = 0                  // waves spawned so far
    let groups: Int               // regular waves for the difficulty the raid started on
    let difficulty: Int
    var totalWaves: Int { groups + (level > 1 ? 1 : 0) }
    var raiders: [Mob] = []
    var state = 0                 // 0 between waves (countdown), 1 wave active, 2 victory, 3 defeat
    var timer: Float = 15         // countdown before the next wave / to disappear after the end
    var waveHealth: Float = 1
    var idle: Float = 0           // seconds active (a raid times out after 40 min)
    var log: [String] = []        // what each wave spawned (harness)
    init(center: V3, level: Int, difficulty: Int = 2) {
        self.center = center
        self.level = max(1, min(5, level))
        self.difficulty = difficulty
        groups = RaidTable.groupCount(difficulty)
    }
}

enum RaidTable {
    // Raiders per wave number 1...8 (reference "spawnsPerWaveBeforeBonus"); the bonus wave uses the
    // entry for the difficulty's last regular wave.
    static let counts: [(MobKind, [Int])] = [
        (.vindicator, [0, 0, 2, 0, 1, 4, 2, 5]),
        (.evoker, [0, 0, 0, 0, 0, 1, 1, 2]),
        (.pillager, [0, 4, 3, 3, 4, 4, 4, 2]),
        (.witch, [0, 0, 0, 0, 3, 0, 0, 1]),
        (.ravager, [0, 0, 0, 1, 0, 1, 0, 2]),
    ]

    static func groupCount(_ difficulty: Int) -> Int { difficulty <= 1 ? 3 : (difficulty == 2 ? 5 : 7) }

    // Chance of raid weapons being enchanted by omen level (reference getEnchantOdds).
    static func enchantOdds(_ level: Int) -> Float { [0, 0, 0.1, 0.25, 0.5, 0.75][max(0, min(5, level))] }

    // Random extra raiders of a kind on top of the table (reference getPotentialBonusSpawns).
    static func bonusSpawns(_ kind: MobKind, wave: Int, difficulty: Int, bonusWave: Bool, roll: (Int) -> Int) -> Int {
        var i = 0
        switch kind {
        case .witch:
            if difficulty <= 1 || wave <= 2 || wave == 4 { return 0 }
            i = 1
        case .pillager, .vindicator:
            i = difficulty <= 1 ? roll(2) : (difficulty == 2 ? 1 : 2)
        case .ravager:
            i = difficulty > 1 && bonusWave ? 1 : 0
        default:
            return 0
        }
        return i > 0 ? roll(i + 1) : 0
    }

    struct Member { var kind: MobKind; var rider: MobKind?; var captain: Bool }

    // One wave: raiders in the reference order (brigands, conjurers, marauders, witches, siegebeasts);
    // the first raider able to lead becomes the captain. `wave` counts from 1 (the bonus wave is groups + 1).
    static func composition(wave: Int, groups: Int, difficulty: Int, bonusWave: Bool,
                            roll: (Int) -> Int = { Int.random(in: 0..<max(1, $0)) }) -> [Member] {
        var out: [Member] = []
        var leader = false
        var ravagers = 0
        for (kind, table) in counts {
            let idx = min(table.count - 1, bonusWave ? groups : wave)
            let n = table[idx] + bonusSpawns(kind, wave: wave, difficulty: difficulty, bonusWave: bonusWave, roll: roll)
            for _ in 0..<n {
                var m = Member(kind: kind, rider: nil, captain: false)
                if !leader && kind != .witch && kind != .ravager { m.captain = true; leader = true }
                if kind == .ravager {
                    if wave == groupCount(2) { m.rider = .pillager }
                    else if wave >= groupCount(3) { m.rider = ravagers == 0 ? .evoker : .vindicator }
                    ravagers += 1
                }
                out.append(m)
            }
        }
        return out
    }
}

extension Game {
    var raidBar: (String, Float)? {
        guard let r = raid, simd_length(player.pos - r.center) < 96 else { return nil }
        switch r.state {
        case 2: return ("Raid - Victory", 1)
        case 3: return ("Raid - Defeat", 0)
        case 0: return ("Raid", 1 - r.timer / 15)
        default:
            let left = r.raiders.filter { $0.health > 0 }.count
            let hp = r.raiders.reduce(Float(0)) { $0 + Float(max(0, $1.health)) }
            return ("Raid - Raiders Remaining: \(left)", hp / max(1, r.waveHealth))
        }
    }

    // A village is anywhere with a bell or at least one villager bed and villagers nearby.
    func nearVillage(_ p: V3) -> V3? {
        let villagers = mobs.mobs.filter { $0.kind == .villager && simd_length($0.pos - p) < 48 }
        guard !villagers.isEmpty else { return nil }
        // Centre: the nearest bell if there is one, else the villagers' average position.
        let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
        let bell = Blocks.id("bell")
        for r in stride(from: 0, through: 32, by: 2) {
            for dy in -6...6 { for dz in stride(from: -r, through: r, by: 1) { for dx in [-r, r] {
                if world.block(c.x + dx, c.y + dy, c.z + dz) == bell { return V3(Float(c.x + dx), Float(c.y + dy), Float(c.z + dz)) }
                if world.block(c.x + dz, c.y + dy, c.z + dx) == bell { return V3(Float(c.x + dz), Float(c.y + dy), Float(c.z + dx)) }
            } } }
        }
        return villagers.reduce(V3.zero) { $0 + $1.pos } / Float(villagers.count)
    }

    // Called every second.
    func raidTick(_ dt: Float) {
        if difficulty == 0 { raid = nil; return }
        // Ill Omen + village -> Siege Omen (30 s) -> raid. Walking into a running raid with Ill Omen
        // raises its level instead (up to V), which can add the bonus wave.
        if let b = effects[.badOmen], survival, dim.dim == .overworld {
            if let r = raid, r.state < 2, simd_length(player.pos - r.center) < 96 {
                effects.remove(.badOmen)
                r.level = min(5, r.level + b.amp + 1)
            } else if raid == nil, nearVillage(player.pos) != nil {
                effects.remove(.badOmen)
                applyEffect(.raidOmen, amp: b.amp, seconds: 30)
                raidOmenAt = player.pos
            }
        }
        if raid == nil, let ro = effects[.raidOmen], ro.time <= 1.1 {
            effects.remove(.raidOmen)
            let c = nearVillage(raidOmenAt ?? player.pos) ?? player.pos
            raid = Raid(center: c, level: ro.amp + 1, difficulty: difficulty)
            sfx(.raidHorn, 1.5, at: c)
            onToast?("A raid has begun")
        }
        guard let r = raid else { return }
        r.raiders.removeAll { rd in rd.health <= 0 || !mobs.mobs.contains { $0 === rd } }
        r.idle += dt
        let villagersLeft = mobs.mobs.contains { $0.kind == .villager && simd_length($0.pos - r.center) < 64 }
        switch r.state {
        case 0:
            if !villagersLeft && r.wave > 0 { r.state = 3; r.timer = 30; onToast?("Raid - Defeat"); return }
            if !villagersLeft { raid = nil; return }
            if simd_length(player.pos - r.center) < 96 { r.timer -= dt }
            if r.timer <= 0 { spawnWave(r) }
        case 1:
            if !villagersLeft { r.state = 3; r.timer = 30; onToast?("Raid - Defeat"); return }
            // Raiders that wander more than 112 blocks off leave the raid; far ones march back.
            r.raiders.removeAll { simd_length($0.pos - r.center) > 112 }
            for m in r.raiders where simd_length(m.pos - r.center) > 48 && m.mount == nil { m.face(r.center); m.moving = true }
            if r.raiders.isEmpty {
                if r.wave >= r.totalWaves {
                    r.state = 2
                    r.timer = 30
                    onToast?("Raid - Victory")
                    // Village Hero: level = omen level, 40 minutes, for players near the village.
                    if simd_length(player.pos - r.center) < 96 {
                        applyEffect(.heroOfTheVillage, amp: r.level - 1, seconds: 2400)
                        achieve("raid_win")
                    }
                    sfx(.villagerCelebrate, 1.2)
                    for v in mobs.mobs where v.kind == .villager && simd_length(v.pos - r.center) < 64 { particles.hearts(at: v.pos + V3(0, 2.2, 0)) }
                } else {
                    r.state = 0
                    r.timer = 15
                }
            }
        default:
            r.timer -= dt
            if r.timer <= 0 { raid = nil; return }
        }
        if r.idle > 2400 && r.state < 2 { raid = nil }
    }

    private func spawnWave(_ r: Raid) {
        r.wave += 1
        r.state = 1
        let bonus = r.wave > r.groups
        // Spawn point on the ground 20-32 blocks from the centre.
        var at = r.center
        for _ in 0..<20 {
            let a = Float.random(in: 0..<(2 * .pi)), d = Float.random(in: 20...32)
            let x = Int(floor(r.center.x + cosf(a) * d)), z = Int(floor(r.center.z + sinf(a) * d))
            guard world.isLoaded(x, z) else { continue }
            let y = world.topY(x, z)
            if Blocks.isLiquid(world.block(x, y, z)) { continue }
            at = V3(Float(x) + 0.5, Float(y + 1), Float(z) + 0.5)
            break
        }
        var spawned: [Mob] = []
        func raider(_ kind: MobKind, _ p: V3) -> Mob {
            let m = Mob(kind, at: p)
            m.raider = true
            m.persistent = true
            m.aggro = kind == .vindicator || kind == .pillager
            m.applyRaidBuffs(wave: r.wave, level: r.level)
            return m
        }
        for member in RaidTable.composition(wave: r.wave, groups: r.groups, difficulty: r.difficulty, bonusWave: bonus) {
            let m = raider(member.kind, at + V3(Float.random(in: -2...2), 0, Float.random(in: -2...2)))
            m.captain = member.captain
            spawned.append(m)
            if let rk = member.rider {
                let rider = raider(rk, m.pos + V3(0, m.height * 0.8, 0))
                rider.mount = m
                spawned.append(rider)
            }
        }
        mobs.mobs += spawned
        r.raiders = spawned
        var n: [String: Int] = [:]
        for m in spawned { n[m.kind.key + (m.captain ? "*" : ""), default: 0] += 1 }
        r.log.append(n.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: " "))
        r.waveHealth = spawned.reduce(Float(0)) { $0 + Float($1.health) }
        sfx(.raidHorn, 1.5, at: at)
    }

    // MARK: Patrols

    // Reference patrol spawner: every 10-11 minutes, by day from day 5 on, a 20% chance of a marauder
    // patrol 24-47 blocks from the player along each axis (never next to a village or in mushroom
    // fields). Size = ceil(effective regional difficulty) + 1; the first one is the captain.
    func patrolTick(_ dt: Float) {
        specialSpawnersTick(dt)
        guard survival, difficulty > 0, dim.dim == .overworld, time / DAY_LENGTH >= 5 else { return }
        patrolTimer -= dt
        guard patrolTimer <= 0 else { return }
        patrolTimer = Float.random(in: 600...660)
        guard daylight > 0.5, Int.random(in: 0..<5) == 0 else { return }
        let x = Int(floor(player.pos.x)) + Int.random(in: 24...47) * (Bool.random() ? -1 : 1)
        let z = Int(floor(player.pos.z)) + Int.random(in: 24...47) * (Bool.random() ? -1 : 1)
        guard world.isLoaded(x, z) else { return }
        let biome = world.gen.column(x, z).biome
        if biome == .mushroomFields || nearVillage(V3(Float(x), player.pos.y, Float(z))) != nil { return }
        let n = Int(ceilf(effectiveDifficulty)) + 1
        var leader: Mob?
        for i in 0..<n {
            let px = x + (i == 0 ? 0 : Int.random(in: 0..<5) - Int.random(in: 0..<5))
            let pz = z + (i == 0 ? 0 : Int.random(in: 0..<5) - Int.random(in: 0..<5))
            guard world.isLoaded(px, pz) else { continue }
            let y = world.topY(px, pz)
            let b = world.block(px, y, pz)
            if Blocks.isLiquid(b) || world.lightAt(px, y + 1, pz).block > 8 { continue }
            let m = Mob(.pillager, at: V3(Float(px) + 0.5, Float(y + 1), Float(pz) + 0.5))
            if leader == nil { m.captain = true; leader = m }
            m.patrolling = true
            m.patrolLeader = leader
            m.persistent = false
            m.applyRaidBuffs(wave: 0, level: 0)
            mobs.mobs.append(m)
        }
    }

    // Killed captains (outside raids) drop an omen bottle (level I-V).
    func captainDied(_ m: Mob) {
        villagerDied(m)
        guard m.captain, !m.raider, m.killedByPlayer, Items.has("ominous_bottle") else { return }
        drops.spawn(ItemStack(Items.id("ominous_bottle"), 1, damage: Int.random(in: 0...4)), at: m.pos + V3(0, 0.5, 0))
    }

    // Zombie kills a villager (Normal: 50%): it becomes a zombie villager keeping its trades.
    func zombify(_ v: Mob) {
        let z = Mob(.zombieVillager, at: v.pos)
        z.yaw = v.yaw
        z.villager = v.villager
        z.persistent = true
        mobs.mobs.append(z)
        sfx(.zombieInfect, 1, at: v.pos)
    }

    // Zombie villager with Weakness + golden apple: cures in 3-5 minutes into a discounted villager.
    func startCure(_ m: Mob) -> Bool {
        guard m.kind == .zombieVillager, Items.key(held.item) == "golden_apple", m.effects?.has(.weakness) ?? false, m.cureTimer <= 0 else { return false }
        m.cureTimer = Float.random(in: 180...300)
        m.persistent = true
        consumeHeld()
        sfx(.zombieCure, 1, at: m.pos)
        return true
    }
}

extension Mob {
    // Reference raid gear: marauders carry a crossbow, brigands an iron axe; with the omen level's odds
    // they're enchanted (Quick Charge / Sharpness I past the Easy wave count, II past the Normal one).
    func applyRaidBuffs(wave: Int, level: Int) {
        let enchant = Float.random(in: 0..<1) < RaidTable.enchantOdds(level)
        let lv = wave > RaidTable.groupCount(2) ? 2 : (wave > RaidTable.groupCount(1) ? 1 : 0)
        let key: String, ench: Ench
        switch kind {
        case .pillager: key = "crossbow"; ench = .quickCharge
        case .vindicator: key = "iron_axe"; ench = .sharpness
        default: return
        }
        guard Items.has(key) else { return }
        var weapon = ItemStack(Items.id(key), 1)
        if enchant && lv > 0 { weapon.ench = Enchant.pack([(ench, lv)]) }
        var eq = equip ?? [ItemStack](repeating: .empty, count: 5)
        eq[4] = weapon
        equip = eq
    }

    // Enchantment level on the held weapon (raid sharpness / quick charge).
    func heldEnchant(_ e: Ench) -> Int {
        guard let eq = equip, eq.count > 4 else { return 0 }
        return Enchant.level(e, eq[4])
    }

    // Melee damage including a sharpened raid axe (+1 / +2).
    var meleeDamage: Int { spec.attack + heldEnchant(.sharpness) }
    // Reference shot cycles: bows draw 1 s then wait the attack interval (2 s, 1 s on Hard);
    // crossbows charge 1.25 s (-0.25 s per Quick Charge) then pause 1-2 s.
    var crossbowReload: Float {
        if kind == .pillager { return 1.25 - 0.25 * Float(heldEnchant(.quickCharge)) + Float.random(in: 1...2) }
        return Mob.hardMode ? 2 : 3
    }
    static var hardMode = false

    // Patrol goal (reference): the captain walks toward a far point, picking a new one on arrival; the
    // others keep within 4 blocks of the captain. Returns the walk speed, or nil when not patrolling.
    func patrolStep(_ g: Game) -> Float? {
        guard patrolling, !raider else { return nil }
        if captain {
            if let p = patrolGoal, simd_length(V2(p.x - pos.x, p.z - pos.z)) > 4 {
                face(p)
            } else {
                let a = Float.random(in: 0..<(2 * .pi))
                patrolGoal = pos + V3(cosf(a) * 80, 0, sinf(a) * 80)
                face(patrolGoal ?? pos)
            }
            return spec.speed * 0.6
        }
        guard let l = patrolLeader, l.health > 0 else { patrolling = false; return nil }
        if simd_length(V2(l.pos.x - pos.x, l.pos.z - pos.z)) > 4 { face(l.pos); return spec.speed * 0.7 }
        wander()
        return moving ? spec.speed * 0.3 : 0
    }

    var isZombie: Bool { kind == .zombie || kind == .husk || kind == .drowned || kind == .zombieVillager }

    // Villager (for zombies and raiders) or iron golem (raiders) to attack instead of the player.
    func villagerTarget(_ g: Game) -> Mob? {
        let zombie = isZombie
        let illager = raider || kind == .vindicator || kind == .pillager || kind == .illusioner
        guard zombie || illager else { return nil }
        var best: Mob?
        var bd: Float = raider ? 32 : 16
        func consider(_ list: [Mob]) {
            for o in list where o.health > 0 && !(o.kind == .villager && o.baby) {
                let d = simd_length(o.pos - pos)
                if d < bd { bd = d; best = o }
            }
        }
        consider(g.mobs.of(.villager))
        if zombie { consider(g.mobs.of(.wanderingTrader)) }
        if illager { consider(g.mobs.of(.ironGolem)) }
        return best
    }

    // Zombie villager curing countdown; returns true when it has become a villager.
    func cureTick(_ dt: Float, _ g: Game) -> Bool {
        guard kind == .zombieVillager, cureTimer > 0 else { return false }
        cureTimer -= dt
        if Float.random(in: 0..<1) < dt * 4 { g.particles.hearts(at: pos + V3(0, 2, 0)) }
        guard cureTimer <= 0 else { return false }
        let v = Mob(.villager, at: pos)
        var d = villager ?? VillagerData()
        d.cured = true
        d.addGossip(.majorPos, 20)
        d.addGossip(.minorPos, 25)
        v.villager = d
        v.yaw = yaw
        v.persistent = true
        g.mobs.mobs.append(v)
        g.applyEffect(.nausea, amp: 0, seconds: 0.1)
        g.sfx(.villagerYes, 1, at: pos)
        health = -2000
        return true
    }
}
