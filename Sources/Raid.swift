import Foundation
import simd

// Raids (reference rules, Normal difficulty): drinking an ominous bottle gives Bad Omen; walking into
// a village with it turns it into Raid Omen, and 30 s later the raid starts. Five waves (+1 bonus wave
// when the omen level is above I) of pillagers, vindicators, ravagers, witches and evokers spawn at
// the village edge. Winning gives Hero of the Village; losing all villagers is a defeat.
// Pillager patrols roam after day 5; their captains drop ominous bottles.

final class Raid {
    var center: V3
    var level: Int                // omen level 1...5
    var wave = 0                  // waves spawned so far
    let totalWaves: Int
    var raiders: [Mob] = []
    var state = 0                 // 0 between waves (countdown), 1 wave active, 2 victory, 3 defeat
    var timer: Float = 15         // countdown before the next wave / to disappear after the end
    var waveHealth: Float = 1
    var idle: Float = 0           // seconds without progress (a raid times out after 40 min)
    init(center: V3, level: Int) {
        self.center = center
        self.level = level
        totalWaves = 5 + (level > 1 ? 1 : 0)
    }
}

enum RaidTable {
    // Raiders per wave index 1...8 on Normal (reference "spawnsPerWaveBeforeBonus").
    static let counts: [(MobKind, [Int])] = [
        (.vindicator, [0, 0, 2, 0, 1, 4, 2, 5]),
        (.evoker, [0, 0, 0, 0, 0, 1, 1, 2]),
        (.pillager, [0, 4, 3, 3, 4, 4, 4, 2]),
        (.witch, [0, 0, 0, 0, 3, 0, 0, 1]),
        (.ravager, [0, 0, 0, 1, 0, 1, 0, 2]),
    ]
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
        // Bad Omen + village -> Raid Omen (30 s) -> raid.
        if raid == nil, let b = effects[.badOmen], survival, dim.dim == .overworld, nearVillage(player.pos) != nil {
            effects.remove(.badOmen)
            applyEffect(.raidOmen, amp: b.amp, seconds: 30)
            raidOmenAt = player.pos
        }
        if raid == nil, let ro = effects[.raidOmen], ro.time <= 1.1 {
            effects.remove(.raidOmen)
            let c = nearVillage(raidOmenAt ?? player.pos) ?? player.pos
            raid = Raid(center: c, level: ro.amp + 1)
            sfx(.raidHorn, 1.5, at: c)
            onToast?("A raid has begun")
        }
        guard let r = raid else { return }
        r.raiders.removeAll { $0.health <= 0 }
        r.idle += dt
        let villagersLeft = mobs.mobs.contains { $0.kind == .villager && simd_length($0.pos - r.center) < 64 }
        switch r.state {
        case 0:
            if !villagersLeft { r.state = 3; r.timer = 30; onToast?("Raid - Defeat"); return }
            if simd_length(player.pos - r.center) < 96 { r.timer -= dt }
            if r.timer <= 0 { spawnWave(r) }
        case 1:
            if !villagersLeft { r.state = 3; r.timer = 30; onToast?("Raid - Defeat"); return }
            // Stragglers far away are pulled back toward the village.
            for m in r.raiders where simd_length(m.pos - r.center) > 48 { m.face(r.center); m.moving = true }
            if r.raiders.isEmpty {
                r.idle = 0
                if r.wave >= r.totalWaves {
                    r.state = 2
                    r.timer = 30
                    onToast?("Raid - Victory")
                    applyEffect(.heroOfTheVillage, amp: r.level - 1, seconds: 2400)
                    achieve("raid_win")
                    sfx(.levelUp, 1)
                    for v in mobs.mobs where v.kind == .villager && simd_length(v.pos - r.center) < 64 { particles.hearts(at: v.pos + V3(0, 2.2, 0)) }
                } else {
                    r.state = 0
                    r.timer = 15
                }
            }
            if r.idle > 2400 { r.state = 3; r.timer = 5 }
        default:
            r.timer -= dt
            if r.timer <= 0 { raid = nil }
        }
    }

    private func spawnWave(_ r: Raid) {
        r.wave += 1
        r.state = 1
        let bonus = r.wave > 5
        let idx = bonus ? 5 : r.wave
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
        for (kind, table) in RaidTable.counts {
            var n = table[min(idx, table.count - 1)]
            // Small random extra (Normal: up to one more pillager/vindicator; witches in later waves).
            if (kind == .pillager || kind == .vindicator) && n > 0 { n += Int.random(in: 0...1) }
            if kind == .witch && r.wave > 2 && r.wave != 4 && Bool.random() { n += 1 }
            for _ in 0..<n {
                let m = Mob(kind, at: at + V3(Float.random(in: -2...2), 0, Float.random(in: -2...2)))
                m.raider = true
                m.persistent = true
                if kind == .vindicator || kind == .pillager { m.aggro = true }
                spawned.append(m)
            }
        }
        // Ravagers get riders on later waves (pillager on wave 3+, vindicator/evoker on 5+).
        if let first = spawned.first(where: { $0.kind == .ravager }) {
            let riderKind: MobKind = r.wave >= 5 ? (r.wave >= 7 ? .evoker : .vindicator) : .pillager
            if r.wave >= 3 {
                let rider = Mob(riderKind, at: first.pos + V3(0, 2.2, 0))
                rider.raider = true; rider.persistent = true
                rider.mount = first
                spawned.append(rider)
            }
        }
        // The wave's captain carries the banner.
        spawned.first { $0.kind == .pillager || $0.kind == .vindicator }?.captain = true
        mobs.mobs += spawned
        r.raiders = spawned
        r.waveHealth = spawned.reduce(Float(0)) { $0 + Float($1.health) }
        sfx(.raidHorn, 1.5, at: at)
    }

    // MARK: Patrols

    // Every 10-11 minutes after day 5, a 20% chance of a pillager patrol 24-48 blocks away.
    func patrolTick(_ dt: Float) {
        guard survival, dim.dim == .overworld, time / DAY_LENGTH >= 5 else { return }
        patrolTimer -= dt
        guard patrolTimer <= 0 else { return }
        patrolTimer = Float.random(in: 600...660)
        guard Float.random(in: 0..<1) < 0.2, daylight > 0.5 || Bool.random() else { return }
        let a = Float.random(in: 0..<(2 * .pi)), d = Float.random(in: 24...48)
        let x = Int(floor(player.pos.x + cosf(a) * d)), z = Int(floor(player.pos.z + sinf(a) * d))
        guard world.isLoaded(x, z) else { return }
        let biome = world.gen.column(x, z).biome
        if biome == .mushroomFields || biome.isOcean || nearVillage(V3(Float(x), player.pos.y, Float(z))) != nil { return }
        let y = world.topY(x, z)
        if Blocks.isLiquid(world.block(x, y, z)) { return }
        let n = Int.random(in: 1...5)
        for i in 0..<n {
            let m = Mob(.pillager, at: V3(Float(x) + 0.5 + Float(i % 3), Float(y + 1), Float(z) + 0.5 + Float(i / 3)))
            if i == 0 { m.captain = true }
            m.persistent = false
            mobs.mobs.append(m)
        }
    }

    // Killed captains (outside raids) drop an ominous bottle (level I-V).
    func captainDied(_ m: Mob) {
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
        sfx(.mobZombie, 1, at: v.pos)
    }

    // Zombie villager with Weakness + golden apple: cures in 3-5 minutes into a discounted villager.
    func startCure(_ m: Mob) -> Bool {
        guard m.kind == .zombieVillager, Items.key(held.item) == "golden_apple", m.effects?.has(.weakness) ?? false, m.cureTimer <= 0 else { return false }
        m.cureTimer = Float.random(in: 180...300)
        m.persistent = true
        consumeHeld()
        sfx(.mobZombie, 0.8, at: m.pos)
        return true
    }
}

extension Mob {
    var isZombie: Bool { kind == .zombie || kind == .husk || kind == .drowned || kind == .zombieVillager }

    // Villager (for zombies and raiders) or iron golem (raiders) to attack instead of the player.
    func villagerTarget(_ g: Game) -> Mob? {
        let zombie = isZombie
        let illager = raider || kind == .vindicator || kind == .pillager
        guard zombie || illager else { return nil }
        let range: Float = raider ? 32 : 16
        return g.mobs.mobs.filter { o in
            o.health > 0 && ((o.kind == .villager && !o.baby) || (illager && o.kind == .ironGolem)) && simd_length(o.pos - pos) < range
        }.min { simd_length($0.pos - pos) < simd_length($1.pos - pos) }
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
        v.villager = d
        v.yaw = yaw
        v.persistent = true
        g.mobs.mobs.append(v)
        g.applyEffect(.nausea, amp: 0, seconds: 0.1)
        g.sfx(.mobVillager, 1, at: pos)
        health = -2000
        return true
    }
}
