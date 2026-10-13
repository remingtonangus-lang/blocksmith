import Foundation
import simd

// Faction raids (backlog O5), `questcheck --raids-only`: an angered faction raids the player's home with dropships,
// a wall turret the player placed fires at its soldiers, and a raid with no raiders left is beaten off.
enum FactionRaidsTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let rep0 = FactionRep.rep, clock0 = g.clock, mobs0 = g.mobs.mobs, money0 = g.money, surv0 = g.survival, spawn0 = g.spawnPoint
        let ships0 = Set(g.world.ships.list.map { ObjectIdentifier($0) })
        var placed: IVec3?
        defer {
            FactionRep.rep = rep0; g.clock = clock0; g.mobs.mobs = mobs0; g.money = money0; g.survival = surv0; g.spawnPoint = spawn0
            for s in g.world.ships.list where !ships0.contains(ObjectIdentifier(s)) { g.world.ships.remove(s) }
            if let p = placed { g.world.setBlock(p.x, p.y, p.z, AIR) }
            FactionRaids.active = nil; FactionRaids.guns = [:]; g.arms.slugs.removeAll()
        }
        g.survival = true
        FactionRep.decode("")
        check(FactionRaids.angered() == nil, "raids: nobody raids a player every faction is only wary of")
        FactionRep.rep[Faction.greywall.rawValue] = -70
        let home = g.player.pos
        g.spawnPoint = home
        let place = g.raidPlaces().first
        let n = g.startRaid(FactionRaids.angered() ?? .greywall, at: home, place: place?.1 ?? "?", sync: true)
        let drops = g.world.ships.list.filter { !ships0.contains(ObjectIdentifier($0)) && $0.role == "dropship" }.count
        check(FactionRaids.angered() == .greywall && place?.1 == "your home" && n == 2 && drops == 2 && FactionRaids.active?.faction == .greywall,
              "raids: an angered Greywall raids \(place?.1 ?? "-") with \(n) dropships (\(drops) in the air)")

        // A wall turret placed by the home fires on a Greywall raider in front of it.
        let tx = Int(floor(home.x)) + 2, tz = Int(floor(home.z)), ty = g.world.topY(tx, tz) + 1
        g.world.setBlock(tx, ty, tz, GreywallAlarmState.turretIds.0 + 3)          // facing +x
        placed = IVec3(tx, ty, tz)
        let raider = Mob(.soldierTrooper, at: V3(Float(tx) + 9.5, Float(ty), Float(tz) + 0.5)); raider.faction = Faction.greywall.rawValue
        g.mobs.mobs = [raider]
        if var r = FactionRaids.active { r.turrets = g.raidTurrets(around: home); FactionRaids.active = r }
        let found = FactionRaids.active?.turrets.contains(IVec3(tx, ty, tz)) ?? false
        g.arms.slugs.removeAll()
        var shots = 0
        for _ in 0..<40 { g.playerTurretsTick(0.05); shots = max(shots, g.arms.slugs.filter { $0.fromPlayer }.count) }
        check(found && shots > 0, "raids: the placed wall turret is found (\(found)) and fires on the raider (\(shots) rounds in flight)")

        // No raiders left after a minute: beaten off, with salvage.
        raider.health = 0
        g.mobs.mobs = []
        let m0 = g.money
        g.clock += 61
        g.factionRaidsTick()
        check(FactionRaids.active == nil && g.money == m0 + FactionRaids.salvage, "raids: with no raiders left the raid is beaten off (+\(Money.format(g.money - m0)))")
    }
}
