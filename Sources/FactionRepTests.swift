import Foundation
import simd

// Faction reputation (backlog O3), `questcheck --factionrep-only`.
enum FactionRepTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let rep0 = FactionRep.rep, clock0 = g.clock
        defer { FactionRep.rep = rep0; g.clock = clock0 }
        FactionRep.decode("")
        let p = g.player.pos
        // Killing Greywall soldiers costs Greywall standing and earns it with the Capital.
        for _ in 0..<20 {
            let m = Mob(.soldierTrooper, at: p + V3(5, 0, 0)); m.faction = Faction.greywall.rawValue
            m.killedByPlayer = true
            g.repSoldierKilled(m)
        }
        let grey = FactionRep.of(.greywall), cap = FactionRep.of(.steelhold)
        check(grey <= FactionRep.huntedAt && cap >= FactionRep.allyAt,
              "factionrep: twenty Greywall soldiers killed leave Greywall at \(Int(grey)) (hunted) and the Capital at \(Int(cap)) (an ally)")
        // An allied Capital soldier holds fire; one the player just hurt does not.
        let c = Mob(.soldierTrooper, at: p + V3(4, 0, 0))
        let holds = g.repAllied(c)
        c.playerHurtAt = g.clock
        let provoked = !g.repAllied(c)
        let gw = Mob(.soldierTrooper, at: p + V3(4, 0, 0)); gw.faction = Faction.greywall.rawValue
        check(holds && provoked && !g.repAllied(gw), "factionrep: an allied Capital soldier holds fire (\(holds)) until hurt (\(provoked)); Greywall's don't")
        // Saved and read back.
        let saved = FactionRep.encode()
        FactionRep.decode(saved)
        check(Int(FactionRep.of(.greywall)) == Int(grey.rounded()) && Int(FactionRep.of(.steelhold)) == Int(cap.rounded()), "factionrep: standings kept through a save (\(saved))")
    }
}
