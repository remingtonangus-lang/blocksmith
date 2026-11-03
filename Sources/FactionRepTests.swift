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
        // P510: a wary Capital or Greywall soldier out in the open leaves an empty-handed man be; a gun in his hand, a
        // hurt comrade or a hunting faction and he is fought on sight.
        do {
            let peace0 = Soldier.unarmedPeace, held0 = g.inventory.held, surv0 = g.survival, standing0 = FactionRep.rep
            Soldier.unarmedPeace = true; g.survival = true
            defer { Soldier.unarmedPeace = peace0; g.inventory.held = held0; g.survival = surv0; FactionRep.rep = standing0 }
            FactionRep.decode("")
            g.inventory.held = .empty
            let cap = Mob(.soldierTrooper, at: p + V3(9, 0, 0)), grey = Mob(.soldierTrooper, at: p + V3(9, 0, 3)); grey.faction = Faction.greywall.rawValue
            let ash = Mob(.soldierTrooper, at: p + V3(9, 0, -3)); ash.faction = Faction.ashguard.rawValue
            let unarmed = Soldier.holdsForUnarmed(g, cap) && Soldier.holdsForUnarmed(g, grey) && !Soldier.holdsForUnarmed(g, ash)
            g.inventory.held = ItemStack(Items.id(Guns.all[Guns.rifle].key), 1)
            let armed = !Soldier.holdsForUnarmed(g, cap) && !Soldier.holdsForUnarmed(g, grey)
            g.inventory.held = .empty
            cap.playerHurtAt = g.clock
            let hurt = !Soldier.holdsForUnarmed(g, cap)
            cap.playerHurtAt = -1e9
            FactionRep.rep[Faction.steelhold.rawValue] = FactionRep.huntedAt
            let hunted = !Soldier.holdsForUnarmed(g, cap)
            check(unarmed && armed && hurt && hunted,
                  "P510: a Capital and a Greywall soldier leave him be with empty hands (\(unarmed), the Ashguard don't); with a gun in hand (\(armed)), once he's hurt one (\(hurt)) or while hunted (\(hunted)) they fight")
        }
        // Saved and read back.
        let saved = FactionRep.encode()
        FactionRep.decode(saved)
        check(Int(FactionRep.of(.greywall)) == Int(grey.rounded()) && Int(FactionRep.of(.steelhold)) == Int(cap.rounded()), "factionrep: standings kept through a save (\(saved))")
    }
}
