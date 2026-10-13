import Foundation
import simd

// Hired companions (backlog O2), `questcheck --companions-only`: hire a townsperson, they fire on a monster in sight,
// wear handed-over plate, and go home when let go.
enum CompanionTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let mobs0 = g.mobs.mobs, money0 = g.money, surv0 = g.survival, held0 = g.inventory.held, shift0 = g.player.sneaking
        defer { g.mobs.mobs = mobs0; g.money = money0; g.survival = surv0; g.inventory.held = held0; g.player.sneaking = shift0 }
        g.survival = true
        g.money = 10_000
        let p = g.player.pos
        _ = w.loadSync(center: p, radius: 2)
        let v = Mob(.villager, at: p + V3(2, 0, 0))
        Townsfolk.setup(v, game: nil)
        g.mobs.mobs = [v]
        g.inventory.held = .empty
        g.player.sneaking = true
        let hired = g.companionUse(v)
        let c = g.companions.first
        check(hired && c != nil && g.money == 10_000 - Companions.townsfolkFee && c?.customName == v.villager?.person && !g.mobs.mobs.contains { $0 === v },
              "companions: sneak-use hires \(v.villager?.person ?? "?") for \(Money.format(Companions.townsfolkFee)) as a gunhand (\(g.companions.count) following)")
        guard let m = c else { return }
        // A zombie in sight 8 blocks off: the companion turns on it and fires.
        g.player.sneaking = false
        m.pos = p + V3(1.5, 0, 0)
        let z = Mob(.zombie, at: m.pos + V3(0, 0, -8))
        g.mobs.mobs.append(z)
        let mag0 = m.soldierBrain.mag
        for _ in 0..<60 { _ = m.companionAI(0.05, g) }
        check(m.companionFoe === z && m.soldierBrain.mag < mag0, "companions: a zombie 8 blocks off is taken on (foe \(m.companionFoe === z), \(mag0 - m.soldierBrain.mag) rounds fired)")
        // Far behind: they arrive by the player.
        m.pos = p + V3(80, 0, 0)
        _ = m.companionAI(0.05, g)
        check(simd_length(m.pos - p) < 4, "companions: left 80 blocks behind, the companion arrives by the player")
        // Plate handed over is worn; sneak-use lets them go.
        g.inventory.held = ItemStack(Items.id("hannibal_vest"), 1)
        _ = g.companionUse(m)
        let plated = m.troopClass == .hannibal && m.troopSeg.y > 0 && g.inventory.held.isEmpty
        g.player.sneaking = true
        _ = g.companionUse(m)
        check(plated && g.companions.isEmpty, "companions: a Hannibal vest handed over is worn (\(plated)); sneak-use lets them go")
    }
}
