import Foundation
import simd

// P471 part 2 (Oct 26 19:39-19:54) checks, `questcheck --troopfight`: a Capital gun's crewman stood at its handles, back
// turned and no gun in hand, whatever the player did close by; a soldier watched his comrade killed beside him and
// stood on. Now the crewman leaves his post to fight a player close by and goes back once he has lost him, and a kill
// turns the dead man's comrades.
enum TroopFightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: 90, dz: -90, r: 20)
        let keep = g.mobs.mobs
        defer { a.restore(); g.mobs.mobs = keep; g.drops.items.removeAll() }
        let fy = Float(a.py + 1)
        func at(_ dx: Float, _ dz: Float) -> V3 { V3(Float(a.fx) + 0.5 + dx, fy, Float(a.fz) + 0.5 + dz) }
        g.survival = true; g.player.flying = false; g.paused = false; g.menu = nil
        g.health = 20; g.alive = true
        func hold() { g.health = 20; g.alive = true }

        // 1. A gun with its crewman called to it, the player far off (out of the arena's reach: behind a wall of air).
        g.mobs.mobs = []
        guard let gun = Mob.structureMob("deck_gun", at: at(0, 6)), let crew = Mob.structureMob("soldier_trooper", at: at(-3, 12)) else {
            check(false, "troopfight: makes a gun and a trooper"); return
        }
        gun.yaw = .pi              // (facing +z: its breech floor is toward -z, the arena's middle; behind him is the floor too)
        g.mobs.mobs = [gun, crew]
        g.player.pos = at(0, 0) + V3(0, 60, 0)          // (far above, out of anyone's sight range)
        g.player.flying = true
        for _ in 0..<(8 * 72) { gun.claimGunner(g); g.tick(1.0 / 72); hold() }
        let posted = crew.soldierBrain.orderStation == .gunner
        let stance = crew.soldierBrain.station
        print("troopfight: crewman posted \(posted), stance \(stance), at \(String(format: "%.1f %.1f", crew.pos.x - at(0, 0).x, crew.pos.z - at(0, 0).z))")
        // 2. The player walks up behind him, 8 blocks off.
        g.player.flying = false
        let behind = crew.pos + V3(sinf(crew.yaw), 0, cosf(crew.yaw)) * 8
        g.player.pos = V3(behind.x, fy, behind.z)
        var damage = 0
        Game.onDamage = { amt, _ in damage += amt }
        var left = false, drew = false
        for i in 0..<(8 * 72) {
            g.tick(1.0 / 72); hold()
            if i % 72 == 0 {
                let b = crew.soldierBrain, d = g.player.pos - crew.pos
                var off = atan2f(-d.x, -d.z) - crew.yaw
                while off > .pi { off -= 2 * .pi }
                while off < -.pi { off += 2 * .pi }
                print(String(format: "troopfight:   %ds: aggro %@ sees %@ offPost %.1f station %d mag %d reload %.1f react %.2f aimT %.2f dist %.1f facing %.0f deg off",
                             i / 72, crew.aggro ? "y" : "n", b.sees ? "y" : "n", b.offPost, b.station.rawValue, b.mag, b.reload, b.react, b.aimTime, simd_length(d), abs(off) * 57.3))
            }
            if crew.soldierBrain.offPost > 0 { left = true }
            if crew.soldierBrain.station == StationPose.none && crew.aggro { drew = true }
        }
        Game.onDamage = nil
        check(posted && left && drew && crew.aggro && damage > 0,
              "troopfight: a gun's crewman (posted \(posted)) with him 8 blocks behind leaves his post (\(left)), draws (\(drew)) and fires on him (\(damage) damage in 8 s)")
        // 3. He goes back to his gun once the player is gone for good.
        g.player.pos = at(0, 0) + V3(0, 60, 0); g.player.flying = true
        for _ in 0..<(80 * 72) { g.tick(1.0 / 72); hold() }
        let post = crew.soldierBrain.gunPost ?? crew.pos
        let back = simd_length(V2(crew.pos.x - post.x, crew.pos.z - post.z))
        check(crew.soldierBrain.orderStation == .gunner && back < 1.5 && crew.soldierBrain.station == .gunner,
              "troopfight: with him gone the crewman is back at the gun (\(String(format: "%.1f", back)) blocks from his post, stance \(crew.soldierBrain.station))")

        // 4. Two calm troopers side by side; he kills one from behind them: the other turns.
        g.mobs.mobs = []
        guard let s1 = Mob.structureMob("soldier_recruit", at: at(-1, 0)), let s2 = Mob.structureMob("soldier_recruit", at: at(1, 0)) else { return }
        s1.yaw = 0; s2.yaw = 0                          // (facing -z; he stands at +z)
        g.mobs.mobs = [s1, s2]
        g.player.flying = false
        g.player.pos = at(0, 17)          // (past 16 from them both: unseen behind their backs for a moment)
        g.player.sneaking = true
        for _ in 0..<20 { g.tick(1.0 / 72); hold() }
        let calm = !s2.aggro
        s1.killedByPlayer = true; s1.playerHurtAt = g.clock
        s1.health = 0
        g.mobDied(s1)
        var turned = false, fired = 0
        Game.onDamage = { amt, _ in fired += amt }
        for _ in 0..<(5 * 72) { g.tick(1.0 / 72); hold(); if s2.aggro { turned = true } }
        Game.onDamage = nil
        g.player.sneaking = false
        check(calm && turned && fired > 0,
              "troopfight: his comrade killed beside him (unaware before: \(calm)), a trooper turns on him (\(turned)) and fires (\(fired) damage in 5 s)")
        g.mobs.mobs = []
    }
}
