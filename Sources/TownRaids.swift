import Foundation
import simd

// Night raids on towns (the gap pass, ET8: "town defence events (raids at night) where townsfolk fight beside you").
// While you're in a town at night (survival, not Peaceful, not wanted there), now and then raiders ride on it: a short
// raid (two waves of the omen raid's marauders and crossbowmen, level I, no omen needed) aimed at the town's bell.
// The armed townsfolk (deputies, the sheriff, the blacksmith's hammer, the farmer's pitchfork...) fight them as they
// fight any monster in town (VillageLife.villageThreats); the rest run for cover. Win and the town thanks you: honour
// (+5, from the "defence" allowance) and a purse from the town ($5 a wave). A town is raided at most once every three
// days (TownLaw.Saved.raidDay); a raid already running anywhere blocks another.
enum TownRaids {
    static var chancePerSecond: Float = 1.0 / 3600     // P231: about once in an hour of night spent in a town
    static let cooldownDays = 7
    static let waves = 1                              // P215: one wave an event (was 2)
    static var started = 0, wonCount = 0

    static func night(_ f: Double) -> Bool { f > 0.55 && f < 0.92 }

    // TownLaw.tick, once a second.
    static func tick(_ g: Game) {
        guard g.survival, g.difficulty > 0, g.dim.dim == .overworld, g.raid == nil, !Reckoning.won, let town = TownLaw.inTown,   // (P98: peace)
              night(g.dayFraction), Honour.bounty(town) == 0, !Honour.isOutlaw else { return }
        let day = Int(g.time / DAY_LENGTH)
        if let d = TownLaw.state.raidDay?[town], day - d < cooldownDays { return }
        guard Rand.float(in: 0..<1) < chancePerSecond * Nation.raidScale(town), g.clock - FactionRaids.lastAssault > FactionRaids.quiet else { return }   // C3: your towns are raided more
        FactionRaids.lastAssault = g.clock                // (P215: no other assault for 25 minutes)
        start(g, town: town)
    }

    @discardableResult
    static func start(_ g: Game, town: String) -> Bool {
        guard g.raid == nil, let c = g.nearVillage(g.player.pos) else { return false }
        let r = Raid(center: c, level: 1, difficulty: max(1, g.difficulty), waves: waves)
        r.night = true
        r.timer = 20                                        // the horn, then twenty seconds to get ready
        g.raid = r
        var days = TownLaw.state.raidDay ?? [:]
        days[town] = Int(g.time / DAY_LENGTH)
        TownLaw.state.raidDay = days
        g.sfx(.raidHorn, 1.5, at: c)
        g.onToast?("Raiders are riding on \(town)! Stand with the townsfolk")
        started += 1
        return true
    }

    // Raid.swift, on a night raid's victory.
    // Only for a player who stood with the town: near it at the end and killed at least one raider.
    static func won(_ g: Game, _ r: Raid) {
        let stood = simd_length(g.player.pos - r.center) < 96 && r.playerKills > 0
        Director.raidResults[Townsfolk.town(g, at: r.center)] = stood             // P266: a Director raid on this town
        guard stood else {
            g.onToast?("The raiders are beaten off")
            return
        }
        let town = Townsfolk.town(g, at: r.center)
        let purse = 500 * r.totalWaves
        g.money += purse
        Honour.earn(g, 5, source: "defence", "you defended \(town)")
        g.onToast?("\(town) thanks you: \(Money.format(purse)) from the town purse")
        Nation.raidWon(town)
        Contracts.raidWon(g, town)                          // C11
        wonCount += 1
    }
}
