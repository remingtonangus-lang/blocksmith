import Foundation
import simd

// The Ashguard: the army holding the Ash Vault at the bottom of the Deep (task 22). Sites (AshSites.swift), units
// (AshUnits.swift, AshModels.swift) and the war's state: the boss bars, victory over the Chancellor (AshFinal.swift; the
// Ashguard stands down, the ending, a lift home in the command bunker), advancements.
enum AshWar {
    static let liftAt = IVec3(0, DeepGen.floorBase + 1, 4)       // the lift home, in the command bunker after victory

    static let epilogue: [String] = [
        "VICTORY", "", "", "The Ash Chancellor is dead.", "His banners burn in the vault.", "The Ashguard lays down its arms.", "",
        "You broke through the bottom of the world,", "dug through rock that glowed with heat,",
        "crossed the fire of the fortresses of Hell,", "broke their lines, their armour and their last army,",
        "and went down into the bunker where the war was made.", "",
        "The war below the world is over.", "Their tanks are cold. Their guns are silent.", "The red lamps burn for no one now.", "",
        "A lift in the command bunker", "will carry you back to the surface.", "", "", "THE END", "", "", "",
        "Made for Remington", "", "Thanks for playing.", "", "", "",
    ]
    static var epilogueLength: Float { Float(epilogue.count) * 1.4 + 12 }
}

extension Game {
    // Once a second while in the Deep: entering the vault, the Marshal, the lift home.
    func ashTick() {
        guard dim.dim == .deep else { return }
        if DeepGen.inVault(player.pos.y) && !advancements.contains("adventure/ash_vault") {
            achieve("ash_vault")
            let d = Int(simd_length(V2(player.pos.x, player.pos.z)))
            onToast?(d > 200 ? "The Ashguard holds this vault: their citadel is \(d) blocks away (compasses and roads lead there)"
                              : "The Ashguard citadel")
        }
        if ashVictory {
            let l = AshWar.liftAt
            // The plate appears (or comes back) whenever the bunker is loaded.
            let lift = Blocks.id("ash_lift")
            if world.isLoaded(l.x, l.z) && world.block(l.x, l.y, l.z) != lift {
                world.setBlock(l.x, l.y, l.z, lift)
                world.setBlock(l.x, l.y + 1, l.z, AIR); world.setBlock(l.x, l.y + 2, l.z, AIR)
            }
            let f = player.pos
            if Int(floor(f.x)) == l.x && Int(floor(f.z)) == l.z && abs(f.y - Float(l.y + 1)) < 0.6 { liftHome() }
        }
    }

    // The boss bar of the Marshal, the Chancellor or the Behemoth while one is near.
    func ashBossBar() -> (String, Float)? {
        guard dim.dim == .deep else { return nil }
        guard let m = mobs.mobs.first(where: { ($0.kind == .ashMarshal || $0.kind == .ashChancellor || $0.kind == .ashBehemoth)
            && $0.health > 0 && simd_length($0.pos - player.pos) < 72 }) else { return nil }
        return (m.spec.name, Float(m.health) / Float(m.spec.health))
    }

    // Called from mobDied.
    func ashUnitDied(_ m: Mob) {
        if m.kind == .ashTank && m.killedByPlayer { achieve("ash_tank") }
        // The first officer you kill carries a Keeper's Journal (the Sunderite chain and where the keeps stand).
        if m.kind == .soldierOfficer && m.killedByPlayer && !ashOfficerHint {
            ashOfficerHint = true
            drops.spawn(ItemStack(Items.id("keepers_journal"), 1), at: m.pos + V3(0, 0.5, 0))
            onToast?("The officer carried a Keeper's Journal")
        }
        if m.faction == Faction.ashguard.rawValue { ashAlarmKill(m) }
        if m.kind.ashVehicle {
            // Vehicles brew up: a burst (fuel trucks a big one, with fire) and smoke; the blocks around are spared.
            let fuel = m.kind == .ashTruck && m.variant == 1
            let at = m.pos + V3(0, m.height * 0.5, 0)
            let power: Float = m.kind == .ashBehemoth ? 3.0 : (fuel ? 3.2 : (m.kind == .ashTank ? 2.4 : 1.8))
            Explosion.explode(at: at, power: power, game: self, fire: fuel, except: m, breakBlocks: false)
            for _ in 0..<10 { particles.smoke(at: at + V3(Rand.float(in: -1.2...1.2), Rand.float(in: 0...1.5), Rand.float(in: -1.2...1.2))) }
            ashWreck(m)
        }
        // The Marshal's fall starts the last battle (AshFinal.swift); the Chancellor's is the victory.
        if m.kind == .ashMarshal { startLastBattle(); return }
        guard m.kind == .ashChancellor, !ashVictory else { return }
        ashVictory = true
        ashStage = 3
        lastWar.wave.removeAll()
        achieve("ash_victory")
        onToast?("Victory: the Ash Chancellor is dead and the war below the world is over")
        ashStrikes.removeAll()
        for u in mobs.mobs where u.faction == Faction.ashguard.rawValue { u.aggro = false; u.brain?.lastSeen = nil; u.lockTime = 0 }
        // The army stands down (AshUnits checks ashVictory); the lift home opens in the command bunker.
        ashTick()
        creditsAsh = true
        credits = 0
    }

    // The lift: back to the bed or world spawn, like leaving the Hollow.
    func liftHome() {
        deepReturn = V3(Float(AshWar.liftAt.x) + 0.5, Float(AshWar.liftAt.y + 1), Float(AshWar.liftAt.z) + 2.5)
        gateCooldown = DeepGates.cooldown
        let to = spawnPoint
        changeDimension(to: .overworld, at: to)
        player.pos = to
        player.vel = .zero
        player.airPeak = to.y
        onToast?("The lift carries you up to the surface")
    }
}
